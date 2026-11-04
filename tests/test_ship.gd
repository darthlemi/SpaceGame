extends RefCounted

const ShipScene = preload("res://scenes/ship/ship.tscn")

# NOTE ON HEADLESS SCENE-TREE TIMING:
# Adding a node to `SceneTree.root` does not make it is_inside_tree()==true, and does
# not run its _ready(), synchronously within the same call that added it -- this is
# true in headless `--script` mode same as in a normal running game. `_ready()` (and
# therefore Ship's @onready var resolution and its weapon_mounts auto-discovery loop)
# fires on the *next process frame* after the node enters the tree, which in headless
# mode is reachable by `await get_tree().process_frame` (or, from a static helper
# handed the tree, `await tree.process_frame`). This is standard Godot deferred
# SceneTree notification behavior, not a hard limitation of headless mode.
#
# This suite therefore covers three things:
#   1. Structural: that scenes/ship/ship.tscn instantiates the expected node tree
#      (Hull/Shield/Engine/WeaponMount children with the exact names Ship.gd's
#      @onready $Hull/$Shield/$Engine paths expect), without relying on _ready().
#   2. Behavioral: Ship's actual logic (execute_order, receive_damage, attack_range,
#      hull-destroyed wiring) by constructing a bare Ship and wiring hull/shield/engine/
#      weapon_mounts manually -- the same assignments @onready + _ready() would have
#      performed in a live game, exercised here without needing a running SceneTree.
#   3. Integration (run_async, see below): instantiates the real ship.tscn, adds it to
#      the live SceneTree under `tree.root`, awaits one process frame so the real
#      `_ready()` actually runs, then asserts @onready resolution, weapon_mounts
#      auto-discovery, and the hull.destroyed -> queue_free() signal wiring all happened
#      through the genuine _ready() code path (not a hand-wired stand-in).
#
# What remains UNVERIFIED here (needs a real editor/F6 playtest): full visual/physics
# behavior -- ship turning/moving via move_and_slide(), projectiles actually spawning
# and flying, shield regen over real frames, and a destroyed ship visually disappearing.

static func run() -> Array[String]:
	var failures: Array[String] = []

	_check_scene_structure(failures)
	_check_ship_logic(failures)
	_check_autofire_targeting(failures)
	_check_engage_movement(failures)
	_check_engagement_distance(failures)
	_check_engagement_range(failures)
	_check_hold_anchor(failures)
	_check_hold_hunt(failures)
	_check_mount_target(failures)
	_check_receive_weapon_damage(failures)

	return failures

static func _check_scene_structure(failures: Array[String]) -> void:
	var ship: Ship = ShipScene.instantiate()

	var hull_node := ship.get_node_or_null("Hull")
	var shield_node := ship.get_node_or_null("Shield")
	var engine_node := ship.get_node_or_null("Engine")

	if hull_node == null or not (hull_node is Hull):
		failures.append("ship.tscn: expected child named 'Hull' with Hull script")
	if shield_node == null or not (shield_node is Shield):
		failures.append("ship.tscn: expected child named 'Shield' with Shield script")
	if engine_node == null or not (engine_node is ShipEngine):
		failures.append("ship.tscn: expected child named 'Engine' with ShipEngine script")

	var mount_count := 0
	var mount_weapon: Weapon = null
	for child in ship.get_children():
		if child is WeaponMount:
			mount_count += 1
			mount_weapon = child.weapon
	if mount_count != 1:
		failures.append("ship.tscn: expected exactly 1 WeaponMount child, got %d" % mount_count)
	if mount_weapon == null:
		failures.append("ship.tscn: expected the WeaponMount's weapon to be assigned (kinetic_cannon.tres)")
	elif not is_equal_approx(mount_weapon.weapon_range, 300.0):
		failures.append("ship.tscn: expected mounted weapon range 300.0, got %s" % mount_weapon.weapon_range)

	if not (ship.get_child_count() >= 1):
		failures.append("ship.tscn: root has no children")

	if not is_equal_approx(ship.hit_radius, 16.0):
		failures.append("ship.tscn: expected hit_radius 16.0, got %s" % ship.hit_radius)
	for child in ship.get_children():
		if child is WeaponMount and child.hitbox_radius <= 0.0:
			failures.append("ship.tscn: expected the WeaponMount to have a positive hitbox_radius")
	var generic_engine := ship.get_node_or_null("Engine")
	if generic_engine != null and generic_engine.hitbox_radius <= 0.0:
		failures.append("ship.tscn: expected the Engine to have a positive hitbox_radius")

	ship.free()

static func _check_ship_logic(failures: Array[String]) -> void:
	# Build a Ship and wire hull/shield/engine/weapon_mounts the way @onready + _ready()
	# would, without requiring a live SceneTree.
	var ship := Ship.new()
	var hull := Hull.new()
	hull.max_hp = 100.0
	hull.current_hp = 100.0
	var shield := Shield.new()
	shield.max_shield = 50.0
	shield.current_shield = 50.0
	var engine := ShipEngine.new()

	ship.hull = hull
	ship.shield = shield
	ship.engine = engine
	ship.hull.destroyed.connect(ship._on_hull_destroyed)
	ship.current_order = Order.hold()

	var weapon := Weapon.new()
	weapon.weapon_name = "Kinetic Cannon"
	weapon.damage = 10.0
	weapon.fire_rate = 2.0
	weapon.weapon_range = 300.0
	var mount := WeaponMount.new()
	mount.weapon = weapon
	ship.weapon_mounts = [mount]

	var target := Ship.new()
	var target_hull := Hull.new()
	target_hull.max_hp = 100.0
	target_hull.current_hp = 100.0
	target.hull = target_hull

	# attack_range() should reflect the mounted weapon's range.
	if not is_equal_approx(ship.attack_range(), 300.0):
		failures.append("attack_range: expected 300.0, got %s" % ship.attack_range())

	# execute_order(attack_target) should update current_order.type/target_ship.
	ship.execute_order(Order.attack_target(target))
	if ship.current_order.type != Order.Type.ATTACK_TARGET:
		failures.append("execute_order: expected current_order.type ATTACK_TARGET, got %s" % ship.current_order.type)
	if ship.current_order.target_ship != target:
		failures.append("execute_order: expected current_order.target_ship to be target")

	# receive_damage should route through shield first (no hull damage while shield absorbs).
	ship.receive_damage(25.0)
	if not is_equal_approx(ship.shield.current_shield, 25.0):
		failures.append("receive_damage: expected shield to absorb damage under its capacity, got current_shield=%s" % ship.shield.current_shield)
	if not is_equal_approx(ship.hull.current_hp, 100.0):
		failures.append("receive_damage: expected hull untouched while shield absorbs, got current_hp=%s" % ship.hull.current_hp)

	# Overflow beyond remaining shield should spill into hull.
	ship.receive_damage(45.0)
	if not is_equal_approx(ship.shield.current_shield, 0.0):
		failures.append("receive_damage: expected shield depleted to 0 after overflow damage, got %s" % ship.shield.current_shield)
	if not is_equal_approx(ship.hull.current_hp, 80.0):
		failures.append("receive_damage: expected hull to take 20.0 overflow damage (100 - 20 = 80), got current_hp=%s" % ship.hull.current_hp)

	# hull.destroyed -> Ship._on_hull_destroyed() should call queue_free() without error.
	if ship.is_queued_for_deletion():
		failures.append("Ship: unexpectedly already queued for deletion before hull destruction")
	ship.hull.apply_damage(ship.hull.current_hp)
	if not ship.hull.is_destroyed():
		failures.append("Hull: expected is_destroyed() true after applying lethal damage")
	if not ship.is_queued_for_deletion():
		failures.append("Ship: expected ship to be queued for deletion after hull.destroyed fires")

	# Component hit resolution: a mount positioned away from the ship's
	# origin should absorb overflow damage exclusively, leaving hull/shield
	# untouched, when the impact point lands inside its hitbox.
	var hit_ship := Ship.new()
	var hit_hull := Hull.new()
	hit_hull.max_hp = 100.0
	hit_hull._ready()
	var hit_shield := Shield.new()
	hit_shield.max_shield = 0.0
	hit_shield.current_shield = 0.0
	var hit_engine := ShipEngine.new()
	hit_engine.max_hp = 20.0
	hit_engine._ready()
	var hit_mount := WeaponMount.new()
	hit_mount.max_hp = 15.0
	hit_mount._ready()
	hit_mount.hitbox_radius = 8.0
	hit_mount.position = Vector2(20, 0)
	hit_ship.hull = hit_hull
	hit_ship.shield = hit_shield
	hit_ship.engine = hit_engine
	hit_ship.weapon_mounts = [hit_mount]
	hit_ship.add_child(hit_mount)
	hit_ship.add_child(hit_engine)

	hit_ship.receive_damage(10.0, Vector2(20, 2))
	if not is_equal_approx(hit_mount.current_hp, 5.0):
		failures.append("receive_damage: expected the mount's hitbox to absorb the hit, got mount.current_hp=%s" % hit_mount.current_hp)
	if not is_equal_approx(hit_hull.current_hp, 100.0):
		failures.append("receive_damage: expected hull untouched by a component-exclusive hit, got %s" % hit_hull.current_hp)

	hit_ship.receive_damage(10.0, Vector2(-200, -200))
	if not is_equal_approx(hit_hull.current_hp, 90.0):
		failures.append("receive_damage: expected a hit outside every hitbox to fall through to hull, got %s" % hit_hull.current_hp)

	hit_ship.receive_damage(10.0)
	if not is_equal_approx(hit_hull.current_hp, 80.0):
		failures.append("receive_damage: expected the default impact_position to route to hull (ship's own center), got %s" % hit_hull.current_hp)

	hit_ship.free()

	hull.free()
	shield.free()
	engine.free()
	mount.free()
	target_hull.free()
	target.free()
	ship.free()

static func _check_receive_weapon_damage(failures: Array[String]) -> void:
	# shield_mult 1.4, hull_mult 0.75, no pierce: damage 10 -> effective shield hit 14,
	# fully absorbed (shield has 20), no hull damage.
	var ship := Ship.new()
	var hull := Hull.new()
	hull.max_hp = 100.0
	hull._ready()
	var shield := Shield.new()
	shield.max_shield = 20.0
	shield.current_shield = 20.0
	ship.hull = hull
	ship.shield = shield
	ship.engine = ShipEngine.new()
	ship.engine._ready()

	var pulse_laser := Weapon.new()
	pulse_laser.damage = 10.0
	pulse_laser.shield_mult = 1.4
	pulse_laser.hull_mult = 0.75
	ship.receive_weapon_damage(pulse_laser)
	if not is_equal_approx(ship.shield.current_shield, 6.0):
		failures.append("receive_weapon_damage: expected shield 20 - 14 = 6.0, got %s" % ship.shield.current_shield)
	if not is_equal_approx(ship.hull.current_hp, 100.0):
		failures.append("receive_weapon_damage: expected hull untouched, got %s" % ship.hull.current_hp)

	# Second hit: effective shield hit 14, only 6 shield left -> overflow_effective 8,
	# raw_unabsorbed = 8 / 1.4, hull_damage = raw_unabsorbed * 0.75.
	ship.receive_weapon_damage(pulse_laser)
	var expected_hull_damage: float = (8.0 / 1.4) * 0.75
	if not is_equal_approx(ship.shield.current_shield, 0.0):
		failures.append("receive_weapon_damage: expected shield depleted to 0.0, got %s" % ship.shield.current_shield)
	if not is_equal_approx(ship.hull.current_hp, 100.0 - expected_hull_damage):
		failures.append("receive_weapon_damage: expected hull %s, got %s" % [100.0 - expected_hull_damage, ship.hull.current_hp])

	# pierce_pct: a railgun with pierce_pct 0.25 against a full shield should still
	# land 25% of its damage * hull_mult directly on hull.
	var railgun_ship := Ship.new()
	var r_hull := Hull.new()
	r_hull.max_hp = 100.0
	r_hull._ready()
	var r_shield := Shield.new()
	r_shield.max_shield = 1000.0
	r_shield.current_shield = 1000.0
	railgun_ship.hull = r_hull
	railgun_ship.shield = r_shield
	railgun_ship.engine = ShipEngine.new()
	railgun_ship.engine._ready()
	var railgun := Weapon.new()
	railgun.damage = 40.0
	railgun.shield_mult = 0.5
	railgun.hull_mult = 1.0
	railgun.pierce_pct = 0.25
	railgun_ship.receive_weapon_damage(railgun)
	if not is_equal_approx(r_hull.current_hp, 90.0):
		failures.append("receive_weapon_damage: expected pierce to deal 10.0 hull damage (40*0.25*1.0), got hull=%s" % r_hull.current_hp)

	# component_damage: a hit that geometrically lands on a component's hitbox gets
	# the bonus added on top of the hull_mult-scaled overflow; a hit that lands on
	# bare hull (no component in range) only ever damages hull, never the component.
	var emp_ship := Ship.new()
	var e_hull := Hull.new()
	e_hull.max_hp = 100.0
	e_hull._ready()
	var e_shield := Shield.new()
	e_shield.max_shield = 0.0
	e_shield.current_shield = 0.0
	var e_engine := ShipEngine.new()
	e_engine.max_hp = 30.0
	e_engine._ready()
	e_engine.hitbox_radius = 8.0
	e_engine.position = Vector2(20, 0)
	emp_ship.hull = e_hull
	emp_ship.shield = e_shield
	emp_ship.engine = e_engine
	emp_ship.add_child(e_engine)

	var emp_missile := Weapon.new()
	emp_missile.damage = 6.0
	emp_missile.hull_mult = 0.5
	emp_missile.component_damage = 15.0
	emp_ship.receive_weapon_damage(emp_missile, Vector2(20, 2))
	if not is_equal_approx(e_engine.current_hp, 30.0 - (6.0 * 0.5 + 15.0)):
		failures.append("receive_weapon_damage: expected engine to take hull_mult-scaled damage plus the component_damage bonus, got %s" % e_engine.current_hp)
	if not is_equal_approx(e_hull.current_hp, 100.0):
		failures.append("receive_weapon_damage: expected hull untouched when the hit lands on a component, got %s" % e_hull.current_hp)

	emp_ship.receive_weapon_damage(emp_missile, Vector2(-200, -200))
	if not is_equal_approx(e_hull.current_hp, 100.0 - 6.0 * 0.5):
		failures.append("receive_weapon_damage: expected a hit outside every hitbox to apply hull_mult-scaled damage to hull with no component_damage bonus, got %s" % e_hull.current_hp)

	hull.free()
	shield.free()
	ship.engine.free()
	ship.free()
	r_hull.free()
	r_shield.free()
	railgun_ship.engine.free()
	railgun_ship.free()
	e_hull.free()
	e_shield.free()
	emp_ship.free()

# Integration test: exercises the REAL scene-tree lifecycle (real @onready resolution,
# real _ready() auto-discovery loop, real signal connection) instead of the manually
# wired stand-in used by _check_ship_logic() above. Must be awaited by the caller
# (see tests/run_tests.gd), since entering the tree and _ready() only happen on the
# next process frame.
static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var ship: Ship = ShipScene.instantiate()
	tree.root.add_child(ship)

	# _ready() (Ship's, and its children Hull/Shield/Engine's) does not run
	# synchronously on add_child -- it fires on the next process frame.
	await tree.process_frame

	if not ship.is_inside_tree():
		failures.append("run_async: expected ship.is_inside_tree() true after a process frame")

	if ship.hull == null:
		failures.append("run_async: expected ship.hull resolved by @onready via real _ready(), got null")
	if ship.shield == null:
		failures.append("run_async: expected ship.shield resolved by @onready via real _ready(), got null")
	if ship.engine == null:
		failures.append("run_async: expected ship.engine resolved by @onready via real _ready(), got null")

	if ship.weapon_mounts.size() != 1:
		failures.append("run_async: expected _ready()'s auto-discovery loop to find 1 WeaponMount, got %d" % ship.weapon_mounts.size())

	if ship.ship_type != ShipType.Kind.CORVETTE:
		failures.append("run_async: expected ship.tscn's default ship_type == CORVETTE, got %s" % ship.ship_type)

	if ship.hull != null:
		if ship.is_queued_for_deletion():
			failures.append("run_async: ship unexpectedly already queued for deletion before hull destruction")

		# Fire lethal damage through the hull's real API. If this triggers
		# Ship.queue_free(), it can only be via the hull.destroyed connection that
		# Ship._ready() itself established (this test never connects it).
		ship.hull.apply_damage(ship.hull.max_hp)

		if not ship.hull.is_destroyed():
			failures.append("run_async: expected hull.is_destroyed() true after applying lethal damage")
		if not ship.is_queued_for_deletion():
			failures.append("run_async: expected ship.is_queued_for_deletion() true after hull.destroyed fired via real _ready() wiring")

	# Cleanup: ship is already queue_free()'d in the success path; if any assertion
	# above failed before that happened, make sure it still gets cleaned up.
	if is_instance_valid(ship) and not ship.is_queued_for_deletion():
		ship.queue_free()

	return failures

static func _check_autofire_targeting(failures: Array[String]) -> void:
	var near := Node2D.new()
	near.global_position = Vector2(20, 0)
	var far := Node2D.new()
	far.global_position = Vector2(80, 0)
	var candidates: Array = [far, near]

	var nearest := Ship.nearest_in_range(candidates, Vector2.ZERO, 100.0)
	if nearest != near:
		failures.append("nearest_in_range: expected the closer candidate, got %s" % nearest)

	var out_of_range := Ship.nearest_in_range(candidates, Vector2.ZERO, 10.0)
	if out_of_range != null:
		failures.append("nearest_in_range: expected null when all candidates exceed max_range, got %s" % out_of_range)

	var explicit_target := Node2D.new()
	explicit_target.global_position = Vector2(500, 0)
	var attack_order := Order.attack_target(explicit_target)
	var picked := Ship.pick_autofire_target(attack_order, candidates, Vector2.ZERO, 100.0)
	if picked != explicit_target:
		failures.append("pick_autofire_target: expected ATTACK_TARGET to override nearest-in-range, got %s" % picked)

	var hold_order := Order.hold()
	var auto_picked := Ship.pick_autofire_target(hold_order, candidates, Vector2.ZERO, 100.0)
	if auto_picked != near:
		failures.append("pick_autofire_target: expected HOLD to auto-target the nearest in range, got %s" % auto_picked)

	near.free()
	far.free()
	explicit_target.free()

static func _check_engage_movement(failures: Array[String]) -> void:
	var ship := _make_bare_ship([_make_weapon(300.0, 10.0, 1.0)])
	var target := Ship.new()
	target.hit_radius = 12.0

	# Inside the 240 standoff: back off while keeping the nose on the target.
	target.global_position = Vector2(100, 0)
	ship._engage(target, 0.1)
	if ship.velocity.x >= 0.0:
		failures.append("_engage: expected a too-close ship to back away, got velocity %s" % ship.velocity)
	if not is_zero_approx(ship.rotation):
		failures.append("_engage: expected a backing ship to keep facing the target, got rotation %s" % ship.rotation)

	# Far outside the standoff: close in.
	ship.velocity = Vector2.ZERO
	ship.engine.velocity = Vector2.ZERO
	target.global_position = Vector2(1000, 0)
	ship._engage(target, 0.1)
	if ship.velocity.x <= 0.0:
		failures.append("_engage: expected a distant ship to close in, got velocity %s" % ship.velocity)

	# Target behind: turn toward it so forward-facing hardpoints can bear.
	target.global_position = Vector2(-1000, 0)
	ship._engage(target, 0.1)
	if is_zero_approx(ship.rotation):
		failures.append("_engage: expected the ship to turn toward a target behind it")

	# Unarmed: never approach.
	var unarmed := _make_bare_ship([])
	target.global_position = Vector2(1000, 0)
	unarmed._engage(target, 0.1)
	if unarmed.velocity.length() > 0.01:
		failures.append("_engage: expected an unarmed ship not to approach, got velocity %s" % unarmed.velocity)

	_free_bare_ship(ship)
	_free_bare_ship(unarmed)
	target.free()

static func _check_engagement_distance(failures: Array[String]) -> void:
	var target := Ship.new()
	target.hit_radius = 12.0

	var ship := _make_bare_ship([_make_weapon(300.0, 10.0, 1.0)])
	var expected := 300.0 * Ship.ENGAGE_RANGE_FRACTION
	if not is_equal_approx(ship.engagement_distance(target), expected):
		failures.append("engagement_distance: expected %s for a 300-range weapon, got %s" % [expected, ship.engagement_distance(target)])

	# A destroyed mount no longer counts.
	ship.weapon_mounts[0].apply_damage(1000.0)
	if ship.engagement_distance(target) >= 0.0:
		failures.append("engagement_distance: expected < 0 once every mount is destroyed, got %s" % ship.engagement_distance(target))

	# Short weapons never pull the hulls into contact.
	var short_ship := _make_bare_ship([_make_weapon(20.0, 10.0, 1.0)])
	var min_gap := short_ship.hit_radius + target.hit_radius + Ship.ENGAGE_HULL_GAP
	if not is_equal_approx(short_ship.engagement_distance(target), min_gap):
		failures.append("engagement_distance: expected the hull-gap floor %s, got %s" % [min_gap, short_ship.engagement_distance(target)])

	var unarmed := _make_bare_ship([])
	if unarmed.engagement_distance(target) >= 0.0:
		failures.append("engagement_distance: expected < 0 for a ship with no mounts, got %s" % unarmed.engagement_distance(target))

	var bomber := BomberDrone.new()
	if not is_zero_approx(bomber.engagement_distance(target)):
		failures.append("engagement_distance: expected a bomber drone to close to 0, got %s" % bomber.engagement_distance(target))
	var ew := EwDrone.new()
	if not is_equal_approx(ew.engagement_distance(target), ew.aura_range * Ship.ENGAGE_RANGE_FRACTION):
		failures.append("engagement_distance: expected an EW drone to hold inside its aura, got %s" % ew.engagement_distance(target))

	_free_bare_ship(ship)
	_free_bare_ship(short_ship)
	_free_bare_ship(unarmed)
	bomber.free()
	ew.free()
	target.free()

static func _check_engagement_range(failures: Array[String]) -> void:
	var none: Array[Weapon] = []
	if not is_zero_approx(Ship.best_engagement_range(none)):
		failures.append("best_engagement_range: expected 0 with no weapons, got %s" % Ship.best_engagement_range(none))

	var single: Array[Weapon] = [_make_weapon(300.0, 10.0, 2.0)]
	if not is_equal_approx(Ship.best_engagement_range(single), 300.0):
		failures.append("best_engagement_range: expected the only weapon's range 300, got %s" % Ship.best_engagement_range(single))

	# Railgun 8.75 dps @500, kinetic 20 @300, flak 16 @200: only 200 reaches the dps share.
	var mixed: Array[Weapon] = [_make_weapon(500.0, 35.0, 0.25), _make_weapon(300.0, 10.0, 2.0), _make_weapon(200.0, 4.0, 4.0)]
	if not is_equal_approx(Ship.best_engagement_range(mixed), 200.0):
		failures.append("best_engagement_range: expected 200 for a flak-heavy mix, got %s" % Ship.best_engagement_range(mixed))

	# 30 of 35 dps reaches 450, so the light short weapon doesn't drag the ship in.
	var long_heavy: Array[Weapon] = [_make_weapon(450.0, 30.0, 1.0), _make_weapon(200.0, 5.0, 1.0)]
	if not is_equal_approx(Ship.best_engagement_range(long_heavy), 450.0):
		failures.append("best_engagement_range: expected 450 when the long weapon carries the dps, got %s" % Ship.best_engagement_range(long_heavy))

static func _check_hold_anchor(failures: Array[String]) -> void:
	# Spawners position a ship after its _ready has already issued HOLD.
	var ship := _make_bare_ship([])
	ship.execute_order(Order.hold())
	ship.global_position = Vector2(300, 200)
	ship._process_hold(0.016, [])
	if ship._hold_center != Vector2(300, 200):
		failures.append("_process_hold: expected the hold anchor at the first-tick position (300, 200), got %s" % ship._hold_center)
	_free_bare_ship(ship)

static func _check_hold_hunt(failures: Array[String]) -> void:
	var ship := _make_bare_ship([_make_weapon(300.0, 10.0, 1.0)])
	ship.execute_order(Order.hold())
	var near := Ship.new()
	near.global_position = Vector2(2000, 0)
	var far := Ship.new()
	far.global_position = Vector2(-5000, 0)

	# Far beyond weapon range: an idle ship still goes after the nearest enemy.
	ship._process_hold(0.1, [far, near])
	if ship.velocity.x <= 0.0:
		failures.append("_process_hold: expected an idle ship to hunt the nearest enemy, got velocity %s" % ship.velocity)
	if ship._hold_anchored:
		failures.append("_process_hold: expected hunting to drop the hold anchor so loiter restarts where the fight ends")

	_free_bare_ship(ship)
	near.free()
	far.free()

static func _check_mount_target(failures: Array[String]) -> void:
	var weapon := _make_weapon(300.0, 10.0, 1.0)
	weapon.fire_arc_degrees = 10.0
	var mount := WeaponMount.new()
	mount.weapon = weapon
	mount._ready()
	var behind := Node2D.new()
	behind.global_position = Vector2(-100, 0)
	var ahead := Node2D.new()
	ahead.global_position = Vector2(150, 0)
	var candidates: Array = [behind, ahead]

	if Ship.pick_mount_target(mount, ahead, candidates) != ahead:
		failures.append("pick_mount_target: expected the primary target when the mount bears on it")
	if Ship.pick_mount_target(mount, behind, candidates) != ahead:
		failures.append("pick_mount_target: expected a fallback in arc when the primary is behind the mount")
	if Ship.pick_mount_target(mount, null, [behind]) != null:
		failures.append("pick_mount_target: expected null when nothing is in range and arc")

	mount.free()
	behind.free()
	ahead.free()

static func _free_bare_ship(ship: Ship) -> void:
	for mount in ship.weapon_mounts:
		mount.free()
	ship.engine.free()
	ship.hull.free()
	ship.shield.free()
	ship.free()

static func _make_bare_ship(weapons: Array) -> Ship:
	var ship := Ship.new()
	ship.hull = Hull.new()
	ship.shield = Shield.new()
	ship.engine = ShipEngine.new()
	ship.engine.max_speed = 100.0
	ship.engine.acceleration = 1000.0
	ship.engine.turn_rate = 10.0
	ship.engine._ready()
	var mounts: Array[WeaponMount] = []
	for weapon in weapons:
		var mount := WeaponMount.new()
		mount.weapon = weapon
		mount._ready()
		mounts.append(mount)
	ship.weapon_mounts = mounts
	ship.current_order = Order.hold()
	return ship

static func _make_weapon(weapon_range: float, damage: float, fire_rate: float) -> Weapon:
	var weapon := Weapon.new()
	weapon.weapon_range = weapon_range
	weapon.damage = damage
	weapon.fire_rate = fire_rate
	return weapon
