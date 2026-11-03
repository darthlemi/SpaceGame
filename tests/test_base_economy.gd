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

	# Pricing: stock-ratio bands relative to Commodity.TARGET_STOCK.
	var pricing_base := BaseEconomy.new()
	var ore_target: float = Commodity.TARGET_STOCK[Commodity.Type.ORE]
	var ore_base_price: float = Commodity.BASE_PRICE[Commodity.Type.ORE]

	pricing_base.stock = {Commodity.Type.ORE: ore_target * 0.1}  # critical: <20%
	if abs(pricing_base.price_for(Commodity.Type.ORE) - ore_base_price * 1.6) > 0.001:
		failures.append("price_for: expected critical band 1.6x, got %s" % pricing_base.price_for(Commodity.Type.ORE))

	pricing_base.stock = {Commodity.Type.ORE: ore_target * 1.0}  # normal: 60-140%
	if abs(pricing_base.price_for(Commodity.Type.ORE) - ore_base_price * 1.0) > 0.001:
		failures.append("price_for: expected normal band 1.0x, got %s" % pricing_base.price_for(Commodity.Type.ORE))

	pricing_base.stock = {Commodity.Type.ORE: ore_target * 2.0}  # surplus: >180%
	if abs(pricing_base.price_for(Commodity.Type.ORE) - ore_base_price * 0.6) > 0.001:
		failures.append("price_for: expected surplus band 0.6x, got %s" % pricing_base.price_for(Commodity.Type.ORE))

	pricing_base.stock = {Commodity.Type.ORE: ore_target * 0.4}  # low: 20-60%
	if abs(pricing_base.price_for(Commodity.Type.ORE) - ore_base_price * 1.3) > 0.001:
		failures.append("price_for: expected low band 1.3x, got %s" % pricing_base.price_for(Commodity.Type.ORE))

	pricing_base.stock = {Commodity.Type.ORE: ore_target * 1.6}  # high: 140-180%
	if abs(pricing_base.price_for(Commodity.Type.ORE) - ore_base_price * 0.8) > 0.001:
		failures.append("price_for: expected high band 0.8x, got %s" % pricing_base.price_for(Commodity.Type.ORE))

	# Boundary: ratio exactly 0.2 falls into the "low" band (threshold check is
	# ratio < 0.2 for critical, so 0.2 itself does not qualify as critical).
	pricing_base.stock = {Commodity.Type.ORE: ore_target * 0.2}  # boundary: exactly 20%
	if abs(pricing_base.price_for(Commodity.Type.ORE) - ore_base_price * 1.3) > 0.001:
		failures.append("price_for: expected ratio==0.2 boundary to land in low band 1.3x, got %s" % pricing_base.price_for(Commodity.Type.ORE))

	var buy: float = pricing_base.price_for(Commodity.Type.ORE)
	var sell: float = pricing_base.sell_price_for(Commodity.Type.ORE)
	if abs(sell - buy * 0.8) > 0.001:
		failures.append("sell_price_for: expected 80%% of buy price, got buy=%s sell=%s" % [buy, sell])

	# net_commodities: sums produces-minus-consumes across all slots.
	var net_base := BaseEconomy.new()
	net_base.slots = [EconomyRole.industrial(), EconomyRole.mining()]
	var net: Dictionary = net_base.net_commodities()
	if abs(net.get(Commodity.Type.ORE, 0.0) - 2.0) > 0.001:
		failures.append("net_commodities: expected Ore net +2.0 (mining +5 - industrial -3), got %s" % net.get(Commodity.Type.ORE, 0.0))
	if abs(net.get(Commodity.Type.FUEL, 0.0) - (-2.0)) > 0.001:
		failures.append("net_commodities: expected Fuel net -2.0, got %s" % net.get(Commodity.Type.FUEL, 0.0))
	if abs(net.get(Commodity.Type.WEAPONS, 0.0) - 2.0) > 0.001:
		failures.append("net_commodities: expected Weapons net +2.0, got %s" % net.get(Commodity.Type.WEAPONS, 0.0))

	# surplus_streak: increments on a clean tick, resets to 0 on any deficit.
	var surplus_base := BaseEconomy.new()
	surplus_base.slots = [EconomyRole.mining()]
	surplus_base.max_slots = 1
	surplus_base.tick()
	surplus_base.tick()
	if surplus_base.surplus_streak != 2:
		failures.append("surplus_streak: expected 2 after two clean ticks, got %s" % surplus_base.surplus_streak)

	var deficit_then_clean_base := BaseEconomy.new()
	deficit_then_clean_base.slots = [EconomyRole.industrial()]
	deficit_then_clean_base.max_slots = 1
	deficit_then_clean_base.stock = {}
	deficit_then_clean_base.tick()
	if deficit_then_clean_base.surplus_streak != 0:
		failures.append("surplus_streak: expected 0 after a deficit tick, got %s" % deficit_then_clean_base.surplus_streak)


	# Population: capacity is the sum of slot housing.
	var housing_base := BaseEconomy.new()
	housing_base.slots = [EconomyRole.mining(), EconomyRole.population()]
	var expected_capacity := EconomyRole.housing_for(EconomyRole.RoleType.MINING) + EconomyRole.housing_for(EconomyRole.RoleType.POPULATION)
	if housing_base.population_capacity() != expected_capacity:
		failures.append("population_capacity: expected %s, got %s" % [expected_capacity, housing_base.population_capacity()])

	# Grows with secure food, never past capacity.
	var growing_base := BaseEconomy.new()
	growing_base.slots = [EconomyRole.agriculture()]
	growing_base.stock = {Commodity.Type.FOOD: BaseEconomy.FOOD_SECURE_STOCK}
	growing_base.population = 1000.0
	growing_base.tick()
	if not is_equal_approx(growing_base.population, 1000.0 * (1.0 + BaseEconomy.POPULATION_GROWTH_RATE)):
		failures.append("population: expected growth with secure food, got %s" % growing_base.population)
	if growing_base.population_trend != 1:
		failures.append("population_trend: expected 1 (growing), got %s" % growing_base.population_trend)
	for i in 50:
		growing_base.tick()
	if growing_base.population > growing_base.population_capacity():
		failures.append("population: expected capped at capacity %s, got %s" % [growing_base.population_capacity(), growing_base.population])
	growing_base.tick()
	if growing_base.population_trend != 0:
		failures.append("population_trend: expected 0 (stable) at capacity, got %s" % growing_base.population_trend)

	# An emptied base regrows from the floor rather than staying at 0.
	var empty_base := BaseEconomy.new()
	empty_base.slots = [EconomyRole.trade_hub()]
	empty_base.stock = {Commodity.Type.FOOD: 50.0}
	empty_base.tick()
	if not is_equal_approx(empty_base.population, BaseEconomy.POPULATION_FLOOR * (1.0 + BaseEconomy.POPULATION_GROWTH_RATE)):
		failures.append("population: expected regrowth from POPULATION_FLOOR, got %s" % empty_base.population)

	# Starving: a population slot that cannot eat zeroes Food, so people leave.
	var starving_base := BaseEconomy.new()
	starving_base.slots = [EconomyRole.population()]
	starving_base.stock = {}
	starving_base.population = 2000.0
	starving_base.tick()
	if not is_equal_approx(starving_base.population, 2000.0 * (1.0 - BaseEconomy.POPULATION_DECLINE_RATE)):
		failures.append("population: expected decline without food, got %s" % starving_base.population)
	if starving_base.population_trend != -1:
		failures.append("population_trend: expected -1 (declining), got %s" % starving_base.population_trend)

	# Some food but below the secure level: holds steady.
	var lean_base := BaseEconomy.new()
	lean_base.slots = [EconomyRole.trade_hub()]
	lean_base.stock = {Commodity.Type.FOOD: BaseEconomy.FOOD_SECURE_STOCK - 1.0}
	lean_base.population = 1000.0
	lean_base.tick()
	if lean_base.population != 1000.0 or lean_base.population_trend != 0:
		failures.append("population: expected unchanged with lean food, got %s trend %s" % [lean_base.population, lean_base.population_trend])

	# Over capacity (housing lost): shrinks toward capacity even with food.
	var crowded_base := BaseEconomy.new()
	crowded_base.slots = [EconomyRole.mining()]
	crowded_base.stock = {Commodity.Type.FOOD: 100.0}
	crowded_base.population = 5000.0
	crowded_base.tick()
	if not is_equal_approx(crowded_base.population, 5000.0 * (1.0 - BaseEconomy.POPULATION_DECLINE_RATE)):
		failures.append("population: expected over-capacity decline, got %s" % crowded_base.population)
	crowded_base.population = crowded_base.population_capacity() + 1.0
	crowded_base.tick()
	if crowded_base.population != crowded_base.population_capacity():
		failures.append("population: expected over-capacity decline to stop at capacity, got %s" % crowded_base.population)

	# Wealth level mirrors deficit/surplus streaks.
	var wealth_base := BaseEconomy.new()
	if wealth_base.wealth_level() != BaseEconomy.WealthLevel.MIDDLING:
		failures.append("wealth_level: expected MIDDLING for a fresh economy, got %s" % wealth_base.wealth_level())
	wealth_base.surplus_streak = BaseEconomy.SURPLUS_STREAK_THRESHOLD
	if wealth_base.wealth_level() != BaseEconomy.WealthLevel.WEALTHY:
		failures.append("wealth_level: expected WEALTHY at the surplus threshold, got %s" % wealth_base.wealth_level())
	wealth_base.deficit_streaks = {0: 1}
	if wealth_base.wealth_level() != BaseEconomy.WealthLevel.POOR:
		failures.append("wealth_level: expected POOR with any active deficit streak, got %s" % wealth_base.wealth_level())

	return failures
