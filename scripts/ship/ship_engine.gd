class_name ShipEngine
extends Node

@export var max_speed: float = 200.0
@export var turn_rate: float = 3.0
@export var acceleration: float = 150.0

var velocity: Vector2 = Vector2.ZERO

func steer_toward(current_pos: Vector2, current_rotation: float, target_pos: Vector2, delta: float, slow_radius: float = -1.0) -> Dictionary:
	var to_target := target_pos - current_pos
	var distance := to_target.length()
	if distance < 1.0:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		return {"rotation": current_rotation, "velocity": velocity}
	var desired_angle := to_target.angle()
	var new_rotation := rotate_toward_angle(current_rotation, desired_angle, turn_rate * delta)
	var forward := Vector2.RIGHT.rotated(new_rotation)
	var effective_slow_radius := slow_radius if slow_radius >= 0.0 else stopping_distance()
	var desired_speed := max_speed
	if effective_slow_radius > 0.0 and distance < effective_slow_radius:
		desired_speed = max_speed * (distance / effective_slow_radius)
	velocity = velocity.move_toward(forward * desired_speed, acceleration * delta)
	return {"rotation": new_rotation, "velocity": velocity}

func stopping_distance() -> float:
	return (max_speed * max_speed) / (2.0 * acceleration) if acceleration > 0.0 else 0.0

static func rotate_toward_angle(current: float, target: float, max_delta: float) -> float:
	var diff := wrapf(target - current, -PI, PI)
	if abs(diff) <= max_delta:
		return target
	return current + sign(diff) * max_delta
