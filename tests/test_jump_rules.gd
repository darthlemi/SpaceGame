extends RefCounted

static func _starter_fleet() -> CampaignFleet:
	var fleet := CampaignFleet.new()
	fleet.ship_compositions = [
		ShipType.new_composition(ShipType.Kind.CORVETTE),
		ShipType.new_composition(ShipType.Kind.CAPITAL),
		ShipType.new_composition(ShipType.Kind.FREIGHTER),
	]
	return fleet

static func _in_bounds(p: Vector2) -> bool:
	return p.x >= JumpRules.SYSTEM_MIN.x and p.y >= JumpRules.SYSTEM_MIN.y \
			and p.x <= JumpRules.SYSTEM_MAX.x and p.y <= JumpRules.SYSTEM_MAX.y

static func run() -> Array[String]:
	var failures: Array[String] = []

	var fleet := _starter_fleet()
	if absf(JumpRules.jump_cost(fleet) - 9.9) > 0.001:
		failures.append("jump_cost: expected 9.9, got %s" % JumpRules.jump_cost(fleet))
	fleet.cargo = {Commodity.Type.FUEL: 9.8}
	if JumpRules.can_afford(fleet):
		failures.append("can_afford: expected false at 9.8 fuel")
	fleet.cargo = {Commodity.Type.FUEL: 9.9}
	if not JumpRules.can_afford(fleet):
		failures.append("can_afford: expected true at 9.9 fuel")

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var west_limit := JumpRules.SYSTEM_MIN.x + JumpRules.ARRIVAL_EDGE_MARGIN + JumpRules.ARRIVAL_RADIUS
	var west := JumpRules.arrival_point(Vector2(0.0, 0.5), Vector2(1.0, 0.5), rng)
	if west.x > west_limit:
		failures.append("arrival_point: expected west edge (x <= %s), got %s" % [west_limit, west])
	for i in 50:
		var origin := Vector2(rng.randf(), rng.randf())
		var dest := Vector2(rng.randf(), rng.randf())
		var p := JumpRules.arrival_point(origin, dest, rng)
		if not _in_bounds(p):
			failures.append("arrival_point: %s out of bounds for %s -> %s" % [p, origin, dest])
	var same := JumpRules.arrival_point(Vector2(0.5, 0.5), Vector2(0.5, 0.5), rng)
	if not _in_bounds(same):
		failures.append("arrival_point: identical positions out of bounds, got %s" % same)
	if not _in_bounds(JumpRules.edge_point(Vector2(0.0, -1.0))):
		failures.append("edge_point: expected a point in bounds")
	var clamped := JumpRules.clamp_to_system(Vector2(-50.0, 9999.0))
	if clamped != Vector2(JumpRules.SYSTEM_MIN.x, JumpRules.SYSTEM_MAX.y):
		failures.append("clamp_to_system: expected corner, got %s" % clamped)

	var short := _starter_fleet()
	short.cargo = {Commodity.Type.FUEL: 5.9}
	var quote := JumpRules.distress_quote(short, 1000)
	if not quote.get("ok", false) or quote.get("price", -1) != 144 or absf(quote.get("fuel", -1.0) - 4.0) > 0.001:
		failures.append("distress_quote: expected fuel 4.0 / price 144 / ok, got %s" % [quote])
	var poor := JumpRules.distress_quote(short, 100)
	if poor.get("ok", true) or not str(poor.get("reason", "")).begins_with("Not enough credits"):
		failures.append("distress_quote poor: expected 'Not enough credits...', got %s" % [poor])
	var full := _starter_fleet()
	full.cargo = {Commodity.Type.FUEL: 5.9, Commodity.Type.ORE: full.cargo_capacity() - 5.9}
	var full_quote := JumpRules.distress_quote(full, 1000)
	if full_quote.get("ok", true) or full_quote.get("reason", "") != "No cargo room for fuel":
		failures.append("distress_quote full: expected 'No cargo room for fuel', got %s" % [full_quote])
	return failures
