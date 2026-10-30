class_name TraderBehavior
extends RefCounted

enum RouteState { TO_BASE, FROM_BASE }

static func next_route_state(state: RouteState, position: Vector2, home_position: Vector2, away_point: Vector2, arrival_radius: float) -> RouteState:
	var target := home_position if state == RouteState.TO_BASE else away_point
	if position.distance_to(target) > arrival_radius:
		return state
	return RouteState.FROM_BASE if state == RouteState.TO_BASE else RouteState.TO_BASE

static func route_target(state: RouteState, home_position: Vector2, away_point: Vector2) -> Vector2:
	return home_position if state == RouteState.TO_BASE else away_point

static func should_flee(position: Vector2, threat_position: Vector2, flee_range: float) -> bool:
	return position.distance_to(threat_position) <= flee_range

static func flee_target(position: Vector2, threat_position: Vector2, flee_distance: float) -> Vector2:
	return position + (position - threat_position).normalized() * flee_distance
