class_name RefitPanel
extends Control

var _fleet: CampaignFleet
var _catalog: Array[String] = []
var _selected_ship_index: int = 0

@onready var credits_label: Label = $Layout/CreditsLabel
@onready var shop_button: Button = $Layout/TabRow/ShopButton
@onready var equip_button: Button = $Layout/TabRow/EquipButton
@onready var shop_scroll: ScrollContainer = $Layout/ShopScroll
@onready var equip_scroll: ScrollContainer = $Layout/EquipScroll
@onready var catalog_rows_container: VBoxContainer = $Layout/ShopScroll/ShopContainer/CatalogRowsContainer
@onready var inventory_rows_container: VBoxContainer = $Layout/ShopScroll/ShopContainer/InventoryRowsContainer
@onready var ship_selector: OptionButton = $Layout/EquipScroll/EquipContainer/ShipSelector
@onready var points_label: Label = $Layout/EquipScroll/EquipContainer/PointsLabel
@onready var slots_container: VBoxContainer = $Layout/EquipScroll/EquipContainer/SlotsContainer
@onready var close_button: Button = $Layout/CloseButton

func _ready() -> void:
	close_button.pressed.connect(close)
	shop_button.pressed.connect(_show_shop)
	equip_button.pressed.connect(_show_equip)
	ship_selector.item_selected.connect(_on_ship_selected)
	visible = false
	_show_shop()

func open_for(fleet: CampaignFleet, catalog: Array[String]) -> void:
	_fleet = fleet
	_catalog = catalog
	_selected_ship_index = 0
	visible = true
	_rebuild_ship_selector()
	refresh()

func close() -> void:
	visible = false
	_fleet = null
	_catalog = []

# Toggle the scrolls, not their contents: a visible-but-empty expand-fill
# scroll would still claim half the panel height.
func _show_shop() -> void:
	shop_scroll.visible = true
	equip_scroll.visible = false

func _show_equip() -> void:
	shop_scroll.visible = false
	equip_scroll.visible = true

func refresh() -> void:
	if _fleet == null:
		return
	credits_label.text = "Credits: %d" % CampaignState.credits
	_rebuild_catalog_rows()
	_rebuild_inventory_rows()
	_rebuild_slot_rows()

func _rebuild_ship_selector() -> void:
	ship_selector.clear()
	for i in _fleet.ship_compositions.size():
		var comp: Dictionary = _fleet.ship_compositions[i]
		ship_selector.add_item("Ship %d (%s)" % [i + 1, ShipType.Kind.keys()[ShipType.kind_of(comp)]], i)
	if _selected_ship_index >= _fleet.ship_compositions.size():
		_selected_ship_index = 0

func _on_ship_selected(index: int) -> void:
	_selected_ship_index = index
	refresh()

func _rebuild_catalog_rows() -> void:
	for child in catalog_rows_container.get_children():
		catalog_rows_container.remove_child(child)
		child.queue_free()
	for path in _catalog:
		var item: Resource = load(path)
		var price: float = PartRarity.price_for(item.rarity)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s  price:%d" % [_item_name(item), price]
		var buy_button := Button.new()
		buy_button.text = "Buy"
		buy_button.disabled = CampaignState.credits < price or _fleet.cargo_total() + 1.0 > _fleet.cargo_capacity()
		buy_button.pressed.connect(_on_buy_pressed.bind(path))
		row.add_child(label)
		row.add_child(buy_button)
		catalog_rows_container.add_child(row)

func _rebuild_inventory_rows() -> void:
	for child in inventory_rows_container.get_children():
		inventory_rows_container.remove_child(child)
		child.queue_free()
	for i in _fleet.part_inventory.size():
		var path: String = _fleet.part_inventory[i]
		var item: Resource = load(path)
		var sell_price: float = PartRarity.sell_price_for(item.rarity)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s  sell:%d" % [_item_name(item), sell_price]
		var sell_button := Button.new()
		sell_button.text = "Sell"
		sell_button.pressed.connect(_on_sell_pressed.bind(i))
		row.add_child(label)
		row.add_child(sell_button)
		inventory_rows_container.add_child(row)

func _rebuild_slot_rows() -> void:
	for child in slots_container.get_children():
		slots_container.remove_child(child)
		child.queue_free()
	if _fleet.ship_compositions.is_empty():
		points_label.text = "Points: -- / --"
		return
	var comp: Dictionary = _fleet.ship_compositions[_selected_ship_index]
	var budget := ShipType.points_budget_for(ShipType.kind_of(comp))
	var used := ShipType.points_used(comp)
	points_label.text = "Points: %d / %d" % [used, budget]
	var damaged := CampaignState.is_damaged(comp)

	var mount_count: int = int(ShipType.BASE_STATS[ShipType.kind_of(comp)]["weapon_mount_count"])
	for j in mount_count:
		_add_slot_row(comp, ShipType.SlotType.WEAPON, j, "Weapon %d" % (j + 1), Weapon, damaged, budget, used)
	_add_slot_row(comp, ShipType.SlotType.SHIELD, 0, "Shield", ShieldGenerator, damaged, budget, used)
	_add_slot_row(comp, ShipType.SlotType.ENGINE, 0, "Engine", EngineCore, damaged, budget, used)

	if damaged:
		var repair_label := Label.new()
		repair_label.text = "Repair this ship before refitting"
		slots_container.add_child(repair_label)

func _add_slot_row(comp: Dictionary, slot_type: ShipType.SlotType, slot_index: int, label_text: String, item_class: Script, damaged: bool, budget: int, used: int) -> void:
	var equipped_path := ShipType.equipped_path(comp, slot_type, slot_index)
	var equipped_name := "stock" if equipped_path == "" else _item_name(load(equipped_path))
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s: %s" % [label_text, equipped_name]
	var picker := OptionButton.new()
	var remaining_without_slot := used - ShipType.points_of_path(equipped_path)
	var compatible_indices: Array[int] = []
	for i in _fleet.part_inventory.size():
		var candidate: Resource = load(_fleet.part_inventory[i])
		if is_instance_of(candidate, item_class) and remaining_without_slot + PartRarity.points_for(candidate.rarity) <= budget:
			picker.add_item(_item_name(candidate))
			compatible_indices.append(i)
	var equip_btn := Button.new()
	equip_btn.text = "Equip"
	equip_btn.disabled = damaged or compatible_indices.is_empty()
	equip_btn.pressed.connect(_on_equip_pressed.bind(slot_type, slot_index, picker, compatible_indices))
	row.add_child(label)
	row.add_child(picker)
	row.add_child(equip_btn)
	slots_container.add_child(row)

func _item_name(item: Resource) -> String:
	if item is Weapon:
		return item.weapon_name
	return item.item_name

func _on_buy_pressed(path: String) -> void:
	CampaignState.buy_part(path, _fleet)
	refresh()

func _on_sell_pressed(inventory_index: int) -> void:
	CampaignState.sell_part(_fleet, inventory_index)
	refresh()

func _on_equip_pressed(slot_type: ShipType.SlotType, slot_index: int, picker: OptionButton, compatible_indices: Array[int]) -> void:
	if picker.selected < 0 or picker.selected >= compatible_indices.size():
		return
	var inventory_index: int = compatible_indices[picker.selected]
	var comp: Dictionary = _fleet.ship_compositions[_selected_ship_index]
	CampaignState.equip_part(comp, _fleet, slot_type, slot_index, inventory_index)
	refresh()
