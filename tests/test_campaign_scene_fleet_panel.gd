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

	var panel: FleetManagementPanel = scene.fleet_management_panel
	var fleet_button: Button = scene.fleet_status_bar.fleet_button

	# (a) open undocked pauses, close unpauses.
	fleet_button.pressed.emit()
	if not panel.visible or not tree.paused:
		failures.append("(a) expected Fleet to open the panel and pause, visible=%s paused=%s" % [panel.visible, tree.paused])
	panel.close_button.pressed.emit()
	if panel.visible or tree.paused:
		failures.append("(a) expected Close to hide the panel and unpause")

	# (b) a pre-existing pause survives open/close.
	tree.paused = true
	fleet_button.pressed.emit()
	panel.close_button.pressed.emit()
	if not tree.paused:
		failures.append("(b) expected Close to keep a pre-existing pause")
	tree.paused = false

	# (d) engage prompt is modal.
	scene.engage_prompt.visible = true
	fleet_button.pressed.emit()
	if panel.visible:
		failures.append("(d) expected Fleet to be ignored while the engage prompt is visible")
	scene.engage_prompt.visible = false

	# (c) docked: close keeps the pause and the overview.
	var home_base: HomeBase = null
	for child in scene.get_children():
		if child is HomeBase:
			home_base = child
			break
	scene._trigger_arrival(home_base)
	var overview: BaseOverviewPanel = scene.base_overview_panel
	if not overview.visible or not tree.paused:
		failures.append("(c) setup: expected docked overview and pause")
	fleet_button.pressed.emit()
	if not panel.visible or not panel.hire_row.visible:
		failures.append("(c) expected panel open with hire row when docked")
	panel.close_button.pressed.emit()
	if not tree.paused or not overview.visible:
		failures.append("(c) expected docked Close to keep pause and overview, paused=%s overview=%s" % [tree.paused, overview.visible])

	# (e) opening Trade Goods closes the fleet panel.
	fleet_button.pressed.emit()
	overview.trade_goods_button.pressed.emit()
	if panel.visible or not scene.trade_panel.visible:
		failures.append("(e) expected Trade Goods to replace the fleet panel")

	scene._on_docking_panel_closed()
	tree.paused = false
	campaign_state.reset()
	scene.queue_free()

	# Modal respawn: map click, speed/pause controls and Fleet cannot resume or open panels.
	campaign_state.reset()
	var modal_player := CampaignFleet.new()
	modal_player.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	campaign_state.player_fleet = modal_player
	campaign_state.begin_respawn()
	var modal_scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(modal_scene)
	await tree.process_frame
	if not modal_scene.respawn_panel.visible or not tree.paused:
		failures.append("modal respawn: setup expected the panel open and the tree paused")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	modal_scene._unhandled_input(click)
	if not tree.paused:
		failures.append("modal respawn: (a) a map click unpaused the game")
	var controls = modal_scene.get_node("UILayer/SpeedControls")
	controls.speed_3x_button.pressed.emit()
	if not tree.paused:
		failures.append("modal respawn: (b) a speed button unpaused the game")
	controls.pause_button.pressed.emit()
	if not tree.paused:
		failures.append("modal respawn: (b) the pause button toggled the pause")
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	controls._unhandled_input(space)
	if not tree.paused:
		failures.append("modal respawn: (b) Space toggled the pause")
	modal_scene.fleet_status_bar.fleet_button.pressed.emit()
	if modal_scene.fleet_management_panel.visible:
		failures.append("modal respawn: (c) Fleet opened the fleet panel")
	modal_scene.respawn_panel.free_button.pressed.emit()
	if tree.paused:
		failures.append("modal respawn: (d) expected the tree unpaused after taking the free ship")
	controls.pause_button.pressed.emit()
	if not tree.paused:
		failures.append("modal respawn: (d) expected the pause button to work after respawn")
	controls.speed_1x_button.pressed.emit()
	if tree.paused:
		failures.append("modal respawn: (d) expected a speed button to unpause after respawn")
	tree.paused = false
	Engine.time_scale = 1.0
	modal_scene.queue_free()
	campaign_state.reset()

	return failures
