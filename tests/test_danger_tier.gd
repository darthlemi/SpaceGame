extends RefCounted

static func _kinds(comps: Array[Dictionary]) -> Array:
	var kinds := []
	for comp in comps:
		kinds.append(ShipType.kind_of(comp))
	return kinds

static func _check_rarity(failures: Array[String], tier: int, label: String, ok: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 10:
		for comp in DangerTier.fleet_for(tier, CampaignFleet.Role.COMBAT, rng):
			for path in comp["weapon_mount_items"]:
				var rarity: int = load(path).rarity
				if not ok.call(rarity):
					failures.append("tier %d weapon %s: rarity %d, expected %s" % [tier, path, rarity, label])

static func run() -> Array[String]:
	var failures: Array[String] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var freighter := ShipType.Kind.FREIGHTER
	var capital := ShipType.Kind.CAPITAL

	var variants := [
		DangerTier.Variant.PICKET, DangerTier.Variant.PATROL, DangerTier.Variant.ESCORT,
		DangerTier.Variant.SECURITY, DangerTier.Variant.CONVOY_SMALL, DangerTier.Variant.CONVOY_LARGE,
	]
	for variant in variants:
		var bounds := DangerTier.ship_count_range(variant)
		var is_convoy := DangerTier.role_of(variant) == CampaignFleet.Role.TRADER
		for seed_value in 20:
			rng.seed = seed_value
			var comps := DangerTier.fleet_for_variant(3, variant, rng)
			if comps.size() < bounds.x or comps.size() > bounds.y:
				failures.append("variant %d seed %d: %d ships outside %s" % [variant, seed_value, comps.size(), bounds])
			for comp in comps:
				if is_convoy != (ShipType.kind_of(comp) == freighter):
					failures.append("variant %d: wrong hull kind %d" % [variant, ShipType.kind_of(comp)])
					break
	if DangerTier.role_of(DangerTier.Variant.CONVOY_LARGE) != CampaignFleet.Role.TRADER or DangerTier.role_of(DangerTier.Variant.SECURITY) != CampaignFleet.Role.COMBAT:
		failures.append("role_of: convoys must be TRADER, combat variants COMBAT")
	if DangerTier.ship_count_range(DangerTier.Variant.SECURITY).y != DangerTier.SECURITY_MAX_SHIPS:
		failures.append("Security max must be SECURITY_MAX_SHIPS")

	for seed_value in 20:
		rng.seed = seed_value
		for comp in DangerTier.fleet_for_variant(3, DangerTier.Variant.SECURITY, rng):
			if ShipType.kind_of(comp) == capital:
				failures.append("tier 3 Security: unexpected capital")
				break
		for comp in DangerTier.fleet_for_variant(5, DangerTier.Variant.PICKET, rng):
			if ShipType.kind_of(comp) == capital:
				failures.append("tier 5 Picket: unexpected capital")
				break
		for variant in [DangerTier.Variant.ESCORT, DangerTier.Variant.SECURITY]:
			var comps := DangerTier.fleet_for_variant(5, variant, rng)
			var want := maxi(1, floori(comps.size() * 0.25))
			var capitals := _kinds(comps).count(capital)
			if capitals != want:
				failures.append("tier 5 variant %d: expected %d capitals, got %d" % [variant, want, capitals])
			if ShipType.kind_of(comps[0]) != capital or not CrewRules.is_flagship(comps[0]):
				failures.append("tier 5 variant %d: expected capital flagship at index 0" % variant)
		var tier4 := DangerTier.fleet_for_variant(4, DangerTier.Variant.ESCORT, rng)
		if _kinds(tier4).count(capital) < 1:
			failures.append("tier 4 Escort: expected a capital")

	# Out-of-range tiers clamp.
	rng.seed = 3
	var high := _kinds(DangerTier.fleet_for_variant(9, DangerTier.Variant.ESCORT, rng))
	rng.seed = 3
	var top := _kinds(DangerTier.fleet_for_variant(5, DangerTier.Variant.ESCORT, rng))
	if high != top:
		failures.append("tier 9 should clamp to tier 5: %s vs %s" % [high, top])
	rng.seed = 3
	var low := _kinds(DangerTier.fleet_for_variant(0, DangerTier.Variant.ESCORT, rng))
	rng.seed = 3
	var bottom := _kinds(DangerTier.fleet_for_variant(1, DangerTier.Variant.ESCORT, rng))
	if low != bottom:
		failures.append("tier 0 should clamp to tier 1: %s vs %s" % [low, bottom])

	# fleet_for keeps its signature: combat -> Patrol, trader -> small convoy.
	var legacy_combat := DangerTier.fleet_for(2, CampaignFleet.Role.COMBAT, rng)
	if legacy_combat.size() < 3 or legacy_combat.size() > 5:
		failures.append("fleet_for combat: expected a Patrol of 3-5, got %d" % legacy_combat.size())
	var legacy_trader := DangerTier.fleet_for(2, CampaignFleet.Role.TRADER, rng)
	if legacy_trader.size() < 2 or legacy_trader.size() > 3 or _kinds(legacy_trader).count(freighter) != legacy_trader.size():
		failures.append("fleet_for trader: expected 2-3 freighters, got %s" % [_kinds(legacy_trader)])

	_check_rarity(failures, 1, "0", func(r): return r == 0)
	_check_rarity(failures, 5, ">= 2", func(r): return r >= 2)

	for comp in DangerTier.fleet_for(1, CampaignFleet.Role.COMBAT, rng):
		var want := ceili(CrewRules.complement(comp) * 0.7)
		if CrewRules.crew_of(comp) != want:
			failures.append("tier 1 crew: expected %d, got %d" % [want, CrewRules.crew_of(comp)])
	for comp in DangerTier.fleet_for(5, CampaignFleet.Role.COMBAT, rng):
		if CrewRules.crew_of(comp) != CrewRules.complement(comp):
			failures.append("tier 5 crew: expected full complement")
	return failures
