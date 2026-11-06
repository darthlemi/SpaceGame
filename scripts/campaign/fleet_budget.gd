class_name FleetBudget
extends RefCounted

# Ships of budget per tier before the station's output adds to it.
const TIER_BUDGET := {1: 4, 2: 10, 3: 16, 4: 24, 5: 32}
const OUTPUT_SHIPS_PER_UNIT := 0.5
const SECURITY_MIN_BUDGET := 12
const CONVOY_LARGE_MIN_BUDGET := 16
# Chance a combat plan includes one Security fleet.
const SECURITY_ODDS := {1: 0.05, 2: 0.15, 3: 0.3, 4: 0.5, 5: 0.7}
const VARIANT_DELAY_FACTOR := {
	DangerTier.Variant.PICKET: 0.5,
	DangerTier.Variant.PATROL: 1.0,
	DangerTier.Variant.ESCORT: 1.5,
	DangerTier.Variant.SECURITY: 3.0,
	DangerTier.Variant.CONVOY_SMALL: 1.0,
	DangerTier.Variant.CONVOY_LARGE: 1.0,
}
# Budget at which respawn runs at the base rate; richer stations respawn faster.
const RESPAWN_BASELINE_BUDGET := 6.0

# Tiers outside 1..5 clamp, like DangerTier.fleet_for.
static func ship_budget(tier: int, economy: BaseEconomy) -> int:
	var output := 0.0
	if economy != null:
		for slot in economy.slots:
			for amount in slot.produces.values():
				output += amount
	return TIER_BUDGET[clampi(tier, DangerTier.MIN_TIER, DangerTier.MAX_TIER)] + int(output * OUTPUT_SHIPS_PER_UNIT)

# Returns DangerTier.Variant values; never fewer than min_fleets entries.
static func build_plan(tier: int, role: CampaignFleet.Role, budget: int, min_fleets: int, rng: RandomNumberGenerator) -> Array[int]:
	var key := clampi(tier, DangerTier.MIN_TIER, DangerTier.MAX_TIER)
	var plan: Array[int] = []
	if role == CampaignFleet.Role.TRADER:
		var convoy := DangerTier.Variant.CONVOY_LARGE if budget >= CONVOY_LARGE_MIN_BUDGET else DangerTier.Variant.CONVOY_SMALL
		for i in min_fleets:
			plan.append(convoy)
		return plan
	var remaining := float(budget)
	if budget >= SECURITY_MIN_BUDGET and rng.randf() < SECURITY_ODDS[key]:
		plan.append(DangerTier.Variant.SECURITY)
		remaining -= _mean_ships(DangerTier.Variant.SECURITY)
	if key >= 3:
		remaining = _fill(plan, DangerTier.Variant.ESCORT, 6.0, remaining)
	if key >= 2:
		remaining = _fill(plan, DangerTier.Variant.PATROL, 3.0, remaining)
	_fill(plan, DangerTier.Variant.PICKET, 1.0, remaining)
	while plan.size() < min_fleets:
		plan.append(DangerTier.Variant.PICKET)
	return plan

static func respawn_delay(variant: DangerTier.Variant, budget: int) -> float:
	return CampaignState.FLEET_RESPAWN_DELAY * VARIANT_DELAY_FACTOR[variant] / maxf(1.0, budget / RESPAWN_BASELINE_BUDGET)

# Adds variant while remaining >= min_remaining; returns what is left.
static func _fill(plan: Array[int], variant: DangerTier.Variant, min_remaining: float, remaining: float) -> float:
	while remaining >= min_remaining:
		plan.append(variant)
		remaining -= _mean_ships(variant)
	return remaining

static func _mean_ships(variant: DangerTier.Variant) -> float:
	var bounds := DangerTier.ship_count_range(variant)
	return (bounds.x + bounds.y) / 2.0
