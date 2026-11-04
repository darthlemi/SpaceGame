class_name CrewRules
extends RefCounted

# Tuning placeholders.
const DEPLOY_MIN_CREW_FRACTION := 0.3
const MIN_CREW_EFFICIENCY := 0.5
const NPC_CREW_FLOOR := 1

# Guards fraction * complement float noise (0.3 * 40 is 12.000000000000002) before rounding up.
const ROUND_EPSILON := 0.0001

# Larger value = larger class; used for flagship choice and leftover-crew ordering.
const CLASS_SIZE_RANK := {
	ShipType.Kind.FREIGHTER: 0,
	ShipType.Kind.CORVETTE: 1,
	ShipType.Kind.CAPITAL: 2,
}

static func add_crew(comps: Array[Dictionary], amount: int) -> int:
	var added := 0
	while added < amount:
		var target := -1
		for i in comps.size():
			if crew_of(comps[i]) >= complement(comps[i]):
				continue
			if target == -1 or crew_fraction(comps[i]) < crew_fraction(comps[target]):
				target = i
		if target == -1:
			break
		set_crew(comps[target], crew_of(comps[target]) + 1)
		added += 1
	return added

static func balance(comps: Array[Dictionary]) -> void:
	var total := 0
	var capacity := 0
	for comp in comps:
		total += crew_of(comp)
		capacity += complement(comp)
	if capacity == 0:
		return
	# Integer floor avoids float noise; leftover is under one crew per ship.
	var leftover := total
	for comp in comps:
		var share := total * complement(comp) / capacity
		set_crew(comp, share)
		leftover -= share
	var order: Array[int] = []
	for i in comps.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var flag_a := is_flagship(comps[a])
		var flag_b := is_flagship(comps[b])
		if flag_a != flag_b:
			return flag_a
		var rank_a := class_size_rank(comps[a])
		var rank_b := class_size_rank(comps[b])
		if rank_a != rank_b:
			return rank_a > rank_b
		return a < b)
	for i in order:
		if leftover <= 0:
			break
		set_crew(comps[i], crew_of(comps[i]) + 1)
		leftover -= 1

# Top speed with crew and engine damage applied; missing keys read as full health.
static func comp_top_speed(comp: Dictionary) -> float:
	var base := ShipType.base_speed_for(ShipType.kind_of(comp))
	var engine_path: String = comp.get("engine_item", "")
	if engine_path != "":
		base = load(engine_path).max_speed
	var engine_max: float = comp.get("engine_max_hp", 0.0)
	var engine_fraction := 1.0
	if engine_max > 0.0:
		engine_fraction = clampf(comp.get("engine_current_hp", engine_max) / engine_max, 0.0, 1.0)
	return base * efficiency_for(float(crew_of(comp)), complement(comp)) * engine_fraction

static func class_size_rank(comp: Dictionary) -> int:
	return CLASS_SIZE_RANK[ShipType.kind_of(comp)]

static func complement(comp: Dictionary) -> int:
	return ShipType.crew_for(ShipType.kind_of(comp))

static func crew_fraction(comp: Dictionary) -> float:
	var full := complement(comp)
	return float(crew_of(comp)) / float(full) if full > 0 else 0.0

static func crew_of(comp: Dictionary) -> int:
	return comp.get("crew", complement(comp))

static func deploy_indices(comps: Array[Dictionary]) -> Array[int]:
	var result: Array[int] = []
	for i in comps.size():
		if wants_deploy(comps[i]) and crew_of(comps[i]) >= deploy_min_for(complement(comps[i])):
			result.append(i)
	if not result.is_empty():
		return result
	var best := _highest_crew_index(comps, true)
	if best == -1:
		best = _flagship_index(comps)
	if best == -1:
		best = _highest_crew_index(comps, false)
	if best != -1:
		result.append(best)
	return result

static func deploy_min_for(complement_crew: int) -> int:
	return _threshold(DEPLOY_MIN_CREW_FRACTION, complement_crew)

static func efficiency_for(crew: float, complement_crew: int) -> float:
	if complement_crew <= 0:
		return 1.0
	return lerpf(MIN_CREW_EFFICIENCY, 1.0, clampf(crew / float(complement_crew), 0.0, 1.0))

static func free_berths(comps: Array[Dictionary]) -> int:
	var sum := 0
	for comp in comps:
		sum += complement(comp) - crew_of(comp)
	return sum

# A missing weapon_mount_current_hp key counts as armed (bootstrap comps).
static func is_armed(comp: Dictionary) -> bool:
	var count := int(ShipType.BASE_STATS[ShipType.kind_of(comp)]["weapon_mount_count"])
	if count <= 0:
		return false
	if not comp.has("weapon_mount_current_hp"):
		return true
	for hp in comp["weapon_mount_current_hp"]:
		if hp > 0.0:
			return true
	return false

static func is_flagship(comp: Dictionary) -> bool:
	return comp.get("flagship", false)

static func remove_crew(comps: Array[Dictionary], amount: int, protect_index: int, protect_floor: int) -> int:
	var removed := 0
	while removed < amount:
		var target := -1
		for i in comps.size():
			if i == protect_index or crew_of(comps[i]) <= 0:
				continue
			if target == -1 or crew_fraction(comps[i]) < crew_fraction(comps[target]):
				target = i
		if target == -1:
			if protect_index < 0 or protect_index >= comps.size() or crew_of(comps[protect_index]) <= protect_floor:
				break
			target = protect_index
		set_crew(comps[target], crew_of(comps[target]) - 1)
		removed += 1
	return removed

static func set_crew(comp: Dictionary, value: int) -> void:
	comp["crew"] = clampi(value, 0, complement(comp))

# Zero-sum: crew moves between this ship and the others, so the fleet total never changes.
static func set_ship_crew(comps: Array[Dictionary], index: int, target: int) -> void:
	var goal := clampi(target, 0, complement(comps[index]))
	while crew_of(comps[index]) != goal:
		var raising := goal > crew_of(comps[index])
		var other := -1
		for i in comps.size():
			if i == index:
				continue
			if raising:
				if crew_of(comps[i]) <= 0:
					continue
				if other == -1 or crew_fraction(comps[i]) > crew_fraction(comps[other]):
					other = i
			else:
				if crew_of(comps[i]) >= complement(comps[i]):
					continue
				if other == -1 or crew_fraction(comps[i]) < crew_fraction(comps[other]):
					other = i
		if other == -1:
			return
		var step := 1 if raising else -1
		set_crew(comps[index], crew_of(comps[index]) + step)
		set_crew(comps[other], crew_of(comps[other]) - step)

static func wants_deploy(comp: Dictionary) -> bool:
	return comp.get("deploy", true)

static func _flagship_index(comps: Array[Dictionary]) -> int:
	for i in comps.size():
		if is_flagship(comps[i]):
			return i
	return -1

# Ties go to the lowest index.
static func _highest_crew_index(comps: Array[Dictionary], only_wanted: bool) -> int:
	var best := -1
	for i in comps.size():
		if only_wanted and not wants_deploy(comps[i]):
			continue
		if best == -1 or crew_of(comps[i]) > crew_of(comps[best]):
			best = i
	return best

static func _threshold(fraction: float, complement_crew: int) -> int:
	return ceili(fraction * complement_crew - ROUND_EPSILON)
