extends RefCounted

const EconomyRole = preload("res://scripts/campaign/economy_role.gd")
const Commodity = preload("res://scripts/campaign/commodity.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var mining := EconomyRole.mining()
	if mining.role_type != EconomyRole.RoleType.MINING:
		failures.append("mining: expected role_type MINING, got %s" % mining.role_type)
	if mining.produces.get(Commodity.Type.ORE, 0.0) <= 0.0:
		failures.append("mining: expected it to produce Ore")
	if not mining.consumes.is_empty():
		failures.append("mining: expected no consumption")

	var agriculture := EconomyRole.agriculture()
	if agriculture.produces.get(Commodity.Type.FOOD, 0.0) <= 0.0:
		failures.append("agriculture: expected it to produce Food")

	var industrial := EconomyRole.industrial()
	if industrial.role_type != EconomyRole.RoleType.INDUSTRIAL:
		failures.append("industrial: expected role_type INDUSTRIAL, got %s" % industrial.role_type)
	if industrial.consumes.get(Commodity.Type.ORE, 0.0) <= 0.0 or industrial.consumes.get(Commodity.Type.FUEL, 0.0) <= 0.0:
		failures.append("industrial: expected it to consume Ore and Fuel")
	if industrial.produces.get(Commodity.Type.WEAPONS, 0.0) <= 0.0:
		failures.append("industrial: expected it to produce Weapons")

	var population := EconomyRole.population()
	if population.consumes.get(Commodity.Type.FOOD, 0.0) <= 0.0:
		failures.append("population: expected it to consume Food")
	if not population.produces.is_empty():
		failures.append("population: expected no production")

	var trade_hub := EconomyRole.trade_hub()
	if trade_hub.role_type != EconomyRole.RoleType.TRADE_HUB:
		failures.append("trade_hub: expected role_type TRADE_HUB, got %s" % trade_hub.role_type)
	if not trade_hub.produces.is_empty() or not trade_hub.consumes.is_empty():
		failures.append("trade_hub: expected no production or consumption")

	return failures
