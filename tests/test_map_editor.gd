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
	_check_links(editor, failures)
	_check_add_mode(editor, failures)
	_check_lists(editor, failures)
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
