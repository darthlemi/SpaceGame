class_name ControlToggle
extends Node

enum Mode { RTS_COMMAND, DIRECT_PILOT }

var mode: Mode = Mode.RTS_COMMAND
var ship: Ship
var rts_commander: RTSCommander
var direct_pilot: DirectPilot

func setup(p_ship: Ship, p_rts: RTSCommander, p_direct: DirectPilot) -> void:
	ship = p_ship
	rts_commander = p_rts
	direct_pilot = p_direct
	_apply_mode()

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(ship):
		return
	if event.is_action_pressed("toggle_control_mode"):
		mode = Mode.DIRECT_PILOT if mode == Mode.RTS_COMMAND else Mode.RTS_COMMAND
		_apply_mode()

func _apply_mode() -> void:
	if not is_instance_valid(ship) or not is_instance_valid(rts_commander) or not is_instance_valid(direct_pilot):
		return
	var is_direct := mode == Mode.DIRECT_PILOT
	ship.control_mode = Ship.ControlMode.DIRECT if is_direct else Ship.ControlMode.ORDER_BASED
	rts_commander.set_process_unhandled_input(not is_direct)
	direct_pilot.set_physics_process(is_direct)
