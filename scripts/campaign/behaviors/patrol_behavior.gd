class_name PatrolBehavior
extends RefCounted

static func next_wander_target(spawn_point: Vector2, current_target: Vector2, position: Vector2, radius: float, arrival_radius: float) -> Vector2:
	if position.distance_to(current_target) > arrival_radius:
		return current_target
	return spawn_point + Vector2(randf_range(-radius, radius), randf_range(-radius, radius))
