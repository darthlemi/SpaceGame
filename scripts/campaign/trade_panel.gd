class_name TradePanel
extends Control

var _docked_base_economy: BaseEconomy
var _player_fleet: CampaignFleet
var _rows: Dictionary = {}

@onready var rows_container: VBoxContainer = $Layout/RowsContainer
@onready var credits_label: Label = $Layout/CreditsLabel
@onready var close_button: Button = $Layout/ButtonRow/CloseButton

func _ready() -> void:
	close_button.pressed.connect(close)
	visible = false
	_build_rows()

func open_for(base_economy: BaseEconomy, fleet: CampaignFleet) -> void:
	_docked_base_economy = base_economy
	_player_fleet = fleet
	visible = true
	refresh()

func close() -> void:
	visible = false
	_docked_base_economy = null
	_player_fleet = null

func refresh() -> void:
	if _docked_base_economy == null or _player_fleet == null:
		return
	credits_label.text = "Credits: %d" % CampaignState.credits
	for commodity in _rows.keys():
		var row: Dictionary = _rows[commodity]
		var stock: float = _docked_base_economy.stock.get(commodity, 0.0)
		var buy_price := _docked_base_economy.price_for(commodity)
		var sell_price := _docked_base_economy.sell_price_for(commodity)
		var held: float = _player_fleet.cargo.get(commodity, 0.0)
		row["label"].text = "%s  stock:%.0f  buy:%.0f  sell:%.0f  held:%.0f" % [Commodity.NAMES[commodity], stock, buy_price, sell_price, held]
		row["buy_button"].disabled = CampaignState.credits < buy_price or stock < 1.0 or _player_fleet.cargo_total() + 1.0 > _player_fleet.cargo_capacity()
		row["sell_button"].disabled = held < 1.0

func _build_rows() -> void:
	if not _rows.is_empty():
		return
	for commodity in Commodity.Type.values():
		var row_box := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = load(Commodity.ICON_TEXTURES[commodity])
		icon.custom_minimum_size = Vector2(18, 18)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		var label := Label.new()
		var buy_button := Button.new()
		buy_button.text = "Buy"
		buy_button.pressed.connect(_on_buy_pressed.bind(commodity))
		var sell_button := Button.new()
		sell_button.text = "Sell"
		sell_button.pressed.connect(_on_sell_pressed.bind(commodity))
		row_box.add_child(icon)
		row_box.add_child(label)
		row_box.add_child(buy_button)
		row_box.add_child(sell_button)
		rows_container.add_child(row_box)
		_rows[commodity] = {"icon": icon, "label": label, "buy_button": buy_button, "sell_button": sell_button}

func _on_buy_pressed(commodity: int) -> void:
	CampaignState.buy(_docked_base_economy, commodity, _player_fleet)
	refresh()

func _on_sell_pressed(commodity: int) -> void:
	CampaignState.sell(_docked_base_economy, commodity, _player_fleet)
	refresh()
