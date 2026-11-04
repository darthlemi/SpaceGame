class_name CampaignJumpController
extends RefCounted

# Player jump wiring for CampaignScene: map open/close, jump requests, warp catching and fleet_jumped.
# A RefCounted helper holding the scene (like the behaviors/ helpers): it needs no tree lifecycle of its
# own, and the scene owns the panels and state it drives.

var _scene: Node2D
var _paused_before_jump_map: bool = false

func _init(scene: Node2D) -> void:
	_scene = scene
	_scene.fleet_status_bar.jump_button.pressed.connect(on_jump_button_pressed)
	_scene.jump_map_panel.jump_requested.connect(on_jump_requested)
	_scene.jump_map_panel.distress_requested.connect(_on_distress_requested)
	_scene.jump_map_panel.closed.connect(_on_jump_map_closed)
	CampaignState.fleet_jumped.connect(_on_fleet_jumped)

func on_jump_button_pressed() -> void:
	if CampaignState.player_fleet.is_warping():
		CampaignState.player_fleet.cancel_warp()
	else:
		open_jump_map()

# Same modal rules as the Fleet panel. The map covers whatever is open; closing it returns there.
func open_jump_map() -> void:
	if _scene.engage_prompt.visible or _scene.respawn_panel.visible:
		return
	if not _scene.jump_map_panel.visible:
		_paused_before_jump_map = _scene.get_tree().paused
	_scene.jump_map_panel.open_for(CampaignState, _scene._docked_base != null, player_hostile_contact())
	_scene.get_tree().paused = true

# Jumping while docked undocks first; the countdown runs in game time, so this unpauses.
func on_jump_requested(system_id: String) -> void:
	if not CampaignState.begin_player_warp(system_id, player_hostile_contact()):
		_scene.jump_map_panel.refresh()
		return
	if _scene._docked_base != null:
		_scene._on_docking_panel_closed()
	_scene.fleet_management_panel.close()
	_scene.jump_map_panel.close()
	_scene._travel_target = null
	_scene._mouse_held = false
	_scene.get_tree().paused = false

# Hostile means running pirate behaviour, so fleeing traders never catch or block the player.
func is_hostile_icon(area: Area2D) -> bool:
	return area is CampaignFleetIcon and area != _scene.player_icon and _scene._behavior_for_fleet(area.fleet) == CampaignFleetIcon.BehaviorType.PIRATE

func player_hostile_contact() -> bool:
	for area in _scene.player_icon.get_overlapping_areas():
		if is_hostile_icon(area):
			return true
	return false

# Caught mid-countdown: contact cancels the warp and forces the engage prompt. True if caught.
func try_catch(area: Area2D) -> bool:
	if not CampaignState.player_fleet.is_warping() or not is_hostile_icon(area):
		return false
	CampaignState.player_fleet.cancel_warp()
	_scene._trigger_arrival(area)
	return true

func _on_jump_map_closed() -> void:
	_scene.get_tree().paused = _paused_before_jump_map

func _on_distress_requested() -> void:
	CampaignState.send_distress()
	_scene.jump_map_panel.refresh()

func _on_fleet_jumped(fleet: CampaignFleet, _from_system: String) -> void:
	var icon: CampaignFleetIcon = _scene.player_icon if fleet == CampaignState.player_fleet else _icon_for_fleet(fleet)
	if icon == null:
		return
	icon.reparent(_scene.layer_for(fleet.system_id), false)
	icon.setup(fleet, _scene._spawn_point_for(fleet))
	if icon == _scene.player_icon:
		_scene.show_system(fleet.system_id)
		_scene._travel_target = null
		_scene._mouse_held = false
		_scene.engage_prompt.visible = false
		_scene._pending_enemy_icon = null
		_scene._close_docking_ui()
	else:
		# The player's target just left for a hidden layer; steering at it would drag the fleet to the edge.
		if _scene._travel_target == icon:
			_scene._travel_target = null
		_scene._aim_trader(icon)
	icon.play_warp_in()

func _icon_for_fleet(fleet: CampaignFleet) -> CampaignFleetIcon:
	for icon in _scene.enemy_icons:
		if is_instance_valid(icon) and icon.fleet == fleet:
			return icon
	return null
