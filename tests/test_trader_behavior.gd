extends RefCounted

const TraderBehavior = preload("res://scripts/campaign/behaviors/trader_behavior.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	if not TraderBehavior.should_flee(Vector2(0, 0), Vector2(50, 0), 100.0):
		failures.append("should_flee: expected true when threat within flee_range")
	if TraderBehavior.should_flee(Vector2(0, 0), Vector2(500, 0), 100.0):
		failures.append("should_flee: expected false when threat outside flee_range")

	var fled := TraderBehavior.flee_target(Vector2(0, 0), Vector2(100, 0), 50.0)
	if fled.distance_to(Vector2(0, 0)) < 49.0:
		failures.append("flee_target: expected to move roughly flee_distance away from threat, got %s" % fled)

	return failures
