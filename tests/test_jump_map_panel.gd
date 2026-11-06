extends RefCounted

const JumpMapPanelScene = preload("res://scenes/ui/jump_map_panel.tscn")
const UiLayoutCheck = preload("res://tests/ui_layout_check.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.new_game()
	var panel = JumpMapPanelScene.instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	if panel.visible:
		failures.append("setup: expected the panel hidden until opened")

	_check_shown_systems(panel, campaign_state, failures)
	_check_not_connected(panel, campaign_state, failures)
	await _check_low_fuel(tree, panel, campaign_state, failures)
	_check_docked(panel, campaign_state, failures)
	_check_signals(panel, campaign_state, failures)
	_check_click_select(panel, campaign_state, failures)
	await _check_layout(tree, panel, campaign_state, failures)

	panel.queue_free()
	await tree.process_frame
	campaign_state.reset()
	return failures

static func _check_shown_systems(panel, campaign_state, failures: Array[String]) -> void:
	panel.open_for(campaign_state, false, false)
	if not panel.visible:
		failures.append("shown: expected open_for to show the panel")
	var shown: Array = panel.node_points.keys()
	shown.sort()
	var expected := ["haven", "kestrel", "marrow", "northgate", "wexford"]
	if shown != expected:
		failures.append("shown: expected exactly %s drawn at a new game, got %s" % [expected, shown])
	if panel.selected_system() != "haven":
		failures.append("shown: expected the current system selected on open, got '%s'" % panel.selected_system())
	panel.select_system("wexford")
	if panel.selected_system() != "wexford":
		failures.append("shown: expected select_system to select wexford")
	if panel.node_color("wexford") != panel.UNKNOWN_COLOR:
		failures.append("shown: expected wexford drawn as unknown, got %s" % panel.node_color("wexford"))
	var fleet: CampaignFleet = campaign_state.player_fleet
	var cost_line := "Jump cost: %.1f fuel (you have %.1f)" % [JumpRules.jump_cost(fleet), fleet.fuel_amount()]
	if panel.info_label.text != "Unknown system\n" + cost_line:
		failures.append("shown: expected the unknown info text, got '%s'" % panel.info_label.text)
	if panel.jump_button.disabled or panel.reason_label.text != "":
		failures.append("shown: expected an affordable connected jump enabled with no reason, disabled=%s reason='%s'" % [panel.jump_button.disabled, panel.reason_label.text])
	if panel.distress_button.visible:
		failures.append("shown: expected no distress button while a jump is affordable")
	# Visited systems show the snapshot, coloured by their most common owner.
	panel.select_system("haven")
	var haven: Dictionary = campaign_state.last_seen["haven"]
	var expected_info := "Haven - %s - %d stations - Danger %d\n%s" % [panel.owner_text(haven["owners"]), haven["stations"], haven["tier"], cost_line]
	if panel.info_label.text != expected_info:
		failures.append("shown: expected haven info '%s', got '%s'" % [expected_info, panel.info_label.text])
	campaign_state.visited["wexford"] = true
	campaign_state.last_seen["wexford"] = {"owners": [CampaignFleet.Faction.FREEHOLD], "stations": 1, "pirates_seen": false, "tier": 1}
	panel.select_system("wexford")
	if not panel.info_label.text.begins_with("Wexford - %s - 1 station - Danger 1" % panel.owner_text([CampaignFleet.Faction.FREEHOLD])):
		failures.append("shown: expected a singular '1 station' for wexford, got '%s'" % panel.info_label.text)
	campaign_state.visited.erase("wexford")
	campaign_state.last_seen.erase("wexford")
	panel.select_system("haven")
	if not panel.jump_button.disabled or panel.reason_label.text != "You are here":
		failures.append("shown: expected the current system's jump disabled with 'You are here', reason='%s'" % panel.reason_label.text)

static func _check_not_connected(panel, campaign_state, failures: Array[String]) -> void:
	campaign_state.discovered["greenreach"] = true
	panel.refresh()
	if not panel.node_points.has("greenreach"):
		failures.append("not connected: expected a newly discovered greenreach drawn after refresh")
	panel.select_system("greenreach")
	if not panel.jump_button.disabled or panel.reason_label.text != "Not connected":
		failures.append("not connected: expected greenreach disabled with 'Not connected', disabled=%s reason='%s'" % [panel.jump_button.disabled, panel.reason_label.text])
	campaign_state.discovered.erase("greenreach")

static func _check_low_fuel(tree: SceneTree, panel, campaign_state, failures: Array[String]) -> void:
	var fleet: CampaignFleet = campaign_state.player_fleet
	fleet.cargo[Commodity.Type.FUEL] = 5.0
	panel.open_for(campaign_state, false, false)
	panel.select_system("wexford")
	if not panel.jump_button.disabled or not panel.reason_label.text.begins_with("Not enough fuel"):
		failures.append("low fuel: expected wexford disabled with 'Not enough fuel...', disabled=%s reason='%s'" % [panel.jump_button.disabled, panel.reason_label.text])
	var quote := JumpRules.distress_quote(fleet, campaign_state.credits)
	var expected := "Distress signal (%d cr for %.1f fuel)" % [quote["price"], quote["fuel"]]
	if not panel.distress_button.visible or panel.distress_button.text != expected or panel.distress_button.disabled:
		failures.append("low fuel: expected an enabled distress button '%s', visible=%s text='%s'" % [expected, panel.distress_button.visible, panel.distress_button.text])
	await tree.process_frame
	UiLayoutCheck.check_panel_layout(panel, failures)

	# Unaffordable distress stays visible but disabled, with its reason.
	campaign_state.credits = 0
	panel.refresh()
	if not panel.distress_button.visible or not panel.distress_button.disabled:
		failures.append("low fuel: expected the distress button disabled with no credits")
	if not panel.reason_label.text.contains("Not enough credits"):
		failures.append("low fuel: expected the distress reason shown, got '%s'" % panel.reason_label.text)
	await tree.process_frame
	UiLayoutCheck.check_panel_layout(panel, failures)
	campaign_state.credits = 500

static func _check_docked(panel, campaign_state, failures: Array[String]) -> void:
	campaign_state.player_fleet.cargo[Commodity.Type.FUEL] = 5.0
	panel.open_for(campaign_state, true, false)
	panel.select_system("wexford")
	if panel.distress_button.visible:
		failures.append("docked: expected no distress button while docked")
	panel.open_for(campaign_state, false, true)
	campaign_state.player_fleet.cargo[Commodity.Type.FUEL] = 30.0
	panel.select_system("wexford")
	if not panel.jump_button.disabled or panel.reason_label.text != "Hostile fleet in contact":
		failures.append("hostile: expected wexford disabled with 'Hostile fleet in contact', reason='%s'" % panel.reason_label.text)

static func _check_signals(panel, campaign_state, failures: Array[String]) -> void:
	campaign_state.player_fleet.cargo[Commodity.Type.FUEL] = 30.0
	panel.open_for(campaign_state, false, false)
	panel.select_system("wexford")
	var jumps: Array = []
	var on_jump := func(system_id: String): jumps.append(system_id)
	panel.jump_requested.connect(on_jump)
	panel.jump_button.pressed.emit()
	panel.jump_requested.disconnect(on_jump)
	if jumps != ["wexford"]:
		failures.append("signals: expected jump_requested('wexford'), got %s" % [jumps])
	var events: Array = []
	var on_closed := func(): events.append("closed")
	var on_distress := func(): events.append("distress")
	panel.closed.connect(on_closed)
	panel.distress_requested.connect(on_distress)
	panel.distress_button.pressed.emit()
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	panel._unhandled_input(esc)
	panel.closed.disconnect(on_closed)
	panel.distress_requested.disconnect(on_distress)
	if events != ["distress", "closed"] or panel.visible:
		failures.append("signals: expected distress_requested then Esc to close, got %s visible=%s" % [events, panel.visible])
	panel.open_for(campaign_state, false, false)
	var j := InputEventAction.new()
	j.action = "open_jump_map"
	j.pressed = true
	panel._unhandled_input(j)
	if panel.visible:
		failures.append("signals: expected J to close the panel")

static func _check_click_select(panel, campaign_state, failures: Array[String]) -> void:
	panel.open_for(campaign_state, false, false)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = panel.node_points["kestrel"] + Vector2(10, 0)
	panel.map_area.gui_input.emit(click)
	if panel.selected_system() != "kestrel":
		failures.append("click: expected a click 10 px from kestrel to select it, got '%s'" % panel.selected_system())
	click.position = panel.node_points["kestrel"] + Vector2(0, 40)
	panel.map_area.gui_input.emit(click)
	if panel.selected_system() != "kestrel":
		failures.append("click: expected a click 40 px from every system to keep the selection, got '%s'" % panel.selected_system())

static func _check_layout(tree: SceneTree, panel, campaign_state, failures: Array[String]) -> void:
	campaign_state.player_fleet.cargo[Commodity.Type.FUEL] = 30.0
	for id in campaign_state.galaxy.systems:
		campaign_state.record_visit(id)
	panel.open_for(campaign_state, false, false)
	panel.select_system("kestrel")
	await tree.process_frame
	UiLayoutCheck.check_panel_layout(panel, failures)
	if panel.get_node("Background").mouse_filter != Control.MOUSE_FILTER_STOP:
		failures.append("layout: expected the Background to stop clicks reaching the map below")
	var rect: Rect2 = panel.get_global_rect()
	if rect != Rect2(10, 80, 1132, 558):
		failures.append("layout: expected the panel at (10, 80) to (1142, 638), got %s" % rect)
	var area: Rect2 = Rect2(Vector2.ZERO, panel.map_area.size)
	for id in panel.node_points:
		if not area.has_point(panel.node_points[id]):
			failures.append("layout: expected %s inside MapArea, at %s" % [id, panel.node_points[id]])
