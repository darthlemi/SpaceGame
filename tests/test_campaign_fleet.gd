extends RefCounted

const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

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

	var default_role_fleet := CampaignFleet.new()
	if default_role_fleet.role != CampaignFleet.Role.COMBAT:
		failures.append("role: expected default role == COMBAT, got %s" % default_role_fleet.role)

	var trader_role_fleet := CampaignFleet.new()
	trader_role_fleet.role = CampaignFleet.Role.TRADER
	if trader_role_fleet.role != CampaignFleet.Role.TRADER:
		failures.append("role: expected TRADER to be settable")

	return failures
