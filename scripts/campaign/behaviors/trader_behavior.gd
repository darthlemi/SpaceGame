class_name TraderBehavior
extends RefCounted

static func should_flee(position: Vector2, threat_position: Vector2, flee_range: float) -> bool:
	return position.distance_to(threat_position) <= flee_range

static func flee_target(position: Vector2, threat_position: Vector2, flee_distance: float) -> Vector2:
	return position + (position - threat_position).normalized() * flee_distance
