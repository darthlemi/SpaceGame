extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []

	if ShipType.kind_of({}) != ShipType.Kind.CORVETTE:
		failures.append("kind_of: expected a dict missing 'ship_type' to default to CORVETTE")
	if ShipType.kind_of({"ship_type": ShipType.Kind.FREIGHTER}) != ShipType.Kind.FREIGHTER:
		failures.append("kind_of: expected an explicit ship_type key to be respected")

	if ShipType.cargo_capacity_for(ShipType.Kind.CORVETTE) != 20.0:
		failures.append("cargo_capacity_for: expected Corvette == 20.0, got %s" % ShipType.cargo_capacity_for(ShipType.Kind.CORVETTE))
	if ShipType.cargo_capacity_for(ShipType.Kind.FREIGHTER) != 60.0:
		failures.append("cargo_capacity_for: expected Freighter == 60.0, got %s" % ShipType.cargo_capacity_for(ShipType.Kind.FREIGHTER))
	if ShipType.cargo_capacity_for(ShipType.Kind.CAPITAL) != 20.0:
		failures.append("cargo_capacity_for: expected Capital == 20.0, got %s" % ShipType.cargo_capacity_for(ShipType.Kind.CAPITAL))

	var comp := ShipType.new_composition(ShipType.Kind.CAPITAL)
	if comp["ship_type"] != ShipType.Kind.CAPITAL:
		failures.append("new_composition: expected ship_type == CAPITAL, got %s" % comp["ship_type"])
	if comp["max_hp"] != 220.0 or comp["current_hp"] != 220.0:
		failures.append("new_composition: expected Capital max_hp/current_hp == 220.0, got %s" % comp)
	if comp["max_shield"] != 80.0 or comp["current_shield"] != 80.0:
		failures.append("new_composition: expected Capital max_shield/current_shield == 80.0, got %s" % comp)

	var corvette_comp := ShipType.new_composition(ShipType.Kind.CORVETTE)
	if corvette_comp["max_hp"] != 60.0 or corvette_comp["max_shield"] != 20.0:
		failures.append("new_composition: expected Corvette max_hp==60.0/max_shield==20.0, got %s" % corvette_comp)

	var freighter_comp := ShipType.new_composition(ShipType.Kind.FREIGHTER)
	if freighter_comp["max_hp"] != 80.0 or freighter_comp["max_shield"] != 20.0:
		failures.append("new_composition: expected Freighter max_hp==80.0/max_shield==20.0, got %s" % freighter_comp)

	return failures
