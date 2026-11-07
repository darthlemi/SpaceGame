extends RefCounted

const SystemsStationsPanelScene = preload("res://scenes/ui/systems_stations_panel.tscn")
const UiLayoutCheck = preload("res://tests/ui_layout_check.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.new_game()

	var panel = SystemsStationsPanelScene.instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	if panel.visible:
		failures.append("setup: expected the panel hidden until opened")

	_check_tree(panel, campaign_state, failures)
	_check_detail(panel, campaign_state, failures)
	await _check_sorting(tree, panel, campaign_state, failures)
	await _check_layout(tree, panel, campaign_state, failures)

	panel.queue_free()
	await tree.process_frame
	campaign_state.reset()
	return failures

static func _check_tree(panel, campaign_state, failures: Array[String]) -> void:
	panel.open_for(campaign_state)
	if not panel.visible:
		failures.append("tree: expected open_for to show the panel")
	if panel.count_label.text != "%d LOGGED" % campaign_state.visited.size():
		failures.append("tree: expected the count label to show %d, got '%s'" % [campaign_state.visited.size(), panel.count_label.text])
	var home_id: String = campaign_state.player_fleet.system_id
	var stations: Array[StationData] = campaign_state.galaxy.stations_in(home_id)
	# new_game() only ever visits the home system, so exactly one system row exists, collapsed.
	if panel.tree_container.get_child_count() != 1:
		failures.append("tree: expected exactly 1 visited system row at new game, got %d" % panel.tree_container.get_child_count())
	panel.toggle_system(home_id)
	var expanded_count := 1 + stations.size()
	if panel.tree_container.get_child_count() != expanded_count:
		failures.append("tree: expected %d rows (system + %d stations) after expanding, got %d" % [expanded_count, stations.size(), panel.tree_container.get_child_count()])
	panel.toggle_system(home_id)
	if panel.tree_container.get_child_count() != 1:
		failures.append("tree: expected the station rows to collapse again")

static func _check_detail(panel, campaign_state, failures: Array[String]) -> void:
	var home_id: String = campaign_state.player_fleet.system_id
	var station: StationData = campaign_state.galaxy.stations_in(home_id)[0]
	panel.select_station(station.id)
	if panel.selected_station() != station.id:
		failures.append("detail: expected select_station to select '%s', got '%s'" % [station.id, panel.selected_station()])
	if panel.name_label.text != station.display_name.to_upper():
		failures.append("detail: expected name label '%s', got '%s'" % [station.display_name.to_upper(), panel.name_label.text])
	var sys: StarSystem = campaign_state.galaxy.system(home_id)
	if panel.system_label.text != "System: %s" % sys.display_name:
		failures.append("detail: expected system label 'System: %s', got '%s'" % [sys.display_name, panel.system_label.text])
	var snapshot: Dictionary = campaign_state.station_snapshots[station.id]
	var days_ago: int = campaign_state.game_day() - snapshot["day"]
	var expected_visited := "Visited: Day %d (%d days ago)" % [snapshot["day"], days_ago]
	if panel.visited_label.text != expected_visited:
		failures.append("detail: expected '%s', got '%s'" % [expected_visited, panel.visited_label.text])
	var faction: PowerFaction = campaign_state.power_faction_for(station.owner)
	var expected_badge: String = (faction.display_name if faction != null else CampaignFleet.Faction.keys()[station.owner].capitalize()).to_upper()
	if panel.badge_label.text != expected_badge:
		failures.append("detail: expected badge '%s', got '%s'" % [expected_badge, panel.badge_label.text])
	var produces_rows: int = panel.produces_table_container.get_child_count() - 1
	if produces_rows != snapshot["produces"].size():
		failures.append("detail: expected %d produces rows, got %d" % [snapshot["produces"].size(), produces_rows])
	var consumes_rows: int = panel.consumes_table_container.get_child_count() - 1
	if consumes_rows != snapshot["consumes"].size():
		failures.append("detail: expected %d consumes rows, got %d" % [snapshot["consumes"].size(), consumes_rows])

static func _check_sorting(tree: SceneTree, panel, campaign_state, failures: Array[String]) -> void:
	for id in campaign_state.galaxy.systems:
		campaign_state.record_visit(id)
	var target_id := ""
	for sid in campaign_state.station_snapshots:
		if campaign_state.station_snapshots[sid]["produces"].size() >= 2:
			target_id = sid
			break
	if target_id == "":
		failures.append("sort: expected at least one station with 2+ produced commodities in the galaxy")
		return
	panel.select_station(target_id)
	var produces: Array = campaign_state.station_snapshots[target_id]["produces"]
	panel.sort_table("produces", 1)
	var ascending_names := _row_commodity_names(panel.produces_table_container)
	var expected_asc := produces.duplicate()
	expected_asc.sort_custom(func(a, b): return (a["stock"] - Commodity.TARGET_STOCK[a["commodity"]]) < (b["stock"] - Commodity.TARGET_STOCK[b["commodity"]]))
	var expected_asc_names: Array[String] = []
	for row in expected_asc:
		expected_asc_names.append(Commodity.NAMES[row["commodity"]])
	if ascending_names != expected_asc_names:
		failures.append("sort: expected produces ascending by stock %s, got %s" % [expected_asc_names, ascending_names])
	panel.sort_table("produces", 1)
	var descending_names := _row_commodity_names(panel.produces_table_container)
	expected_asc_names.reverse()
	if descending_names != expected_asc_names:
		failures.append("sort: expected produces descending by stock %s, got %s" % [expected_asc_names, descending_names])
	await tree.process_frame

static func _row_commodity_names(table_container: VBoxContainer) -> Array[String]:
	var names: Array[String] = []
	var children := table_container.get_children()
	for i in range(1, children.size()):
		var row: HBoxContainer = children[i]
		names.append((row.get_child(0) as Label).text)
	return names

static func _check_layout(tree: SceneTree, panel, campaign_state, failures: Array[String]) -> void:
	var home_id: String = campaign_state.player_fleet.system_id
	panel.toggle_system(home_id)
	panel.select_station(campaign_state.galaxy.stations_in(home_id)[0].id)
	await tree.process_frame
	UiLayoutCheck.check_panel_layout(panel, failures)
	if panel.get_node("Background").mouse_filter != Control.MOUSE_FILTER_STOP:
		failures.append("layout: expected the Background to stop clicks reaching the world below")
