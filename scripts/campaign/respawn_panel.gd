class_name RespawnPanel
extends Control

signal finished

# Kind -> Button, one per purchasable ship.
var buy_buttons: Dictionary = {}

@onready var header_label: Label = $Layout/HeaderLabel
@onready var credits_label: Label = $Layout/CreditsLabel
@onready var buy_container: VBoxContainer = $Layout/BuyScroll/BuyContainer
@onready var free_button: Button = $Layout/FreeButton

func _ready() -> void:
	free_button.pressed.connect(_on_free_pressed)
	visible = false

func open_for() -> void:
	_rebuild_buttons()
	visible = true

func _rebuild_buttons() -> void:
	for child in buy_container.get_children():
		buy_container.remove_child(child)
		child.queue_free()
	buy_buttons = {}
	header_label.text = "Your fleet was lost. Choose a new ship."
	credits_label.text = "Credits: %d" % floori(CampaignState.credits)
	for kind in ShipType.Kind.values():
		var button := Button.new()
		button.text = "Buy %s (%d cr)" % [ShipType.Kind.keys()[kind].capitalize(), ShipType.SHIP_PRICE[kind]]
		button.disabled = CampaignState.credits < ShipType.SHIP_PRICE[kind]
		button.pressed.connect(_on_buy_pressed.bind(kind))
		buy_container.add_child(button)
		buy_buttons[kind] = button

func _on_buy_pressed(kind: ShipType.Kind) -> void:
	if CampaignState.complete_respawn(kind, true):
		_finish()

func _on_free_pressed() -> void:
	if CampaignState.complete_respawn(ShipType.Kind.CORVETTE, false):
		_finish()

func _finish() -> void:
	visible = false
	finished.emit()
