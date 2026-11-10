extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	await _check_layers(tree, campaign_state, failures)
	await _check_no_cross_system_overlaps(tree, campaign_state, failures)
	await _check_docking(tree, campaign_state, failures)
	await _check_respawn_returns_to_home_system(tree, campaign_state, failures)
	await _check_trading_round_trip(tree, campaign_state, failures)
	await _check_hidden_layers_keep_running(tree, campaign_state, failures)
	await _check_scenery_layering(tree, campaign_state, failures)
	tree.paused = false
	campaign_state.reset()
	return failures

static func _open_scene(tree: SceneTree) -> Node2D:
	var scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame
	await tree.process_frame
	return scene

static func _close_scene(tree: SceneTree, campaign_state, scene: Node2D) -> void:
	tree.paused = false
	scene.queue_free()
	await tree.process_frame
	campaign_state.reset()

static func _icon_for(scene: Node2D, fleet: CampaignFleet) -> CampaignFleetIcon:
	for icon in scene.enemy_icons:
		if is_instance_valid(icon) and icon.fleet == fleet:
			return icon
	return null

static func _first_fleet(campaign_state, station_id: String, role: CampaignFleet.Role) -> CampaignFleet:
	var fleets: Array[CampaignFleet] = campaign_state.station_fleets(campaign_state.galaxy.station(station_id), role)
	return fleets[0] if not fleets.is_empty() else null

static func _check_layers(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	var scene := await _open_scene(tree)
	if scene.layers.size() != 27:
		failures.append("layers: expected 27 system layers, got %d" % scene.layers.size())
	for system_id in scene.layers:
		var layer: Node2D = scene.layers[system_id]
		if system_id == "haven":
			if not layer.visible or layer.position != Vector2.ZERO:
				failures.append("layers: expected haven visible at the origin, visible=%s position=%s" % [layer.visible, layer.position])
		else:
			if layer.visible:
				failures.append("layers: expected %s hidden" % system_id)
			if layer.position.length() < scene.SYSTEM_SPACING:
				failures.append("layers: expected %s at least SYSTEM_SPACING from the origin, at %s" % [system_id, layer.position])
	if scene.station_nodes.size() != campaign_state.galaxy.stations.size():
		failures.append("layers: expected one station node per station, got %d" % scene.station_nodes.size())
	for station_id in scene.station_nodes:
		var node: Node2D = scene.station_nodes[station_id]
		if node.get_parent() != scene.layer_for(node.station.system_id):
			failures.append("layers: expected station %s under its system's layer" % station_id)
	# Aurum Spire (Dominion) and Ashfall Yard (pirate) share a local position; only layer
	# offsets keep their fleets apart.
	if not campaign_state.active_skirmishes.is_empty():
		failures.append("layers: expected no skirmish at game start, got %d" % campaign_state.active_skirmishes.size())
	var icons: Array = [scene.player_icon]
	icons.append_array(scene.enemy_icons)
	for icon in icons:
		if icon.get_parent() != scene.layer_for(icon.fleet.system_id):
			failures.append("layers: expected the %s fleet icon under layer %s" % [CampaignFleet.Faction.keys()[icon.fleet.faction], icon.fleet.system_id])
	await _close_scene(tree, campaign_state, scene)

static func _check_no_cross_system_overlaps(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	var scene := await _open_scene(tree)
	var pirate := _icon_for(scene, _first_fleet(campaign_state, "marrow_hideout", CampaignFleet.Role.COMBAT))
	var trader := _icon_for(scene, _first_fleet(campaign_state, "wexford_outpost", CampaignFleet.Role.TRADER))
	if pirate == null or trader == null:
		failures.append("overlaps: setup expected a marrow pirate icon and a wexford trader icon")
		await _close_scene(tree, campaign_state, scene)
		return
	var spot := Vector2(500, 300)
	pirate.position = spot
	trader.position = spot
	for i in 10:
		await tree.physics_frame
	if _in_skirmish(campaign_state, pirate.fleet):
		failures.append("overlaps: a pirate in marrow and a trader in wexford at the same local position started a skirmish")

	# The same pair inside one system must still fight.
	trader.reparent(scene.layer_for("marrow"))
	trader.fleet.system_id = "marrow"
	trader.position = pirate.position
	for i in 10:
		await tree.physics_frame
	if not _in_skirmish(campaign_state, pirate.fleet):
		failures.append("overlaps: expected the pirate and trader in the same system to start a skirmish")
	await _close_scene(tree, campaign_state, scene)

static func _in_skirmish(campaign_state, fleet: CampaignFleet) -> bool:
	for skirmish in campaign_state.active_skirmishes:
		if skirmish.fleet_winner == fleet or skirmish.fleet_loser == fleet:
			return true
	return false

static func _check_docking(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	var scene := await _open_scene(tree)
	var overview: BaseOverviewPanel = scene.base_overview_panel
	scene._trigger_arrival(scene.station_nodes["haven_exchange"])
	var exchange: StationData = campaign_state.galaxy.station("haven_exchange")
	if not overview.visible or overview.title_label.text != "Haven Exchange":
		failures.append("docking: expected the overview open titled 'Haven Exchange', visible=%s title='%s'" % [overview.visible, overview.title_label.text])
	if overview._economy != exchange.economy:
		failures.append("docking: expected the overview to show Haven Exchange's own economy")
	if overview._faction != null or overview.pay_fine_button.visible:
		failures.append("docking: expected no faction and no fine button at a neutral station")
	scene._on_docking_panel_closed()

	scene._trigger_arrival(scene.station_nodes["marrow_hideout"])
	if not overview.visible or overview.title_label.text != "Marrow Hideout":
		failures.append("docking: expected the overview open at the pirate Marrow Hideout, visible=%s title='%s'" % [overview.visible, overview.title_label.text])
	scene._on_docking_panel_closed()
	await _close_scene(tree, campaign_state, scene)

static func _check_respawn_returns_to_home_system(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	campaign_state.player_fleet.system_id = "marrow"
	campaign_state.player_fleet.position = Vector2(850, 420)
	campaign_state.begin_respawn()
	var scene := await _open_scene(tree)
	var home: StationData = campaign_state.galaxy.home_station()
	var haven_layer: Node2D = scene.layer_for("haven")
	if scene.player_icon.get_parent() != haven_layer:
		failures.append("respawn_returns_to_home_system: expected the player icon in haven's layer, system_id=%s" % campaign_state.player_fleet.system_id)
	if scene.player_icon.position != home.position:
		failures.append("respawn_returns_to_home_system: expected the player at the home station %s, got %s" % [home.position, scene.player_icon.position])
	if haven_layer == null or not haven_layer.visible or haven_layer.position != Vector2.ZERO:
		failures.append("respawn_returns_to_home_system: expected haven to be the current layer")
	await _close_scene(tree, campaign_state, scene)

static func _check_trading_round_trip(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	var fleet := _first_fleet(campaign_state, "aurum_spire", CampaignFleet.Role.TRADER)
	if fleet == null:
		failures.append("trading: setup expected an Aurum Spire trader")
		return
	fleet.dest_station_id = "aurum_bazaar"
	var scene := await _open_scene(tree)
	var icon := _icon_for(scene, fleet)
	var bazaar: StationData = campaign_state.galaxy.station("aurum_bazaar")
	if icon.dest_position != bazaar.position:
		failures.append("trading: expected dest_position at Aurum Bazaar %s, got %s" % [bazaar.position, icon.dest_position])
	var arrivals: Array[String] = []
	icon.trader_arrived_at.connect(func(station_id: String): arrivals.append(station_id))
	icon.position = bazaar.position + Vector2(40, 0)
	var start_distance: float = icon.position.distance_to(bazaar.position)
	for i in 120:
		await tree.physics_frame
		if not arrivals.is_empty():
			break
	if arrivals.size() != 1 or arrivals[0] != "aurum_bazaar":
		failures.append("trading: expected one trader_arrived_at('aurum_bazaar') after moving %.0f px, got %s" % [start_distance, arrivals])
	if fleet.dest_station_id != "aurum_spire":
		failures.append("trading: expected the next destination home ('aurum_spire'), got '%s'" % fleet.dest_station_id)
	if icon.dest_position != campaign_state.galaxy.station("aurum_spire").position:
		failures.append("trading: expected dest_position updated to Aurum Spire, got %s" % icon.dest_position)
	await _close_scene(tree, campaign_state, scene)

static func _check_hidden_layers_keep_running(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	campaign_state.new_game()
	var scene := await _open_scene(tree)
	var icon := _icon_for(scene, _first_fleet(campaign_state, "kestrel_picket", CampaignFleet.Role.COMBAT))
	if icon == null:
		failures.append("hidden layers: setup expected a Kestrel Picket combat icon")
		await _close_scene(tree, campaign_state, scene)
		return
	var start: Vector2 = icon.position
	for i in 30:
		await tree.physics_frame
	if icon.position == start:
		failures.append("hidden layers: expected a fleet in a hidden layer to keep moving, stayed at %s" % start)
	if icon.fleet.position != icon.position:
		failures.append("hidden layers: expected fleet.position to track the icon's local position")
	for child in icon.get_children():
		if child is CPUParticles2D and child.emitting:
			failures.append("hidden layers: expected no engine trails emitting in a hidden layer")
			break
	await _close_scene(tree, campaign_state, scene)

static func _check_scenery_layering(tree: SceneTree, campaign_state, failures: Array[String]) -> void:
	var layer := SystemLayer.new()
	tree.root.add_child(layer)
	var behind := layer.add_scenery({"type": "planet", "texture": "planet_gas_purple.png", "pos": [100.0, 100.0], "scale": 3.0, "layer": "mid_distance"})
	var front := layer.add_scenery({"type": "asteroid", "texture": "v1_round_a.png", "pos": [200.0, 200.0], "scale": 1.5, "layer": "foreground"})
	# add_scenery offsets world positions by the same centering SceneryCanvas's viewport outline
	# uses (see system_layer.gd's SCENERY_SPACE/SCENERY_VIEWPORT), so the resulting sprite
	# position is the recipe's world pos minus that offset, not the raw world pos.
	var offset: Vector2 = (SystemLayer.SCENERY_SPACE - SystemLayer.SCENERY_VIEWPORT) / 2.0
	if behind == null or front == null:
		failures.append("scenery layering: expected both sprites created")
	elif behind.position != Vector2(100.0, 100.0) - offset or front.position != Vector2(200.0, 200.0) - offset:
		failures.append("scenery layering: expected sprites at their recipe position minus the viewport-centering offset, got %s / %s" % [behind.position, front.position])
	elif layer.get_children().find(front) <= layer.get_children().find(behind):
		failures.append("scenery layering: expected the foreground sprite added after the mid_distance one")
	# (1600, 1600) is the center of SceneryCanvas's drawn viewport outline in its 3200x3200
	# world space, matching MapEditModel.NEW_SCENERY_POS -- a scenery item placed there (the
	# default for a freshly-placed item) must render at the center of the actual visible
	# 1152x648 screen, not at raw world coordinates.
	var centered := layer.add_scenery({"type": "planet", "texture": "planet_gas_purple.png", "pos": [1600.0, 1600.0], "scale": 1.0, "layer": "foreground"})
	if centered == null or centered.position.distance_to(Vector2(576.0, 324.0)) >= 1.0:
		failures.append("scenery layering: expected a scenery item placed at the editor's viewport-outline center to render near screen center (576, 324), got %s" % [centered.position if centered != null else null])
	layer.queue_free()
	await tree.process_frame
