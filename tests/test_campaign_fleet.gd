extends RefCounted

const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")
const Commodity = preload("res://scripts/campaign/commodity.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var fleet := CampaignFleet.new()
	fleet.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 60.0, "max_shield": 50.0, "current_shield": 20.0},
		{"max_hp": 100.0, "current_hp": 0.0, "max_shield": 50.0, "current_shield": 0.0},
	]

	if fleet.total_strength() != 80.0:
		failures.append("total_strength: expected 80.0, got %s" % fleet.total_strength())
	if fleet.is_destroyed():
		failures.append("is_destroyed: expected false with one ship alive")

	fleet.repair_to_full()
	for comp in fleet.ship_compositions:
		if comp["current_hp"] != comp["max_hp"] or comp["current_shield"] != comp["max_shield"]:
			failures.append("repair_to_full: expected all ships at max, got %s" % comp)

	var wiped := CampaignFleet.new()
	wiped.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 0.0, "max_shield": 50.0, "current_shield": 0.0},
	]
	if not wiped.is_destroyed():
		failures.append("is_destroyed: expected true when all ships at 0 hp")

	var dominion_fleet := CampaignFleet.new()
	dominion_fleet.faction = CampaignFleet.Faction.DOMINION
	if dominion_fleet.faction != CampaignFleet.Faction.DOMINION:
		failures.append("Faction enum: expected DOMINION to be a valid value")

	var freehold_fleet := CampaignFleet.new()
	freehold_fleet.faction = CampaignFleet.Faction.FREEHOLD
	if freehold_fleet.faction != CampaignFleet.Faction.FREEHOLD:
		failures.append("Faction enum: expected FREEHOLD to be a valid value")

	var damaged := CampaignFleet.new()
	damaged.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
	]
	damaged.apply_fractional_damage(0.5)
	var comp: Dictionary = damaged.ship_compositions[0]
	if abs(comp["current_hp"] - 50.0) > 0.001:
		failures.append("apply_fractional_damage: expected current_hp halved to 50.0, got %s" % comp["current_hp"])
	if abs(comp["current_shield"] - 25.0) > 0.001:
		failures.append("apply_fractional_damage: expected current_shield halved to 25.0, got %s" % comp["current_shield"])

	var overkill := CampaignFleet.new()
	overkill.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 10.0, "max_shield": 50.0, "current_shield": 5.0},
	]
	overkill.apply_fractional_damage(1.0)
	var overkill_comp: Dictionary = overkill.ship_compositions[0]
	if overkill_comp["current_hp"] != 0.0:
		failures.append("apply_fractional_damage: expected current_hp clamped to 0.0 at fraction 1.0, got %s" % overkill_comp["current_hp"])
	if overkill_comp["current_shield"] != 0.0:
		failures.append("apply_fractional_damage: expected current_shield clamped to 0.0 at fraction 1.0, got %s" % overkill_comp["current_shield"])

	var cargo_fleet := CampaignFleet.new()
	cargo_fleet.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
	]
	if cargo_fleet.cargo_capacity() != 40.0:
		failures.append("cargo_capacity: expected 40.0 for a 2-ship fleet, got %s" % cargo_fleet.cargo_capacity())
	if cargo_fleet.cargo_total() != 0.0:
		failures.append("cargo_total: expected 0.0 with empty cargo, got %s" % cargo_fleet.cargo_total())

	cargo_fleet.cargo = {0: 10.0, 1: 5.0}
	if cargo_fleet.cargo_total() != 15.0:
		failures.append("cargo_total: expected 15.0 with cargo {0:10.0, 1:5.0}, got %s" % cargo_fleet.cargo_total())

	var mixed_cargo_fleet := CampaignFleet.new()
	mixed_cargo_fleet.ship_compositions = [
		ShipType.new_composition(ShipType.Kind.FREIGHTER),
		ShipType.new_composition(ShipType.Kind.CORVETTE),
	]
	if mixed_cargo_fleet.cargo_capacity() != 80.0:
		failures.append("cargo_capacity: expected 80.0 for 1 Freighter (60.0) + 1 Corvette (20.0), got %s" % mixed_cargo_fleet.cargo_capacity())

	var default_role_fleet := CampaignFleet.new()
	if default_role_fleet.role != CampaignFleet.Role.COMBAT:
		failures.append("role: expected default role == COMBAT, got %s" % default_role_fleet.role)

	var trader_role_fleet := CampaignFleet.new()
	trader_role_fleet.role = CampaignFleet.Role.TRADER
	if trader_role_fleet.role != CampaignFleet.Role.TRADER:
		failures.append("role: expected TRADER to be settable")

	var parts_fleet := CampaignFleet.new()
	parts_fleet.ship_compositions = [ShipType.new_composition(ShipType.Kind.FREIGHTER)]
	parts_fleet.cargo = {Commodity.Type.ORE: 5.0}
	parts_fleet.part_inventory = ["res://resources/weapons/kinetic_cannon.tres", "res://resources/weapons/mass_driver.tres"]
	if parts_fleet.cargo_total() != 7.0:
		failures.append("cargo_total: expected commodities (5) + part_inventory (2) == 7.0, got %s" % parts_fleet.cargo_total())

	var fuel_fleet := CampaignFleet.new()
	fuel_fleet.speed = 100.0
	fuel_fleet.ship_compositions = [ShipType.new_composition(ShipType.Kind.CORVETTE), ShipType.new_composition(ShipType.Kind.CAPITAL)]
	# new_composition starts fully crewed, so actual crew equals the class complements here.
	var expected_crew := ShipType.crew_for(ShipType.Kind.CORVETTE) + ShipType.crew_for(ShipType.Kind.CAPITAL)
	if fuel_fleet.crew_total() != expected_crew:
		failures.append("crew_total: expected %d, got %d" % [expected_crew, fuel_fleet.crew_total()])

	var crewed_fleet := CampaignFleet.new()
	crewed_fleet.ship_compositions = [
		{"ship_type": ShipType.Kind.CORVETTE, "crew": 12},
		{"ship_type": ShipType.Kind.FREIGHTER},
	]
	if crewed_fleet.crew_total() != 18:
		failures.append("crew_total: expected 18 (12 + missing-key freighter 6), got %d" % crewed_fleet.crew_total())
	if crewed_fleet.crew_capacity() != 18:
		failures.append("crew_capacity: expected 18, got %d" % crewed_fleet.crew_capacity())
	if crewed_fleet.has_uncrewed_ship():
		failures.append("has_uncrewed_ship: expected false when all ships have crew")

	var skeleton_fleet := CampaignFleet.new()
	skeleton_fleet.speed = 100.0
	skeleton_fleet.cargo = {Commodity.Type.FUEL: 10.0}
	skeleton_fleet.ship_compositions = [
		{"ship_type": ShipType.Kind.CORVETTE, "crew": 0},
		{"ship_type": ShipType.Kind.FREIGHTER},
	]
	if not skeleton_fleet.has_uncrewed_ship():
		failures.append("has_uncrewed_ship: expected true with a crew-0 ship")
	var crawl_speed := 100.0 * CampaignFleet.EMPTY_FUEL_SPEED_FACTOR
	if not is_equal_approx(skeleton_fleet.travel_speed(), crawl_speed):
		failures.append("travel_speed: expected crawl with an uncrewed ship and fuel, got %s" % skeleton_fleet.travel_speed())
	skeleton_fleet.cargo = {}
	if not is_equal_approx(skeleton_fleet.travel_speed(), crawl_speed):
		failures.append("travel_speed: expected crawl (not squared) with no fuel and an uncrewed ship, got %s" % skeleton_fleet.travel_speed())
	var expected_burn := (ShipType.fuel_burn_for(ShipType.Kind.CORVETTE) + ShipType.fuel_burn_for(ShipType.Kind.CAPITAL)) / CampaignFleet.FUEL_BURN_DISTANCE
	if not is_equal_approx(fuel_fleet.fuel_burn_per_distance(), expected_burn):
		failures.append("fuel_burn_per_distance: expected %s, got %s" % [expected_burn, fuel_fleet.fuel_burn_per_distance()])
	if not is_equal_approx(fuel_fleet.fuel_burn_rate(), expected_burn * 100.0):
		failures.append("fuel_burn_rate: expected burn/distance * speed, got %s" % fuel_fleet.fuel_burn_rate())

	if fuel_fleet.fuel_amount() != 0.0:
		failures.append("fuel_amount: expected 0.0 with no Fuel cargo, got %s" % fuel_fleet.fuel_amount())
	if not is_equal_approx(fuel_fleet.travel_speed(), 100.0 * CampaignFleet.EMPTY_FUEL_SPEED_FACTOR):
		failures.append("travel_speed: expected crawl speed with no fuel, got %s" % fuel_fleet.travel_speed())
	fuel_fleet.consume_fuel(500.0)
	if fuel_fleet.cargo.has(Commodity.Type.FUEL):
		failures.append("consume_fuel: expected no Fuel key created when there is no fuel to burn")

	fuel_fleet.cargo = {Commodity.Type.FUEL: 10.0}
	if fuel_fleet.travel_speed() != 100.0:
		failures.append("travel_speed: expected full speed with fuel, got %s" % fuel_fleet.travel_speed())
	fuel_fleet.consume_fuel(1000.0)
	if not is_equal_approx(fuel_fleet.fuel_amount(), 10.0 - expected_burn * 1000.0):
		failures.append("consume_fuel: expected %s left after 1000 units, got %s" % [10.0 - expected_burn * 1000.0, fuel_fleet.fuel_amount()])
	var fuel_before_negative := fuel_fleet.fuel_amount()
	fuel_fleet.consume_fuel(-50.0)
	if fuel_fleet.fuel_amount() != fuel_before_negative:
		failures.append("consume_fuel: expected negative distance to be ignored, got %s" % fuel_fleet.fuel_amount())
	fuel_fleet.consume_fuel(100000.0)
	if fuel_fleet.fuel_amount() != 0.0:
		failures.append("consume_fuel: expected fuel clamped at 0.0, got %s" % fuel_fleet.fuel_amount())

	var warp_fleet := CampaignFleet.new()
	if warp_fleet.is_warping():
		failures.append("is_warping: expected false by default")
	warp_fleet.start_warp("x")
	if not warp_fleet.is_warping() or warp_fleet.warp_remaining != 3.0 or warp_fleet.warp_target != "x":
		failures.append("start_warp: expected warping 3.0 to x, got %s / %s" % [warp_fleet.warp_remaining, warp_fleet.warp_target])
	warp_fleet.cancel_warp()
	if warp_fleet.is_warping() or warp_fleet.warp_target != "":
		failures.append("cancel_warp: expected cleared warp state")

	var strength_fleet := CampaignFleet.new()
	strength_fleet.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 10.0, "max_shield": 50.0, "current_shield": 0.0},
		{"max_hp": 60.0, "current_hp": 0.0, "max_shield": 20.0, "current_shield": 5.0},
	]
	if strength_fleet.max_strength() != 230.0:
		failures.append("max_strength: expected 230.0 ignoring damage, got %s" % strength_fleet.max_strength())

	return failures
