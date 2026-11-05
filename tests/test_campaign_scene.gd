extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(scene)
	# The player spawns on the home station; park it well clear so no incidental overlap
	# (with the station or with icons this test stages in haven) fires before a check wants it.
	scene.player_icon.position = Vector2(-9000, -9000)
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

	var station_count := 0
	for layer in scene.layers.values():
		for child in layer.get_children():
			if child is CampaignStation:
				station_count += 1
	if station_count != campaign_state.galaxy.stations.size():
		failures.append("expected one CampaignStation node per galaxy station (%d), got %d" % [campaign_state.galaxy.stations.size(), station_count])

	var dominion_icon := _station_icon(scene, campaign_state, "kestrel_picket", CampaignFleet.Role.COMBAT)
	var freehold_icon := _station_icon(scene, campaign_state, "wexford_outpost", CampaignFleet.Role.COMBAT)
	var dominion_trader_icon := _station_icon(scene, campaign_state, "aurum_spire", CampaignFleet.Role.TRADER)
	var freehold_trader_icon := _station_icon(scene, campaign_state, "wexford_outpost", CampaignFleet.Role.TRADER)
	var pirate_icon := _station_icon(scene, campaign_state, "marrow_hideout", CampaignFleet.Role.COMBAT)
	if dominion_icon == null or freehold_icon == null:
		failures.append("expected both a DOMINION and a FREEHOLD combat-role enemy icon spawned")
	elif dominion_icon.behavior_type != CampaignFleetIcon.BehaviorType.PATROL:
		failures.append("expected DOMINION combat fleet to use PATROL behavior at starting (non-hostile) reputation, got %s" % dominion_icon.behavior_type)
	if dominion_trader_icon == null or freehold_trader_icon == null:
		failures.append("expected both a DOMINION and a FREEHOLD trader-role enemy icon spawned")
	elif dominion_trader_icon.behavior_type != CampaignFleetIcon.BehaviorType.TRADER:
		failures.append("expected DOMINION trader fleet to use TRADER behavior, got %s" % dominion_trader_icon.behavior_type)

	if dominion_trader_icon != null:
		# Aurum Spire's hauler trades with the neutral Aurum Bazaar in the same system. Teleport
		# it onto the bazaar: arriving runs CampaignState.run_npc_trade_at, which loads what its
		# home station needs out of the bazaar's surplus (here, Ore above TARGET_STOCK).
		var galaxy: Galaxy = campaign_state.galaxy
		var bazaar: StationData = galaxy.station("aurum_bazaar")
		var spire: StationData = galaxy.station("aurum_spire")
		bazaar.economy.stock[Commodity.Type.ORE] = Commodity.TARGET_STOCK[Commodity.Type.ORE] + 40.0
		dominion_trader_icon.fleet.dest_station_id = bazaar.id
		scene._aim_trader(dominion_trader_icon)
		dominion_trader_icon.position = bazaar.position
		for i in 5:
			await tree.physics_frame
		if dominion_trader_icon.fleet.cargo.get(Commodity.Type.ORE, 0.0) <= 0.0:
			failures.append("expected the DOMINION trader icon to have loaded cargo its home needs after reaching Aurum Bazaar")
		if dominion_trader_icon.fleet.dest_station_id != spire.id:
			failures.append("expected the DOMINION trader to head home after the away stop, got '%s'" % dominion_trader_icon.fleet.dest_station_id)

		# Closing the loop: arriving home must unload the carried cargo into the home station's
		# own stock (the actual resupply) before loading surplus again.
		var cargo_before_delivery: Dictionary = dominion_trader_icon.fleet.cargo.duplicate()
		var stock_before_delivery: Dictionary = {}
		for commodity in cargo_before_delivery:
			stock_before_delivery[commodity] = spire.economy.stock.get(commodity, 0.0)
		dominion_trader_icon.position = spire.position
		for i in 5:
			await tree.physics_frame
		var delivered_to_home_stock := false
		for commodity in cargo_before_delivery:
			if cargo_before_delivery[commodity] > 0.0 and spire.economy.stock.get(commodity, 0.0) > stock_before_delivery[commodity]:
				delivered_to_home_stock = true
		if not delivered_to_home_stock:
			failures.append("expected the DOMINION trader icon to deliver its carried cargo into its home station's stock on returning home")

	# FleetAllocationPolicy.REALLOCATE_TO_COMBAT can flip a faction hauler to COMBAT via
	# fleet_role_changed. Haulers start with no player_target, so _on_fleet_role_changed must
	# set it for a COMBAT role (or a reallocated fleet could never chase the player) and clear
	# it again for TRADER.
	if freehold_trader_icon != null:
		if freehold_trader_icon.player_target != null:
			failures.append("expected a freshly-spawned TRADER-role icon to have a null player_target")
		freehold_trader_icon.fleet.role = CampaignFleet.Role.COMBAT
		scene._on_fleet_role_changed(freehold_trader_icon.fleet)
		if freehold_trader_icon.player_target != scene.player_icon:
			failures.append("expected _on_fleet_role_changed to re-establish player_target when a fleet's role changes to COMBAT")
		freehold_trader_icon.fleet.role = CampaignFleet.Role.TRADER
		scene._on_fleet_role_changed(freehold_trader_icon.fleet)
		if freehold_trader_icon.player_target != null:
			failures.append("expected _on_fleet_role_changed to clear player_target when a fleet's role changes back to TRADER")

	# The interaction checks below need the fleets in the player's system: stage them in haven,
	# clear of its two stations.
	if dominion_icon != null and freehold_icon != null:
		_move_to_system(scene, dominion_icon, "haven")
		_move_to_system(scene, freehold_icon, "haven")
		# Equal fleets would make the winner depend on signal order; make freehold strictly weaker.
		freehold_icon.fleet.ship_compositions.assign(dominion_icon.fleet.ship_compositions.duplicate(true))
		freehold_icon.fleet.apply_fractional_damage(0.01)
		dominion_icon.position = Vector2(900, 250)
		freehold_icon.position = dominion_icon.position
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

	# Finding 1 coverage: if the fleet the Engage prompt points at is destroyed by an NPC
	# skirmish while the prompt is open, the prompt must hide and _pending_enemy_icon must be
	# cleared -- pressing Engage afterward must be a no-op, not a null-deref crash.
	var surviving_power_icon: CampaignFleetIcon = dominion_icon if is_instance_valid(dominion_icon) else null
	if surviving_power_icon == null or pirate_icon == null:
		failures.append("expected a surviving power-faction icon and a pirate icon to remain for the engage-prompt finding-1 test")
	else:
		_move_to_system(scene, pirate_icon, "haven")
		# Strictly stronger than the damaged survivor, so the survivor is the loser below.
		var stronger: Array[Dictionary] = surviving_power_icon.fleet.ship_compositions.duplicate(true)
		stronger.append(ShipType.new_composition(ShipType.Kind.CORVETTE))
		pirate_icon.fleet.ship_compositions.assign(stronger)
		pirate_icon.position = Vector2(-6000, -6000)
		# Interactions only fire when the overlap is the player's deliberate click target.
		scene._travel_target = surviving_power_icon
		scene.player_icon.position = surviving_power_icon.position
		for i in 5:
			await tree.physics_frame
		var engage_prompt_ctrl: Control = scene.get_node("UILayer/EngagePrompt")
		if not engage_prompt_ctrl.visible:
			failures.append("expected EngagePrompt visible after player overlaps the power-faction icon")
		tree.paused = false

		pirate_icon.position = surviving_power_icon.position
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

		# Leave the skirmish site so the next overlap is a fresh area_entered transition.
		scene.player_icon.position = Vector2(-5000, -5000)
		for i in 3:
			await tree.physics_frame

	# Simulate clicking the pirate to travel there: set _travel_target (what a real click sets),
	# overlap it and let physics process the gated area_entered signal.
	if pirate_icon != null and is_instance_valid(pirate_icon):
		var target_icon: CampaignFleetIcon = pirate_icon
		scene._travel_target = target_icon
		scene.player_icon.position = target_icon.position
		for i in 5:
			await tree.physics_frame

		var prompt: Control = scene.get_node("UILayer/EngagePrompt")
		if not prompt.visible:
			failures.append("expected EngagePrompt visible after player icon overlaps an enemy icon")
		tree.paused = false

		# Fix 3 coverage: departing the overlap must hide the Engage prompt, not just clear
		# _pending_enemy_icon, or the prompt stays up (and swallows clicks) forever.
		scene.player_icon.position = Vector2(-7000, -7000)
		for i in 5:
			await tree.physics_frame
		if prompt.visible:
			failures.append("expected EngagePrompt to hide after the overlapping icon departs")
		if scene._pending_enemy_icon != null:
			failures.append("expected _pending_enemy_icon cleared after the overlapping icon departs")

		# Re-establish the overlap so the Engage-button assertion has a valid pending target.
		scene._travel_target = target_icon
		scene.player_icon.position = target_icon.position
		for i in 5:
			await tree.physics_frame
		if not prompt.visible:
			failures.append("expected EngagePrompt visible again after re-overlapping the enemy icon")
		tree.paused = false

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

	# Fix 4 coverage: CampaignScene._ready()'s loot-panel wiring -- when
	# CampaignState.pending_loot is set before the scene loads, _ready() must open the
	# LootPanel for it and clear the pending flag.
	campaign_state.new_game()
	var loot_offer := LootOffer.new()
	loot_offer.cargo = {Commodity.Type.ORE: 5.0}
	campaign_state.pending_loot = loot_offer

	var loot_scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(loot_scene)
	await tree.process_frame
	tree.paused = false

	if not loot_scene.loot_panel.visible:
		failures.append("expected CampaignScene._ready() to open the LootPanel for a pending_loot set before the scene loaded")
	if campaign_state.pending_loot != null:
		failures.append("expected CampaignScene._ready() to clear pending_loot after opening the LootPanel for it")

	campaign_state.reset()
	loot_scene.queue_free()

	# Review Focus 1: Engage is blocked while neither deploy set has an armed ship.
	campaign_state.reset()
	var blocked_scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(blocked_scene)
	blocked_scene.player_icon.position = Vector2(-9000, -9000)
	await tree.process_frame
	tree.paused = false
	var blocked_prompt: Control = blocked_scene.get_node("UILayer/EngagePrompt")
	var blocked_button: Button = blocked_prompt.get_node("EngageButton")
	var blocked_label: Label = blocked_prompt.get_node("Label")
	var blocked_icon: CampaignFleetIcon = blocked_scene.enemy_icons[0]
	campaign_state.player_fleet.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.FREIGHTER)])
	blocked_icon.fleet.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.FREIGHTER)])
	blocked_scene._trigger_arrival(blocked_icon)
	if not blocked_prompt.visible or not blocked_button.disabled or blocked_label.text != "Neither fleet can fight":
		failures.append("unarmed engage: expected the prompt shown with Engage disabled and 'Neither fleet can fight', got visible=%s disabled=%s '%s'" % [blocked_prompt.visible, blocked_button.disabled, blocked_label.text])
	blocked_prompt.get_node("DisengageButton").pressed.emit()
	# One armed side is enough to fight; the prompt must not keep the blocked state.
	blocked_icon.fleet.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	blocked_scene._trigger_arrival(blocked_icon)
	if not blocked_prompt.visible or blocked_button.disabled or blocked_label.text == "Neither fleet can fight":
		failures.append("armed engage: expected Engage enabled with the normal prompt, got visible=%s disabled=%s '%s'" % [blocked_prompt.visible, blocked_button.disabled, blocked_label.text])
	blocked_prompt.get_node("DisengageButton").pressed.emit()
	tree.paused = false
	campaign_state.reset()
	blocked_scene.queue_free()

	return failures

static func _station_icon(scene: Node2D, campaign_state, station_id: String, role: CampaignFleet.Role) -> CampaignFleetIcon:
	var fleets: Array[CampaignFleet] = campaign_state.station_fleets(campaign_state.galaxy.station(station_id), role)
	for icon in scene.enemy_icons:
		if is_instance_valid(icon) and not fleets.is_empty() and icon.fleet == fleets[0]:
			return icon
	return null

static func _move_to_system(scene: Node2D, icon: CampaignFleetIcon, system_id: String) -> void:
	icon.reparent(scene.layer_for(system_id))
	icon.fleet.system_id = system_id
