extends RefCounted

const CampaignFleetIconScene = preload("res://scenes/campaign/campaign_fleet_icon.tscn")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	# Patrol: should wander and stay within radius of its spawn point.
	var patrol_fleet := CampaignFleet.new()
	patrol_fleet.position = Vector2(500, 500)
	patrol_fleet.speed = 400.0
	var patrol_icon: Area2D = CampaignFleetIconScene.instantiate()
	patrol_icon.behavior_type = patrol_icon.BehaviorType.PATROL
	patrol_icon.wander_radius = 50.0
	tree.root.add_child(patrol_icon)
	patrol_icon.setup(patrol_fleet, Vector2.ZERO)

	for i in 30:
		await tree.physics_frame
	if patrol_icon.global_position.distance_to(Vector2(500, 500)) > 50.0:
		failures.append("patrol: expected to stay within wander_radius of spawn, got %s" % patrol_icon.global_position)
	if patrol_icon.global_position.distance_to(Vector2(500, 500)) < 1.0:
		failures.append("patrol: expected icon to actually wander, but it never left spawn")

	patrol_icon.queue_free()

	# Pirate: stronger than target, within detection range -> moves toward target.
	var pirate_fleet := CampaignFleet.new()
	pirate_fleet.position = Vector2(0, 0)
	pirate_fleet.speed = 400.0
	pirate_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0}]
	var weak_fleet := CampaignFleet.new()
	weak_fleet.ship_compositions = [{"max_hp": 10.0, "current_hp": 10.0, "max_shield": 0.0, "current_shield": 0.0}]

	var target_icon: Area2D = CampaignFleetIconScene.instantiate()
	target_icon.behavior_type = target_icon.BehaviorType.PLAYER
	tree.root.add_child(target_icon)
	target_icon.setup(weak_fleet, Vector2.ZERO)
	target_icon.global_position = Vector2(100, 0)

	var pirate_icon: Area2D = CampaignFleetIconScene.instantiate()
	pirate_icon.behavior_type = pirate_icon.BehaviorType.PIRATE
	pirate_icon.detection_range = 500.0
	tree.root.add_child(pirate_icon)
	pirate_icon.setup(pirate_fleet, Vector2.ZERO)
	pirate_icon.player_target = target_icon

	var start_distance: float = pirate_icon.global_position.distance_to(target_icon.global_position)
	for i in 10:
		await tree.physics_frame
	var end_distance: float = pirate_icon.global_position.distance_to(target_icon.global_position)
	if end_distance >= start_distance:
		failures.append("pirate: expected to close distance on a weaker target, start=%s end=%s" % [start_distance, end_distance])

	pirate_icon.queue_free()
	target_icon.queue_free()

	# Frozen: a patrol icon should not move at all while frozen, then
	# should resume wandering once unfrozen.
	var frozen_fleet := CampaignFleet.new()
	frozen_fleet.position = Vector2(300, 300)
	frozen_fleet.speed = 400.0
	var frozen_icon: Area2D = CampaignFleetIconScene.instantiate()
	frozen_icon.behavior_type = frozen_icon.BehaviorType.PATROL
	frozen_icon.wander_radius = 50.0
	frozen_icon.frozen = true
	tree.root.add_child(frozen_icon)
	frozen_icon.setup(frozen_fleet, Vector2.ZERO)

	var frozen_start: Vector2 = frozen_icon.global_position
	for i in 15:
		await tree.physics_frame
	if frozen_icon.global_position != frozen_start:
		failures.append("frozen: expected icon to hold position while frozen, moved from %s to %s" % [frozen_start, frozen_icon.global_position])

	frozen_icon.frozen = false
	for i in 30:
		await tree.physics_frame
	if frozen_icon.global_position == frozen_start:
		failures.append("frozen: expected icon to move again once unfrozen, still at %s" % frozen_icon.global_position)

	frozen_icon.queue_free()

	# Trader route retargeting + trader_arrived signal: an icon set up with
	# set_route_endpoints should route between those exact points (not its
	# spawn point) and emit trader_arrived(true) on reaching home, then
	# trader_arrived(false) on reaching the away point.
	var route_fleet := CampaignFleet.new()
	route_fleet.position = Vector2(500, 500)
	route_fleet.speed = 400.0
	var route_icon: Area2D = CampaignFleetIconScene.instantiate()
	route_icon.behavior_type = route_icon.BehaviorType.TRADER
	route_icon.arrival_radius = 10.0
	tree.root.add_child(route_icon)
	route_icon.setup(route_fleet, Vector2.ZERO)
	var home_pos := Vector2(0, 0)
	var away_pos := Vector2(100, 0)
	route_icon.set_route_endpoints(home_pos, away_pos)
	route_icon.global_position = home_pos

	var arrivals: Array = []
	route_icon.trader_arrived.connect(func(at_home: bool): arrivals.append(at_home))

	for i in 60:
		await tree.physics_frame
		if arrivals.size() >= 1:
			break
	if arrivals.size() < 1 or arrivals[0] != false:
		failures.append("trader_arrived: expected first arrival to be at the away point (false), got %s" % [arrivals])

	for i in 60:
		await tree.physics_frame
		if arrivals.size() >= 2:
			break
	if arrivals.size() < 2 or arrivals[1] != true:
		failures.append("trader_arrived: expected second arrival to be at home (true), got %s" % [arrivals])

	route_icon.queue_free()

	# set_route_endpoints(reset_state): re-wiring an in-progress route with the
	# SAME endpoints and reset_state=false (as CampaignScene._ready() does on
	# every return from CombatScene) must preserve route progress -- a hauler
	# mid-trip toward home should keep heading home, not get rewound. Passing
	# reset_state=true (the default, for a genuine initial/role-change config)
	# at the same mid-trip point DOES rewind it back toward the away point.
	var preserved_fleet := CampaignFleet.new()
	preserved_fleet.position = Vector2(100, 0)
	preserved_fleet.speed = 400.0
	var preserved_icon: Area2D = CampaignFleetIconScene.instantiate()
	preserved_icon.behavior_type = preserved_icon.BehaviorType.TRADER
	preserved_icon.arrival_radius = 10.0
	tree.root.add_child(preserved_icon)
	preserved_icon.setup(preserved_fleet, Vector2.ZERO)
	var preserved_home := Vector2(0, 0)
	var preserved_away := Vector2(100, 0)
	preserved_icon.set_route_endpoints(preserved_home, preserved_away)
	preserved_icon.global_position = preserved_away

	var preserved_arrivals: Array = []
	preserved_icon.trader_arrived.connect(func(at_home: bool): preserved_arrivals.append(at_home))
	await tree.physics_frame
	if preserved_arrivals.size() != 1 or preserved_arrivals[0] != false:
		failures.append("set_route_endpoints: test setup expected arrival at the away point first, got %s" % [preserved_arrivals])

	# Now mid-trip toward home -- snap to a midpoint, then re-wire with the
	# SAME endpoints and reset_state=false.
	preserved_icon.global_position = Vector2(50, 0)
	preserved_icon.set_route_endpoints(preserved_home, preserved_away, false)
	for i in 20:
		await tree.physics_frame
		if preserved_arrivals.size() >= 2:
			break
	if preserved_arrivals.size() < 2 or preserved_arrivals[1] != true:
		failures.append("set_route_endpoints: expected reset_state=false to preserve in-progress route state (continue home), got %s" % [preserved_arrivals])

	preserved_icon.queue_free()

	var rewound_fleet := CampaignFleet.new()
	rewound_fleet.position = Vector2(100, 0)
	rewound_fleet.speed = 400.0
	var rewound_icon: Area2D = CampaignFleetIconScene.instantiate()
	rewound_icon.behavior_type = rewound_icon.BehaviorType.TRADER
	rewound_icon.arrival_radius = 10.0
	tree.root.add_child(rewound_icon)
	rewound_icon.setup(rewound_fleet, Vector2.ZERO)
	var rewound_home := Vector2(0, 0)
	var rewound_away := Vector2(100, 0)
	rewound_icon.set_route_endpoints(rewound_home, rewound_away)
	rewound_icon.global_position = rewound_away

	var rewound_arrivals: Array = []
	rewound_icon.trader_arrived.connect(func(at_home: bool): rewound_arrivals.append(at_home))
	await tree.physics_frame
	if rewound_arrivals.size() != 1 or rewound_arrivals[0] != false:
		failures.append("set_route_endpoints: test setup expected arrival at the away point first, got %s" % [rewound_arrivals])

	# Mid-trip toward home, but this time re-wire with reset_state=true (the
	# default) -- route state must rewind, sending it back toward the away
	# point instead of continuing home.
	rewound_icon.global_position = Vector2(50, 0)
	rewound_icon.set_route_endpoints(rewound_home, rewound_away)
	for i in 20:
		await tree.physics_frame
		if rewound_arrivals.size() >= 2:
			break
	if rewound_arrivals.size() < 2 or rewound_arrivals[1] != false:
		failures.append("set_route_endpoints: expected reset_state=true to rewind route state (back to the away point), got %s" % [rewound_arrivals])

	rewound_icon.queue_free()

	return failures
