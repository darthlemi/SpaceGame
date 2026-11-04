class_name LootPanel
extends Control

var _offer: LootOffer
var _player_fleet: CampaignFleet
var _rows: Dictionary = {}

# One entry per offered ship, in offer.ships order: {"keep_check": CheckBox, "label": Label}.
var ship_rows: Array[Dictionary] = []
# One entry per offered part still on the table: {"path": String, "box": Control, "take_button": Button}.
var part_rows: Array[Dictionary] = []

@onready var rows_container: VBoxContainer = $Layout/RowsScroll/RowsContainer
@onready var crew_row: HBoxContainer = $Layout/CrewRow
@onready var crew_label: Label = $Layout/CrewRow/CrewLabel
@onready var crew_slider: HSlider = $Layout/CrewRow/CrewSlider
@onready var take_button: Button = $Layout/ButtonsRow/TakeButton
@onready var close_button: Button = $Layout/ButtonsRow/CloseButton

func _ready() -> void:
	close_button.pressed.connect(close)
	take_button.pressed.connect(_on_take_ships_pressed)
	crew_slider.value_changed.connect(_on_crew_slider_changed)
	visible = false

func open_for(offer: LootOffer, player_fleet: CampaignFleet) -> void:
	_offer = offer
	_player_fleet = player_fleet
	visible = true
	_rebuild_rows()

func close() -> void:
	visible = false
	_offer = null
	_player_fleet = null

func refresh() -> void:
	if _offer == null or _player_fleet == null:
		return
	var has_room := _player_fleet.cargo_total() + 1.0 <= _player_fleet.cargo_capacity()
	for commodity in _rows.keys():
		var row: Dictionary = _rows[commodity]
		var available: float = _offer.cargo.get(commodity, 0.0)
		row["label"].text = "%s  available:%.0f" % [Commodity.NAMES[commodity], available]
		row["take_button"].disabled = available < 1.0 or not has_room
	for row in part_rows:
		row["take_button"].disabled = not has_room
	_refresh_crew()

func _rebuild_rows() -> void:
	for child in rows_container.get_children():
		rows_container.remove_child(child)
		child.queue_free()
	_rows = {}
	ship_rows = []
	part_rows = []
	for i in _offer.ships.size():
		_add_ship_row(_offer.ships[i])
	for path in _offer.parts:
		_add_part_row(path)
	for commodity in _offer.cargo.keys():
		if _offer.cargo[commodity] <= 0.0:
			continue
		var row_box := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = load(Commodity.ICON_TEXTURES[commodity])
		icon.custom_minimum_size = Vector2(18, 18)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		var label := Label.new()
		var commodity_take := Button.new()
		commodity_take.text = "Take"
		commodity_take.pressed.connect(_on_take_pressed.bind(commodity))
		row_box.add_child(icon)
		row_box.add_child(label)
		row_box.add_child(commodity_take)
		rows_container.add_child(row_box)
		_rows[commodity] = {"icon": icon, "label": label, "take_button": commodity_take}
	var has_ships := not _offer.ships.is_empty()
	crew_row.visible = has_ships
	take_button.visible = has_ships
	crew_slider.max_value = _crew_cap()
	crew_slider.set_value_no_signal(0.0)
	refresh()

func _add_ship_row(comp: Dictionary) -> void:
	var row_box := HBoxContainer.new()
	var keep_check := CheckBox.new()
	keep_check.text = "Keep"
	var label := Label.new()
	var hull_fraction := 0.0
	if comp["max_hp"] > 0.0:
		hull_fraction = comp["current_hp"] / comp["max_hp"]
	label.text = "%s  hull %d%%  crew %d/%d" % [ShipType.Kind.keys()[ShipType.kind_of(comp)].capitalize(), roundi(hull_fraction * 100.0), CrewRules.crew_of(comp), CrewRules.complement(comp)]
	keep_check.toggled.connect(_on_keep_toggled)
	row_box.add_child(keep_check)
	row_box.add_child(label)
	rows_container.add_child(row_box)
	ship_rows.append({"keep_check": keep_check, "label": label})

func _add_part_row(path: String) -> void:
	var row_box := HBoxContainer.new()
	var label := Label.new()
	label.text = "Part  %s" % _part_name(path)
	var part_take := Button.new()
	part_take.text = "Take"
	var row := {"path": path, "box": row_box, "take_button": part_take}
	part_take.pressed.connect(_on_part_take_pressed.bind(row))
	row_box.add_child(label)
	row_box.add_child(part_take)
	rows_container.add_child(row_box)
	part_rows.append(row)

func _part_name(path: String) -> String:
	var item: Resource = load(path)
	if item == null:
		return path.get_file()
	if item is Weapon:
		return item.weapon_name
	return item.item_name

func _kept_comps() -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for i in ship_rows.size():
		if ship_rows[i]["keep_check"].button_pressed:
			kept.append(_offer.ships[i])
	return kept

func _crew_cap() -> int:
	var berths := CrewRules.free_berths(_player_fleet.ship_compositions)
	for comp in _kept_comps():
		berths += CrewRules.complement(comp)
	return mini(_offer.crew_pool(), berths)

# Wage delta of the slider's crew, computed on a scratch fleet so floor-per-group and the
# flagship exemption match what pay_wages will charge.
func _added_wages() -> int:
	var scratch := CampaignFleet.new()
	scratch.ship_compositions.assign(_player_fleet.ship_compositions.duplicate(true))
	var before := CampaignState.wage_bill(scratch)
	for comp in _kept_comps():
		var copy := comp.duplicate(true)
		CrewRules.set_crew(copy, 0)
		copy["flagship"] = false
		scratch.ship_compositions.append(copy)
	CrewRules.add_crew(scratch.ship_compositions, int(crew_slider.value))
	return CampaignState.wage_bill(scratch) - before

func _refresh_crew() -> void:
	crew_label.text = "Crew  %d  +%d cr/tick" % [int(crew_slider.value), _added_wages()]

func _on_keep_toggled(pressed: bool) -> void:
	var cap := _crew_cap()
	crew_slider.max_value = cap
	if pressed:
		crew_slider.value = cap
	else:
		crew_slider.value = minf(crew_slider.value, cap)
	_refresh_crew()

func _on_crew_slider_changed(_value: float) -> void:
	_refresh_crew()

func _on_part_take_pressed(row: Dictionary) -> void:
	if _player_fleet.cargo_total() + 1.0 > _player_fleet.cargo_capacity():
		return
	_offer.parts.erase(row["path"])
	_player_fleet.part_inventory.append(row["path"])
	part_rows.erase(row)
	rows_container.remove_child(row["box"])
	row["box"].queue_free()
	refresh()

func _on_take_pressed(commodity: int) -> void:
	var available: float = _offer.cargo.get(commodity, 0.0)
	if available < 1.0 or _player_fleet.cargo_total() + 1.0 > _player_fleet.cargo_capacity():
		return
	_offer.cargo[commodity] = available - 1.0
	_player_fleet.cargo[commodity] = _player_fleet.cargo.get(commodity, 0.0) + 1.0
	refresh()

# Captured ships join empty; the slider's crew is then spread over the whole fleet.
func _on_take_ships_pressed() -> void:
	var crew := mini(int(crew_slider.value), _crew_cap())
	for comp in _kept_comps():
		var copy := comp.duplicate(true)
		CrewRules.set_crew(copy, 0)
		copy["flagship"] = false
		_player_fleet.ship_compositions.append(copy)
	CrewRules.add_crew(_player_fleet.ship_compositions, crew)
	_player_fleet.ensure_flagship()
	close()
