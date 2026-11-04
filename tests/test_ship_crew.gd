extends RefCounted

const CORVETTE_SCENE := "res://scenes/ship/ship_corvette.tscn"
# Fixed weapon: randomize_loadout can pick weapons that do not fire at 50px in two frames.
const TEST_WEAPON := "res://resources/weapons/kinetic_cannon.tres"
# free() not queue_free(): a lingering group member would be fired at by the next case.
const TARGET_SCENE := "res://scenes/ship/ship.tscn"

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	# Crew scales with hull loss and efficiency follows: lerp(0.5, 1.0, crew / complement).
	var ship: Ship = await _spawn(tree, 6, 12, 0)
	_check_multipliers(ship, 0.75, "crew 6/12", failures)
	ship.hull.apply_damage(ship.hull.current_hp * 0.5)
	if absf(ship.crew - 3.0) > 0.01:
		failures.append("crew after 50%% hull damage: expected ~3.0, got %f" % ship.crew)
	_check_multipliers(ship, 0.625, "crew 3/12 after hull hit", failures)
	if not is_equal_approx(ship.crew_efficiency(), 0.625):
		failures.append("crew_efficiency: expected 0.625, got %s" % ship.crew_efficiency())
	ship.free()

	# Cooldown after firing is stretched by 1 / efficiency.
	var slow: Ship = await _spawn(tree, 0, 12, 0)
	var slow_target := await _spawn_target(tree, slow)
	var slow_mount: WeaponMount = slow.weapon_mounts[0]
	slow_mount.cooldown_remaining = 0.0
	if not slow_mount.try_fire(slow_target):
		failures.append("cooldown test: mount failed to fire (test would be vacuous)")
	var expected_cooldown: float = 1.0 / (slow_mount.weapon.fire_rate * 0.5)
	if not is_equal_approx(slow_mount.cooldown_remaining, expected_cooldown):
		failures.append("cooldown at efficiency 0.5: expected %f, got %f" % [expected_cooldown, slow_mount.cooldown_remaining])
	slow.free()
	slow_target.free()

	# The EW drone's per-frame regen_multiplier reset must not clear the crew part.
	var ew: Ship = await _spawn(tree, 0, 12, 0)
	ew.shield.regen_multiplier = 0.5
	await tree.physics_frame
	if not is_equal_approx(ew.shield.crew_multiplier, 0.5):
		failures.append("shield.crew_multiplier after a physics frame: expected 0.5, got %s" % ew.shield.crew_multiplier)
	ew.free()

	# Heavy damage never disables: a ship at crew 1 still fires.
	var control: Ship = await _spawn(tree, 12, 12, 0)
	var control_target := await _spawn_target(tree, control)
	await tree.physics_frame
	await tree.physics_frame
	var control_fired := false
	for mount in control.weapon_mounts:
		if mount.cooldown_remaining > 0.0:
			control_fired = true
	if not control_fired:
		failures.append("control: full-crew ship never fired (test would be vacuous)")
	control.free()
	control_target.free()

	var weak: Ship = await _spawn(tree, 12, 12, 1)
	weak.hull.apply_damage(weak.hull.current_hp * 0.95)
	var weak_target := await _spawn_target(tree, weak)
	await tree.physics_frame
	await tree.physics_frame
	if weak.crew > 1.0 + 0.001:
		failures.append("fire test: expected crew floored at 1, got %f" % weak.crew)
	var weak_fired := false
	for mount in weak.weapon_mounts:
		if mount.cooldown_remaining > 0.0:
			weak_fired = true
	if not weak_fired:
		failures.append("a ship at crew 1 never fired (cooldown stayed 0)")
	weak.free()
	weak_target.free()

	# Crew floor holds under heavy damage.
	var floored: Ship = await _spawn(tree, 12, 12, 1)
	floored.hull.apply_damage(floored.hull.current_hp * 0.95)
	if floored.crew < 1.0:
		failures.append("crew_floor 1 violated: crew %f" % floored.crew)
	if floored.crew_floor != 1:
		failures.append("crew_floor expected 1, got %d" % floored.crew_floor)
	floored.free()

	# Untracked crew (complement 0) keeps full efficiency.
	var untracked: Ship = preload(CORVETTE_SCENE).instantiate()
	tree.root.add_child(untracked)
	await tree.process_frame
	untracked.hull.apply_damage(untracked.hull.current_hp * 0.95)
	if untracked.crew_efficiency() != 1.0:
		failures.append("complement 0 ship efficiency: expected 1.0, got %s" % untracked.crew_efficiency())
	untracked.free()

	return failures

static func _check_multipliers(ship: Ship, expected: float, label: String, failures: Array[String]) -> void:
	if not is_equal_approx(ship.engine.crew_multiplier, expected):
		failures.append("%s: engine.crew_multiplier expected %s, got %s" % [label, expected, ship.engine.crew_multiplier])
	if not is_equal_approx(ship.shield.crew_multiplier, expected):
		failures.append("%s: shield.crew_multiplier expected %s, got %s" % [label, expected, ship.shield.crew_multiplier])
	for mount in ship.weapon_mounts:
		if not is_equal_approx(mount.fire_rate_multiplier, expected):
			failures.append("%s: mount.fire_rate_multiplier expected %s, got %s" % [label, expected, mount.fire_rate_multiplier])

static func _spawn(tree: SceneTree, crew_count: int, complement: int, floor_count: int) -> Ship:
	var ship: Ship = load(CORVETTE_SCENE).instantiate()
	ship.enemy_group = &"test_crew_enemy"
	tree.root.add_child(ship)
	await tree.process_frame
	for mount in ship.weapon_mounts:
		mount.weapon = load(TEST_WEAPON)
	ship.setup_crew(crew_count, complement, floor_count)
	return ship

static func _spawn_target(tree: SceneTree, ship: Ship) -> Ship:
	var target: Ship = load(TARGET_SCENE).instantiate()
	target.add_to_group(&"test_crew_enemy")
	tree.root.add_child(target)
	target.global_position = ship.global_position + Vector2(50.0, 0.0)
	await tree.process_frame
	return target
