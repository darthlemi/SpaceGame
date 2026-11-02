class_name Projectile
extends Area2D

const HIT_RADIUS := 10.0
const DEFAULT_MAX_TRAVEL := 450.0

@export var speed: float = 500.0
var target: Node2D
var damage: float = 0.0
var travel_direction: Vector2 = Vector2.RIGHT
var max_travel: float = DEFAULT_MAX_TRAVEL
var _distance_traveled: float = 0.0

func setup(p_target: Node2D, p_damage: float, p_weapon_range: float = 0.0) -> void:
	target = p_target
	damage = p_damage
	if is_instance_valid(target):
		travel_direction = (target.global_position - global_position).normalized()
	rotation = travel_direction.angle()
	if p_weapon_range > 0.0:
		max_travel = p_weapon_range * 1.5

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		queue_free()
		return
	var step := travel_direction * speed * delta
	global_position += step
	_distance_traveled += step.length()
	var effective_hit_radius: float = target.get_hit_radius() if target.has_method("get_hit_radius") else HIT_RADIUS
	if global_position.distance_to(target.global_position) < effective_hit_radius:
		_hit()
	elif _distance_traveled >= max_travel:
		queue_free()

func _hit() -> void:
	if is_instance_valid(target) and target.has_method("receive_damage"):
		target.receive_damage(damage, global_position)
	queue_free()
