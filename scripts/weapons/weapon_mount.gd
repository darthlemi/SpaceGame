class_name WeaponMount
extends Node2D

@export var weapon: Weapon
var cooldown_remaining: float = 0.0

func _physics_process(delta: float) -> void:
	if cooldown_remaining > 0.0:
		cooldown_remaining -= delta

func can_fire() -> bool:
	return weapon != null and cooldown_remaining <= 0.0

func try_fire(target: Node2D) -> bool:
	if not can_fire() or target == null or not is_instance_valid(target):
		return false
	if global_position.distance_to(target.global_position) > weapon.weapon_range:
		return false
	_spawn_projectile(target)
	cooldown_remaining = 1.0 / weapon.fire_rate
	return true

func _spawn_projectile(target: Node2D) -> void:
	if weapon.projectile_scene == null:
		return
	var projectile: Node2D = weapon.projectile_scene.instantiate()
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	host.add_child(projectile)
	projectile.global_position = global_position
	projectile.setup(target, weapon.damage, weapon.weapon_range)
