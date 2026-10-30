extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame

	if scene.player_icon == null:
		failures.append("expected player_icon spawned on first run (bootstrap)")
	if scene.enemy_icons.is_empty():
		failures.append("expected at least one enemy_icon spawned on first run (bootstrap)")
	if campaign_state.player_fleet == null:
		failures.append("expected CampaignState.player_fleet populated by bootstrap")

	# Simulate the player clicking to engage: directly overlap player_icon with
	# the first enemy icon's position and let physics process the area_entered signal.
	var target_icon: CampaignFleetIcon = scene.enemy_icons[0]
	scene.player_icon.global_position = target_icon.global_position
	for i in 5:
		await tree.physics_frame

	var prompt: Control = scene.get_node("EngagePrompt")
	if not prompt.visible:
		failures.append("expected EngagePrompt visible after player icon overlaps an enemy icon")

	prompt.get_node("EngageButton").pressed.emit()
	if campaign_state.active_enemy_fleet != target_icon.fleet:
		failures.append("expected Engage button to call CampaignState.start_engagement with the overlapped fleet")

	campaign_state.reset()
	scene.queue_free()
	return failures
