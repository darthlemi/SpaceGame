extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(scene)
	# The player fleet spawns already docked at HomeBase, which now auto-pauses
	# the tree on area_entered. That signal fires on a physics step rather than
	# immediately, so move the icon away before any frame elapses to avoid the
	# race entirely instead of reactively clearing a pause that might land at
	# an unpredictable point later in this test.
	scene.player_icon.global_position = Vector2(-9000, -9000)
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
	var dominion_trader_icon: CampaignFleetIcon = null
	var freehold_trader_icon: CampaignFleetIcon = null
	for icon in scene.enemy_icons:
		if icon.fleet.faction == CampaignFleet.Faction.DOMINION and icon.fleet.role == CampaignFleet.Role.COMBAT:
			dominion_icon = icon
		elif icon.fleet.faction == CampaignFleet.Faction.FREEHOLD and icon.fleet.role == CampaignFleet.Role.COMBAT:
			freehold_icon = icon
		elif icon.fleet.faction == CampaignFleet.Faction.DOMINION and icon.fleet.role == CampaignFleet.Role.TRADER:
			dominion_trader_icon = icon
		elif icon.fleet.faction == CampaignFleet.Faction.FREEHOLD and icon.fleet.role == CampaignFleet.Role.TRADER:
			freehold_trader_icon = icon
	if dominion_icon == null or freehold_icon == null:
		failures.append("expected both a DOMINION and a FREEHOLD combat-role enemy icon spawned")
	elif dominion_icon.behavior_type != CampaignFleetIcon.BehaviorType.PATROL:
		failures.append("expected DOMINION combat fleet to use PATROL behavior at starting (non-hostile) reputation, got %s" % dominion_icon.behavior_type)
	if dominion_trader_icon == null or freehold_trader_icon == null:
		failures.append("expected both a DOMINION and a FREEHOLD trader-role enemy icon spawned")
	elif dominion_trader_icon.behavior_type != CampaignFleetIcon.BehaviorType.TRADER:
		failures.append("expected DOMINION trader fleet to use TRADER behavior, got %s" % dominion_trader_icon.behavior_type)

	if dominion_trader_icon != null:
		var dominion_power_faction: PowerFaction = null
		for faction in campaign_state.factions:
			if faction.faction_enum == CampaignFleet.Faction.DOMINION:
				dominion_power_faction = faction
		if dominion_power_faction == null:
			failures.append("expected a DOMINION PowerFaction to look up its base_position")
		else:
			# Teleport directly onto the away endpoint (Dominion's dock point
			# near HomeBase -- not necessarily the exact HOME_BASE_POSITION
			# pixel, see Fix 2) rather than waiting for the icon to travel
			# there under its own speed -- this mirrors the
			# teleport-then-wait-a-few-frames pattern used for the route_icon
			# trader_arrived coverage in test_campaign_fleet_icon.gd. Arriving
			# at HomeBase triggers trader_arrived(false), which runs
			# CampaignState._unload_and_load_deficit: it loads Dominion's
			# deficit commodities (ORE/FUEL/FOOD) out of home_base_economy.stock
			# into the fleet's cargo -- not the surplus path.
			dominion_trader_icon.global_position = dominion_trader_icon.route_away_point()
			for i in 5:
				await tree.physics_frame
			if dominion_trader_icon.fleet.cargo_total() <= 0.0:
				failures.append("expected the DOMINION trader icon to have loaded deficit cargo after reaching HomeBase")

			# Closing the loop: teleporting back to the faction base triggers
			# trader_arrived(true), running CampaignState._unload_and_load_surplus,
			# which must dump the deficit cargo just picked up at HomeBase into
			# the faction's own economy.stock (the actual resupply) before
			# topping cargo back up with any surplus commodities. Snapshot the
			# carried cargo and the faction's stock for those commodities
			# beforehand, then confirm delivery actually landed in stock.
			var cargo_before_delivery: Dictionary = dominion_trader_icon.fleet.cargo.duplicate()
			var stock_before_delivery: Dictionary = {}
			for commodity in cargo_before_delivery:
				stock_before_delivery[commodity] = dominion_power_faction.economy.stock.get(commodity, 0.0)

			dominion_trader_icon.global_position = dominion_power_faction.base_position
			for i in 5:
				await tree.physics_frame

			var delivered_to_faction_stock := false
			for commodity in cargo_before_delivery:
				if cargo_before_delivery[commodity] > 0.0 and dominion_power_faction.economy.stock.get(commodity, 0.0) > stock_before_delivery[commodity]:
					delivered_to_faction_stock = true
			if not delivered_to_faction_stock:
				failures.append("expected the DOMINION trader icon to deliver its carried cargo into the faction's own economy.stock on returning home")

			# Teleporting the trader icon onto HOME_BASE_POSITION above also
			# overlapped the stationary player_icon (which sits there for the
			# whole test), an unavoidable side effect of this test's placement
			# that opens the Engage prompt against the trader icon. Reset that
			# state so it doesn't leak into the EngagePrompt/_pending_enemy_icon
			# assertions later in this test.
			scene._pending_enemy_icon = null
			scene.engage_prompt.visible = false

			# FleetAllocationPolicy.REALLOCATE_TO_COMBAT can flip a TRADER-role
			# faction hauler back to COMBAT via fleet_role_changed. Since
			# TRADER-role icons start with player_target == null (the
			# exemption above), _on_fleet_role_changed must re-establish
			# player_target when the new role is COMBAT, or a reallocated
			# fleet could never detect/chase the player (PirateBehavior's
			# intercept check is null-guarded and silently no-ops).
			if freehold_trader_icon != null:
				if freehold_trader_icon.player_target != null:
					failures.append("expected a freshly-spawned TRADER-role icon to have a null player_target")
				freehold_trader_icon.fleet.role = CampaignFleet.Role.COMBAT
				scene._on_fleet_role_changed(freehold_trader_icon.fleet)
				if freehold_trader_icon.player_target != scene.player_icon:
					failures.append("expected _on_fleet_role_changed to re-establish player_target when a fleet's role changes to COMBAT")
				# Revert back to TRADER so this icon doesn't masquerade as a
				# second COMBAT-role FREEHOLD icon for the surviving_power_icon
				# lookup later in this test (which assumes exactly one COMBAT
				# icon per power faction).
				freehold_trader_icon.fleet.role = CampaignFleet.Role.TRADER
				scene._on_fleet_role_changed(freehold_trader_icon.fleet)
				if freehold_trader_icon.player_target != null:
					failures.append("expected _on_fleet_role_changed to clear player_target when a fleet's role changes back to TRADER")

			# The DOMINION/FREEHOLD trader-role icons no longer have a
			# player_target (they're running a scripted route, not evading the
			# player), so they roam autonomously toward their route endpoints
			# for the rest of this test's duration. Left alone they can
			# wander into incidental overlaps with the other icons the
			# skirmish/engage-prompt sections below stage deliberately --
			# park them out of the way now that this block's checks are done.
			dominion_trader_icon.global_position = Vector2(-9000, -9000)
			if freehold_trader_icon != null:
				freehold_trader_icon.global_position = Vector2(-9500, -9500)

	if dominion_icon != null and freehold_icon != null:
		# dominion_icon and freehold_icon start with exactly equal strength, so
		# without a tiebreaker the "winner" of this overlap depends on which
		# icon's area_entered signal happens to fire first -- order that now
		# shifts run-to-run because this task added two more Area2D icons to
		# the scene (the trader-role haulers). Nudge freehold_icon strictly
		# weaker so the outcome (dominion wins) is deterministic regardless of
		# signal order, matching what the rest of this block already assumes.
		freehold_icon.fleet.apply_fractional_damage(0.01)
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
		if (icon.fleet.faction == CampaignFleet.Faction.DOMINION or icon.fleet.faction == CampaignFleet.Faction.FREEHOLD) and icon.fleet.role == CampaignFleet.Role.COMBAT:
			surviving_power_icon = icon
		elif icon.fleet.faction == CampaignFleet.Faction.PIRATE:
			pirate_icon = icon
	if surviving_power_icon == null or pirate_icon == null:
		failures.append("expected a surviving power-faction icon and a pirate icon to remain for the engage-prompt finding-1 test")
	else:
		scene.player_icon.global_position = surviving_power_icon.global_position
		for i in 5:
			await tree.physics_frame
		var engage_prompt_ctrl: Control = scene.get_node("UILayer/EngagePrompt")
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

	var prompt: Control = scene.get_node("UILayer/EngagePrompt")
	if not prompt.visible:
		failures.append("expected EngagePrompt visible after player icon overlaps an enemy icon")

	# Fix 3 coverage: departing the overlap must hide the Engage prompt, not
	# just clear _pending_enemy_icon -- otherwise the prompt stays visible
	# forever (and can swallow clicks) after the first overlapping icon
	# (e.g. a faction hauler docking near HomeBase) moves on.
	scene.player_icon.global_position = Vector2(-7000, -7000)
	for i in 5:
		await tree.physics_frame
	if prompt.visible:
		failures.append("expected EngagePrompt to hide after the overlapping icon departs")
	if scene._pending_enemy_icon != null:
		failures.append("expected _pending_enemy_icon cleared after the overlapping icon departs")

	# Re-establish the overlap so the Engage-button assertion below still
	# has a valid pending target.
	scene.player_icon.global_position = target_icon.global_position
	for i in 5:
		await tree.physics_frame
	if not prompt.visible:
		failures.append("expected EngagePrompt visible again after re-overlapping the enemy icon")

	prompt.get_node("EngageButton").pressed.emit()
	if campaign_state.active_enemy_fleet != target_icon.fleet:
		failures.append("expected Engage button to call CampaignState.start_engagement with the overlapped fleet")

	# Fix 2 coverage: Dominion's and Freehold's TRADER-role haulers must be
	# routed to distinct dock points near HomeBase, not the identical pixel --
	# otherwise their arrival_radius (10) and icon collision radius (24)
	# guarantee an overlap, triggering a hostile skirmish between two
	# haulers that should never fight each other.
	if dominion_trader_icon != null and freehold_trader_icon != null:
		var dominion_dock := dominion_trader_icon.route_away_point()
		var freehold_dock := freehold_trader_icon.route_away_point()
		if dominion_dock == freehold_dock:
			failures.append("expected Dominion's and Freehold's trader haulers to dock at distinct points near HomeBase")
		elif dominion_dock.distance_to(freehold_dock) < 60.0:
			failures.append("expected the two factions' dock points to be far enough apart to avoid mutual collision, got distance=%s" % dominion_dock.distance_to(freehold_dock))

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

	# Fix 4 coverage: CampaignScene._ready()'s loot-panel wiring -- when
	# CampaignState.pending_loot_fleet is set before the scene loads, _ready()
	# must open the LootPanel for it and clear the pending flag. Existing
	# tests cover LootPanel.open_for and CampaignState.pending_loot_fleet in
	# isolation, but not this specific wiring seam between them.
	campaign_state.reset()
	var loot_fleet := CampaignFleet.new()
	loot_fleet.faction = CampaignFleet.Faction.DOMINION
	loot_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 0.0, "max_shield": 50.0, "current_shield": 0.0}]
	loot_fleet.cargo = {Commodity.Type.ORE: 5.0}
	campaign_state.pending_loot_fleet = loot_fleet

	var loot_scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(loot_scene)
	await tree.process_frame
	tree.paused = false

	if not loot_scene.loot_panel.visible:
		failures.append("expected CampaignScene._ready() to open the LootPanel for a pending_loot_fleet set before the scene loaded")
	if campaign_state.pending_loot_fleet != null:
		failures.append("expected CampaignScene._ready() to clear pending_loot_fleet after opening the LootPanel for it")

	campaign_state.reset()
	loot_scene.queue_free()

	return failures
