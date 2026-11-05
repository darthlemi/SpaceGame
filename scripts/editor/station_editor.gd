class_name StationEditor
extends VBoxContainer

# The full editor for one station: identity fields, slots (preset + per-slot overrides), starting
# stock, fleet quotas, free-form extra properties and a computed preview. Edits go through the
# MapEditModel; `edited` tells the screen to refresh its canvas, lists and findings.

signal edited
signal message(text: String)
signal station_renamed(new_id: String)
signal duplicate_requested(id: String)
signal delete_requested(id: String)

const OVERRIDE_MARKER := "(overridden)"
const HOUSING_MAX := 100000.0

var model: MapEditModel = null
var station_id: String = ""
var preview_label: Label
var add_slot_button: Button
var duplicate_button: Button
var delete_button: Button
var extra_key_edit: LineEdit
var extra_value_edit: LineEdit

# "slot|key" -> marker Label / reset Button, shown only while that key is overridden.
var _markers: Dictionary = {}
var _resets: Dictionary = {}

func bind(new_model: MapEditModel, id: String) -> void:
	model = new_model
	station_id = id
	_rebuild()

# --- editing (public so tests and the controls share one path) ---

func set_slot_preset(slot_index: int, preset: String) -> void:
	model.set_slot_preset(station_id, slot_index, preset)
	_rebuild()
	edited.emit()

func add_slot() -> void:
	if model.add_slot(station_id):
		_rebuild()
		edited.emit()

func remove_slot(slot_index: int) -> void:
	if model.remove_slot(station_id, slot_index):
		_rebuild()
		edited.emit()

func set_produce(slot_index: int, commodity: String, amount: float) -> void:
	_set_amount(slot_index, "produces", commodity, amount)

func set_consume(slot_index: int, commodity: String, amount: float) -> void:
	_set_amount(slot_index, "consumes", commodity, amount)

func set_housing(slot_index: int, value: float) -> void:
	if value == float(_preset_of(slot_index).get("housing", 0.0)):
		model.reset_override(station_id, slot_index, "housing")
	else:
		model.set_override(station_id, slot_index, "housing", value)
	_refresh_dynamic()
	edited.emit()

func reset_override(slot_index: int, key: String) -> void:
	model.reset_override(station_id, slot_index, key)
	_rebuild()
	edited.emit()

func is_overridden(slot_index: int, key: String) -> bool:
	return _slot_overrides(slot_index).has(key)

# Whether the "(overridden)" marker for that slot key is showing.
func marker_visible(slot_index: int, key: String) -> bool:
	var marker: Label = _markers.get("%d|%s" % [slot_index, key])
	return marker != null and marker.visible

# Blank means "use the game default" (key removed). False, and no change, for text that isn't a
# non-negative number.
func set_stock_text(commodity: String, text: String) -> bool:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		model.set_stock(station_id, commodity, null)
	elif trimmed.is_valid_float() and trimmed.to_float() >= 0.0:
		model.set_stock(station_id, commodity, trimmed.to_float())
	else:
		return false
	_refresh_dynamic()
	edited.emit()
	return true

func set_quota(role: String, count: int) -> void:
	model.set_quota(station_id, role, count)
	edited.emit()

func add_extra(key: String, value: String) -> bool:
	if key.strip_edges().is_empty():
		return false
	model.set_station_extra(station_id, key.strip_edges(), value)
	_rebuild()
	edited.emit()
	return true

func remove_extra(key: String) -> void:
	model.set_station_extra(station_id, key, null)
	_rebuild()
	edited.emit()

# --- preview: the same economy code the game runs, on a throwaway station ---

func preview_station() -> StationData:
	var entry := _entry()
	if entry.is_empty():
		return null
	# GalaxyData asserts on bad names, so only build from a station the validator has no block on.
	for finding in GalaxyValidator.validate(model.doc):
		if finding["severity"] == "block" and finding["target"]["kind"] == "station" and finding["target"]["id"] == station_id:
			return null
	return GalaxyData._make_station(entry, model.doc["presets"])

func preview_net() -> Dictionary:
	var st := preview_station()
	return {} if st == null else st.economy.net_commodities()

func preview_housing() -> float:
	var st := preview_station()
	return 0.0 if st == null else st.economy.population_capacity()

func preview_text() -> String:
	if preview_station() == null:
		return "Preview unavailable: fix the station's slots first"
	var parts: Array[String] = []
	var net := preview_net()
	for commodity in net:
		if absf(net[commodity]) > 0.0:
			parts.append("%+.1f %s" % [net[commodity], Commodity.NAMES[commodity]])
	return "Net per tick: %s\nHousing: %.0f" % [", ".join(parts) if not parts.is_empty() else "none", preview_housing()]

# --- internals ---

func _entry() -> Dictionary:
	var index := model.station_index(station_id) if model != null else -1
	return model.doc["stations"][index] if index >= 0 else {}

func _slot(slot_index: int):
	var slots: Array = _entry().get("slots", [])
	return slots[slot_index] if slot_index >= 0 and slot_index < slots.size() else ""

func _preset_of(slot_index: int) -> Dictionary:
	return model.doc["presets"].get(MapEditModel.slot_preset_name(_slot(slot_index)), {})

func _slot_overrides(slot_index: int) -> Dictionary:
	return MapEditModel.slot_overrides_of(_slot(slot_index))

# The slot's amounts for "produces" or "consumes": its override, else the preset's.
func _effective(slot_index: int, key: String) -> Dictionary:
	var overrides := _slot_overrides(slot_index)
	return overrides[key] if overrides.has(key) else _preset_of(slot_index).get(key, {})

func _set_amount(slot_index: int, key: String, commodity: String, amount: float) -> void:
	var amounts: Dictionary = _effective(slot_index, key).duplicate()
	if amount <= 0.0:
		amounts.erase(commodity)
	else:
		amounts[commodity] = amount
	# Matching the preset again drops the override rather than storing a no-op copy of it.
	if amounts == _preset_of(slot_index).get(key, {}):
		model.reset_override(station_id, slot_index, key)
	else:
		model.set_override(station_id, slot_index, key, amounts)
	_refresh_dynamic()
	edited.emit()

func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_markers.clear()
	_resets.clear()

func _rebuild() -> void:
	_clear()
	var entry := _entry()
	visible = not entry.is_empty()
	if entry.is_empty():
		return
	var title := Label.new()
	title.name = "StationTitle"
	title.text = "Station: %s" % entry["name"]
	add_child(title)
	for spec in EditorFields.STATION_FIELDS:
		add_child(EditorFields.make_row(spec, EditorFields.value_of(entry, spec), EditorFields.choices_for(spec, model.doc),
				func(value) -> void: _on_field_changed(spec, value)))
	_build_slots(entry)
	_build_stock(entry)
	_build_quota(entry)
	_build_extras(entry)
	preview_label = Label.new()
	preview_label.name = "PreviewLabel"
	add_child(preview_label)
	_build_buttons(entry)
	_refresh_dynamic()

# False (and the field reverts) when another station already has the new name's id: two stations
# with one id could not be told apart for later edits.
func rename(new_name: String) -> bool:
	var new_id := GalaxyDocument.station_id(new_name)
	if new_id != station_id and model.station_index(new_id) >= 0:
		message.emit("Name '%s' is taken by another station" % new_name)
		_rebuild()
		return false
	model.set_station_field(station_id, "name", new_name)
	station_id = new_id
	station_renamed.emit(station_id)
	_refresh_dynamic()
	edited.emit()
	return true

func _on_field_changed(spec: Dictionary, value) -> void:
	if spec["key"] == "name":
		rename(str(value))
		return
	model.set_station_field(station_id, spec["key"], value)
	_refresh_dynamic()
	edited.emit()

func _build_slots(entry: Dictionary) -> void:
	var title := Label.new()
	title.name = "SlotsTitle"
	title.text = "Slots (%d/%d)" % [entry["slots"].size(), GalaxyData.STATION_MAX_SLOTS]
	add_child(title)
	for i in entry["slots"].size():
		_build_slot(i)
	add_slot_button = Button.new()
	add_slot_button.name = "AddSlotButton"
	add_slot_button.text = "+ Add slot"
	add_slot_button.disabled = entry["slots"].size() >= GalaxyData.STATION_MAX_SLOTS
	add_slot_button.pressed.connect(add_slot)
	add_child(add_slot_button)

func _build_slot(i: int) -> void:
	var box := VBoxContainer.new()
	box.name = "Slot%d" % i
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var label := Label.new()
	label.text = "Slot %d" % (i + 1)
	head.add_child(label)
	var option := OptionButton.new()
	option.name = "PresetOption"
	var names: Array = model.doc["presets"].keys()
	names.sort()
	var current := MapEditModel.slot_preset_name(_slot(i))
	if not names.has(current):
		names.append(current)
	for preset_name in names:
		option.add_item(str(preset_name))
	option.select(names.find(current))
	option.item_selected.connect(func(index: int) -> void: set_slot_preset(i, names[index]))
	head.add_child(option)
	var remove := Button.new()
	remove.name = "RemoveSlotButton"
	remove.text = "Remove"
	remove.pressed.connect(func() -> void: remove_slot(i))
	head.add_child(remove)
	box.add_child(EditorFields.commodity_grid(_effective(i, "produces"), _effective(i, "consumes"),
			func(commodity: String, amount: float) -> void: set_produce(i, commodity, amount),
			func(commodity: String, amount: float) -> void: set_consume(i, commodity, amount)))
	var housing_row := HBoxContainer.new()
	box.add_child(housing_row)
	var housing_label := Label.new()
	housing_label.text = "Housing"
	housing_label.custom_minimum_size.x = EditorFields.LABEL_WIDTH
	housing_row.add_child(housing_label)
	var spin := SpinBox.new()
	spin.name = "Housing"
	spin.max_value = HOUSING_MAX
	spin.step = 50.0
	spin.value = float(_slot_overrides(i).get("housing", _preset_of(i).get("housing", 0.0)))
	spin.value_changed.connect(func(value: float) -> void: set_housing(i, value))
	housing_row.add_child(spin)
	var marker_row := HBoxContainer.new()
	box.add_child(marker_row)
	for key in ["produces", "consumes", "housing"]:
		var marker := Label.new()
		marker.name = "Marker_%s" % key
		marker.text = "%s %s" % [key.capitalize(), OVERRIDE_MARKER]
		marker_row.add_child(marker)
		var reset := Button.new()
		reset.name = "Reset_%s" % key
		reset.text = "Reset"
		reset.pressed.connect(func() -> void: reset_override(i, key))
		marker_row.add_child(reset)
		_markers["%d|%s" % [i, key]] = marker
		_resets["%d|%s" % [i, key]] = reset

func _build_stock(entry: Dictionary) -> void:
	var title := Label.new()
	title.name = "StockTitle"
	title.text = "Starting stock (blank = default)"
	add_child(title)
	for commodity in Commodity.Type.keys():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = commodity.capitalize()
		label.custom_minimum_size.x = EditorFields.LABEL_WIDTH
		row.add_child(label)
		var edit := LineEdit.new()
		edit.name = "Stock_%s" % commodity
		edit.placeholder_text = str(Commodity.TARGET_STOCK[Commodity.Type[commodity]])
		edit.text = "" if not entry["stock"].has(commodity) else str(entry["stock"][commodity])
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var commit := func(text: String) -> void:
			if not set_stock_text(commodity, text):
				# Reverts to what the document holds.
				edit.text = "" if not _entry()["stock"].has(commodity) else str(_entry()["stock"][commodity])
		var last := [edit.text]
		var commit_if_changed := func() -> void:
			if edit.text != last[0]:
				last[0] = edit.text
				commit.call(edit.text)
		edit.text_submitted.connect(func(_text: String) -> void: commit_if_changed.call())
		edit.focus_exited.connect(commit_if_changed)
		row.add_child(edit)
		add_child(row)

func _build_quota(entry: Dictionary) -> void:
	var title := Label.new()
	title.name = "QuotaTitle"
	title.text = "Fleet quota"
	add_child(title)
	for role in CampaignFleet.Role.keys():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = role.capitalize()
		label.custom_minimum_size.x = EditorFields.LABEL_WIDTH
		row.add_child(label)
		var spin := SpinBox.new()
		spin.name = "Quota_%s" % role
		spin.max_value = 20.0
		spin.value = int(entry["quota"].get(role, 0))
		spin.value_changed.connect(func(value: float) -> void: set_quota(role, int(value)))
		row.add_child(spin)
		add_child(row)

func _build_extras(entry: Dictionary) -> void:
	var title := Label.new()
	title.name = "ExtraTitle"
	title.text = "Extra properties"
	add_child(title)
	var extra: Dictionary = entry.get("extra", {})
	for key in extra:
		var row := HBoxContainer.new()
		row.name = "Extra_%s" % key
		var label := Label.new()
		label.text = "%s = %s" % [key, extra[key]]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		row.add_child(label)
		var remove := Button.new()
		remove.name = "RemoveExtraButton"
		remove.text = "x"
		remove.pressed.connect(func() -> void: remove_extra(key))
		row.add_child(remove)
		add_child(row)
	var add_row := HBoxContainer.new()
	add_child(add_row)
	extra_key_edit = LineEdit.new()
	extra_key_edit.name = "ExtraKeyEdit"
	extra_key_edit.placeholder_text = "key"
	extra_key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(extra_key_edit)
	extra_value_edit = LineEdit.new()
	extra_value_edit.name = "ExtraValueEdit"
	extra_value_edit.placeholder_text = "value"
	extra_value_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(extra_value_edit)
	var add := Button.new()
	add.name = "AddExtraButton"
	add.text = "Add"
	add.pressed.connect(func() -> void: add_extra(extra_key_edit.text, extra_value_edit.text))
	add_row.add_child(add)

func _build_buttons(entry: Dictionary) -> void:
	var row := HBoxContainer.new()
	add_child(row)
	var is_player: bool = entry.get("owner", "") == MapEditModel.PLAYER_OWNER
	duplicate_button = Button.new()
	duplicate_button.name = "DuplicateButton"
	duplicate_button.text = "Duplicate"
	duplicate_button.disabled = is_player
	duplicate_button.pressed.connect(func() -> void: duplicate_requested.emit(station_id))
	row.add_child(duplicate_button)
	delete_button = Button.new()
	delete_button.name = "DeleteStationButton"
	delete_button.text = "Delete"
	delete_button.disabled = is_player
	delete_button.pressed.connect(func() -> void: delete_requested.emit(station_id))
	row.add_child(delete_button)

# Markers and the preview follow edits without rebuilding the controls (which would drop focus).
func _refresh_dynamic() -> void:
	if preview_label == null or not is_instance_valid(preview_label):
		return
	preview_label.text = preview_text()
	for key in _markers:
		var parts: PackedStringArray = str(key).split("|")
		var overridden := is_overridden(int(parts[0]), parts[1])
		_markers[key].visible = overridden
		_resets[key].visible = overridden
