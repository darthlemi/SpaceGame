class_name Projectile
extends Area2D

@export var speed: float = 500.0
var target: Node2D
var damage: float = 0.0

func setup(p_target: Node2D, p_damage: float) -> void:
	target = p_target
	damage = p_damage

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		queue_free()
		return
	var direction := (target.global_position - global_position).normalized()
	global_position += direction * speed * delta
	if global_position.distance_to(target.global_position) < 10.0:
		_hit()

func _hit() -> void:
	if is_instance_valid(target) and target.has_method("receive_damage"):
		target.receive_damage(damage)
	queue_free()
