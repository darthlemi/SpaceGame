class_name GalaxyValidator
extends RefCounted

# Checks a galaxy document. "block" findings stop Save; "warn" findings are shown only.
# A finding is {"severity", "message", "target": {"kind": "system" | "station" | "link" | "doc", "id"}}.

static func has_blockers(findings: Array[Dictionary]) -> bool:
	for f in findings:
		if f["severity"] == "block":
			return true
	return false

static func validate(doc: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var presets: Dictionary = doc.get("presets", {})
	var system_ids := _check_systems(doc, out)
	_check_presets(presets, out)
	_check_stations(doc, presets, system_ids, out)
	_check_links(doc, system_ids, out)
	_check_start_and_player(doc, system_ids, out)
	return out

static func _add(out: Array[Dictionary], severity: String, kind: String, id: String, message: String) -> void:
	out.append({"severity": severity, "message": message, "target": {"kind": kind, "id": id}})

static func _check_systems(doc: Dictionary, out: Array[Dictionary]) -> Dictionary:
	var ids := {}
	for sys in doc.get("systems", []):
		var id := str(sys.get("id", ""))
		if ids.has(id):
			_add(out, "block", "system", id, "Two systems share the id '%s'. Give one a different id." % id)
		ids[id] = true
	return ids

static func _check_presets(presets: Dictionary, out: Array[Dictionary]) -> void:
	for name in presets:
		var preset: Dictionary = presets[name]
		if not EconomyRole.RoleType.keys().has(preset.get("kind", "")):
			_add(out, "block", "doc", "", "Preset '%s' has an unknown kind '%s'." % [name, preset.get("kind", "")])
		_check_amounts(preset.get("produces", {}), "preset '%s' produces" % name, "doc", "", out)
		_check_amounts(preset.get("consumes", {}), "preset '%s' consumes" % name, "doc", "", out)
		if float(preset.get("housing", 0.0)) < 0.0:
			_add(out, "block", "doc", "", "Preset '%s' has negative housing." % name)

# Commodity-name -> amount maps: every name must be a Commodity.Type and no amount negative.
static func _check_amounts(amounts: Dictionary, label: String, kind: String, id: String, out: Array[Dictionary]) -> void:
	for commodity in amounts:
		if not Commodity.Type.keys().has(commodity):
			_add(out, "block", kind, id, "%s: '%s' is not a commodity." % [label.capitalize(), commodity])
		elif float(amounts[commodity]) < 0.0:
			_add(out, "block", kind, id, "%s: %s is negative. Use 0 or more." % [label.capitalize(), commodity])

static func _check_stations(doc: Dictionary, presets: Dictionary, system_ids: Dictionary, out: Array[Dictionary]) -> void:
	var seen := {}
	var stations_per_system := {}
	for st in doc.get("stations", []):
		var name := str(st.get("name", ""))
		var id := GalaxyDocument.station_id(name)
		if seen.has(id):
			_add(out, "block", "station", id, "Two stations share the id '%s' (names are compared lower-cased). Rename one." % id)
		seen[id] = true
		var system_id := str(st.get("system", ""))
		stations_per_system[system_id] = true
		if not system_ids.has(system_id):
			_add(out, "block", "station", id, "Station '%s' is in unknown system '%s'. Move it to an existing system." % [name, system_id])
		if not CampaignFleet.Faction.keys().has(st.get("owner", "")):
			_add(out, "block", "station", id, "Station '%s' has an unknown owner '%s'." % [name, st.get("owner", "")])
		for role in st.get("quota", {}):
			if not CampaignFleet.Role.keys().has(role):
				_add(out, "block", "station", id, "Station '%s' has a quota for unknown fleet role '%s'." % [name, role])
		_check_amounts(st.get("stock", {}), "station '%s' stock" % name, "station", id, out)
		_check_slots(st, name, id, presets, out)
	for sys in doc.get("systems", []):
		if not stations_per_system.has(str(sys.get("id", ""))):
			_add(out, "warn", "system", str(sys.get("id", "")), "System '%s' has no stations." % sys.get("name", ""))

static func _check_slots(st: Dictionary, name: String, id: String, presets: Dictionary, out: Array[Dictionary]) -> void:
	var slots: Array = st.get("slots", [])
	if slots.is_empty():
		_add(out, "warn", "station", id, "Station '%s' has no slots." % name)
	if slots.size() > GalaxyData.STATION_MAX_SLOTS:
		_add(out, "block", "station", id, "Station '%s' has %d slots; the maximum is %d. Remove one." % [name, slots.size(), GalaxyData.STATION_MAX_SLOTS])
	for slot in slots:
		var preset_name := str(slot if typeof(slot) == TYPE_STRING else slot.get("preset", ""))
		if not presets.has(preset_name):
			_add(out, "block", "station", id, "Station '%s' uses unknown preset '%s'. Pick an existing preset." % [name, preset_name])
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		var overrides: Dictionary = slot.get("overrides", {})
		_check_amounts(overrides.get("produces", {}), "station '%s' slot override produces" % name, "station", id, out)
		_check_amounts(overrides.get("consumes", {}), "station '%s' slot override consumes" % name, "station", id, out)
		if float(overrides.get("housing", 0.0)) < 0.0:
			_add(out, "block", "station", id, "Station '%s' has a negative housing override." % name)

static func _check_links(doc: Dictionary, system_ids: Dictionary, out: Array[Dictionary]) -> void:
	var adjacency := {}
	for pair in doc.get("links", []):
		var a := str(pair[0])
		var b := str(pair[1])
		if not system_ids.has(a) or not system_ids.has(b):
			_add(out, "block", "link", "%s|%s" % [a, b], "Link %s - %s names an unknown system. Delete the link." % [a, b])
			continue
		adjacency[a] = true
		adjacency[b] = true
	var reachable := _reachable(doc, system_ids)
	var multi := system_ids.size() > 1
	for sys in doc.get("systems", []):
		var id := str(sys.get("id", ""))
		if multi and not adjacency.has(id):
			_add(out, "block", "system", id, "System '%s' has no links. Link it to another system." % sys.get("name", id))
		elif multi and not reachable.has(id) and system_ids.has(str(doc.get("start_system", ""))):
			_add(out, "block", "system", id, "System '%s' cannot be reached from the start system. Link it to the connected galaxy." % sys.get("name", id))

# Undirected breadth-first search from start_system.
static func _reachable(doc: Dictionary, system_ids: Dictionary) -> Dictionary:
	var start := str(doc.get("start_system", ""))
	var seen := {}
	if not system_ids.has(start):
		return seen
	var neighbours := {}
	for pair in doc.get("links", []):
		var a := str(pair[0])
		var b := str(pair[1])
		if not neighbours.has(a):
			neighbours[a] = []
		if not neighbours.has(b):
			neighbours[b] = []
		neighbours[a].append(b)
		neighbours[b].append(a)
	var queue: Array = [start]
	seen[start] = true
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next in neighbours.get(current, []):
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen

static func _check_start_and_player(doc: Dictionary, system_ids: Dictionary, out: Array[Dictionary]) -> void:
	var start := str(doc.get("start_system", ""))
	if start.is_empty():
		_add(out, "block", "doc", "", "No start system is set.")
	elif not system_ids.has(start):
		_add(out, "block", "doc", "", "The start system '%s' does not exist." % start)
	var players: Array = []
	for st in doc.get("stations", []):
		if st.get("owner", "") == "PLAYER":
			players.append(st)
	if players.size() != 1:
		_add(out, "block", "doc", "", "The galaxy needs exactly one PLAYER station; it has %d." % players.size())
	elif players[0].get("system", "") != start and system_ids.has(start):
		_add(out, "block", "doc", "", "The PLAYER station must be in the start system '%s'." % start)
