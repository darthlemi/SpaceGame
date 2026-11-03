class_name LootPanel
extends Control

var _defeated_fleet: CampaignFleet
var _player_fleet: CampaignFleet
var _rows: Dictionary = {}
var _captured_crew: int = 0
var _crew_label: Label

var crew_take_button: Button

@onready var rows_container: VBoxContainer = $Layout/RowsScroll/RowsContainer
@onready var close_button: Button = $Layout/CloseButton

func _ready() -> void:
	close_button.pressed.connect(close)
	visible = false

func open_for(defeated_fleet: CampaignFleet, player_fleet: CampaignFleet, captured_crew: int = 0) -> void:
	_captured_crew = captured_crew
	_defeated_fleet = defeated_fleet
	_player_fleet = player_fleet
	visible = true
	_rebuild_rows()

func close() -> void:
	visible = false
	_defeated_fleet = null
	_player_fleet = null

func refresh() -> void:
	if _defeated_fleet == null or _player_fleet == null:
		return
	if crew_take_button != null:
		_crew_label.text = "Crew  available:%d" % _captured_crew
		crew_take_button.disabled = _captured_crew < 1 or CrewRules.free_berths(_player_fleet.ship_compositions) < 1
	for commodity in _rows.keys():
		var row: Dictionary = _rows[commodity]
		var available: float = _defeated_fleet.cargo.get(commodity, 0.0)
		row["label"].text = "%s  available:%.0f" % [Commodity.NAMES[commodity], available]
		row["take_button"].disabled = available < 1.0 or _player_fleet.cargo_total() + 1.0 > _player_fleet.cargo_capacity()

func _rebuild_rows() -> void:
	for child in rows_container.get_children():
		rows_container.remove_child(child)
		child.queue_free()
	_rows = {}
	crew_take_button = null
	_crew_label = null
	if _captured_crew > 0:
		var crew_box := HBoxContainer.new()
		_crew_label = Label.new()
		crew_take_button = Button.new()
		crew_take_button.text = "Take"
		crew_take_button.pressed.connect(_on_crew_take_pressed)
		crew_box.add_child(_crew_label)
		crew_box.add_child(crew_take_button)
		rows_container.add_child(crew_box)
	for commodity in _defeated_fleet.cargo.keys():
		if _defeated_fleet.cargo[commodity] <= 0.0:
			continue
		var row_box := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = load(Commodity.ICON_TEXTURES[commodity])
		icon.custom_minimum_size = Vector2(18, 18)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		var label := Label.new()
		var take_button := Button.new()
		take_button.text = "Take"
		take_button.pressed.connect(_on_take_pressed.bind(commodity))
		row_box.add_child(icon)
		row_box.add_child(label)
		row_box.add_child(take_button)
		rows_container.add_child(row_box)
		_rows[commodity] = {"icon": icon, "label": label, "take_button": take_button}
	refresh()

func _on_take_pressed(commodity: int) -> void:
	var available: float = _defeated_fleet.cargo.get(commodity, 0.0)
	if available < 1.0 or _player_fleet.cargo_total() + 1.0 > _player_fleet.cargo_capacity():
		return
	_defeated_fleet.cargo[commodity] = available - 1.0
	_player_fleet.cargo[commodity] = _player_fleet.cargo.get(commodity, 0.0) + 1.0
	refresh()

func _on_crew_take_pressed() -> void:
	var take := mini(_captured_crew, CrewRules.free_berths(_player_fleet.ship_compositions))
	if take < 1:
		return
	_captured_crew -= CrewRules.add_crew(_player_fleet.ship_compositions, take)
	refresh()
