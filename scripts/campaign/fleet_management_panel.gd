class_name FleetManagementPanel
extends Control

const FLAGSHIP_MARK := "[F]"
const FLAGSHIP_SET_TEXT := "Flag"
const LABEL_MIN_WIDTH := 80.0
const SLIDER_MIN_WIDTH := 60.0
const COUNT_MIN_WIDTH := 96.0

# One Dictionary per ship: flagship_button, label, slider, count_label, deploy_check, scuttle_button.
var rows: Array[Dictionary] = []

var _economy: BaseEconomy
var _player_fleet: CampaignFleet
var _scuttle_index := -1

@onready var header_label: Label = $Layout/HeaderLabel
@onready var rows_container: VBoxContainer = $Layout/RowsScroll/RowsContainer
@onready var hire_row: Control = $Layout/HireRow
@onready var hire_label: Label = $Layout/HireRow/HireLabel
@onready var hire_count: SpinBox = $Layout/HireRow/HireCount
@onready var hire_button: Button = $Layout/HireRow/HireButton
@onready var balance_button: Button = $Layout/ButtonRow/BalanceButton
@onready var close_button: Button = $Layout/ButtonRow/CloseButton
@onready var jettison_button: Button = $Layout/ButtonRow/JettisonButton
@onready var scuttle_confirm_row: Control = $Layout/ScuttleConfirmRow
@onready var scuttle_confirm_label: Label = $Layout/ScuttleConfirmRow/ScuttleConfirmLabel
@onready var scuttle_confirm_button: Button = $Layout/ScuttleConfirmRow/ScuttleConfirmButton
@onready var scuttle_cancel_button: Button = $Layout/ScuttleConfirmRow/ScuttleCancelButton
@onready var jettison_panel: JettisonPanel = $JettisonPanel

func _ready() -> void:
	close_button.pressed.connect(close)
	balance_button.pressed.connect(_on_balance_pressed)
	hire_button.pressed.connect(_on_hire_pressed)
	hire_count.value_changed.connect(_on_hire_count_changed)
	jettison_button.pressed.connect(_on_jettison_pressed)
	scuttle_confirm_button.pressed.connect(_on_scuttle_confirmed)
	scuttle_cancel_button.pressed.connect(_hide_scuttle_confirm)
	jettison_panel.finished.connect(_on_jettison_finished)
	visible = false

# docked_economy is null when the fleet is not docked (no hiring).
func open_for(fleet: CampaignFleet, docked_economy: BaseEconomy) -> void:
	_player_fleet = fleet
	_economy = docked_economy
	_clear_rows()
	_hide_scuttle_confirm()
	visible = true
	refresh()

func close() -> void:
	visible = false
	jettison_panel.visible = false
	_hide_scuttle_confirm()
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
	header_label.text = "Crew %d / %d   Wages %d cr/tick   Credits %d" % [_player_fleet.crew_total(), _player_fleet.crew_capacity(), CampaignState.wage_bill(_player_fleet), CampaignState.credits]
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
	var scuttle_button := Button.new()
	scuttle_button.text = "Scuttle"
	scuttle_button.pressed.connect(_on_scuttle_pressed.bind(index))
	for control in [flagship_button, label, slider, count_label, deploy_check, scuttle_button]:
		row.add_child(control)
	rows_container.add_child(row)
	rows.append({
		"flagship_button": flagship_button,
		"label": label,
		"slider": slider,
		"count_label": count_label,
		"deploy_check": deploy_check,
		"scuttle_button": scuttle_button,
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
	var scuttle_button: Button = row["scuttle_button"]
	var scuttle := CampaignState.scuttle_check(_player_fleet, index)
	scuttle_button.disabled = not scuttle["allowed"]
	scuttle_button.tooltip_text = scuttle["reason"]

func _update_hire_row() -> void:
	hire_row.visible = _economy != null
	if _economy == null:
		return
	var pool := floori(_economy.crew_pool)
	var cap := mini(pool, CrewRules.free_berths(_player_fleet.ship_compositions))
	cap = mini(cap, floori(CampaignState.credits / float(CampaignState.CREW_HIRE_COST)))
	hire_label.text = "Hire (pool %d, %d cr each)" % [pool, CampaignState.CREW_HIRE_COST]
	hire_count.max_value = maxi(1, cap)
	hire_count.set_value_no_signal(clampf(hire_count.value, 1.0, hire_count.max_value))
	hire_button.text = "Hire (%d cr)" % (int(hire_count.value) * CampaignState.CREW_HIRE_COST)
	hire_button.disabled = cap < 1

func _on_balance_pressed() -> void:
	CrewRules.balance(_player_fleet.ship_compositions)
	refresh()

func _on_deploy_toggled(pressed: bool, index: int) -> void:
	_player_fleet.ship_compositions[index]["deploy"] = pressed

func _on_flagship_pressed(index: int) -> void:
	_player_fleet.set_flagship(index)
	refresh()

func _on_hire_count_changed(_value: float) -> void:
	_update_hire_row()

func _on_hire_pressed() -> void:
	CampaignState.hire_crew(_economy, _player_fleet, int(hire_count.value))
	refresh()

func _on_slider_changed(value: float, index: int) -> void:
	CrewRules.set_ship_crew(_player_fleet.ship_compositions, index, int(value))
	refresh()

func _hide_scuttle_confirm() -> void:
	_scuttle_index = -1
	scuttle_confirm_row.visible = false

func _on_jettison_finished(confirmed: bool) -> void:
	if confirmed and _scuttle_index >= 0:
		CampaignState.scuttle_ship(_player_fleet, _scuttle_index)
	_hide_scuttle_confirm()
	refresh()

func _on_jettison_pressed() -> void:
	_hide_scuttle_confirm()
	jettison_panel.open_for(_player_fleet, 0.0)

func _on_scuttle_confirmed() -> void:
	var check := CampaignState.scuttle_check(_player_fleet, _scuttle_index)
	if not check["allowed"]:
		_hide_scuttle_confirm()
		return
	if check["cargo_overflow"] > 0.0:
		scuttle_confirm_row.visible = false
		jettison_panel.open_for(_player_fleet, check["cargo_overflow"])
		return
	CampaignState.scuttle_ship(_player_fleet, _scuttle_index)
	_hide_scuttle_confirm()
	refresh()

func _on_scuttle_pressed(index: int) -> void:
	var check := CampaignState.scuttle_check(_player_fleet, index)
	if not check["allowed"]:
		return
	_scuttle_index = index
	scuttle_confirm_label.text = "Scuttle %s? Lost: %d crew, %.1f cargo" % [rows[index]["label"].text, check["crew_lost"], check["cargo_overflow"]]
	scuttle_confirm_row.visible = true
