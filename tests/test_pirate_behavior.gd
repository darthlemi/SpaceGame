extends RefCounted

const PirateBehavior = preload("res://scripts/campaign/behaviors/pirate_behavior.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	if not PirateBehavior.should_intercept(150.0, 100.0):
		failures.append("should_intercept: expected true when own_strength > target_strength")
	if PirateBehavior.should_intercept(80.0, 100.0):
		failures.append("should_intercept: expected false when own_strength <= target_strength")

	if not PirateBehavior.in_detection_range(Vector2(0, 0), Vector2(50, 0), 100.0):
		failures.append("in_detection_range: expected true within range")
	if PirateBehavior.in_detection_range(Vector2(0, 0), Vector2(500, 0), 100.0):
		failures.append("in_detection_range: expected false outside range")

	return failures
