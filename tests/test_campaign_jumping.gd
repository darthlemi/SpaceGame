extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")
const CampaignFleetIconScene = preload("res://scenes/campaign/campaign_fleet_icon.tscn")
const UiLayoutCheck = preload("res://tests/ui_layout_check.gd")
const CAMPAIGN_SCENE_PATH := "res://scenes/campaign/campaign_scene.tscn"

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	_check_block_reasons(campaign_state, failures)
	_check_fuel_timing_arrival_discovery(campaign_state, failures)
	_check_cancelled_warps(campaign_state, failures)
	_check_distress(campaign_state, failures)
	await _check_jump_while_docked_undocks(tree, campaign_state, failures)
	await _check_moves_ignored_mid_warp(tree, campaign_state, failures)
	await _check_caught_by_hostile(tree, campaign_state, failures)
	await _check_switching_layers(tree, campaign_state, failures)
	await _check_combat_round_trip_keeps_system_and_npc_warp(tree, campaign_state, failures)
	await _check_jump_map_blocked_by_modals(tree, campaign_state, failures)
	tree.paused = false
	campaign_state.reset()
	return failures

static func _open_scene(tree: SceneTree) -> Node2D:
	var scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame
	await tree.process_frame
	tree.paused = false
	return scene

static func _close_scene(tree: SceneTree, campaign_state, scene: Node2D) -> void:
	tree.paused = false
	scene.queue_free()
	await tree.process_frame
	campaign_state.reset()

static func _icon_for(scene: Node2D, fleet: CampaignFleet) -> CampaignFleetIcon:
	for icon in scene.enemy_icons:
		if is_instance_valid(icon) and icon.fleet == fleet:
			return icon
	return null

static func _first_fleet(campaign_state, station_id: String, role: CampaignFleet.Role) -> CampaignFleet:
	var fleets: Array[CampaignFleet] = campaign_state.station_fleets(campaign_state.galaxy.station(station_id), role)
	return fleets[0] if not fleets.is_empty() else null

static func _check_block_reasons(campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	var reason: String = campaign_state.jump_block_reason("deadreach", false)
	if reason != "Not connected":
		failures.append("block reasons: expected 'Not connected' for deadreach, got '%s'" % reason)
	reason = campaign_state.jump_block_reason("wexford", false)
	if reason != "":
		failures.append("block reasons: expected wexford allowed at a new game, got '%s'" % reason)
	reason = campaign_state.jump_block_reason("wexford", true)
	if reason != "Hostile fleet in contact":
		failures.append("block reasons: expected 'Hostile fleet in contact', got '%s'" % reason)
	campaign_state.player_fleet.cargo[Commodity.Type.FUEL] = 5.0
	reason = campaign_state.jump_block_reason("wexford", false)
	var expected := "Not enough fuel (need %.1f, have %.1f)" % [JumpRules.jump_cost(campaign_state.player_fleet), 5.0]
	if reason != expected:
		failures.append("block reasons: expected '%s', got '%s'" % [expected, reason])
	if campaign_state.begin_player_warp("wexford", false):
		failures.append("block reasons: expected begin_player_warp refused without fuel")
	campaign_state.player_fleet.cargo[Commodity.Type.FUEL] = 30.0
	campaign_state.begin_player_warp("wexford", false)
	reason = campaign_state.jump_block_reason("kestrel", false)
	if reason != "Warp already charging":
		failures.append("block reasons: expected 'Warp already charging' mid-countdown, got '%s'" % reason)

static func _check_fuel_timing_arrival_discovery(campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	var fleet: CampaignFleet = campaign_state.player_fleet
	var fuel_before := fleet.fuel_amount()
	var cost := JumpRules.jump_cost(fleet)
	var jumps: Array = []
	var on_jumped := func(jumped: CampaignFleet, from_system: String): jumps.append([jumped, from_system])
	campaign_state.fleet_jumped.connect(on_jumped)
	if not campaign_state.begin_player_warp("wexford", false):
		failures.append("fuel timing: expected begin_player_warp('wexford') to start")
	if fleet.fuel_amount() != fuel_before:
		failures.append("fuel timing: expected no fuel spent when the countdown starts")
	campaign_state.tick_warps(2.9)
	if fleet.system_id != "haven" or fleet.fuel_amount() != fuel_before:
		failures.append("fuel timing: expected the player still in haven with full fuel at 2.9 s, in %s fuel %.2f" % [fleet.system_id, fleet.fuel_amount()])
	campaign_state.tick_warps(0.2)
	campaign_state.fleet_jumped.disconnect(on_jumped)
	if fleet.system_id != "wexford":
		failures.append("fuel timing: expected the player in wexford after 3.1 s, in %s" % fleet.system_id)
	if not is_equal_approx(fleet.fuel_amount(), fuel_before - cost):
		failures.append("fuel timing: expected fuel %.2f after the jump, got %.2f" % [fuel_before - cost, fleet.fuel_amount()])
	if fleet.is_warping() or fleet.warp_target != "":
		failures.append("fuel timing: expected the warp state cleared on arrival")
	if jumps.size() != 1 or jumps[0][0] != fleet or jumps[0][1] != "haven":
		failures.append("fuel timing: expected one fleet_jumped(player, 'haven'), got %s" % [jumps])

	var haven: StarSystem = campaign_state.galaxy.system("haven")
	var wexford: StarSystem = campaign_state.galaxy.system("wexford")
	var edge := JumpRules.edge_point(haven.map_position - wexford.map_position)
	if fleet.position.distance_to(edge) > JumpRules.ARRIVAL_RADIUS + 1.0:
		failures.append("arrival: expected the player within %.0f of %s, at %s" % [JumpRules.ARRIVAL_RADIUS + 1.0, edge, fleet.position])

	for id in ["haven", "wexford"]:
		if not campaign_state.visited.has(id):
			failures.append("discovery: expected %s visited" % id)
	for id in ["greenreach", "cinder", "kestrel"]:
		if not campaign_state.discovered.has(id):
			failures.append("discovery: expected %s discovered" % id)
	if campaign_state.discovered.has("freeport"):
		failures.append("discovery: expected freeport (two jumps out) undiscovered")
	if not campaign_state.last_seen.has("haven"):
		failures.append("discovery: expected last_seen['haven'] recorded")
	var seen: Dictionary = campaign_state.last_seen.get("wexford", {})
	if seen.get("stations", -1) != campaign_state.galaxy.stations_in("wexford").size() or seen.get("tier", -1) != wexford.tier:
		failures.append("discovery: expected last_seen['wexford'] to snapshot its stations and tier, got %s" % seen)

static func _check_cancelled_warps(campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	var fleet: CampaignFleet = campaign_state.player_fleet
	var fuel_before := fleet.fuel_amount()
	campaign_state.begin_player_warp("wexford", false)
	campaign_state.tick_warps(1.0)
	fleet.cancel_warp()
	campaign_state.tick_warps(3.0)
	if fleet.fuel_amount() != fuel_before or fleet.system_id != "haven":
		failures.append("cancel: expected a cancelled warp to cost nothing and stay in haven, fuel %.2f in %s" % [fleet.fuel_amount(), fleet.system_id])

	var npc: CampaignFleet = campaign_state.enemy_fleets[0]
	var other: CampaignFleet = campaign_state.enemy_fleets[1]
	npc.start_warp(campaign_state.galaxy.neighbours(npc.system_id)[0])
	var icon_a: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	var icon_b: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	icon_a.fleet = npc
	icon_b.fleet = other
	campaign_state.start_skirmish(icon_a, icon_b)
	if npc.is_warping() or npc.warp_target != "":
		failures.append("cancel: expected start_skirmish to cancel the warping NPC's warp")
	icon_a.free()
	icon_b.free()

static func _check_distress(campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	var fleet: CampaignFleet = campaign_state.player_fleet
	if campaign_state.send_distress():
		failures.append("distress: expected send_distress refused when fuel covers the jump")
	fleet.cargo[Commodity.Type.FUEL] = 5.0
	campaign_state.credits = 500
	var quote := JumpRules.distress_quote(fleet, campaign_state.credits)
	if not campaign_state.send_distress():
		failures.append("distress: expected send_distress to succeed with enough credits")
	if not JumpRules.can_afford(fleet):
		failures.append("distress: expected the jump affordable after the distress fuel, fuel %.3f" % fleet.fuel_amount())
	if campaign_state.credits != 500 - int(quote["price"]):
		failures.append("distress: expected credits %d, got %d" % [500 - int(quote["price"]), campaign_state.credits])
	fleet.cargo[Commodity.Type.FUEL] = 5.0
	campaign_state.credits = 0
	if campaign_state.send_distress() or fleet.fuel_amount() != 5.0:
		failures.append("distress: expected send_distress refused without credits")

static func _check_jump_while_docked_undocks(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	var scene := await _open_scene(tree)
	scene._trigger_arrival(scene.station_nodes[campaign_state.galaxy.home_station().id])
	scene.base_overview_panel.trade_goods_button.pressed.emit()
	scene._open_jump_map()
	if not scene.jump_map_panel.visible or not tree.paused:
		failures.append("jump_while_docked_undocks: setup expected the jump map open and paused")
	scene._on_jump_requested("wexford")
	if scene.base_overview_panel.visible or scene.trade_panel.visible or scene._docked_base != null:
		failures.append("jump_while_docked_undocks: expected the overview and trade panel closed, overview=%s trade=%s" % [scene.base_overview_panel.visible, scene.trade_panel.visible])
	if tree.paused or scene.jump_map_panel.visible:
		failures.append("jump_while_docked_undocks: expected the map closed and the tree unpaused, paused=%s" % tree.paused)
	if not campaign_state.player_fleet.is_warping():
		failures.append("jump_while_docked_undocks: expected the player warping")
	await _close_scene(tree, campaign_state, scene)

static func _check_moves_ignored_mid_warp(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	var scene := await _open_scene(tree)
	scene._on_jump_requested("wexford")
	var target: Vector2 = scene.player_icon._move_target
	var start: Vector2 = scene.player_icon.position
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(200, 200)
	scene._unhandled_input(click)
	if scene.player_icon._move_target != target or scene._mouse_held:
		failures.append("moves ignored: expected a click mid-warp to leave the move target at %s, got %s" % [target, scene.player_icon._move_target])
	for i in 5:
		await tree.physics_frame
	if scene.player_icon.position != start:
		failures.append("moves ignored: expected the warping player to hold position, moved %s -> %s" % [start, scene.player_icon.position])
	var button: Button = scene.fleet_status_bar.jump_button
	await tree.process_frame
	if not button.text.begins_with("Cancel Warp ("):
		failures.append("moves ignored: expected the status bar to offer 'Cancel Warp (...)', got '%s'" % button.text)
	# The longer label must still fit the bar, clear of SpeedControls.
	UiLayoutCheck.check_panel_layout(scene.fleet_status_bar, failures)
	var speed_rect: Rect2 = scene.get_node("UILayer/SpeedControls/Background").get_global_rect()
	if button.get_global_rect().intersects(speed_rect):
		failures.append("moves ignored: expected the Cancel Warp button %s clear of SpeedControls %s" % [button.get_global_rect(), speed_rect])
	button.pressed.emit()
	if campaign_state.player_fleet.is_warping() or scene.jump_map_panel.visible:
		failures.append("moves ignored: expected Cancel Warp to cancel without opening the map")
	await tree.process_frame
	if button.text != "Jump":
		failures.append("moves ignored: expected the button back to 'Jump', got '%s'" % button.text)
	await _close_scene(tree, campaign_state, scene)

static func _check_caught_by_hostile(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	var scene := await _open_scene(tree)
	var pirate := _icon_for(scene, _first_fleet(campaign_state, "marrow_hideout", CampaignFleet.Role.COMBAT))
	var trader := _icon_for(scene, _first_fleet(campaign_state, "haven_exchange", CampaignFleet.Role.TRADER))
	if pirate == null or trader == null:
		failures.append("caught: setup expected a marrow pirate icon and a haven trader icon")
		await _close_scene(tree, campaign_state, scene)
		return
	# A fleeing trader is not hostile: touching it mid-warp changes nothing.
	scene._on_jump_requested("wexford")
	trader.position = scene.player_icon.position
	for i in 3:
		await tree.physics_frame
	if not campaign_state.player_fleet.is_warping() or scene.engage_prompt.visible:
		failures.append("caught: expected a neutral trader's contact to leave the warp running")
	trader.position = scene.player_icon.position + Vector2(400, 0)
	campaign_state.player_fleet.cancel_warp()
	for i in 3:
		await tree.physics_frame

	scene._on_jump_requested("wexford")
	pirate.reparent(scene.layer_for("haven"))
	pirate.fleet.system_id = "haven"
	pirate.position = scene.player_icon.position
	for i in 3:
		await tree.physics_frame
	if campaign_state.player_fleet.is_warping():
		failures.append("caught: expected the pirate's contact to cancel the warp")
	if not scene.engage_prompt.visible or scene._pending_enemy_icon != pirate:
		failures.append("caught: expected the engage prompt for the pirate, visible=%s" % scene.engage_prompt.visible)
	scene.engage_prompt.get_node("DisengageButton").pressed.emit()
	if not scene._player_hostile_contact():
		failures.append("caught: expected the pirate still overlapping after Disengage")
	if campaign_state.begin_player_warp("wexford", scene._player_hostile_contact()):
		failures.append("caught: expected a new warp refused while the pirate overlaps")
	var reason: String = campaign_state.jump_block_reason("wexford", scene._player_hostile_contact())
	if reason != "Hostile fleet in contact":
		failures.append("caught: expected 'Hostile fleet in contact', got '%s'" % reason)
	await _close_scene(tree, campaign_state, scene)

static func _check_switching_layers(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	var scene := await _open_scene(tree)
	scene._on_jump_requested("wexford")
	for i in 240:
		await tree.physics_frame
		if campaign_state.player_fleet.system_id == "wexford":
			break
	await tree.physics_frame
	var layer: Node2D = scene.layer_for("wexford")
	if scene.player_icon.get_parent() != layer:
		failures.append("switching layers: expected the player icon under wexford's layer")
	if not layer.visible or layer.position != Vector2.ZERO or scene.layer_for("haven").visible:
		failures.append("switching layers: expected wexford the visible layer at the origin, visible=%s at %s" % [layer.visible, layer.position])
	if scene.player_icon.position.distance_to(campaign_state.player_fleet.position) > 1.0:
		failures.append("switching layers: expected the icon at the fleet's arrival point")
	if scene.player_icon._warp_in_elapsed < 0.0:
		failures.append("switching layers: expected the arriving icon to play its warp-in")

	# NPC arrivals move their icon too, without changing the visible layer.
	var npc := _first_fleet(campaign_state, "kestrel_picket", CampaignFleet.Role.COMBAT)
	var npc_icon := _icon_for(scene, npc)
	scene._travel_target = npc_icon
	npc.start_warp("bastion")
	npc.warp_remaining = 0.05
	for i in 10:
		await tree.physics_frame
	if scene._travel_target != null:
		failures.append("switching layers: expected the player's travel target cleared when that NPC jumped away")
	if npc.system_id != "bastion" or npc_icon.get_parent() != scene.layer_for("bastion"):
		failures.append("switching layers: expected the NPC and its icon in bastion, fleet in %s" % npc.system_id)
	if npc_icon.position.distance_to(npc.position) > 20.0 or not layer.visible:
		failures.append("switching layers: expected the NPC icon at its arrival point with wexford still shown")
	await _close_scene(tree, campaign_state, scene)

static func _check_combat_round_trip_keeps_system_and_npc_warp(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	campaign_state.player_fleet.system_id = "wexford"
	campaign_state.player_fleet.position = Vector2(500, 300)
	var npc := _first_fleet(campaign_state, "kestrel_picket", CampaignFleet.Role.COMBAT)
	var scene := await _open_scene(tree)
	npc.start_warp("bastion")
	npc.warp_remaining = 2.0
	# Paused across the reload so a slow frame's physics catch-up can't eat the tolerance.
	tree.paused = true
	# As combat does: the campaign is rebuilt from CampaignState by a real scene change.
	tree.current_scene = scene
	tree.change_scene_to_file(CAMPAIGN_SCENE_PATH)
	var rebuilt: Node = null
	for i in 10:
		await tree.process_frame
		if tree.current_scene != null and tree.current_scene != scene:
			rebuilt = tree.current_scene
			break
	if rebuilt == null:
		failures.append("combat_round_trip: expected change_scene_to_file to rebuild the campaign")
		tree.current_scene = null
		await _close_scene(tree, campaign_state, scene)
		return
	await tree.process_frame
	await tree.process_frame
	if campaign_state.player_fleet.system_id != "wexford" or rebuilt.player_icon.get_parent() != rebuilt.layer_for("wexford") or not rebuilt.layer_for("wexford").visible:
		failures.append("combat_round_trip: expected the player still in (and showing) wexford, in %s" % campaign_state.player_fleet.system_id)
	# Tolerance covers physics catch-up on the slow frames of a rebuild; bigger NPC fleets mean more
	# icons to build, so those frames run longer (0.1 held with 3-ship fleets, ~0.15 lost with 10+).
	if absf(npc.warp_remaining - 2.0) > 0.5 or npc.warp_target != "bastion":
		failures.append("combat_round_trip: expected the NPC's warp kept at about 2.0 s to bastion, got %.3f to '%s'" % [npc.warp_remaining, npc.warp_target])
	tree.paused = false
	var before := npc.warp_remaining
	for i in 5:
		await tree.physics_frame
	if npc.warp_remaining >= before:
		failures.append("combat_round_trip: expected the NPC's warp to keep counting down, %.3f -> %.3f" % [before, npc.warp_remaining])
	tree.current_scene = null
	await _close_scene(tree, campaign_state, rebuilt)

static func _check_jump_map_blocked_by_modals(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	var scene := await _open_scene(tree)
	var j := InputEventAction.new()
	j.action = "open_jump_map"
	j.pressed = true
	scene._unhandled_input(j)
	if not scene.jump_map_panel.visible or not tree.paused:
		failures.append("modals: expected J to open the map and pause")
	scene.jump_map_panel.close_button.pressed.emit()
	if scene.jump_map_panel.visible or tree.paused:
		failures.append("modals: expected Close to hide the map and restore the unpaused state")
	tree.paused = true
	scene.fleet_status_bar.jump_button.pressed.emit()
	scene.jump_map_panel._unhandled_input(j)
	if scene.jump_map_panel.visible or not tree.paused:
		failures.append("modals: expected J on the open map to close it and keep the earlier pause")
	tree.paused = false

	# The Fleet button stays clickable under the map; it must not record the map's pause as its own.
	scene._open_jump_map()
	scene.fleet_status_bar.fleet_button.pressed.emit()
	if scene.fleet_management_panel.visible:
		failures.append("modals: expected the Fleet button ignored while the jump map is open")
	scene.jump_map_panel.close_button.pressed.emit()
	if tree.paused:
		failures.append("modals: expected closing the map to leave the game unpaused after a Fleet press")

	scene.engage_prompt.visible = true
	scene._unhandled_input(j)
	scene.fleet_status_bar.jump_button.pressed.emit()
	if scene.jump_map_panel.visible:
		failures.append("modals: expected J and the Jump button ignored while the engage prompt is visible")
	scene.engage_prompt.visible = false
	scene.respawn_panel.visible = true
	scene._unhandled_input(j)
	scene.fleet_status_bar.jump_button.pressed.emit()
	if scene.jump_map_panel.visible:
		failures.append("modals: expected J and the Jump button ignored while the respawn panel is visible")
	scene.respawn_panel.visible = false
	await _close_scene(tree, campaign_state, scene)
