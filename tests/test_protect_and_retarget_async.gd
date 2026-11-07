extends RefCounted

const CorvetteScene = preload("res://scenes/ship/ship_corvette.tscn")
const Railgun = preload("res://resources/weapons/railgun.tres")

const ENEMY_GROUP := &"test_protect_enemies"
const ALLY_GROUP := &"test_protect_allies"

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	await _check_protect_holds_near_protectee(tree, failures)
	await _check_protect_faces_threat(tree, failures)
	await _check_attack_retargets_on_loss(tree, failures)
	await _check_protect_falls_back_when_protectee_lost(tree, failures)
	await _check_attack_retargets_when_hull_destroyed_mid_step(tree, failures)
	return failures

static func _spawn(tree: SceneTree, pos: Vector2, weapon: Weapon, group: StringName) -> Ship:
	var ship: Ship = CorvetteScene.instantiate()
	tree.root.add_child(ship)
	ship.global_position = pos
	for mount in ship.weapon_mounts:
		mount.weapon = null
	if weapon != null:
		ship.weapon_mounts[0].weapon = weapon
	ship.ally_group = group
	ship.add_to_group(group)
	ship.enemy_group = ENEMY_GROUP if group == ALLY_GROUP else ALLY_GROUP
	await tree.physics_frame
	return ship

static func _spawn_dummy(tree: SceneTree, pos: Vector2, group: StringName) -> Ship:
	var dummy := await _spawn(tree, pos, null, group)
	dummy.set_physics_process(false)
	dummy.hull.max_hp = 1.0e9
	dummy.hull.current_hp = 1.0e9
	return dummy

static func _run_for(tree: SceneTree, seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await tree.physics_frame

static func _cleanup(tree: SceneTree, nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await tree.physics_frame

static func _check_protect_holds_near_protectee(tree: SceneTree, failures: Array[String]) -> void:
	var protectee := await _spawn_dummy(tree, Vector2(500.0, 500.0), ALLY_GROUP)
	var guard := await _spawn(tree, Vector2(900.0, 500.0), Railgun, ALLY_GROUP)
	guard.execute_order(Order.protect(protectee))
	await _run_for(tree, 2.0)
	var dist := guard.global_position.distance_to(protectee.global_position)
	if dist > Ship.PROTECT_STANDOFF + 60.0 or dist < 10.0:
		failures.append("protect_holds_near_protectee: expected the guard near standoff range of the protectee, got %s px" % dist)
	await _cleanup(tree, [protectee, guard])

static func _check_protect_faces_threat(tree: SceneTree, failures: Array[String]) -> void:
	var protectee := await _spawn_dummy(tree, Vector2(500.0, 500.0), ALLY_GROUP)
	var threat := await _spawn_dummy(tree, Vector2(200.0, 500.0), ENEMY_GROUP)
	var guard := await _spawn(tree, Vector2(900.0, 500.0), Railgun, ALLY_GROUP)
	guard.execute_order(Order.protect(protectee))
	# A corvette's turn/accel means crossing to the far side of a protectee it starts
	# opposite from takes closer to 3s than 2s; widened from an initial 2.0s to avoid
	# a false failure while the guard is still correctly, but only partway, underway.
	await _run_for(tree, 3.0)
	var toward_threat := (threat.global_position - protectee.global_position).normalized()
	var toward_guard := (guard.global_position - protectee.global_position).normalized()
	if toward_guard.dot(toward_threat) < 0.3:
		failures.append("protect_faces_threat: expected the guard to sit on the threat's side of the protectee, dot %s" % toward_guard.dot(toward_threat))
	await _cleanup(tree, [protectee, threat, guard])

static func _check_attack_retargets_on_loss(tree: SceneTree, failures: Array[String]) -> void:
	var target := await _spawn_dummy(tree, Vector2(700.0, 500.0), ENEMY_GROUP)
	var backup := await _spawn_dummy(tree, Vector2(750.0, 540.0), ENEMY_GROUP)
	var attacker := await _spawn(tree, Vector2(500.0, 500.0), Railgun, ALLY_GROUP)
	attacker.execute_order(Order.attack_target(target))
	await _run_for(tree, 0.1)
	target.queue_free()
	await _run_for(tree, 0.5)
	if attacker.current_order.type != Order.Type.ATTACK_TARGET or attacker.current_order.target_ship != backup:
		failures.append("attack_retargets_on_loss: expected the attacker to retarget the remaining enemy, got %s / %s" % [attacker.current_order.type, attacker.current_order.target_ship])
	await _cleanup(tree, [backup, attacker])

static func _check_protect_falls_back_when_protectee_lost(tree: SceneTree, failures: Array[String]) -> void:
	var protectee := await _spawn_dummy(tree, Vector2(500.0, 500.0), ALLY_GROUP)
	var threat := await _spawn_dummy(tree, Vector2(700.0, 500.0), ENEMY_GROUP)
	var guard := await _spawn(tree, Vector2(300.0, 500.0), Railgun, ALLY_GROUP)
	guard.execute_order(Order.protect(protectee))
	await _run_for(tree, 0.1)
	protectee.queue_free()
	await _run_for(tree, 0.5)
	if guard.current_order.type != Order.Type.ATTACK_TARGET or guard.current_order.target_ship != threat:
		failures.append("protect_falls_back_when_protectee_lost: expected the guard to attack the remaining enemy, got %s / %s" % [guard.current_order.type, guard.current_order.target_ship])
	await _cleanup(tree, [threat, guard])

# Review Focus 1's exact scenario: the target dies from hull damage (queue_free called
# from _on_hull_destroyed, mid-signal, not from the test directly) the same tick its
# order is read. Must not SCRIPT ERROR on the stale reference, and must retarget cleanly.
static func _check_attack_retargets_when_hull_destroyed_mid_step(tree: SceneTree, failures: Array[String]) -> void:
	var target := await _spawn_dummy(tree, Vector2(700.0, 500.0), ENEMY_GROUP)
	var backup := await _spawn_dummy(tree, Vector2(750.0, 540.0), ENEMY_GROUP)
	var attacker := await _spawn(tree, Vector2(500.0, 500.0), Railgun, ALLY_GROUP)
	attacker.execute_order(Order.attack_target(target))
	await _run_for(tree, 0.1)
	target.hull.apply_damage(target.hull.max_hp)
	await _run_for(tree, 0.5)
	if attacker.current_order.type != Order.Type.ATTACK_TARGET or attacker.current_order.target_ship != backup:
		failures.append("attack_retargets_when_hull_destroyed_mid_step: expected the attacker to retarget the remaining enemy, got %s / %s" % [attacker.current_order.type, attacker.current_order.target_ship])
	await _cleanup(tree, [backup, attacker])
