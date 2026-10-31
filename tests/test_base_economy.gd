# tests/test_base_economy.gd
extends RefCounted

const BaseEconomy = preload("res://scripts/campaign/base_economy.gd")
const EconomyRole = preload("res://scripts/campaign/economy_role.gd")
const Commodity = preload("res://scripts/campaign/commodity.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	# Production: a MINING slot adds Ore to stock each tick.
	var mining_base := BaseEconomy.new()
	mining_base.slots = [EconomyRole.mining()]
	mining_base.max_slots = 1
	mining_base.tick()
	if mining_base.stock.get(Commodity.Type.ORE, 0.0) != 5.0:
		failures.append("tick: expected MINING to add 5.0 Ore, got %s" % mining_base.stock.get(Commodity.Type.ORE, 0.0))

	# Consumption: INDUSTRIAL draws down Ore/Fuel and adds Weapons when stocked.
	var industrial_base := BaseEconomy.new()
	industrial_base.slots = [EconomyRole.industrial()]
	industrial_base.max_slots = 1
	industrial_base.stock = {Commodity.Type.ORE: 10.0, Commodity.Type.FUEL: 10.0}
	industrial_base.tick()
	if industrial_base.stock.get(Commodity.Type.ORE, 0.0) != 7.0:
		failures.append("tick: expected Ore drawn down to 7.0, got %s" % industrial_base.stock.get(Commodity.Type.ORE, 0.0))
	if industrial_base.stock.get(Commodity.Type.FUEL, 0.0) != 8.0:
		failures.append("tick: expected Fuel drawn down to 8.0, got %s" % industrial_base.stock.get(Commodity.Type.FUEL, 0.0))
	if industrial_base.stock.get(Commodity.Type.WEAPONS, 0.0) != 2.0:
		failures.append("tick: expected Weapons produced to 2.0, got %s" % industrial_base.stock.get(Commodity.Type.WEAPONS, 0.0))
	if industrial_base.deficit_streaks.get(0, 0) != 0:
		failures.append("tick: expected deficit streak reset to 0 when fully stocked")

	# Deficit: insufficient input drains that slot's inputs to 0 and increments its streak.
	var starved_base := BaseEconomy.new()
	starved_base.slots = [EconomyRole.industrial()]
	starved_base.max_slots = 1
	starved_base.stock = {Commodity.Type.ORE: 1.0, Commodity.Type.FUEL: 10.0}
	starved_base.tick()
	if starved_base.stock.get(Commodity.Type.ORE, 0.0) != 0.0:
		failures.append("tick: expected Ore drained to 0.0 on deficit, got %s" % starved_base.stock.get(Commodity.Type.ORE, 0.0))
	if starved_base.stock.get(Commodity.Type.FUEL, 0.0) != 0.0:
		failures.append("tick: expected Fuel also drained to 0.0 (same slot) on deficit, got %s" % starved_base.stock.get(Commodity.Type.FUEL, 0.0))
	if starved_base.stock.get(Commodity.Type.WEAPONS, 0.0) != 0.0:
		failures.append("tick: expected no Weapons produced on a deficit tick")
	if starved_base.deficit_streaks.get(0, 0) != 1:
		failures.append("tick: expected deficit streak == 1 after one starved tick, got %s" % starved_base.deficit_streaks.get(0, 0))

	# Slot removal: 5 consecutive starved ticks removes the last slot and resets streaks.
	var decaying_base := BaseEconomy.new()
	decaying_base.slots = [EconomyRole.mining(), EconomyRole.population()]
	decaying_base.max_slots = 2
	decaying_base.stock = {}
	for i in 5:
		decaying_base.tick()
	if decaying_base.slots.size() != 1:
		failures.append("tick: expected the last slot removed after 5 consecutive deficits, got %d slots" % decaying_base.slots.size())
	if decaying_base.deficit_streaks.values().any(func(v): return v != 0):
		failures.append("tick: expected all deficit streaks reset to 0 after a slot is removed")

	# Ordering: production for ALL slots must apply before ANY consumption is
	# evaluated. An earlier-indexed consuming slot (industrial) must see a
	# later-indexed producing slot's (mining) same-tick output.
	var ordering_base := BaseEconomy.new()
	ordering_base.slots = [EconomyRole.industrial(), EconomyRole.mining()]
	ordering_base.max_slots = 2
	ordering_base.stock = {Commodity.Type.FUEL: 2.0}
	ordering_base.tick()
	if ordering_base.stock.get(Commodity.Type.ORE, 0.0) != 2.0:
		failures.append("tick: expected Ore produced by mining (5.0) then drawn down by industrial (3.0) to 2.0, got %s" % ordering_base.stock.get(Commodity.Type.ORE, 0.0))
	if ordering_base.stock.get(Commodity.Type.FUEL, 0.0) != 0.0:
		failures.append("tick: expected Fuel drawn down to 0.0, got %s" % ordering_base.stock.get(Commodity.Type.FUEL, 0.0))
	if ordering_base.stock.get(Commodity.Type.WEAPONS, 0.0) != 2.0:
		failures.append("tick: expected Weapons produced to 2.0, got %s" % ordering_base.stock.get(Commodity.Type.WEAPONS, 0.0))
	if ordering_base.deficit_streaks.get(0, 0) != 0:
		failures.append("tick: expected industrial deficit streak == 0 (affordable using same-tick mining production), got %s" % ordering_base.deficit_streaks.get(0, 0))

	# TRADE_HUB (no production/consumption) never decays regardless of ticks.
	var trade_hub_base := BaseEconomy.new()
	trade_hub_base.slots = [EconomyRole.trade_hub()]
	trade_hub_base.max_slots = 1
	for i in 10:
		trade_hub_base.tick()
	if trade_hub_base.slots.size() != 1:
		failures.append("tick: expected TRADE_HUB slot to never decay, got %d slots" % trade_hub_base.slots.size())

	return failures
