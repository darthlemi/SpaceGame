extends RefCounted

const FactionBaseScene = preload("res://scenes/campaign/faction_base.tscn")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var base: Area2D = FactionBaseScene.instantiate()
	if base.faction_enum != CampaignFleet.Faction.NEUTRAL:
		failures.append("FactionBase: expected default faction_enum == NEUTRAL, got %s" % base.faction_enum)

	base.faction_enum = CampaignFleet.Faction.FREEHOLD
	base.global_position = Vector2(150, 150)
	if base.faction_enum != CampaignFleet.Faction.FREEHOLD:
		failures.append("FactionBase: expected faction_enum to be settable")
	if base.global_position != Vector2(150, 150):
		failures.append("FactionBase: expected global_position to be settable")

	base.free()
	return failures
