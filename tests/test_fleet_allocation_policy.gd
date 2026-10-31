extends RefCounted

const FleetAllocationPolicy = preload("res://scripts/campaign/fleet_allocation_policy.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var danger_stable := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.STABLE, 2.0, 2)
	if danger_stable != FleetAllocationPolicy.Action.GROW_COMBAT:
		failures.append("decide: expected GROW_COMBAT when outmatched and not in deficit, got %s" % danger_stable)

	var danger_deficit_with_spare_trader := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.DEFICIT, 2.0, 2)
	if danger_deficit_with_spare_trader != FleetAllocationPolicy.Action.REALLOCATE_TO_COMBAT:
		failures.append("decide: expected REALLOCATE_TO_COMBAT when outmatched, in deficit, and more than 1 trader, got %s" % danger_deficit_with_spare_trader)

	var danger_deficit_last_trader := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.DEFICIT, 2.0, 1)
	if danger_deficit_last_trader != FleetAllocationPolicy.Action.NONE:
		failures.append("decide: expected NONE when outmatched, in deficit, and only 1 trader left, got %s" % danger_deficit_last_trader)

	var strong_safe := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.STRONG, 0.1, 1)
	if strong_safe != FleetAllocationPolicy.Action.GROW_TRADE:
		failures.append("decide: expected GROW_TRADE when strong and safe, got %s" % strong_safe)

	var strong_not_safe := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.STRONG, 0.9, 1)
	if strong_not_safe != FleetAllocationPolicy.Action.NONE:
		failures.append("decide: expected NONE when strong but threat_ratio isn't below SAFE_THRESHOLD, got %s" % strong_not_safe)

	var stable_mid := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.STABLE, 0.9, 1)
	if stable_mid != FleetAllocationPolicy.Action.NONE:
		failures.append("decide: expected NONE when stable and threat_ratio is mid-range, got %s" % stable_mid)

	var boundary_danger := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.STABLE, FleetAllocationPolicy.DANGER_THRESHOLD, 1)
	if boundary_danger != FleetAllocationPolicy.Action.NONE:
		failures.append("decide: expected threat_ratio exactly at DANGER_THRESHOLD to NOT count as danger, got %s" % boundary_danger)

	var boundary_safe := FleetAllocationPolicy.decide(FleetAllocationPolicy.EconomicHealth.STRONG, FleetAllocationPolicy.SAFE_THRESHOLD, 1)
	if boundary_safe != FleetAllocationPolicy.Action.NONE:
		failures.append("decide: expected threat_ratio exactly at SAFE_THRESHOLD to NOT count as safe, got %s" % boundary_safe)

	return failures
