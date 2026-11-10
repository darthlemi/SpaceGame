class_name SceneryEditor
extends VBoxContainer

# The Scenery sub-tab's side panel: background category/seed, an asset-folder thumbnail
# browser, layer picking, randomize, and the selected item's scale/delete. All edits go
# through MapEditModel; `edited` tells the screen to refresh its canvas and findings.

signal edited

const BACKGROUNDS_DIR := "res://assets/sprites/backgrounds"
const LAYERS := ["deep_background", "mid_distance", "foreground"]
const SEED_COUNT := 5
# Singular type name stored in the document, keyed by the plural folder name on disk.
const TYPE_BY_FOLDER := {"planets": "planet", "asteroids": "asteroid"}

var model: MapEditModel = null
var system_id: String = ""

var background_category_option: OptionButton
var background_seed_option: OptionButton
var folder_option: OptionButton
var layer_option: OptionButton
var thumbnail_grid: GridContainer
var scale_spin: SpinBox
var delete_button: Button
var randomize_button: Button

var _selected_folder: String = ""
var _selected_texture: String = ""
var _selected_index: int = -1

func bind(new_model: MapEditModel, new_system_id: String) -> void:
	model = new_model
	system_id = new_system_id
	_rebuild()

func pick_folder(folder: String) -> void:
	_selected_folder = folder
	_selected_texture = ""
	_rebuild_thumbnails()

func select_thumbnail(basename: String) -> void:
	_selected_texture = "%s.png" % basename

func pick_layer(layer: String) -> void:
	if layer_option == null:
		return
	for i in layer_option.item_count:
		if layer_option.get_item_text(i) == layer:
			layer_option.select(i)
			return

func place_selected() -> void:
	if model == null or _selected_folder == "" or _selected_texture == "":
		return
	var type: String = TYPE_BY_FOLDER.get(_selected_folder, _selected_folder.trim_suffix("s"))
	var layer := layer_option.get_item_text(layer_option.selected) if layer_option.selected >= 0 else LAYERS[0]
	model.add_scenery(system_id, type, _selected_texture, layer)
	edited.emit()
	_rebuild()

func select_item(index: int) -> void:
	var entry := _entry()
	if entry.is_empty() or index < 0 or index >= entry.get("scenery", []).size():
		_selected_index = -1
		return
	_selected_index = index
	scale_spin.value = float(entry["scenery"][index].get("scale", 1.0))

func set_selected_scale(value: float) -> void:
	if model == null or _selected_index < 0:
		return
	model.set_scenery_field(system_id, _selected_index, "scale", value)
	edited.emit()

func delete_selected() -> void:
	if model == null or _selected_index < 0:
		return
	model.remove_scenery(system_id, _selected_index)
	_selected_index = -1
	edited.emit()
	_rebuild()

func set_background(category: String, seed: int) -> void:
	if model == null:
		return
	model.set_background(system_id, category, seed)
	edited.emit()

func randomize() -> void:
	if model == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var planets := EditorFields.scan_png_basenames("%s/planets" % BACKGROUNDS_DIR)
	var asteroids := EditorFields.scan_png_basenames("%s/asteroids" % BACKGROUNDS_DIR)
	var planet_files: Array = planets.map(func(name): return "%s.png" % name)
	var asteroid_files: Array = asteroids.map(func(name): return "%s.png" % name)
	model.randomize_scenery(system_id, rng, planet_files, asteroid_files)
	edited.emit()
	_rebuild()

func _entry() -> Dictionary:
	if model == null:
		return {}
	for sys in model.doc["systems"]:
		if sys["id"] == system_id:
			return sys
	return {}

func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

func _rebuild() -> void:
	_clear()
	if model == null:
		return

	add_child(_label("Background"))
	background_category_option = OptionButton.new()
	background_category_option.name = "BackgroundCategory"
	for category in StarfieldAssignment.CATEGORIES:
		background_category_option.add_item(category)
	background_category_option.item_selected.connect(func(_i): _on_background_changed())
	add_child(background_category_option)
	background_seed_option = OptionButton.new()
	background_seed_option.name = "BackgroundSeed"
	for seed in range(1, SEED_COUNT + 1):
		background_seed_option.add_item(str(seed))
	background_seed_option.item_selected.connect(func(_i): _on_background_changed())
	add_child(background_seed_option)
	var current_background: Dictionary = StarfieldAssignment.pick(system_id, StarfieldAssignment.SYSTEM_CATEGORIES, _entry().get("background", {}))
	background_category_option.select(StarfieldAssignment.CATEGORIES.find(current_background.category))
	background_seed_option.select(current_background.seed - 1)

	add_child(_label("Folder"))
	folder_option = OptionButton.new()
	folder_option.name = "Folder"
	var folders := EditorFields.scan_subfolders(BACKGROUNDS_DIR)
	for folder in folders:
		if TYPE_BY_FOLDER.has(folder):
			folder_option.add_item(folder)
	folder_option.item_selected.connect(func(i): pick_folder(folder_option.get_item_text(i)))
	add_child(folder_option)
	if _selected_folder == "" and folder_option.item_count > 0:
		_selected_folder = folder_option.get_item_text(0)

	add_child(_label("Layer"))
	layer_option = OptionButton.new()
	layer_option.name = "Layer"
	for layer in LAYERS:
		layer_option.add_item(layer)
	add_child(layer_option)

	thumbnail_grid = GridContainer.new()
	thumbnail_grid.name = "ThumbnailGrid"
	thumbnail_grid.columns = 2
	add_child(thumbnail_grid)
	_rebuild_thumbnails()

	var place_button := Button.new()
	place_button.name = "PlaceButton"
	place_button.text = "+ Place"
	place_button.pressed.connect(place_selected)
	add_child(place_button)

	randomize_button = Button.new()
	randomize_button.name = "RandomizeButton"
	randomize_button.text = "Randomize"
	randomize_button.pressed.connect(randomize)
	add_child(randomize_button)

	add_child(_label("Selected item"))
	scale_spin = SpinBox.new()
	scale_spin.name = "ScaleSpin"
	scale_spin.min_value = 0.1
	scale_spin.max_value = 10.0
	scale_spin.step = 0.1
	scale_spin.value_changed.connect(set_selected_scale)
	add_child(scale_spin)
	delete_button = Button.new()
	delete_button.name = "DeleteButton"
	delete_button.text = "Delete"
	delete_button.pressed.connect(delete_selected)
	add_child(delete_button)

func _rebuild_thumbnails() -> void:
	if thumbnail_grid == null:
		return
	for child in thumbnail_grid.get_children():
		thumbnail_grid.remove_child(child)
		child.queue_free()
	if _selected_folder == "":
		return
	for basename in EditorFields.scan_png_basenames("%s/%s" % [BACKGROUNDS_DIR, _selected_folder]):
		var button := Button.new()
		button.name = "Thumb_%s" % basename
		button.text = basename
		var path := "%s/%s/%s.png" % [BACKGROUNDS_DIR, _selected_folder, basename]
		if ResourceLoader.exists(path):
			button.icon = load(path)
		button.pressed.connect(func(): select_thumbnail(basename))
		thumbnail_grid.add_child(button)

func _on_background_changed() -> void:
	var category: String = background_category_option.get_item_text(background_category_option.selected)
	var seed: int = background_seed_option.selected + 1
	set_background(category, seed)

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
