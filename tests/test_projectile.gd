extends RefCounted

const Projectile = preload("res://scripts/weapons/projectile.gd")

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
	return failures
