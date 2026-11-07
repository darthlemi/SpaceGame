extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame
	tree.paused = false

	var panel: SystemsStationsPanel = scene.systems_stations_panel
	var systems_button: Button = scene.fleet_status_bar.systems_button

	# (a) open pauses, close unpauses.
	systems_button.pressed.emit()
	if not panel.visible or not tree.paused:
		failures.append("(a) expected Systems to open the panel and pause, visible=%s paused=%s" % [panel.visible, tree.paused])
	panel.close_button.pressed.emit()
	if panel.visible or tree.paused:
		failures.append("(a) expected Close to hide the panel and unpause")

	# (b) a pre-existing pause survives open/close.
	tree.paused = true
	systems_button.pressed.emit()
	panel.close_button.pressed.emit()
	if not tree.paused:
		failures.append("(b) expected Close to keep a pre-existing pause")
	tree.paused = false

	# (c) the engage prompt is modal: Systems is ignored while it's up.
	scene.engage_prompt.visible = true
	systems_button.pressed.emit()
	if panel.visible:
		failures.append("(c) expected Systems to be ignored while the engage prompt is visible")
	scene.engage_prompt.visible = false

	# (d) mutual exclusion: Systems is ignored while the Fleet panel is open, and vice versa.
	scene.fleet_status_bar.fleet_button.pressed.emit()
	systems_button.pressed.emit()
	if panel.visible:
		failures.append("(d) expected Systems to be ignored while the Fleet panel is visible")
	scene.fleet_management_panel.close_button.pressed.emit()
	tree.paused = false
	systems_button.pressed.emit()
	scene.fleet_status_bar.fleet_button.pressed.emit()
	if scene.fleet_management_panel.visible:
		failures.append("(d) expected Fleet to be ignored while the Systems panel is visible")
	panel.close_button.pressed.emit()
	tree.paused = false

	campaign_state.reset()
	return failures
