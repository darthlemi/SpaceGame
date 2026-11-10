extends RefCounted

const Validator = preload("res://tests/test_galaxy_validator.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []
	var model := MapEditModel.from_document(Validator.doc())
	var editor := SceneryEditor.new()
	editor.bind(model, "b")

	if editor.folder_option.item_count < 2:
		failures.append("scenery editor: expected at least 2 folders (planets, asteroids), got %d" % editor.folder_option.item_count)
	editor.pick_folder("planets")
	if editor.thumbnail_grid.get_child_count() == 0:
		failures.append("scenery editor: expected thumbnails for the planets folder")
	editor.select_thumbnail("planet_gas_purple")
	editor.pick_layer("foreground")
	editor.place_selected()
	var scenery: Array = model.doc["systems"][1]["scenery"]
	if scenery.size() != 1 or scenery[0]["texture"] != "planet_gas_purple.png" or scenery[0]["layer"] != "foreground":
		failures.append("place_selected: expected a placed planet_gas_purple on foreground, got %s" % [scenery])

	editor.select_item(0)
	editor.set_selected_scale(4.2)
	if model.doc["systems"][1]["scenery"][0]["scale"] != 4.2:
		failures.append("set_selected_scale: expected 4.2, got %s" % [model.doc["systems"][1]["scenery"][0]])

	editor.delete_selected()
	if not model.doc["systems"][1]["scenery"].is_empty():
		failures.append("delete_selected: expected scenery cleared, got %s" % [model.doc["systems"][1]["scenery"]])

	editor.set_background("sparse", 1)
	if model.doc["systems"][1].get("background", {}) != {"category": "sparse", "seed": 1}:
		failures.append("set_background: expected it stored, got %s" % [model.doc["systems"][1].get("background")])

	editor.randomize()
	if not model.doc["systems"][1].has("background") or model.doc["systems"][1]["scenery"].is_empty():
		failures.append("randomize: expected a fresh background and scenery, got %s" % [model.doc["systems"][1]])

	var before_oob: Array = model.doc["systems"][1]["scenery"].duplicate(true)
	editor.select_item(99)
	editor.set_selected_scale(7.0)
	editor.delete_selected()
	if model.doc["systems"][1]["scenery"] != before_oob:
		failures.append("select_item/out-of-range: expected a stale/invalid index to leave scenery untouched, got %s" % [model.doc["systems"][1]["scenery"]])

	editor.queue_free()
	return failures
