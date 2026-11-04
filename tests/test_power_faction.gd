extends RefCounted

const PowerFaction = preload("res://scripts/campaign/power_faction.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var faction := PowerFaction.new()
	if faction.faction_enum != CampaignFleet.Faction.NEUTRAL:
		failures.append("PowerFaction: expected default faction_enum == NEUTRAL, got %s" % faction.faction_enum)
	if faction.reputation != 60.0:
		failures.append("PowerFaction: expected default reputation == 60.0, got %s" % faction.reputation)

	faction.faction_enum = CampaignFleet.Faction.DOMINION
	faction.display_name = "Dominion"
	faction.reputation = 25.0

	if faction.faction_enum != CampaignFleet.Faction.DOMINION:
		failures.append("PowerFaction: expected faction_enum to be settable")
	if faction.display_name != "Dominion":
		failures.append("PowerFaction: expected display_name to be settable")
	if faction.reputation != 25.0:
		failures.append("PowerFaction: expected reputation to be settable")

	var fresh := PowerFaction.new()
	if fresh.fine != 0 or fresh.fine_reputation != 0.0:
		failures.append("PowerFaction: expected no outstanding fine by default, got fine=%s rep=%s" % [fresh.fine, fresh.fine_reputation])

	return failures
