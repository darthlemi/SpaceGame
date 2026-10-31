extends Node2D

const CampaignFleetIconScene = preload("res://scenes/campaign/campaign_fleet_icon.tscn")
const HomeBaseScene = preload("res://scenes/campaign/home_base.tscn")
const FactionBaseScene = preload("res://scenes/campaign/faction_base.tscn")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

const HOME_BASE_POSITION := Vector2(600, 400)

var player_icon: CampaignFleetIcon
var enemy_icons: Array[CampaignFleetIcon] = []

@onready var engage_prompt: Control = $EngagePrompt
@onready var trade_panel: TradePanel = $TradePanel
@onready var loot_panel: LootPanel = $LootPanel

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
		_setup_enemy_icon(enemy_fleet)

	engage_prompt.visible = false
	engage_prompt.get_node("EngageButton").pressed.connect(_on_engage_pressed)
	engage_prompt.get_node("DisengageButton").pressed.connect(_on_disengage_pressed)

	CampaignState.skirmish_resolved.connect(_on_skirmish_resolved)
	CampaignState.fleet_spawn_requested.connect(_on_fleet_spawn_requested)
	CampaignState.fleet_role_changed.connect(_on_fleet_role_changed)

	if CampaignState.pending_loot_fleet != null:
		loot_panel.open_for(CampaignState.pending_loot_fleet, CampaignState.player_fleet)
		CampaignState.pending_loot_fleet = null

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
	dominion_fleet.position = Vector2(980, 480)
	dominion_fleet.speed = 100.0
	dominion_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var freehold_fleet := CampaignFleet.new()
	freehold_fleet.faction = CampaignFleet.Faction.FREEHOLD
	freehold_fleet.position = Vector2(200, 200)
	freehold_fleet.speed = 100.0
	freehold_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var dominion_trader_fleet := CampaignFleet.new()
	dominion_trader_fleet.faction = CampaignFleet.Faction.DOMINION
	dominion_trader_fleet.role = CampaignFleet.Role.TRADER
	dominion_trader_fleet.position = dominion_faction.base_position
	dominion_trader_fleet.speed = 100.0
	dominion_trader_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var freehold_trader_fleet := CampaignFleet.new()
	freehold_trader_fleet.faction = CampaignFleet.Faction.FREEHOLD
	freehold_trader_fleet.role = CampaignFleet.Role.TRADER
	freehold_trader_fleet.position = freehold_faction.base_position
	freehold_trader_fleet.speed = 100.0
	freehold_trader_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	CampaignState.enemy_fleets = [pirate, trader, patrol, dominion_fleet, freehold_fleet, dominion_trader_fleet, freehold_trader_fleet]

	CampaignState.home_base_economy = BaseEconomy.new()
	CampaignState.home_base_economy.slots = [EconomyRole.trade_hub(), EconomyRole.refinery()]
	CampaignState.home_base_economy.max_slots = 2
	for commodity in Commodity.Type.values():
		CampaignState.home_base_economy.stock[commodity] = Commodity.TARGET_STOCK[commodity]

	dominion_faction.economy = BaseEconomy.new()
	dominion_faction.economy.slots = [EconomyRole.industrial(), EconomyRole.population()]
	dominion_faction.economy.max_slots = 2
	dominion_faction.economy.stock = {
		Commodity.Type.ORE: 50.0,
		Commodity.Type.FUEL: 50.0,
		Commodity.Type.FOOD: 50.0,
	}

	freehold_faction.economy = BaseEconomy.new()
	freehold_faction.economy.slots = [EconomyRole.mining(), EconomyRole.agriculture()]
	freehold_faction.economy.max_slots = 2
	freehold_faction.economy.stock = {
		Commodity.Type.ORE: 50.0,
		Commodity.Type.FOOD: 50.0,
	}

func _behavior_for_fleet(fleet: CampaignFleet) -> CampaignFleetIcon.BehaviorType:
	match fleet.faction:
		CampaignFleet.Faction.PIRATE:
			return CampaignFleetIcon.BehaviorType.PIRATE
		CampaignFleet.Faction.TRADER:
			return CampaignFleetIcon.BehaviorType.TRADER
		CampaignFleet.Faction.DOMINION, CampaignFleet.Faction.FREEHOLD:
			if fleet.role == CampaignFleet.Role.TRADER:
				return CampaignFleetIcon.BehaviorType.TRADER
			return CampaignFleetIcon.BehaviorType.PIRATE if _is_faction_hostile(fleet.faction) else CampaignFleetIcon.BehaviorType.PATROL
		_:
			return CampaignFleetIcon.BehaviorType.PATROL

func _is_faction_hostile(faction: CampaignFleet.Faction) -> bool:
	for power_faction in CampaignState.factions:
		if power_faction.faction_enum == faction:
			return power_faction.reputation < CampaignState.HOSTILE_REPUTATION_THRESHOLD
	return false

func _economy_for_base(area: Area2D) -> BaseEconomy:
	if area is HomeBase:
		return CampaignState.home_base_economy
	if area is FactionBase:
		for faction in CampaignState.factions:
			if faction.faction_enum == area.faction_enum:
				return faction.economy
	return null

func _spawn_icon(fleet: CampaignFleet, behavior: CampaignFleetIcon.BehaviorType) -> CampaignFleetIcon:
	var icon: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	icon.behavior_type = behavior
	add_child(icon)
	icon.setup(fleet, HOME_BASE_POSITION)
	return icon

func _setup_enemy_icon(fleet: CampaignFleet) -> CampaignFleetIcon:
	var behavior := _behavior_for_fleet(fleet)
	var icon := _spawn_icon(fleet, behavior)
	var is_faction_hauler := (fleet.faction == CampaignFleet.Faction.DOMINION or fleet.faction == CampaignFleet.Faction.FREEHOLD) and fleet.role == CampaignFleet.Role.TRADER
	if not is_faction_hauler:
		icon.player_target = player_icon
	icon.area_entered.connect(_on_enemy_area_entered.bind(icon))
	icon.trader_arrived.connect(_on_trader_arrived.bind(icon))
	enemy_icons.append(icon)
	_configure_trade_route(icon, fleet)
	return icon

func _on_fleet_spawn_requested(fleet: CampaignFleet) -> void:
	_setup_enemy_icon(fleet)

func _on_fleet_role_changed(fleet: CampaignFleet) -> void:
	for icon in enemy_icons:
		if icon.fleet == fleet:
			icon.behavior_type = _behavior_for_fleet(fleet)
			_configure_trade_route(icon, fleet)
			break

func _on_trader_arrived(at_home: bool, icon: CampaignFleetIcon) -> void:
	if icon.fleet.faction == CampaignFleet.Faction.DOMINION or icon.fleet.faction == CampaignFleet.Faction.FREEHOLD:
		CampaignState.run_npc_trade_for_fleet(icon.fleet, at_home)

func _configure_trade_route(icon: CampaignFleetIcon, fleet: CampaignFleet) -> void:
	if fleet.faction != CampaignFleet.Faction.DOMINION and fleet.faction != CampaignFleet.Faction.FREEHOLD:
		return
	var faction: PowerFaction = null
	for f in CampaignState.factions:
		if f.faction_enum == fleet.faction:
			faction = f
			break
	if faction == null:
		return
	if fleet.role == CampaignFleet.Role.TRADER:
		icon.set_route_endpoints(faction.base_position, HOME_BASE_POSITION)
	else:
		icon.set_route_endpoints(faction.base_position, faction.base_position)

func _on_player_area_entered(area: Area2D) -> void:
	if area is CampaignFleetIcon and area != player_icon and not engage_prompt.visible:
		_pending_enemy_icon = area
		engage_prompt.visible = true
	elif area is HomeBase or area is FactionBase:
		var economy := _economy_for_base(area)
		if economy != null:
			trade_panel.open_for(economy, CampaignState.player_fleet)

func _on_player_area_exited(area: Area2D) -> void:
	if area == _pending_enemy_icon:
		_pending_enemy_icon = null
	elif area is HomeBase or area is FactionBase:
		trade_panel.close()

func _on_enemy_area_entered(other: Area2D, icon: CampaignFleetIcon) -> void:
	if other is CampaignFleetIcon and other != icon and other != player_icon:
		if CampaignState.are_hostile(icon.fleet, other.fleet):
			CampaignState.start_skirmish(icon, other)

func _on_skirmish_resolved(_winner_fleet: CampaignFleet, _loser_fleet: CampaignFleet) -> void:
	enemy_icons = enemy_icons.filter(func(icon): return is_instance_valid(icon) and not icon.is_queued_for_deletion())
	if _pending_enemy_icon != null and (not is_instance_valid(_pending_enemy_icon) or _pending_enemy_icon.is_queued_for_deletion()):
		_pending_enemy_icon = null
		engage_prompt.visible = false

func _physics_process(delta: float) -> void:
	CampaignState.tick_skirmishes(delta)
	CampaignState.tick_economy(delta)

func _on_engage_pressed() -> void:
	if _pending_enemy_icon == null:
		engage_prompt.visible = false
		return
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
