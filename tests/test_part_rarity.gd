extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []

	if PartRarity.price_for(PartRarity.Tier.COMMON) != 100:
		failures.append("price_for: expected COMMON == 100, got %s" % PartRarity.price_for(PartRarity.Tier.COMMON))
	if PartRarity.price_for(PartRarity.Tier.EPIC) != 1500:
		failures.append("price_for: expected EPIC == 1500, got %s" % PartRarity.price_for(PartRarity.Tier.EPIC))
	if PartRarity.sell_price_for(PartRarity.Tier.RARE) != 300:
		failures.append("sell_price_for: expected RARE sell == 300.0 (50%% of 600), got %s" % PartRarity.sell_price_for(PartRarity.Tier.RARE))
	if PartRarity.points_for(PartRarity.Tier.UNCOMMON) != 10:
		failures.append("points_for: expected UNCOMMON == 10, got %s" % PartRarity.points_for(PartRarity.Tier.UNCOMMON))

	for tier in PartRarity.Tier.values():
		var tier_buy = PartRarity.price_for(tier)
		var tier_sell = PartRarity.sell_price_for(tier)
		if typeof(tier_buy) != TYPE_INT or typeof(tier_sell) != TYPE_INT:
			failures.append("price_for: expected int buy/sell for tier %s" % tier)
		elif tier_sell < 1 or tier_sell > tier_buy - 1:
			failures.append("sell_price_for: expected 1 <= sell < buy for tier %s, got buy=%d sell=%d" % [tier, tier_buy, tier_sell])

	var prev_price := -1
	var prev_points := -1
	for tier in PartRarity.Tier.values():
		if PartRarity.price_for(tier) <= prev_price:
			failures.append("price_for: expected strictly increasing price by tier, failed at tier %s" % tier)
		if PartRarity.points_for(tier) <= prev_points:
			failures.append("points_for: expected strictly increasing points by tier, failed at tier %s" % tier)
		prev_price = PartRarity.price_for(tier)
		prev_points = PartRarity.points_for(tier)

	return failures
