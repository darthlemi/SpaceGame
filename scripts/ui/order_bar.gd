class_name OrderBar
extends Control

signal flee_pressed
signal formation_picked(type: Formation.Type)
signal hold_pressed

const FORMATION_NAMES := {
	Formation.Type.NONE: "Free",
	Formation.Type.LINE: "Line",
	Formation.Type.WEDGE: "Wedge",
	Formation.Type.BOX: "Box",
	Formation.Type.CIRCLE: "Circle",
}

@onready var hold_button: Button = $Row/HoldButton
@onready var flee_button: Button = $Row/FleeButton
@onready var formation_button: Button = $Row/FormationButton
@onready var popup: Control = $Popup
@onready var popup_buttons: Control = $Popup/Buttons

var _formation_buttons: Dictionary = {}

func _ready() -> void:
	set_has_selection(false)
	hold_button.pressed.connect(func(): hold_pressed.emit())
	flee_button.pressed.connect(func(): flee_pressed.emit())
	formation_button.pressed.connect(func(): popup.visible = not popup.visible)
	var group := ButtonGroup.new()
	# Hotkeys 1-5 follow the enum order.
	for type in Formation.Type.values():
		var button := Button.new()
		button.text = "%s %d" % [FORMATION_NAMES[type], type + 1]
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(_on_formation_button_pressed.bind(type))
		popup_buttons.add_child(button)
		_formation_buttons[type] = button
	show_formation(Formation.Type.NONE)

func set_has_selection(value: bool) -> void:
	hold_button.disabled = not value
	flee_button.disabled = not value

# Does not emit formation_picked: the commander is the source when this is called.
func show_formation(type: Formation.Type) -> void:
	formation_button.text = "Formation: %s ^" % FORMATION_NAMES[type]
	# set_pressed_no_signal skips the group, so unpress the others by hand.
	for key in _formation_buttons:
		_formation_buttons[key].set_pressed_no_signal(key == type)

func _on_formation_button_pressed(type: Formation.Type) -> void:
	popup.visible = false
	formation_picked.emit(type)
