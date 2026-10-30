class_name SkirmishResolution
extends RefCounted

const MAX_SKIRMISH_TIME := 30.0
const MIN_SKIRMISH_TIME := 3.0
const MAX_WINNER_DAMAGE_FRACTION := 0.5

static func imbalance(strength_a: float, strength_b: float) -> float:
	var total := strength_a + strength_b
	if total <= 0.0:
		return 1.0
	return abs(strength_a - strength_b) / total

static func duration(imbalance_value: float) -> float:
	return lerp(MAX_SKIRMISH_TIME, MIN_SKIRMISH_TIME, imbalance_value)

static func winner_damage_fraction(imbalance_value: float) -> float:
	return (1.0 - imbalance_value) * MAX_WINNER_DAMAGE_FRACTION
