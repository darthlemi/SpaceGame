extends RefCounted

const CorvetteScene = preload("res://scenes/ship/ship_corvette.tscn")
const CapitalScene = preload("res://scenes/ship/ship_capital.tscn")
const Railgun = preload("res://resources/weapons/railgun.tres")
const PdLaserTurret = preload("res://resources/weapons/pd_laser_turret.tres")

const ENEMY_GROUP := &"test_focus_enemies"
const ALLY_GROUP := &"test_focus_allies"

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	await _check_only_primary_weapons_fire(tree, failures)
	await _check_pd_fires_regardless(tree, failures)
	await _check_dodge_offsets_station(tree, failures)
	return failures

static func _spawn_dummy(tree: SceneTree, pos: Vector2, group: StringName) -> Ship:
	var ship: Ship = CorvetteScene.instantiate()
	tree.root.add_child(ship)
	ship.global_position = pos
	for mount in ship.weapon_mounts:
		mount.weapon = null
	ship.ally_group = group
	ship.add_to_group(group)
	ship.enemy_group = ENEMY_GROUP if group == ALLY_GROUP else ALLY_GROUP
	ship.set_physics_process(false)
	ship.hull.max_hp = 1.0e9
	ship.hull.current_hp = 1.0e9
	await tree.physics_frame
	return ship

static func _run_for(tree: SceneTree, seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await tree.physics_frame

static func _cleanup(tree: SceneTree, nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await tree.physics_frame

static func _check_only_primary_weapons_fire(tree: SceneTree, failures: Array[String]) -> void:
	# Far enough that the side mounts' lateral offset (+-25px) stays inside their narrow
	# 10-degree fire arc (a few hundred px away keeps the bearing error under the 5-degree
	# half-arc), but still inside the railgun's 500 range.
	var target := await _spawn_dummy(tree, Vector2(950.0, 500.0), ENEMY_GROUP)
	var capital: Ship = CapitalScene.instantiate()
	tree.root.add_child(capital)
	capital.global_position = Vector2(500.0, 500.0)
	# Capital has 3 mounts: wire 3 distinct-dps railguns so one is clearly
	# the lowest and must be held back.
	var weak := Railgun.duplicate()
	weak.damage = 1.0
	capital.weapon_mounts[0].weapon = weak
	capital.weapon_mounts[1].weapon = Railgun.duplicate()
	capital.weapon_mounts[2].weapon = Railgun.duplicate()
	capital.ally_group = ALLY_GROUP
	capital.add_to_group(ALLY_GROUP)
	capital.enemy_group = ENEMY_GROUP
	await tree.physics_frame
	capital.execute_order(Order.attack_target(target))
	await _run_for(tree, 1.0)
	if capital.weapon_mounts[0].cooldown_remaining > 0.0:
		failures.append("only_primary_weapons_fire: expected the lowest-dps mount to be held back, but it fired")
	if capital.weapon_mounts[1].cooldown_remaining <= 0.0 and capital.weapon_mounts[2].cooldown_remaining <= 0.0:
		failures.append("only_primary_weapons_fire: expected the two higher-dps mounts to fire")
	await _cleanup(tree, [target, capital])

static func _check_pd_fires_regardless(tree: SceneTree, failures: Array[String]) -> void:
	var target := await _spawn_dummy(tree, Vector2(600.0, 500.0), ENEMY_GROUP)
	# The corvette scene has only 1 weapon mount, so this needs the capital's 3 mounts to
	# wire a PD turret alongside two higher-dps non-PD weapons that legitimately fill the
	# top-2 focus set, proving PD fires independently rather than by being the sole option.
	var ship: Ship = CapitalScene.instantiate()
	tree.root.add_child(ship)
	ship.global_position = Vector2(500.0, 500.0)
	ship.weapon_mounts[0].weapon = PdLaserTurret
	ship.weapon_mounts[1].weapon = Railgun.duplicate()
	ship.weapon_mounts[2].weapon = Railgun.duplicate()
	ship.ally_group = ALLY_GROUP
	ship.add_to_group(ALLY_GROUP)
	ship.enemy_group = ENEMY_GROUP
	await tree.physics_frame
	ship.execute_order(Order.attack_target(target))
	await _run_for(tree, 1.0)
	if ship.weapon_mounts[0].cooldown_remaining <= 0.0:
		failures.append("pd_fires_regardless: expected the PD mount to fire even when not in the top-2 ranked set")
	await _cleanup(tree, [target, ship])

static func _check_dodge_offsets_station(tree: SceneTree, failures: Array[String]) -> void:
	var target := await _spawn_dummy(tree, Vector2(700.0, 500.0), ENEMY_GROUP)
	var attacker := await _spawn_dummy(tree, Vector2(500.0, 500.0), ALLY_GROUP)
	attacker.set_physics_process(true)
	attacker.weapon_mounts[0].weapon = Railgun
	var projectile := Projectile.new()
	tree.root.add_child(projectile)
	projectile.global_position = target.global_position
	projectile.target = attacker
	projectile.travel_direction = (attacker.global_position - target.global_position).normalized()
	projectile.add_to_group(&"projectiles")
	attacker.execute_order(Order.hold_position())
	await tree.physics_frame
	if attacker._dodge_timer <= 0.0:
		failures.append("dodge_offsets_station: expected an incoming projectile targeting this ship to start a dodge")
	await _cleanup(tree, [target, attacker, projectile])
