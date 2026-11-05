class_name BaseEconomy
extends Resource

const SURPLUS_STREAK_THRESHOLD := 5
# Warehouse size as a multiple of Commodity.TARGET_STOCK; production above it is discarded.
const STOCK_CAP_FACTOR := 3.0
const BAND_THRESHOLDS := [0.2, 0.6, 1.4, 1.8]
const BAND_MULTIPLIERS := [1.6, 1.3, 1.0, 0.8, 0.6]
const SELL_SPREAD := 0.8
const POPULATION_GROWTH_RATE := 0.02
const POPULATION_DECLINE_RATE := 0.05
# Growth restarts from this headcount, so an emptied base can repopulate.
const POPULATION_FLOOR := 100.0
const FOOD_SECURE_STOCK := 10.0
# Tuning placeholders: hireable crew regenerates from population up to a population-scaled cap.
const CREW_POOL_CAP_FRACTION := 0.05
const CREW_POOL_REGEN_RATE := 0.005

enum WealthLevel { POOR, MIDDLING, WEALTHY }

@export var slots: Array[EconomyRole] = []
@export var max_slots: int = 2
var stock: Dictionary = {}
var deficit_streaks: Dictionary = {}
var surplus_streak: int = 0
var population: float = 0.0
# -1 declining, 0 stable, 1 growing (as of the last tick).
var population_trend: int = 0
# Hireable crew available at this base.
var crew_pool: float = 0.0

func tick() -> void:
	for slot in slots:
		if slot.consumes.is_empty():
			for commodity in slot.produces:
				stock[commodity] = stock.get(commodity, 0.0) + slot.produces[commodity]

	var any_deficit := false
	for i in slots.size():
		var slot: EconomyRole = slots[i]
		if slot.consumes.is_empty():
			continue
		# A full warehouse idles the slot, so inputs aren't burned for output that would be discarded.
		if _output_full(slot):
			deficit_streaks[i] = 0
			continue
		var can_afford := true
		for commodity in slot.consumes:
			if stock.get(commodity, 0.0) < slot.consumes[commodity]:
				can_afford = false
				break
		if can_afford:
			for commodity in slot.consumes:
				stock[commodity] = stock.get(commodity, 0.0) - slot.consumes[commodity]
			for commodity in slot.produces:
				stock[commodity] = stock.get(commodity, 0.0) + slot.produces[commodity]
			deficit_streaks[i] = 0
		else:
			# A starved slot idles and keeps its inputs; it restarts when supply arrives.
			any_deficit = true
			deficit_streaks[i] = deficit_streaks.get(i, 0) + 1

	for commodity in stock.keys():
		stock[commodity] = minf(stock[commodity], stock_cap(commodity))

	if any_deficit:
		surplus_streak = 0
	else:
		surplus_streak += 1
	_tick_population()
	crew_pool = min(population * CREW_POOL_CAP_FRACTION, crew_pool + population * CREW_POOL_REGEN_RATE)

func crew_pool_cap() -> float:
	return population * CREW_POOL_CAP_FRACTION

func stock_cap(commodity: int) -> float:
	return Commodity.TARGET_STOCK[commodity] * STOCK_CAP_FACTOR

# Short means the stock is in the two highest-price bands (below BAND_THRESHOLDS[1] of target).
func is_short_of(commodity: int) -> bool:
	return stock.get(commodity, 0.0) < Commodity.TARGET_STOCK[commodity] * BAND_THRESHOLDS[1]

func _output_full(slot: EconomyRole) -> bool:
	if slot.produces.is_empty():
		return false
	for commodity in slot.produces:
		if stock.get(commodity, 0.0) < stock_cap(commodity):
			return false
	return true

func price_for(commodity: int) -> int:
	var target: float = Commodity.TARGET_STOCK[commodity]
	var ratio: float = stock.get(commodity, 0.0) / target
	var multiplier: float = BAND_MULTIPLIERS[BAND_MULTIPLIERS.size() - 1]
	for i in BAND_THRESHOLDS.size():
		if ratio < BAND_THRESHOLDS[i]:
			multiplier = BAND_MULTIPLIERS[i]
			break
	return maxi(1, roundi(Commodity.BASE_PRICE[commodity] * multiplier))

# Always at least 1 under the buy price (unless the buy price is itself 1), so a round trip never profits.
func sell_price_for(commodity: int) -> int:
	var buy := price_for(commodity)
	return clampi(floori(buy * SELL_SPREAD), 1, maxi(1, buy - 1))

func net_commodities() -> Dictionary:
	var net: Dictionary = {}
	for slot in slots:
		for commodity in slot.produces:
			net[commodity] = net.get(commodity, 0.0) + slot.produces[commodity]
		for commodity in slot.consumes:
			net[commodity] = net.get(commodity, 0.0) - slot.consumes[commodity]
	return net

func population_capacity() -> float:
	var sum := 0.0
	for slot in slots:
		sum += slot.housing
	return sum

func wealth_level() -> WealthLevel:
	for streak in deficit_streaks.values():
		if streak > 0:
			return WealthLevel.POOR
	if surplus_streak >= SURPLUS_STREAK_THRESHOLD:
		return WealthLevel.WEALTHY
	return WealthLevel.MIDDLING

# Runs after production, so a slot that just starved has already zeroed Food.
func _tick_population() -> void:
	var previous := population
	var capacity := population_capacity()
	var food: float = stock.get(Commodity.Type.FOOD, 0.0)
	if population > capacity:
		# Housing lost with a collapsed slot: people leave until they fit.
		population = max(capacity, population * (1.0 - POPULATION_DECLINE_RATE))
	elif food < 1.0:
		population *= 1.0 - POPULATION_DECLINE_RATE
	elif food >= FOOD_SECURE_STOCK:
		population = min(capacity, max(population, POPULATION_FLOOR) * (1.0 + POPULATION_GROWTH_RATE))
	if is_equal_approx(population, previous):
		population_trend = 0
	else:
		population_trend = 1 if population > previous else -1
