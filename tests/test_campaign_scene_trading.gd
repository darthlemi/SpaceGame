extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame
	# The player fleet spawns already docked at HomeBase, which now auto-pauses
	# the tree on area_entered -- clear that incidental pause so the
	# teleport-and-await-physics-frame checks below actually progress.
	tree.paused = false

	var trade_panel: TradePanel = scene.get_node("UILayer/TradePanel")
	if trade_panel.visible:
		failures.append("expected TradePanel hidden before the player docks anywhere")

	# HomeBase sits at CampaignScene.HOME_BASE_POSITION; the player icon
	# starts there too, but area_entered only fires on a fresh overlap
	# transition, so move away first and then back onto it. Docking now
	# only opens the panel when the overlap is the player's deliberate
	# click target, so set _travel_target (what a real click would set)
	# to the HomeBase node before re-approaching it.
	scene.player_icon.global_position = Vector2(-5000, -5000)
	for i in 3:
		await tree.physics_frame
	var home_base: HomeBase = null
	for child in scene.get_children():
		if child is HomeBase:
			home_base = child
			break
	scene._travel_target = home_base
	scene.player_icon.global_position = scene.HOME_BASE_POSITION
	for i in 5:
		await tree.physics_frame

	if not trade_panel.visible:
		failures.append("expected TradePanel visible after docking at HomeBase")
	var refit_panel: RefitPanel = scene.get_node("UILayer/RefitPanel")
	if not refit_panel.visible:
		failures.append("expected RefitPanel visible after docking at HomeBase")
	# Both open together on dock, so their drawn backgrounds must not overlap.
	var trade_rect: Rect2 = trade_panel.get_node("Background").get_global_rect()
	var refit_rect: Rect2 = refit_panel.get_node("Background").get_global_rect()
	if trade_rect.intersects(refit_rect):
		failures.append("expected TradePanel %s and RefitPanel %s not to overlap" % [trade_rect, refit_rect])
	var speed_rect: Rect2 = scene.get_node("UILayer/SpeedControls/Background").get_global_rect()
	# Headless runs use a 64x64 window, so check against the configured size.
	var viewport_rect := Rect2(0, 0, ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))
	for panel in [trade_panel, refit_panel]:
		var bg_rect: Rect2 = panel.get_node("Background").get_global_rect()
		if bg_rect.intersects(speed_rect):
			failures.append("expected %s %s not to overlap SpeedControls %s" % [panel.name, bg_rect, speed_rect])
		if not viewport_rect.encloses(bg_rect):
			failures.append("expected %s %s inside the viewport %s" % [panel.name, bg_rect, viewport_rect])
		_check_panel_layout(panel, failures)
	# Docking auto-pauses, so the PAUSED label is shown and checked too.
	_check_panel_layout(scene.get_node("UILayer/SpeedControls"), failures)
	refit_panel.equip_button.pressed.emit()
	await tree.process_frame
	_check_panel_layout(refit_panel, failures)
	refit_panel.shop_button.pressed.emit()
	# Docking now auto-pauses the tree; undo that so the physics-frame-driven
	# "leave the base" teleport below can actually register the area_exited
	# transition (mirrors how a real move command would unpause).
	tree.paused = false

	scene.player_icon.global_position = Vector2(-5000, -5000)
	for i in 5:
		await tree.physics_frame

	if trade_panel.visible:
		failures.append("expected TradePanel hidden after leaving HomeBase")
	if refit_panel.visible:
		failures.append("expected RefitPanel hidden after leaving HomeBase")

	# Dock at a faction base and confirm the panel opens with that
	# faction's own economy (not HomeBase's).
	var faction_base: FactionBase = null
	for child in scene.get_children():
		if child is FactionBase:
			faction_base = child
			break
	if faction_base == null:
		failures.append("expected at least one FactionBase spawned by bootstrap")
	else:
		scene._travel_target = faction_base
		scene.player_icon.global_position = faction_base.global_position
		for i in 5:
			await tree.physics_frame
		if not trade_panel.visible:
			failures.append("expected TradePanel visible after docking at a FactionBase")
		else:
			var expected_economy: BaseEconomy = null
			for faction in campaign_state.factions:
				if faction.faction_enum == faction_base.faction_enum:
					expected_economy = faction.economy
			if trade_panel._docked_base_economy != expected_economy:
				failures.append("expected TradePanel to open with the docked FactionBase's own economy")

	tree.paused = false

	# Flyby coverage: overlapping a base that was NOT the player's clicked
	# travel target (e.g. drifting past it during free-drag movement) must
	# not open the panel -- only a deliberate click (_travel_target set to
	# that base) should.
	scene.player_icon.global_position = Vector2(-5000, -5000)
	for i in 3:
		await tree.physics_frame
	scene._travel_target = null
	scene.player_icon.global_position = scene.HOME_BASE_POSITION
	for i in 5:
		await tree.physics_frame
	if trade_panel.visible:
		failures.append("expected TradePanel to stay hidden when overlapping HomeBase without it being the clicked travel target")
	tree.paused = false

	# Arrival coverage: reaching the clicked target must clear _travel_target
	# so the player regains normal click control once the panel is open.
	scene.player_icon.global_position = Vector2(-5000, -5000)
	for i in 3:
		await tree.physics_frame
	scene._travel_target = home_base
	scene.player_icon.global_position = scene.HOME_BASE_POSITION
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
	var enemy_original_position: Vector2 = enemy_icon.global_position
	scene.player_icon.global_position = Vector2(-5000, -5000)
	enemy_icon.global_position = Vector2(-6000, -6000)
	for i in 3:
		await tree.physics_frame
	enemy_icon.global_position = scene.HOME_BASE_POSITION
	scene._travel_target = enemy_icon
	scene.player_icon.global_position = scene.HOME_BASE_POSITION
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
	if not trade_panel.visible:
		failures.append("expected clicking an already-overlapped base (after disengaging) to open the TradePanel immediately")
	tree.paused = false

	enemy_icon.global_position = enemy_original_position
	scene.player_icon.global_position = Vector2(-5000, -5000)
	for i in 3:
		await tree.physics_frame

	campaign_state.reset()
	scene.queue_free()
	return failures

# Theme-driven control sizes (e.g. the 8px button margins) must never push
# content outside the panel chrome or on top of other content.
static func _check_panel_layout(panel: Control, failures: Array[String]) -> void:
	var bg_rect: Rect2 = panel.get_node("Background").get_global_rect()
	var controls: Array[Control] = []
	_collect_visible_widgets(panel, controls)
	for c in controls:
		# ScrollContainer clips its content, so off-screen rows are fine.
		if not _has_scroll_ancestor(c, panel) and not bg_rect.encloses(c.get_global_rect()):
			failures.append("%s: %s %s spills outside Background %s" % [panel.name, c.name, c.get_global_rect(), bg_rect])
	for i in controls.size():
		for j in range(i + 1, controls.size()):
			if controls[i].get_global_rect().intersects(controls[j].get_global_rect()):
				failures.append("%s: %s overlaps %s" % [panel.name, controls[i].name, controls[j].name])

static func _collect_visible_widgets(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		if not (child is Control) or not child.visible:
			continue
		if child is Button or child is Label:
			out.append(child)
		_collect_visible_widgets(child, out)

static func _has_scroll_ancestor(node: Node, stop_at: Node) -> bool:
	var parent := node.get_parent()
	while parent != null and parent != stop_at:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false
