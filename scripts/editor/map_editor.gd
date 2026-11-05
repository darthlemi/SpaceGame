class_name MapEditor
extends Control

# Standalone galaxy editor (see tools\map_editor.bat). A thin view: every edit goes through
# MapEditModel and is checked by GalaxyValidator; Save is blocked while blockers exist.

const ART_DIR := "res://assets/sprites/stations"
const INSPECTOR_WIDTH := 380.0
const ERRORS_HEIGHT := 96.0
const STATION_LIST_HEIGHT := 110.0
const BLOCK_COLOR := Color(0.95, 0.35, 0.35, 1.0)
const WARN_COLOR := Color(0.95, 0.8, 0.3, 1.0)
const NEW_SYSTEM_NAME := "New System"

@export var auto_load := true

var model: MapEditModel = MapEditModel.from_document(_empty_document())
var save_path: String = GalaxyDocument.PATH
var selected_system: String = ""
var selected_station: String = ""

var canvas: MapCanvas
var errors_list: ItemList
var station_list: ItemList
var station_box: VBoxContainer
var system_fields_box: VBoxContainer
var all_stations_toggle: CheckButton
var save_button: Button
var load_button: Button
var validate_button: Button
var status_label: Label
var dirty_label: Label
var tabs: TabContainer
var map_tab: HBoxContainer

var _findings: Array[Dictionary] = []
var _confirm: ConfirmationDialog
var _confirm_action: Callable = Callable()

func _ready() -> void:
	_build_ui()
	canvas.system_selected.connect(select_system)
	canvas.system_moved.connect(_on_system_moved)
	canvas.link_requested.connect(_on_link_requested)
	canvas.link_delete_requested.connect(_on_link_delete_requested)
	canvas.add_requested.connect(_on_add_requested)
	if auto_load:
		reload()
	else:
		_refresh_all()

static func _empty_document() -> Dictionary:
	return {"version": GalaxyDocument.VERSION, "start_system": "", "presets": GalaxyData.default_presets(),
		"systems": [], "links": [], "stations": []}

# --- public API (also what the tests drive) ---

func load_document(doc: Dictionary) -> void:
	model = MapEditModel.from_document(doc)
	selected_system = ""
	selected_station = ""
	canvas.selected = ""
	canvas.set_document(model.doc)
	_refresh_all()

# Re-reads the saved file, discarding unsaved edits.
func reload() -> void:
	var result := GalaxyDocument.load_file(save_path)
	if not result["ok"]:
		_set_status("Cannot load %s: %s" % [save_path, result["error"]])
		return
	load_document(result["doc"])
	_set_status("Loaded %s" % save_path)

func validate() -> Array[Dictionary]:
	_findings = GalaxyValidator.validate(model.doc)
	_show_findings()
	return _findings

# False when blocked or when the file already matched (nothing written).
func save() -> bool:
	var findings := validate()
	if GalaxyValidator.has_blockers(findings):
		_set_status("Save blocked: fix the red items in the list")
		return false
	var wrote := GalaxyDocument.save_file(model.doc, save_path)
	model.dirty = false
	_update_dirty()
	_set_status("Saved %s" % save_path if wrote else "No changes to save")
	return wrote

func select_system(id: String) -> void:
	if model.doc["systems"].filter(func(s): return s["id"] == id).is_empty():
		return
	selected_system = id
	canvas.selected = id
	var station_index := model.station_index(selected_station)
	if station_index >= 0 and model.doc["stations"][station_index]["system"] != id:
		selected_station = ""
	canvas.queue_redraw()
	_rebuild_system_fields()
	_rebuild_station_list()
	_rebuild_station_box()

func select_station(id: String) -> void:
	var index := model.station_index(id)
	if index < 0:
		return
	var system_id: String = model.doc["stations"][index]["system"]
	if system_id != selected_system:
		select_system(system_id)
	selected_station = id
	_rebuild_station_list()
	_rebuild_station_box()

# Clicking a finding selects what it names.
func select_finding(index: int) -> void:
	if index < 0 or index >= _findings.size():
		return
	var target: Dictionary = _findings[index]["target"]
	match target["kind"]:
		"system":
			select_system(target["id"])
		"station":
			select_station(target["id"])
		"link":
			select_system(str(target["id"]).split("|")[0])

# --- UI construction ---

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.name = "Layout"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)
	root.add_child(_build_top_bar())
	tabs = TabContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	map_tab = HBoxContainer.new()
	map_tab.name = "Map"
	tabs.add_child(map_tab)
	map_tab.add_child(_build_left_column())
	map_tab.add_child(_build_inspector())
	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(_on_confirmed)
	add_child(_confirm)

func _build_top_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.name = "TopBar"
	var group := ButtonGroup.new()
	for entry in [["Move", MapCanvas.Mode.MOVE], ["Link", MapCanvas.Mode.LINK], ["Add System", MapCanvas.Mode.ADD]]:
		var button := Button.new()
		button.name = "Mode%s" % str(entry[0]).replace(" ", "")
		button.text = entry[0]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = entry[1] == MapCanvas.Mode.MOVE
		button.pressed.connect(func() -> void: canvas.set_mode(entry[1]))
		bar.add_child(button)
	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	bar.add_child(status_label)
	dirty_label = Label.new()
	dirty_label.name = "DirtyLabel"
	bar.add_child(dirty_label)
	validate_button = _top_button(bar, "ValidateButton", "Validate", validate)
	load_button = _top_button(bar, "LoadButton", "Load", _on_load_pressed)
	save_button = _top_button(bar, "SaveButton", "Save", save)
	return bar

func _top_button(parent: Node, button_name: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _build_left_column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "LeftColumn"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas = MapCanvas.new()
	canvas.name = "Canvas"
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(300.0, 200.0)
	column.add_child(canvas)
	errors_list = ItemList.new()
	errors_list.name = "ErrorsList"
	errors_list.custom_minimum_size.y = ERRORS_HEIGHT
	errors_list.item_selected.connect(select_finding)
	column.add_child(errors_list)
	return column

func _build_inspector() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Inspector"
	scroll.custom_minimum_size.x = INSPECTOR_WIDTH
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Clicks stop here so they never reach the canvas behind.
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var title := Label.new()
	title.name = "SystemTitle"
	title.text = "System"
	box.add_child(title)
	system_fields_box = VBoxContainer.new()
	system_fields_box.name = "SystemFields"
	box.add_child(system_fields_box)
	var delete_system := Button.new()
	delete_system.name = "DeleteSystemButton"
	delete_system.text = "Delete system"
	delete_system.pressed.connect(_on_delete_system_pressed)
	box.add_child(delete_system)
	var stations_title := Label.new()
	stations_title.name = "StationsTitle"
	stations_title.text = "Stations"
	box.add_child(stations_title)
	all_stations_toggle = CheckButton.new()
	all_stations_toggle.name = "AllStationsToggle"
	all_stations_toggle.text = "All stations"
	all_stations_toggle.toggled.connect(func(_on: bool) -> void: _rebuild_station_list())
	box.add_child(all_stations_toggle)
	station_list = ItemList.new()
	station_list.name = "StationList"
	station_list.custom_minimum_size.y = STATION_LIST_HEIGHT
	station_list.item_selected.connect(func(index: int) -> void: select_station(str(station_list.get_item_metadata(index))))
	box.add_child(station_list)
	var add_station := Button.new()
	add_station.name = "AddStationButton"
	add_station.text = "+ Add station"
	add_station.pressed.connect(_on_add_station_pressed)
	box.add_child(add_station)
	station_box = VBoxContainer.new()
	station_box.name = "StationEditorBox"
	station_box.visible = false
	box.add_child(station_box)
	return scroll

# --- rebuilding views ---

func _refresh_all() -> void:
	canvas.refresh()
	_rebuild_system_fields()
	_rebuild_station_list()
	_rebuild_station_box()
	_update_dirty()
	validate()

# After a model edit. Field rows keep their controls (and focus) when rebuild_fields is false.
func _after_edit(rebuild_fields: bool = true) -> void:
	canvas.refresh()
	if rebuild_fields:
		_rebuild_system_fields()
		_rebuild_station_box()
	_rebuild_station_list()
	_update_dirty()
	validate()

func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

func _choices_for(spec: Dictionary) -> Array:
	var choices = spec.get("choices", [])
	if typeof(choices) == TYPE_ARRAY:
		return choices
	match choices:
		"systems":
			var ids: Array = []
			for sys in model.doc["systems"]:
				ids.append(sys["id"])
			ids.sort()
			return ids
		"owners":
			return CampaignFleet.Faction.keys()
		"art":
			var names: Array = []
			for file in DirAccess.get_files_at(ART_DIR):
				if file.ends_with(".png"):
					names.append(file.get_basename())
			names.sort()
			return names
	return []

func _rebuild_system_fields() -> void:
	_clear(system_fields_box)
	var index := _system_index(selected_system)
	if index < 0:
		return
	var entry: Dictionary = model.doc["systems"][index]
	for spec in EditorFields.SYSTEM_FIELDS:
		system_fields_box.add_child(EditorFields.make_row(spec, EditorFields.value_of(entry, spec), _choices_for(spec),
				func(value) -> void: _on_system_field_changed(spec, value)))

func _rebuild_station_list() -> void:
	station_list.clear()
	var shown: Array = model.doc["stations"] if all_stations_toggle.button_pressed else model.stations_in(selected_system)
	var ordered := shown.duplicate()
	ordered.sort_custom(func(a, b): return MapEditModel.station_id_of(a) < MapEditModel.station_id_of(b))
	for st in ordered:
		var id := MapEditModel.station_id_of(st)
		var text := "%s (%s)" % [st["name"], str(st["owner"]).capitalize()]
		if all_stations_toggle.button_pressed:
			text += " - %s" % st["system"]
		var row := station_list.add_item(text)
		station_list.set_item_metadata(row, id)
		if id == selected_station:
			station_list.select(row)

# Task 4 replaces the read-only slot text with the full station editor.
func _rebuild_station_box() -> void:
	_clear(station_box)
	var index := model.station_index(selected_station)
	station_box.visible = index >= 0
	if index < 0:
		return
	var entry: Dictionary = model.doc["stations"][index]
	var title := Label.new()
	title.name = "StationTitle"
	title.text = "Station: %s" % entry["name"]
	station_box.add_child(title)
	for spec in EditorFields.STATION_FIELDS:
		station_box.add_child(EditorFields.make_row(spec, EditorFields.value_of(entry, spec), _choices_for(spec),
				func(value) -> void: _on_station_field_changed(spec, value)))
	var slots := Label.new()
	slots.name = "SlotsLabel"
	slots.text = "Slots: %s" % ", ".join(entry["slots"].map(func(s): return str(s if typeof(s) == TYPE_STRING else s["preset"])))
	station_box.add_child(slots)

func _show_findings() -> void:
	errors_list.clear()
	canvas.flags.clear()
	for f in _findings:
		var block: bool = f["severity"] == "block"
		var row := errors_list.add_item("%s %s" % ["[BLOCK]" if block else "[warn]", f["message"]])
		errors_list.set_item_custom_fg_color(row, BLOCK_COLOR if block else WARN_COLOR)
		var target: Dictionary = f["target"]
		if target["kind"] == "system" and not (canvas.flags.get(target["id"], "") == "block"):
			canvas.flags[target["id"]] = f["severity"]
	canvas.queue_redraw()

func _update_dirty() -> void:
	dirty_label.text = "*" if model.dirty else ""

func _set_status(text: String) -> void:
	status_label.text = text

func _system_index(id: String) -> int:
	var systems: Array = model.doc["systems"]
	for i in systems.size():
		if systems[i]["id"] == id:
			return i
	return -1

# --- edits ---

func _on_system_field_changed(spec: Dictionary, value) -> void:
	if spec["key"] == "map":
		model.move_system(selected_system, value)
	else:
		model.set_system_field(selected_system, spec["key"], null if EditorFields.is_default(spec, value) else value)
	_after_edit(false)

func _on_station_field_changed(spec: Dictionary, value) -> void:
	model.set_station_field(selected_station, spec["key"], null if EditorFields.is_default(spec, value) else value)
	if spec["key"] == "name":
		selected_station = GalaxyDocument.station_id(str(value))
	_after_edit(false)

func _on_system_moved(id: String, map: Vector2) -> void:
	model.move_system(id, map)
	_after_edit(true)

func _on_link_requested(a: String, b: String) -> void:
	if model.link(a, b):
		_after_edit(false)

func _on_link_delete_requested(a: String, b: String) -> void:
	if model.unlink(a, b):
		_after_edit(false)

func _on_add_requested(map: Vector2) -> void:
	var id := model.add_system(NEW_SYSTEM_NAME, map)
	_after_edit(false)
	select_system(id)

func _on_add_station_pressed() -> void:
	if selected_system == "":
		_set_status("Select a system first")
		return
	var id := model.add_station(selected_system)
	_after_edit(false)
	select_station(id)

func _on_load_pressed() -> void:
	if model.dirty:
		_ask("Discard unsaved changes and reload the saved file?", reload)
	else:
		reload()

func _on_delete_system_pressed() -> void:
	if selected_system == "":
		return
	var id := selected_system
	_ask("Delete system '%s' with its stations and links?" % id, func() -> void: _delete_system(id))

func _delete_system(id: String) -> void:
	if not model.delete_system(id):
		_set_status("Cannot delete '%s': it holds the player station" % id)
		return
	selected_system = ""
	selected_station = ""
	canvas.selected = ""
	_after_edit(true)

func _ask(text: String, action: Callable) -> void:
	_confirm.dialog_text = text
	_confirm_action = action
	_confirm.popup_centered()

func _on_confirmed() -> void:
	if _confirm_action.is_valid():
		_confirm_action.call()
	_confirm_action = Callable()
