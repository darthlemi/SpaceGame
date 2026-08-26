extends RefCounted

const ShipEngine = preload("res://scripts/ship/ship_engine.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var result := ShipEngine.rotate_toward_angle(0.0, PI / 2.0, 0.1)
	if not is_equal_approx(result, 0.1):
		failures.append("rotate_toward_angle: expected small step of 0.1, got %s" % result)

	result = ShipEngine.rotate_toward_angle(0.0, 0.05, 0.1)
	if not is_equal_approx(result, 0.05):
		failures.append("rotate_toward_angle: expected snap to target 0.05, got %s" % result)

	var ship_engine := ShipEngine.new()
	ship_engine.max_speed = 100.0
	ship_engine.acceleration = 1000.0
	ship_engine.turn_rate = 10.0
	var steer := ship_engine.steer_toward(Vector2.ZERO, 0.0, Vector2(100, 0), 1.0)
	var vel: Vector2 = steer["velocity"]
	if vel.length() < 50.0:
		failures.append("steer_toward: expected ship to accelerate toward target, velocity length was %s" % vel.length())

	ship_engine.free()
	return failures
