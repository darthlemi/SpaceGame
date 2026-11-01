extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")

const STEP_DELTA := 1.0 / 60.0

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")

	var duration := 300.0  # 5 simulated minutes
	campaign_state.reset()

	var scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame

	var icons: Array[CampaignFleetIcon] = [scene.player_icon]
	icons.append_array(scene.enemy_icons)

	var spawn_positions: Dictionary = {}
	var max_distance: Dictionary = {}
	for icon in icons:
		spawn_positions[icon] = icon.global_position
		max_distance[icon] = 0.0

	var step_count := int(duration / STEP_DELTA)
	for step in step_count:
		for icon in icons:
			icon._physics_process(STEP_DELTA)
		for icon in icons:
			var d: float = icon.global_position.distance_to(spawn_positions[icon])
			if d > max_distance[icon]:
				max_distance[icon] = d

	for icon in icons:
		var label: String = "player" if icon == scene.player_icon else "enemy[%d] (%s)" % [scene.enemy_icons.find(icon), CampaignFleetIcon.BehaviorType.keys()[icon.behavior_type]]
		print("[sim %0.0fs] %s max distance from spawn: %.1f" % [duration, label, max_distance[icon]])

	scene.queue_free()
	await tree.process_frame

	return failures
