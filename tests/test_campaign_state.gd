extends RefCounted

const CampaignState = preload("res://scripts/campaign/campaign_state.gd")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var state := CampaignState.new()
	var player := CampaignFleet.new()
	player.ship_compositions = [{"max_hp": 100.0, "current_hp": 50.0, "max_shield": 50.0, "current_shield": 10.0}]
	var enemy := CampaignFleet.new()
	enemy.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	state.player_fleet = player
	state.enemy_fleets = [enemy]

	state.start_engagement(enemy)
	if state.active_enemy_fleet != enemy:
		failures.append("start_engagement: expected active_enemy_fleet == enemy")

	state.resolve_engagement(
		[{"max_hp": 100.0, "current_hp": 30.0, "max_shield": 50.0, "current_shield": 0.0}],
		[]
	)
	if player.ship_compositions[0]["current_hp"] != 30.0:
		failures.append("resolve_engagement: expected player fleet updated with survivor data")
	if not enemy.is_destroyed():
		failures.append("resolve_engagement: expected enemy fleet marked destroyed with empty survivors")
	if state.enemy_fleets.has(enemy):
		failures.append("resolve_engagement: expected destroyed enemy fleet removed from enemy_fleets")
	if state.active_enemy_fleet != null:
		failures.append("resolve_engagement: expected active_enemy_fleet cleared after resolution")

	state.factions = [PowerFaction.new()]
	state.factions_at_war = false
	state.active_skirmishes = [Skirmish.new()]

	state.reset()
	if state.player_fleet != null or not state.enemy_fleets.is_empty() or state.active_enemy_fleet != null:
		failures.append("reset: expected all state cleared")
	if not state.factions.is_empty() or state.factions_at_war != true or not state.active_skirmishes.is_empty():
		failures.append("reset: expected factions, factions_at_war, and active_skirmishes cleared")

	# Credits, cargo capacity, and buy/sell.
	var trade_state := CampaignState.new()
	trade_state.credits = 50
	var trade_economy := BaseEconomy.new()
	trade_economy.stock = {Commodity.Type.ORE: 10.0}
	var trade_fleet := CampaignFleet.new()
	trade_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var buy_price: float = trade_economy.price_for(Commodity.Type.ORE)
	var bought: bool = trade_state.buy(trade_economy, Commodity.Type.ORE, trade_fleet)
	if not bought:
		failures.append("buy: expected a well-funded, in-capacity purchase to succeed")
	if trade_state.credits != 50 - buy_price:
		failures.append("buy: expected credits reduced by buy_price, got %s" % trade_state.credits)
	if trade_economy.stock.get(Commodity.Type.ORE, 0.0) != 9.0:
		failures.append("buy: expected base stock reduced by 1, got %s" % trade_economy.stock.get(Commodity.Type.ORE, 0.0))
	if trade_fleet.cargo.get(Commodity.Type.ORE, 0.0) != 1.0:
		failures.append("buy: expected fleet cargo increased by 1, got %s" % trade_fleet.cargo.get(Commodity.Type.ORE, 0.0))

	trade_state.credits = 0
	var bought_broke: bool = trade_state.buy(trade_economy, Commodity.Type.ORE, trade_fleet)
	if bought_broke:
		failures.append("buy: expected purchase to fail with 0 credits")

	var sell_price: float = trade_economy.sell_price_for(Commodity.Type.ORE)
	var sold: bool = trade_state.sell(trade_economy, Commodity.Type.ORE, trade_fleet)
	if not sold:
		failures.append("sell: expected selling held cargo to succeed")
	if trade_state.credits != sell_price:
		failures.append("sell: expected credits increased by sell_price, got %s" % trade_state.credits)
	if trade_fleet.cargo.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("sell: expected fleet cargo reduced by 1, got %s" % trade_fleet.cargo.get(Commodity.Type.ORE, 0.0))

	var sold_empty: bool = trade_state.sell(trade_economy, Commodity.Type.ORE, trade_fleet)
	if sold_empty:
		failures.append("sell: expected selling with no cargo held to fail")

	# buy: out-of-stock base should fail without touching credits/cargo/stock.
	var out_of_stock_state := CampaignState.new()
	out_of_stock_state.credits = 50
	var out_of_stock_economy := BaseEconomy.new()
	out_of_stock_economy.stock = {Commodity.Type.ORE: 0.0}
	var out_of_stock_fleet := CampaignFleet.new()
	out_of_stock_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var bought_out_of_stock: bool = out_of_stock_state.buy(out_of_stock_economy, Commodity.Type.ORE, out_of_stock_fleet)
	if bought_out_of_stock:
		failures.append("buy: expected purchase to fail when base stock is below 1.0")
	if out_of_stock_state.credits != 50:
		failures.append("buy: expected credits unchanged when base stock is below 1.0, got %s" % out_of_stock_state.credits)
	if out_of_stock_fleet.cargo.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("buy: expected fleet cargo unchanged when base stock is below 1.0")
	if out_of_stock_economy.stock.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("buy: expected base stock unchanged when base stock is below 1.0")

	# buy: fleet cargo already at capacity should fail without touching credits/cargo/stock.
	var full_cargo_state := CampaignState.new()
	full_cargo_state.credits = 50
	var full_cargo_economy := BaseEconomy.new()
	full_cargo_economy.stock = {Commodity.Type.ORE: 10.0}
	var full_cargo_fleet := CampaignFleet.new()
	full_cargo_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	full_cargo_fleet.cargo = {Commodity.Type.FUEL: 20.0}
	if full_cargo_fleet.cargo_total() < full_cargo_fleet.cargo_capacity():
		failures.append("buy: test setup expected cargo already at capacity")

	var bought_full_cargo: bool = full_cargo_state.buy(full_cargo_economy, Commodity.Type.ORE, full_cargo_fleet)
	if bought_full_cargo:
		failures.append("buy: expected purchase to fail when cargo would exceed capacity")
	if full_cargo_state.credits != 50:
		failures.append("buy: expected credits unchanged when cargo is full, got %s" % full_cargo_state.credits)
	if full_cargo_fleet.cargo.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("buy: expected fleet cargo unchanged (no Ore added) when cargo is full")
	if full_cargo_economy.stock.get(Commodity.Type.ORE, 0.0) != 10.0:
		failures.append("buy: expected base stock unchanged when cargo is full")

	# tick_economy: fires on a fixed interval, not every delta.
	var tick_state := CampaignState.new()
	var ticked_economy := BaseEconomy.new()
	ticked_economy.slots = [EconomyRole.mining()]
	ticked_economy.max_slots = 1
	tick_state.galaxy = _test_galaxy([_test_station("home_base", CampaignFleet.Faction.PLAYER, ticked_economy)])
	tick_state.tick_economy(1.0)
	if ticked_economy.stock.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("tick_economy: expected no tick yet before the interval elapses")
	tick_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
	if ticked_economy.stock.get(Commodity.Type.ORE, 0.0) != 5.0:
		failures.append("tick_economy: expected one economy tick once the interval elapses, got Ore=%s" % ticked_economy.stock.get(Commodity.Type.ORE, 0.0))

	# tick_economy: every station's economy ticks, and a station with no economy is skipped.
	var station_tick_state := CampaignState.new()
	var station_economy := BaseEconomy.new()
	station_economy.slots = [EconomyRole.mining()]
	station_economy.max_slots = 1
	var bare_station := _test_station("bare", CampaignFleet.Faction.NEUTRAL, null)
	station_tick_state.galaxy = _test_galaxy([_test_station("mine", CampaignFleet.Faction.FREEHOLD, station_economy), bare_station])
	station_tick_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
	if station_economy.stock.get(Commodity.Type.ORE, 0.0) != 5.0:
		failures.append("tick_economy: expected the station's economy to tick, got Ore=%s" % station_economy.stock.get(Commodity.Type.ORE, 0.0))
	if bare_station.economy != null:
		failures.append("tick_economy: expected the economy-less station to remain untouched")

	# reset() clears the economy and galaxy fields too.
	tick_state.credits = 10
	tick_state.reset()
	if tick_state.credits != 500:
		failures.append("reset: expected credits reset to 500, got %s" % tick_state.credits)
	if tick_state.home_base_economy != null:
		failures.append("reset: expected home_base_economy cleared to null")
	if tick_state.galaxy != null:
		failures.append("reset: expected galaxy cleared to null")

	# run_npc_trade_at: at its home station a hauler loads home's surplus
	# commodities (produced more than consumed) from home's own stock.
	var trade_route_state := CampaignState.new()
	var freehold_home := _test_station("freehold_home", CampaignFleet.Faction.FREEHOLD, BaseEconomy.new())
	freehold_home.economy.slots = [EconomyRole.mining(), EconomyRole.agriculture()]
	freehold_home.economy.stock = {Commodity.Type.ORE: 15.0, Commodity.Type.FOOD: 15.0}
	var player_home := _test_station("home_base", CampaignFleet.Faction.PLAYER, BaseEconomy.new())
	trade_route_state.galaxy = _test_galaxy([freehold_home, player_home])

	var hauler := CampaignFleet.new()
	hauler.faction = CampaignFleet.Faction.FREEHOLD
	hauler.role = CampaignFleet.Role.TRADER
	hauler.home_station_id = "freehold_home"
	hauler.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
	]

	trade_route_state.run_npc_trade_at(hauler, freehold_home)
	if hauler.cargo_total() <= 0.0:
		failures.append("run_npc_trade_at: expected loading surplus at the home station to fill cargo")
	# Cargo capacity (40.0, two ships) comfortably covers both commodities'
	# combined stock (30.0), so both must be drawn down individually -- this
	# proves the loop handles every surplus commodity, not just the first one
	# it encounters.
	if freehold_home.economy.stock.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("run_npc_trade_at: expected loading surplus to draw down Ore stock to 0.0, got %s" % freehold_home.economy.stock.get(Commodity.Type.ORE, 0.0))
	if freehold_home.economy.stock.get(Commodity.Type.FOOD, 0.0) != 0.0:
		failures.append("run_npc_trade_at: expected loading surplus to draw down Food stock to 0.0, got %s" % freehold_home.economy.stock.get(Commodity.Type.FOOD, 0.0))

	# Arriving at another station: dumps carried cargo into that station's stock,
	# then loads whatever home nets a deficit on (here, nothing is consumed by
	# mining/agriculture, so no deficit cargo should be loaded).
	player_home.economy.stock[Commodity.Type.FUEL] = 20.0
	var cargo_before_dump: Dictionary = hauler.cargo.duplicate()
	trade_route_state.run_npc_trade_at(hauler, player_home)
	for commodity in cargo_before_dump:
		if player_home.economy.stock.get(commodity, 0.0) < cargo_before_dump[commodity]:
			failures.append("run_npc_trade_at: expected carried cargo dumped into the away station's stock")
	# The only cargo is the jump fuel refuel_npc tops up from the station after the unload.
	if hauler.cargo_total() - hauler.fuel_amount() != 0.0:
		failures.append("run_npc_trade_at: expected no deficit cargo loaded for a home with no consuming slots, got cargo=%s" % hauler.cargo)

	# A home with a deficit (Dominion needs Ore/Fuel/Food) loads from the
	# away station's surplus: stock above TARGET_STOCK of goods it doesn't make.
	var dominion_home := _test_station("dominion_home", CampaignFleet.Faction.DOMINION, BaseEconomy.new())
	dominion_home.economy.slots = [EconomyRole.industrial(), EconomyRole.population()]
	trade_route_state.galaxy.add_station(dominion_home)
	player_home.economy.stock[Commodity.Type.ORE] = Commodity.TARGET_STOCK[Commodity.Type.ORE] + 30.0

	var deficit_hauler := CampaignFleet.new()
	deficit_hauler.faction = CampaignFleet.Faction.DOMINION
	deficit_hauler.role = CampaignFleet.Role.TRADER
	deficit_hauler.home_station_id = "dominion_home"
	deficit_hauler.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	trade_route_state.run_npc_trade_at(deficit_hauler, player_home)
	if deficit_hauler.cargo.get(Commodity.Type.ORE, 0.0) <= 0.0:
		failures.append("run_npc_trade_at: expected Dominion's hauler to load Ore (a deficit commodity) from the away station's stock")

	# run_npc_trade_at: when cargo capacity is NOT enough to cover every
	# deficit commodity, the available space must be split across all
	# qualifying commodities, not raced for by whichever one net_commodities()
	# happens to enumerate first. Dominion's industrial+population slots net
	# WEAPONS +2, ORE -3, FUEL -2, FOOD -4 -- a single-ship hauler (capacity
	# 20) arriving at a station whose surplus is well above capacity in all
	# three must come away with more than just Ore, including Fuel past its tank.
	var split_deficit_state := CampaignState.new()
	var split_deficit_home := _test_station("split_home", CampaignFleet.Faction.DOMINION, BaseEconomy.new())
	split_deficit_home.economy.slots = [EconomyRole.industrial(), EconomyRole.population()]
	var split_deficit_away := _test_station("split_away", CampaignFleet.Faction.PLAYER, BaseEconomy.new())
	split_deficit_away.economy.stock = {
		Commodity.Type.ORE: 200.0,
		Commodity.Type.FUEL: 200.0,
		Commodity.Type.FOOD: 200.0,
	}
	split_deficit_state.galaxy = _test_galaxy([split_deficit_home, split_deficit_away])
	var split_deficit_hauler := CampaignFleet.new()
	split_deficit_hauler.faction = CampaignFleet.Faction.DOMINION
	split_deficit_hauler.role = CampaignFleet.Role.TRADER
	split_deficit_hauler.home_station_id = "split_home"
	split_deficit_hauler.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	split_deficit_state.run_npc_trade_at(split_deficit_hauler, split_deficit_away)
	var split_deficit_commodities_loaded := 0
	for commodity in [Commodity.Type.ORE, Commodity.Type.FUEL, Commodity.Type.FOOD]:
		if split_deficit_hauler.cargo.get(commodity, 0.0) > 0.0:
			split_deficit_commodities_loaded += 1
	if split_deficit_commodities_loaded <= 1:
		failures.append("run_npc_trade_at: expected cargo space to be split across all deficit commodities, not just one, got cargo=%s" % split_deficit_hauler.cargo)
	var split_tank: float = split_deficit_state.NPC_FUEL_TARGET_JUMPS * JumpRules.jump_cost(split_deficit_hauler)
	if split_deficit_hauler.fuel_amount() <= split_tank + CrewRules.ROUND_EPSILON:
		failures.append("run_npc_trade_at: expected Fuel (a deficit commodity) to actually be picked up past the jump tank, not starved by a greedy first commodity")

	# Symmetric case on the export side: a home with multiple surplus
	# commodities and capacity too small to carry all of them fully should
	# still load more than one distinct commodity.
	var split_surplus_state := CampaignState.new()
	var split_surplus_home := _test_station("surplus_home", CampaignFleet.Faction.FREEHOLD, BaseEconomy.new())
	split_surplus_home.economy.slots = [EconomyRole.mining(), EconomyRole.agriculture()]
	split_surplus_home.economy.stock = {Commodity.Type.ORE: 50.0, Commodity.Type.FOOD: 50.0}
	split_surplus_state.galaxy = _test_galaxy([split_surplus_home])
	var split_surplus_hauler := CampaignFleet.new()
	split_surplus_hauler.faction = CampaignFleet.Faction.FREEHOLD
	split_surplus_hauler.role = CampaignFleet.Role.TRADER
	split_surplus_hauler.home_station_id = "surplus_home"
	split_surplus_hauler.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	split_surplus_state.run_npc_trade_at(split_surplus_hauler, split_surplus_home)
	var split_surplus_commodities_loaded := 0
	for commodity in [Commodity.Type.ORE, Commodity.Type.FOOD]:
		if split_surplus_hauler.cargo.get(commodity, 0.0) > 0.0:
			split_surplus_commodities_loaded += 1
	if split_surplus_commodities_loaded <= 1:
		failures.append("run_npc_trade_at: expected cargo space to be split across all surplus commodities, not just one, got cargo=%s" % split_surplus_hauler.cargo)

	# No-op cases: unknown home station, a home with no economy, no galaxy.
	var orphan_hauler := CampaignFleet.new()
	orphan_hauler.faction = CampaignFleet.Faction.PIRATE
	orphan_hauler.home_station_id = "nowhere"
	trade_route_state.run_npc_trade_at(orphan_hauler, player_home)
	if orphan_hauler.cargo_total() != 0.0:
		failures.append("run_npc_trade_at: expected no-op for a fleet with no known home station")

	var null_economy_station := _test_station("null_economy", CampaignFleet.Faction.NEUTRAL, null)
	trade_route_state.galaxy.add_station(null_economy_station)
	var null_economy_hauler := CampaignFleet.new()
	null_economy_hauler.faction = CampaignFleet.Faction.TRADER
	null_economy_hauler.role = CampaignFleet.Role.TRADER
	null_economy_hauler.home_station_id = "null_economy"
	null_economy_hauler.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	trade_route_state.run_npc_trade_at(null_economy_hauler, player_home)
	if null_economy_hauler.cargo_total() != 0.0:
		failures.append("run_npc_trade_at: expected no-op for a home station with no economy")

	var no_galaxy_state := CampaignState.new()
	var no_galaxy_station := _test_station("lonely", CampaignFleet.Faction.FREEHOLD, BaseEconomy.new())
	no_galaxy_station.economy.slots = [EconomyRole.mining()]
	no_galaxy_station.economy.stock = {Commodity.Type.ORE: 50.0}
	var no_galaxy_hauler := CampaignFleet.new()
	no_galaxy_hauler.faction = CampaignFleet.Faction.FREEHOLD
	no_galaxy_hauler.role = CampaignFleet.Role.TRADER
	no_galaxy_hauler.home_station_id = "lonely"
	no_galaxy_hauler.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	no_galaxy_state.run_npc_trade_at(no_galaxy_hauler, no_galaxy_station)
	if no_galaxy_hauler.cargo_total() != 0.0:
		failures.append("run_npc_trade_at: expected no-op with no galaxy")
	if no_galaxy_station.economy.stock.get(Commodity.Type.ORE, 0.0) != 50.0:
		failures.append("run_npc_trade_at: expected station stock unchanged with no galaxy")

	# Fleet allocation: a station outmatched by pirates in its system, with a
	# healthy economy, grows a ship on its existing combat fleet.
	var grow_combat_state := CampaignState.new()
	var grow_combat_station := _test_station("dom", CampaignFleet.Faction.DOMINION, BaseEconomy.new())
	grow_combat_station.economy.slots = [EconomyRole.mining()]  # no consumption -> never in deficit
	grow_combat_state.galaxy = _test_galaxy([grow_combat_station])

	var weak_combat_fleet := _test_station_fleet("dom", CampaignFleet.Faction.DOMINION, CampaignFleet.Role.COMBAT, 10.0)
	var strong_pirate_fleet := _test_station_fleet("", CampaignFleet.Faction.PIRATE, CampaignFleet.Role.COMBAT, 1000.0)
	grow_combat_state.enemy_fleets = [weak_combat_fleet, strong_pirate_fleet]

	var ships_before: int = weak_combat_fleet.ship_compositions.size()
	grow_combat_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
	if weak_combat_fleet.ship_compositions.size() != ships_before + 1:
		failures.append("tick_economy: expected an outmatched combat fleet to grow a ship, had %d before, %d after" % [ships_before, weak_combat_fleet.ship_compositions.size()])
	elif weak_combat_fleet.ship_compositions[ships_before]["ship_type"] != ShipType.Kind.CORVETTE:
		failures.append("tick_economy: expected a grown COMBAT fleet's new ship to be ship_type CORVETTE, got %s" % weak_combat_fleet.ship_compositions[ships_before]["ship_type"])

	# A station that's economically strong and safe from pirates grows its
	# trader fleet a freighter at a time up to the ship cap, never spawning a
	# new fleet (lost fleets come back through respawn instead).
	var grow_trade_state := CampaignState.new()
	var grow_trade_station := _test_station("free", CampaignFleet.Faction.FREEHOLD, BaseEconomy.new())
	grow_trade_station.economy.slots = [EconomyRole.mining()]
	grow_trade_state.galaxy = _test_galaxy([grow_trade_station])

	var safe_combat_fleet := _test_station_fleet("free", CampaignFleet.Faction.FREEHOLD, CampaignFleet.Role.COMBAT, 1000.0)
	var growing_trader := _test_station_fleet("free", CampaignFleet.Faction.FREEHOLD, CampaignFleet.Role.TRADER, 100.0)
	grow_trade_state.enemy_fleets = [safe_combat_fleet, growing_trader]

	var spawned := []
	grow_trade_state.fleet_spawn_requested.connect(func(fleet: CampaignFleet): spawned.append(fleet))
	# The economy turns WEALTHY on tick SURPLUS_STREAK_THRESHOLD, then grows every tick until capped.
	for i in BaseEconomy.SURPLUS_STREAK_THRESHOLD + FleetAllocationPolicy.MAX_SHIPS_PER_FLEET:
		grow_trade_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
	if growing_trader.ship_compositions.size() != FleetAllocationPolicy.MAX_SHIPS_PER_FLEET:
		failures.append("tick_economy: expected a strong, safe station's trader to grow to the ship cap, got %d ships" % growing_trader.ship_compositions.size())
	elif growing_trader.ship_compositions[1]["ship_type"] != ShipType.Kind.FREIGHTER:
		failures.append("tick_economy: expected a grown trader fleet's new ship to be ship_type FREIGHTER, got %s" % growing_trader.ship_compositions[1]["ship_type"])
	if not spawned.is_empty():
		failures.append("tick_economy: expected growth never to spawn a fleet, got %d" % spawned.size())

	# Growth stops at the fleet's variant maximum: a Picket stays at 2 ships, a Security reaches the global cap.
	for case in [[DangerTier.Variant.PICKET, 2], [DangerTier.Variant.SECURITY, FleetAllocationPolicy.MAX_SHIPS_PER_FLEET]]:
		var cap_state := CampaignState.new()
		var cap_station := _test_station("dom", CampaignFleet.Faction.DOMINION, BaseEconomy.new())
		cap_station.economy.slots = [EconomyRole.mining()]
		cap_state.galaxy = _test_galaxy([cap_station])
		var cap_fleet := _test_station_fleet("dom", CampaignFleet.Faction.DOMINION, CampaignFleet.Role.COMBAT, 10.0)
		cap_fleet.variant = case[0]
		cap_state.enemy_fleets = [cap_fleet, _test_station_fleet("", CampaignFleet.Faction.PIRATE, CampaignFleet.Role.COMBAT, 1000000.0)]
		for _i in FleetAllocationPolicy.MAX_SHIPS_PER_FLEET + 3:
			cap_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
		if cap_fleet.ship_compositions.size() != case[1]:
			failures.append("tick_economy: variant %d expected growth to stop at %d ships, got %d" % [case[0], case[1], cap_fleet.ship_compositions.size()])

	# Reallocation: an outmatched station in economic deficit with 2 trader
	# fleets flips one to COMBAT instead of growing (can't afford to grow).
	var reallocate_state := CampaignState.new()
	var reallocate_station := _test_station("dom", CampaignFleet.Faction.DOMINION, BaseEconomy.new())
	reallocate_station.economy.slots = [EconomyRole.industrial()]  # will starve immediately, no inputs
	reallocate_state.galaxy = _test_galaxy([reallocate_station])

	var weak_combat_fleet_2 := _test_station_fleet("dom", CampaignFleet.Faction.DOMINION, CampaignFleet.Role.COMBAT, 1.0)
	var trader_fleet_1 := _test_station_fleet("dom", CampaignFleet.Faction.DOMINION, CampaignFleet.Role.TRADER, 100.0)
	var trader_fleet_2 := _test_station_fleet("dom", CampaignFleet.Faction.DOMINION, CampaignFleet.Role.TRADER, 100.0)
	var strong_pirate_fleet_2 := _test_station_fleet("", CampaignFleet.Faction.PIRATE, CampaignFleet.Role.COMBAT, 1000.0)
	reallocate_state.enemy_fleets = [weak_combat_fleet_2, trader_fleet_1, trader_fleet_2, strong_pirate_fleet_2]

	var role_changes := []
	reallocate_state.fleet_role_changed.connect(func(fleet: CampaignFleet): role_changes.append(fleet))
	reallocate_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
	if role_changes.size() != 1:
		failures.append("tick_economy: expected exactly one fleet reallocated to COMBAT, got %d" % role_changes.size())
	elif role_changes[0].role != CampaignFleet.Role.COMBAT:
		failures.append("tick_economy: expected the reallocated fleet's role to now be COMBAT")

	# resolve_engagement: a destroyed enemy fleet carrying cargo sets
	# pending_loot; one with no cargo or parts leaves it null.
	var loot_state := CampaignState.new()
	var loot_player := CampaignFleet.new()
	loot_player.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	loot_state.player_fleet = loot_player
	var looted_enemy := CampaignFleet.new()
	looted_enemy.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	looted_enemy.cargo = {Commodity.Type.ORE: 5.0}
	loot_state.enemy_fleets = [looted_enemy]
	loot_state.start_engagement(looted_enemy)
	loot_state.resolve_engagement([{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}], [])
	if loot_state.pending_loot == null or loot_state.pending_loot.cargo.get(Commodity.Type.ORE, 0.0) != 5.0:
		failures.append("resolve_engagement: expected pending_loot to carry the destroyed fleet's cargo")
	elif not loot_state.pending_loot.ships.is_empty():
		failures.append("resolve_engagement: expected no ships in the loot offer yet")

	var no_loot_state := CampaignState.new()
	var no_loot_player := CampaignFleet.new()
	no_loot_player.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	no_loot_state.player_fleet = no_loot_player
	var empty_cargo_enemy := CampaignFleet.new()
	empty_cargo_enemy.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	no_loot_state.enemy_fleets = [empty_cargo_enemy]
	no_loot_state.start_engagement(empty_cargo_enemy)
	no_loot_state.resolve_engagement([{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}], [])
	if no_loot_state.pending_loot != null:
		failures.append("resolve_engagement: expected pending_loot to stay null for a fleet with no cargo")

	# Parts alone make an offer too.
	var parts_state := CampaignState.new()
	var parts_player := CampaignFleet.new()
	parts_player.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	parts_state.player_fleet = parts_player
	var parts_enemy := CampaignFleet.new()
	parts_enemy.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	parts_enemy.part_inventory.assign(["res://resources/weapons/railgun.tres"])
	parts_state.enemy_fleets = [parts_enemy]
	parts_state.start_engagement(parts_enemy)
	parts_state.resolve_engagement([{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}], [])
	if parts_state.pending_loot == null or parts_state.pending_loot.parts != ["res://resources/weapons/railgun.tres"]:
		failures.append("resolve_engagement: expected pending_loot to carry the destroyed fleet's parts")

	loot_state.reset()
	if loot_state.pending_loot != null:
		failures.append("reset: expected pending_loot cleared to null")

	# resolve_engagement player_won with a partial escape: enemy_survivors are the escapers,
	# so the enemy stays with them; cargo splits by capacity and the captured ship is offered.
	var won_state := CampaignState.new()
	var won_dominion := PowerFaction.new()
	won_dominion.faction_enum = CampaignFleet.Faction.DOMINION
	won_dominion.reputation = 60.0
	won_state.factions = [won_dominion]
	var won_player := CampaignFleet.new()
	won_player.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	won_state.player_fleet = won_player
	var won_escaper := ShipType.new_composition(ShipType.Kind.CAPITAL)
	var won_caught := ShipType.new_composition(ShipType.Kind.FREIGHTER)
	won_caught["crew"] = 4
	var won_enemy := CampaignFleet.new()
	won_enemy.faction = CampaignFleet.Faction.DOMINION
	won_enemy.ship_compositions.assign([won_escaper, won_caught, ShipType.new_composition(ShipType.Kind.CORVETTE)])
	won_enemy.cargo = {Commodity.Type.ORE: 80.0}
	won_enemy.part_inventory.assign(["part_a", "part_b", "part_c"])
	won_state.enemy_fleets.assign([won_enemy])
	won_state.start_engagement(won_enemy)
	var won_escapers: Array[Dictionary] = [won_escaper]
	var won_captured: Array[Dictionary] = [won_caught]
	won_state.resolve_engagement(won_player.ship_compositions, won_escapers, true, won_captured)
	if not won_state.enemy_fleets.has(won_enemy) or won_enemy.ship_compositions.size() != 1:
		failures.append("resolve_engagement(partial escape): expected the enemy kept with its 1 escaper, got %d ships" % won_enemy.ship_compositions.size())
	if not is_equal_approx(won_enemy.cargo.get(Commodity.Type.ORE, 0.0), 20.0) or won_enemy.part_inventory != ["part_c"]:
		failures.append("resolve_engagement(partial escape): expected the escaper to keep ORE 20 and part_c, got %s / %s" % [won_enemy.cargo, won_enemy.part_inventory])
	if won_state.pending_loot == null:
		failures.append("resolve_engagement(partial escape): expected a loot offer")
	else:
		if not is_equal_approx(won_state.pending_loot.cargo.get(Commodity.Type.ORE, 0.0), 60.0) or won_state.pending_loot.parts != ["part_a", "part_b"]:
			failures.append("resolve_engagement(partial escape): expected loot ORE 60 and 2 parts, got %s / %s" % [won_state.pending_loot.cargo, won_state.pending_loot.parts])
		if won_state.pending_loot.ships.size() != 1 or CrewRules.crew_of(won_state.pending_loot.ships[0]) != 4:
			failures.append("resolve_engagement(partial escape): expected the captured freighter offered with crew 4, got %s" % [won_state.pending_loot.ships])
	# Once per battle, although one ship was destroyed and another captured.
	if won_dominion.fine != CampaignState.FINE_PER_KILL or not is_equal_approx(won_dominion.reputation, 60.0 - CampaignState.REPUTATION_LOSS_PER_DEFEAT):
		failures.append("resolve_engagement(partial escape): expected one reputation loss and fine, got fine %d rep %s" % [won_dominion.fine, won_dominion.reputation])
	if won_player.flagship_index() == -1:
		failures.append("resolve_engagement: expected ensure_flagship to assign a flagship to the player fleet")

	# player_won with every enemy ship escaping: nothing lost, so no reputation loss and no loot.
	var fled_state := CampaignState.new()
	var fled_dominion := PowerFaction.new()
	fled_dominion.faction_enum = CampaignFleet.Faction.DOMINION
	fled_state.factions = [fled_dominion]
	var fled_player := CampaignFleet.new()
	fled_player.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	fled_state.player_fleet = fled_player
	var fled_enemy := CampaignFleet.new()
	fled_enemy.faction = CampaignFleet.Faction.DOMINION
	fled_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	fled_enemy.cargo = {Commodity.Type.ORE: 10.0}
	fled_state.enemy_fleets.assign([fled_enemy])
	fled_state.start_engagement(fled_enemy)
	fled_state.resolve_engagement(fled_player.ship_compositions, fled_enemy.ship_compositions.duplicate(true), true)
	if not fled_state.enemy_fleets.has(fled_enemy) or fled_dominion.fine != 0 or fled_state.pending_loot != null:
		failures.append("resolve_engagement(all escaped): expected the enemy kept, no fine and no loot, got fine %d loot %s" % [fled_dominion.fine, fled_state.pending_loot])
	if fled_enemy.cargo.get(Commodity.Type.ORE, 0.0) != 10.0:
		failures.append("resolve_engagement(all escaped): expected the enemy to keep all its cargo, got %s" % fled_enemy.cargo)

	# player_won with the only enemy ship captured: the fleet is erased and its ship is offered.
	var caught_state := CampaignState.new()
	var caught_player := CampaignFleet.new()
	caught_player.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	caught_state.player_fleet = caught_player
	var caught_enemy := CampaignFleet.new()
	caught_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	caught_state.enemy_fleets.assign([caught_enemy])
	caught_state.start_engagement(caught_enemy)
	var caught_ships: Array[Dictionary] = [caught_enemy.ship_compositions[0].duplicate(true)]
	var no_escapers: Array[Dictionary] = []
	caught_state.resolve_engagement(caught_player.ship_compositions, no_escapers, true, caught_ships)
	if caught_state.enemy_fleets.has(caught_enemy):
		failures.append("resolve_engagement(all captured): expected the enemy fleet erased")
	if caught_state.pending_loot == null or caught_state.pending_loot.ships.size() != 1:
		failures.append("resolve_engagement(all captured): expected the captured ship offered")

	# Player loss: captured player comps join the enemy fleet up to MAX_SHIPS_PER_FLEET, flagship cleared.
	var taken_state := CampaignState.new()
	var taken_flagship := ShipType.new_composition(ShipType.Kind.CAPITAL)
	taken_flagship["flagship"] = true
	taken_flagship["deploy"] = false
	var taken_corvette := ShipType.new_composition(ShipType.Kind.CORVETTE)
	var taken_escaper := ShipType.new_composition(ShipType.Kind.FREIGHTER)
	var taken_player := CampaignFleet.new()
	taken_player.ship_compositions.assign([taken_flagship, taken_corvette, taken_escaper])
	taken_state.player_fleet = taken_player
	var taken_enemy := CampaignFleet.new()
	# One slot under the cap: the first captured ship (the capital) fits, the second is scuttled.
	for _i in FleetAllocationPolicy.MAX_SHIPS_PER_FLEET - 1:
		taken_enemy.ship_compositions.append(ShipType.new_composition(ShipType.Kind.CORVETTE))
	taken_state.enemy_fleets.assign([taken_enemy])
	taken_state.start_engagement(taken_enemy)
	var taken_player_escapers: Array[Dictionary] = [taken_escaper]
	var taken_captured: Array[Dictionary] = [taken_flagship, taken_corvette]
	taken_state.resolve_engagement(taken_player_escapers, taken_enemy.ship_compositions.duplicate(true), false, taken_captured)
	if taken_enemy.ship_compositions.size() != FleetAllocationPolicy.MAX_SHIPS_PER_FLEET:
		failures.append("resolve_engagement(player loss): expected the enemy capped at %d ships, got %d" % [FleetAllocationPolicy.MAX_SHIPS_PER_FLEET, taken_enemy.ship_compositions.size()])
	elif ShipType.kind_of(taken_enemy.ship_compositions.back()) != ShipType.Kind.CAPITAL or CrewRules.is_flagship(taken_enemy.ship_compositions.back()):
		failures.append("resolve_engagement(player loss): expected the captured capital appended with its flagship flag cleared, got %s" % taken_enemy.ship_compositions.back())
	if taken_enemy.ship_compositions.size() > 2 and not CrewRules.wants_deploy(taken_enemy.ship_compositions.back()):
		failures.append("resolve_engagement(player loss): expected the captured capital to deploy for its new fleet")
	if taken_player.ship_compositions.size() != 1 or ShipType.kind_of(taken_player.ship_compositions[0]) != ShipType.Kind.FREIGHTER:
		failures.append("resolve_engagement(player loss): expected the player left with the escaped freighter")
	elif taken_player.flagship_index() != 0:
		failures.append("resolve_engagement(player loss): expected ensure_flagship to promote the escaped freighter")
	if taken_state.pending_loot != null:
		failures.append("resolve_engagement(player loss): expected no loot")

	# Player loss splits the player's cargo by captured capacity: the share goes to the enemy.
	var split_state := CampaignState.new()
	var split_capital := ShipType.new_composition(ShipType.Kind.CAPITAL)
	split_capital["flagship"] = true
	var split_freighter := ShipType.new_composition(ShipType.Kind.FREIGHTER)
	var split_player := CampaignFleet.new()
	split_player.ship_compositions.assign([split_capital, split_freighter])
	split_player.cargo = {Commodity.Type.ORE: 80.0}
	split_state.player_fleet = split_player
	var split_enemy := CampaignFleet.new()
	split_enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	split_state.enemy_fleets.assign([split_enemy])
	split_state.start_engagement(split_enemy)
	var split_escapers: Array[Dictionary] = [split_capital]
	var split_captured: Array[Dictionary] = [split_freighter]
	split_state.resolve_engagement(split_escapers, split_enemy.ship_compositions.duplicate(true), false, split_captured)
	if not is_equal_approx(split_enemy.cargo.get(Commodity.Type.ORE, 0.0), 60.0):
		failures.append("resolve_engagement(player loss): expected the enemy to gain 60 ore, got %s" % split_enemy.cargo.get(Commodity.Type.ORE, 0.0))
	if not is_equal_approx(split_player.cargo.get(Commodity.Type.ORE, 0.0), 20.0):
		failures.append("resolve_engagement(player loss): expected the player to keep 20 ore, got %s" % split_player.cargo.get(Commodity.Type.ORE, 0.0))

	# resolve_engagement player loss: a surviving enemy fleet stays and its crew is rebalanced.
	var lost_state := CampaignState.new()
	var lost_player := CampaignFleet.new()
	lost_player.ship_compositions.assign([{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}])
	lost_state.player_fleet = lost_player
	var lost_enemy := CampaignFleet.new()
	lost_enemy.ship_compositions.assign([{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}])
	lost_state.enemy_fleets.assign([lost_enemy])
	lost_state.start_engagement(lost_enemy)
	var lost_enemy_survivors: Array[Dictionary] = [
		{"ship_type": ShipType.Kind.CORVETTE, "max_hp": 60.0, "current_hp": 60.0, "max_shield": 20.0, "current_shield": 20.0, "crew": 2},
		{"ship_type": ShipType.Kind.CORVETTE, "max_hp": 60.0, "current_hp": 60.0, "max_shield": 20.0, "current_shield": 20.0, "crew": 10},
	]
	lost_state.resolve_engagement(lost_player.ship_compositions, lost_enemy_survivors, false)
	if not lost_state.enemy_fleets.has(lost_enemy):
		failures.append("resolve_engagement(player loss): expected the surviving enemy fleet kept")
	elif CrewRules.crew_of(lost_enemy.ship_compositions[0]) != 6 or CrewRules.crew_of(lost_enemy.ship_compositions[1]) != 6:
		failures.append("resolve_engagement(player loss): expected enemy crew balanced to 6/6, got %s" % [lost_enemy.ship_compositions])
	if lost_state.pending_loot != null:
		failures.append("resolve_engagement(player loss): expected no loot pending")

	# resolve_engagement mutual wipe: a total loss (respawn) never offers loot, even from a destroyed enemy.
	var wipe_state := CampaignState.new()
	var wipe_player := CampaignFleet.new()
	wipe_player.ship_compositions.assign([{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}])
	wipe_state.player_fleet = wipe_player
	var wipe_enemy := CampaignFleet.new()
	wipe_enemy.ship_compositions.assign([{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}])
	wipe_enemy.cargo = {Commodity.Type.ORE: 5.0}
	wipe_state.enemy_fleets.assign([wipe_enemy])
	wipe_state.start_engagement(wipe_enemy)
	wipe_state.resolve_engagement([], [])
	if wipe_state.pending_loot != null:
		failures.append("resolve_engagement(mutual wipe): expected no loot pending after a total loss")

	# Station repair: is_damaged/repair_cost_for/repair_ship.
	var damaged_comp := {
		"max_hp": 100.0, "current_hp": 50.0, "max_shield": 50.0, "current_shield": 50.0,
		"engine_max_hp": 20.0, "engine_current_hp": 20.0,
		"weapon_mount_max_hp": [10.0], "weapon_mount_current_hp": [10.0],
	}
	if not CampaignState.is_damaged(damaged_comp):
		failures.append("is_damaged: expected true when hull is below max")
	if CampaignState.repair_cost_for(damaged_comp) != CampaignState.REPAIR_COST:
		failures.append("repair_cost_for: expected REPAIR_COST for a damaged ship, got %s" % CampaignState.repair_cost_for(damaged_comp))

	var full_comp := {
		"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0,
		"engine_max_hp": 20.0, "engine_current_hp": 20.0,
		"weapon_mount_max_hp": [10.0], "weapon_mount_current_hp": [10.0],
	}
	if CampaignState.is_damaged(full_comp):
		failures.append("is_damaged: expected false for a fully healed ship")
	if CampaignState.repair_cost_for(full_comp) != 0.0:
		failures.append("repair_cost_for: expected 0.0 for a fully healed ship")

	var engine_damaged := {
		"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0,
		"engine_max_hp": 20.0, "engine_current_hp": 5.0,
		"weapon_mount_max_hp": [], "weapon_mount_current_hp": [],
	}
	if not CampaignState.is_damaged(engine_damaged):
		failures.append("is_damaged: expected true when only the engine is damaged")

	var mount_damaged := {
		"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0,
		"engine_max_hp": 20.0, "engine_current_hp": 20.0,
		"weapon_mount_max_hp": [10.0, 10.0], "weapon_mount_current_hp": [10.0, 0.0],
	}
	if not CampaignState.is_damaged(mount_damaged):
		failures.append("is_damaged: expected true when a weapon mount is damaged")

	var legacy_comp := {"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}
	if CampaignState.is_damaged(legacy_comp):
		failures.append("is_damaged: expected false for a legacy composition dict with no engine/mount fields")

	var repair_state := CampaignState.new()
	repair_state.credits = 200
	var to_repair := {
		"max_hp": 100.0, "current_hp": 10.0, "max_shield": 50.0, "current_shield": 0.0,
		"engine_max_hp": 20.0, "engine_current_hp": 2.0,
		"weapon_mount_max_hp": [10.0], "weapon_mount_current_hp": [1.0],
	}
	repair_state.repair_ship(to_repair)
	if repair_state.credits != 200 - CampaignState.REPAIR_COST:
		failures.append("repair_ship: expected credits reduced by REPAIR_COST, got %s" % repair_state.credits)
	if to_repair["current_hp"] != 100.0 or to_repair["current_shield"] != 50.0 or to_repair["engine_current_hp"] != 20.0 or to_repair["weapon_mount_current_hp"][0] != 10.0:
		failures.append("repair_ship: expected every field restored to max, got %s" % to_repair)

	# Whole credits: credits stay int after every spend or gain.
	var int_state := CampaignState.new()
	int_state.credits = 5000
	var int_economy := BaseEconomy.new()
	int_economy.stock = {Commodity.Type.ORE: 10.0}
	var int_fleet := CampaignFleet.new()
	int_fleet.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CAPITAL)])
	int_fleet.set_flagship(0)
	int_state.player_fleet = int_fleet
	int_state.buy(int_economy, Commodity.Type.ORE, int_fleet)
	if typeof(int_state.credits) != TYPE_INT:
		failures.append("buy: expected int credits, got type %d" % typeof(int_state.credits))
	int_state.sell(int_economy, Commodity.Type.ORE, int_fleet)
	if typeof(int_state.credits) != TYPE_INT:
		failures.append("sell: expected int credits, got type %d" % typeof(int_state.credits))
	int_economy.crew_pool = 10.0
	int_fleet.ship_compositions[0]["crew"] = 0
	int_state.hire_crew(int_economy, int_fleet, 2)
	if typeof(int_state.credits) != TYPE_INT:
		failures.append("hire_crew: expected int credits, got type %d" % typeof(int_state.credits))
	var int_damaged := {"max_hp": 100.0, "current_hp": 10.0, "max_shield": 0.0, "current_shield": 0.0}
	int_state.repair_ship(int_damaged)
	if typeof(int_state.credits) != TYPE_INT:
		failures.append("repair_ship: expected int credits, got type %d" % typeof(int_state.credits))
	if typeof(CampaignState.repair_cost_for(int_damaged)) != TYPE_INT:
		failures.append("repair_cost_for: expected int")
	var int_faction := PowerFaction.new()
	int_faction.faction_enum = CampaignFleet.Faction.DOMINION
	int_faction.fine = 150
	int_state.factions.assign([int_faction])
	int_state.pay_fine(CampaignFleet.Faction.DOMINION)
	if typeof(int_state.credits) != TYPE_INT:
		failures.append("pay_fine: expected int credits, got type %d" % typeof(int_state.credits))
	int_state.begin_respawn()
	if typeof(int_state.credits) != TYPE_INT:
		failures.append("begin_respawn: expected int credits, got type %d" % typeof(int_state.credits))
	int_state.free()

	# buy_part/sell_part/equip_part.
	var campaign_state := CampaignState.new()
	campaign_state.reset()
	campaign_state.credits = 1000
	var part_fleet := CampaignFleet.new()
	part_fleet.ship_compositions = [ShipType.new_composition(ShipType.Kind.CORVETTE)]

	if not campaign_state.buy_part("res://resources/weapons/railgun.tres", part_fleet):
		failures.append("buy_part: expected buying an affordable, in-capacity part to succeed")
	if part_fleet.part_inventory != ["res://resources/weapons/railgun.tres"]:
		failures.append("buy_part: expected the bought part added to part_inventory, got %s" % part_fleet.part_inventory)
	if campaign_state.credits != 1000 - PartRarity.price_for(PartRarity.Tier.RARE):
		failures.append("buy_part: expected credits debited by the railgun's RARE price, got %s" % campaign_state.credits)

	campaign_state.credits = 0
	if campaign_state.buy_part("res://resources/weapons/mass_driver.tres", part_fleet):
		failures.append("buy_part: expected buying to fail with insufficient credits")
	campaign_state.credits = 1000

	var credits_before_sell := campaign_state.credits
	if not campaign_state.sell_part(part_fleet, 0):
		failures.append("sell_part: expected selling an owned inventory part to succeed")
	if not part_fleet.part_inventory.is_empty():
		failures.append("sell_part: expected part_inventory emptied after selling its only item")
	if campaign_state.credits <= credits_before_sell:
		failures.append("sell_part: expected credits to increase after selling")
	if campaign_state.sell_part(part_fleet, 0):
		failures.append("sell_part: expected selling an out-of-range index to fail")

	# equip_part: budget enforcement. Corvette budget is 20 points; a RARE
	# weapon (15 points) plus a RARE shield (15 points) would be 30, over budget.
	var corvette_comp: Dictionary = part_fleet.ship_compositions[0]
	part_fleet.part_inventory = ["res://resources/weapons/railgun.tres", "res://resources/shields/shield_dominion_bulwark.tres"]
	if not campaign_state.equip_part(corvette_comp, part_fleet, ShipType.SlotType.WEAPON, 0, 0):
		failures.append("equip_part: expected equipping the RARE railgun (15/20 points) to succeed")
	if ShipType.equipped_path(corvette_comp, ShipType.SlotType.WEAPON, 0) != "res://resources/weapons/railgun.tres":
		failures.append("equip_part: expected the corvette's weapon slot to now hold the railgun")
	if part_fleet.part_inventory.has("res://resources/weapons/railgun.tres"):
		failures.append("equip_part: expected the equipped railgun removed from part_inventory")
	if campaign_state.equip_part(corvette_comp, part_fleet, ShipType.SlotType.SHIELD, 0, 0):
		failures.append("equip_part: expected equipping the RARE shield (would push 15+15=30 > 20 budget) to fail")

	# Swapping a different weapon back into the same slot returns the old one to inventory.
	part_fleet.part_inventory.append("res://resources/weapons/mass_driver.tres")
	if not campaign_state.equip_part(corvette_comp, part_fleet, ShipType.SlotType.WEAPON, 0, part_fleet.part_inventory.find("res://resources/weapons/mass_driver.tres")):
		failures.append("equip_part: expected swapping in the COMMON mass_driver (5 points) to succeed")
	if not part_fleet.part_inventory.has("res://resources/weapons/railgun.tres"):
		failures.append("equip_part: expected the swapped-out railgun returned to part_inventory")

	# equip_part is blocked on a damaged ship.
	corvette_comp["current_hp"] = 1.0
	if campaign_state.equip_part(corvette_comp, part_fleet, ShipType.SlotType.WEAPON, 0, part_fleet.part_inventory.find("res://resources/weapons/railgun.tres")):
		failures.append("equip_part: expected equip to be blocked on a damaged ship")
	corvette_comp["current_hp"] = corvette_comp["max_hp"]

	# equip_part on SHIELD updates max_shield/current_shield proportionally.
	part_fleet.part_inventory.append("res://resources/shields/shield_dominion_aegis.tres")
	var old_max_shield: float = corvette_comp["max_shield"]
	if not campaign_state.equip_part(corvette_comp, part_fleet, ShipType.SlotType.SHIELD, 0, part_fleet.part_inventory.find("res://resources/shields/shield_dominion_aegis.tres")):
		failures.append("equip_part: expected equipping the UNCOMMON aegis shield (10 points, within budget) to succeed")
	if not is_equal_approx(corvette_comp["max_shield"], 35.0):
		failures.append("equip_part: expected max_shield updated to the aegis shield's 35.0, got %s" % corvette_comp["max_shield"])
	if is_equal_approx(corvette_comp["max_shield"], old_max_shield):
		failures.append("equip_part: expected max_shield to actually change from the pre-equip value %s" % old_max_shield)
	if not is_equal_approx(corvette_comp["current_shield"], corvette_comp["max_shield"]):
		failures.append("equip_part: expected current_shield scaled up to the new max (was full before swap)")

	# equip_part: defensively rejects a type mismatch between the inventory
	# item and the slot (e.g. a shield resource into a WEAPON slot), even if
	# RefitPanel's UI-level filtering is bypassed or has a bug.
	var mismatch_inventory_before: Array[String] = part_fleet.part_inventory.duplicate()
	var mismatch_comp_before: Dictionary = corvette_comp.duplicate(true)
	var mismatch_shield_index: int = part_fleet.part_inventory.find("res://resources/shields/shield_dominion_bulwark.tres")
	if mismatch_shield_index == -1:
		part_fleet.part_inventory.append("res://resources/shields/shield_dominion_bulwark.tres")
		mismatch_shield_index = part_fleet.part_inventory.size() - 1
		mismatch_inventory_before = part_fleet.part_inventory.duplicate()
	if campaign_state.equip_part(corvette_comp, part_fleet, ShipType.SlotType.WEAPON, 0, mismatch_shield_index):
		failures.append("equip_part: expected equipping a shield into a WEAPON slot to fail")
	if part_fleet.part_inventory != mismatch_inventory_before:
		failures.append("equip_part: expected part_inventory unchanged after a rejected type-mismatch equip, got %s" % part_fleet.part_inventory)
	if corvette_comp != mismatch_comp_before:
		failures.append("equip_part: expected the composition unchanged after a rejected type-mismatch equip")

	# Crew hiring, wages and desertion.
	var hire_state := CampaignState.new()
	var hire_economy := BaseEconomy.new()
	hire_economy.crew_pool = 10.0
	var hire_fleet := CampaignFleet.new()
	hire_fleet.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	hire_fleet.ship_compositions[0]["crew"] = 9
	hire_state.credits = 500
	if not hire_state.hire_crew(hire_economy, hire_fleet, 3):
		failures.append("hire_crew: expected 3 hires to succeed")
	if hire_state.credits != 500 - 3 * CampaignState.CREW_HIRE_COST:
		failures.append("hire_crew: expected credits 380, got %s" % hire_state.credits)
	if not is_equal_approx(hire_economy.crew_pool, 7.0) or hire_fleet.crew_total() != 12:
		failures.append("hire_crew: expected pool 7 and crew 12, got %s / %s" % [hire_economy.crew_pool, hire_fleet.crew_total()])
	hire_fleet.ship_compositions[0]["crew"] = 8
	if hire_state.hire_crew(hire_economy, hire_fleet, 5):
		failures.append("hire_crew: expected failure when count exceeds free berths")
	hire_fleet.ship_compositions[0]["crew"] = 0
	if hire_state.hire_crew(hire_economy, hire_fleet, 8):
		failures.append("hire_crew: expected failure when count exceeds the pool")
	hire_state.credits = 100
	if hire_state.hire_crew(hire_economy, hire_fleet, 3):
		failures.append("hire_crew: expected failure when credits are short")
	if hire_state.hire_crew(hire_economy, hire_fleet, 0):
		failures.append("hire_crew: expected failure for count < 1")

	var wage_state := CampaignState.new()
	var wage_fleet := CampaignFleet.new()
	wage_fleet.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CAPITAL), ShipType.new_composition(ShipType.Kind.CORVETTE)])
	wage_fleet.set_flagship(0)
	wage_state.player_fleet = wage_fleet
	if wage_state.wage_bill(wage_fleet) != 4:
		failures.append("wage_bill: expected 4, got %s" % wage_state.wage_bill(wage_fleet))
	if wage_state.flagship_floor(wage_fleet) != 12:
		failures.append("flagship_floor: expected 12 for a capital, got %s" % wage_state.flagship_floor(wage_fleet))
	wage_state.credits = 1
	wage_state.pay_wages()
	if wage_state.credits != 0:
		failures.append("pay_wages: expected credits 0, got %s" % wage_state.credits)
	if wage_fleet.ship_compositions[1]["crew"] != 6 or wage_fleet.ship_compositions[0]["crew"] != 40:
		failures.append("pay_wages: expected 6 deserters from the corvette, got %s" % wage_fleet.ship_compositions)
	if typeof(wage_state.credits) != TYPE_INT:
		failures.append("pay_wages: expected int credits, got type %d" % typeof(wage_state.credits))
	wage_state.credits = 100
	wage_state.pay_wages()
	if wage_state.credits != 100 - 3:
		failures.append("pay_wages: expected full bill paid, got credits %s" % wage_state.credits)

	# Desertion with no credits never takes the flagship below its floor.
	var broke_state := CampaignState.new()
	var broke_fleet := CampaignFleet.new()
	broke_fleet.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CAPITAL), ShipType.new_composition(ShipType.Kind.CORVETTE)])
	broke_fleet.ship_compositions[0]["crew"] = 12
	broke_fleet.ship_compositions[1]["crew"] = 0
	broke_fleet.set_flagship(0)
	broke_state.player_fleet = broke_fleet
	broke_state.credits = 0
	for i in 20:
		broke_state.pay_wages()
	if broke_fleet.ship_compositions[0]["crew"] != 12 or broke_state.credits != 0:
		failures.append("pay_wages: flagship floor/credits violated, crew %s credits %s" % [broke_fleet.ship_compositions[0]["crew"], broke_state.credits])
	# Unpayable bill above the floor: deserters leave but the flagship stops at its floor.
	broke_fleet.ship_compositions[0]["crew"] = 40
	for i in 40:
		broke_state.pay_wages()
	# Under 10 billable crew is not a wage group: desertion stops there (12 floor + 8 free = 20).
	if broke_fleet.ship_compositions[0]["crew"] != 20 or broke_state.credits != 0:
		failures.append("pay_wages: expected flagship to settle at 20 (floor 12 + 8 unbilled crew), got %s" % broke_fleet.ship_compositions[0]["crew"])
	if broke_state.wage_bill(broke_fleet) != 0:
		failures.append("wage_bill: expected 0 under one full wage group, got %s" % broke_state.wage_bill(broke_fleet))

	# NPC crew: non-pirate fleets refill from their home station's pool, pirates regen a fixed amount.
	var npc_state := CampaignState.new()
	var npc_economy := BaseEconomy.new()
	npc_economy.crew_pool = 5.0
	npc_state.galaxy = _test_galaxy([_test_station("dom", CampaignFleet.Faction.DOMINION, npc_economy)])
	var npc_dominion := CampaignFleet.new()
	npc_dominion.faction = CampaignFleet.Faction.DOMINION
	npc_dominion.home_station_id = "dom"
	npc_dominion.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	npc_dominion.ship_compositions[0]["crew"] = 2
	var npc_pirate := CampaignFleet.new()
	npc_pirate.faction = CampaignFleet.Faction.PIRATE
	npc_pirate.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	npc_pirate.ship_compositions[0]["crew"] = 2
	var npc_homeless := CampaignFleet.new()
	npc_homeless.faction = CampaignFleet.Faction.NEUTRAL
	npc_homeless.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	npc_homeless.ship_compositions[0]["crew"] = 2
	npc_state.enemy_fleets.assign([npc_dominion, npc_pirate, npc_homeless])
	npc_state._refill_npc_crew()
	if CrewRules.crew_of(npc_dominion.ship_compositions[0]) != 7 or not is_equal_approx(npc_economy.crew_pool, 0.0):
		failures.append("_refill_npc_crew: expected Dominion crew 7 and pool 0.0, got %s / %s" % [CrewRules.crew_of(npc_dominion.ship_compositions[0]), npc_economy.crew_pool])
	if CrewRules.crew_of(npc_pirate.ship_compositions[0]) != 3:
		failures.append("_refill_npc_crew: expected pirate crew 3, got %s" % CrewRules.crew_of(npc_pirate.ship_compositions[0]))
	if CrewRules.crew_of(npc_homeless.ship_compositions[0]) != 2:
		failures.append("_refill_npc_crew: expected a fleet with no home station to get no crew, got %s" % CrewRules.crew_of(npc_homeless.ship_compositions[0]))

	campaign_state.reset()

	_check_reengage_delay(failures)
	return failures

static func _reengage_state() -> Array:
	var state := CampaignState.new()
	var player := CampaignFleet.new()
	player.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	state.player_fleet = player
	var enemy := CampaignFleet.new()
	enemy.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	var other := CampaignFleet.new()
	other.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
	state.enemy_fleets.assign([enemy, other])
	return [state, player, enemy, other]

# Enemy survivors escape, so the enemy fleet stays on the map.
static func _fight_and_escape(state, player: CampaignFleet, enemy: CampaignFleet) -> void:
	state.start_engagement(enemy)
	state.resolve_engagement(player.ship_compositions.duplicate(true), enemy.ship_compositions.duplicate(true), true)

static func _check_reengage_delay(failures: Array[String]) -> void:
	var parts := _reengage_state()
	var state = parts[0]
	var player: CampaignFleet = parts[1]
	var enemy: CampaignFleet = parts[2]
	var other: CampaignFleet = parts[3]
	if not state.can_engage(enemy):
		failures.append("reengage: expected a fresh fleet to be engageable")
	_fight_and_escape(state, player, enemy)
	if state.can_engage(enemy):
		failures.append("reengage_blocked_after_battle: expected the surviving enemy blocked after a battle")
	if not state.can_engage(other):
		failures.append("reengage_other_fleet_unaffected: expected an uninvolved fleet to stay engageable")
	state.tick_reengage(CampaignState.REENGAGE_DELAY - 1.0)
	if state.can_engage(enemy):
		failures.append("reengage: expected the block to hold before REENGAGE_DELAY elapses")
	state.tick_reengage(1.1)
	if not state.can_engage(enemy):
		failures.append("reengage_expires: expected the block to lift after REENGAGE_DELAY")

	var reset_parts := _reengage_state()
	var reset_state = reset_parts[0]
	_fight_and_escape(reset_state, reset_parts[1], reset_parts[2])
	reset_state.reset()
	if not reset_state.can_engage(reset_parts[2]):
		failures.append("reengage_cleared_on_reset: expected reset() to clear the block")

	var kill_parts := _reengage_state()
	var kill_state = kill_parts[0]
	kill_state.start_engagement(kill_parts[2])
	var no_survivors: Array[Dictionary] = []
	kill_state.resolve_engagement(kill_parts[1].ship_compositions.duplicate(true), no_survivors, true)
	if not kill_state._reengage_block.is_empty():
		failures.append("destroyed_enemy_not_tracked: expected no block for a destroyed enemy, got %s" % [kill_state._reengage_block])

	var gone_parts := _reengage_state()
	var gone_state = gone_parts[0]
	_fight_and_escape(gone_state, gone_parts[1], gone_parts[2])
	gone_state.enemy_fleets.erase(gone_parts[2])
	gone_state.tick_reengage(0.1)
	if not gone_state._reengage_block.is_empty():
		failures.append("reengage: expected tick_reengage to drop a fleet no longer in enemy_fleets")

	var loss_parts := _reengage_state()
	var loss_state = loss_parts[0]
	loss_state.start_engagement(loss_parts[2])
	var wiped: Array[Dictionary] = []
	loss_state.resolve_engagement(wiped, loss_parts[2].ship_compositions.duplicate(true), false)
	if not loss_state._reengage_block.is_empty():
		failures.append("reengage: expected no block when the player fleet is destroyed")

class SkirmishResolvedTracker:
	var fired := false
	var winner_fleet: CampaignFleet
	var loser_fleet: CampaignFleet
	func on_skirmish_resolved(winner: CampaignFleet, loser: CampaignFleet) -> void:
		fired = true
		winner_fleet = winner
		loser_fleet = loser

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var state := CampaignState.new()

	var dominion := PowerFaction.new()
	dominion.faction_enum = CampaignFleet.Faction.DOMINION
	var freehold := PowerFaction.new()
	freehold.faction_enum = CampaignFleet.Faction.FREEHOLD
	state.factions = [dominion, freehold]
	state.factions_at_war = true

	var dominion_fleet := CampaignFleet.new()
	dominion_fleet.faction = CampaignFleet.Faction.DOMINION
	var freehold_fleet := CampaignFleet.new()
	freehold_fleet.faction = CampaignFleet.Faction.FREEHOLD
	var trader_fleet := CampaignFleet.new()
	trader_fleet.faction = CampaignFleet.Faction.TRADER

	if not state.are_hostile(dominion_fleet, freehold_fleet):
		failures.append("are_hostile: expected two warring power factions to be hostile")
	if state.are_hostile(dominion_fleet, trader_fleet):
		failures.append("are_hostile: expected a power faction and a trader to be non-hostile")
	state.factions_at_war = false
	if state.are_hostile(dominion_fleet, freehold_fleet):
		failures.append("are_hostile: expected power factions at peace to be non-hostile")
	state.factions_at_war = true

	var pirate_fleet := CampaignFleet.new()
	pirate_fleet.faction = CampaignFleet.Faction.PIRATE
	if not state.are_hostile(pirate_fleet, dominion_fleet):
		failures.append("are_hostile: expected a pirate and a power faction to be hostile")
	var neutral_patrol := CampaignFleet.new()
	neutral_patrol.faction = CampaignFleet.Faction.NEUTRAL
	if not state.are_hostile(neutral_patrol, pirate_fleet) or not state.are_hostile(pirate_fleet, neutral_patrol):
		failures.append("are_hostile: expected a neutral patrol and a pirate to be hostile either way round")
	if state.are_hostile(neutral_patrol, dominion_fleet) or state.are_hostile(neutral_patrol, trader_fleet):
		failures.append("are_hostile: expected a neutral patrol to be non-hostile to power factions and traders")
	if state.are_hostile(pirate_fleet, trader_fleet) or state.are_hostile(pirate_fleet, pirate_fleet):
		failures.append("are_hostile: expected a pirate to be non-hostile to neutral traders and pirates")

	# start_skirmish + tick_skirmishes: stronger fleet wins, loser removed,
	# winner damaged proportionally, loser icon freed, winner icon unfrozen.
	var strong_fleet := CampaignFleet.new()
	strong_fleet.faction = CampaignFleet.Faction.DOMINION
	strong_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0}]
	var weak_fleet := CampaignFleet.new()
	weak_fleet.faction = CampaignFleet.Faction.FREEHOLD
	weak_fleet.ship_compositions = [{"max_hp": 20.0, "current_hp": 20.0, "max_shield": 0.0, "current_shield": 0.0}]

	state.enemy_fleets = [strong_fleet, weak_fleet]

	const CampaignFleetIconScene = preload("res://scenes/campaign/campaign_fleet_icon.tscn")
	var strong_icon: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(strong_icon)
	strong_icon.setup(strong_fleet, Vector2.ZERO)
	var weak_icon: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(weak_icon)
	weak_icon.setup(weak_fleet, Vector2.ZERO)

	var resolved_tracker := SkirmishResolvedTracker.new()
	state.skirmish_resolved.connect(resolved_tracker.on_skirmish_resolved)

	state.start_skirmish(strong_icon, weak_icon)
	if not strong_icon.frozen or not weak_icon.frozen:
		failures.append("start_skirmish: expected both icons frozen")
	if state.active_skirmishes.size() != 1:
		failures.append("start_skirmish: expected exactly one active skirmish, got %d" % state.active_skirmishes.size())

	var skirmish: Skirmish = state.active_skirmishes[0]
	if skirmish.fleet_winner != strong_fleet or skirmish.fleet_loser != weak_fleet:
		failures.append("start_skirmish: expected the stronger fleet to be recorded as winner")

	state.tick_skirmishes(skirmish.remaining_time + 1.0)
	if state.active_skirmishes.size() != 0:
		failures.append("tick_skirmishes: expected the skirmish to be resolved and removed")
	if state.enemy_fleets.has(weak_fleet):
		failures.append("tick_skirmishes: expected the loser fleet removed from enemy_fleets")
	if strong_fleet.ship_compositions[0]["current_hp"] >= 100.0:
		failures.append("tick_skirmishes: expected the winner to take proportional damage")
	if strong_icon.frozen:
		failures.append("tick_skirmishes: expected the winner icon to unfreeze")
	if not resolved_tracker.fired:
		failures.append("tick_skirmishes: expected skirmish_resolved to fire")
	elif resolved_tracker.winner_fleet != strong_fleet or resolved_tracker.loser_fleet != weak_fleet:
		failures.append("tick_skirmishes: expected skirmish_resolved to fire with the correct winner/loser fleets")

	await tree.process_frame

	if is_instance_valid(weak_icon):
		failures.append("tick_skirmishes: expected the loser icon to be freed")
	strong_icon.queue_free()

	# tick_skirmishes should drop (not resolve) a skirmish whose icons were
	# freed out-of-band (e.g. the scene that owned them was torn down across
	# a scene reload, as happens after a combat round-trip) -- no damage,
	# no fleet removal, no signal.
	var stale_fleet_winner := CampaignFleet.new()
	stale_fleet_winner.faction = CampaignFleet.Faction.DOMINION
	stale_fleet_winner.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0}]
	var stale_fleet_loser := CampaignFleet.new()
	stale_fleet_loser.faction = CampaignFleet.Faction.FREEHOLD
	stale_fleet_loser.ship_compositions = [{"max_hp": 20.0, "current_hp": 20.0, "max_shield": 0.0, "current_shield": 0.0}]
	state.enemy_fleets = [stale_fleet_winner, stale_fleet_loser]

	var stale_winner_icon: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(stale_winner_icon)
	stale_winner_icon.setup(stale_fleet_winner, Vector2.ZERO)
	var stale_loser_icon: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(stale_loser_icon)
	stale_loser_icon.setup(stale_fleet_loser, Vector2.ZERO)

	var stale_tracker := SkirmishResolvedTracker.new()
	state.skirmish_resolved.connect(stale_tracker.on_skirmish_resolved)

	state.start_skirmish(stale_winner_icon, stale_loser_icon)
	if state.active_skirmishes.size() != 1:
		failures.append("tick_skirmishes (stale icons): expected a skirmish to start")
	else:
		var stale_remaining_time: float = state.active_skirmishes[0].remaining_time
		# Simulate a scene reload: free both icons out-of-band, bypassing
		# CampaignState entirely, the way a real scene teardown would.
		stale_winner_icon.queue_free()
		stale_loser_icon.queue_free()
		await tree.process_frame

		state.tick_skirmishes(stale_remaining_time + 1.0)
		if state.active_skirmishes.size() != 0:
			failures.append("tick_skirmishes (stale icons): expected the stale skirmish to be dropped")
		if not state.enemy_fleets.has(stale_fleet_loser):
			failures.append("tick_skirmishes (stale icons): expected the loser fleet NOT erased from enemy_fleets when its icon is stale")
		if stale_fleet_winner.ship_compositions[0]["current_hp"] != 100.0:
			failures.append("tick_skirmishes (stale icons): expected no damage applied to the winner when icons are stale")
		if stale_tracker.fired:
			failures.append("tick_skirmishes (stale icons): expected skirmish_resolved NOT to fire for a dropped stale skirmish")

	state.skirmish_resolved.disconnect(stale_tracker.on_skirmish_resolved)

	# Skirmish winner crew shrinks with the damage fraction, never below NPC_CREW_FLOOR.
	for crew_case in [[0.5, 6], [1.0, 1]]:
		var crew_winner := CampaignFleet.new()
		crew_winner.faction = CampaignFleet.Faction.DOMINION
		crew_winner.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
		crew_winner.ship_compositions[0]["crew"] = 12
		var crew_loser := CampaignFleet.new()
		crew_loser.faction = CampaignFleet.Faction.FREEHOLD
		crew_loser.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CORVETTE)])
		var crew_winner_icon: Area2D = CampaignFleetIconScene.instantiate()
		tree.root.add_child(crew_winner_icon)
		crew_winner_icon.setup(crew_winner, Vector2.ZERO)
		var crew_loser_icon: Area2D = CampaignFleetIconScene.instantiate()
		tree.root.add_child(crew_loser_icon)
		crew_loser_icon.setup(crew_loser, Vector2.ZERO)
		var crew_skirmish := Skirmish.new()
		crew_skirmish.fleet_winner = crew_winner
		crew_skirmish.fleet_loser = crew_loser
		crew_skirmish.icon_winner = crew_winner_icon
		crew_skirmish.icon_loser = crew_loser_icon
		crew_skirmish.winner_damage_fraction = crew_case[0]
		state.active_skirmishes.append(crew_skirmish)
		state._resolve_skirmish(crew_skirmish)
		if CrewRules.crew_of(crew_winner.ship_compositions[0]) != crew_case[1]:
			failures.append("_resolve_skirmish: expected winner crew %d at damage %s, got %s" % [crew_case[1], crew_case[0], CrewRules.crew_of(crew_winner.ship_compositions[0])])
		crew_winner_icon.queue_free()

	# cancel_skirmish_for: starting a fresh skirmish and cancelling it
	# should unfreeze the untouched participant without resolving a winner.
	var fleet_c := CampaignFleet.new()
	fleet_c.faction = CampaignFleet.Faction.DOMINION
	fleet_c.ship_compositions = [{"max_hp": 50.0, "current_hp": 50.0, "max_shield": 0.0, "current_shield": 0.0}]
	var fleet_d := CampaignFleet.new()
	fleet_d.faction = CampaignFleet.Faction.FREEHOLD
	fleet_d.ship_compositions = [{"max_hp": 50.0, "current_hp": 50.0, "max_shield": 0.0, "current_shield": 0.0}]
	var icon_c: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(icon_c)
	icon_c.setup(fleet_c, Vector2.ZERO)
	var icon_d: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(icon_d)
	icon_d.setup(fleet_d, Vector2.ZERO)

	state.start_skirmish(icon_c, icon_d)
	state.cancel_skirmish_for(icon_c)
	if state.active_skirmishes.size() != 0:
		failures.append("cancel_skirmish_for: expected the skirmish removed")
	if icon_d.frozen:
		failures.append("cancel_skirmish_for: expected the other participant unfrozen")

	icon_c.queue_free()
	icon_d.queue_free()

	# start_engagement: engaging a fleet that's mid-skirmish should cancel
	# that skirmish and unfreeze the other participant.
	var fleet_e := CampaignFleet.new()
	fleet_e.faction = CampaignFleet.Faction.DOMINION
	fleet_e.ship_compositions = [{"max_hp": 50.0, "current_hp": 50.0, "max_shield": 0.0, "current_shield": 0.0}]
	var fleet_f := CampaignFleet.new()
	fleet_f.faction = CampaignFleet.Faction.FREEHOLD
	fleet_f.ship_compositions = [{"max_hp": 50.0, "current_hp": 50.0, "max_shield": 0.0, "current_shield": 0.0}]
	var icon_e: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(icon_e)
	icon_e.setup(fleet_e, Vector2.ZERO)
	var icon_f: Area2D = CampaignFleetIconScene.instantiate()
	tree.root.add_child(icon_f)
	icon_f.setup(fleet_f, Vector2.ZERO)

	state.start_skirmish(icon_e, icon_f)
	state.start_engagement(fleet_e)
	if state.active_skirmishes.size() != 0:
		failures.append("start_engagement: expected the skirmish involving the engaged fleet to be cancelled")
	if icon_f.frozen:
		failures.append("start_engagement: expected the other participant unfrozen")

	icon_e.queue_free()
	icon_f.queue_free()

	# resolve_engagement reputation decay.
	var defeat_state := CampaignState.new()
	var defeat_dominion := PowerFaction.new()
	defeat_dominion.faction_enum = CampaignFleet.Faction.DOMINION
	defeat_dominion.reputation = 60.0
	defeat_state.factions = [defeat_dominion]
	var defeat_player := CampaignFleet.new()
	defeat_player.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	defeat_state.player_fleet = defeat_player
	var defeated_enemy := CampaignFleet.new()
	defeated_enemy.faction = CampaignFleet.Faction.DOMINION
	defeated_enemy.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	defeat_state.start_engagement(defeated_enemy)
	defeat_state.resolve_engagement(
		[{"max_hp": 100.0, "current_hp": 80.0, "max_shield": 50.0, "current_shield": 50.0}],
		[]
	)
	if abs(defeat_dominion.reputation - 45.0) > 0.001:
		failures.append("resolve_engagement: expected reputation reduced by REPUTATION_LOSS_PER_DEFEAT to 45.0, got %s" % defeat_dominion.reputation)
	if defeat_dominion.fine != CampaignState.FINE_PER_KILL:
		failures.append("resolve_engagement: expected FINE_PER_KILL charged for destroying a faction fleet, got %s" % defeat_dominion.fine)
	if defeat_dominion.fine_reputation != CampaignState.REPUTATION_LOSS_PER_DEFEAT:
		failures.append("resolve_engagement: expected fine_reputation to record the reputation lost, got %s" % defeat_dominion.fine_reputation)

	# Fines stack; at low reputation only the actual (clamped) loss is recorded.
	defeat_dominion.reputation = 5.0
	var second_enemy := CampaignFleet.new()
	second_enemy.faction = CampaignFleet.Faction.DOMINION
	second_enemy.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	defeat_state.start_engagement(second_enemy)
	defeat_state.resolve_engagement(defeat_player.ship_compositions, [])
	if defeat_dominion.fine != CampaignState.FINE_PER_KILL * 2:
		failures.append("fines: expected two kills to stack fines, got %s" % defeat_dominion.fine)
	if defeat_dominion.fine_reputation != CampaignState.REPUTATION_LOSS_PER_DEFEAT + 5.0:
		failures.append("fines: expected the clamped 5.0 loss recorded, got fine_reputation %s" % defeat_dominion.fine_reputation)

	# pay_fine: refused without enough credits, then clears the fine and restores reputation.
	var signalled: Array = []
	defeat_state.faction_reputation_changed.connect(func(f): signalled.append(f))
	defeat_state.credits = defeat_dominion.fine - 1
	if defeat_state.pay_fine(CampaignFleet.Faction.DOMINION):
		failures.append("pay_fine: expected refusal when credits cannot cover the fine")
	defeat_state.credits = 1000
	if not defeat_state.pay_fine(CampaignFleet.Faction.DOMINION):
		failures.append("pay_fine: expected success with enough credits")
	if defeat_state.credits != 1000 - CampaignState.FINE_PER_KILL * 2:
		failures.append("pay_fine: expected the fine deducted, got credits %s" % defeat_state.credits)
	if defeat_dominion.reputation != 0.0 + CampaignState.REPUTATION_LOSS_PER_DEFEAT + 5.0:
		failures.append("pay_fine: expected recorded reputation restored, got %s" % defeat_dominion.reputation)
	if defeat_dominion.fine != 0 or defeat_dominion.fine_reputation != 0.0:
		failures.append("pay_fine: expected fine cleared, got fine=%s rep=%s" % [defeat_dominion.fine, defeat_dominion.fine_reputation])
	if signalled != [CampaignFleet.Faction.DOMINION]:
		failures.append("pay_fine: expected one faction_reputation_changed(DOMINION) emission, got %s" % [signalled])
	if defeat_state.pay_fine(CampaignFleet.Faction.DOMINION):
		failures.append("pay_fine: expected refusal when nothing is owed")
	if defeat_state.pay_fine(CampaignFleet.Faction.FREEHOLD):
		failures.append("pay_fine: expected refusal for a faction not in play")
	defeat_state.free()

	# scuttle_check / scuttle_ship / jettison.
	var scuttle_state := CampaignState.new()
	var scuttle_fleet := _scuttle_fleet()
	scuttle_fleet.cargo = {Commodity.Type.ORE: 70.0}
	var overflow_check: Dictionary = scuttle_state.scuttle_check(scuttle_fleet, 1)
	if not overflow_check["allowed"] or not is_equal_approx(overflow_check["cargo_overflow"], 50.0) or overflow_check["crew_lost"] != 6:
		failures.append("scuttle_check: expected allowed, overflow 50 and crew_lost 6, got %s" % [overflow_check])
	if scuttle_state.scuttle_ship(scuttle_fleet, 1):
		failures.append("scuttle_ship: expected refusal while cargo overflows the remaining capacity")
	if scuttle_fleet.ship_compositions.size() != 2:
		failures.append("scuttle_ship: expected a refused scuttle to leave the fleet intact")
	var flagship_check: Dictionary = scuttle_state.scuttle_check(scuttle_fleet, 0)
	if flagship_check["allowed"] or flagship_check["reason"] != "Flagship":
		failures.append("scuttle_check: expected the flagship refused with reason 'Flagship', got %s" % [flagship_check])
	scuttle_state.jettison(scuttle_fleet, {Commodity.Type.ORE: 50.0}, [], {})
	if not scuttle_state.scuttle_ship(scuttle_fleet, 1):
		failures.append("scuttle_ship: expected success after jettisoning the overflow")
	if scuttle_fleet.ship_compositions.size() != 1 or scuttle_fleet.crew_total() != 40:
		failures.append("scuttle_ship: expected 1 ship and crew 40, got %d ships crew %d" % [scuttle_fleet.ship_compositions.size(), scuttle_fleet.crew_total()])
	var last_check: Dictionary = scuttle_state.scuttle_check(scuttle_fleet, 0)
	if last_check["allowed"]:
		failures.append("scuttle_check: expected the last ship refused")
	var moved_fleet := _scuttle_fleet()
	moved_fleet.ship_compositions[0]["crew"] = 30
	var moved_check: Dictionary = scuttle_state.scuttle_check(moved_fleet, 1)
	if moved_check["crew_lost"] != 0:
		failures.append("scuttle_check: expected crew to fit on the other ships, got crew_lost %d" % moved_check["crew_lost"])
	scuttle_state.scuttle_ship(moved_fleet, 1)
	if CrewRules.crew_of(moved_fleet.ship_compositions[0]) != 36:
		failures.append("scuttle_ship: expected the freighter crew moved aboard (36), got %d" % CrewRules.crew_of(moved_fleet.ship_compositions[0]))
	var jet_fleet := _scuttle_fleet()
	jet_fleet.cargo = {Commodity.Type.ORE: 5.0, Commodity.Type.FOOD: 3.0}
	jet_fleet.part_inventory.assign(["a", "b", "c"])
	var jet_indices: Array[int] = [0, 2]
	scuttle_state.jettison(jet_fleet, {Commodity.Type.ORE: 99.0, Commodity.Type.FOOD: 1.0}, jet_indices, {0: 40, 1: 2})
	if not is_equal_approx(jet_fleet.cargo.get(Commodity.Type.ORE, 0.0), 0.0) or not is_equal_approx(jet_fleet.cargo.get(Commodity.Type.FOOD, 0.0), 2.0):
		failures.append("jettison: expected amounts clamped to held, got %s" % [jet_fleet.cargo])
	if jet_fleet.part_inventory != ["b"]:
		failures.append("jettison: expected parts 0 and 2 removed, got %s" % [jet_fleet.part_inventory])
	if CrewRules.crew_of(jet_fleet.ship_compositions[0]) != 12 or CrewRules.crew_of(jet_fleet.ship_compositions[1]) != 4:
		failures.append("jettison: expected flagship floored at 12 and freighter at 4, got %d / %d" % [CrewRules.crew_of(jet_fleet.ship_compositions[0]), CrewRules.crew_of(jet_fleet.ship_compositions[1])])
	scuttle_state.free()

	# Respawn: credit penalty, loss of cargo/parts/ships; reputation and fines kept.
	var respawn_state = CampaignState.new()
	var respawn_faction := PowerFaction.new()
	respawn_faction.fine = 150
	respawn_faction.reputation = 30.0
	respawn_state.factions.assign([respawn_faction])
	var respawn_fleet := CampaignFleet.new()
	respawn_fleet.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CAPITAL)])
	respawn_fleet.cargo = {Commodity.Type.ORE: 5.0}
	respawn_fleet.part_inventory.assign(["res://resources/weapons/kinetic_cannon.tres"])
	respawn_state.player_fleet = respawn_fleet
	respawn_state.credits = 400
	respawn_state.begin_respawn()
	if not respawn_state.pending_respawn:
		failures.append("begin_respawn: expected pending_respawn set")
	if respawn_state.credits != 300:
		failures.append("begin_respawn: expected 300 credits, got %s" % respawn_state.credits)
	if not respawn_fleet.cargo.is_empty() or not respawn_fleet.part_inventory.is_empty() or not respawn_fleet.ship_compositions.is_empty():
		failures.append("begin_respawn: expected cargo, parts and ships cleared")
	if respawn_faction.fine != 150 or respawn_faction.reputation != 30.0:
		failures.append("begin_respawn: expected fine and reputation untouched")
	if respawn_state.complete_respawn(ShipType.Kind.CAPITAL, true):
		failures.append("complete_respawn: expected buying a capital at 300 credits to fail")
	if not respawn_state.pending_respawn or not respawn_fleet.ship_compositions.is_empty():
		failures.append("complete_respawn: expected a failed buy to change nothing")
	if not respawn_state.complete_respawn(ShipType.Kind.CAPITAL, false):
		failures.append("complete_respawn: expected the free respawn to succeed")
	var free_comps: Array[Dictionary] = respawn_fleet.ship_compositions
	if free_comps.size() != 1 or ShipType.kind_of(free_comps[0]) != ShipType.Kind.CORVETTE:
		failures.append("complete_respawn: expected one free corvette regardless of kind")
	elif CrewRules.crew_of(free_comps[0]) != 4 or not CrewRules.is_flagship(free_comps[0]):
		failures.append("complete_respawn: expected corvette crew 4 and flagship, got %s" % free_comps[0])
	if respawn_state.credits != 300:
		failures.append("complete_respawn: expected the free ship to cost nothing, got %s" % respawn_state.credits)
	if respawn_state.pending_respawn:
		failures.append("complete_respawn: expected pending_respawn cleared")
	respawn_fleet.ship_compositions.clear()
	if respawn_state.complete_respawn(ShipType.Kind.FREIGHTER, true):
		failures.append("complete_respawn: expected buying a freighter at 300 credits to fail")
	respawn_state.credits = 600
	if not respawn_state.complete_respawn(ShipType.Kind.FREIGHTER, true):
		failures.append("complete_respawn: expected buying a freighter at 600 credits to succeed")
	elif respawn_state.credits != 100 or CrewRules.crew_of(respawn_fleet.ship_compositions[0]) != 2:
		failures.append("complete_respawn: expected 100 credits left and freighter crew 2")
	respawn_state.credits = 10
	respawn_state.begin_respawn()
	if respawn_state.credits != 7:
		failures.append("begin_respawn: expected 7 credits, got %s" % respawn_state.credits)
	respawn_state.credits = 401
	respawn_state.begin_respawn()
	if respawn_state.credits != 300 or typeof(respawn_state.credits) != TYPE_INT:
		failures.append("begin_respawn: expected int 300 credits from 401, got %s" % respawn_state.credits)
	respawn_state.reset()
	if respawn_state.pending_respawn:
		failures.append("reset: expected pending_respawn cleared")
	respawn_state.free()

	return failures

static func _scuttle_fleet() -> CampaignFleet:
	var fleet := CampaignFleet.new()
	var capital := ShipType.new_composition(ShipType.Kind.CAPITAL)
	var freighter := ShipType.new_composition(ShipType.Kind.FREIGHTER)
	capital["crew"] = 40
	freighter["crew"] = 6
	fleet.ship_compositions.assign([capital, freighter])
	fleet.set_flagship(0)
	return fleet

static func _test_galaxy(stations: Array) -> Galaxy:
	var galaxy := Galaxy.new()
	var sys := StarSystem.new()
	sys.id = "test"
	galaxy.systems[sys.id] = sys
	for st in stations:
		galaxy.add_station(st)
	return galaxy

static func _test_station(id: String, owner: CampaignFleet.Faction, economy: BaseEconomy) -> StationData:
	var station := StationData.new()
	station.id = id
	station.system_id = "test"
	station.owner = owner
	station.economy = economy
	return station

static func _test_station_fleet(home_id: String, faction: CampaignFleet.Faction, role: CampaignFleet.Role, hp: float) -> CampaignFleet:
	var fleet := CampaignFleet.new()
	fleet.faction = faction
	fleet.role = role
	fleet.home_station_id = home_id
	fleet.system_id = "test"
	fleet.ship_compositions = [{"max_hp": hp, "current_hp": hp, "max_shield": 0.0, "current_shield": 0.0}]
	return fleet
