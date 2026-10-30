extends Node

var player_fleet: CampaignFleet
var enemy_fleets: Array[CampaignFleet] = []
var active_enemy_fleet: CampaignFleet

func start_engagement(enemy_fleet: CampaignFleet) -> void:
	active_enemy_fleet = enemy_fleet

func resolve_engagement(player_survivors: Array[Dictionary], enemy_survivors: Array[Dictionary]) -> void:
	player_fleet.ship_compositions = player_survivors
	if active_enemy_fleet != null:
		active_enemy_fleet.ship_compositions = enemy_survivors
		if active_enemy_fleet.is_destroyed():
			enemy_fleets.erase(active_enemy_fleet)
	active_enemy_fleet = null

func reset() -> void:
	player_fleet = null
	enemy_fleets = []
	active_enemy_fleet = null
