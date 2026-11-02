extends RefCounted

const Projectile = preload("res://scripts/weapons/projectile.gd")

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
	return failures
