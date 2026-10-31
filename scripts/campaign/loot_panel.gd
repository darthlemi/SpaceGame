class_name LootPanel
extends Control

var _defeated_fleet: CampaignFleet
var _player_fleet: CampaignFleet
var _rows: Dictionary = {}

@onready var rows_container: VBoxContainer = $RowsContainer
@onready var close_button: Button = $CloseButton

func _ready() -> void:
	close_button.pressed.connect(close)
	visible = false

func open_for(defeated_fleet: CampaignFleet, player_fleet: CampaignFleet) -> void:
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
	for commodity in _rows.keys():
		var row: Dictionary = _rows[commodity]
		var available: float = _defeated_fleet.cargo.get(commodity, 0.0)
		row["label"].text = "%s  available:%.0f" % [Commodity.NAMES[commodity], available]
		row["take_button"].disabled = available < 1.0 or _player_fleet.cargo_total() + 1.0 > _player_fleet.cargo_capacity()

func _rebuild_rows() -> void:
	for child in rows_container.get_children():
		child.queue_free()
	_rows = {}
	for commodity in _defeated_fleet.cargo.keys():
		if _defeated_fleet.cargo[commodity] <= 0.0:
			continue
		var row_box := HBoxContainer.new()
		var label := Label.new()
		var take_button := Button.new()
		take_button.text = "Take"
		take_button.pressed.connect(_on_take_pressed.bind(commodity))
		row_box.add_child(label)
		row_box.add_child(take_button)
		rows_container.add_child(row_box)
		_rows[commodity] = {"label": label, "take_button": take_button}
	refresh()

func _on_take_pressed(commodity: int) -> void:
	var available: float = _defeated_fleet.cargo.get(commodity, 0.0)
	if available < 1.0 or _player_fleet.cargo_total() + 1.0 > _player_fleet.cargo_capacity():
		return
	_defeated_fleet.cargo[commodity] = available - 1.0
	_player_fleet.cargo[commodity] = _player_fleet.cargo.get(commodity, 0.0) + 1.0
	refresh()
