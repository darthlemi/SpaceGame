extends RefCounted

const CORVETTE_SCENE := "res://scenes/ship/ship_corvette.tscn"
const TARGET_SCENE := "res://scenes/ship/ship.tscn"

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	# Crew scales with hull loss; disabled fires once at 10% hull (threshold 2 of 12).
	var ship: Ship = await _spawn(tree, 12, 12, 0)
	var original_hp: float = ship.hull.current_hp
	var disabled_count := [0]
	ship.disabled.connect(func(): disabled_count[0] += 1)
	ship.hull.apply_damage(original_hp * 0.5)
	if absf(ship.crew - 6.0) > 0.01:
		failures.append("crew after 50%% hull damage: expected ~6.0, got %f" % ship.crew)
	if ship.is_disabled():
		failures.append("ship disabled at 50% hull, expected not disabled")
	ship.hull.apply_damage(original_hp * 0.4)
	if not ship.is_disabled():
		failures.append("expected disabled at 10%% hull (crew %f)" % ship.crew)
	ship.hull.apply_damage(original_hp * 0.05)
	if disabled_count[0] != 1:
		failures.append("expected disabled emitted exactly once, got %d" % disabled_count[0])
	ship.queue_free()

	# Disabled ship fires nothing; control ship fires.
	var control: Ship = await _spawn(tree, 12, 12, 0)
	var control_target := await _spawn_target(tree, control)
	await tree.physics_frame
	await tree.physics_frame
	var control_fired := false
	for mount in control.weapon_mounts:
		if mount.cooldown_remaining > 0.0:
			control_fired = true
	if not control_fired:
		failures.append("control: non-disabled ship never fired (test would be vacuous)")
	control.free()
	control_target.free()

	var dis: Ship = await _spawn(tree, 12, 12, 0)
	dis.hull.apply_damage(dis.hull.current_hp * 0.9)
	var dis_target := await _spawn_target(tree, dis)
	await tree.physics_frame
	await tree.physics_frame
	if not dis.is_disabled():
		failures.append("fire test: ship expected to be disabled")
	for mount in dis.weapon_mounts:
		if mount.cooldown_remaining != 0.0:
			failures.append("disabled ship fired a weapon (cooldown %f)" % mount.cooldown_remaining)
	dis.queue_free()
	dis_target.free()

	# Crew floor holds under heavy damage.
	var floored: Ship = await _spawn(tree, 12, 12, 1)
	floored.hull.apply_damage(floored.hull.current_hp * 0.95)
	if floored.crew < 1.0:
		failures.append("crew_floor 1 violated: crew %f" % floored.crew)
	if floored.crew_floor != 1:
		failures.append("crew_floor expected 1, got %d" % floored.crew_floor)
	floored.queue_free()

	# Untracked crew (complement 0) never disables.
	var untracked: Ship = preload(CORVETTE_SCENE).instantiate()
	tree.root.add_child(untracked)
	await tree.process_frame
	untracked.hull.apply_damage(untracked.hull.current_hp * 0.95)
	if untracked.is_disabled():
		failures.append("complement 0 ship was disabled")
	untracked.queue_free()

	return failures

static func _spawn(tree: SceneTree, crew_count: int, complement: int, floor_count: int) -> Ship:
	var ship: Ship = load(CORVETTE_SCENE).instantiate()
	ship.enemy_group = &"test_crew_enemy"
	tree.root.add_child(ship)
	await tree.process_frame
	ship.setup_crew(crew_count, complement, floor_count)
	return ship

static func _spawn_target(tree: SceneTree, ship: Ship) -> Ship:
	var target: Ship = load(TARGET_SCENE).instantiate()
	target.add_to_group(&"test_crew_enemy")
	tree.root.add_child(target)
	target.global_position = ship.global_position + Vector2(50.0, 0.0)
	await tree.process_frame
	return target
