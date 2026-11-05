extends RefCounted

const CorvetteScene = preload("res://scenes/ship/ship_corvette.tscn")
const CapitalScene = preload("res://scenes/ship/ship_capital.tscn")
const HeavyBeam = preload("res://resources/weapons/heavy_beam.tres")
const KineticCannon = preload("res://resources/weapons/kinetic_cannon.tres")
const MassDriver = preload("res://resources/weapons/mass_driver.tres")
const PdLaser = preload("res://resources/weapons/pd_laser_turret.tres")
const Railgun = preload("res://resources/weapons/railgun.tres")

const TEST_GROUP := &"test_tactics_targets"
# Long enough for two railgun passes (4 s cooldown).
const RUN_CHECK_TICKS := 720

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	await _check_edge_range_capital(tree, failures)
	await _check_edge_range_heavy_beam(tree, failures)
	await _check_hold_idle_capital(tree, failures)
	await _check_pd_only(tree, failures)
	await _check_run(tree, failures)
	await _check_run_near_wall(tree, failures)
	await _check_park(tree, failures)
	await _check_kite(tree, failures)
	await _check_spread(tree, failures)
	return failures

# Placed after add_child so _ready's random loadout is overwritten. One tick lets the physics
# server see the new position, else spawns overlapping a stale body at the origin get shoved.
static func _spawn(tree: SceneTree, scene: PackedScene, pos: Vector2, weapon: Weapon, facing: float = 0.0) -> Ship:
	var ship: Ship = scene.instantiate()
	tree.root.add_child(ship)
	ship.global_position = pos
	ship.rotation = facing
	for mount in ship.weapon_mounts:
		mount.weapon = null
	if weapon != null:
		ship.weapon_mounts[0].weapon = weapon
	await tree.physics_frame
	return ship

# A target that stays put and survives the fight.
static func _spawn_dummy(tree: SceneTree, scene: PackedScene, pos: Vector2, weapon: Weapon) -> Ship:
	var dummy := await _spawn(tree, scene, pos, weapon)
	dummy.set_physics_process(false)
	dummy.hull.max_hp = 1.0e9
	dummy.hull.current_hp = 1.0e9
	dummy.add_to_group(TEST_GROUP)
	return dummy

static func _wait_ticks(tree: SceneTree, ticks: int) -> void:
	for i in ticks:
		await tree.physics_frame

static func _check_edge_range_capital(tree: SceneTree, failures: Array[String]) -> void:
	var capital := await _spawn_dummy(tree, CapitalScene, Vector2(2000.0, 0.0), null)
	var ship := await _spawn(tree, CorvetteScene, Vector2.ZERO, KineticCannon)
	var standoff := ship.engagement_distance(capital)
	ship.global_position = capital.global_position + Vector2(-(standoff + capital.get_hit_radius()), 0.0)
	ship.rotation = 0.0
	if not ship.weapon_mounts[0].can_engage(capital):
		failures.append("edge_range_capital_engageable_at_standoff: mount cannot engage a capital from its standoff %s" % standoff)
	ship.queue_free()
	capital.queue_free()

# Short-range beam: centre-based range would fail here (176 + 54 > 220).
static func _check_edge_range_heavy_beam(tree: SceneTree, failures: Array[String]) -> void:
	var capital := await _spawn_dummy(tree, CapitalScene, Vector2(2000.0, 0.0), null)
	var ship := await _spawn(tree, CorvetteScene, Vector2.ZERO, HeavyBeam)
	var standoff := ship.engagement_distance(capital)
	ship.global_position = capital.global_position + Vector2(-(standoff + capital.get_hit_radius()), 0.0)
	ship.rotation = 0.0
	if not ship.weapon_mounts[0].can_engage(capital):
		failures.append("edge_range_heavy_beam_engageable_at_standoff: mount cannot engage a capital from its standoff %s" % standoff)
	ship.queue_free()
	capital.queue_free()

static func _check_hold_idle_capital(tree: SceneTree, failures: Array[String]) -> void:
	var capital := await _spawn_dummy(tree, CapitalScene, Vector2(2000.0, 0.0), null)
	var ship := await _spawn(tree, CorvetteScene, Vector2.ZERO, HeavyBeam)
	var standoff := ship.engagement_distance(capital)
	ship.global_position = capital.global_position + Vector2(-(standoff + capital.get_hit_radius()), 0.0)
	var picked := Ship.pick_autofire_target(Order.hold(), [], ship.global_position, HeavyBeam.weapon_range, capital)
	if picked != capital:
		failures.append("hold_idle_capital_kept_at_standoff: expected the idle capital, got %s" % picked)
	ship.queue_free()
	capital.queue_free()

static func _check_pd_only(tree: SceneTree, failures: Array[String]) -> void:
	var target := await _spawn_dummy(tree, CorvetteScene, Vector2(1000.0, 0.0), null)
	var ship := await _spawn(tree, CorvetteScene, Vector2.ZERO, PdLaser)
	var expected := PdLaser.weapon_range * Ship.ENGAGE_RANGE_FRACTION
	var got := ship.engagement_distance(target)
	if absf(got - expected) > 0.01:
		failures.append("pd_only_ship_closes_to_pd_range: expected %s, got %s" % [expected, got])
	ship.queue_free()
	target.queue_free()

static func _check_run(tree: SceneTree, failures: Array[String]) -> void:
	var capital := await _spawn_dummy(tree, CapitalScene, Vector2(1000.0, 0.0), null)
	var ship := await _spawn(tree, CorvetteScene, Vector2.ZERO, Railgun)
	await _expect_repeated_runs(tree, ship, capital, "run_ship_repeats_passes", failures)
	ship.queue_free()
	capital.queue_free()

# Approached along a wall from the side whose break point lies past it, so the latched point
# must be clamped inside the arena for the runs to go on.
static func _check_run_near_wall(tree: SceneTree, failures: Array[String]) -> void:
	var capital := await _spawn_dummy(tree, CapitalScene, Vector2(1000.0, 100.0), null)
	var ship := await _spawn(tree, CorvetteScene, Vector2.ZERO, Railgun)
	var side := 1.0 if ship.get_instance_id() % 2 == 0 else -1.0
	ship.global_position = capital.global_position + Vector2(-900.0 * side, 0.0)
	ship.rotation = 0.0 if side > 0.0 else PI
	ship.arena_rect = Rect2(0.0, 0.0, 2000.0, 1200.0)
	await tree.physics_frame
	await _expect_repeated_runs(tree, ship, capital, "run_ship_repeats_passes_near_wall", failures)
	ship.queue_free()
	capital.queue_free()

# Two shots and a turn back in prove a second pass; a ship orbiting after one pass never
# bears its fixed gun again. Shots show as the mount's cooldown jumping up.
static func _expect_repeated_runs(tree: SceneTree, ship: Ship, target: Ship, label: String, failures: Array[String]) -> void:
	ship.execute_order(Order.attack_target(target))
	var hull_floor := ship.hit_radius + Ship.ENGAGE_HULL_GAP
	var shots := 0
	var returns := 0
	var min_edge := INF
	var left_arena := false
	var last_cooldown := 0.0
	var last_phase := ship._run_phase
	for i in RUN_CHECK_TICKS:
		await tree.physics_frame
		if not is_instance_valid(ship):
			break
		min_edge = minf(min_edge, CombatTactics.edge_distance(ship.global_position, target))
		if ship.arena_rect.has_area() and not ship.arena_rect.has_point(ship.global_position):
			left_arena = true
		if last_phase == CombatTactics.RunPhase.BREAK and ship._run_phase == CombatTactics.RunPhase.INBOUND:
			returns += 1
		last_phase = ship._run_phase
		var cooldown: float = ship.weapon_mounts[0].cooldown_remaining
		if cooldown > last_cooldown:
			shots += 1
		last_cooldown = cooldown
	if returns < 1 or shots < 2:
		failures.append("%s: expected a turn back in and 2 shots in %d ticks, got %d returns, %d shots" % [label, RUN_CHECK_TICKS, returns, shots])
	if min_edge < hull_floor:
		failures.append("%s: closed to edge %s, inside the hull floor %s" % [label, min_edge, hull_floor])
	if left_arena:
		failures.append("%s: left the arena" % label)

static func _check_park(tree: SceneTree, failures: Array[String]) -> void:
	var capital := await _spawn_dummy(tree, CapitalScene, Vector2(700.0, 0.0), null)
	var ship := await _spawn(tree, CorvetteScene, Vector2.ZERO, KineticCannon)
	ship.execute_order(Order.attack_target(capital))
	await _wait_ticks(tree, 180)
	var standoff := ship.engagement_distance(capital)
	var edge := CombatTactics.edge_distance(ship.global_position, capital)
	if absf(edge - standoff) > standoff * 0.15:
		failures.append("turret_ship_parks: edge %s not within 15%% of standoff %s" % [edge, standoff])
	ship.queue_free()
	capital.queue_free()

static func _check_kite(tree: SceneTree, failures: Array[String]) -> void:
	var enemy := await _spawn_dummy(tree, CorvetteScene, Vector2(700.0, 0.0), KineticCannon)
	var ship := await _spawn(tree, CorvetteScene, Vector2.ZERO, MassDriver)
	ship.execute_order(Order.attack_target(enemy))
	await _wait_ticks(tree, 180)
	var edge := CombatTactics.edge_distance(ship.global_position, enemy)
	var kite_at := KineticCannon.weapon_range + CombatTactics.KITE_MARGIN
	if edge <= kite_at - 10.0:
		failures.append("kiter_holds_outside_enemy_range: edge %s should sit near %s, not at the 320 standoff" % [edge, kite_at])
	ship.queue_free()
	enemy.queue_free()

static func _check_spread(tree: SceneTree, failures: Array[String]) -> void:
	var target := await _spawn_dummy(tree, CorvetteScene, Vector2(1000.0, 0.0), null)
	var ships: Array[Ship] = []
	for y in [-30.0, 0.0, 30.0]:
		var ship := await _spawn(tree, CorvetteScene, Vector2(0.0, y), KineticCannon)
		ship.ally_group = &"test_tactics_allies"
		ship.add_to_group(&"test_tactics_allies")
		ship.execute_order(Order.attack_target(target))
		ships.append(ship)
	await _wait_ticks(tree, 180)
	var min_gap := 2.0 * ships[0].hit_radius
	for i in ships.size():
		for j in range(i + 1, ships.size()):
			var gap := ships[i].global_position.distance_to(ships[j].global_position)
			if gap <= min_gap:
				failures.append("allies_spread_on_one_target: ships %d and %d are %s apart (need > %s)" % [i, j, gap, min_gap])
	for ship in ships:
		ship.queue_free()
	target.queue_free()
