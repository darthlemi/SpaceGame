class_name DangerTier
extends RefCounted

const MIN_TIER := 1
const MAX_TIER := 5

const COMBAT_SHIPS := {
	1: [ShipType.Kind.CORVETTE],
	2: [ShipType.Kind.CORVETTE, ShipType.Kind.CORVETTE],
	3: [ShipType.Kind.CORVETTE, ShipType.Kind.CORVETTE, ShipType.Kind.CORVETTE],
	4: [ShipType.Kind.CAPITAL, ShipType.Kind.CORVETTE, ShipType.Kind.CORVETTE],
	5: [ShipType.Kind.CAPITAL, ShipType.Kind.CAPITAL, ShipType.Kind.CORVETTE],
}
const TRADER_SHIPS := {
	1: [ShipType.Kind.FREIGHTER],
	2: [ShipType.Kind.FREIGHTER],
	3: [ShipType.Kind.FREIGHTER, ShipType.Kind.FREIGHTER],
	4: [ShipType.Kind.FREIGHTER, ShipType.Kind.FREIGHTER],
	5: [ShipType.Kind.FREIGHTER, ShipType.Kind.FREIGHTER, ShipType.Kind.FREIGHTER],
}
# Inclusive Weapon.Rarity bounds per tier.
const WEAPON_RARITY_RANGE := {
	1: [0, 0],
	2: [0, 1],
	3: [1, 2],
	4: [1, 2],
	5: [2, 3],
}
const CREW_FRACTION := {
	1: 0.7,
	2: 0.8,
	3: 0.9,
	4: 1.0,
	5: 1.0,
}

# Weapon path -> rarity, loaded once.
static var _rarity_by_path: Dictionary = {}

# Tiers outside 1..5 clamp to the nearest table entry.
static func fleet_for(tier: int, role: CampaignFleet.Role, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var key := clampi(tier, MIN_TIER, MAX_TIER)
	var kinds: Array = TRADER_SHIPS[key] if role == CampaignFleet.Role.TRADER else COMBAT_SHIPS[key]
	var comps: Array[Dictionary] = []
	for kind in kinds:
		var comp := ShipType.new_composition(kind)
		_equip_weapons(comp, key, rng)
		CrewRules.set_crew(comp, maxi(CrewRules.NPC_CREW_FLOOR, ceili(CrewRules.complement(comp) * CREW_FRACTION[key])))
		comps.append(comp)
	_flag_largest(comps)
	return comps

static func _equip_weapons(comp: Dictionary, tier: int, rng: RandomNumberGenerator) -> void:
	var candidates := _weapons_in_range(WEAPON_RARITY_RANGE[tier][0], WEAPON_RARITY_RANGE[tier][1])
	var items: Array = comp["weapon_mount_items"]
	for i in items.size():
		items[i] = candidates[rng.randi() % candidates.size()]

# Matches CampaignFleet.ensure_flagship (largest class, lowest index) without a fleet instance.
static func _flag_largest(comps: Array[Dictionary]) -> void:
	var best := 0
	for i in comps.size():
		if CrewRules.class_size_rank(comps[i]) > CrewRules.class_size_rank(comps[best]):
			best = i
	for i in comps.size():
		comps[i]["flagship"] = (i == best)

static func _weapons_in_range(min_rarity: int, max_rarity: int) -> Array[String]:
	if _rarity_by_path.is_empty():
		for path in ShipType.WEAPON_POOL:
			_rarity_by_path[path] = load(path).rarity
	var result: Array[String] = []
	for path in ShipType.WEAPON_POOL:
		var rarity: int = _rarity_by_path[path]
		if rarity >= min_rarity and rarity <= max_rarity:
			result.append(path)
	assert(not result.is_empty(), "DangerTier: no weapon with rarity %d..%d" % [min_rarity, max_rarity])
	return result
