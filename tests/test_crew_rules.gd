extends RefCounted

static func _ship(kind: ShipType.Kind, crew: int, deploy: bool = true, flagship: bool = false) -> Dictionary:
	var comp := ShipType.new_composition(kind)
	comp["crew"] = crew
	comp["deploy"] = deploy
	comp["flagship"] = flagship
	return comp

static func _crews(comps: Array[Dictionary]) -> Array[int]:
	var result: Array[int] = []
	for comp in comps:
		result.append(CrewRules.crew_of(comp))
	return result

static func _total(comps: Array[Dictionary]) -> int:
	var sum := 0
	for comp in comps:
		sum += CrewRules.crew_of(comp)
	return sum

static func run() -> Array[String]:
	var failures: Array[String] = []

	var expected_deploy_min := {12: 4, 6: 2, 40: 12}
	for complement in expected_deploy_min:
		var got := CrewRules.deploy_min_for(complement)
		if got != expected_deploy_min[complement]:
			failures.append("deploy_min_for(%d): expected %d, got %d" % [complement, expected_deploy_min[complement], got])

	var expected_efficiency := [[12.0, 12, 1.0], [6.0, 12, 0.75], [0.0, 12, 0.5], [5.0, 0, 1.0], [24.0, 12, 1.0]]
	for case in expected_efficiency:
		var got := CrewRules.efficiency_for(case[0], case[1])
		if not is_equal_approx(got, case[2]):
			failures.append("efficiency_for(%s, %d): expected %s, got %s" % [case[0], case[1], case[2], got])

	if CrewRules.is_armed(ShipType.new_composition(ShipType.Kind.FREIGHTER)):
		failures.append("is_armed: expected a freighter to be unarmed")
	if not CrewRules.is_armed(ShipType.new_composition(ShipType.Kind.CORVETTE)):
		failures.append("is_armed: expected a fresh corvette to be armed")
	var mountless := ShipType.new_composition(ShipType.Kind.CORVETTE)
	mountless["weapon_mount_current_hp"] = [0.0]
	if CrewRules.is_armed(mountless):
		failures.append("is_armed: expected a corvette with every mount at 0 hp to be unarmed")
	var partial := ShipType.new_composition(ShipType.Kind.CAPITAL)
	partial["weapon_mount_current_hp"] = [0.0, 0.0, 5.0]
	if not CrewRules.is_armed(partial):
		failures.append("is_armed: expected a capital with one live mount to be armed")
	if not CrewRules.is_armed({"ship_type": ShipType.Kind.CORVETTE}):
		failures.append("is_armed: expected a bootstrap corvette dict (no mount hp key) to be armed")
	if CrewRules.is_armed({"ship_type": ShipType.Kind.FREIGHTER}):
		failures.append("is_armed: expected a bootstrap freighter dict to be unarmed")

	var corvette_base := ShipType.base_speed_for(ShipType.Kind.CORVETTE)
	var bare_half := {"ship_type": ShipType.Kind.CORVETTE, "crew": 6}
	if not is_equal_approx(CrewRules.comp_top_speed(bare_half), corvette_base * 0.75):
		failures.append("comp_top_speed: expected a half-crew bare corvette at base * 0.75, got %s" % CrewRules.comp_top_speed(bare_half))
	var damaged_engine := ShipType.new_composition(ShipType.Kind.CORVETTE)
	damaged_engine["engine_current_hp"] = damaged_engine["engine_max_hp"] * 0.5
	if not is_equal_approx(CrewRules.comp_top_speed(damaged_engine), corvette_base * 0.5):
		failures.append("comp_top_speed: expected a half-hp engine at base * 0.5, got %s" % CrewRules.comp_top_speed(damaged_engine))
	var racer := ShipType.new_composition(ShipType.Kind.CORVETTE)
	racer["engine_item"] = "res://resources/engines/engine_freehold_racer.tres"
	if not is_equal_approx(CrewRules.comp_top_speed(racer), 300.0):
		failures.append("comp_top_speed: expected the equipped engine's max_speed 300, got %s" % CrewRules.comp_top_speed(racer))

	var capital_no_key := {"ship_type": ShipType.Kind.CAPITAL}
	if CrewRules.crew_of(capital_no_key) != 40:
		failures.append("crew_of: expected 40 for a capital with no crew key, got %d" % CrewRules.crew_of(capital_no_key))
	CrewRules.set_crew(capital_no_key, 99)
	if CrewRules.crew_of(capital_no_key) != 40:
		failures.append("set_crew(99): expected clamp to 40, got %d" % CrewRules.crew_of(capital_no_key))
	CrewRules.set_crew(capital_no_key, -3)
	if CrewRules.crew_of(capital_no_key) != 0:
		failures.append("set_crew(-3): expected clamp to 0, got %d" % CrewRules.crew_of(capital_no_key))

	var half := _ship(ShipType.Kind.CORVETTE, 6)
	if not is_equal_approx(CrewRules.crew_fraction(half), 0.5):
		failures.append("crew_fraction: expected 0.5 for 6/12, got %s" % CrewRules.crew_fraction(half))
	if ShipType.new_composition(ShipType.Kind.CAPITAL).get("crew", -1) != 40:
		failures.append("new_composition: expected crew 40 for a capital")

	# deploy_indices
	var strong_weak: Array[Dictionary] = [_ship(ShipType.Kind.CORVETTE, 12), _ship(ShipType.Kind.CORVETTE, 2)]
	if CrewRules.deploy_indices(strong_weak) != [0]:
		failures.append("deploy_indices: expected [0] when only ship 0 meets the minimum, got %s" % [CrewRules.deploy_indices(strong_weak)])
	var none_meet: Array[Dictionary] = [_ship(ShipType.Kind.CORVETTE, 2), _ship(ShipType.Kind.CAPITAL, 5)]
	if CrewRules.deploy_indices(none_meet) != [1]:
		failures.append("deploy_indices: expected [1] (highest-crew wanted ship), got %s" % [CrewRules.deploy_indices(none_meet)])
	var none_want: Array[Dictionary] = [_ship(ShipType.Kind.CORVETTE, 12, false), _ship(ShipType.Kind.CAPITAL, 40, false, true)]
	if CrewRules.deploy_indices(none_want) != [1]:
		failures.append("deploy_indices: expected flagship [1] when none want to deploy, got %s" % [CrewRules.deploy_indices(none_want)])
	var empty_fleet: Array[Dictionary] = []
	if CrewRules.deploy_indices(empty_fleet) != []:
		failures.append("deploy_indices: expected [] for an empty fleet")

	# add_crew
	var add_fleet: Array[Dictionary] = [_ship(ShipType.Kind.CORVETTE, 6), _ship(ShipType.Kind.FREIGHTER, 6)]
	var added := CrewRules.add_crew(add_fleet, 10)
	if added != 6 or _crews(add_fleet) != [12, 6]:
		failures.append("add_crew: expected 6 added -> [12, 6], got %d -> %s" % [added, _crews(add_fleet)])
	if CrewRules.free_berths(add_fleet) != 0:
		failures.append("free_berths: expected 0 after filling, got %d" % CrewRules.free_berths(add_fleet))

	# remove_crew
	var remove_fleet: Array[Dictionary] = [_ship(ShipType.Kind.CAPITAL, 20, true, true), _ship(ShipType.Kind.CORVETTE, 6)]
	var removed := CrewRules.remove_crew(remove_fleet, 30, 0, 12)
	if removed != 14 or _crews(remove_fleet) != [12, 0]:
		failures.append("remove_crew: expected 14 removed -> [12, 0], got %d -> %s" % [removed, _crews(remove_fleet)])

	# set_ship_crew
	var move_fleet: Array[Dictionary] = [_ship(ShipType.Kind.CORVETTE, 4), _ship(ShipType.Kind.CAPITAL, 40), _ship(ShipType.Kind.FREIGHTER, 6)]
	CrewRules.set_ship_crew(move_fleet, 0, 12)
	if CrewRules.crew_of(move_fleet[0]) != 12 or _total(move_fleet) != 50:
		failures.append("set_ship_crew: expected corvette 12 and total 50, got %s" % [_crews(move_fleet)])

	# balance
	var balance_fleet: Array[Dictionary] = [_ship(ShipType.Kind.CAPITAL, 40), _ship(ShipType.Kind.CORVETTE, 0), _ship(ShipType.Kind.FREIGHTER, 0)]
	CrewRules.balance(balance_fleet)
	if _total(balance_fleet) != 40:
		failures.append("balance: expected total 40, got %d" % _total(balance_fleet))
	for comp in balance_fleet:
		var ideal := 40.0 / 58.0 * CrewRules.complement(comp)
		if absf(CrewRules.crew_of(comp) - ideal) > 1.0:
			failures.append("balance: expected crew within 1 of %s, got %d" % [ideal, CrewRules.crew_of(comp)])

	# Bootstrap-style dicts (no crew/deploy/flagship keys)
	var bare_corvette := {"ship_type": ShipType.Kind.CORVETTE, "max_hp": 100.0}
	if not CrewRules.wants_deploy(bare_corvette) or CrewRules.is_flagship(bare_corvette):
		failures.append("bootstrap dict: expected wants_deploy true and is_flagship false")
	var fleet := CampaignFleet.new()
	fleet.ship_compositions.assign([
		{"ship_type": ShipType.Kind.CORVETTE},
		{"ship_type": ShipType.Kind.CAPITAL},
		{"ship_type": ShipType.Kind.FREIGHTER},
	])
	fleet.ensure_flagship()
	if fleet.flagship_index() != 1:
		failures.append("ensure_flagship: expected index 1 (capital), got %d" % fleet.flagship_index())
	fleet.set_flagship(2)
	if fleet.flagship_index() != 2 or CrewRules.is_flagship(fleet.ship_compositions[1]):
		failures.append("set_flagship: expected only index 2 flagged")

	return failures
