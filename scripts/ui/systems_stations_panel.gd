class_name SystemsStationsPanel
extends Control

const SURPLUS_COLOR := Color("#5fe08a")
const DEFICIT_COLOR := Color("#ff7a6a")
const COLUMN_LABELS := ["COMMODITY", "STOCK", "BUY", "SELL"]
const COLUMN_WIDTHS := [160.0, 100.0, 100.0, 100.0]
const TOGGLE_WIDTH := 24.0

var _state: Node = null
# system_id -> bool, expanded state of the left tree.
var _expanded: Dictionary = {}
var _selected_station: String = ""
# "produces"/"consumes" -> {"sort_column": int, "ascending": bool}. -1 = unsorted.
var _table_state: Dictionary = {}
var _header_rule: StyleBoxFlat = null

@onready var tree_container: VBoxContainer = $Body/TreeScroll/TreeContainer
@onready var count_label: Label = $TopBar/CountLabel
@onready var close_button: Button = $TopBar/CloseButton
@onready var name_label: Label = $Body/DetailScroll/DetailContainer/Header/NameBox/NameLabel
@onready var system_label: Label = $Body/DetailScroll/DetailContainer/Header/NameBox/SystemLabel
@onready var badge_label: Label = $Body/DetailScroll/DetailContainer/Header/BadgeBox/BadgeFrame/BadgeLabel
@onready var visited_label: Label = $Body/DetailScroll/DetailContainer/Header/BadgeBox/VisitedLabel
@onready var population_value_label: Label = $Body/DetailScroll/DetailContainer/Tiles/PopulationTile/PopulationBox/PopulationValueLabel
@onready var wealth_value_label: Label = $Body/DetailScroll/DetailContainer/Tiles/WealthTile/WealthBox/WealthValueLabel
@onready var reputation_value_label: Label = $Body/DetailScroll/DetailContainer/Tiles/ReputationTile/ReputationBox/ReputationValueLabel
@onready var produces_table_container: VBoxContainer = $Body/DetailScroll/DetailContainer/ProducesTableContainer
@onready var consumes_table_container: VBoxContainer = $Body/DetailScroll/DetailContainer/ConsumesTableContainer

func _ready() -> void:
	close_button.pressed.connect(close)
	visible = false

func open_for(state: Node) -> void:
	_state = state
	_expanded = {}
	_selected_station = ""
	_reset_table_state()
	visible = true
	refresh()

func close() -> void:
	visible = false
	_state = null

func refresh() -> void:
	if _state == null:
		return
	_rebuild_tree()
	count_label.text = "%d LOGGED" % _state.visited.size()
	_refresh_detail()

func toggle_system(system_id: String) -> void:
	_expanded[system_id] = not _expanded.get(system_id, false)
	_rebuild_tree()

func select_station(station_id: String) -> void:
	_selected_station = station_id
	_reset_table_state()
	_rebuild_tree()
	_refresh_detail()

func selected_station() -> String:
	return _selected_station

func sort_table(table_key: String, column: int) -> void:
	var state: Dictionary = _table_state[table_key]
	if state["sort_column"] == column:
		state["ascending"] = not state["ascending"]
	else:
		state["sort_column"] = column
		state["ascending"] = true
	_refresh_detail()

func _reset_table_state() -> void:
	_table_state = {
		"produces": {"sort_column": -1, "ascending": true},
		"consumes": {"sort_column": -1, "ascending": true},
	}

func _rebuild_tree() -> void:
	for child in tree_container.get_children():
		tree_container.remove_child(child)
		child.queue_free()
	var system_ids: Array = _state.visited.keys()
	system_ids.sort_custom(func(a, b): return _state.galaxy.system(a).display_name < _state.galaxy.system(b).display_name)
	for system_id in system_ids:
		var sys: StarSystem = _state.galaxy.system(system_id)
		if sys == null:
			continue
		var stations: Array[StationData] = _state.galaxy.stations_in(system_id)
		tree_container.add_child(_build_system_row(sys, stations.size()))
		if _expanded.get(system_id, false):
			for station in stations:
				tree_container.add_child(_build_station_row(station))

func _build_system_row(sys: StarSystem, station_count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var toggle := Button.new()
	toggle.custom_minimum_size = Vector2(TOGGLE_WIDTH, 0)
	toggle.text = "-" if _expanded.get(sys.id, false) else "+"
	toggle.pressed.connect(toggle_system.bind(sys.id))
	var labels := VBoxContainer.new()
	var name := Label.new()
	name.text = sys.display_name
	var count := Label.new()
	count.text = "Stations - %d" % station_count
	labels.add_child(name)
	labels.add_child(count)
	row.add_child(toggle)
	row.add_child(labels)
	return row

func _build_station_row(station: StationData) -> HBoxContainer:
	var row := HBoxContainer.new()
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(9, 9)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = CampaignFleetIcon.FACTION_COLORS.get(station.owner, CampaignFleetIcon.FACTION_COLORS[CampaignFleet.Faction.NEUTRAL])
	dot_style.corner_radius_top_left = 5
	dot_style.corner_radius_top_right = 5
	dot_style.corner_radius_bottom_left = 5
	dot_style.corner_radius_bottom_right = 5
	dot.add_theme_stylebox_override("panel", dot_style)
	var button := Button.new()
	button.flat = true
	button.text = station.display_name
	if station.id == _selected_station:
		button.add_theme_color_override("font_color", Color.WHITE)
	button.pressed.connect(select_station.bind(station.id))
	row.add_child(dot)
	row.add_child(button)
	return row

func _refresh_detail() -> void:
	if _selected_station == "":
		name_label.text = ""
		system_label.text = "System: "
		badge_label.text = ""
		visited_label.text = ""
		population_value_label.text = "0"
		population_value_label.remove_theme_color_override("font_color")
		wealth_value_label.text = ""
		reputation_value_label.text = ""
		_build_table(produces_table_container, [], "produces")
		_build_table(consumes_table_container, [], "consumes")
		return
	var station: StationData = _state.galaxy.station(_selected_station)
	var snapshot: Dictionary = _state.station_snapshots.get(_selected_station, {})
	name_label.text = station.display_name.to_upper()
	system_label.text = "System: %s" % _state.galaxy.system(station.system_id).display_name
	var faction: PowerFaction = _state.power_faction_for(station.owner)
	badge_label.text = (faction.display_name if faction != null else CampaignFleet.Faction.keys()[station.owner].capitalize()).to_upper()
	var day: int = snapshot.get("day", 0)
	var days_ago: int = _state.game_day() - day
	visited_label.text = "Visited: Day %d (%d days ago)" % [day, days_ago]
	_update_population_tile(snapshot)
	_update_wealth_tile(snapshot)
	_update_reputation_tile(snapshot)
	_build_table(produces_table_container, snapshot.get("produces", []), "produces")
	_build_table(consumes_table_container, snapshot.get("consumes", []), "consumes")

func _update_population_tile(snapshot: Dictionary) -> void:
	var population: float = snapshot.get("population", 0.0)
	var trend: int = snapshot.get("population_trend", 0)
	if trend > 0:
		population_value_label.text = "+%d" % roundi(population)
		population_value_label.add_theme_color_override("font_color", SURPLUS_COLOR)
	elif trend < 0:
		population_value_label.text = "-%d" % roundi(population)
		population_value_label.add_theme_color_override("font_color", DEFICIT_COLOR)
	else:
		population_value_label.text = "%d" % roundi(population)
		population_value_label.remove_theme_color_override("font_color")

func _update_wealth_tile(snapshot: Dictionary) -> void:
	var wealth_level: int = snapshot.get("wealth_level", BaseEconomy.WealthLevel.MIDDLING)
	wealth_value_label.text = BaseOverviewPanel.WEALTH_NAMES[wealth_level]

func _update_reputation_tile(snapshot: Dictionary) -> void:
	var reputation = snapshot.get("reputation")
	reputation_value_label.text = "-" if reputation == null else "%+d" % roundi(reputation)

func _header_rule_style() -> StyleBoxFlat:
	if _header_rule == null:
		_header_rule = StyleBoxFlat.new()
		_header_rule.bg_color = Color(0, 0, 0, 0)
		_header_rule.border_width_bottom = 1
		_header_rule.border_color = Color("#1a4e8a")
	return _header_rule

func _build_table(container: VBoxContainer, rows_data: Array, table_key: String) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	var state: Dictionary = _table_state[table_key]
	var header := HBoxContainer.new()
	for i in COLUMN_LABELS.size():
		var header_button := Button.new()
		header_button.flat = true
		header_button.custom_minimum_size = Vector2(COLUMN_WIDTHS[i], 0)
		var arrow := "  "
		if state["sort_column"] == i:
			arrow = " ^" if state["ascending"] else " v"
		header_button.text = COLUMN_LABELS[i] + arrow
		header_button.pressed.connect(sort_table.bind(table_key, i))
		header.add_child(header_button)
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", _header_rule_style())
	header_panel.add_child(header)
	container.add_child(header_panel)
	for row in _sorted_rows(rows_data, state):
		container.add_child(_build_table_row(row))

func _sorted_rows(rows_data: Array, state: Dictionary) -> Array:
	var column: int = state["sort_column"]
	if column < 0:
		return rows_data.duplicate()
	var sorted_rows: Array = rows_data.duplicate()
	# Always sort ascending, then reverse for descending, rather than flipping the
	# comparator: sort_custom is not stable, so an independently-run ">" comparator on
	# tied keys is not guaranteed to be the exact reverse of the "<" comparator's order.
	sorted_rows.sort_custom(func(a, b):
		var key_a = _sort_key(a, column)
		var key_b = _sort_key(b, column)
		return key_a < key_b)
	if not state["ascending"]:
		sorted_rows.reverse()
	return sorted_rows

func _sort_key(row: Dictionary, column: int):
	match column:
		0:
			return Commodity.NAMES[row["commodity"]]
		1:
			return row["stock"] - Commodity.TARGET_STOCK[row["commodity"]]
		2:
			return row["buy"]
		3:
			return row["sell"]
	return 0

func _build_table_row(row: Dictionary) -> HBoxContainer:
	var box := HBoxContainer.new()
	var commodity_label := Label.new()
	commodity_label.custom_minimum_size = Vector2(COLUMN_WIDTHS[0], 0)
	commodity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	commodity_label.text = Commodity.NAMES[row["commodity"]]
	var diff: float = row["stock"] - Commodity.TARGET_STOCK[row["commodity"]]
	var stock_label := Label.new()
	stock_label.custom_minimum_size = Vector2(COLUMN_WIDTHS[1], 0)
	stock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stock_label.text = "%+d" % roundi(diff)
	stock_label.add_theme_color_override("font_color", SURPLUS_COLOR if diff >= 0.0 else DEFICIT_COLOR)
	var buy_label := Label.new()
	buy_label.custom_minimum_size = Vector2(COLUMN_WIDTHS[2], 0)
	buy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	buy_label.text = str(row["buy"])
	var sell_label := Label.new()
	sell_label.custom_minimum_size = Vector2(COLUMN_WIDTHS[3], 0)
	sell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sell_label.text = str(row["sell"])
	for widget in [commodity_label, stock_label, buy_label, sell_label]:
		box.add_child(widget)
	return box
