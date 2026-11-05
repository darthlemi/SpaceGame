class_name PresetEditor
extends VBoxContainer

# The Presets tab: the defaults every station slot inherits (kind, produces, consumes, housing),
# and a way to add new presets. `edited` tells the screen to refresh the station editor, whose
# slot dropdowns and preview depend on these values.

signal edited

const HOUSING_MAX := 100000.0

var model: MapEditModel = null
var selected_preset: String = ""
var preset_list: ItemList
var new_name_edit: LineEdit

func bind(new_model: MapEditModel) -> void:
	model = new_model
	if not model.doc["presets"].has(selected_preset):
		var names: Array = model.doc["presets"].keys()
		names.sort()
		selected_preset = "" if names.is_empty() else names[0]
	_rebuild()

func select_preset(preset: String) -> void:
	if model.doc["presets"].has(preset):
		selected_preset = preset
		_rebuild()

func set_produce(preset: String, commodity: String, amount: float) -> void:
	_set_amount(preset, "produces", commodity, amount)

func set_consume(preset: String, commodity: String, amount: float) -> void:
	_set_amount(preset, "consumes", commodity, amount)

func set_housing(preset: String, value: float) -> void:
	model.set_preset_field(preset, "housing", value)
	edited.emit()

func set_kind(preset: String, kind: String) -> void:
	model.set_preset_field(preset, "kind", kind)
	edited.emit()

func add_preset(preset_name: String) -> bool:
	var trimmed := preset_name.strip_edges()
	if not model.add_preset(trimmed):
		return false
	selected_preset = trimmed
	_rebuild()
	edited.emit()
	return true

func _set_amount(preset: String, key: String, commodity: String, amount: float) -> void:
	var amounts: Dictionary = model.doc["presets"][preset].get(key, {}).duplicate()
	if amount <= 0.0:
		amounts.erase(commodity)
	else:
		amounts[commodity] = amount
	model.set_preset_field(preset, key, amounts)
	edited.emit()

func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

func _rebuild() -> void:
	_clear()
	preset_list = ItemList.new()
	preset_list.name = "PresetList"
	preset_list.custom_minimum_size.y = 110.0
	var names: Array = model.doc["presets"].keys()
	names.sort()
	for preset_name in names:
		var row := preset_list.add_item(str(preset_name))
		if preset_name == selected_preset:
			preset_list.select(row)
	preset_list.item_selected.connect(func(index: int) -> void: select_preset(preset_list.get_item_text(index)))
	add_child(preset_list)
	var add_row := HBoxContainer.new()
	add_child(add_row)
	new_name_edit = LineEdit.new()
	new_name_edit.name = "NewPresetEdit"
	new_name_edit.placeholder_text = "new preset name"
	new_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(new_name_edit)
	var add := Button.new()
	add.name = "AddPresetButton"
	add.text = "+ Add preset"
	add.pressed.connect(func() -> void: add_preset(new_name_edit.text))
	add_row.add_child(add)
	if selected_preset != "":
		_build_selected(model.doc["presets"][selected_preset])

func _build_selected(preset: Dictionary) -> void:
	var title := Label.new()
	title.name = "PresetTitle"
	title.text = "Preset: %s" % selected_preset
	add_child(title)
	var kind_row := HBoxContainer.new()
	add_child(kind_row)
	var kind_label := Label.new()
	kind_label.text = "Kind"
	kind_label.custom_minimum_size.x = EditorFields.LABEL_WIDTH
	kind_row.add_child(kind_label)
	var kinds: Array = EconomyRole.RoleType.keys()
	var kind := OptionButton.new()
	kind.name = "KindOption"
	for k in kinds:
		kind.add_item(k)
	kind.select(kinds.find(preset.get("kind", "")))
	var chosen := selected_preset
	kind.item_selected.connect(func(index: int) -> void: set_kind(chosen, kinds[index]))
	kind_row.add_child(kind)
	add_child(EditorFields.commodity_grid(preset.get("produces", {}), preset.get("consumes", {}),
			func(commodity: String, amount: float) -> void: set_produce(chosen, commodity, amount),
			func(commodity: String, amount: float) -> void: set_consume(chosen, commodity, amount)))
	var housing_row := HBoxContainer.new()
	add_child(housing_row)
	var housing_label := Label.new()
	housing_label.text = "Housing"
	housing_label.custom_minimum_size.x = EditorFields.LABEL_WIDTH
	housing_row.add_child(housing_label)
	var housing := SpinBox.new()
	housing.name = "Housing"
	housing.max_value = HOUSING_MAX
	housing.step = 50.0
	housing.value = float(preset.get("housing", 0.0))
	housing.value_changed.connect(func(value: float) -> void: set_housing(chosen, value))
	housing_row.add_child(housing)
