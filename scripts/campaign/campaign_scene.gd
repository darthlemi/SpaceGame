extends Node2D

const CampaignFleetIconScene = preload("res://scenes/campaign/campaign_fleet_icon.tscn")
const HomeBaseScene = preload("res://scenes/campaign/home_base.tscn")
const FactionBaseScene = preload("res://scenes/campaign/faction_base.tscn")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

const ENGAGE_BLOCKED_TEXT := "Neither fleet can fight"
const HOME_BASE_POSITION := Vector2(600, 400)
const PLAYER_STARTING_FUEL := 30.0
# Bases start below housing capacity so population has room to grow.
const STARTING_POPULATION_FRACTION := 0.75

var player_icon: CampaignFleetIcon
var enemy_icons: Array[CampaignFleetIcon] = []

@onready var engage_prompt: Control = $UILayer/EngagePrompt
@onready var trade_panel: TradePanel = $UILayer/TradePanel
@onready var refit_panel: RefitPanel = $UILayer/RefitPanel
@onready var repair_panel: RepairPanel = $UILayer/RepairPanel
@onready var fleet_management_panel: FleetManagementPanel = $UILayer/FleetManagementPanel
@onready var fleet_status_bar: Control = $UILayer/FleetStatusBar
@onready var base_overview_panel: BaseOverviewPanel = $UILayer/BaseOverviewPanel
@onready var loot_panel: LootPanel = $UILayer/LootPanel
@onready var respawn_panel: RespawnPanel = $UILayer/RespawnPanel

var _pending_enemy_icon: CampaignFleetIcon
var _mouse_held: bool = false
var _travel_target: Area2D = null
var _docked_base: Area2D = null
var _home_base: Area2D = null
var _paused_before_fleet_panel: bool = false
var _engage_prompt_text: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if CampaignState.player_fleet == null:
		_bootstrap_default_campaign()

	if CampaignState.pending_respawn:
		CampaignState.player_fleet.position = HOME_BASE_POSITION

	_home_base = HomeBaseScene.instantiate()
	_home_base.global_position = HOME_BASE_POSITION
	add_child(_home_base)

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
	_engage_prompt_text = engage_prompt.get_node("Label").text
	engage_prompt.get_node("EngageButton").pressed.connect(_on_engage_pressed)
	engage_prompt.get_node("DisengageButton").pressed.connect(_on_disengage_pressed)
	# Sub-panel Close buttons only close that panel, returning to the overview.
	base_overview_panel.trade_goods_button.pressed.connect(_open_trade_goods)
	base_overview_panel.shipyard_button.pressed.connect(_open_shipyard)
	base_overview_panel.repair_button.pressed.connect(_open_repair)
	base_overview_panel.undock_button.pressed.connect(_on_docking_panel_closed)
	fleet_status_bar.fleet_button.pressed.connect(_open_fleet_management)
	fleet_management_panel.close_button.pressed.connect(_on_fleet_management_closed)

	CampaignState.skirmish_resolved.connect(_on_skirmish_resolved)
	CampaignState.fleet_spawn_requested.connect(_on_fleet_spawn_requested)
	CampaignState.fleet_role_changed.connect(_on_fleet_role_changed)
	CampaignState.faction_reputation_changed.connect(_on_faction_reputation_changed)

	respawn_panel.finished.connect(_on_respawn_finished)
	if CampaignState.pending_respawn:
		respawn_panel.open_for()
		get_tree().paused = true

	if CampaignState.pending_loot != null and not CampaignState.pending_loot.is_empty():
		loot_panel.open_for(CampaignState.pending_loot, CampaignState.player_fleet)
	CampaignState.pending_loot = null

# The new ship appears docked at home base, exactly as on arrival (overview open, paused).
func _on_respawn_finished() -> void:
	_trigger_arrival(_home_base)
	if _docked_base == null:
		get_tree().paused = false

func _bootstrap_default_campaign() -> void:
	var player := CampaignFleet.new()
	player.faction = CampaignFleet.Faction.PLAYER
	player.position = HOME_BASE_POSITION
	player.speed = 120.0
	player.ship_compositions = [
		{"ship_type": ShipType.Kind.CORVETTE, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"ship_type": ShipType.Kind.CAPITAL, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"ship_type": ShipType.Kind.FREIGHTER, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
	]
	player.cargo = {Commodity.Type.FUEL: PLAYER_STARTING_FUEL}
	player.ensure_flagship()
	CampaignState.player_fleet = player

	var pirate := CampaignFleet.new()
	pirate.faction = CampaignFleet.Faction.PIRATE
	pirate.position = Vector2(1000, 200)
	pirate.speed = 100.0
	pirate.ship_compositions = [{"ship_type": ShipType.Kind.CORVETTE, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var trader := CampaignFleet.new()
	trader.faction = CampaignFleet.Faction.TRADER
	trader.position = Vector2(200, 550)
	trader.speed = 80.0
	trader.ship_compositions = [{"ship_type": ShipType.Kind.FREIGHTER, "max_hp": 60.0, "current_hp": 60.0, "max_shield": 20.0, "current_shield": 20.0}]

	var patrol := CampaignFleet.new()
	patrol.faction = CampaignFleet.Faction.NEUTRAL
	patrol.position = Vector2(900, 450)
	patrol.speed = 90.0
	patrol.ship_compositions = [{"ship_type": ShipType.Kind.CORVETTE, "max_hp": 80.0, "current_hp": 80.0, "max_shield": 30.0, "current_shield": 30.0}]

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
	dominion_fleet.ship_compositions = [{"ship_type": ShipType.Kind.CAPITAL, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var freehold_fleet := CampaignFleet.new()
	freehold_fleet.faction = CampaignFleet.Faction.FREEHOLD
	freehold_fleet.position = Vector2(200, 200)
	freehold_fleet.speed = 100.0
	freehold_fleet.ship_compositions = [{"ship_type": ShipType.Kind.CORVETTE, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var dominion_trader_fleet := CampaignFleet.new()
	dominion_trader_fleet.faction = CampaignFleet.Faction.DOMINION
	dominion_trader_fleet.role = CampaignFleet.Role.TRADER
	dominion_trader_fleet.position = dominion_faction.base_position
	dominion_trader_fleet.speed = 100.0
	dominion_trader_fleet.ship_compositions = [{"ship_type": ShipType.Kind.FREIGHTER, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var freehold_trader_fleet := CampaignFleet.new()
	freehold_trader_fleet.faction = CampaignFleet.Faction.FREEHOLD
	freehold_trader_fleet.role = CampaignFleet.Role.TRADER
	freehold_trader_fleet.position = freehold_faction.base_position
	freehold_trader_fleet.speed = 100.0
	freehold_trader_fleet.ship_compositions = [{"ship_type": ShipType.Kind.FREIGHTER, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	CampaignState.enemy_fleets = [pirate, trader, patrol, dominion_fleet, freehold_fleet, dominion_trader_fleet, freehold_trader_fleet]

	CampaignState.home_base_economy = BaseEconomy.new()
	CampaignState.home_base_economy.slots = [EconomyRole.trade_hub(), EconomyRole.refinery()]
	CampaignState.home_base_economy.max_slots = 2
	for commodity in Commodity.Type.values():
		CampaignState.home_base_economy.stock[commodity] = Commodity.TARGET_STOCK[commodity]
	CampaignState.home_base_economy.population = CampaignState.home_base_economy.population_capacity() * STARTING_POPULATION_FRACTION

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
	for faction in CampaignState.factions:
		faction.economy.population = faction.economy.population_capacity() * STARTING_POPULATION_FRACTION
		faction.economy.crew_pool = faction.economy.crew_pool_cap()
	CampaignState.home_base_economy.crew_pool = CampaignState.home_base_economy.crew_pool_cap()

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

func _catalog_for_base(area: Area2D) -> Array[String]:
	if area is FactionBase:
		return RefitCatalog.for_faction(area.faction_enum)
	return RefitCatalog.HOME_CATALOG

func _economy_for_base(area: Area2D) -> BaseEconomy:
	if area is HomeBase:
		return CampaignState.home_base_economy
	var faction := _faction_for_base(area)
	return faction.economy if faction != null else null

func _faction_for_base(area: Area2D) -> PowerFaction:
	if area is FactionBase:
		for faction in CampaignState.factions:
			if faction.faction_enum == area.faction_enum:
				return faction
	return null

func _name_for_base(area: Area2D) -> String:
	var faction := _faction_for_base(area)
	return "%s Base" % faction.display_name if faction != null else "Home Base"

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
			icon.player_target = player_icon if fleet.role == CampaignFleet.Role.COMBAT else null
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
	var away_pos := _dock_point_for(fleet.faction) if fleet.role == CampaignFleet.Role.TRADER else faction.base_position
	var reset_state := not icon.route_endpoints_match(faction.base_position, away_pos)
	icon.set_route_endpoints(faction.base_position, away_pos, reset_state)

func _dock_point_for(faction_enum: CampaignFleet.Faction) -> Vector2:
	if faction_enum == CampaignFleet.Faction.DOMINION:
		return HOME_BASE_POSITION + Vector2(40, 0)
	return HOME_BASE_POSITION + Vector2(-40, 0)

func _on_player_area_entered(area: Area2D) -> void:
	if area != _travel_target:
		return
	_trigger_arrival(area)

static func _deploys_armed(fleet: CampaignFleet) -> bool:
	for i in CrewRules.deploy_indices(fleet.ship_compositions):
		if CrewRules.is_armed(fleet.ship_compositions[i]):
			return true
	return false

# With no armed ship on either side the battle would be an instant Defeat; Disengage stays open.
func _refresh_engage_block(enemy_fleet: CampaignFleet) -> void:
	var can_fight := _deploys_armed(CampaignState.player_fleet) or _deploys_armed(enemy_fleet)
	engage_prompt.get_node("EngageButton").disabled = not can_fight
	engage_prompt.get_node("Label").text = _engage_prompt_text if can_fight else ENGAGE_BLOCKED_TEXT

func _trigger_arrival(area: Area2D) -> void:
	if area is CampaignFleetIcon and area != player_icon and not engage_prompt.visible:
		_pending_enemy_icon = area
		_refresh_engage_block(area.fleet)
		engage_prompt.visible = true
		get_tree().paused = true
		_travel_target = null
	elif area is HomeBase or area is FactionBase:
		var economy := _economy_for_base(area)
		if economy != null:
			_close_docking_ui()
			_docked_base = area
			base_overview_panel.open_for(_name_for_base(area), economy, _faction_for_base(area))
			get_tree().paused = true
			_travel_target = null

func _on_player_area_exited(area: Area2D) -> void:
	if area == _pending_enemy_icon:
		_pending_enemy_icon = null
		engage_prompt.visible = false
	elif area is HomeBase or area is FactionBase:
		_close_docking_ui()
		get_tree().paused = false

func _on_enemy_area_entered(other: Area2D, icon: CampaignFleetIcon) -> void:
	if other is CampaignFleetIcon and other != icon and other != player_icon:
		if CampaignState.are_hostile(icon.fleet, other.fleet):
			CampaignState.start_skirmish(icon, other)

func _on_skirmish_resolved(_winner_fleet: CampaignFleet, _loser_fleet: CampaignFleet) -> void:
	enemy_icons = enemy_icons.filter(func(icon): return is_instance_valid(icon) and not icon.is_queued_for_deletion())
	if _pending_enemy_icon != null and (not is_instance_valid(_pending_enemy_icon) or _pending_enemy_icon.is_queued_for_deletion()):
		_pending_enemy_icon = null
		engage_prompt.visible = false
		get_tree().paused = false

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	CampaignState.tick_skirmishes(delta)
	CampaignState.tick_economy(delta)
	if _travel_target != null:
		if not is_instance_valid(_travel_target) or _travel_target.is_queued_for_deletion():
			_travel_target = null
		else:
			player_icon.set_move_target(_travel_target.global_position)
	elif _mouse_held:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			player_icon.set_move_target(get_global_mouse_position())
		else:
			_mouse_held = false

func _on_engage_pressed() -> void:
	if engage_prompt.get_node("EngageButton").disabled:
		return
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
	get_tree().paused = false

func _on_docking_panel_closed() -> void:
	_close_docking_ui()
	get_tree().paused = false
	_travel_target = null

func _close_docking_ui() -> void:
	_close_dock_subpanels()
	base_overview_panel.close()
	_docked_base = null

# Trade Goods / Shipyard / Repair share one screen slot; one open at a time.
func _close_dock_subpanels() -> void:
	trade_panel.close()
	refit_panel.close()
	repair_panel.close()
	fleet_management_panel.close()

func _open_trade_goods() -> void:
	_close_dock_subpanels()
	trade_panel.open_for(_economy_for_base(_docked_base), CampaignState.player_fleet)

func _open_shipyard() -> void:
	_close_dock_subpanels()
	refit_panel.open_for(CampaignState.player_fleet, _catalog_for_base(_docked_base))

func _open_repair() -> void:
	_close_dock_subpanels()
	repair_panel.open_for(CampaignState.player_fleet)

func _open_fleet_management() -> void:
	# The engage and respawn prompts are modal and share the panel's screen slot.
	if engage_prompt.visible or respawn_panel.visible:
		return
	if not fleet_management_panel.visible:
		_paused_before_fleet_panel = get_tree().paused
	_close_dock_subpanels()
	fleet_management_panel.open_for(CampaignState.player_fleet, _economy_for_base(_docked_base))
	get_tree().paused = true

# Docked play stays paused behind the overview; an undocked close restores the prior pause.
func _on_fleet_management_closed() -> void:
	if _docked_base == null:
		get_tree().paused = _paused_before_fleet_panel

# Reputation changes (e.g. a paid fine) can flip a faction between hostile and
# friendly; re-derive behavior for its live icons instead of waiting for a reload.
func _on_faction_reputation_changed(faction_enum: CampaignFleet.Faction) -> void:
	for icon in enemy_icons:
		if is_instance_valid(icon) and icon.fleet.faction == faction_enum:
			_on_fleet_role_changed(icon.fleet)

func _find_clickable_target(global_pos: Vector2) -> Area2D:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = global_pos
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for result in get_world_2d().direct_space_state.intersect_point(query):
		var collider = result.collider
		if collider == player_icon:
			continue
		if collider is CampaignFleetIcon or collider is HomeBase or collider is FactionBase:
			return collider
	return null

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if base_overview_panel.visible or engage_prompt.visible or fleet_management_panel.visible or respawn_panel.visible:
			return
		if get_tree().paused:
			get_tree().paused = false
			Engine.time_scale = 1.0
		var target := _find_clickable_target(get_global_mouse_position())
		if target != null:
			_travel_target = target
			_mouse_held = false
			if player_icon.get_overlapping_areas().has(target):
				# Already standing on the target -- no fresh area_entered
				# transition will fire to drive the arrival trigger, so fire
				# it directly (e.g. disengaging a fleet encountered on top of
				# a base, then clicking that same base).
				_trigger_arrival(target)
		else:
			_travel_target = null
			_mouse_held = true
			player_icon.set_move_target(get_global_mouse_position())
