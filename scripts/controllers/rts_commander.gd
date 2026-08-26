class_name RTSCommander
extends Node

const CLICK_TARGET_RADIUS := 40.0

var ship: Ship
var enemy: Ship

func setup(p_ship: Ship, p_enemy: Ship) -> void:
	ship = p_ship
	enemy = p_enemy

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(ship):
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var world_pos: Vector2 = ship.get_global_mouse_position()
	if event.button_index == MOUSE_BUTTON_LEFT:
		if is_instance_valid(enemy) and enemy.global_position.distance_to(world_pos) < CLICK_TARGET_RADIUS:
			ship.execute_order(Order.attack_target(enemy))
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		ship.execute_order(Order.move_to(world_pos))
