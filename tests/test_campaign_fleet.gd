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

	return failures
