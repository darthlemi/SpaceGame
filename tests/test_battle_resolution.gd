extends RefCounted

const BattleResolution = preload("res://scripts/combat/battle_resolution.gd")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	# escape_chance
	var cases := [[100.0, 100.0, 0.5], [200.0, 100.0, 0.9], [25.0, 100.0, 0.1], [50.0, 0.0, 1.0]]
	for c in cases:
		var got := BattleResolution.escape_chance(c[0], c[1])
		if not is_equal_approx(got, c[2]):
			failures.append("escape_chance(%s, %s): expected %s, got %s" % [c[0], c[1], c[2], got])

	# roll_escapes: a seeded rng gives the same rolls every run.
	var speeds: Array[float] = [100.0, 100.0, 100.0]
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 1234
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 1234
	var rolls_a := BattleResolution.roll_escapes(speeds, 100.0, rng_a)
	var rolls_b := BattleResolution.roll_escapes(speeds, 100.0, rng_b)
	if rolls_a != rolls_b:
		failures.append("roll_escapes: expected identical rolls for seed 1234, got %s vs %s" % [rolls_a, rolls_b])
	# Seed 1234 draws 0.107, 0.452, 0.021: all under the 0.5 equal-speed chance, so all escape.
	if rolls_a != [true, true, true]:
		failures.append("roll_escapes: expected [true, true, true] for seed 1234 at equal speed, got %s" % [rolls_a])
	var rng_zero := RandomNumberGenerator.new()
	rng_zero.seed = 14  # First draw 0.996: only a 100% chance escapes it.
	var slow: Array[float] = [50.0]
	if BattleResolution.roll_escapes(slow, 0.0, rng_zero) != [true]:
		failures.append("roll_escapes: expected escape against a pursuer speed of 0")
	var empty_speeds: Array[float] = []
	if BattleResolution.roll_escapes(empty_speeds, 100.0, rng_a) != []:
		failures.append("roll_escapes: expected [] for no escapers")

	# split_cargo: the captured share follows cargo capacity.
	var fleet := CampaignFleet.new()
	fleet.ship_compositions.assign([ShipType.new_composition(ShipType.Kind.CAPITAL), ShipType.new_composition(ShipType.Kind.FREIGHTER)])
	fleet.cargo = {Commodity.Type.ORE: 80.0}
	fleet.part_inventory.assign(["part_a", "part_b", "part_c"])
	var captured_freighter: Array[int] = [1]
	var split := BattleResolution.split_cargo(fleet, captured_freighter)
	if not is_equal_approx(split["loot_cargo"].get(Commodity.Type.ORE, 0.0), 60.0):
		failures.append("split_cargo: expected loot ORE 60, got %s" % split["loot_cargo"])
	if not is_equal_approx(split["kept_cargo"].get(Commodity.Type.ORE, 0.0), 20.0):
		failures.append("split_cargo: expected kept ORE 20, got %s" % split["kept_cargo"])
	if split["loot_parts"] != ["part_a", "part_b"]:
		failures.append("split_cargo: expected the first 2 parts looted, got %s" % [split["loot_parts"]])
	if split["kept_parts"] != ["part_c"]:
		failures.append("split_cargo: expected the last part kept, got %s" % [split["kept_parts"]])
	if fleet.cargo.get(Commodity.Type.ORE) != 80.0 or fleet.part_inventory.size() != 3:
		failures.append("split_cargo: expected the fleet's own cargo untouched")

	var captured_all: Array[int] = [0, 1]
	var all_split := BattleResolution.split_cargo(fleet, captured_all)
	if all_split["loot_cargo"].get(Commodity.Type.ORE, 0.0) != 80.0 or all_split["loot_parts"].size() != 3:
		failures.append("split_cargo: expected all cargo looted when every ship is captured, got %s" % all_split)
	if all_split["kept_cargo"].get(Commodity.Type.ORE, 0.0) != 0.0 or not all_split["kept_parts"].is_empty():
		failures.append("split_cargo: expected nothing kept when every ship is captured, got %s" % all_split)

	var captured_none: Array[int] = []
	var none_split := BattleResolution.split_cargo(fleet, captured_none)
	if none_split["kept_cargo"].get(Commodity.Type.ORE, 0.0) != 80.0 or none_split["kept_parts"].size() != 3:
		failures.append("split_cargo: expected all cargo kept when nothing is captured, got %s" % none_split)

	# A fleet with no ships left (all destroyed) has nothing to keep it: everything is loot.
	var empty_fleet := CampaignFleet.new()
	empty_fleet.cargo = {Commodity.Type.ORE: 5.0}
	var empty_split := BattleResolution.split_cargo(empty_fleet, captured_none)
	if empty_split["loot_cargo"].get(Commodity.Type.ORE, 0.0) != 5.0:
		failures.append("split_cargo: expected all cargo looted from a fleet with no ships, got %s" % empty_split)

	return failures
