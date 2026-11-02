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
	# the tree on area_entered -- clear that incidental pause so the economy
	# tick loop below actually progresses.
	tree.paused = false

	if campaign_state.home_base_economy == null:
		failures.append("expected bootstrap to set CampaignState.home_base_economy")
	else:
		var home_role_types: Array = campaign_state.home_base_economy.slots.map(func(s): return s.role_type)
		if not home_role_types.has(EconomyRole.RoleType.TRADE_HUB):
			failures.append("expected home_base_economy to have a TRADE_HUB slot")
		if not home_role_types.has(EconomyRole.RoleType.REFINERY):
			failures.append("expected home_base_economy to have a REFINERY slot")

	if campaign_state.player_fleet == null:
		failures.append("expected bootstrap to set CampaignState.player_fleet")
	else:
		var player_types: Array = campaign_state.player_fleet.ship_compositions.map(func(c): return ShipType.kind_of(c))
		if not player_types.has(ShipType.Kind.CORVETTE):
			failures.append("expected the player's bootstrap fleet to include a CORVETTE")
		if not player_types.has(ShipType.Kind.FREIGHTER):
			failures.append("expected the player's bootstrap fleet to include a FREIGHTER")
		if not player_types.has(ShipType.Kind.CAPITAL):
			failures.append("expected the player's bootstrap fleet to include a CAPITAL")

	var dominion: PowerFaction = null
	var freehold: PowerFaction = null
	for faction in campaign_state.factions:
		if faction.faction_enum == CampaignFleet.Faction.DOMINION:
			dominion = faction
		elif faction.faction_enum == CampaignFleet.Faction.FREEHOLD:
			freehold = faction

	if dominion == null or dominion.economy == null:
		failures.append("expected the Dominion PowerFaction to have an economy set by bootstrap")
	else:
		var role_types: Array = dominion.economy.slots.map(func(s): return s.role_type)
		if not role_types.has(EconomyRole.RoleType.INDUSTRIAL) or not role_types.has(EconomyRole.RoleType.POPULATION):
			failures.append("expected Dominion economy to have INDUSTRIAL and POPULATION slots, got %s" % [role_types])

	if freehold == null or freehold.economy == null:
		failures.append("expected the Freehold PowerFaction to have an economy set by bootstrap")
	else:
		var role_types: Array = freehold.economy.slots.map(func(s): return s.role_type)
		if not role_types.has(EconomyRole.RoleType.MINING) or not role_types.has(EconomyRole.RoleType.AGRICULTURE):
			failures.append("expected Freehold economy to have MINING and AGRICULTURE slots, got %s" % [role_types])

	# _physics_process ticks the economy: a MINING slot should accrue stock
	# once enough physics frames cover the tick interval.
	if freehold != null and freehold.economy != null:
		var ore_before: float = freehold.economy.stock.get(Commodity.Type.ORE, 0.0)
		var elapsed := 0.0
		while elapsed < CampaignState.ECONOMY_TICK_INTERVAL + 1.0:
			# The player fleet spawned docked at HomeBase; its area_entered signal
			# can fire a frame late and auto-pause the tree mid-loop. Clear it each
			# iteration so the economy keeps ticking regardless of that timing.
			tree.paused = false
			await tree.physics_frame
			elapsed += 1.0 / 60.0
		var ore_after: float = freehold.economy.stock.get(Commodity.Type.ORE, 0.0)
		if ore_after <= ore_before:
			failures.append("expected CampaignScene._physics_process to tick the economy and grow Freehold's Ore stock, before=%s after=%s" % [ore_before, ore_after])

	campaign_state.reset()
	scene.queue_free()
	return failures
