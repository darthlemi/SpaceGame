class_name RepairPanel
extends Control

var _player_fleet: CampaignFleet

@onready var credits_label: Label = $Layout/CreditsLabel
@onready var repair_container: VBoxContainer = $Layout/RepairScroll/RepairContainer
@onready var repair_all_button: Button = $Layout/ButtonRow/RepairAllButton
@onready var close_button: Button = $Layout/ButtonRow/CloseButton

func _ready() -> void:
	close_button.pressed.connect(close)
	repair_all_button.pressed.connect(_on_repair_all_pressed)
	visible = false

func open_for(fleet: CampaignFleet) -> void:
	_player_fleet = fleet
	visible = true
	refresh()

func close() -> void:
	visible = false
	_player_fleet = null

func refresh() -> void:
	if _player_fleet == null:
		return
	credits_label.text = "Credits: %d" % CampaignState.credits
	for child in repair_container.get_children():
		repair_container.remove_child(child)
		child.queue_free()
	var total_cost := 0
	for i in _player_fleet.ship_compositions.size():
		var comp: Dictionary = _player_fleet.ship_compositions[i]
		var cost := CampaignState.repair_cost_for(comp)
		if cost <= 0:
			continue
		total_cost += cost
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "Ship %d  repair cost: %d" % [i + 1, cost]
		var button := Button.new()
		button.text = "Repair"
		button.disabled = CampaignState.credits < cost
		button.pressed.connect(_on_repair_pressed.bind(i))
		row.add_child(label)
		row.add_child(button)
		repair_container.add_child(row)
	if total_cost <= 0:
		var none_label := Label.new()
		none_label.text = "All ships are fully repaired."
		repair_container.add_child(none_label)
	repair_all_button.disabled = total_cost <= 0 or CampaignState.credits < total_cost

func _on_repair_pressed(index: int) -> void:
	CampaignState.repair_ship(_player_fleet.ship_compositions[index])
	refresh()

func _on_repair_all_pressed() -> void:
	for comp in _player_fleet.ship_compositions:
		if CampaignState.repair_cost_for(comp) > 0 and CampaignState.credits >= CampaignState.REPAIR_COST:
			CampaignState.repair_ship(comp)
	refresh()
