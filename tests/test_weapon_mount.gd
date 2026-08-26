extends RefCounted

const WeaponMount = preload("res://scripts/weapons/weapon_mount.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var weapon := Weapon.new()
	weapon.weapon_name = "Kinetic Cannon"
	weapon.damage = 10.0
	weapon.fire_rate = 2.0
	weapon.range = 300.0

	var mount := WeaponMount.new()
	mount.weapon = weapon

	if not mount.can_fire():
		failures.append("can_fire: expected true initially, got false")

	# Target beyond weapon range: try_fire should return false and not fire.
	var far_target := Node2D.new()
	far_target.global_position = Vector2(500.0, 0.0)
	mount.global_position = Vector2.ZERO
	var fired_far := mount.try_fire(far_target)
	if fired_far:
		failures.append("try_fire: expected false for target beyond range, got true")
	if mount.cooldown_remaining != 0.0:
		failures.append("try_fire: expected no cooldown to be set when out of range, got %s" % mount.cooldown_remaining)
	if not mount.can_fire():
		failures.append("can_fire: expected true after failed out-of-range fire attempt")

	# Cooldown bookkeeping: simulate cooldown_remaining being set and ticking down,
	# without invoking _spawn_projectile (which requires a live SceneTree).
	mount.cooldown_remaining = 1.0 / weapon.fire_rate
	if mount.can_fire():
		failures.append("can_fire: expected false immediately after cooldown is set")
	if not is_equal_approx(mount.cooldown_remaining, 0.5):
		failures.append("cooldown_remaining: expected 0.5 for fire_rate 2.0, got %s" % mount.cooldown_remaining)

	mount._physics_process(0.5)
	if mount.cooldown_remaining > 0.0:
		failures.append("_physics_process: expected cooldown to reach 0 after ticking 0.5s, got %s" % mount.cooldown_remaining)
	if not mount.can_fire():
		failures.append("can_fire: expected true after cooldown fully elapsed")

	far_target.free()
	mount.free()
	return failures
