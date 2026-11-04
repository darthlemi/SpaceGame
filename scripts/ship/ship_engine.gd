class_name ShipEngine
extends ShipComponent

# Thrusters off the nose are weaker: full speed forward, this fraction straight back.
const REVERSE_SPEED_FACTOR := 0.5

@export var max_speed: float = 200.0
@export var turn_rate: float = 3.0
@export var acceleration: float = 150.0

# Set by Ship from crew efficiency.
var crew_multiplier: float = 1.0
var velocity: Vector2 = Vector2.ZERO

func effective_acceleration() -> float:
	return acceleration * health_fraction()

func effective_max_speed() -> float:
	return max_speed * health_fraction() * crew_multiplier

# Keeps the nose on face_pos while thrusting toward station_pos in any direction, so a
# ship can back off or sidestep without turning its forward hardpoints away.
func hold_station(current_pos: Vector2, current_rotation: float, face_pos: Vector2, station_pos: Vector2, delta: float) -> Dictionary:
	var new_rotation := current_rotation
	var to_face := face_pos - current_pos
	if to_face.length() > 0.01:
		new_rotation = rotate_toward_angle(current_rotation, to_face.angle(), turn_rate * crew_multiplier * delta)
	var to_station := station_pos - current_pos
	var distance := to_station.length()
	var desired_velocity := Vector2.ZERO
	if distance >= 1.0:
		var direction := to_station / distance
		var alignment := (direction.dot(Vector2.RIGHT.rotated(new_rotation)) + 1.0) * 0.5
		var speed_cap := effective_max_speed() * lerpf(REVERSE_SPEED_FACTOR, 1.0, alignment)
		var slow_radius := stopping_distance()
		var speed := speed_cap if slow_radius <= 0.0 or distance >= slow_radius else speed_cap * distance / slow_radius
		desired_velocity = direction * speed
	velocity = velocity.move_toward(desired_velocity, effective_acceleration() * delta)
	return {"rotation": new_rotation, "velocity": velocity}

func steer_toward(current_pos: Vector2, current_rotation: float, target_pos: Vector2, delta: float, slow_radius: float = -1.0) -> Dictionary:
	var to_target := target_pos - current_pos
	var distance := to_target.length()
	var accel := effective_acceleration()
	if distance < 1.0:
		velocity = velocity.move_toward(Vector2.ZERO, accel * delta)
		return {"rotation": current_rotation, "velocity": velocity}
	var desired_angle := to_target.angle()
	var new_rotation := rotate_toward_angle(current_rotation, desired_angle, turn_rate * crew_multiplier * delta)
	var forward := Vector2.RIGHT.rotated(new_rotation)
	var top_speed := effective_max_speed()
	var effective_slow_radius := slow_radius if slow_radius >= 0.0 else stopping_distance()
	var desired_speed := top_speed
	if effective_slow_radius > 0.0 and distance < effective_slow_radius:
		desired_speed = top_speed * (distance / effective_slow_radius)
	velocity = velocity.move_toward(forward * desired_speed, accel * delta)
	return {"rotation": new_rotation, "velocity": velocity}

func stopping_distance() -> float:
	var accel := effective_acceleration()
	var top_speed := effective_max_speed()
	return (top_speed * top_speed) / (2.0 * accel) if accel > 0.0 else 0.0

static func rotate_toward_angle(current: float, target: float, max_delta: float) -> float:
	var diff := wrapf(target - current, -PI, PI)
	if abs(diff) <= max_delta:
		return target
	return current + sign(diff) * max_delta
