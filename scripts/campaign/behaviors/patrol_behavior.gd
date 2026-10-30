class_name PatrolBehavior
extends RefCounted

static func next_wander_target(spawn_point: Vector2, current_target: Vector2, position: Vector2, radius: float, arrival_radius: float) -> Vector2:
	if position.distance_to(current_target) > arrival_radius:
		return current_target
	var angle := randf_range(0.0, TAU)
	var distance := randf_range(0.0, radius)
	return spawn_point + Vector2(cos(angle), sin(angle)) * distance
