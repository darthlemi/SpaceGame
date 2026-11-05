extends RefCounted

const CorvetteScene = preload("res://scenes/ship/ship_corvette.tscn")
const Railgun = preload("res://resources/weapons/railgun.tres")

const TEST_GROUP := &"test_scoring_targets"

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	await _check_ai_uses_score(tree, failures)
	await _check_target_freed(tree, failures)
	await _check_idle_hold(tree, failures)
	return failures

# Dummies are stationary members of TEST_GROUP; the shooter has one railgun and faces +x.
static func _spawn(tree: SceneTree, pos: Vector2, armed: bool, dummy: bool) -> Ship:
	var ship: Ship = CorvetteScene.instantiate()
	tree.root.add_child(ship)
	ship.global_position = pos
	for mount in ship.weapon_mounts:
		mount.weapon = null
	if armed:
		ship.weapon_mounts[0].weapon = Railgun
	if dummy:
		ship.set_physics_process(false)
		ship.hull.max_hp = 1.0e9
		ship.hull.current_hp = 1.0e9
		ship.add_to_group(TEST_GROUP)
	await tree.physics_frame
	return ship

static func _wait_for_attack(tree: SceneTree, ship: Ship) -> void:
	for i in 5:
		await tree.physics_frame
		if ship.current_order.type == Order.Type.ATTACK_TARGET:
			return

static func _check_ai_uses_score(tree: SceneTree, failures: Array[String]) -> void:
	var near_behind := await _spawn(tree, Vector2(-200.0, 0.0), false, true)
	var far_ahead := await _spawn(tree, Vector2(260.0, 0.0), false, true)
	var ship := await _spawn(tree, Vector2.ZERO, true, false)
	ship.enemy_group = TEST_GROUP
	ship.set_physics_process(false)
	var controller := AIController.new()
	tree.root.add_child(controller)
	controller.setup(ship, TEST_GROUP)
	await _wait_for_attack(tree, ship)
	if ship.current_order.type != Order.Type.ATTACK_TARGET:
		failures.append("ai_uses_score_not_nearest: expected ATTACK_TARGET, got %s" % ship.current_order.type)
	elif ship.current_order.target_ship != far_ahead:
		failures.append("ai_uses_score_not_nearest: expected the target dead ahead, got the one behind")
	controller.queue_free()
	ship.queue_free()
	near_behind.queue_free()
	far_ahead.queue_free()
	await tree.physics_frame

static func _check_target_freed(tree: SceneTree, failures: Array[String]) -> void:
	var a := await _spawn(tree, Vector2(200.0, 0.0), false, true)
	var b := await _spawn(tree, Vector2(400.0, 0.0), false, true)
	var ship := await _spawn(tree, Vector2.ZERO, true, false)
	ship.enemy_group = TEST_GROUP
	ship.set_physics_process(false)
	var controller := AIController.new()
	tree.root.add_child(controller)
	controller.setup(ship, TEST_GROUP)
	await _wait_for_attack(tree, ship)
	if ship.current_order.target_ship != a:
		failures.append("target_freed_mid_fight: setup expected the nearer target A first")
	a.queue_free()
	var switched := false
	for i in 3:
		await tree.physics_frame
		if ship.current_order.type == Order.Type.ATTACK_TARGET and ship.current_order.target_ship == b:
			switched = true
			break
	if not switched:
		failures.append("target_freed_mid_fight: expected the AI to attack B within 3 ticks of A being freed")
	controller.queue_free()
	ship.queue_free()
	b.queue_free()
	await tree.physics_frame

static func _check_idle_hold(tree: SceneTree, failures: Array[String]) -> void:
	var near_behind := await _spawn(tree, Vector2(-200.0, 0.0), false, true)
	var far_ahead := await _spawn(tree, Vector2(260.0, 0.0), false, true)
	var ship := await _spawn(tree, Vector2.ZERO, true, false)
	ship.enemy_group = TEST_GROUP
	var expected := CombatTactics.pick_target(ship, tree.get_nodes_in_group(TEST_GROUP), null)
	for i in 2:
		await tree.physics_frame
	if expected != far_ahead:
		failures.append("idle_hold_engages_scored_target: pick_target should favour the target ahead")
	if ship.idle_target() != expected:
		failures.append("idle_hold_engages_scored_target: idle_target %s differs from pick_target %s" % [ship.idle_target(), expected])
	ship.queue_free()
	near_behind.queue_free()
	far_ahead.queue_free()
	await tree.physics_frame
