class_name WeaponMount
extends ShipComponent

const MuzzleFlashScene = preload("res://scenes/vfx/muzzle_flash.tscn")

@export var weapon: Weapon
var cooldown_remaining: float = 0.0

func _physics_process(delta: float) -> void:
	if cooldown_remaining > 0.0:
		cooldown_remaining -= delta

func can_fire() -> bool:
	return weapon != null and cooldown_remaining <= 0.0 and not is_destroyed()

func try_fire(target: Node2D) -> bool:
	if not can_fire() or target == null or not is_instance_valid(target):
		return false
	if global_position.distance_to(target.global_position) > weapon.weapon_range:
		return false
	if not _within_arc(target):
		return false
	_spawn_projectile(target)
	cooldown_remaining = 1.0 / weapon.fire_rate
	return true

func _within_arc(target: Node2D) -> bool:
	if weapon.fire_arc_degrees >= 360.0:
		return true
	var to_target_angle := (target.global_position - global_position).angle()
	var diff := wrapf(to_target_angle - global_rotation, -PI, PI)
	return abs(diff) <= deg_to_rad(weapon.fire_arc_degrees) * 0.5

func _spawn_projectile(target: Node2D) -> void:
	if weapon.projectile_scene == null:
		return
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	for i in range(weapon.submissile_count):
		var projectile: Node2D = weapon.projectile_scene.instantiate()
		host.add_child(projectile)
		projectile.global_position = global_position
		if weapon.projectile_speed > 0.0:
			projectile.speed = weapon.projectile_speed
		projectile.setup(target, weapon.damage, weapon.weapon_range, weapon)
	var muzzle_flash: Node2D = MuzzleFlashScene.instantiate()
	host.add_child(muzzle_flash)
	muzzle_flash.global_position = global_position
	muzzle_flash.rotation = (target.global_position - global_position).angle()
