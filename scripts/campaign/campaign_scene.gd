extends Node2D

const CampaignFleetIconScene = preload("res://scenes/campaign/campaign_fleet_icon.tscn")
const HomeBaseScene = preload("res://scenes/campaign/home_base.tscn")
const FactionBaseScene = preload("res://scenes/campaign/faction_base.tscn")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

const HOME_BASE_POSITION := Vector2(600, 400)

var player_icon: CampaignFleetIcon
var enemy_icons: Array[CampaignFleetIcon] = []

@onready var engage_prompt: Control = $EngagePrompt

var _pending_enemy_icon: CampaignFleetIcon

func _ready() -> void:
	if CampaignState.player_fleet == null:
		_bootstrap_default_campaign()

	var base: Area2D = HomeBaseScene.instantiate()
	base.global_position = HOME_BASE_POSITION
	add_child(base)

	for faction in CampaignState.factions:
		var faction_base: Area2D = FactionBaseScene.instantiate()
		faction_base.faction_enum = faction.faction_enum
		faction_base.global_position = faction.base_position
		add_child(faction_base)

	player_icon = _spawn_icon(CampaignState.player_fleet, CampaignFleetIcon.BehaviorType.PLAYER)
	player_icon.area_entered.connect(_on_player_area_entered)
	player_icon.area_exited.connect(_on_player_area_exited)

	for enemy_fleet in CampaignState.enemy_fleets:
		var behavior := _behavior_for_faction(enemy_fleet.faction)
		var icon := _spawn_icon(enemy_fleet, behavior)
		icon.player_target = player_icon
		icon.area_entered.connect(_on_enemy_area_entered.bind(icon))
		enemy_icons.append(icon)

	engage_prompt.visible = false
	engage_prompt.get_node("EngageButton").pressed.connect(_on_engage_pressed)
	engage_prompt.get_node("DisengageButton").pressed.connect(_on_disengage_pressed)

	CampaignState.skirmish_resolved.connect(_on_skirmish_resolved)

func _bootstrap_default_campaign() -> void:
	var player := CampaignFleet.new()
	player.faction = CampaignFleet.Faction.PLAYER
	player.position = HOME_BASE_POSITION
	player.speed = 120.0
	player.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
	]
	CampaignState.player_fleet = player

	var pirate := CampaignFleet.new()
	pirate.faction = CampaignFleet.Faction.PIRATE
	pirate.position = Vector2(1000, 200)
	pirate.speed = 100.0
	pirate.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var trader := CampaignFleet.new()
	trader.faction = CampaignFleet.Faction.TRADER
	trader.position = Vector2(200, 550)
	trader.speed = 80.0
	trader.ship_compositions = [{"max_hp": 60.0, "current_hp": 60.0, "max_shield": 20.0, "current_shield": 20.0}]

	var patrol := CampaignFleet.new()
	patrol.faction = CampaignFleet.Faction.NEUTRAL
	patrol.position = Vector2(900, 450)
	patrol.speed = 90.0
	patrol.ship_compositions = [{"max_hp": 80.0, "current_hp": 80.0, "max_shield": 30.0, "current_shield": 30.0}]

	var dominion_faction := PowerFaction.new()
	dominion_faction.faction_enum = CampaignFleet.Faction.DOMINION
	dominion_faction.display_name = "Dominion"
	dominion_faction.reputation = 60.0
	dominion_faction.base_position = Vector2(1000, 550)

	var freehold_faction := PowerFaction.new()
	freehold_faction.faction_enum = CampaignFleet.Faction.FREEHOLD
	freehold_faction.display_name = "Freehold"
	freehold_faction.reputation = 60.0
	freehold_faction.base_position = Vector2(150, 150)

	CampaignState.factions = [dominion_faction, freehold_faction]
	CampaignState.factions_at_war = true

	var dominion_fleet := CampaignFleet.new()
	dominion_fleet.faction = CampaignFleet.Faction.DOMINION
	dominion_fleet.position = Vector2(1000, 480)
	dominion_fleet.speed = 100.0
	dominion_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var freehold_fleet := CampaignFleet.new()
	freehold_fleet.faction = CampaignFleet.Faction.FREEHOLD
	freehold_fleet.position = Vector2(200, 200)
	freehold_fleet.speed = 100.0
	freehold_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	CampaignState.enemy_fleets = [pirate, trader, patrol, dominion_fleet, freehold_fleet]

func _behavior_for_faction(faction: CampaignFleet.Faction) -> CampaignFleetIcon.BehaviorType:
	match faction:
		CampaignFleet.Faction.PIRATE:
			return CampaignFleetIcon.BehaviorType.PIRATE
		CampaignFleet.Faction.TRADER:
			return CampaignFleetIcon.BehaviorType.TRADER
		CampaignFleet.Faction.DOMINION, CampaignFleet.Faction.FREEHOLD:
			return CampaignFleetIcon.BehaviorType.PIRATE if _is_faction_hostile(faction) else CampaignFleetIcon.BehaviorType.PATROL
		_:
			return CampaignFleetIcon.BehaviorType.PATROL

func _is_faction_hostile(faction: CampaignFleet.Faction) -> bool:
	for power_faction in CampaignState.factions:
		if power_faction.faction_enum == faction:
			return power_faction.reputation < CampaignState.HOSTILE_REPUTATION_THRESHOLD
	return false

func _spawn_icon(fleet: CampaignFleet, behavior: CampaignFleetIcon.BehaviorType) -> CampaignFleetIcon:
	var icon: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	icon.behavior_type = behavior
	add_child(icon)
	icon.setup(fleet, HOME_BASE_POSITION)
	return icon

func _on_player_area_entered(area: Area2D) -> void:
	if area is CampaignFleetIcon and area != player_icon and not engage_prompt.visible:
		_pending_enemy_icon = area
		engage_prompt.visible = true

func _on_player_area_exited(area: Area2D) -> void:
	if area == _pending_enemy_icon:
		_pending_enemy_icon = null

func _on_enemy_area_entered(other: Area2D, icon: CampaignFleetIcon) -> void:
	if other is CampaignFleetIcon and other != icon and other != player_icon:
		if CampaignState.are_hostile(icon.fleet, other.fleet):
			CampaignState.start_skirmish(icon, other)

func _on_skirmish_resolved(_winner_fleet: CampaignFleet, _loser_fleet: CampaignFleet) -> void:
	enemy_icons = enemy_icons.filter(func(icon): return is_instance_valid(icon) and not icon.is_queued_for_deletion())
	if _pending_enemy_icon != null and (not is_instance_valid(_pending_enemy_icon) or _pending_enemy_icon.is_queued_for_deletion()):
		_pending_enemy_icon = null

func _physics_process(delta: float) -> void:
	CampaignState.tick_skirmishes(delta)

func _on_engage_pressed() -> void:
	engage_prompt.visible = false
	CampaignState.cancel_skirmish_for(_pending_enemy_icon)
	CampaignState.start_engagement(_pending_enemy_icon.fleet)
	get_tree().change_scene_to_file("res://scenes/combat/combat_scene.tscn")

func _on_disengage_pressed() -> void:
	engage_prompt.visible = false
	_pending_enemy_icon = null

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		player_icon.set_move_target(get_global_mouse_position())
