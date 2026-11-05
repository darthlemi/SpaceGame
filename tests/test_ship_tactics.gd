extends RefCounted

const CorvetteScene = preload("res://scenes/ship/ship_corvette.tscn")
const CapitalScene = preload("res://scenes/ship/ship_capital.tscn")
const KineticCannon = preload("res://resources/weapons/kinetic_cannon.tres")
const MassDriver = preload("res://resources/weapons/mass_driver.tres")
const PdLaser = preload("res://resources/weapons/pd_laser_turret.tres")
const Railgun = preload("res://resources/weapons/railgun.tres")

const TEST_GROUP := &"test_tactics_targets"

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	await _check_edge_range_capital(tree, failures)
	await _check_pd_only(tree, failures)
	await _check_run(tree, failures)
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
	ship.execute_order(Order.attack_target(capital))
	var break_edge := CombatTactics.RUN_BREAK_FRACTION * Railgun.weapon_range
	var went_close := false
	var reopened := false
	for i in 600:
		await tree.physics_frame
		if not is_instance_valid(ship):
			break
		var edge := CombatTactics.edge_distance(ship.global_position, capital)
		if edge < break_edge:
			went_close = true
		elif went_close and edge > break_edge:
			reopened = true
			break
	if not went_close:
		failures.append("run_ship_closes_then_breaks: never closed inside %s" % break_edge)
	elif not reopened:
		failures.append("run_ship_closes_then_breaks: closed in but never opened out again")
	ship.queue_free()
	capital.queue_free()

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
