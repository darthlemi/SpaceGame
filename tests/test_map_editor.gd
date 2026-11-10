extends RefCounted

const MapEditorScene = preload("res://scenes/editor/map_editor.tscn")
const UiLayoutCheck = preload("res://tests/ui_layout_check.gd")
const Validator = preload("res://tests/test_galaxy_validator.gd")
const TMP_PATH := "user://map_editor_test.json"
const WINDOW_SIZE := Vector2i(1152, 648)

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	_remove_tmp()
	# A --script run's root window is tiny; the real editor window is the project default.
	var old_size := tree.root.size
	tree.root.size = WINDOW_SIZE
	var editor: MapEditor = MapEditorScene.instantiate()
	editor.auto_load = false
	editor.save_path = TMP_PATH
	tree.root.add_child(editor)
	await tree.process_frame
	await tree.process_frame
	editor.load_document(Validator.doc())
	editor.canvas.refresh()

	if editor.canvas.size.x < 100.0:
		failures.append("setup: expected the canvas to have a size, got %s" % editor.canvas.size)
	_check_drag(editor, failures)
	_check_station_canvas_standalone(failures)
	_check_links(editor, failures)
	_check_add_mode(editor, failures)
	_check_lists(editor, failures)
	_check_system_tab(editor, failures)
	await _check_station_editor(tree, editor, failures)
	_check_presets_tab(editor, failures)
	_check_vector_row(editor, failures)
	_check_rename_and_failed_save(editor, failures)
	_check_save_blocked(editor, failures)
	_check_save_and_load(editor, failures)
	await _check_layout(tree, editor, failures)

	editor.queue_free()
	await tree.process_frame
	tree.root.size = old_size
	_remove_tmp()
	return failures

static func _remove_tmp() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

static func _map_of(editor: MapEditor, id: String) -> Array:
	for sys in editor.model.doc["systems"]:
		if sys["id"] == id:
			return sys["map"]
	return []

static func _check_drag(editor: MapEditor, failures: Array[String]) -> void:
	var canvas := editor.canvas
	var start: Vector2 = canvas.node_points["b"]
	canvas.handle_press(start, MOUSE_BUTTON_LEFT)
	canvas.handle_drag(start + Vector2(40.0, 30.0))
	canvas.handle_release()
	var moved := _map_of(editor, "b").duplicate()
	canvas.handle_drag(start + Vector2(200.0, 200.0))
	if moved == [0.5, 0.5] or not editor.model.dirty:
		failures.append("drag: expected system b to move and the model to be dirty, got %s dirty=%s" % [moved, editor.model.dirty])
	if _map_of(editor, "b") != moved:
		failures.append("drag: expected a drag after release to be ignored")
	if editor.selected_system != "b":
		failures.append("drag: expected b selected, got '%s'" % editor.selected_system)
	editor.load_document(Validator.doc())
	canvas.refresh()

static func _check_links(editor: MapEditor, failures: Array[String]) -> void:
	var canvas := editor.canvas
	canvas.set_mode(MapCanvas.Mode.LINK)
	canvas.handle_press(canvas.node_points["a"], MOUSE_BUTTON_LEFT)
	canvas.handle_press(canvas.node_points["c"], MOUSE_BUTTON_LEFT)
	if editor.model.doc["links"].size() != 3:
		failures.append("link mode: expected a-c added (3 links), got %s" % [editor.model.doc["links"]])
	canvas.handle_press(canvas.node_points["b"], MOUSE_BUTTON_LEFT)
	canvas.handle_press(canvas.node_points["b"], MOUSE_BUTTON_LEFT)
	if editor.model.doc["links"].size() != 3:
		failures.append("link mode: clicking the same node twice must not add a link")
	canvas.set_mode(MapCanvas.Mode.MOVE)
	editor.load_document(Validator.doc())
	canvas.refresh()
	var middle: Vector2 = (canvas.node_points["b"] + canvas.node_points["c"]) / 2.0
	canvas.handle_press(middle, MOUSE_BUTTON_RIGHT)
	if editor.model.doc["links"] != [["a", "b"]]:
		failures.append("right-click: expected b-c deleted, got %s" % [editor.model.doc["links"]])
	editor.load_document(Validator.doc())
	canvas.refresh()

static func _check_add_mode(editor: MapEditor, failures: Array[String]) -> void:
	var canvas := editor.canvas
	canvas.set_mode(MapCanvas.Mode.ADD)
	var point := Vector2(canvas.size.x * 0.5, canvas.size.y * 0.9)
	canvas.handle_press(point, MOUSE_BUTTON_LEFT)
	canvas.set_mode(MapCanvas.Mode.MOVE)
	if editor.model.doc["systems"].size() != 4:
		failures.append("add mode: expected a 4th system, got %d" % editor.model.doc["systems"].size())
		return
	var added: Array = editor.model.doc["systems"][3]["map"]
	if absf(added[0] - 0.5) > 0.1 or absf(added[1] - 0.9) > 0.1:
		failures.append("add mode: expected the system near (0.5, 0.9), got %s" % [added])
	editor.load_document(Validator.doc())
	editor.canvas.refresh()

static func _check_lists(editor: MapEditor, failures: Array[String]) -> void:
	editor.select_system("b")
	if editor.station_list.item_count != 1:
		failures.append("station list: expected 1 station in b, got %d" % editor.station_list.item_count)
	if editor.station_box.visible:
		failures.append("station list: expected no station editor before a station is chosen")
	editor.station_list.item_selected.emit(0)
	if editor.selected_station != "post_b" or not editor.station_box.visible:
		failures.append("station list: expected post_b selected with the station editor shown, got '%s'" % editor.selected_station)
	editor.all_stations_toggle.button_pressed = true
	if editor.station_list.item_count != 3:
		failures.append("station list: expected all 3 stations with the filter on, got %d" % editor.station_list.item_count)
	editor.all_stations_toggle.button_pressed = false
	editor.select_station("post_c")
	if editor.selected_system != "c":
		failures.append("select_station: expected the station's system c to be selected, got '%s'" % editor.selected_system)

static func _check_save_blocked(editor: MapEditor, failures: Array[String]) -> void:
	var doc := Validator.doc()
	doc["systems"].append({"id": "d", "name": "D", "map": [0.1, 0.1], "extra": {}})
	editor.load_document(doc)
	if editor.save():
		failures.append("save blocked: expected false with an unlinked system")
	if FileAccess.file_exists(TMP_PATH):
		failures.append("save blocked: expected nothing written")
	var found := -1
	for i in editor.errors_list.item_count:
		var text := editor.errors_list.get_item_text(i)
		if text.begins_with("[BLOCK]") and text.find("'D'") >= 0:
			found = i
	if found < 0:
		failures.append("save blocked: expected a blocker for D in the errors list")
		return
	editor.select_system("a")
	editor.errors_list.item_selected.emit(found)
	if editor.selected_system != "d":
		failures.append("save blocked: expected clicking the blocker to select d, got '%s'" % editor.selected_system)

static func _check_save_and_load(editor: MapEditor, failures: Array[String]) -> void:
	editor.load_document(Validator.doc())
	editor.canvas.refresh()
	if not editor.save():
		failures.append("save: expected a valid galaxy to write")
	var first_time := FileAccess.get_modified_time(TMP_PATH)
	if editor.save():
		failures.append("save: expected a second identical save to write nothing")
	if FileAccess.get_modified_time(TMP_PATH) != first_time:
		failures.append("save: the second save changed the file")
	editor.model.move_system("b", Vector2(0.9, 0.9))
	editor.reload()
	if _map_of(editor, "b") != [0.5, 0.5] or editor.model.dirty:
		failures.append("load: expected unsaved edits discarded, got %s dirty=%s" % [_map_of(editor, "b"), editor.model.dirty])

static func _check_layout(tree: SceneTree, editor: MapEditor, failures: Array[String]) -> void:
	editor.select_station("post_b")
	await tree.process_frame
	await tree.process_frame
	UiLayoutCheck.check_panel_layout(editor, failures)

static func _economy_matches(se: StationEditor, editor: MapEditor, label: String, failures: Array[String]) -> void:
	var index := editor.model.station_index(se.station_id)
	var built := GalaxyData._make_station(editor.model.doc["stations"][index], editor.model.doc["presets"])
	if se.preview_net() != built.economy.net_commodities() or se.preview_housing() != built.economy.population_capacity():
		failures.append("%s: expected the preview to match the economy, got %s / %s vs %s / %s" % [
			label, se.preview_net(), se.preview_housing(), built.economy.net_commodities(), built.economy.population_capacity()])

static func _slot_of(editor: MapEditor, station_id: String, index: int):
	return editor.model.doc["stations"][editor.model.station_index(station_id)]["slots"][index]

static func _check_station_editor(tree: SceneTree, editor: MapEditor, failures: Array[String]) -> void:
	editor.load_document(Validator.doc())
	editor.select_station("post_b")
	var se: StationEditor = editor.station_box
	if not se.visible or se.station_id != "post_b":
		failures.append("station editor: expected it shown for post_b")
		return
	_economy_matches(se, editor, "station editor start", failures)

	se.set_slot_preset(1, "agriculture")
	if _slot_of(editor, "post_b", 1) != "agriculture" or se.preview_net().get(Commodity.Type.FOOD, 0.0) != 5.0:
		failures.append("slot preset: expected agriculture in slot 2 and +5 Food, got %s / %s" % [_slot_of(editor, "post_b", 1), se.preview_net()])
	_economy_matches(se, editor, "slot preset", failures)

	se.set_produce(0, "ORE", 9.0)
	var slot = _slot_of(editor, "post_b", 0)
	if typeof(slot) != TYPE_DICTIONARY or slot["overrides"].get("produces", {}) != {"ORE": 9.0} or not se.is_overridden(0, "produces"):
		failures.append("override: expected a produces override of ORE 9, got %s" % [slot])
	if not se.marker_visible(0, "produces") or se.marker_visible(0, "consumes"):
		failures.append("override: expected only the produces marker visible")
	if se.preview_net().get(Commodity.Type.ORE, 0.0) != 9.0:
		failures.append("override: expected the preview to show +9 Ore, got %s" % [se.preview_net()])
	_economy_matches(se, editor, "override", failures)
	se.set_produce(0, "ORE", 5.0)
	if _slot_of(editor, "post_b", 0) != "mining":
		failures.append("override: setting the preset's own value back should drop the override, got %s" % [_slot_of(editor, "post_b", 0)])
	se.set_produce(0, "ORE", 9.0)
	se.reset_override(0, "produces")
	if _slot_of(editor, "post_b", 0) != "mining" or se.is_overridden(0, "produces") or se.marker_visible(0, "produces"):
		failures.append("reset: expected the preset value back with no marker, got %s" % [_slot_of(editor, "post_b", 0)])
	se.get_node("Slot0").find_child("Housing", true, false).value = 450.0
	if not se.is_overridden(0, "housing") or _slot_of(editor, "post_b", 0)["overrides"]["housing"] != 450.0:
		failures.append("housing: expected a housing override of 450 from the spin box")
	_economy_matches(se, editor, "housing", failures)
	se.reset_override(0, "housing")

	var stock: Dictionary = editor.model.doc["stations"][editor.model.station_index("post_b")]["stock"]
	if not se.set_stock_text("ORE", "") or stock.has("ORE"):
		failures.append("stock: expected a blank to remove the key")
	if not se.set_stock_text("FUEL", "12.5") or stock.get("FUEL", -1.0) != 12.5:
		failures.append("stock: expected FUEL 12.5, got %s" % [stock])
	if se.set_stock_text("FUEL", "abc") or se.set_stock_text("FUEL", "-3") or stock.get("FUEL", -1.0) != 12.5:
		failures.append("stock: expected non-numbers and negatives refused with no change, got %s" % [stock])

	se.find_child("Quota_COMBAT", true, false).value = 2.0
	var quota: Dictionary = editor.model.doc["stations"][editor.model.station_index("post_b")]["quota"]
	if quota.get("COMBAT", 0) != 2:
		failures.append("quota: expected COMBAT 2 from the spin box, got %s" % [quota])

	if not se.add_extra("mood", "calm") or se.add_extra("  ", "x"):
		failures.append("extras: expected a key to add and a blank key to be refused")
	var back: Dictionary = GalaxyDocument.parse(GalaxyDocument.serialize(editor.model.doc))["doc"]
	var found := false
	for st in back["stations"]:
		if st["name"] == "Post B" and st["extra"].get("mood", "") == "calm":
			found = true
	if not found:
		failures.append("extras: expected mood to survive a serialise and parse")
	se.remove_extra("mood")
	if editor.model.doc["stations"][editor.model.station_index("post_b")]["extra"].has("mood"):
		failures.append("extras: expected mood removed")

	se.duplicate_button.pressed.emit()
	if editor.model.station_index("post_b_copy") < 0 or editor.selected_station != "post_b_copy":
		failures.append("duplicate: expected post_b_copy created and selected, got '%s'" % editor.selected_station)
	editor.station_box.delete_button.pressed.emit()
	editor._on_confirmed()
	if editor.model.station_index("post_b_copy") >= 0:
		failures.append("delete: expected post_b_copy removed after confirming")

	editor.select_station("home_base")
	if not editor.station_box.duplicate_button.disabled or not editor.station_box.delete_button.disabled:
		failures.append("player station: expected Duplicate and Delete disabled")

	editor.select_station("post_b")
	editor.station_box.set_slot_preset(0, "mining")
	await tree.process_frame

static func _check_vector_row(editor: MapEditor, failures: Array[String]) -> void:
	editor.load_document(Validator.doc())
	editor.model.doc["systems"][1]["map"] = [0.123, 0.456]
	editor.select_system("b")
	editor._rebuild_system_fields()
	editor.system_fields_box.get_node("Row_map").get_node("X").value = 0.5
	var map: Array = editor.model.doc["systems"][1]["map"]
	if map[0] != 0.5 or absf(map[1] - 0.456) > 0.0001:
		failures.append("vector row: editing x must leave y unrounded, got %s" % [map])

static func _check_presets_tab(editor: MapEditor, failures: Array[String]) -> void:
	editor.load_document(Validator.doc())
	var pe: PresetEditor = editor.preset_editor
	pe.select_preset("mining")
	pe.set_produce("mining", "ORE", 8.0)
	pe.set_consume("mining", "FOOD", 1.0)
	pe.set_housing("mining", 900.0)
	var mining: Dictionary = editor.model.doc["presets"]["mining"]
	if mining["produces"] != {"ORE": 8.0} or mining["consumes"] != {"FOOD": 1.0} or mining["housing"] != 900.0:
		failures.append("presets tab: expected the mining edits stored, got %s" % [mining])
	editor.select_station("post_b")
	var se: StationEditor = editor.station_box
	_economy_matches(se, editor, "presets tab", failures)
	if not pe.add_preset("scrapyard") or pe.add_preset("scrapyard"):
		failures.append("presets tab: expected one new preset and a refusal for a duplicate")
	if not editor.model.doc["presets"].has("scrapyard") or not editor.model.dirty:
		failures.append("presets tab: expected scrapyard in the document")
	var options := se.find_children("PresetOption", "OptionButton", true, false)
	if options.size() != 2:
		failures.append("presets tab: expected a dropdown per slot, got %d" % options.size())
	for option in options:
		var names: Array[String] = []
		for i in option.item_count:
			names.append(option.get_item_text(i))
		if not names.has("scrapyard") or names.size() != 7:
			failures.append("presets tab: expected the new preset in every slot dropdown, got %s" % [names])

static func _check_rename_and_failed_save(editor: MapEditor, failures: Array[String]) -> void:
	editor.load_document(Validator.doc())
	editor.select_station("post_b")
	var se: StationEditor = editor.station_box
	var before: Dictionary = editor.model.doc.duplicate(true)
	if se.rename("Post C") or editor.model.doc != before or se.station_id != "post_b":
		failures.append("rename: a name whose id is taken must be refused with no change")
	if not se.rename("Post Bee") or se.station_id != "post_bee" or editor.selected_station != "post_bee":
		failures.append("rename: expected a free name to apply and follow the selection, got '%s'" % se.station_id)
	se.set_stock_text("FUEL", "3")
	if editor.model.station_index("post_bee") < 0 or editor.model.doc["stations"][editor.model.station_index("post_bee")]["stock"].get("FUEL", 0.0) != 3.0:
		failures.append("rename: later edits must land on the renamed station")
	var good_path := editor.save_path
	editor.save_path = "user://no_such_dir/galaxy.json"
	if editor.save() or not editor.model.dirty or editor.status_label.text.find("failed") < 0:
		failures.append("save: a failed write must return false, keep dirty and say so, got '%s' dirty=%s" % [editor.status_label.text, editor.model.dirty])
	editor.save_path = good_path

static func _check_system_tab(editor: MapEditor, failures: Array[String]) -> void:
	editor.load_document(Validator.doc())
	editor.select_system("b")
	if not editor.station_canvas.station_points.has("post_b"):
		failures.append("system tab: expected the station canvas to show post_b, got %s" % [editor.station_canvas.station_points.keys()])

	var start: Vector2 = editor.station_canvas.station_points["post_b"]
	editor.station_canvas.handle_press(start, MOUSE_BUTTON_LEFT)
	if editor.selected_station != "post_b":
		failures.append("system tab: expected clicking the station canvas to select post_b, got '%s'" % editor.selected_station)
	editor.station_canvas.handle_drag(start + Vector2(30.0, 10.0))
	editor.station_canvas.handle_release()
	var moved: Array = editor.model.doc["stations"][editor.model.station_index("post_b")]["pos"]
	if Vector2(moved[0], moved[1]) == Vector2(300.0, 250.0):
		failures.append("system tab: expected the drag to move post_b's pos, stayed at %s" % [moved])

	editor.scenery_editor.set_background("dense", 2)
	if editor.scenery_canvas.items.is_empty() and editor.model.doc["systems"][1].get("background", {}) != {"category": "dense", "seed": 2}:
		failures.append("system tab: expected the background edit to reach the model")
	editor.scenery_editor.randomize()
	if editor.scenery_canvas.items.is_empty():
		failures.append("system tab: expected the scenery canvas to refresh with the randomized items")
	editor.load_document(Validator.doc())

static func _check_station_canvas_standalone(failures: Array[String]) -> void:
	var canvas := StationCanvas.new()
	canvas.size = Vector2(1152, 648)
	var doc := Validator.doc()
	canvas.set_system(doc, "b")
	if not canvas.station_points.has("post_b"):
		failures.append("station canvas: expected post_b plotted, got %s" % [canvas.station_points.keys()])
		return
	var start: Vector2 = canvas.station_points["post_b"]
	var moved_signals: Array = []
	canvas.station_moved.connect(func(id: String, pos: Vector2): moved_signals.append([id, pos]))
	var selected_signals: Array[String] = []
	canvas.station_selected.connect(func(id: String): selected_signals.append(id))
	canvas.handle_press(start, MOUSE_BUTTON_LEFT)
	if selected_signals != ["post_b"] or canvas.selected != "post_b":
		failures.append("station canvas: expected post_b selected on press, got %s" % [selected_signals])
	canvas.handle_drag(start + Vector2(50.0, 20.0))
	if moved_signals.size() != 1 or moved_signals[0][0] != "post_b":
		failures.append("station canvas: expected a station_moved signal for post_b, got %s" % [moved_signals])
	canvas.handle_release()
	canvas.handle_drag(start + Vector2(500.0, 500.0))
	if moved_signals.size() != 1:
		failures.append("station canvas: expected a drag after release to be ignored")
	canvas.queue_free()
