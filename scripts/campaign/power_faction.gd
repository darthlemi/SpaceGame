class_name PowerFaction
extends Resource

@export var faction_enum: CampaignFleet.Faction = CampaignFleet.Faction.NEUTRAL
@export var display_name: String = ""
@export var reputation: float = 60.0
@export var fine: int = 0
# Reputation the outstanding fine has cost; paying the fine restores it.
@export var fine_reputation: float = 0.0
