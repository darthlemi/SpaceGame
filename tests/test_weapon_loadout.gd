extends RefCounted

const CorvetteScene = preload("res://scenes/ship/ship_corvette.tscn")
const CapitalScene = preload("res://scenes/ship/ship_capital.tscn")
const GenericShipScene = preload("res://scenes/ship/ship.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	# Capital: 3 mounts, all non-null, pairwise distinct.
	var capital: Ship = CapitalScene.instantiate()
	tree.root.add_child(capital)
	await tree.process_frame

	if capital.weapon_mounts.size() != 3:
		failures.append("ship_capital.tscn: expected 3 WeaponMounts, got %d" % capital.weapon_mounts.size())
	else:
		var resource_paths: Array[String] = []
		for mount in capital.weapon_mounts:
			if mount.weapon == null:
				failures.append("ship_capital.tscn: expected every mount's weapon to be non-null")
			else:
				resource_paths.append(mount.weapon.resource_path)
		var unique_paths := {}
		for path in resource_paths:
			unique_paths[path] = true
		if unique_paths.size() != resource_paths.size():
			failures.append("ship_capital.tscn: expected 3 distinct weapons across its mounts, got %s" % resource_paths)

	if is_instance_valid(capital) and not capital.is_queued_for_deletion():
		capital.queue_free()

	# Corvette: 1 mount, non-null, pool member.
	var corvette: Ship = CorvetteScene.instantiate()
	tree.root.add_child(corvette)
	await tree.process_frame

	if corvette.weapon_mounts.size() != 1:
		failures.append("ship_corvette.tscn: expected 1 WeaponMount, got %d" % corvette.weapon_mounts.size())
	elif corvette.weapon_mounts[0].weapon == null:
		failures.append("ship_corvette.tscn: expected the mount's weapon to be non-null")
	elif not ShipType.WEAPON_POOL.has(corvette.weapon_mounts[0].weapon.resource_path):
		failures.append("ship_corvette.tscn: expected the assigned weapon to be a WEAPON_POOL member, got %s" % corvette.weapon_mounts[0].weapon.resource_path)

	if is_instance_valid(corvette) and not corvette.is_queued_for_deletion():
		corvette.queue_free()

	# Variety check: spawn 10 corvettes, expect at least 2 distinct weapons across them.
	var seen_across_spawns := {}
	for i in range(10):
		var c: Ship = CorvetteScene.instantiate()
		tree.root.add_child(c)
		await tree.process_frame
		if c.weapon_mounts.size() == 1 and c.weapon_mounts[0].weapon != null:
			seen_across_spawns[c.weapon_mounts[0].weapon.resource_path] = true
		c.queue_free()
	if seen_across_spawns.size() < 2:
		failures.append("ship_corvette.tscn: expected at least 2 distinct weapons across 10 spawns, got %s" % seen_across_spawns.keys())

	# Regression guard: the generic ship.tscn (randomize_loadout defaults false)
	# must keep its fixed kinetic_cannon.tres.
	var generic: Ship = GenericShipScene.instantiate()
	tree.root.add_child(generic)
	await tree.process_frame

	if generic.weapon_mounts.size() != 1:
		failures.append("ship.tscn: expected 1 WeaponMount, got %d" % generic.weapon_mounts.size())
	elif generic.weapon_mounts[0].weapon == null or generic.weapon_mounts[0].weapon.resource_path != "res://resources/weapons/kinetic_cannon.tres":
		failures.append("ship.tscn: expected the fixed kinetic_cannon.tres to be unaffected, got %s" % (generic.weapon_mounts[0].weapon.resource_path if generic.weapon_mounts[0].weapon else "null"))

	if is_instance_valid(generic) and not generic.is_queued_for_deletion():
		generic.queue_free()

	return failures
