class_name PartRarity
extends RefCounted

enum Tier { COMMON, UNCOMMON, RARE, EPIC }

const PRICE_BY_TIER := {
	Tier.COMMON: 100,
	Tier.UNCOMMON: 250,
	Tier.RARE: 600,
	Tier.EPIC: 1500,
}

const POINTS_BY_TIER := {
	Tier.COMMON: 5,
	Tier.UNCOMMON: 10,
	Tier.RARE: 15,
	Tier.EPIC: 20,
}

const SELL_FRACTION := 0.5

static func price_for(tier: int) -> int:
	return PRICE_BY_TIER[tier]

static func sell_price_for(tier: int) -> int:
	var buy := price_for(tier)
	return clampi(roundi(buy * SELL_FRACTION), 1, maxi(1, buy - 1))

static func points_for(tier: int) -> int:
	return POINTS_BY_TIER[tier]
