extends RefCounted

const CorvetteScene = preload("res://scenes/ship/ship_corvette.tscn")
const FreighterScene = preload("res://scenes/ship/ship_freighter.tscn")
const CapitalScene = preload("res://scenes/ship/ship_capital.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var corvette: Ship = CorvetteScene.instantiate()
	tree.root.add_child(corvette)
	var freighter: Ship = FreighterScene.instantiate()
	tree.root.add_child(freighter)
	var capital: Ship = CapitalScene.instantiate()
	tree.root.add_child(capital)

	await tree.process_frame

	if corvette.ship_type != ShipType.Kind.CORVETTE:
		failures.append("ship_corvette.tscn: expected ship_type == CORVETTE, got %s" % corvette.ship_type)
	if not is_equal_approx(corvette.hull.max_hp, 60.0):
		failures.append("ship_corvette.tscn: expected hull.max_hp == 60.0, got %s" % corvette.hull.max_hp)
	if not is_equal_approx(corvette.shield.max_shield, 20.0):
		failures.append("ship_corvette.tscn: expected shield.max_shield == 20.0, got %s" % corvette.shield.max_shield)
	if corvette.weapon_mounts.size() != 1:
		failures.append("ship_corvette.tscn: expected exactly 1 WeaponMount, got %d" % corvette.weapon_mounts.size())

	if freighter.ship_type != ShipType.Kind.FREIGHTER:
		failures.append("ship_freighter.tscn: expected ship_type == FREIGHTER, got %s" % freighter.ship_type)
	if not is_equal_approx(freighter.hull.max_hp, 80.0):
		failures.append("ship_freighter.tscn: expected hull.max_hp == 80.0, got %s" % freighter.hull.max_hp)
	if freighter.weapon_mounts.size() != 0:
		failures.append("ship_freighter.tscn: expected 0 WeaponMounts (unarmed), got %d" % freighter.weapon_mounts.size())
	if not is_equal_approx(freighter.attack_range(), 0.0):
		failures.append("ship_freighter.tscn: expected attack_range() == 0.0 for an unarmed hull, got %s" % freighter.attack_range())

	if capital.ship_type != ShipType.Kind.CAPITAL:
		failures.append("ship_capital.tscn: expected ship_type == CAPITAL, got %s" % capital.ship_type)
	if not is_equal_approx(capital.hull.max_hp, 220.0):
		failures.append("ship_capital.tscn: expected hull.max_hp == 220.0, got %s" % capital.hull.max_hp)
	if not is_equal_approx(capital.shield.max_shield, 80.0):
		failures.append("ship_capital.tscn: expected shield.max_shield == 80.0, got %s" % capital.shield.max_shield)
	if capital.weapon_mounts.size() != 3:
		failures.append("ship_capital.tscn: expected exactly 3 WeaponMounts, got %d" % capital.weapon_mounts.size())

	for ship in [corvette, freighter, capital]:
		if is_instance_valid(ship) and not ship.is_queued_for_deletion():
			ship.queue_free()

	return failures
