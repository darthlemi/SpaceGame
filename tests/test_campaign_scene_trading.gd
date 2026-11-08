extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")
const UiLayoutCheck = preload("res://tests/ui_layout_check.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame
	# Clear any incidental pause so the teleport-and-await-physics-frame checks below progress.
	tree.paused = false

	var overview: BaseOverviewPanel = scene.get_node("UILayer/BaseOverviewPanel")
	var trade_panel: TradePanel = scene.get_node("UILayer/TradePanel")
	var refit_panel: RefitPanel = scene.get_node("UILayer/RefitPanel")
	var repair_panel: RepairPanel = scene.get_node("UILayer/RepairPanel")
	if overview.visible:
		failures.append("expected BaseOverviewPanel hidden before the player docks anywhere")

	# The player icon starts on the home station, but area_entered only fires on a fresh
	# overlap transition, so move away first and then back onto it. Docking only opens the
	# panel when the overlap is the player's deliberate click target, so set _travel_target
	# (what a real click would set) to the home station node before re-approaching it.
	scene.player_icon.position = Vector2(-5000, -5000)
	for i in 3:
		await tree.physics_frame
	var home_base: CampaignStation = scene.station_nodes[campaign_state.galaxy.home_station().id]
	scene._travel_target = home_base
	scene.player_icon.position = home_base.position
	for i in 5:
		await tree.physics_frame

	# Docking opens only the overview; sub-panels open from its buttons.
	if not overview.visible:
		failures.append("expected BaseOverviewPanel visible after docking at the home station")
	if overview.title_label.text != "Home Base":
		failures.append("expected the overview titled 'Home Base', got '%s'" % overview.title_label.text)
	if overview.population_label.text.begins_with("Population: 0 "):
		failures.append("expected bootstrap to seed the home station population, got '%s'" % overview.population_label.text)
	for sub_panel in [trade_panel, refit_panel, repair_panel]:
		if sub_panel.visible:
			failures.append("expected %s hidden until chosen from the overview" % sub_panel.name)

	var speed_rect: Rect2 = scene.get_node("UILayer/SpeedControls/Background").get_global_rect()
	var status_bar: Control = scene.get_node("UILayer/FleetStatusBar")
	var status_rect: Rect2 = status_bar.get_node("Background").get_global_rect()
	var overview_rect: Rect2 = overview.get_node("Background").get_global_rect()
	# Headless runs use a 64x64 window, so check against the configured size.
	var viewport_rect := Rect2(0, 0, ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	var sub_panel_buttons := {trade_panel: overview.trade_goods_button, refit_panel: overview.shipyard_button, repair_panel: overview.repair_button}
	for sub_panel in sub_panel_buttons:
		sub_panel_buttons[sub_panel].pressed.emit()
		await tree.process_frame
		for other in sub_panel_buttons:
			if other.visible != (other == sub_panel):
				failures.append("expected only %s open after its overview button, but %s visible=%s" % [sub_panel.name, other.name, other.visible])
		var bg_rect: Rect2 = sub_panel.get_node("Background").get_global_rect()
		for other_rect in [speed_rect, status_rect, overview_rect]:
			if bg_rect.intersects(other_rect):
				failures.append("expected %s %s not to overlap %s" % [sub_panel.name, bg_rect, other_rect])
		if not viewport_rect.encloses(bg_rect):
			failures.append("expected %s %s inside the viewport %s" % [sub_panel.name, bg_rect, viewport_rect])
		UiLayoutCheck.check_panel_layout(sub_panel, failures)
	overview.shipyard_button.pressed.emit()
	refit_panel.equip_button.pressed.emit()
	await tree.process_frame
	UiLayoutCheck.check_panel_layout(refit_panel, failures)
	refit_panel.shop_button.pressed.emit()

	# A sub-panel's Close returns to the overview without undocking.
	refit_panel.close_button.pressed.emit()
	if refit_panel.visible or not overview.visible or not tree.paused:
		failures.append("expected sub-panel Close to return to the still-docked overview")

	for other_rect in [speed_rect, status_rect]:
		if overview_rect.intersects(other_rect):
			failures.append("expected BaseOverviewPanel %s not to overlap %s" % [overview_rect, other_rect])
	if not viewport_rect.encloses(overview_rect):
		failures.append("expected BaseOverviewPanel %s inside the viewport %s" % [overview_rect, viewport_rect])
	UiLayoutCheck.check_panel_layout(overview, failures)
	# Docking auto-pauses, so the PAUSED label is shown and checked too.
	UiLayoutCheck.check_panel_layout(scene.get_node("UILayer/SpeedControls"), failures)
	if status_rect.intersects(speed_rect):
		failures.append("expected FleetStatusBar %s not to overlap SpeedControls %s" % [status_rect, speed_rect])
	if not viewport_rect.encloses(status_rect):
		failures.append("expected FleetStatusBar %s inside the viewport %s" % [status_rect, viewport_rect])
	UiLayoutCheck.check_panel_layout(status_bar, failures)
	var crew_text: String = status_bar.get_node("Layout/CrewLabel").text
	var crew_fleet: CampaignFleet = campaign_state.player_fleet
	var expected_crew_text := "Crew: %d/%d (-%d cr/tick)" % [crew_fleet.crew_total(), crew_fleet.crew_capacity(), campaign_state.wage_bill(crew_fleet)]
	if status_bar.get_node_or_null("Layout/FleetButton") == null:
		failures.append("expected FleetStatusBar to have a Fleet button")
	if "." in crew_text.get_slice("
", 0):
		failures.append("expected FleetStatusBar wage text without a decimal point, got '%s'" % crew_text)
	if crew_text != expected_crew_text:
		failures.append("expected FleetStatusBar crew label '%s', got '%s'" % [expected_crew_text, crew_text])
	var fuel_text: String = status_bar.get_node("Layout/FuelLabel").text
	if not fuel_text.begins_with("Fuel: %.1f" % campaign_state.player_fleet.fuel_amount()):
		failures.append("expected FleetStatusBar fuel label to show the fleet's fuel, got '%s'" % fuel_text)

	# A 0-crew ship crawls the fleet: the crew label says so in the empty-fuel colour.
	var crew_label: Label = status_bar.get_node("Layout/CrewLabel")
	var crawl_suffix := "\n(0-crew ship: %d%% speed)" % roundi(CampaignFleet.EMPTY_FUEL_SPEED_FACTOR * 100.0)
	var crawl_comp: Dictionary = crew_fleet.ship_compositions[crew_fleet.ship_compositions.size() - 1]
	var crawl_crew_before: int = CrewRules.crew_of(crawl_comp)
	CrewRules.set_crew(crawl_comp, 0)
	status_bar._update_display()
	if not crew_label.text.ends_with(crawl_suffix):
		failures.append("expected crew label to end with '%s' for a 0-crew ship, got '%s'" % [crawl_suffix.c_escape(), crew_label.text.c_escape()])
	if not crew_label.has_theme_color_override("font_color") or crew_label.get_theme_color("font_color") != status_bar.EMPTY_FUEL_COLOR:
		failures.append("expected crew label coloured EMPTY_FUEL_COLOR for a 0-crew ship")
	await tree.process_frame
	UiLayoutCheck.check_panel_layout(status_bar, failures)
	CrewRules.set_crew(crawl_comp, crawl_crew_before)
	status_bar._update_display()
	if crew_label.text.ends_with(crawl_suffix) or crew_label.has_theme_color_override("font_color"):
		failures.append("expected the crawl warning and colour removed once the ship is crewed, got '%s'" % crew_label.text)

	# Undock closes everything and resumes the game.
	overview.trade_goods_button.pressed.emit()
	overview.undock_button.pressed.emit()
	if overview.visible or trade_panel.visible or tree.paused:
		failures.append("expected Undock to close the overview and sub-panels and unpause")

	# Re-dock to cover leaving the base by moving away.
	scene.player_icon.position = Vector2(-5000, -5000)
	for i in 3:
		await tree.physics_frame
	scene._travel_target = home_base
	scene.player_icon.position = home_base.position
	for i in 5:
		await tree.physics_frame
	overview.trade_goods_button.pressed.emit()
	# Docking now auto-pauses the tree; undo that so the physics-frame-driven
	# "leave the base" teleport below can actually register the area_exited
	# transition (mirrors how a real move command would unpause).
	tree.paused = false

	scene.player_icon.position = Vector2(-5000, -5000)
	for i in 5:
		await tree.physics_frame

	for docking_panel in [overview, trade_panel, refit_panel, repair_panel]:
		if docking_panel.visible:
			failures.append("expected %s hidden after leaving the home station" % docking_panel.name)

	# Dock at a faction station and confirm the panel opens with that station's own economy.
	# Haven has none, so put the player in Kestrel (Dominion) the way arriving there would.
	_move_to_system(scene, scene.player_icon, "kestrel")
	scene.show_system("kestrel")
	var faction_base: CampaignStation = scene.station_nodes["kestrel_picket"]
	scene._travel_target = faction_base
	scene.player_icon.position = faction_base.position
	for i in 5:
		await tree.physics_frame
	var docked_faction: PowerFaction = campaign_state.power_faction_for(faction_base.station.owner)
	if not overview.visible:
		failures.append("expected BaseOverviewPanel visible after docking at a faction station")
	elif overview.title_label.text != faction_base.station.display_name:
		failures.append("expected the overview titled after the station, got '%s'" % overview.title_label.text)
	overview.trade_goods_button.pressed.emit()
	if trade_panel._docked_base_economy != faction_base.station.economy:
		failures.append("expected Trade Goods to open with the docked faction station's own economy")

	# Paying a fine re-derives that faction's icon behavior immediately.
	var faction_icon: CampaignFleetIcon = null
	for icon in scene.enemy_icons:
		if is_instance_valid(icon) and icon.fleet.faction == docked_faction.faction_enum and icon.fleet.role == CampaignFleet.Role.COMBAT:
			faction_icon = icon
			break
	if faction_icon == null:
		failures.append("expected a combat fleet icon for the docked faction")
	else:
		docked_faction.reputation = campaign_state.HOSTILE_REPUTATION_THRESHOLD - 10.0
		docked_faction.fine = 150
		docked_faction.fine_reputation = 20.0
		faction_icon.behavior_type = CampaignFleetIcon.BehaviorType.PIRATE
		campaign_state.credits = 1000
		overview.refresh()
		overview.pay_fine_button.pressed.emit()
		if faction_icon.behavior_type != CampaignFleetIcon.BehaviorType.PATROL:
			failures.append("expected paying the fine to turn the faction's combat icon back to PATROL, got %s" % faction_icon.behavior_type)

	scene._on_docking_panel_closed()
	_move_to_system(scene, scene.player_icon, "haven")
	scene.show_system("haven")
	tree.paused = false

	# Flyby coverage: overlapping a base that was NOT the player's clicked
	# travel target (e.g. drifting past it during free-drag movement) must
	# not open the panel -- only a deliberate click (_travel_target set to
	# that base) should.
	scene.player_icon.position = Vector2(-5000, -5000)
	for i in 3:
		await tree.physics_frame
	scene._travel_target = null
	scene.player_icon.position = home_base.position
	for i in 5:
		await tree.physics_frame
	if overview.visible:
		failures.append("expected BaseOverviewPanel to stay hidden when overlapping the home station without it being the clicked travel target")
	tree.paused = false

	# Arrival coverage: reaching the clicked target must clear _travel_target
	# so the player regains normal click control once the panel is open.
	scene.player_icon.position = Vector2(-5000, -5000)
	for i in 3:
		await tree.physics_frame
	scene._travel_target = home_base
	scene.player_icon.position = home_base.position
	for i in 5:
		await tree.physics_frame
	if scene._travel_target != null:
		failures.append("expected _travel_target cleared after arriving at the clicked base")
	tree.paused = false

	# Bug coverage: a fleet icon sitting on top of a base, then clicking the
	# base itself while already overlapping it. Disengaging from the fleet
	# encounter leaves the player standing on the base with no fresh
	# area_entered transition left to fire -- clicking the base (already
	# overlapped) must still open the trade panel immediately.
	var enemy_icon: CampaignFleetIcon = scene.enemy_icons[0]
	_move_to_system(scene, enemy_icon, "haven")
	scene.player_icon.position = Vector2(-5000, -5000)
	enemy_icon.position = Vector2(-6000, -6000)
	for i in 3:
		await tree.physics_frame
	enemy_icon.position = home_base.position
	scene._travel_target = enemy_icon
	scene.player_icon.position = home_base.position
	for i in 5:
		await tree.physics_frame
	var engage_prompt: Control = scene.get_node("UILayer/EngagePrompt")
	if not engage_prompt.visible:
		failures.append("expected EngagePrompt visible after clicking a fleet icon overlapping a base")

	engage_prompt.get_node("DisengageButton").pressed.emit()
	if tree.paused:
		failures.append("expected disengaging to unpause the tree")

	# This is what a real click on the (already-overlapped) base does: set
	# it as the travel target, then fire the arrival trigger directly since
	# no fresh area_entered signal will come.
	scene._travel_target = home_base
	if scene.player_icon.get_overlapping_areas().has(home_base):
		scene._trigger_arrival(home_base)
	if not overview.visible:
		failures.append("expected clicking an already-overlapped base (after disengaging) to open the BaseOverviewPanel immediately")
	tree.paused = false

	scene.player_icon.position = Vector2(-5000, -5000)
	for i in 3:
		await tree.physics_frame

	campaign_state.reset()
	scene.queue_free()
	await tree.process_frame
	return failures

static func _move_to_system(scene: Node2D, icon: CampaignFleetIcon, system_id: String) -> void:
	icon.reparent(scene.layer_for(system_id))
	icon.fleet.system_id = system_id
