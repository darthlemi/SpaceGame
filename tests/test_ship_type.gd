extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []

	if ShipType.kind_of({}) != ShipType.Kind.CORVETTE:
		failures.append("kind_of: expected a dict missing 'ship_type' to default to CORVETTE")
	if ShipType.kind_of({"ship_type": ShipType.Kind.FREIGHTER}) != ShipType.Kind.FREIGHTER:
		failures.append("kind_of: expected an explicit ship_type key to be respected")

	if ShipType.cargo_capacity_for(ShipType.Kind.CORVETTE) != 20.0:
		failures.append("cargo_capacity_for: expected Corvette == 20.0, got %s" % ShipType.cargo_capacity_for(ShipType.Kind.CORVETTE))
	if ShipType.cargo_capacity_for(ShipType.Kind.FREIGHTER) != 60.0:
		failures.append("cargo_capacity_for: expected Freighter == 60.0, got %s" % ShipType.cargo_capacity_for(ShipType.Kind.FREIGHTER))
	if ShipType.cargo_capacity_for(ShipType.Kind.CAPITAL) != 20.0:
		failures.append("cargo_capacity_for: expected Capital == 20.0, got %s" % ShipType.cargo_capacity_for(ShipType.Kind.CAPITAL))

	for kind in ShipType.Kind.values():
		if ShipType.crew_for(kind) <= 0:
			failures.append("crew_for: expected a positive crew complement for kind %s" % kind)
		if ShipType.fuel_burn_for(kind) <= 0.0:
			failures.append("fuel_burn_for: expected a positive fuel burn for kind %s" % kind)
	if ShipType.crew_for(ShipType.Kind.CAPITAL) <= ShipType.crew_for(ShipType.Kind.CORVETTE):
		failures.append("crew_for: expected Capital to need more crew than Corvette")

	# base_speed_for/BASE_STATS.turn_rate drive the campaign-layer travel speed, which is
	# independent of the in-combat ShipEngine tuning on the ship scenes (Task 4 retuned the
	# latter for slower, heavier combat pacing without touching BASE_STATS) -- so these only
	# check the values are sane, not that they match the scene.
	for kind in ShipType.Kind.values():
		var scene_ship: Ship = ShipType.scene_for(kind).instantiate()
		var scene_engine: ShipEngine = scene_ship.get_node("Engine")
		if ShipType.base_speed_for(kind) <= 0.0:
			failures.append("base_speed_for(%s): expected a positive campaign travel speed, got %s" % [kind, ShipType.base_speed_for(kind)])
		if ShipType.BASE_STATS[kind]["turn_rate"] <= 0.0:
			failures.append("BASE_STATS turn_rate(%s): expected a positive campaign turn rate, got %s" % [kind, ShipType.BASE_STATS[kind]["turn_rate"]])
		if scene_engine.max_speed <= 0.0 or scene_engine.turn_rate <= 0.0:
			failures.append("scene Engine(%s): expected positive max_speed/turn_rate, got %s/%s" % [kind, scene_engine.max_speed, scene_engine.turn_rate])
		scene_ship.free()

	var comp := ShipType.new_composition(ShipType.Kind.CAPITAL)
	if comp["ship_type"] != ShipType.Kind.CAPITAL:
		failures.append("new_composition: expected ship_type == CAPITAL, got %s" % comp["ship_type"])
	if comp["max_hp"] != 220.0 or comp["current_hp"] != 220.0:
		failures.append("new_composition: expected Capital max_hp/current_hp == 220.0, got %s" % comp)
	if comp["max_shield"] != 80.0 or comp["current_shield"] != 80.0:
		failures.append("new_composition: expected Capital max_shield/current_shield == 80.0, got %s" % comp)

	var corvette_comp := ShipType.new_composition(ShipType.Kind.CORVETTE)
	if corvette_comp["max_hp"] != 60.0 or corvette_comp["max_shield"] != 20.0:
		failures.append("new_composition: expected Corvette max_hp==60.0/max_shield==20.0, got %s" % corvette_comp)

	var freighter_comp := ShipType.new_composition(ShipType.Kind.FREIGHTER)
	if freighter_comp["max_hp"] != 80.0 or freighter_comp["max_shield"] != 20.0:
		failures.append("new_composition: expected Freighter max_hp==80.0/max_shield==20.0, got %s" % freighter_comp)

	if not is_equal_approx(corvette_comp["engine_max_hp"], 25.0):
		failures.append("new_composition: expected corvette engine_max_hp 25.0, got %s" % corvette_comp["engine_max_hp"])
	if corvette_comp["weapon_mount_max_hp"] != [15.0]:
		failures.append("new_composition: expected corvette weapon_mount_max_hp [15.0], got %s" % corvette_comp["weapon_mount_max_hp"])

	if freighter_comp["weapon_mount_max_hp"] != []:
		failures.append("new_composition: expected freighter weapon_mount_max_hp [] (unarmed), got %s" % freighter_comp["weapon_mount_max_hp"])

	if comp["weapon_mount_max_hp"] != [30.0, 30.0, 30.0]:
		failures.append("new_composition: expected capital weapon_mount_max_hp [30.0, 30.0, 30.0], got %s" % comp["weapon_mount_max_hp"])
	if comp["weapon_mount_current_hp"] != comp["weapon_mount_max_hp"]:
		failures.append("new_composition: expected weapon_mount_current_hp to start equal to weapon_mount_max_hp")

	if ShipType.WEAPON_POOL.size() != 14:
		failures.append("WEAPON_POOL: expected 14 entries, got %d" % ShipType.WEAPON_POOL.size())
	var seen_paths := {}
	for path in ShipType.WEAPON_POOL:
		if seen_paths.has(path):
			failures.append("WEAPON_POOL: duplicate entry %s" % path)
		seen_paths[path] = true
		if not ResourceLoader.exists(path):
			failures.append("WEAPON_POOL: path does not exist: %s" % path)
		if path.contains("drone_"):
			failures.append("WEAPON_POOL: drone-only weapon should not appear in the ship pool: %s" % path)

	if ShipType.points_budget_for(ShipType.Kind.CORVETTE) != 20:
		failures.append("points_budget_for: expected corvette 20, got %s" % ShipType.points_budget_for(ShipType.Kind.CORVETTE))
	if ShipType.points_budget_for(ShipType.Kind.CAPITAL) != 40:
		failures.append("points_budget_for: expected capital 40, got %s" % ShipType.points_budget_for(ShipType.Kind.CAPITAL))

	if comp["weapon_mount_items"] != ["", "", ""]:
		failures.append("new_composition: expected capital weapon_mount_items == 3 empty strings, got %s" % comp["weapon_mount_items"])
	if comp["shield_item"] != "" or comp["engine_item"] != "":
		failures.append("new_composition: expected shield_item/engine_item to default to empty string")

	var test_comp := ShipType.new_composition(ShipType.Kind.CORVETTE)
	if ShipType.equipped_path(test_comp, ShipType.SlotType.WEAPON, 0) != "":
		failures.append("equipped_path: expected empty string for a fresh composition's weapon slot")
	ShipType.set_equipped_path(test_comp, ShipType.SlotType.WEAPON, 0, "res://resources/weapons/railgun.tres")
	if ShipType.equipped_path(test_comp, ShipType.SlotType.WEAPON, 0) != "res://resources/weapons/railgun.tres":
		failures.append("set_equipped_path/equipped_path: expected weapon slot to round-trip the assigned path")
	if ShipType.points_of_path("res://resources/weapons/railgun.tres") != PartRarity.points_for(PartRarity.Tier.RARE):
		failures.append("points_of_path: expected railgun (RARE) to cost %s points, got %s" % [PartRarity.points_for(PartRarity.Tier.RARE), ShipType.points_of_path("res://resources/weapons/railgun.tres")])
	if ShipType.points_used(test_comp) != PartRarity.points_for(PartRarity.Tier.RARE):
		failures.append("points_used: expected a corvette with only a RARE weapon equipped to use exactly that many points, got %s" % ShipType.points_used(test_comp))

	ShipType.set_equipped_path(test_comp, ShipType.SlotType.SHIELD, 0, "res://resources/shields/shield_dominion_aegis.tres")
	if ShipType.equipped_path(test_comp, ShipType.SlotType.SHIELD, 0) != "res://resources/shields/shield_dominion_aegis.tres":
		failures.append("set_equipped_path/equipped_path: expected shield slot to round-trip the assigned path")

	# Test set_equipped_path safety: setting weapon on a composition with missing/undersized weapon_mount_items
	var unsafe_comp := {"ship_type": ShipType.Kind.CORVETTE}
	ShipType.set_equipped_path(unsafe_comp, ShipType.SlotType.WEAPON, 0, "res://resources/weapons/kinetic_cannon.tres")
	if ShipType.equipped_path(unsafe_comp, ShipType.SlotType.WEAPON, 0) != "res://resources/weapons/kinetic_cannon.tres":
		failures.append("set_equipped_path: expected array resize to allow setting on missing weapon_mount_items")

	return failures
