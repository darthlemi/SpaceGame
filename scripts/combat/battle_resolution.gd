class_name BattleResolution
extends RefCounted

# Tuning placeholders.
const ESCAPE_SPEED_WEIGHT := 1.0
const ESCAPE_MIN := 0.1
const ESCAPE_MAX := 0.9

static func escape_chance(escaper_speed: float, pursuer_speed: float) -> float:
	if pursuer_speed <= 0.0:
		return 1.0
	return clampf(0.5 + ESCAPE_SPEED_WEIGHT * (escaper_speed / pursuer_speed - 1.0), ESCAPE_MIN, ESCAPE_MAX)

# One draw per escaper, in order; true means escaped.
static func roll_escapes(escaper_speeds: Array[float], pursuer_speed: float, rng: RandomNumberGenerator) -> Array[bool]:
	var result: Array[bool] = []
	for speed in escaper_speeds:
		result.append(rng.randf() < escape_chance(speed, pursuer_speed))
	return result

# fleet holds only the ships left after battle (captured and escaped), so the captured share
# is captured capacity over theirs. Parts go whole, rounded down (epsilon absorbs 1/3 * 3 noise).
static func split_cargo(fleet: CampaignFleet, captured_indices: Array[int]) -> Dictionary:
	var share := 1.0
	if captured_indices.size() < fleet.ship_compositions.size():
		var captured_capacity := 0.0
		for i in captured_indices:
			captured_capacity += ShipType.cargo_capacity_for(ShipType.kind_of(fleet.ship_compositions[i]))
		var total_capacity := fleet.cargo_capacity()
		share = captured_capacity / total_capacity if total_capacity > 0.0 else 0.0
	var loot_cargo := {}
	var kept_cargo := {}
	for commodity in fleet.cargo:
		var amount: float = fleet.cargo[commodity]
		loot_cargo[commodity] = amount * share
		kept_cargo[commodity] = amount - loot_cargo[commodity]
	var loot_count := floori(share * fleet.part_inventory.size() + CrewRules.ROUND_EPSILON)
	var loot_parts: Array[String] = []
	loot_parts.assign(fleet.part_inventory.slice(0, loot_count))
	var kept_parts: Array[String] = []
	kept_parts.assign(fleet.part_inventory.slice(loot_count))
	return {"loot_cargo": loot_cargo, "loot_parts": loot_parts, "kept_cargo": kept_cargo, "kept_parts": kept_parts}
