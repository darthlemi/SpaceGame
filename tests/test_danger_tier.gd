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
	var corvette := ShipType.Kind.CORVETTE
	var freighter := ShipType.Kind.FREIGHTER
	var capital := ShipType.Kind.CAPITAL

	var cases := [
		[1, CampaignFleet.Role.COMBAT, [corvette]],
		[3, CampaignFleet.Role.COMBAT, [corvette, corvette, corvette]],
		[5, CampaignFleet.Role.COMBAT, [capital, capital, corvette]],
		[3, CampaignFleet.Role.TRADER, [freighter, freighter]],
		[1, CampaignFleet.Role.TRADER, [freighter]],
		[0, CampaignFleet.Role.COMBAT, [corvette]],
		[9, CampaignFleet.Role.COMBAT, [capital, capital, corvette]],
		[9, CampaignFleet.Role.TRADER, [freighter, freighter, freighter]],
	]
	for c in cases:
		var kinds := _kinds(DangerTier.fleet_for(c[0], c[1], rng))
		if kinds != c[2]:
			failures.append("fleet_for tier %d role %d: expected %s, got %s" % [c[0], c[1], c[2], kinds])

	var tier4 := DangerTier.fleet_for(4, CampaignFleet.Role.COMBAT, rng)
	if ShipType.kind_of(tier4[0]) != capital or not CrewRules.is_flagship(tier4[0]):
		failures.append("tier 4 combat: expected capital flagship at index 0")

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
