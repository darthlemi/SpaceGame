# tests/test_fleet_budget.gd
extends RefCounted

static func _economy(roles: Array[EconomyRole]) -> BaseEconomy:
	var economy := BaseEconomy.new()
	economy.slots = roles
	economy.max_slots = roles.size()
	return economy

static func _security_share(tier: int, budget: int) -> float:
	var rng := RandomNumberGenerator.new()
	var hits := 0
	var seeds := 200
	for seed_value in seeds:
		rng.seed = seed_value
		if FleetBudget.build_plan(tier, CampaignFleet.Role.COMBAT, budget, 1, rng).has(DangerTier.Variant.SECURITY):
			hits += 1
	return float(hits) / seeds

static func run() -> Array[String]:
	var failures: Array[String] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	var poor := _economy([EconomyRole.population()])
	var rich := _economy([EconomyRole.mining(), EconomyRole.agriculture(), EconomyRole.refinery()])
	if FleetBudget.ship_budget(3, rich) <= FleetBudget.ship_budget(3, poor):
		failures.append("test_ship_budget_rich_station_beats_poor: rich %d, poor %d" % [FleetBudget.ship_budget(3, rich), FleetBudget.ship_budget(3, poor)])
	if FleetBudget.ship_budget(9, poor) != FleetBudget.ship_budget(5, poor):
		failures.append("ship_budget: tier 9 should clamp to tier 5")
	if FleetBudget.ship_budget(1, null) != 3:
		failures.append("ship_budget: tier 1, no economy: expected 3, got %d" % FleetBudget.ship_budget(1, null))

	var empty_plan := FleetBudget.build_plan(3, CampaignFleet.Role.COMBAT, 0, 2, rng)
	if empty_plan != [DangerTier.Variant.PICKET, DangerTier.Variant.PICKET]:
		failures.append("test_build_plan_respects_min_fleets_with_zero_budget: got %s" % [empty_plan])
	var tiny_plan := FleetBudget.build_plan(5, CampaignFleet.Role.COMBAT, 1, 1, rng)
	if tiny_plan.is_empty():
		failures.append("build_plan: budget 1 returned an empty plan")

	var low_share := _security_share(1, 22)
	var high_share := _security_share(5, 22)
	if low_share >= 0.15:
		failures.append("test_build_plan_low_tier_rarely_security: tier 1 share %.2f, expected < 0.15" % low_share)
	if high_share <= 0.5:
		failures.append("test_build_plan_low_tier_rarely_security: tier 5 share %.2f, expected > 0.5" % high_share)
	if _security_share(5, 11) != 0.0:
		failures.append("build_plan: no Security below budget 12")

	var small_trader := FleetBudget.build_plan(2, CampaignFleet.Role.TRADER, 6, 2, rng)
	if small_trader != [DangerTier.Variant.CONVOY_SMALL, DangerTier.Variant.CONVOY_SMALL]:
		failures.append("test_build_plan_trader_uses_convoys: small budget got %s" % [small_trader])
	var large_trader := FleetBudget.build_plan(5, CampaignFleet.Role.TRADER, 16, 1, rng)
	if large_trader != [DangerTier.Variant.CONVOY_LARGE]:
		failures.append("test_build_plan_trader_uses_convoys: large budget got %s" % [large_trader])

	var low_tier_plan := FleetBudget.build_plan(1, CampaignFleet.Role.COMBAT, 3, 1, rng)
	for variant in low_tier_plan:
		if variant != DangerTier.Variant.PICKET:
			failures.append("build_plan: tier 1 budget 3 must only plan Pickets, got %d" % variant)

	var picket_delay := FleetBudget.respawn_delay(DangerTier.Variant.PICKET, 6)
	var security_delay := FleetBudget.respawn_delay(DangerTier.Variant.SECURITY, 6)
	if security_delay <= picket_delay:
		failures.append("test_respawn_delay_security_slower_than_picket: security %.1f, picket %.1f" % [security_delay, picket_delay])
	if FleetBudget.respawn_delay(DangerTier.Variant.PATROL, 24) >= FleetBudget.respawn_delay(DangerTier.Variant.PATROL, 6):
		failures.append("respawn_delay: richer station should respawn faster")
	if FleetBudget.respawn_delay(DangerTier.Variant.PATROL, 0) != CampaignState.FLEET_RESPAWN_DELAY:
		failures.append("respawn_delay: budget 0 should floor at the base delay")
	return failures
