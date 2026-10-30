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
