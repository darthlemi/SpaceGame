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
	ship_engine._ready()  # seed current_hp = max_hp now that ShipEngine extends ShipComponent
	var steer := ship_engine.steer_toward(Vector2.ZERO, 0.0, Vector2(100, 0), 1.0)
	var vel: Vector2 = steer["velocity"]
	if vel.length() < 50.0:
		failures.append("steer_toward: expected ship to accelerate toward target, velocity length was %s" % vel.length())

	ship_engine.free()

	var damaged_engine := ShipEngine.new()
	damaged_engine.max_speed = 200.0
	damaged_engine.acceleration = 100.0
	damaged_engine.max_hp = 20.0
	damaged_engine._ready()
	damaged_engine.apply_damage(10.0)  # 50% health

	if not is_equal_approx(damaged_engine.effective_acceleration(), 50.0):
		failures.append("effective_acceleration: expected 50.0 at half health, got %s" % damaged_engine.effective_acceleration())
	if not is_equal_approx(damaged_engine.effective_max_speed(), 100.0):
		failures.append("effective_max_speed: expected 100.0 at half health, got %s" % damaged_engine.effective_max_speed())

	damaged_engine.apply_damage(1000.0)
	if not is_equal_approx(damaged_engine.effective_acceleration(), 0.0):
		failures.append("effective_acceleration: expected 0.0 once engine is destroyed, got %s" % damaged_engine.effective_acceleration())

	var dead_steer := damaged_engine.steer_toward(Vector2.ZERO, 0.0, Vector2(100, 0), 1.0)
	var dead_vel: Vector2 = dead_steer["velocity"]
	if dead_vel.length() > 0.01:
		failures.append("steer_toward: expected a destroyed engine to produce no new acceleration, velocity length was %s" % dead_vel.length())

	damaged_engine.free()
	return failures
