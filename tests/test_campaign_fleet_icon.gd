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
	patrol_icon.setup(patrol_fleet, patrol_fleet.position)

	for i in 30:
		await tree.physics_frame
	if patrol_icon.global_position.distance_to(Vector2(500, 500)) > 50.0:
		failures.append("patrol: expected to stay within wander_radius of spawn, got %s" % patrol_icon.global_position)
	if patrol_icon.global_position.distance_to(Vector2(500, 500)) < 1.0:
		failures.append("patrol: expected icon to actually wander, but it never left spawn")

	patrol_icon.queue_free()

	# Pirate: stronger than target, within detection range -> moves toward target.
	var pirate_fleet := CampaignFleet.new()
	pirate_fleet.position = Vector2(300, 300)
	pirate_fleet.speed = 400.0
	pirate_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0}]
	var weak_fleet := CampaignFleet.new()
	weak_fleet.position = Vector2(400, 300)
	weak_fleet.ship_compositions = [{"max_hp": 10.0, "current_hp": 10.0, "max_shield": 0.0, "current_shield": 0.0}]

	var target_icon: Area2D = CampaignFleetIconScene.instantiate()
	target_icon.behavior_type = target_icon.BehaviorType.PLAYER
	tree.root.add_child(target_icon)
	target_icon.setup(weak_fleet, weak_fleet.position)

	var pirate_icon: Area2D = CampaignFleetIconScene.instantiate()
	pirate_icon.behavior_type = pirate_icon.BehaviorType.PIRATE
	pirate_icon.detection_range = 500.0
	tree.root.add_child(pirate_icon)
	pirate_icon.setup(pirate_fleet, pirate_fleet.position)
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
	# should resume wandering once unfrozen. Also: a fleet frozen mid-travel
	# should stop emitting its engine trail, not leave it emitting forever.
	var frozen_fleet := CampaignFleet.new()
	frozen_fleet.position = Vector2(300, 300)
	frozen_fleet.speed = 400.0
	frozen_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0}]
	var frozen_icon: Area2D = CampaignFleetIconScene.instantiate()
	frozen_icon.behavior_type = frozen_icon.BehaviorType.PATROL
	frozen_icon.wander_radius = 50.0
	tree.root.add_child(frozen_icon)
	frozen_icon.setup(frozen_fleet, frozen_fleet.position)

	# Let it wander un-frozen first so the engine trail actually turns on,
	# then freeze it mid-travel (the normal case when entering combat).
	for i in 15:
		await tree.physics_frame
	var frozen_trail: CPUParticles2D = frozen_icon.get_children().filter(func(c): return c is CPUParticles2D)[0]
	if not frozen_trail.emitting:
		failures.append("frozen: expected EngineTrail to be emitting while moving, before freeze")

	frozen_icon.frozen = true
	await tree.physics_frame
	if frozen_trail.emitting:
		failures.append("frozen: expected EngineTrail not emitting while frozen")

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

	# Trader destination: heads for dest_position, emits trader_arrived_at once with the fleet's
	# dest_station_id, then idles until the scene hands it a new destination.
	var route_fleet := CampaignFleet.new()
	route_fleet.position = Vector2(500, 300)
	route_fleet.speed = 400.0
	route_fleet.dest_station_id = "away_station"
	var route_icon: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	route_icon.behavior_type = CampaignFleetIcon.BehaviorType.TRADER
	tree.root.add_child(route_icon)
	route_icon.setup(route_fleet, route_fleet.position)
	route_icon.dest_position = Vector2(600, 300)
	route_icon.has_destination = true
	var arrivals: Array[String] = []
	route_icon.trader_arrived_at.connect(func(station_id: String): arrivals.append(station_id))
	for i in 60:
		await tree.physics_frame
		if not arrivals.is_empty():
			break
	if arrivals.size() != 1 or arrivals[0] != "away_station":
		failures.append("trader_arrived_at: expected one arrival at 'away_station', got %s" % [arrivals])
	var idle_at: Vector2 = route_icon.position
	for i in 10:
		await tree.physics_frame
	if arrivals.size() != 1 or route_icon.position != idle_at:
		failures.append("trader_arrived_at: expected the trader to idle after arriving, arrivals=%s moved %s -> %s" % [arrivals, idle_at, route_icon.position])
	route_icon.queue_free()

	# Layers: movement is local to the parent layer, while detection uses global positions, so a
	# pirate in another (offset) layer never chases a target at the same local position.
	var layer_a := Node2D.new()
	var layer_b := Node2D.new()
	layer_b.position = Vector2(5000, 0)
	tree.root.add_child(layer_a)
	tree.root.add_child(layer_b)
	var prey_fleet := CampaignFleet.new()
	prey_fleet.position = Vector2(400, 300)
	prey_fleet.ship_compositions = [{"max_hp": 10.0, "current_hp": 10.0, "max_shield": 0.0, "current_shield": 0.0}]
	var prey_icon: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	prey_icon.behavior_type = CampaignFleetIcon.BehaviorType.PLAYER
	layer_a.add_child(prey_icon)
	prey_icon.setup(prey_fleet, prey_fleet.position)
	var far_pirate_fleet := CampaignFleet.new()
	far_pirate_fleet.position = Vector2(500, 300)
	far_pirate_fleet.speed = 400.0
	far_pirate_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0}]
	var far_pirate: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	far_pirate.behavior_type = CampaignFleetIcon.BehaviorType.PIRATE
	far_pirate.detection_range = 500.0
	far_pirate.wander_radius = 0.0
	layer_b.add_child(far_pirate)
	far_pirate.setup(far_pirate_fleet, far_pirate_fleet.position)
	far_pirate.player_target = prey_icon
	for i in 10:
		await tree.physics_frame
	if far_pirate.position.distance_to(Vector2(500, 300)) > 1.0:
		failures.append("layers: expected a pirate in another layer to ignore the target, moved to %s" % far_pirate.position)
	if far_pirate.global_position != layer_b.position + far_pirate.position:
		failures.append("layers: expected the icon to sit at its layer offset plus its local position")
	if far_pirate_fleet.position != far_pirate.position:
		failures.append("layers: expected fleet.position to be the local position, got %s" % far_pirate_fleet.position)

	# The same pirate moved into the target's layer does chase it.
	far_pirate.reparent(layer_a)
	far_pirate.position = Vector2(500, 300)
	for i in 10:
		await tree.physics_frame
	if far_pirate.position.distance_to(prey_icon.position) >= 100.0:
		failures.append("layers: expected a pirate in the same layer to close on the target, at %s" % far_pirate.position)

	# Trails only emit while the icon's layer is visible.
	layer_a.visible = false
	prey_icon.set_move_target(Vector2(900, 300))
	for i in 5:
		await tree.physics_frame
	for child in prey_icon.get_children():
		if child is CPUParticles2D and child.emitting:
			failures.append("layers: expected no trail emitting while the layer is hidden")
			break
	layer_a.queue_free()
	layer_b.queue_free()

	# Ship dots: setup() should create one Sprite2D dot per ship
	# composition, each within CLUMP_RADIUS of the icon's local origin.
	var dots_fleet := CampaignFleet.new()
	dots_fleet.position = Vector2(200, 200)
	dots_fleet.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
	]
	var dots_icon: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	tree.root.add_child(dots_icon)
	dots_icon.setup(dots_fleet, dots_fleet.position)

	var dot_nodes: Array = dots_icon.get_children().filter(func(c): return c is Sprite2D)
	if dot_nodes.size() != 3:
		failures.append("ship dots: expected 3 dots for a 3-ship fleet, got %d" % dot_nodes.size())
	for dot in dot_nodes:
		if dot.position.length() > CampaignFleetIcon.CLUMP_RADIUS:
			failures.append("ship dots: expected dot offset within CLUMP_RADIUS, got %s" % dot.position)
		if dot.texture == null:
			failures.append("ship dots: expected dot to have a ship texture assigned")

	# Per-ship trails: one CPUParticles2D per ship dot, not one shared trail
	# for the whole fleet.
	var trail_nodes: Array = dots_icon.get_children().filter(func(c): return c is CPUParticles2D)
	if trail_nodes.size() != 3:
		failures.append("ship trails: expected one trail per ship dot (3), got %d" % trail_nodes.size())

	# Live update: shrinking ship_compositions and ticking physics should
	# remove dots (and their paired trails) to match, without moving the
	# surviving dots' positions.
	var surviving_positions: Array = []
	for dot in dot_nodes.slice(0, 2):
		surviving_positions.append(dot.position)
	dots_fleet.ship_compositions = dots_fleet.ship_compositions.slice(0, 2)
	await tree.physics_frame
	var dot_nodes_after: Array = dots_icon.get_children().filter(func(c): return c is Sprite2D)
	if dot_nodes_after.size() != 2:
		failures.append("ship dots: expected dot count to drop to 2 after composition shrank, got %d" % dot_nodes_after.size())
	for i in dot_nodes_after.size():
		if dot_nodes_after[i].position != surviving_positions[i]:
			failures.append("ship dots: expected surviving dot %d to keep its position %s, got %s" % [i, surviving_positions[i], dot_nodes_after[i].position])
	var trail_nodes_after: Array = dots_icon.get_children().filter(func(c): return c is CPUParticles2D)
	if trail_nodes_after.size() != 2:
		failures.append("ship trails: expected trail count to drop to 2 after composition shrank, got %d" % trail_nodes_after.size())

	dots_icon.queue_free()

	# Heading rotation: a moving fleet's ship sprites should rotate to face
	# the direction of travel.
	var heading_fleet := CampaignFleet.new()
	heading_fleet.position = Vector2(200, 200)
	heading_fleet.speed = 400.0
	heading_fleet.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
	]
	var heading_icon: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	heading_icon.behavior_type = heading_icon.BehaviorType.PLAYER
	tree.root.add_child(heading_icon)
	heading_icon.setup(heading_fleet, heading_fleet.position)
	heading_icon.set_move_target(Vector2(200, 300))

	for i in 10:
		await tree.physics_frame
	var heading_sprite: Sprite2D = heading_icon.get_children().filter(func(c): return c is Sprite2D)[0]
	var expected_angle: float = Vector2(0, 100).angle()
	if not is_equal_approx(wrapf(heading_sprite.rotation, 0, TAU), wrapf(expected_angle, 0, TAU)):
		failures.append("ship dots: expected sprite rotation to face direction of travel (%s), got %s" % [expected_angle, heading_sprite.rotation])

	var engine_trail: CPUParticles2D = heading_icon.get_children().filter(func(c): return c is CPUParticles2D)[0]
	if not engine_trail.emitting:
		failures.append("ship dots: expected EngineTrail emitting while fleet is moving")
	if not is_equal_approx(wrapf(engine_trail.rotation, 0, TAU), wrapf(expected_angle, 0, TAU)):
		failures.append("ship dots: expected EngineTrail rotation to match heading (%s), got %s" % [expected_angle, engine_trail.rotation])

	heading_icon.queue_free()

	# System bounds: a player's click target far outside the system is clamped to it.
	var bounds_player_fleet := CampaignFleet.new()
	bounds_player_fleet.position = Vector2(1100, 600)
	bounds_player_fleet.speed = 1000.0
	var bounds_player_icon: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	bounds_player_icon.behavior_type = CampaignFleetIcon.BehaviorType.PLAYER
	tree.root.add_child(bounds_player_icon)
	bounds_player_icon.setup(bounds_player_fleet, bounds_player_fleet.position)
	bounds_player_icon.set_move_target(Vector2(9999, 9999))

	for i in 20:
		await tree.physics_frame
	if bounds_player_icon.position != JumpRules.clamp_to_system(bounds_player_icon.position):
		failures.append("system bounds: expected player target clamped to the system, got position %s" % bounds_player_icon.position)

	bounds_player_icon.queue_free()

	# System bounds: a trader fleeing past SYSTEM_MAX.x is clamped too. The raw flee target is
	# (1100,350) + (1,0) * 300 = (1400,350), past SYSTEM_MAX.x (1112).
	var bounds_threat_fleet := CampaignFleet.new()
	bounds_threat_fleet.position = Vector2(1000, 350)
	var bounds_threat_icon: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	bounds_threat_icon.behavior_type = CampaignFleetIcon.BehaviorType.PLAYER
	tree.root.add_child(bounds_threat_icon)
	bounds_threat_icon.setup(bounds_threat_fleet, bounds_threat_fleet.position)

	var bounds_trader_fleet := CampaignFleet.new()
	bounds_trader_fleet.position = Vector2(1100, 350)
	bounds_trader_fleet.speed = 1000.0
	var bounds_trader_icon: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	bounds_trader_icon.behavior_type = CampaignFleetIcon.BehaviorType.TRADER
	tree.root.add_child(bounds_trader_icon)
	bounds_trader_icon.setup(bounds_trader_fleet, bounds_trader_fleet.position)
	bounds_trader_icon.player_target = bounds_threat_icon

	for i in 20:
		await tree.physics_frame
	if bounds_trader_icon.position.x > JumpRules.SYSTEM_MAX.x:
		failures.append("system bounds: expected fleeing trader's target clamped to SYSTEM_MAX.x, got position %s" % bounds_trader_icon.position)

	bounds_trader_icon.queue_free()
	bounds_threat_icon.queue_free()

	# Faction circle: radius should grow with ship count (sqrt scaling), and
	# the color map should return a distinct color per faction, falling back
	# to the neutral color for an unmapped value.
	var small_fleet := CampaignFleet.new()
	small_fleet.faction = CampaignFleet.Faction.PLAYER
	small_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0}]
	var small_icon: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	tree.root.add_child(small_icon)
	small_icon.setup(small_fleet, small_fleet.position)

	var large_fleet := CampaignFleet.new()
	large_fleet.faction = CampaignFleet.Faction.PIRATE
	large_fleet.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0},
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0},
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0},
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0},
	]
	var large_icon: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	tree.root.add_child(large_icon)
	large_icon.setup(large_fleet, large_fleet.position)

	if large_icon._faction_circle_radius <= small_icon._faction_circle_radius:
		failures.append("faction circle: expected a 4-ship fleet's circle radius (%s) to be larger than a 1-ship fleet's (%s)" % [large_icon._faction_circle_radius, small_icon._faction_circle_radius])

	if CampaignFleetIcon.FACTION_COLORS[CampaignFleet.Faction.PLAYER] != Color(0.2, 0.9, 0.2, 1.0):
		failures.append("faction circle: expected PLAYER color to be green, got %s" % CampaignFleetIcon.FACTION_COLORS[CampaignFleet.Faction.PLAYER])
	if CampaignFleetIcon.FACTION_COLORS[CampaignFleet.Faction.PIRATE] != Color(0.9, 0.2, 0.2, 1.0):
		failures.append("faction circle: expected PIRATE color to be red, got %s" % CampaignFleetIcon.FACTION_COLORS[CampaignFleet.Faction.PIRATE])

	small_icon.queue_free()
	large_icon.queue_free()

	# Fuel: the player burns fuel while moving and crawls once empty; NPC
	# fleets carry no fuel and must keep full speed.
	var fueled_fleet := CampaignFleet.new()
	fueled_fleet.speed = 100.0
	fueled_fleet.ship_compositions = [ShipType.new_composition(ShipType.Kind.CAPITAL)]
	fueled_fleet.cargo = {Commodity.Type.FUEL: 50.0}
	var empty_fleet := CampaignFleet.new()
	empty_fleet.speed = 100.0
	empty_fleet.ship_compositions = [ShipType.new_composition(ShipType.Kind.CAPITAL)]
	var npc_fleet := CampaignFleet.new()
	npc_fleet.speed = 100.0
	npc_fleet.ship_compositions = [ShipType.new_composition(ShipType.Kind.CAPITAL)]

	var fuel_start := Vector2(100, 300)
	# Far-off target so no icon arrives (and stops) during the window.
	var fuel_target := Vector2(1100, 300)
	var fuel_icons: Array[CampaignFleetIcon] = []
	for fuel_case in [[fueled_fleet, CampaignFleetIcon.BehaviorType.PLAYER], [empty_fleet, CampaignFleetIcon.BehaviorType.PLAYER], [npc_fleet, CampaignFleetIcon.BehaviorType.TRADER]]:
		var fuel_icon: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
		fuel_icon.behavior_type = fuel_case[1]
		tree.root.add_child(fuel_icon)
		fuel_case[0].position = fuel_start
		fuel_icon.setup(fuel_case[0], fuel_start)
		fuel_icon.dest_position = fuel_target
		fuel_icon.has_destination = true
		fuel_icon.set_move_target(fuel_target)
		fuel_icons.append(fuel_icon)
	for i in 10:
		await tree.physics_frame

	var fueled_moved: float = fuel_icons[0].position.distance_to(fuel_start)
	var empty_moved: float = fuel_icons[1].position.distance_to(fuel_start)
	var npc_moved: float = fuel_icons[2].position.distance_to(fuel_start)
	if fueled_fleet.fuel_amount() >= 50.0:
		failures.append("fuel: expected the moving player fleet to burn fuel, still at %s" % fueled_fleet.fuel_amount())
	if not is_equal_approx(50.0 - fueled_fleet.fuel_amount(), fueled_moved * fueled_fleet.fuel_burn_per_distance()):
		failures.append("fuel: expected burn proportional to distance %s, burned %s" % [fueled_moved, 50.0 - fueled_fleet.fuel_amount()])
	if fueled_moved <= 0.0 or empty_moved <= 0.0:
		failures.append("fuel: expected both player fleets to move (fueled %s, empty %s)" % [fueled_moved, empty_moved])
	elif not is_equal_approx(empty_moved / fueled_moved, CampaignFleet.EMPTY_FUEL_SPEED_FACTOR):
		failures.append("fuel: expected empty fleet at %s of full speed, got %s" % [CampaignFleet.EMPTY_FUEL_SPEED_FACTOR, empty_moved / fueled_moved])
	if not is_equal_approx(npc_moved, fueled_moved):
		failures.append("fuel: expected fuel-less NPC fleet at full speed (%s), moved %s" % [fueled_moved, npc_moved])
	if npc_fleet.cargo.has(Commodity.Type.FUEL):
		failures.append("fuel: expected NPC fleet cargo untouched by fuel burn")

	for fuel_icon in fuel_icons:
		fuel_icon.queue_free()

	return failures
