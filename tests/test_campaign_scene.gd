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

	if campaign_state.factions.size() != 2:
		failures.append("expected 2 PowerFactions created by bootstrap, got %d" % campaign_state.factions.size())
	var faction_enums: Array = []
	for faction in campaign_state.factions:
		faction_enums.append(faction.faction_enum)
	if not faction_enums.has(CampaignFleet.Faction.DOMINION):
		failures.append("expected a DOMINION PowerFaction created by bootstrap")
	if not faction_enums.has(CampaignFleet.Faction.FREEHOLD):
		failures.append("expected a FREEHOLD PowerFaction created by bootstrap")

	var faction_base_count := 0
	for child in scene.get_children():
		if child is FactionBase:
			faction_base_count += 1
	if faction_base_count != 2:
		failures.append("expected 2 FactionBase nodes spawned, got %d" % faction_base_count)

	var dominion_icon: CampaignFleetIcon = null
	var freehold_icon: CampaignFleetIcon = null
	for icon in scene.enemy_icons:
		if icon.fleet.faction == CampaignFleet.Faction.DOMINION:
			dominion_icon = icon
		elif icon.fleet.faction == CampaignFleet.Faction.FREEHOLD:
			freehold_icon = icon
	if dominion_icon == null or freehold_icon == null:
		failures.append("expected both a DOMINION and a FREEHOLD enemy icon spawned")
	elif dominion_icon.behavior_type != CampaignFleetIcon.BehaviorType.PATROL:
		failures.append("expected DOMINION fleet to use PATROL behavior at starting (non-hostile) reputation, got %s" % dominion_icon.behavior_type)

	if dominion_icon != null and freehold_icon != null:
		dominion_icon.global_position = freehold_icon.global_position
		for i in 5:
			await tree.physics_frame
		if campaign_state.active_skirmishes.size() != 1:
			failures.append("expected overlapping hostile power-faction icons to start a skirmish")
		else:
			var skirmish: Skirmish = campaign_state.active_skirmishes[0]
			var enemy_icons_before_resolve: int = scene.enemy_icons.size()
			skirmish.remaining_time = 0.01
			await tree.physics_frame
			await tree.physics_frame
			if campaign_state.active_skirmishes.size() != 0:
				failures.append("expected CampaignScene._physics_process to tick and resolve the skirmish")
			if scene.enemy_icons.size() != enemy_icons_before_resolve - 1:
				failures.append("expected enemy_icons to shrink by exactly 1 after the skirmish resolved, had %d before and %d after" % [enemy_icons_before_resolve, scene.enemy_icons.size()])
			for icon in scene.enemy_icons:
				if not is_instance_valid(icon):
					failures.append("expected CampaignScene to prune the freed loser icon from enemy_icons after skirmish_resolved, found a freed entry still present")
					break

	# Finding 1 coverage: if the fleet the Engage prompt is pointing at is
	# destroyed by an NPC skirmish while the prompt is open, the prompt must
	# hide itself and _pending_enemy_icon must be cleared -- pressing Engage
	# afterward must be a no-op, not a null-deref crash.
	var surviving_power_icon: CampaignFleetIcon = null
	var pirate_icon: CampaignFleetIcon = null
	for icon in scene.enemy_icons:
		if icon.fleet.faction == CampaignFleet.Faction.DOMINION or icon.fleet.faction == CampaignFleet.Faction.FREEHOLD:
			surviving_power_icon = icon
		elif icon.fleet.faction == CampaignFleet.Faction.PIRATE:
			pirate_icon = icon
	if surviving_power_icon == null or pirate_icon == null:
		failures.append("expected a surviving power-faction icon and a pirate icon to remain for the engage-prompt finding-1 test")
	else:
		scene.player_icon.global_position = surviving_power_icon.global_position
		for i in 5:
			await tree.physics_frame
		var engage_prompt_ctrl: Control = scene.get_node("EngagePrompt")
		if not engage_prompt_ctrl.visible:
			failures.append("expected EngagePrompt visible after player overlaps the power-faction icon")

		# A full-strength pirate fleet overlapping the already-damaged
		# survivor (it took winner_damage_fraction damage in the earlier
		# skirmish above) is stronger, so the survivor is the loser here --
		# i.e. the icon the Engage prompt is currently pointing at.
		pirate_icon.global_position = surviving_power_icon.global_position
		for i in 5:
			await tree.physics_frame
		if campaign_state.active_skirmishes.size() != 1:
			failures.append("expected the pirate/power-faction overlap to start a skirmish")
		else:
			var finding1_skirmish: Skirmish = campaign_state.active_skirmishes[0]
			var pending_is_loser := finding1_skirmish.icon_loser == surviving_power_icon
			if not pending_is_loser:
				failures.append("test setup assumption violated: expected the already-damaged survivor to lose this skirmish")
			finding1_skirmish.remaining_time = 0.01
			await tree.physics_frame
			await tree.physics_frame
			if pending_is_loser:
				if engage_prompt_ctrl.visible:
					failures.append("expected EngagePrompt to hide when its pending target icon was destroyed by a skirmish")
				if scene._pending_enemy_icon != null:
					failures.append("expected _pending_enemy_icon cleared when its icon was destroyed by a skirmish")
				var active_enemy_fleet_before = campaign_state.active_enemy_fleet
				engage_prompt_ctrl.get_node("EngageButton").pressed.emit()
				if campaign_state.active_enemy_fleet != active_enemy_fleet_before:
					failures.append("expected pressing Engage with a null pending icon to be a no-op, not a crash")

		# Move the player away from the skirmish site so it's no longer
		# overlapping pirate_icon (they were teleported to the same spot
		# above) -- otherwise the next block's teleport onto enemy_icons[0]
		# (which may now be pirate_icon, since the loser was pruned) would
		# be a no-op: area_entered only fires on a fresh overlap transition.
		scene.player_icon.global_position = Vector2(-5000, -5000)
		for i in 3:
			await tree.physics_frame

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

	# The Engage button above called change_scene_to_file("res://scenes/combat/combat_scene.tscn"),
	# which only takes effect several frames later (measured empirically: not yet applied
	# after 1 frame, applied by the 3rd) and becomes tree.current_scene once it fires. Left
	# alone, that CombatScene instance would keep running in the background for the rest of
	# the --script test run (see the identical cleanup in test_combat_scene.gd), and its
	# spawned ships would share the same PLAYER_GROUP/ENEMY_GROUP StringNames as any later
	# test's own CombatScene instances, corrupting their destruction-count logic. Poll a few
	# frames rather than assuming a fixed count, since this is deferred-queue timing, not a
	# guaranteed single-frame contract.
	var leaked_scene: Node = null
	for i in 10:
		await tree.process_frame
		if tree.current_scene != null and tree.current_scene != scene:
			leaked_scene = tree.current_scene
			break
	if leaked_scene != null:
		tree.current_scene = null
		if is_instance_valid(leaked_scene) and not leaked_scene.is_queued_for_deletion():
			leaked_scene.queue_free()
			await tree.process_frame

	return failures
