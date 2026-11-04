class_name JumpRules
extends RefCounted

const WARP_DURATION := 3.0
# The starter fleet burns 5.5 per distance unit, so it pays 9.9 of its 30 starting fuel.
const JUMP_FUEL_FACTOR := 1.8
# The 1152x648 viewport, minus a margin and the HUD strip.
const SYSTEM_MIN := Vector2(40, 90)
const SYSTEM_MAX := Vector2(1112, 608)
const ARRIVAL_EDGE_MARGIN := 60.0
const ARRIVAL_RADIUS := 80.0
const DISTRESS_PRICE_MULTIPLIER := 3

static func can_afford(fleet: CampaignFleet) -> bool:
	# Epsilon: burn * distance * factor accumulates float error, so exactly-enough fuel must pass.
	return fleet.fuel_amount() >= jump_cost(fleet) - CrewRules.ROUND_EPSILON

static func clamp_to_system(p: Vector2) -> Vector2:
	return p.clamp(SYSTEM_MIN, SYSTEM_MAX)

# Arrival is at the edge facing the origin system, with scatter so stacked arrivals don't overlap.
static func arrival_point(origin_map_pos: Vector2, dest_map_pos: Vector2, rng: RandomNumberGenerator) -> Vector2:
	var toward_origin := origin_map_pos - dest_map_pos
	var direction := toward_origin.normalized() if toward_origin.length_squared() > 0.0 else Vector2.LEFT
	var scatter := Vector2.from_angle(rng.randf() * TAU) * (ARRIVAL_RADIUS * sqrt(rng.randf()))
	return clamp_to_system(edge_point(direction) + scatter)

# Casts a ray from the system centre and stops at the play rect shrunk by ARRIVAL_EDGE_MARGIN.
static func edge_point(direction: Vector2) -> Vector2:
	var centre := (SYSTEM_MIN + SYSTEM_MAX) / 2.0
	if direction.length_squared() <= 0.0:
		return centre
	var half := (SYSTEM_MAX - SYSTEM_MIN) / 2.0 - Vector2(ARRIVAL_EDGE_MARGIN, ARRIVAL_EDGE_MARGIN)
	var t := INF
	if absf(direction.x) > 0.0:
		t = minf(t, half.x / absf(direction.x))
	if absf(direction.y) > 0.0:
		t = minf(t, half.y / absf(direction.y))
	return centre + direction * t

# Fuel-for-credits rescue when a jump is unaffordable; room is checked before credits.
static func distress_quote(fleet: CampaignFleet, credits: int) -> Dictionary:
	var shortfall := jump_cost(fleet) - fleet.fuel_amount()
	if shortfall <= 0.0:
		return {"fuel": 0.0, "price": 0, "ok": false, "reason": "Fuel not needed"}
	var price := ceili(shortfall * Commodity.BASE_PRICE[Commodity.Type.FUEL] * DISTRESS_PRICE_MULTIPLIER - CrewRules.ROUND_EPSILON)
	var quote := {"fuel": shortfall, "price": price, "ok": false, "reason": ""}
	if fleet.cargo_capacity() - fleet.cargo_total() < shortfall:
		quote["reason"] = "No cargo room for fuel"
	elif credits < price:
		quote["reason"] = "Not enough credits (need %d)" % price
	else:
		quote["ok"] = true
	return quote

static func jump_cost(fleet: CampaignFleet) -> float:
	return fleet.fuel_burn_per_distance() * CampaignFleet.FUEL_BURN_DISTANCE * JUMP_FUEL_FACTOR
