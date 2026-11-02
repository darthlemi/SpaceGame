extends RefCounted

# Deliberately NOT registered near test_ship.gd/test_ai_controller_targeting.gd in
# run_tests.gd -- that test has a documented single-frame timing assumption that is
# sensitive to extra awaited frames introduced immediately before it. Register this
# later in the sequence instead.
static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var randomized_ship: Ship = preload("res://scenes/ship/ship.tscn").instantiate()
	randomized_ship.randomize_loadout = true
	tree.root.add_child(randomized_ship)
	await tree.process_frame

	if randomized_ship.weapon_mounts.size() != 1:
		failures.append("randomize_loadout: expected ship.tscn to still have exactly 1 WeaponMount, got %d" % randomized_ship.weapon_mounts.size())
	elif randomized_ship.weapon_mounts[0].weapon == null:
		failures.append("randomize_loadout: expected the mount's weapon to be non-null after randomization")
	elif not ShipType.WEAPON_POOL.has(randomized_ship.weapon_mounts[0].weapon.resource_path):
		failures.append("randomize_loadout: expected the assigned weapon's resource_path to be a member of WEAPON_POOL, got %s" % randomized_ship.weapon_mounts[0].weapon.resource_path)

	if is_instance_valid(randomized_ship) and not randomized_ship.is_queued_for_deletion():
		randomized_ship.queue_free()

	return failures
