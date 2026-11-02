extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []

	if PartRarity.price_for(PartRarity.Tier.COMMON) != 100.0:
		failures.append("price_for: expected COMMON == 100.0, got %s" % PartRarity.price_for(PartRarity.Tier.COMMON))
	if PartRarity.price_for(PartRarity.Tier.EPIC) != 1500.0:
		failures.append("price_for: expected EPIC == 1500.0, got %s" % PartRarity.price_for(PartRarity.Tier.EPIC))
	if not is_equal_approx(PartRarity.sell_price_for(PartRarity.Tier.RARE), 300.0):
		failures.append("sell_price_for: expected RARE sell == 300.0 (50%% of 600), got %s" % PartRarity.sell_price_for(PartRarity.Tier.RARE))
	if PartRarity.points_for(PartRarity.Tier.UNCOMMON) != 10:
		failures.append("points_for: expected UNCOMMON == 10, got %s" % PartRarity.points_for(PartRarity.Tier.UNCOMMON))

	var prev_price := -1.0
	var prev_points := -1
	for tier in PartRarity.Tier.values():
		if PartRarity.price_for(tier) <= prev_price:
			failures.append("price_for: expected strictly increasing price by tier, failed at tier %s" % tier)
		if PartRarity.points_for(tier) <= prev_points:
			failures.append("points_for: expected strictly increasing points by tier, failed at tier %s" % tier)
		prev_price = PartRarity.price_for(tier)
		prev_points = PartRarity.points_for(tier)

	return failures
