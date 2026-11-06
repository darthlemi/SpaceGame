class_name DangerTier
extends RefCounted

const MIN_TIER := 1
const MAX_TIER := 5

enum Variant { PICKET, PATROL, ESCORT, SECURITY, CONVOY_SMALL, CONVOY_LARGE }

# Measured by tests\perf_combat.gd: 15v15 passes the frame-time bar at 1x and 5x.
const SECURITY_MAX_SHIPS := 15
# Share of a fleet's hulls that are capitals, by tier (none below tier 4).
const CAPITAL_FRACTION := {
	4: 0.15,
	5: 0.25,
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
	var variant := Variant.CONVOY_SMALL if role == CampaignFleet.Role.TRADER else Variant.PATROL
	return fleet_for_variant(tier, variant, rng)

static func fleet_for_variant(tier: int, variant: Variant, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var key := clampi(tier, MIN_TIER, MAX_TIER)
	var bounds := ship_count_range(variant)
	var count := rng.randi_range(bounds.x, bounds.y)
	var capitals := _capital_count(key, variant, count)
	var is_convoy := role_of(variant) == CampaignFleet.Role.TRADER
	var comps: Array[Dictionary] = []
	for i in count:
		# Capitals lead the list so the flagship is index 0.
		var kind := ShipType.Kind.FREIGHTER if is_convoy else (ShipType.Kind.CAPITAL if i < capitals else ShipType.Kind.CORVETTE)
		var comp := ShipType.new_composition(kind)
		_equip_weapons(comp, key, rng)
		CrewRules.set_crew(comp, maxi(CrewRules.NPC_CREW_FLOOR, ceili(CrewRules.complement(comp) * CREW_FRACTION[key])))
		comps.append(comp)
	_flag_largest(comps)
	return comps

static func role_of(variant: Variant) -> CampaignFleet.Role:
	if variant == Variant.CONVOY_SMALL or variant == Variant.CONVOY_LARGE:
		return CampaignFleet.Role.TRADER
	return CampaignFleet.Role.COMBAT

# Inclusive ship-count bounds.
static func ship_count_range(variant: Variant) -> Vector2i:
	match variant:
		Variant.PICKET:
			return Vector2i(1, 2)
		Variant.PATROL:
			return Vector2i(3, 5)
		Variant.ESCORT:
			return Vector2i(5, 8)
		Variant.SECURITY:
			# Collapses the minimum when the perf cap is below 10.
			return Vector2i(mini(10, SECURITY_MAX_SHIPS), SECURITY_MAX_SHIPS)
		Variant.CONVOY_SMALL:
			return Vector2i(2, 3)
		_:
			return Vector2i(4, 6)

# Capitals only in Patrol/Escort/Security at tier 4+; Escort and Security always get at least one.
static func _capital_count(tier: int, variant: Variant, count: int) -> int:
	if not CAPITAL_FRACTION.has(tier):
		return 0
	if variant != Variant.PATROL and variant != Variant.ESCORT and variant != Variant.SECURITY:
		return 0
	var capitals := floori(count * CAPITAL_FRACTION[tier])
	if variant != Variant.PATROL:
		capitals = maxi(1, capitals)
	return capitals

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
