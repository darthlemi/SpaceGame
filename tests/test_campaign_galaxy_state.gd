extends RefCounted

const CampaignStateScript = preload("res://scripts/campaign/campaign_state.gd")
const COMBAT := CampaignFleet.Role.COMBAT
const TRADER := CampaignFleet.Role.TRADER

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	_check_new_game(failures)
	_check_fleet_counts(failures)
	_check_hostility(failures)
	_check_respawn(failures)
	_check_threat(failures)
	_check_growth(failures)
	_check_trade_at(failures)
	_check_next_destination(failures)
	_check_trade_range(failures)
	_check_crew_refill(failures)
	await tree.process_frame
	return failures

static func _fresh_state() -> CampaignStateScript:
	var state := CampaignStateScript.new()
	state.rng.seed = 1
	state.new_game()
	return state

static func _strong_pirate(system_id: String) -> CampaignFleet:
	var fleet := CampaignFleet.new()
	fleet.faction = CampaignFleet.Faction.PIRATE
	fleet.system_id = system_id
	fleet.ship_compositions.assign([{"max_hp": 1000.0, "current_hp": 1000.0, "max_shield": 0.0, "current_shield": 0.0}])
	return fleet

static func _extra_station(id: String, system_id: String, owner: CampaignFleet.Faction, pos: Vector2, stock: Dictionary) -> StationData:
	var st := StationData.new()
	st.id = id
	st.system_id = system_id
	st.owner = owner
	st.position = pos
	st.economy = BaseEconomy.new()
	st.economy.stock = stock
	return st

static func _check_new_game(failures: Array[String]) -> void:
	var state := _fresh_state()
	var home: StationData = state.galaxy.home_station()
	var player: CampaignFleet = state.player_fleet
	if player == null:
		failures.append("new_game: expected a player fleet")
	else:
		if player.system_id != "haven":
			failures.append("new_game: expected the player in haven, got '%s'" % player.system_id)
		if player.position != home.position:
			failures.append("new_game: expected the player at the home station %s, got %s" % [home.position, player.position])
		if not is_equal_approx(player.fuel_amount(), 30.0):
			failures.append("new_game: expected 30 fuel, got %s" % player.fuel_amount())
	if state.home_base_economy == null or state.home_base_economy != home.economy:
		failures.append("new_game: expected home_base_economy to be the home station's economy")
	var seeded := true
	for st in state.galaxy.stations:
		if not is_equal_approx(st.economy.stock.get(Commodity.Type.ORE, 0.0), Commodity.TARGET_STOCK[Commodity.Type.ORE]):
			seeded = false
		if not is_equal_approx(st.economy.population, st.economy.population_capacity() * CampaignStateScript.STARTING_POPULATION_FRACTION):
			seeded = false
		if not is_equal_approx(st.economy.crew_pool, st.economy.crew_pool_cap()):
			seeded = false
	if not seeded:
		failures.append("new_game: expected every station seeded with target stock, 0.75 population and a full crew pool")
	if state.factions.size() != 2 or not state.factions_at_war:
		failures.append("new_game: expected two warring power factions, got %d" % state.factions.size())
	elif state.power_faction_for(CampaignFleet.Faction.DOMINION) == null or state.power_faction_for(CampaignFleet.Faction.FREEHOLD) == null:
		failures.append("power_faction_for: expected Dominion and Freehold")
	state.free()

static func _check_fleet_counts(failures: Array[String]) -> void:
	var state := _fresh_state()
	var expected := 0
	for st in state.galaxy.stations:
		for role in st.fleet_quota:
			expected += st.fleet_quota[role]
	if state.enemy_fleets.size() != expected:
		failures.append("new_game: expected %d quota fleets, got %d" % [expected, state.enemy_fleets.size()])
	for fleet in state.enemy_fleets:
		var st: StationData = state.galaxy.station(fleet.home_station_id)
		if st == null or fleet.system_id != st.system_id:
			failures.append("new_game: expected fleet homed at '%s' in its station's system, got '%s'" % [fleet.home_station_id, fleet.system_id])
			break
		if fleet.speed != CampaignStateScript.NPC_SPEED[fleet.role]:
			failures.append("spawn_station_fleet: expected NPC_SPEED for role %d, got %s" % [fleet.role, fleet.speed])
			break
		if not is_equal_approx(fleet.fuel_amount(), CampaignStateScript.NPC_FUEL_TARGET_JUMPS * JumpRules.jump_cost(fleet)):
			failures.append("spawn_station_fleet: expected %d jumps of fuel, got %s" % [CampaignStateScript.NPC_FUEL_TARGET_JUMPS, fleet.fuel_amount()])
			break
		if fleet.position.distance_to(st.position) > 40.0 * sqrt(2.0) + 0.01:
			failures.append("spawn_station_fleet: expected the fleet within 40 of its station on each axis")
			break
	var bazaar: StationData = state.galaxy.station("aurum_bazaar")
	var bazaar_traders: Array[CampaignFleet] = state.station_fleets(bazaar, TRADER)
	if bazaar_traders.size() != 1 or bazaar_traders[0].faction != CampaignFleet.Faction.TRADER:
		failures.append("new_game: expected one TRADER-faction trader at a neutral station")
	var tier5_pirates := 0
	for fleet in state.enemy_fleets:
		if fleet.faction == CampaignFleet.Faction.PIRATE and state.galaxy.system(fleet.system_id).tier == 5:
			tier5_pirates += 1
			if fleet.ship_compositions.size() != 3:
				failures.append("new_game: expected a tier-5 pirate fleet of 3 ships, got %d" % fleet.ship_compositions.size())
	if tier5_pirates == 0:
		failures.append("new_game: expected tier-5 pirate fleets")
	var pirate_stations: Array[StationData] = state.stations_of(CampaignFleet.Faction.PIRATE)
	if pirate_stations.is_empty() or pirate_stations.any(func(s): return s.owner != CampaignFleet.Faction.PIRATE):
		failures.append("stations_of: expected only pirate stations")
	if CampaignStateScript.fleet_faction_for(CampaignFleet.Faction.NEUTRAL, COMBAT) != CampaignFleet.Faction.NEUTRAL:
		failures.append("fleet_faction_for: expected a neutral patrol to be NEUTRAL")
	if CampaignStateScript.fleet_faction_for(CampaignFleet.Faction.DOMINION, TRADER) != CampaignFleet.Faction.DOMINION:
		failures.append("fleet_faction_for: expected a Dominion trader to stay DOMINION")
	if CampaignStateScript.fleet_faction_for(CampaignFleet.Faction.PIRATE, COMBAT) != CampaignFleet.Faction.PIRATE:
		failures.append("fleet_faction_for: expected a pirate fleet to stay PIRATE")
	state.free()

static func _check_hostility(failures: Array[String]) -> void:
	var state := _fresh_state()
	var pirate := _strong_pirate("haven")
	var dominion := CampaignFleet.new()
	dominion.faction = CampaignFleet.Faction.DOMINION
	var patrol := CampaignFleet.new()
	patrol.faction = CampaignFleet.Faction.NEUTRAL
	if not state.is_hostile_to_player(pirate):
		failures.append("is_hostile_to_player: expected pirates hostile")
	if state.is_hostile_to_player(dominion) or state.is_hostile_to_player(patrol):
		failures.append("is_hostile_to_player: expected Dominion at 60 and neutrals friendly")
	state.power_faction_for(CampaignFleet.Faction.DOMINION).reputation = CampaignStateScript.HOSTILE_REPUTATION_THRESHOLD - 1.0
	if not state.is_hostile_to_player(dominion):
		failures.append("is_hostile_to_player: expected Dominion hostile below the threshold")
	state.free()

static func _check_respawn(failures: Array[String]) -> void:
	var state := _fresh_state()
	var den: StationData = state.galaxy.station("southdeep_den")
	for fleet in state.station_fleets(den, COMBAT):
		state.enemy_fleets.erase(fleet)
	state.tick_economy(CampaignStateScript.FLEET_RESPAWN_DELAY - CampaignStateScript.ECONOMY_TICK_INTERVAL)
	if state.station_fleets(den, COMBAT).size() != 0:
		failures.append("respawn: expected no fleet back before FLEET_RESPAWN_DELAY, got %d" % state.station_fleets(den, COMBAT).size())
	state.tick_economy(CampaignStateScript.ECONOMY_TICK_INTERVAL * 2.0)
	var back: Array[CampaignFleet] = state.station_fleets(den, COMBAT)
	if back.size() != 2:
		failures.append("respawn: expected 2 combat fleets back after the delay, got %d" % back.size())
	elif back[0].system_id != "southdeep" or back[0].faction != CampaignFleet.Faction.PIRATE:
		failures.append("respawn: expected a pirate fleet in southdeep")
	# The timer restarts after a respawn: a fleet lost later waits a full delay again.
	if not back.is_empty():
		state.enemy_fleets.erase(back[0])
		state.tick_economy(CampaignStateScript.ECONOMY_TICK_INTERVAL)
		if state.station_fleets(den, COMBAT).size() != 1:
			failures.append("respawn: expected a fleet lost after a respawn to stay gone one tick later, got %d" % state.station_fleets(den, COMBAT).size())
		state.tick_economy(CampaignStateScript.FLEET_RESPAWN_DELAY)
		if state.station_fleets(den, COMBAT).size() != 2:
			failures.append("respawn: expected the lost fleet back after another full delay, got %d" % state.station_fleets(den, COMBAT).size())
	state.free()

static func _check_threat(failures: Array[String]) -> void:
	var state := _fresh_state()
	var bastion: StationData = state.galaxy.station("bastion")
	var before: float = state._threat_ratio_for(bastion)
	state.enemy_fleets.append(_strong_pirate("deadreach"))
	if not is_equal_approx(state._threat_ratio_for(bastion), before):
		failures.append("_threat_ratio_for: expected a far pirate fleet to leave Bastion's threat at %s, got %s" % [before, state._threat_ratio_for(bastion)])
	state.enemy_fleets.append(_strong_pirate("kestrel"))
	if state._threat_ratio_for(bastion) <= before:
		failures.append("_threat_ratio_for: expected a pirate fleet in adjacent kestrel to raise Bastion's threat")
	state.free()

static func _check_growth(failures: Array[String]) -> void:
	var state := _fresh_state()
	var bastion: StationData = state.galaxy.station("bastion")
	state.enemy_fleets.append(_strong_pirate("bastion"))
	var combat: Array[CampaignFleet] = state.station_fleets(bastion, COMBAT)
	var traders: Array[CampaignFleet] = state.station_fleets(bastion, TRADER)
	var action := FleetAllocationPolicy.decide(state._economic_health(bastion.economy), state._threat_ratio_for(bastion), traders.size())
	if action != FleetAllocationPolicy.Action.GROW_COMBAT or combat.is_empty() or combat[0].ship_compositions.size() >= FleetAllocationPolicy.MAX_SHIPS_PER_FLEET:
		failures.append("growth: test setup expected GROW_COMBAT on a Bastion combat fleet under the ship cap")
		state.free()
		return
	var target: CampaignFleet = combat[0]
	var ships_before := target.ship_compositions.size()
	var fleets_before := state.enemy_fleets.size()
	state._apply_station_allocation(bastion)
	if target.ship_compositions.size() != ships_before + 1 or ShipType.kind_of(target.ship_compositions[ships_before]) != ShipType.Kind.CORVETTE:
		failures.append("growth: expected one corvette added to Bastion's combat fleet, %d -> %d ships" % [ships_before, target.ship_compositions.size()])
	if state.enemy_fleets.size() != fleets_before:
		failures.append("growth: expected no new fleet, %d -> %d" % [fleets_before, state.enemy_fleets.size()])
	# Every fleet at the cap: growth adds nothing and still spawns no fleet.
	for fleet in combat:
		while fleet.ship_compositions.size() < FleetAllocationPolicy.MAX_SHIPS_PER_FLEET:
			fleet.ship_compositions.append(ShipType.new_composition(ShipType.Kind.CORVETTE))
	state._apply_station_allocation(bastion)
	if state.enemy_fleets.size() != fleets_before or combat.any(func(f): return f.ship_compositions.size() > FleetAllocationPolicy.MAX_SHIPS_PER_FLEET):
		failures.append("growth: expected capped fleets to stay at %d ships with no new fleet" % FleetAllocationPolicy.MAX_SHIPS_PER_FLEET)
	state.free()

	# No combat fleets: a pirate next door must not block trade growth.
	state = _fresh_state()
	bastion = state.galaxy.station("bastion")
	for fleet in state.station_fleets(bastion, COMBAT):
		state.enemy_fleets.erase(fleet)
	state.enemy_fleets.append(_strong_pirate("bastion"))
	bastion.economy.deficit_streaks = {}
	bastion.economy.surplus_streak = BaseEconomy.SURPLUS_STREAK_THRESHOLD
	var trade_fleets: Array[CampaignFleet] = state.station_fleets(bastion, TRADER)
	if trade_fleets.is_empty() or trade_fleets[0].ship_compositions.size() >= FleetAllocationPolicy.MAX_SHIPS_PER_FLEET:
		failures.append("growth: test setup expected a Bastion trader under the ship cap")
	else:
		var trade_ships_before := trade_fleets[0].ship_compositions.size()
		state._apply_station_allocation(bastion)
		if trade_fleets[0].ship_compositions.size() != trade_ships_before + 1:
			failures.append("growth: expected a combat-less station to grow trade despite pirates, %d -> %d ships" % [trade_ships_before, trade_fleets[0].ship_compositions.size()])
	state.free()

static func _check_trade_at(failures: Array[String]) -> void:
	var state := _fresh_state()
	var bastion: StationData = state.galaxy.station("bastion")
	var home_net: Dictionary = bastion.economy.net_commodities()
	var trader: CampaignFleet = state.station_fleets(bastion, TRADER)[0]

	# At home: everything unloads, then surplus (home net > 0) loads.
	trader.cargo = {Commodity.Type.ORE: 5.0}
	var home_ore_before: float = bastion.economy.stock.get(Commodity.Type.ORE, 0.0)
	state.run_npc_trade_at(trader, bastion)
	if not is_equal_approx(bastion.economy.stock.get(Commodity.Type.ORE, 0.0), home_ore_before + 5.0):
		failures.append("run_npc_trade_at(home): expected 5 Ore unloaded into home stock, got %s" % bastion.economy.stock.get(Commodity.Type.ORE, 0.0))
	if trader.cargo_total() <= 0.0:
		failures.append("run_npc_trade_at(home): expected surplus loaded")
	for commodity in trader.cargo:
		# Jump fuel is topped up at every stop (refuel_npc), surplus or not.
		if commodity == Commodity.Type.FUEL:
			continue
		if trader.cargo[commodity] > 0.0 and home_net.get(commodity, 0.0) <= 0.0:
			failures.append("run_npc_trade_at(home): expected only surplus goods loaded, got %s" % [trader.cargo])
			break

	# Away: cargo unloads into that station, then goods home needs (net < 0) load from its surplus
	# only. Kestrel Picket burns Ore and Fuel itself, so only stock above TARGET_STOCK is spare.
	var away: StationData = state.galaxy.station("kestrel_picket")
	away.economy.stock[Commodity.Type.ORE] = Commodity.TARGET_STOCK[Commodity.Type.ORE] + 30.0
	away.economy.stock[Commodity.Type.FOOD] = Commodity.TARGET_STOCK[Commodity.Type.FOOD] + 30.0
	trader.cargo = {Commodity.Type.WEAPONS: 4.0}
	var away_before: Dictionary = away.economy.stock.duplicate()
	var home_weapons_before: float = bastion.economy.stock.get(Commodity.Type.WEAPONS, 0.0)
	state.run_npc_trade_at(trader, away)
	if not is_equal_approx(away.economy.stock.get(Commodity.Type.WEAPONS, 0.0), away_before.get(Commodity.Type.WEAPONS, 0.0) + 4.0):
		failures.append("run_npc_trade_at(away): expected 4 Weapons unloaded into the away station")
	if not is_equal_approx(bastion.economy.stock.get(Commodity.Type.WEAPONS, 0.0), home_weapons_before):
		failures.append("run_npc_trade_at(away): expected home stock untouched")
	var needed_loaded := 0
	for commodity in trader.cargo:
		var amount: float = trader.cargo[commodity]
		if amount <= 0.0:
			continue
		if home_net.get(commodity, 0.0) >= 0.0:
			failures.append("run_npc_trade_at(away): expected only goods home needs, got %s" % [trader.cargo])
			break
		needed_loaded += 1
		if commodity == Commodity.Type.FUEL:
			continue
		if not is_equal_approx(away.economy.stock.get(commodity, 0.0), away_before.get(commodity, 0.0) - amount):
			failures.append("run_npc_trade_at(away): expected %s drawn from the away station's stock" % Commodity.NAMES[commodity])
		if away.economy.stock.get(commodity, 0.0) < Commodity.TARGET_STOCK[commodity] - CrewRules.ROUND_EPSILON:
			failures.append("run_npc_trade_at(away): expected %s taken only above TARGET_STOCK, left %.1f" % [Commodity.NAMES[commodity], away.economy.stock.get(commodity, 0.0)])
	if needed_loaded < 2:
		failures.append("run_npc_trade_at(away): expected cargo split across the needed goods, got %s" % [trader.cargo])
	_check_trade_surplus_only(state, trader, bastion, failures)

	# A fleet with no known home station is a no-op.
	var orphan := CampaignFleet.new()
	orphan.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.FREIGHTER)])
	orphan.cargo = {Commodity.Type.ORE: 3.0}
	state.run_npc_trade_at(orphan, bastion)
	if not is_equal_approx(orphan.cargo.get(Commodity.Type.ORE, 0.0), 3.0):
		failures.append("run_npc_trade_at: expected a homeless fleet left untouched")
	state.free()

# A partner that consumes a good keeps it all up to TARGET_STOCK; one that makes it gives all it has.
static func _check_trade_surplus_only(state, trader: CampaignFleet, home: StationData, failures: Array[String]) -> void:
	var yards: StationData = state.galaxy.station("bastion_yards")
	yards.economy.stock[Commodity.Type.ORE] = Commodity.TARGET_STOCK[Commodity.Type.ORE]
	trader.cargo = {}
	state.run_npc_trade_at(trader, yards)
	if trader.cargo.get(Commodity.Type.ORE, 0.0) > 0.0 or yards.economy.stock[Commodity.Type.ORE] < Commodity.TARGET_STOCK[Commodity.Type.ORE]:
		failures.append("surplus only: expected no Ore taken from bastion_yards, which burns it, got cargo %s" % [trader.cargo])
	var depot: StationData = state.galaxy.station("marrow_depot")
	depot.economy.stock[Commodity.Type.FOOD] = 20.0
	trader.cargo = {}
	state.run_npc_trade_at(trader, depot)
	if not is_equal_approx(trader.cargo.get(Commodity.Type.FOOD, 0.0), 20.0) or not is_zero_approx(depot.economy.stock[Commodity.Type.FOOD]):
		failures.append("surplus only: expected all 20 Food taken from marrow_depot, which farms it, got cargo %s" % [trader.cargo])
	if home.economy.net_commodities().get(Commodity.Type.FOOD, 0.0) >= 0.0:
		failures.append("surplus only: test setup expected bastion to need Food")

static func _check_next_destination(failures: Array[String]) -> void:
	var state := _fresh_state()
	if CampaignStateScript.TRADE_RANGE_JUMPS != 2:
		failures.append("next_trade_destination: these checks assume TRADE_RANGE_JUMPS 2")
	var greenreach: StationData = state.galaxy.station("greenreach")
	var gr_trader: CampaignFleet = state.station_fleets(greenreach, TRADER)[0]
	gr_trader.dest_station_id = "greenreach_fields"
	if state.next_trade_destination(gr_trader) != "greenreach":
		failures.append("next_trade_destination: expected a trader away from home to head home, got '%s'" % state.next_trade_destination(gr_trader))
	gr_trader.dest_station_id = "greenreach"
	if state.next_trade_destination(gr_trader) != "greenreach_fields":
		failures.append("next_trade_destination: expected greenreach_fields from greenreach, got '%s'" % state.next_trade_destination(gr_trader))
	# All scores 0 (Greenreach needs nothing): the nearest candidate wins.
	state.galaxy.add_station(_extra_station("near_post", "greenreach", CampaignFleet.Faction.NEUTRAL, greenreach.position + Vector2(20, 0), {}))
	if state.next_trade_destination(gr_trader) != "near_post":
		failures.append("next_trade_destination: expected the nearest candidate when every score is 0, got '%s'" % state.next_trade_destination(gr_trader))

	# Beside a pirate base, a neutral hauler still finds a neutral partner within range.
	var depot: StationData = state.galaxy.station("marrow_depot")
	var depot_trader: CampaignFleet = state.station_fleets(depot, TRADER)[0]
	depot_trader.dest_station_id = "marrow_depot"
	var in_range: StationData = state.galaxy.station(state.next_trade_destination(depot_trader))
	if in_range == null or in_range.owner != CampaignFleet.Faction.NEUTRAL or state.galaxy.jump_distance("marrow", in_range.system_id) > CampaignStateScript.TRADE_RANGE_JUMPS:
		failures.append("next_trade_destination: expected a neutral partner within range of marrow_depot, got '%s'" % (in_range.id if in_range != null else ""))

	# Scoring: the stock of goods home needs (Ore, Fuel, Food for Bastion) beats distance.
	var bastion: StationData = state.galaxy.station("bastion")
	var b_trader: CampaignFleet = state.station_fleets(bastion, TRADER)[0]
	b_trader.dest_station_id = "bastion"
	# The Dominion quarries (Ore makers beside Bastion) are real partners now; keep them out of these checks.
	for quarry_id in ["bastion_quarry", "ironhold_quarry", "kestrel_mines"]:
		state.galaxy.station(quarry_id).owner = CampaignFleet.Faction.PIRATE
	var far_rich := _extra_station("far_rich", "bastion", CampaignFleet.Faction.NEUTRAL, bastion.position + Vector2(900, 900), {Commodity.Type.ORE: 1000.0})
	state.galaxy.add_station(far_rich)
	state.galaxy.add_station(_extra_station("pirate_hoard", "bastion", CampaignFleet.Faction.PIRATE, bastion.position, {Commodity.Type.ORE: 9000.0}))
	state.galaxy.add_station(_extra_station("enemy_hoard", "bastion", CampaignFleet.Faction.FREEHOLD, bastion.position, {Commodity.Type.ORE: 5000.0}))
	if state.next_trade_destination(b_trader) != "far_rich":
		failures.append("next_trade_destination: expected the best-stocked friendly station, got '%s'" % state.next_trade_destination(b_trader))
	state.factions_at_war = false
	if state.next_trade_destination(b_trader) != "enemy_hoard":
		failures.append("next_trade_destination: expected a power faction at peace to be a candidate, got '%s'" % state.next_trade_destination(b_trader))
	state.factions_at_war = true
	# Once far_rich is empty, scores are surplus: Bastion Yards burns the Ore Bastion needs, so it
	# offers none, and Marrow Depot's Food (it farms) wins at 1 jump. Far_rich is left at TARGET_STOCK,
	# not empty: an empty one is short of everything and would win as a delivery.
	for commodity in Commodity.TARGET_STOCK:
		far_rich.economy.stock[commodity] = Commodity.TARGET_STOCK[commodity]
		state.galaxy.station("near_post").economy.stock[commodity] = Commodity.TARGET_STOCK[commodity]
	if state.next_trade_destination(b_trader) != "marrow_depot":
		failures.append("next_trade_destination: expected marrow_depot's food surplus once far_rich is empty, got '%s'" % state.next_trade_destination(b_trader))

	# A neutral trader (TRADER faction) only targets neutral stations, however rich the others are.
	var bazaar: StationData = state.galaxy.station("aurum_bazaar")
	var n_trader: CampaignFleet = state.station_fleets(bazaar, TRADER)[0]
	n_trader.dest_station_id = "aurum_bazaar"
	var rich: Dictionary = {}
	for commodity in Commodity.Type.values():
		rich[commodity] = 9000.0
	state.galaxy.add_station(_extra_station("bazaar_player", bazaar.system_id, CampaignFleet.Faction.PLAYER, bazaar.position, rich.duplicate()))
	state.galaxy.add_station(_extra_station("bazaar_freehold", bazaar.system_id, CampaignFleet.Faction.FREEHOLD, bazaar.position, rich.duplicate()))
	state.galaxy.add_station(_extra_station("bazaar_dominion", bazaar.system_id, CampaignFleet.Faction.DOMINION, bazaar.position, rich.duplicate()))
	state.galaxy.add_station(_extra_station("bazaar_post", bazaar.system_id, CampaignFleet.Faction.NEUTRAL, bazaar.position + Vector2(500, 500), {}))
	state.factions_at_war = false
	var neutral_target: StationData = state.galaxy.station(state.next_trade_destination(n_trader))
	if neutral_target == null or neutral_target.owner != CampaignFleet.Faction.NEUTRAL:
		failures.append("next_trade_destination: expected a neutral trader to pick a neutral station over richer ones, got '%s'" % (neutral_target.id if neutral_target != null else ""))
	state.free()

# Range: Bastion (which needs Ore) takes a rich partner 2 jumps out (haven), never a richer one 3 out (tollgate).
static func _check_trade_range(failures: Array[String]) -> void:
	var state := _fresh_state()
	var bastion: StationData = state.galaxy.station("bastion")
	var trader: CampaignFleet = state.station_fleets(bastion, TRADER)[0]
	trader.dest_station_id = "bastion"
	state.galaxy.add_station(_extra_station("far_post", "tollgate", CampaignFleet.Faction.NEUTRAL, Vector2(500, 300), {Commodity.Type.ORE: 1.0e7}))
	state.galaxy.add_station(_extra_station("edge_post", "haven", CampaignFleet.Faction.NEUTRAL, Vector2(500, 300), {Commodity.Type.ORE: 1.0e6}))
	# The Dominion quarries beside Bastion would out-supply both posts; take them out of the trade.
	for quarry_id in ["bastion_quarry", "ironhold_quarry", "kestrel_mines"]:
		state.galaxy.station(quarry_id).owner = CampaignFleet.Faction.PIRATE
	if state.galaxy.jump_distance("bastion", "haven") != 2 or state.galaxy.jump_distance("bastion", "tollgate") != 3:
		failures.append("trade range: test setup expected haven 2 and tollgate 3 jumps from bastion")
	if state.next_trade_destination(trader) != "edge_post":
		failures.append("trade range: expected edge_post (2 jumps) over far_post (3 jumps), got '%s'" % state.next_trade_destination(trader))
	state.free()

static func _check_crew_refill(failures: Array[String]) -> void:
	var state := _fresh_state()
	var station: StationData = state.galaxy.station("farhaven")
	var patrol: CampaignFleet = state.station_fleets(station, COMBAT)[0]
	if patrol.faction != CampaignFleet.Faction.NEUTRAL:
		failures.append("crew refill: test setup expected a NEUTRAL patrol at farhaven")
	for fleet in state.enemy_fleets:
		for comp in fleet.ship_compositions:
			CrewRules.set_crew(comp, CrewRules.complement(comp))
	CrewRules.set_crew(patrol.ship_compositions[0], 1)
	var crew_before := patrol.crew_total()
	station.economy.crew_pool = 3.0
	state._refill_npc_crew()
	if patrol.crew_total() != crew_before + 3 or not is_equal_approx(station.economy.crew_pool, 0.0):
		failures.append("crew refill: expected the patrol to draw 3 crew from farhaven's pool, got crew %d -> %d pool %s" % [crew_before, patrol.crew_total(), station.economy.crew_pool])
	state.free()
