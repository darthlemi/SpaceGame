class_name WeaponMount
extends ShipComponent

const MuzzleFlashScene = preload("res://scenes/vfx/muzzle_flash.tscn")

@export var weapon: Weapon
var cooldown_remaining: float = 0.0
# Set by Ship from crew efficiency.
var fire_rate_multiplier: float = 1.0

func _physics_process(delta: float) -> void:
	if cooldown_remaining > 0.0:
		cooldown_remaining -= delta

func can_fire() -> bool:
	return weapon != null and cooldown_remaining <= 0.0 and not is_destroyed()

# Range is to the target's hull edge, so big hulls are hittable from their standoff.
# Range and arc only; cooldown and damage are can_fire's job.
func can_engage(target: Node2D) -> bool:
	if weapon == null or target == null or not is_instance_valid(target):
		return false
	if CombatTactics.edge_distance(global_position, target) > weapon.weapon_range:
		return false
	return _within_arc(target)

func nearest_engageable(candidates: Array) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for c in candidates:
		if c is Node2D and can_engage(c):
			var d := CombatTactics.edge_distance(global_position, c)
			if d < nearest_dist:
				nearest_dist = d
				nearest = c
	return nearest

func try_fire(target: Node2D) -> bool:
	if not can_fire() or not can_engage(target):
		return false
	_spawn_projectile(target)
	cooldown_remaining = 1.0 / (weapon.fire_rate * fire_rate_multiplier)
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
