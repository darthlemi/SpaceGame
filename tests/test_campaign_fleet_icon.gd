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

	return failures
