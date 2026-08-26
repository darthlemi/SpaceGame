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

	hull.free()
	shield.free()
	engine.free()
	mount.free()
	target_hull.free()
	target.free()
	ship.free()

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
