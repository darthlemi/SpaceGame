class_name PowerFaction
extends Resource

@export var faction_enum: CampaignFleet.Faction = CampaignFleet.Faction.NEUTRAL
@export var display_name: String = ""
@export var reputation: float = 60.0
@export var base_position: Vector2 = Vector2.ZERO
@export var economy: BaseEconomy = null
