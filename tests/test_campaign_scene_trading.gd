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
	# transition, so move away first and then back onto it.
	scene.player_icon.global_position = Vector2(-5000, -5000)
	for i in 3:
		await tree.physics_frame
	scene.player_icon.global_position = scene.HOME_BASE_POSITION
	for i in 5:
		await tree.physics_frame

	if not trade_panel.visible:
		failures.append("expected TradePanel visible after docking at HomeBase")
	# Docking now auto-pauses the tree; undo that so the physics-frame-driven
	# "leave the base" teleport below can actually register the area_exited
	# transition (mirrors how a real move command would unpause).
	tree.paused = false

	scene.player_icon.global_position = Vector2(-5000, -5000)
	for i in 5:
		await tree.physics_frame

	if trade_panel.visible:
		failures.append("expected TradePanel hidden after leaving HomeBase")

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
	campaign_state.reset()
	scene.queue_free()
	return failures
