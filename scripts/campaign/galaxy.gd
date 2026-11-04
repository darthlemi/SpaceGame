class_name Galaxy
extends RefCounted

const MAX_TIER := 5

var systems: Dictionary = {}
var stations: Array[StationData] = []
var start_system_id: String = ""

func system(id: String) -> StarSystem:
	return systems.get(id)

func station(id: String) -> StationData:
	for st in stations:
		if st.id == id:
			return st
	return null

func stations_in(system_id: String) -> Array[StationData]:
	var result: Array[StationData] = []
	for st in stations:
		if st.system_id == system_id:
			result.append(st)
	return result

func home_station() -> StationData:
	for st in stations:
		if st.is_home():
			return st
	return null

func neighbours(id: String) -> Array[String]:
	var sys := system(id)
	var result: Array[String] = []
	if sys != null:
		result.assign(sys.links)
	return result

func are_linked(a: String, b: String) -> bool:
	var sys := system(a)
	return sys != null and sys.links.has(b)

# BFS route excluding from_id and including to_id; empty when same or unreachable.
func path(from_id: String, to_id: String) -> Array[String]:
	var result: Array[String] = []
	if from_id == to_id or not systems.has(from_id) or not systems.has(to_id):
		return result
	var came_from := {from_id: ""}
	var queue: Array[String] = [from_id]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		if current == to_id:
			break
		for next in neighbours(current):
			if not came_from.has(next):
				came_from[next] = current
				queue.append(next)
	if not came_from.has(to_id):
		return result
	var step := to_id
	while step != from_id:
		result.push_front(step)
		step = came_from[step]
	return result

# -1 when unreachable (or either id is unknown).
func jump_distance(from_id: String, to_id: String) -> int:
	if from_id == to_id:
		return 0 if systems.has(from_id) else -1
	var route := path(from_id, to_id)
	return route.size() if not route.is_empty() else -1

func link(a: String, b: String) -> void:
	var sys_a := system(a)
	var sys_b := system(b)
	assert(sys_a != null and sys_b != null, "Galaxy.link: unknown system %s or %s" % [a, b])
	if sys_a == null or sys_b == null:
		return
	if not sys_a.links.has(b):
		sys_a.links.append(b)
	if not sys_b.links.has(a):
		sys_b.links.append(a)

func assign_tiers() -> void:
	for id in systems:
		var sys: StarSystem = systems[id]
		if sys.tier_override > 0:
			sys.tier = sys.tier_override
		else:
			sys.tier = clampi(jump_distance(start_system_id, id), 1, MAX_TIER)
