class_name EditorFields
extends RefCounted

# Field descriptors the map editor's inspectors are built from: add an entry to add a row.
# {"key", "label", "type": "string" | "int" | "float" | "vector2" | "enum" | "bool", "default",
#  "choices" (enum: an Array, or "systems" / "art" resolved by the editor),
#  "optional" (a value equal to the default removes the key), "min", "max", "step"}.

const SYSTEM_FIELDS: Array[Dictionary] = [
	{"key": "name", "label": "Name", "type": "string", "default": ""},
	{"key": "map", "label": "Map x / y", "type": "vector2", "default": Vector2(0.5, 0.5), "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "tier", "label": "Danger tier (0 = auto)", "type": "int", "default": 0, "optional": true, "min": 0, "max": 5},
]

const STATION_FIELDS: Array[Dictionary] = [
	{"key": "name", "label": "Name", "type": "string", "default": ""},
	{"key": "system", "label": "System", "type": "enum", "default": "", "choices": "systems"},
	{"key": "owner", "label": "Owner", "type": "enum", "default": "NEUTRAL", "choices": "owners"},
	{"key": "art", "label": "Art", "type": "enum", "default": "ring_2", "choices": "art"},
	{"key": "pos", "label": "Position x / y", "type": "vector2", "default": Vector2(580.0, 350.0), "min": 0.0, "max": 1200.0, "step": 1.0},
]

const LABEL_WIDTH := 130.0
const DEFAULT_MIN := -1000000.0
const DEFAULT_MAX := 1000000.0
const SPIN_WIDTH := 80.0

# The entry's value as the control type: vector2 arrays become Vector2, numbers int / float.
static func value_of(entry: Dictionary, spec: Dictionary):
	var raw = entry.get(spec["key"], spec["default"])
	match spec["type"]:
		"int":
			return int(raw)
		"float":
			return float(raw)
		"bool":
			return bool(raw)
		"vector2":
			return Vector2(raw[0], raw[1]) if typeof(raw) == TYPE_ARRAY else raw
	return raw

# True when a committed value should remove the key instead of storing it.
static func is_default(spec: Dictionary, value) -> bool:
	return spec.get("optional", false) and value == spec["default"]

# One labelled row. on_change(value) is called with the typed value on a user edit only.
static func make_row(spec: Dictionary, value, choices: Array, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % spec["key"]
	var label := Label.new()
	label.text = spec["label"]
	label.custom_minimum_size.x = LABEL_WIDTH
	row.add_child(label)
	match spec["type"]:
		"enum":
			row.add_child(_enum_control(value, choices, on_change))
		"bool":
			var box := CheckBox.new()
			box.button_pressed = value
			box.toggled.connect(func(pressed: bool) -> void: on_change.call(pressed))
			row.add_child(box)
		"vector2":
			_add_vector_controls(row, spec, value, on_change)
		"int", "float":
			var spin := _spin(spec, float(value))
			spin.value_changed.connect(func(v: float) -> void: on_change.call(int(v) if spec["type"] == "int" else v))
			row.add_child(spin)
		_:
			row.add_child(_line_edit(str(value), on_change))
	return row

static func _spin(spec: Dictionary, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = spec.get("min", DEFAULT_MIN)
	spin.max_value = spec.get("max", DEFAULT_MAX)
	spin.step = spec.get("step", 1.0 if spec["type"] == "int" else 0.01)
	spin.value = value
	spin.custom_minimum_size.x = SPIN_WIDTH
	return spin

static func _add_vector_controls(row: HBoxContainer, spec: Dictionary, value: Vector2, on_change: Callable) -> void:
	var x_spin := _spin(spec, value.x)
	var y_spin := _spin(spec, value.y)
	x_spin.name = "X"
	y_spin.name = "Y"
	x_spin.value_changed.connect(func(_v: float) -> void: on_change.call(Vector2(x_spin.value, y_spin.value)))
	y_spin.value_changed.connect(func(_v: float) -> void: on_change.call(Vector2(x_spin.value, y_spin.value)))
	row.add_child(x_spin)
	row.add_child(y_spin)

static func _enum_control(value, choices: Array, on_change: Callable) -> OptionButton:
	var option := OptionButton.new()
	var shown := choices.duplicate()
	# A value the list doesn't know stays visible so it is never silently replaced.
	if not shown.has(value):
		shown.append(value)
	for choice in shown:
		option.add_item(str(choice))
	option.select(shown.find(value))
	option.item_selected.connect(func(index: int) -> void: on_change.call(shown[index]))
	return option

static func _line_edit(text: String, on_change: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var last := [text]
	var commit := func(new_text: String) -> void:
		if new_text != last[0]:
			last[0] = new_text
			on_change.call(new_text)
	edit.text_submitted.connect(commit)
	edit.focus_exited.connect(func() -> void: commit.call(edit.text))
	return edit
