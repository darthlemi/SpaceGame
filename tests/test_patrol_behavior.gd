extends RefCounted

const PatrolBehavior = preload("res://scripts/campaign/behaviors/patrol_behavior.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var spawn := Vector2(100, 100)
	var target := Vector2(120, 100)
	var far_position := Vector2(50, 100)

	var unchanged := PatrolBehavior.next_wander_target(spawn, target, far_position, 50.0, 5.0)
	if unchanged != target:
		failures.append("next_wander_target: expected unchanged target when not arrived, got %s" % unchanged)

	var arrived_position := Vector2(120, 100)
	var new_target := PatrolBehavior.next_wander_target(spawn, target, arrived_position, 50.0, 5.0)
	if new_target.distance_to(spawn) > 50.0:
		failures.append("next_wander_target: expected new target within radius of spawn, got %s" % new_target)

	return failures
