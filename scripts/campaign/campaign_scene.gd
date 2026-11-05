extends Node2D

const CampaignFleetIconScene = preload("res://scenes/campaign/campaign_fleet_icon.tscn")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

const ENGAGE_BLOCKED_TEXT := "Neither fleet can fight"
# Far wider than a system, so hidden layers never overlap the current one's Area2Ds.
const SYSTEM_SPACING := 5000.0

var player_icon: CampaignFleetIcon
var enemy_icons: Array[CampaignFleetIcon] = []
# system_id -> SystemLayer.
var layers: Dictionary = {}
# station_id -> CampaignStation.
var station_nodes: Dictionary = {}

@onready var engage_prompt: Control = $UILayer/EngagePrompt
@onready var trade_panel: TradePanel = $UILayer/TradePanel
@onready var refit_panel: RefitPanel = $UILayer/RefitPanel
@onready var repair_panel: RepairPanel = $UILayer/RepairPanel
@onready var fleet_management_panel: FleetManagementPanel = $UILayer/FleetManagementPanel
@onready var fleet_status_bar: Control = $UILayer/FleetStatusBar
@onready var base_overview_panel: BaseOverviewPanel = $UILayer/BaseOverviewPanel
@onready var loot_panel: LootPanel = $UILayer/LootPanel
@onready var respawn_panel: RespawnPanel = $UILayer/RespawnPanel
@onready var jump_map_panel: JumpMapPanel = $UILayer/JumpMapPanel

var _pending_enemy_icon: CampaignFleetIcon
var _mouse_held: bool = false
var _travel_target: Area2D = null
var _docked_base: Area2D = null
var _paused_before_fleet_panel: bool = false
var _jump: CampaignJumpController
var _engage_prompt_text: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if CampaignState.player_fleet == null:
		CampaignState.new_game()
	elif CampaignState.galaxy == null:
		# Fixtures that hand-build a player fleet still need a galaxy to place it in.
		CampaignState.galaxy = GalaxyData.build()

	if CampaignState.pending_respawn:
		CampaignState.player_fleet.position = CampaignState.galaxy.home_station().position

	_build_layers()

	player_icon = _spawn_icon(CampaignState.player_fleet, CampaignFleetIcon.BehaviorType.PLAYER)
	player_icon.area_entered.connect(_on_player_area_entered)
	player_icon.area_exited.connect(_on_player_area_exited)
	# Before NPCs spawn, so no two systems' fleets ever share the origin.
	show_system(CampaignState.player_fleet.system_id)
	# Fixture fleets skip new_game(), so chart where they start for the jump map.
	if not CampaignState.visited.has(CampaignState.player_fleet.system_id):
		CampaignState.record_visit(CampaignState.player_fleet.system_id)

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
	_jump = CampaignJumpController.new(self)

	CampaignState.skirmish_resolved.connect(_on_skirmish_resolved)
	CampaignState.fleet_spawn_requested.connect(_on_fleet_spawn_requested)
	CampaignState.fleet_role_changed.connect(_on_fleet_role_changed)
	CampaignState.faction_reputation_changed.connect(_on_faction_reputation_changed)
	CampaignState.fleet_retired.connect(_on_fleet_retired)
	CampaignState.trade_destination_changed.connect(_on_trade_destination_changed)

	respawn_panel.finished.connect(_on_respawn_finished)
	if CampaignState.pending_respawn:
		respawn_panel.open_for()
		get_tree().paused = true

	if CampaignState.pending_loot != null and not CampaignState.pending_loot.is_empty():
		loot_panel.open_for(CampaignState.pending_loot, CampaignState.player_fleet)
	CampaignState.pending_loot = null

# The new ship appears docked at the home station, exactly as on arrival (overview open, paused).
func _on_respawn_finished() -> void:
	_trigger_arrival(station_nodes.get(CampaignState.galaxy.home_station().id))
	if _docked_base == null:
		get_tree().paused = false

func layer_for(system_id: String) -> SystemLayer:
	return layers.get(system_id)

# Layer i in sorted id order parks at slot i + 1, so slot 0 (the origin) is the current system's alone.
func show_system(system_id: String) -> void:
	var ids: Array = layers.keys()
	ids.sort()
	for i in ids.size():
		layers[ids[i]].set_current(ids[i] == system_id, Vector2(SYSTEM_SPACING * (i + 1), 0))

func _build_layers() -> void:
	var ids: Array = CampaignState.galaxy.systems.keys()
	ids.sort()
	for system_id in ids:
		var layer := SystemLayer.new()
		layer.name = system_id
		layer.system_id = system_id
		add_child(layer)
		layers[system_id] = layer
	for station in CampaignState.galaxy.stations:
		station_nodes[station.id] = layer_for(station.system_id).add_station(station)

func _behavior_for_fleet(fleet: CampaignFleet) -> CampaignFleetIcon.BehaviorType:
	if fleet.role == CampaignFleet.Role.TRADER:
		return CampaignFleetIcon.BehaviorType.TRADER
	return CampaignFleetIcon.BehaviorType.PIRATE if CampaignState.is_hostile_to_player(fleet) else CampaignFleetIcon.BehaviorType.PATROL

# Faction haulers hold their route; neutral traders flee the player and combat fleets react to it.
func _player_target_for(fleet: CampaignFleet) -> CampaignFleetIcon:
	if fleet.role == CampaignFleet.Role.TRADER and fleet.faction != CampaignFleet.Faction.TRADER:
		return null
	return player_icon

func _catalog_for_base(area: Area2D) -> Array[String]:
	return RefitCatalog.for_faction(area.station.owner)

func _economy_for_base(area: Area2D) -> BaseEconomy:
	return area.station.economy if area is CampaignStation else null

func _faction_for_base(area: Area2D) -> PowerFaction:
	return CampaignState.power_faction_for(area.station.owner) if area is CampaignStation else null

func _name_for_base(area: Area2D) -> String:
	return area.station.display_name

func _spawn_icon(fleet: CampaignFleet, behavior: CampaignFleetIcon.BehaviorType) -> CampaignFleetIcon:
	# Hand-built fixture fleets carry no system; treat them as being in the start system.
	if not layers.has(fleet.system_id):
		fleet.system_id = CampaignState.galaxy.start_system_id
	var icon: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	icon.behavior_type = behavior
	layer_for(fleet.system_id).add_child(icon)
	icon.setup(fleet, _spawn_point_for(fleet))
	return icon

# Fleets wander around their home station; away from home they wander where they are.
func _spawn_point_for(fleet: CampaignFleet) -> Vector2:
	var home: StationData = CampaignState.galaxy.station(fleet.home_station_id)
	return home.position if home != null and home.system_id == fleet.system_id else fleet.position

func _setup_enemy_icon(fleet: CampaignFleet) -> CampaignFleetIcon:
	var icon := _spawn_icon(fleet, _behavior_for_fleet(fleet))
	icon.player_target = _player_target_for(fleet)
	icon.area_entered.connect(_on_enemy_area_entered.bind(icon))
	icon.trader_arrived_at.connect(_on_trader_arrived_at.bind(icon))
	enemy_icons.append(icon)
	# Only a fresh trader starts here; a saved destination (even "") is kept across rebuilds.
	if fleet.role == CampaignFleet.Role.TRADER and fleet.dest_station_id == "":
		fleet.dest_station_id = CampaignState.next_trade_destination(fleet)
	_aim_trader(icon)
	return icon

# A destination in another system leaves the trader idle here until CampaignState.tick_npc_jumps
# jumps it there; the jump controller re-aims it on arrival.
func _aim_trader(icon: CampaignFleetIcon) -> void:
	var dest: StationData = CampaignState.galaxy.station(icon.fleet.dest_station_id)
	icon.has_destination = dest != null and dest.system_id == icon.fleet.system_id
	if icon.has_destination:
		icon.dest_position = dest.position

func _on_fleet_spawn_requested(fleet: CampaignFleet) -> void:
	_setup_enemy_icon(fleet)

func _on_fleet_role_changed(fleet: CampaignFleet) -> void:
	for icon in enemy_icons:
		if is_instance_valid(icon) and icon.fleet == fleet:
			icon.behavior_type = _behavior_for_fleet(fleet)
			icon.player_target = _player_target_for(fleet)
			_aim_trader(icon)
			break

func _on_trade_destination_changed(fleet: CampaignFleet) -> void:
	var icon := _icon_of(fleet)
	if icon != null:
		_aim_trader(icon)

# The fleet already left the roster; its icon goes, and the player stops steering at it.
func _on_fleet_retired(fleet: CampaignFleet) -> void:
	var icon := _icon_of(fleet)
	if icon == null:
		return
	if _travel_target == icon:
		_travel_target = null
	icon.queue_free()
	_drop_freed_icons()

func _icon_of(fleet: CampaignFleet) -> CampaignFleetIcon:
	for icon in enemy_icons:
		if is_instance_valid(icon) and not icon.is_queued_for_deletion() and icon.fleet == fleet:
			return icon
	return null

func _on_trader_arrived_at(station_id: String, icon: CampaignFleetIcon) -> void:
	CampaignState.run_npc_trade_at(icon.fleet, CampaignState.galaxy.station(station_id))
	icon.fleet.dest_station_id = CampaignState.next_trade_destination(icon.fleet)
	_aim_trader(icon)

func _on_player_area_entered(area: Area2D) -> void:
	if _jump.try_catch(area):
		return
	if area != _travel_target:
		return
	_trigger_arrival(area)

func _player_hostile_contact() -> bool:
	return _jump.player_hostile_contact()

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
		if not CampaignState.can_engage(area.fleet):
			return
		_pending_enemy_icon = area
		_refresh_engage_block(area.fleet)
		engage_prompt.visible = true
		get_tree().paused = true
		_travel_target = null
	elif area is CampaignStation:
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
	elif area is CampaignStation:
		_close_docking_ui()
		get_tree().paused = false

func _on_enemy_area_entered(other: Area2D, icon: CampaignFleetIcon) -> void:
	if other is CampaignFleetIcon and other != icon and other != player_icon:
		if CampaignState.are_hostile(icon.fleet, other.fleet):
			CampaignState.start_skirmish(icon, other)

func _on_skirmish_resolved(_winner_fleet: CampaignFleet, _loser_fleet: CampaignFleet) -> void:
	_drop_freed_icons()

# Prunes queued-for-deletion icons and closes an engage prompt whose fleet is gone.
func _drop_freed_icons() -> void:
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
	CampaignState.tick_warps(delta)
	CampaignState.tick_npc_jumps(delta)
	CampaignState.tick_reengage(delta)
	if _travel_target != null:
		if not is_instance_valid(_travel_target) or _travel_target.is_queued_for_deletion():
			_travel_target = null
		else:
			player_icon.set_move_target(_to_player_space(_travel_target.global_position))
	elif _mouse_held:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			player_icon.set_move_target(_to_player_space(get_global_mouse_position()))
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
	# The engage and respawn prompts are modal and share the panel's screen slot; the open jump
	# map owns the pause state, which a second record here would corrupt.
	if engage_prompt.visible or respawn_panel.visible or jump_map_panel.visible:
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

func _open_jump_map() -> void:
	_jump.open_jump_map()

func _on_jump_requested(system_id: String) -> void:
	_jump.on_jump_requested(system_id)

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
		if collider is CampaignFleetIcon or collider is CampaignStation:
			return collider
	return null

func _unhandled_input(event: InputEvent) -> void:
	# An open map handles J itself (it closes).
	if event.is_action_pressed("open_jump_map") and not jump_map_panel.visible:
		_open_jump_map()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if base_overview_panel.visible or engage_prompt.visible or fleet_management_panel.visible or respawn_panel.visible or jump_map_panel.visible:
			return
		if get_tree().paused:
			get_tree().paused = false
			Engine.time_scale = 1.0
		# The fleet holds still through a warp countdown.
		if CampaignState.player_fleet.is_warping():
			return
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
			player_icon.set_move_target(_to_player_space(get_global_mouse_position()))

# The current layer sits at the origin, but the player icon moves in its layer's space.
func _to_player_space(global_point: Vector2) -> Vector2:
	return player_icon.get_parent().to_local(global_point)
