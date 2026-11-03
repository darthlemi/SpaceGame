class_name FleetManagementPanel
extends Control

const FLAGSHIP_MARK := "[F]"
const FLAGSHIP_SET_TEXT := "Flag"
const LABEL_MIN_WIDTH := 80.0
const SLIDER_MIN_WIDTH := 60.0
const COUNT_MIN_WIDTH := 96.0

# One Dictionary per ship: flagship_button, label, slider, count_label, deploy_check.
var rows: Array[Dictionary] = []

var _economy: BaseEconomy
var _player_fleet: CampaignFleet

@onready var header_label: Label = $Layout/HeaderLabel
@onready var rows_container: VBoxContainer = $Layout/RowsScroll/RowsContainer
@onready var hire_row: Control = $Layout/HireRow
@onready var hire_label: Label = $Layout/HireRow/HireLabel
@onready var hire_count: SpinBox = $Layout/HireRow/HireCount
@onready var hire_button: Button = $Layout/HireRow/HireButton
@onready var balance_button: Button = $Layout/ButtonRow/BalanceButton
@onready var close_button: Button = $Layout/ButtonRow/CloseButton

func _ready() -> void:
	close_button.pressed.connect(close)
	balance_button.pressed.connect(_on_balance_pressed)
	hire_button.pressed.connect(_on_hire_pressed)
	visible = false

# docked_economy is null when the fleet is not docked (no hiring).
func open_for(fleet: CampaignFleet, docked_economy: BaseEconomy) -> void:
	_player_fleet = fleet
	_economy = docked_economy
	_clear_rows()
	visible = true
	refresh()

func close() -> void:
	visible = false
	_player_fleet = null
	_economy = null

func refresh() -> void:
	if _player_fleet == null:
		return
	var comps := _player_fleet.ship_compositions
	if rows.size() != comps.size():
		_clear_rows()
		for i in comps.size():
			_build_row(i)
	for i in comps.size():
		_update_row(i)
	header_label.text = "Crew %d / %d   Wages %.1f cr/tick   Credits %d" % [_player_fleet.crew_total(), _player_fleet.crew_capacity(), CampaignState.wage_bill(_player_fleet), CampaignState.credits]
	_update_hire_row()

# Single place rows are built, so per-row buttons can be added here.
func _build_row(index: int) -> void:
	var row := HBoxContainer.new()
	var flagship_button := Button.new()
	flagship_button.custom_minimum_size = Vector2(44, 0)
	flagship_button.pressed.connect(_on_flagship_pressed.bind(index))
	var label := Label.new()
	label.custom_minimum_size = Vector2(LABEL_MIN_WIDTH, 0)
	var slider := HSlider.new()
	slider.step = 1.0
	slider.custom_minimum_size = Vector2(SLIDER_MIN_WIDTH, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(_on_slider_changed.bind(index))
	var count_label := Label.new()
	count_label.custom_minimum_size = Vector2(COUNT_MIN_WIDTH, 0)
	var deploy_check := CheckBox.new()
	deploy_check.toggled.connect(_on_deploy_toggled.bind(index))
	for control in [flagship_button, label, slider, count_label, deploy_check]:
		row.add_child(control)
	rows_container.add_child(row)
	rows.append({
		"flagship_button": flagship_button,
		"label": label,
		"slider": slider,
		"count_label": count_label,
		"deploy_check": deploy_check,
	})

func _clear_rows() -> void:
	rows.clear()
	for child in rows_container.get_children():
		rows_container.remove_child(child)
		child.queue_free()

func _update_row(index: int) -> void:
	var comp: Dictionary = _player_fleet.ship_compositions[index]
	var row: Dictionary = rows[index]
	var complement := CrewRules.complement(comp)
	var crew := CrewRules.crew_of(comp)
	var deploy_min := CrewRules.deploy_min_for(complement)
	var flagship := CrewRules.is_flagship(comp)
	var flagship_button: Button = row["flagship_button"]
	flagship_button.text = FLAGSHIP_MARK if flagship else FLAGSHIP_SET_TEXT
	flagship_button.disabled = flagship
	var label: Label = row["label"]
	label.text = "%s %d" % [ShipType.Kind.keys()[ShipType.kind_of(comp)].capitalize(), index + 1]
	# no_signal: refresh must not re-enter set_ship_crew.
	var slider: HSlider = row["slider"]
	slider.max_value = complement
	slider.set_value_no_signal(crew)
	var count_label: Label = row["count_label"]
	count_label.text = "%d/%d (min %d)" % [crew, complement, deploy_min]
	var deploy_check: CheckBox = row["deploy_check"]
	var too_few := crew < deploy_min
	deploy_check.disabled = too_few
	deploy_check.text = "Too few" if too_few else "Deploy"
	deploy_check.set_pressed_no_signal(CrewRules.wants_deploy(comp) and not too_few)

func _update_hire_row() -> void:
	hire_row.visible = _economy != null
	if _economy == null:
		return
	var pool := floori(_economy.crew_pool)
	var cap := mini(pool, CrewRules.free_berths(_player_fleet.ship_compositions))
	hire_label.text = "Hire (pool %d, %d cr each)" % [pool, roundi(CampaignState.CREW_HIRE_COST)]
	hire_count.max_value = maxi(1, cap)
	hire_count.set_value_no_signal(clampf(hire_count.value, 1.0, hire_count.max_value))
	hire_button.disabled = cap < 1 or CampaignState.credits < CampaignState.CREW_HIRE_COST

func _on_balance_pressed() -> void:
	CrewRules.balance(_player_fleet.ship_compositions)
	refresh()

func _on_deploy_toggled(pressed: bool, index: int) -> void:
	_player_fleet.ship_compositions[index]["deploy"] = pressed

func _on_flagship_pressed(index: int) -> void:
	_player_fleet.set_flagship(index)
	refresh()

func _on_hire_pressed() -> void:
	CampaignState.hire_crew(_economy, _player_fleet, int(hire_count.value))
	refresh()

func _on_slider_changed(value: float, index: int) -> void:
	CrewRules.set_ship_crew(_player_fleet.ship_compositions, index, int(value))
	refresh()
