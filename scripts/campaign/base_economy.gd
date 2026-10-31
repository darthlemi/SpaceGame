class_name BaseEconomy
extends Resource

const DEFICIT_STREAK_THRESHOLD := 5
const SURPLUS_STREAK_THRESHOLD := 5
const BAND_THRESHOLDS := [0.2, 0.6, 1.4, 1.8]
const BAND_MULTIPLIERS := [1.6, 1.3, 1.0, 0.8, 0.6]
const SELL_SPREAD := 0.8

@export var slots: Array[EconomyRole] = []
@export var max_slots: int = 2
var stock: Dictionary = {}
var deficit_streaks: Dictionary = {}
var surplus_streak: int = 0

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
			any_deficit = true
			for commodity in slot.consumes:
				stock[commodity] = 0.0
			deficit_streaks[i] = deficit_streaks.get(i, 0) + 1
			if deficit_streaks[i] >= DEFICIT_STREAK_THRESHOLD:
				slots.remove_at(slots.size() - 1)
				deficit_streaks.clear()
				break

	if any_deficit:
		surplus_streak = 0
	else:
		surplus_streak += 1

func price_for(commodity: int) -> float:
	var target: float = Commodity.TARGET_STOCK[commodity]
	var ratio: float = stock.get(commodity, 0.0) / target
	var multiplier: float = BAND_MULTIPLIERS[BAND_MULTIPLIERS.size() - 1]
	for i in BAND_THRESHOLDS.size():
		if ratio < BAND_THRESHOLDS[i]:
			multiplier = BAND_MULTIPLIERS[i]
			break
	return Commodity.BASE_PRICE[commodity] * multiplier

func sell_price_for(commodity: int) -> float:
	return price_for(commodity) * SELL_SPREAD

func net_commodities() -> Dictionary:
	var net: Dictionary = {}
	for slot in slots:
		for commodity in slot.produces:
			net[commodity] = net.get(commodity, 0.0) + slot.produces[commodity]
		for commodity in slot.consumes:
			net[commodity] = net.get(commodity, 0.0) - slot.consumes[commodity]
	return net
