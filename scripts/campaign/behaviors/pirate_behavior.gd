class_name PirateBehavior
extends RefCounted

static func should_intercept(own_strength: float, target_strength: float) -> bool:
	return own_strength > target_strength

static func in_detection_range(position: Vector2, target_position: Vector2, detection_range: float) -> bool:
	return position.distance_to(target_position) <= detection_range
