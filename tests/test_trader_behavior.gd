extends RefCounted

const TraderBehavior = preload("res://scripts/campaign/behaviors/trader_behavior.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var home := Vector2(0, 0)
	var away := Vector2(200, 0)

	var still_to_base := TraderBehavior.next_route_state(TraderBehavior.RouteState.TO_BASE, Vector2(100, 0), home, away, 5.0)
	if still_to_base != TraderBehavior.RouteState.TO_BASE:
		failures.append("next_route_state: expected TO_BASE unchanged before arrival")

	var flipped_to_from := TraderBehavior.next_route_state(TraderBehavior.RouteState.TO_BASE, home, home, away, 5.0)
	if flipped_to_from != TraderBehavior.RouteState.FROM_BASE:
		failures.append("next_route_state: expected flip to FROM_BASE on arrival at home")

	if TraderBehavior.route_target(TraderBehavior.RouteState.TO_BASE, home, away) != home:
		failures.append("route_target: expected home_position for TO_BASE")
	if TraderBehavior.route_target(TraderBehavior.RouteState.FROM_BASE, home, away) != away:
		failures.append("route_target: expected away_point for FROM_BASE")

	if not TraderBehavior.should_flee(Vector2(0, 0), Vector2(50, 0), 100.0):
		failures.append("should_flee: expected true when threat within flee_range")
	if TraderBehavior.should_flee(Vector2(0, 0), Vector2(500, 0), 100.0):
		failures.append("should_flee: expected false when threat outside flee_range")

	var fled := TraderBehavior.flee_target(Vector2(0, 0), Vector2(100, 0), 50.0)
	if fled.distance_to(Vector2(0, 0)) < 49.0:
		failures.append("flee_target: expected to move roughly flee_distance away from threat, got %s" % fled)

	return failures
