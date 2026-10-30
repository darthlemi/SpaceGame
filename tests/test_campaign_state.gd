extends RefCounted

const CampaignState = preload("res://scripts/campaign/campaign_state.gd")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var state := CampaignState.new()
	var player := CampaignFleet.new()
	player.ship_compositions = [{"max_hp": 100.0, "current_hp": 50.0, "max_shield": 50.0, "current_shield": 10.0}]
	var enemy := CampaignFleet.new()
	enemy.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	state.player_fleet = player
	state.enemy_fleets = [enemy]

	state.start_engagement(enemy)
	if state.active_enemy_fleet != enemy:
		failures.append("start_engagement: expected active_enemy_fleet == enemy")

	state.resolve_engagement(
		[{"max_hp": 100.0, "current_hp": 30.0, "max_shield": 50.0, "current_shield": 0.0}],
		[]
	)
	if player.ship_compositions[0]["current_hp"] != 30.0:
		failures.append("resolve_engagement: expected player fleet updated with survivor data")
	if not enemy.is_destroyed():
		failures.append("resolve_engagement: expected enemy fleet marked destroyed with empty survivors")
	if state.enemy_fleets.has(enemy):
		failures.append("resolve_engagement: expected destroyed enemy fleet removed from enemy_fleets")
	if state.active_enemy_fleet != null:
		failures.append("resolve_engagement: expected active_enemy_fleet cleared after resolution")

	state.reset()
	if state.player_fleet != null or not state.enemy_fleets.is_empty() or state.active_enemy_fleet != null:
		failures.append("reset: expected all state cleared")

	return failures
