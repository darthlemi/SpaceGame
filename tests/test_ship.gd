extends RefCounted

const ShipScene = preload("res://scenes/ship/ship.tscn")

# NOTE ON HEADLESS LIMITATIONS:
# Godot's `--script` headless mode runs this test file's main loop (tests/run_tests.gd)
# without a live, displayed scene. Nodes added to `SceneTree.root` in this mode never
# actually become is_inside_tree()==true, so Node._ready() (and therefore Ship's
# @onready var resolution and its weapon_mounts auto-discovery) never fires. This was
# confirmed experimentally: after `tree.root.add_child(ship)`, `ship.is_inside_tree()`
# is false and `ship.hull`/`ship.shield`/`ship.engine` remain null.
#
# Because of that, this suite verifies two things separately:
#   1. Structural: that scenes/ship/ship.tscn instantiates the expected node tree
#      (Hull/Shield/Engine/WeaponMount children with the exact names Ship.gd's
#      @onready $Hull/$Shield/$Engine paths expect), without relying on _ready().
#   2. Behavioral: Ship's actual logic (execute_order, receive_damage, attack_range,
#      hull-destroyed wiring) by constructing a bare Ship and wiring hull/shield/engine/
#      weapon_mounts manually -- the same assignments @onready + _ready() would have
#      performed in a live game, exercised here without needing a running SceneTree.
#
# What remains UNVERIFIED here (needs a real editor/F6 playtest): that _ready() itself
# correctly performs this wiring at runtime, and the full visual/physics behavior --
# ship turning/moving via move_and_slide(), projectiles actually spawning and flying,
# shield regen over real frames, and a destroyed ship visually disappearing.

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
	elif not is_equal_approx(mount_weapon.range, 300.0):
		failures.append("ship.tscn: expected mounted weapon range 300.0, got %s" % mount_weapon.range)

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
	weapon.range = 300.0
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
