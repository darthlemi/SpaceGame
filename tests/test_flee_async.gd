extends RefCounted

const CorvetteScene = preload("res://scenes/ship/ship_corvette.tscn")
const Railgun = preload("res://resources/weapons/railgun.tres")
const PulseLaser = preload("res://resources/weapons/pulse_laser.tres")

const ENEMY_GROUP := &"test_flee_enemies"
const ALLY_GROUP := &"test_flee_allies"

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	await _check_flee_completes(tree, failures)
	await _check_hull_hit_resets(tree, failures)
	await _check_shield_hit_keeps(tree, failures)
	await _check_pierce_resets(tree, failures)
	await _check_new_order_cancels(tree, failures)
	await _check_killed_on_last_tick(tree, failures)
	await _check_hold_position_no_chase(tree, failures)
	await _check_hold_position_fires(tree, failures)
	await _check_unarmed_safe(tree, failures)
	await _check_fled_ship_untargetable(tree, failures)
	return failures

static func _spawn(tree: SceneTree, pos: Vector2, weapon: Weapon, group: StringName = ALLY_GROUP) -> Ship:
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

# Stationary enemy with a huge hull.
static func _spawn_dummy(tree: SceneTree, pos: Vector2) -> Ship:
	var dummy := await _spawn(tree, pos, null, ENEMY_GROUP)
	dummy.set_physics_process(false)
	dummy.hull.max_hp = 1.0e9
	dummy.hull.current_hp = 1.0e9
	return dummy

static func _run_for(tree: SceneTree, seconds: float) -> void:
	var frames := int(seconds * Engine.physics_ticks_per_second)
	for i in frames:
		await tree.physics_frame

static func _cleanup(tree: SceneTree, nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await tree.physics_frame

static func _start_fleeing(tree: SceneTree, ship: Ship, seconds: float) -> void:
	ship.execute_order(Order.flee())
	await _run_for(tree, seconds)

static func _check_flee_completes(tree: SceneTree, failures: Array[String]) -> void:
	var ship := await _spawn(tree, Vector2(500.0, 500.0), Railgun)
	var emitted := [0]
	ship.jumped_out.connect(func(_s): emitted[0] += 1)
	ship.execute_order(Order.flee())
	await _run_for(tree, 6.5)
	if not ship.has_fled:
		failures.append("flee_completes_and_jumps_out: expected has_fled by 6.5 s")
	if ship.is_in_group(ALLY_GROUP):
		failures.append("flee_completes_and_jumps_out: expected the ship out of its group")
	if emitted[0] != 1:
		failures.append("flee_completes_and_jumps_out: expected jumped_out once, got %d" % emitted[0])
	await _cleanup(tree, [ship])

static func _check_hull_hit_resets(tree: SceneTree, failures: Array[String]) -> void:
	var ship := await _spawn(tree, Vector2(500.0, 500.0), Railgun)
	await _start_fleeing(tree, ship, 3.0)
	if ship.flee_progress() <= 0.3:
		failures.append("hull_hit_resets_spool: setup expected progress past 0.3, got %s" % ship.flee_progress())
	ship.shield.current_shield = 0.0
	ship.receive_weapon_damage(PulseLaser)
	if ship.flee_progress() != 0.0:
		failures.append("hull_hit_resets_spool: expected progress 0 after a hull hit, got %s" % ship.flee_progress())
	await _cleanup(tree, [ship])

static func _check_shield_hit_keeps(tree: SceneTree, failures: Array[String]) -> void:
	var ship := await _spawn(tree, Vector2(500.0, 500.0), Railgun)
	await _start_fleeing(tree, ship, 3.0)
	ship.shield.max_shield = 1000.0
	ship.shield.current_shield = 1000.0
	var before := ship.flee_progress()
	ship.receive_weapon_damage(PulseLaser)
	if ship.flee_progress() != before or before <= 0.0:
		failures.append("shield_absorbed_hit_keeps_spool: expected progress %s unchanged, got %s" % [before, ship.flee_progress()])
	await _cleanup(tree, [ship])

static func _check_pierce_resets(tree: SceneTree, failures: Array[String]) -> void:
	var ship := await _spawn(tree, Vector2(500.0, 500.0), Railgun)
	await _start_fleeing(tree, ship, 3.0)
	ship.shield.max_shield = 1000.0
	ship.shield.current_shield = 1000.0
	ship.receive_weapon_damage(Railgun)
	if ship.flee_progress() != 0.0:
		failures.append("pierce_hit_resets_spool: expected progress 0 after a piercing hit, got %s" % ship.flee_progress())
	await _cleanup(tree, [ship])

static func _check_new_order_cancels(tree: SceneTree, failures: Array[String]) -> void:
	var ship := await _spawn(tree, Vector2(500.0, 500.0), Railgun)
	var emitted := [0]
	ship.jumped_out.connect(func(_s): emitted[0] += 1)
	await _start_fleeing(tree, ship, 3.0)
	ship.execute_order(Order.move_to(Vector2(520.0, 500.0)))
	if ship.flee_progress() != 0.0:
		failures.append("new_order_cancels_flee: expected progress 0 after a new order, got %s" % ship.flee_progress())
	await _run_for(tree, 3.5)
	if ship.has_fled or emitted[0] != 0:
		failures.append("new_order_cancels_flee: expected no jump-out after cancelling")
	await _cleanup(tree, [ship])

# Review Focus 2: the killing blow lands the same frame the spool would complete.
static func _check_killed_on_last_tick(tree: SceneTree, failures: Array[String]) -> void:
	var ship := await _spawn(tree, Vector2(500.0, 500.0), Railgun)
	var emitted := [0]
	ship.jumped_out.connect(func(_s): emitted[0] += 1)
	ship.execute_order(Order.flee())
	ship._flee_spool = Ship.FLEE_SPOOL_TIME[ship.ship_type] - 0.001
	ship.shield.current_shield = 0.0
	ship.hull.apply_damage(ship.hull.max_hp)
	await _run_for(tree, 1.0)
	if emitted[0] != 0 or (is_instance_valid(ship) and ship.has_fled):
		failures.append("killed_on_last_tick_never_jumps: a destroyed ship jumped out")
	await _cleanup(tree, [ship])

static func _check_hold_position_no_chase(tree: SceneTree, failures: Array[String]) -> void:
	# 500 px apart: inside the railgun's reach by edge distance, but past its standoff.
	var enemy := await _spawn_dummy(tree, Vector2(1000.0, 500.0))
	var ship := await _spawn(tree, Vector2(500.0, 500.0), Railgun)
	ship.rotation = PI
	ship.execute_order(Order.hold_position())
	await _run_for(tree, 3.0)
	var moved := ship.global_position.distance_to(Vector2(500.0, 500.0))
	if moved >= 10.0:
		failures.append("hold_position_does_not_chase: moved %s px" % moved)
	var facing := Vector2.RIGHT.rotated(ship.rotation).dot((enemy.global_position - ship.global_position).normalized())
	if facing < 0.9:
		failures.append("hold_position_does_not_chase: expected the nose on the enemy, dot %s" % facing)
	await _cleanup(tree, [ship, enemy])

static func _check_hold_position_fires(tree: SceneTree, failures: Array[String]) -> void:
	var enemy := await _spawn_dummy(tree, Vector2(700.0, 500.0))
	enemy.shield.max_shield = 0.0
	enemy.shield.current_shield = 0.0
	var ship := await _spawn(tree, Vector2(500.0, 500.0), Railgun)
	var before := enemy.hull.current_hp
	var engine_before := enemy.engine.current_hp
	var mount_before := enemy.weapon_mounts[0].current_hp
	ship.execute_order(Order.hold_position())
	await _run_for(tree, 3.0)
	var damaged := enemy.hull.current_hp < before or enemy.engine.current_hp < engine_before or enemy.weapon_mounts[0].current_hp < mount_before
	if not damaged:
		failures.append("hold_position_fires_in_range: expected the in-range enemy to take damage")
	await _cleanup(tree, [ship, enemy])

# Review Focus 4: every mount destroyed under Hold Position, then Flee.
static func _check_unarmed_safe(tree: SceneTree, failures: Array[String]) -> void:
	var enemy := await _spawn_dummy(tree, Vector2(800.0, 500.0))
	var ship := await _spawn(tree, Vector2(500.0, 500.0), Railgun)
	ship.weapon_mounts[0].apply_damage(1000.0)
	ship.execute_order(Order.hold_position())
	await _run_for(tree, 1.0)
	ship.execute_order(Order.flee())
	await _run_for(tree, 1.0)
	if not is_instance_valid(ship):
		failures.append("unarmed_hold_position_safe: ship vanished")
	await _cleanup(tree, [ship, enemy])

# A fled ship stays in the tree (combat_scene reads its state) but must not be hit or chased.
static func _check_fled_ship_untargetable(tree: SceneTree, failures: Array[String]) -> void:
	var target := await _spawn_dummy(tree, Vector2(700.0, 500.0))
	target.shield.max_shield = 0.0
	target.shield.current_shield = 0.0
	var attacker := await _spawn(tree, Vector2(500.0, 500.0), Railgun)
	attacker.execute_order(Order.attack_target(target))
	await _run_for(tree, 0.5)
	target._jump_out()
	var hull_before := target.hull.current_hp
	var mount_before := target.weapon_mounts[0].current_hp
	var engine_before := target.engine.current_hp
	await _run_for(tree, 2.0)
	if not is_instance_valid(target):
		failures.append("fled_ship_untargetable: the fled ship was freed")
	elif target.hull.current_hp != hull_before or target.weapon_mounts[0].current_hp != mount_before or target.engine.current_hp != engine_before:
		failures.append("fled_ship_untargetable: the fled ship took damage after jumping out")
	if attacker.current_order.type == Order.Type.ATTACK_TARGET:
		failures.append("fled_ship_untargetable: the attacker still chases the fled ship")
	# The damage entry points are guarded at the root, for projectiles already in flight.
	if is_instance_valid(target):
		target.receive_weapon_damage(Railgun)
		target.receive_damage(100.0)
		if target.hull.current_hp != hull_before:
			failures.append("fled_ship_untargetable: direct damage landed on a fled ship")
	await _cleanup(tree, [attacker, target])
