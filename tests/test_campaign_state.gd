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
	trade_state.credits = 50.0
	var trade_economy := BaseEconomy.new()
	trade_economy.stock = {Commodity.Type.ORE: 10.0}
	var trade_fleet := CampaignFleet.new()
	trade_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var buy_price: float = trade_economy.price_for(Commodity.Type.ORE)
	var bought: bool = trade_state.buy(trade_economy, Commodity.Type.ORE, trade_fleet)
	if not bought:
		failures.append("buy: expected a well-funded, in-capacity purchase to succeed")
	if abs(trade_state.credits - (50.0 - buy_price)) > 0.001:
		failures.append("buy: expected credits reduced by buy_price, got %s" % trade_state.credits)
	if trade_economy.stock.get(Commodity.Type.ORE, 0.0) != 9.0:
		failures.append("buy: expected base stock reduced by 1, got %s" % trade_economy.stock.get(Commodity.Type.ORE, 0.0))
	if trade_fleet.cargo.get(Commodity.Type.ORE, 0.0) != 1.0:
		failures.append("buy: expected fleet cargo increased by 1, got %s" % trade_fleet.cargo.get(Commodity.Type.ORE, 0.0))

	trade_state.credits = 0.0
	var bought_broke: bool = trade_state.buy(trade_economy, Commodity.Type.ORE, trade_fleet)
	if bought_broke:
		failures.append("buy: expected purchase to fail with 0 credits")

	var sell_price: float = trade_economy.sell_price_for(Commodity.Type.ORE)
	var sold: bool = trade_state.sell(trade_economy, Commodity.Type.ORE, trade_fleet)
	if not sold:
		failures.append("sell: expected selling held cargo to succeed")
	if abs(trade_state.credits - sell_price) > 0.001:
		failures.append("sell: expected credits increased by sell_price, got %s" % trade_state.credits)
	if trade_fleet.cargo.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("sell: expected fleet cargo reduced by 1, got %s" % trade_fleet.cargo.get(Commodity.Type.ORE, 0.0))

	var sold_empty: bool = trade_state.sell(trade_economy, Commodity.Type.ORE, trade_fleet)
	if sold_empty:
		failures.append("sell: expected selling with no cargo held to fail")

	# buy: out-of-stock base should fail without touching credits/cargo/stock.
	var out_of_stock_state := CampaignState.new()
	out_of_stock_state.credits = 50.0
	var out_of_stock_economy := BaseEconomy.new()
	out_of_stock_economy.stock = {Commodity.Type.ORE: 0.0}
	var out_of_stock_fleet := CampaignFleet.new()
	out_of_stock_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var bought_out_of_stock: bool = out_of_stock_state.buy(out_of_stock_economy, Commodity.Type.ORE, out_of_stock_fleet)
	if bought_out_of_stock:
		failures.append("buy: expected purchase to fail when base stock is below 1.0")
	if out_of_stock_state.credits != 50.0:
		failures.append("buy: expected credits unchanged when base stock is below 1.0, got %s" % out_of_stock_state.credits)
	if out_of_stock_fleet.cargo.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("buy: expected fleet cargo unchanged when base stock is below 1.0")
	if out_of_stock_economy.stock.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("buy: expected base stock unchanged when base stock is below 1.0")

	# buy: fleet cargo already at capacity should fail without touching credits/cargo/stock.
	var full_cargo_state := CampaignState.new()
	full_cargo_state.credits = 50.0
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
	if full_cargo_state.credits != 50.0:
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
	tick_state.home_base_economy = ticked_economy
	tick_state.tick_economy(1.0)
	if ticked_economy.stock.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("tick_economy: expected no tick yet before the interval elapses")
	tick_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
	if ticked_economy.stock.get(Commodity.Type.ORE, 0.0) != 5.0:
		failures.append("tick_economy: expected one economy tick once the interval elapses, got Ore=%s" % ticked_economy.stock.get(Commodity.Type.ORE, 0.0))

	# tick_economy: per-faction economies tick too, and a null economy is skipped.
	var faction_tick_state := CampaignState.new()
	var economy_faction := PowerFaction.new()
	var faction_economy := BaseEconomy.new()
	faction_economy.slots = [EconomyRole.mining()]
	faction_economy.max_slots = 1
	economy_faction.economy = faction_economy
	var no_economy_faction := PowerFaction.new()
	no_economy_faction.economy = null
	faction_tick_state.factions = [economy_faction, no_economy_faction]

	faction_tick_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
	if faction_economy.stock.get(Commodity.Type.ORE, 0.0) != 5.0:
		failures.append("tick_economy: expected the faction's economy to tick, got Ore=%s" % faction_economy.stock.get(Commodity.Type.ORE, 0.0))
	if no_economy_faction.economy != null:
		failures.append("tick_economy: expected the null-economy faction to remain untouched")

	# reset() clears the new economy fields too.
	tick_state.credits = 10.0
	tick_state.reset()
	if tick_state.credits != 500.0:
		failures.append("reset: expected credits reset to 500.0, got %s" % tick_state.credits)
	if tick_state.home_base_economy != null:
		failures.append("reset: expected home_base_economy cleared to null")

	# run_npc_trade_for_fleet: at the faction base, loads surplus commodities
	# (produced more than consumed) from the faction's own stock into cargo.
	var trade_route_state := CampaignState.new()
	var trade_route_faction := PowerFaction.new()
	trade_route_faction.faction_enum = CampaignFleet.Faction.FREEHOLD
	trade_route_faction.economy = BaseEconomy.new()
	trade_route_faction.economy.slots = [EconomyRole.mining(), EconomyRole.agriculture()]
	trade_route_faction.economy.stock = {Commodity.Type.ORE: 15.0, Commodity.Type.FOOD: 15.0}
	trade_route_state.factions = [trade_route_faction]
	trade_route_state.home_base_economy = BaseEconomy.new()

	var hauler := CampaignFleet.new()
	hauler.faction = CampaignFleet.Faction.FREEHOLD
	hauler.role = CampaignFleet.Role.TRADER
	hauler.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
	]

	trade_route_state.run_npc_trade_for_fleet(hauler, true)
	if hauler.cargo_total() <= 0.0:
		failures.append("run_npc_trade_for_fleet: expected loading surplus at the faction base to fill cargo")
	# Cargo capacity (40.0, two ships) comfortably covers both commodities'
	# combined stock (30.0), so both must be drawn down individually -- this
	# proves the loop handles every surplus commodity, not just the first one
	# it encounters.
	if trade_route_faction.economy.stock.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("run_npc_trade_for_fleet: expected loading surplus to draw down Ore stock to 0.0, got %s" % trade_route_faction.economy.stock.get(Commodity.Type.ORE, 0.0))
	if trade_route_faction.economy.stock.get(Commodity.Type.FOOD, 0.0) != 0.0:
		failures.append("run_npc_trade_for_fleet: expected loading surplus to draw down Food stock to 0.0, got %s" % trade_route_faction.economy.stock.get(Commodity.Type.FOOD, 0.0))

	# Arriving at HomeBase: dumps carried cargo into home_base_economy.stock,
	# then loads whatever the faction nets a deficit on (here, nothing is
	# consumed by mining/agriculture, so no deficit cargo should be loaded).
	trade_route_state.home_base_economy.stock[Commodity.Type.FUEL] = 20.0
	var cargo_before_dump: Dictionary = hauler.cargo.duplicate()
	trade_route_state.run_npc_trade_for_fleet(hauler, false)
	for commodity in cargo_before_dump:
		if trade_route_state.home_base_economy.stock.get(commodity, 0.0) < cargo_before_dump[commodity]:
			failures.append("run_npc_trade_for_fleet: expected carried cargo dumped into home_base_economy.stock")
	if hauler.cargo_total() != 0.0:
		failures.append("run_npc_trade_for_fleet: expected no deficit cargo loaded for a faction with no consuming slots, got cargo=%s" % hauler.cargo)

	# A faction with a deficit (Dominion needs Ore/Fuel/Food) loads from
	# home_base_economy.stock when arriving at HomeBase.
	var deficit_faction := PowerFaction.new()
	deficit_faction.faction_enum = CampaignFleet.Faction.DOMINION
	deficit_faction.economy = BaseEconomy.new()
	deficit_faction.economy.slots = [EconomyRole.industrial(), EconomyRole.population()]
	trade_route_state.factions.append(deficit_faction)
	trade_route_state.home_base_economy.stock[Commodity.Type.ORE] = 30.0

	var deficit_hauler := CampaignFleet.new()
	deficit_hauler.faction = CampaignFleet.Faction.DOMINION
	deficit_hauler.role = CampaignFleet.Role.TRADER
	deficit_hauler.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	trade_route_state.run_npc_trade_for_fleet(deficit_hauler, false)
	if deficit_hauler.cargo.get(Commodity.Type.ORE, 0.0) <= 0.0:
		failures.append("run_npc_trade_for_fleet: expected Dominion's hauler to load Ore (a deficit commodity) from home_base_economy.stock")

	# No-op cases: unknown faction, null economy, null home_base_economy.
	var orphan_hauler := CampaignFleet.new()
	orphan_hauler.faction = CampaignFleet.Faction.PIRATE
	trade_route_state.run_npc_trade_for_fleet(orphan_hauler, true)
	if orphan_hauler.cargo_total() != 0.0:
		failures.append("run_npc_trade_for_fleet: expected no-op for a faction with no matching PowerFaction")

	var null_economy_faction := PowerFaction.new()
	null_economy_faction.faction_enum = CampaignFleet.Faction.TRADER
	null_economy_faction.economy = null
	trade_route_state.factions.append(null_economy_faction)
	var null_economy_hauler := CampaignFleet.new()
	null_economy_hauler.faction = CampaignFleet.Faction.TRADER
	null_economy_hauler.role = CampaignFleet.Role.TRADER
	null_economy_hauler.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	trade_route_state.run_npc_trade_for_fleet(null_economy_hauler, true)
	if null_economy_hauler.cargo_total() != 0.0:
		failures.append("run_npc_trade_for_fleet: expected no-op for a matching PowerFaction with a null economy")

	var no_home_base_state := CampaignState.new()
	var no_home_base_faction := PowerFaction.new()
	no_home_base_faction.faction_enum = CampaignFleet.Faction.FREEHOLD
	no_home_base_faction.economy = BaseEconomy.new()
	no_home_base_faction.economy.slots = [EconomyRole.mining()]
	no_home_base_faction.economy.stock = {Commodity.Type.ORE: 50.0}
	no_home_base_state.factions = [no_home_base_faction]
	no_home_base_state.home_base_economy = null
	var no_home_base_hauler := CampaignFleet.new()
	no_home_base_hauler.faction = CampaignFleet.Faction.FREEHOLD
	no_home_base_hauler.role = CampaignFleet.Role.TRADER
	no_home_base_hauler.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	no_home_base_state.run_npc_trade_for_fleet(no_home_base_hauler, true)
	if no_home_base_hauler.cargo_total() != 0.0:
		failures.append("run_npc_trade_for_fleet: expected no-op when home_base_economy is null")
	if no_home_base_faction.economy.stock.get(Commodity.Type.ORE, 0.0) != 50.0:
		failures.append("run_npc_trade_for_fleet: expected faction stock unchanged when home_base_economy is null")

	# Fleet allocation: a faction outmatched by pirates, with a healthy
	# economy, grows a ship on its existing combat fleet.
	var grow_combat_state := CampaignState.new()
	var grow_combat_faction := PowerFaction.new()
	grow_combat_faction.faction_enum = CampaignFleet.Faction.DOMINION
	grow_combat_faction.economy = BaseEconomy.new()
	grow_combat_faction.economy.slots = [EconomyRole.mining()]  # no consumption -> never in deficit
	grow_combat_state.factions = [grow_combat_faction]
	grow_combat_state.home_base_economy = BaseEconomy.new()

	var weak_combat_fleet := CampaignFleet.new()
	weak_combat_fleet.faction = CampaignFleet.Faction.DOMINION
	weak_combat_fleet.role = CampaignFleet.Role.COMBAT
	weak_combat_fleet.ship_compositions = [{"max_hp": 10.0, "current_hp": 10.0, "max_shield": 0.0, "current_shield": 0.0}]
	var strong_pirate_fleet := CampaignFleet.new()
	strong_pirate_fleet.faction = CampaignFleet.Faction.PIRATE
	strong_pirate_fleet.ship_compositions = [{"max_hp": 1000.0, "current_hp": 1000.0, "max_shield": 0.0, "current_shield": 0.0}]
	grow_combat_state.enemy_fleets = [weak_combat_fleet, strong_pirate_fleet]

	var ships_before: int = weak_combat_fleet.ship_compositions.size()
	grow_combat_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
	if weak_combat_fleet.ship_compositions.size() != ships_before + 1:
		failures.append("tick_economy: expected an outmatched combat fleet to grow a ship, had %d before, %d after" % [ships_before, weak_combat_fleet.ship_compositions.size()])

	# A faction that's economically strong and safe from pirates grows a new
	# trader fleet (spawn, since its one existing trader is already at the
	# ship cap would be a separate case -- here there is no trader fleet yet,
	# so this exercises the spawn-a-new-fleet path).
	var grow_trade_state := CampaignState.new()
	var grow_trade_faction := PowerFaction.new()
	grow_trade_faction.faction_enum = CampaignFleet.Faction.FREEHOLD
	grow_trade_faction.economy = BaseEconomy.new()
	grow_trade_faction.economy.slots = [EconomyRole.mining()]
	grow_trade_faction.base_position = Vector2(150, 150)
	grow_trade_state.factions = [grow_trade_faction]
	grow_trade_state.home_base_economy = BaseEconomy.new()

	var safe_combat_fleet := CampaignFleet.new()
	safe_combat_fleet.faction = CampaignFleet.Faction.FREEHOLD
	safe_combat_fleet.role = CampaignFleet.Role.COMBAT
	safe_combat_fleet.ship_compositions = [{"max_hp": 1000.0, "current_hp": 1000.0, "max_shield": 0.0, "current_shield": 0.0}]
	grow_trade_state.enemy_fleets = [safe_combat_fleet]

	var spawned := []
	grow_trade_state.fleet_spawn_requested.connect(func(fleet: CampaignFleet): spawned.append(fleet))
	for i in BaseEconomy.SURPLUS_STREAK_THRESHOLD + 1:
		grow_trade_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
	if spawned.is_empty():
		failures.append("tick_economy: expected an economically strong, safe faction to spawn a new trader fleet")
	elif spawned[0].role != CampaignFleet.Role.TRADER:
		failures.append("tick_economy: expected the spawned fleet's role to be TRADER")

	# Reallocation: an outmatched faction in economic deficit with 2 trader
	# fleets flips one to COMBAT instead of growing (can't afford to grow).
	var reallocate_state := CampaignState.new()
	var reallocate_faction := PowerFaction.new()
	reallocate_faction.faction_enum = CampaignFleet.Faction.DOMINION
	reallocate_faction.economy = BaseEconomy.new()
	reallocate_faction.economy.slots = [EconomyRole.industrial()]  # will starve immediately, no inputs
	reallocate_state.factions = [reallocate_faction]
	reallocate_state.home_base_economy = BaseEconomy.new()

	var weak_combat_fleet_2 := CampaignFleet.new()
	weak_combat_fleet_2.faction = CampaignFleet.Faction.DOMINION
	weak_combat_fleet_2.role = CampaignFleet.Role.COMBAT
	weak_combat_fleet_2.ship_compositions = [{"max_hp": 1.0, "current_hp": 1.0, "max_shield": 0.0, "current_shield": 0.0}]
	var trader_fleet_1 := CampaignFleet.new()
	trader_fleet_1.faction = CampaignFleet.Faction.DOMINION
	trader_fleet_1.role = CampaignFleet.Role.TRADER
	trader_fleet_1.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0}]
	var trader_fleet_2 := CampaignFleet.new()
	trader_fleet_2.faction = CampaignFleet.Faction.DOMINION
	trader_fleet_2.role = CampaignFleet.Role.TRADER
	trader_fleet_2.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0}]
	var strong_pirate_fleet_2 := CampaignFleet.new()
	strong_pirate_fleet_2.faction = CampaignFleet.Faction.PIRATE
	strong_pirate_fleet_2.ship_compositions = [{"max_hp": 1000.0, "current_hp": 1000.0, "max_shield": 0.0, "current_shield": 0.0}]
	reallocate_state.enemy_fleets = [weak_combat_fleet_2, trader_fleet_1, trader_fleet_2, strong_pirate_fleet_2]

	var role_changes := []
	reallocate_state.fleet_role_changed.connect(func(fleet: CampaignFleet): role_changes.append(fleet))
	reallocate_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
	if role_changes.size() != 1:
		failures.append("tick_economy: expected exactly one fleet reallocated to COMBAT, got %d" % role_changes.size())
	elif role_changes[0].role != CampaignFleet.Role.COMBAT:
		failures.append("tick_economy: expected the reallocated fleet's role to now be COMBAT")

	return failures

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

	return failures
