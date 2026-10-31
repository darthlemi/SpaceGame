extends RefCounted

const Commodity = preload("res://scripts/campaign/commodity.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var all_types: Array = Commodity.Type.values()
	if all_types.size() != 6:
		failures.append("Commodity.Type: expected 6 commodities, got %d" % all_types.size())

	for t in all_types:
		if not Commodity.BASE_PRICE.has(t):
			failures.append("Commodity.BASE_PRICE: missing entry for type %s" % t)
		if not Commodity.TARGET_STOCK.has(t):
			failures.append("Commodity.TARGET_STOCK: missing entry for type %s" % t)
		if not Commodity.NAMES.has(t):
			failures.append("Commodity.NAMES: missing entry for type %s" % t)

	if Commodity.BASE_PRICE[Commodity.Type.ORE] != 10.0:
		failures.append("Commodity.BASE_PRICE: expected ORE == 10.0, got %s" % Commodity.BASE_PRICE[Commodity.Type.ORE])
	if Commodity.NAMES[Commodity.Type.HULL_PARTS] != "Hull Parts":
		failures.append("Commodity.NAMES: expected HULL_PARTS == 'Hull Parts', got %s" % Commodity.NAMES[Commodity.Type.HULL_PARTS])

	return failures
