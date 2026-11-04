extends RefCounted

# new_game() replaces the campaign scene's old bootstrap; the scene now calls it from _ready.
static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()
	campaign_state.new_game()
	await tree.process_frame

	if campaign_state.home_base_economy == null:
		failures.append("expected new_game to set CampaignState.home_base_economy")
	else:
		var home_role_types: Array = campaign_state.home_base_economy.slots.map(func(s): return s.role_type)
		if not home_role_types.has(EconomyRole.RoleType.TRADE_HUB):
			failures.append("expected home_base_economy to have a TRADE_HUB slot")
		if not home_role_types.has(EconomyRole.RoleType.REFINERY):
			failures.append("expected home_base_economy to have a REFINERY slot")

	if campaign_state.player_fleet == null:
		failures.append("expected new_game to set CampaignState.player_fleet")
	else:
		var player_types: Array = campaign_state.player_fleet.ship_compositions.map(func(c): return ShipType.kind_of(c))
		if not player_types.has(ShipType.Kind.CORVETTE):
			failures.append("expected the player's starting fleet to include a CORVETTE")
		if not player_types.has(ShipType.Kind.FREIGHTER):
			failures.append("expected the player's starting fleet to include a FREIGHTER")
		if not player_types.has(ShipType.Kind.CAPITAL):
			failures.append("expected the player's starting fleet to include a CAPITAL")
		if campaign_state.player_fleet.flagship_index() == -1:
			failures.append("expected the player's starting fleet to have a flagship")

	var dominion_stations: Array = campaign_state.stations_of(CampaignFleet.Faction.DOMINION)
	if dominion_stations.is_empty() or dominion_stations[0].economy == null:
		failures.append("expected the first Dominion station to have an economy")
	else:
		var role_types: Array = dominion_stations[0].economy.slots.map(func(s): return s.role_type)
		if not role_types.has(EconomyRole.RoleType.INDUSTRIAL):
			failures.append("expected the first Dominion station to have an INDUSTRIAL slot, got %s" % [role_types])

	var freehold_stations: Array = campaign_state.stations_of(CampaignFleet.Faction.FREEHOLD)
	var freehold_miner: StationData = null
	for station in freehold_stations:
		var role_types: Array = station.economy.slots.map(func(s): return s.role_type)
		if role_types.has(EconomyRole.RoleType.MINING) and not role_types.has(EconomyRole.RoleType.INDUSTRIAL):
			freehold_miner = station
			break
	if freehold_miner == null:
		failures.append("expected a Freehold station with a MINING slot and no Ore consumer")
	else:
		# One economy tick grows the MINING slot's Ore.
		var ore_before: float = freehold_miner.economy.stock.get(Commodity.Type.ORE, 0.0)
		campaign_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
		var ore_after: float = freehold_miner.economy.stock.get(Commodity.Type.ORE, 0.0)
		if ore_after <= ore_before:
			failures.append("expected tick_economy to grow %s's Ore stock, before=%s after=%s" % [freehold_miner.id, ore_before, ore_after])

	campaign_state.reset()
	return failures
