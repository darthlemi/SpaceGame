class_name StationData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var system_id: String = ""
# In-system position.
@export var position: Vector2 = Vector2.ZERO
@export var owner: CampaignFleet.Faction = CampaignFleet.Faction.NEUTRAL
# Sprite basename under assets/sprites/stations, e.g. "ring_2".
@export var art: String = ""
@export var economy: BaseEconomy = null
# Commodity.Type -> units at new_game(); unlisted goods start at Commodity.TARGET_STOCK.
@export var starting_stock: Dictionary = {}
# Role -> int target number of fleets.
@export var fleet_quota: Dictionary = {}
# Role -> Array of DangerTier.Variant ints: the fleets this station fields (see CampaignState.build_station_plans).
@export var fleet_plan: Dictionary = {}
# "role:variant" -> float seconds until the next replacement fleet of that variant.
@export var respawn_timers: Dictionary = {}

func is_home() -> bool:
	return owner == CampaignFleet.Faction.PLAYER

func texture_path() -> String:
	return "res://assets/sprites/stations/%s.png" % art
