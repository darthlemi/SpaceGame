extends RefCounted

const Projectile = preload("res://scripts/weapons/projectile.gd")
const Weapon = preload("res://scripts/weapons/weapon.gd")

class TrackerTarget:
	extends Node2D
	var received_weapon: Weapon = null
	var received_weapon_position: Vector2 = Vector2.ZERO
	var received_plain := false
	func receive_weapon_damage(weapon, impact_position: Vector2 = Vector2.INF) -> void:
		received_weapon = weapon
		received_weapon_position = impact_position
	func receive_damage(_amount: float, _impact_position: Vector2 = Vector2.ZERO) -> void:
		received_plain = true

class RecordingTarget:
	extends Node2D
	var received_amount: float = -1.0
	var received_position: Vector2 = Vector2.ZERO
	func receive_damage(amount: float, impact_position: Vector2 = Vector2.ZERO) -> void:
		received_amount = amount
		received_position = impact_position

static func run() -> Array[String]:
	var failures: Array[String] = []

	var projectile := Projectile.new()
	var target := Node2D.new()
	target.global_position = Vector2(0.0, 100.0)
	projectile.global_position = Vector2.ZERO
	projectile.setup(target, 10.0)

	var expected_angle: float = Vector2(0.0, 100.0).angle()
	if not is_equal_approx(projectile.rotation, expected_angle):
		failures.append("setup: expected rotation to face travel_direction (%s), got %s" % [expected_angle, projectile.rotation])

	target.free()
	projectile.free()

	var hit_projectile := Projectile.new()
	var recording_target := RecordingTarget.new()
	recording_target.global_position = Vector2(5.0, 0.0)
	hit_projectile.global_position = Vector2(0.0, 0.0)
	hit_projectile.setup(recording_target, 25.0)
	hit_projectile._hit()

	if not is_equal_approx(recording_target.received_amount, 25.0):
		failures.append("_hit: expected receive_damage called with the projectile's damage, got %s" % recording_target.received_amount)
	if not recording_target.received_position.is_equal_approx(Vector2(0.0, 0.0)):
		failures.append("_hit: expected receive_damage called with the projectile's own global_position as impact_position, got %s" % recording_target.received_position)

	recording_target.free()

	# weapon-aware hit routing: when a Weapon is attached, _hit() should call
	# receive_weapon_damage(weapon, global_position) instead of plain receive_damage.
	var tracker_target := TrackerTarget.new()
	var weapon := Weapon.new()
	weapon.damage = 12.0
	var weapon_projectile := Projectile.new()
	weapon_projectile.global_position = Vector2(3.0, 4.0)
	weapon_projectile.setup(tracker_target, weapon.damage, 0.0, weapon)
	weapon_projectile._hit()
	if tracker_target.received_weapon != weapon:
		failures.append("_hit: expected receive_weapon_damage(weapon, ...) to be called when a weapon is attached")
	if not tracker_target.received_weapon_position.is_equal_approx(Vector2(3.0, 4.0)):
		failures.append("_hit: expected receive_weapon_damage's impact_position to be the projectile's global_position, got %s" % tracker_target.received_weapon_position)
	if tracker_target.received_plain:
		failures.append("_hit: expected plain receive_damage NOT to be called when a weapon is attached")

	tracker_target.free()
	return failures
