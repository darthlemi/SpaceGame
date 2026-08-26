class_name ShipEngine
extends Node

@export var max_speed: float = 200.0
@export var turn_rate: float = 3.0
@export var acceleration: float = 150.0

var velocity: Vector2 = Vector2.ZERO

func steer_toward(current_pos: Vector2, current_rotation: float, target_pos: Vector2, delta: float) -> Dictionary:
	var to_target := target_pos - current_pos
	if to_target.length() < 1.0:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		return {"rotation": current_rotation, "velocity": velocity}
	var desired_angle := to_target.angle()
	var new_rotation := rotate_toward_angle(current_rotation, desired_angle, turn_rate * delta)
	var forward := Vector2.RIGHT.rotated(new_rotation)
	velocity = velocity.move_toward(forward * max_speed, acceleration * delta)
	return {"rotation": new_rotation, "velocity": velocity}

static func rotate_toward_angle(current: float, target: float, max_delta: float) -> float:
	var diff := wrapf(target - current, -PI, PI)
	if abs(diff) <= max_delta:
		return target
	return current + sign(diff) * max_delta
