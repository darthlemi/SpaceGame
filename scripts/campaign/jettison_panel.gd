class_name JettisonPanel
extends Control

signal finished(confirmed: bool)

const LABEL_MIN_WIDTH := 110.0
const SLIDER_MIN_WIDTH := 80.0
const AMOUNT_MIN_WIDTH := 56.0

# One Dictionary per held commodity: commodity, slider, amount_label.
var cargo_rows: Array[Dictionary] = []
# One CheckBox per part_inventory entry / per ship, in fleet order.
var part_checks: Array[CheckBox] = []
var crew_checks: Array[CheckBox] = []

var _fleet: CampaignFleet
var _required_cargo := 0.0

@onready var header_label: Label = $Layout/HeaderLabel
@onready var rows_container: VBoxContainer = $Layout/RowsScroll/RowsContainer
@onready var confirm_button: Button = $Layout/ButtonRow/ConfirmButton
@onready var cancel_button: Button = $Layout/ButtonRow/CancelButton

func _ready() -> void:
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	visible = false

# required_cargo is the cargo (commodity units plus parts) that must be selected to confirm.
func open_for(fleet: CampaignFleet, required_cargo: float) -> void:
	_fleet = fleet
	_required_cargo = required_cargo
	_rebuild_rows()
	visible = true
	_refresh_state()

func _rebuild_rows() -> void:
	cargo_rows.clear()
	part_checks.clear()
	crew_checks.clear()
	for child in rows_container.get_children():
		rows_container.remove_child(child)
		child.queue_free()
	var commodities := _fleet.cargo.keys()
	commodities.sort()
	for commodity in commodities:
		var held: float = _fleet.cargo[commodity]
		if held <= 0.0:
			continue
		_add_cargo_row(commodity, held)
	for i in _fleet.part_inventory.size():
		var part_check := CheckBox.new()
		part_check.text = "Part: %s" % _part_name(_fleet.part_inventory[i])
		part_check.toggled.connect(_on_selection_changed)
		rows_container.add_child(part_check)
		part_checks.append(part_check)
	var flagship := _fleet.flagship_index()
	var floor_crew := CampaignState.flagship_floor(_fleet)
	for i in _fleet.ship_compositions.size():
		var comp: Dictionary = _fleet.ship_compositions[i]
		var removable := CrewRules.crew_of(comp)
		if i == flagship:
			removable = maxi(0, removable - floor_crew)
		var crew_check := CheckBox.new()
		crew_check.text = "Crew: %s %d (%d)" % [ShipType.Kind.keys()[ShipType.kind_of(comp)].capitalize(), i + 1, removable]
		crew_check.disabled = removable <= 0
		rows_container.add_child(crew_check)
		crew_checks.append(crew_check)

func _add_cargo_row(commodity: int, held: float) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s (%.1f)" % [Commodity.NAMES[commodity], held]
	label.custom_minimum_size = Vector2(LABEL_MIN_WIDTH, 0)
	var slider := HSlider.new()
	slider.step = 1.0
	slider.max_value = held
	slider.custom_minimum_size = Vector2(SLIDER_MIN_WIDTH, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(_on_selection_changed)
	var amount_label := Label.new()
	amount_label.custom_minimum_size = Vector2(AMOUNT_MIN_WIDTH, 0)
	for control in [label, slider, amount_label]:
		row.add_child(control)
	rows_container.add_child(row)
	cargo_rows.append({"commodity": commodity, "slider": slider, "amount_label": amount_label})

func _part_name(path: String) -> String:
	var item: Resource = load(path)
	if item == null:
		return path.get_file()
	if item is Weapon:
		return item.weapon_name
	return item.item_name

func _selected_cargo() -> float:
	var sum := 0.0
	for row in cargo_rows:
		var slider: HSlider = row["slider"]
		sum += slider.value
	return sum + _selected_part_indices().size()

func _selected_part_indices() -> Array[int]:
	var indices: Array[int] = []
	for i in part_checks.size():
		if part_checks[i].button_pressed:
			indices.append(i)
	return indices

func _refresh_state() -> void:
	var selected := _selected_cargo()
	for row in cargo_rows:
		var slider: HSlider = row["slider"]
		var amount_label: Label = row["amount_label"]
		amount_label.text = "%d" % int(slider.value)
	header_label.text = "Jettison: %.1f / %.1f cargo required" % [selected, _required_cargo]
	confirm_button.disabled = selected < _required_cargo

func _on_selection_changed(_value = null) -> void:
	_refresh_state()

func _on_confirm_pressed() -> void:
	var amounts := {}
	for row in cargo_rows:
		var slider: HSlider = row["slider"]
		amounts[row["commodity"]] = slider.value
	var crew_by_ship := {}
	for i in crew_checks.size():
		if crew_checks[i].button_pressed:
			crew_by_ship[i] = CrewRules.crew_of(_fleet.ship_compositions[i])
	CampaignState.jettison(_fleet, amounts, _selected_part_indices(), crew_by_ship)
	visible = false
	finished.emit(true)

func _on_cancel_pressed() -> void:
	visible = false
	finished.emit(false)
