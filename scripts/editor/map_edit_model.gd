class_name MapEditModel
extends RefCounted

# Edits a galaxy document (see GalaxyDocument) in place. Pure logic: no scene, no autoload.
# Refused edits return false / "" and leave the document and `dirty` untouched.

const NEW_STATION_NAME := "New Station"
const NEW_STATION_POS := [580.0, 350.0]
const NEW_STATION_ART := "ring_2"
const NEW_PRESET_HOUSING := 1000.0
const PLAYER_OWNER := "PLAYER"

var doc: Dictionary = {}
var dirty := false

static func from_document(document: Dictionary) -> MapEditModel:
	var model := MapEditModel.new()
	model.doc = document.duplicate(true)
	return model

static func station_id_of(entry: Dictionary) -> String:
	return GalaxyDocument.station_id(str(entry.get("name", "")))

func station_index(id: String) -> int:
	var stations: Array = doc["stations"]
	for i in stations.size():
		if station_id_of(stations[i]) == id:
			return i
	return -1

func stations_in(system_id: String) -> Array:
	var out: Array = []
	for st in doc["stations"]:
		if st.get("system", "") == system_id:
			out.append(st)
	return out

func _system_index(id: String) -> int:
	var systems: Array = doc["systems"]
	for i in systems.size():
		if systems[i].get("id", "") == id:
			return i
	return -1

func _station(id: String) -> Dictionary:
	var i := station_index(id)
	return doc["stations"][i] if i >= 0 else {}

func _touch() -> void:
	dirty = true

static func _vec_to_array(value):
	return [value.x, value.y] if typeof(value) == TYPE_VECTOR2 else value

# --- systems ---

func move_system(id: String, map: Vector2) -> void:
	var i := _system_index(id)
	if i < 0:
		return
	doc["systems"][i]["map"] = [clampf(map.x, 0.0, 1.0), clampf(map.y, 0.0, 1.0)]
	_touch()

func add_system(name: String, map: Vector2) -> String:
	var base := GalaxyDocument.station_id(name)
	if base.is_empty():
		base = "system"
	var id := base
	var n := 2
	while _system_index(id) >= 0:
		id = "%s_%d" % [base, n]
		n += 1
	doc["systems"].append({"id": id, "name": name, "map": [clampf(map.x, 0.0, 1.0), clampf(map.y, 0.0, 1.0)], "extra": {}})
	_touch()
	return id

func delete_system(id: String) -> bool:
	var i := _system_index(id)
	if i < 0:
		return false
	for st in stations_in(id):
		if st.get("owner", "") == PLAYER_OWNER:
			return false
	doc["systems"].remove_at(i)
	var links: Array = []
	for pair in doc["links"]:
		if pair[0] != id and pair[1] != id:
			links.append(pair)
	doc["links"] = links
	var stations: Array = []
	for st in doc["stations"]:
		if st.get("system", "") != id:
			stations.append(st)
	doc["stations"] = stations
	_touch()
	return true

# Keys other than the id; ids are not editable because links and stations refer to them.
func set_system_field(id: String, key: String, value) -> void:
	var i := _system_index(id)
	if i < 0 or key == "id":
		return
	if key == "map" and typeof(value) == TYPE_VECTOR2:
		move_system(id, value)
		return
	if value == null:
		doc["systems"][i].erase(key)
	else:
		doc["systems"][i][key] = _vec_to_array(value)
	_touch()

# --- links ---

func _link_index(a: String, b: String) -> int:
	var links: Array = doc["links"]
	for i in links.size():
		if (links[i][0] == a and links[i][1] == b) or (links[i][0] == b and links[i][1] == a):
			return i
	return -1

func link(a: String, b: String) -> bool:
	if a == b or _system_index(a) < 0 or _system_index(b) < 0 or _link_index(a, b) >= 0:
		return false
	doc["links"].append([a, b])
	_touch()
	return true

func unlink(a: String, b: String) -> bool:
	var i := _link_index(a, b)
	if i < 0:
		return false
	doc["links"].remove_at(i)
	_touch()
	return true

# --- stations ---

func _unique_station_name(base: String) -> String:
	var name := base
	var n := 2
	while station_index(GalaxyDocument.station_id(name)) >= 0:
		name = "%s %d" % [base, n]
		n += 1
	return name

func add_station(system_id: String) -> String:
	if _system_index(system_id) < 0:
		return ""
	var name := _unique_station_name(NEW_STATION_NAME)
	doc["stations"].append({"name": name, "system": system_id, "owner": "NEUTRAL", "pos": NEW_STATION_POS.duplicate(),
		"art": NEW_STATION_ART, "slots": [], "stock": {}, "quota": {}, "extra": {}})
	_touch()
	return GalaxyDocument.station_id(name)

func duplicate_station(id: String) -> String:
	var i := station_index(id)
	if i < 0 or doc["stations"][i].get("owner", "") == PLAYER_OWNER:
		return ""
	var copy: Dictionary = doc["stations"][i].duplicate(true)
	var base := "%s copy" % doc["stations"][i]["name"]
	var name := base
	var n := 2
	while station_index(GalaxyDocument.station_id(name)) >= 0:
		name = "%s %d" % [base, n]
		n += 1
	copy["name"] = name
	doc["stations"].insert(i + 1, copy)
	_touch()
	return GalaxyDocument.station_id(name)

func delete_station(id: String) -> bool:
	var i := station_index(id)
	if i < 0 or doc["stations"][i].get("owner", "") == PLAYER_OWNER:
		return false
	doc["stations"].remove_at(i)
	_touch()
	return true

# A rename changes the derived id; nothing else refers to it, and the station keeps its place.
func set_station_field(id: String, key: String, value) -> void:
	var i := station_index(id)
	if i < 0:
		return
	if value == null:
		doc["stations"][i].erase(key)
	else:
		doc["stations"][i][key] = _vec_to_array(value)
	_touch()

# --- slots ---

func _slot_at(station_id: String, slot_index: int) -> Array:
	var st := _station(station_id)
	if st.is_empty() or slot_index < 0 or slot_index >= st["slots"].size():
		return []
	return st["slots"]

# A slot is a bare preset name, or {"preset", "overrides"} once something is overridden.
static func slot_preset_name(slot) -> String:
	return str(slot if typeof(slot) == TYPE_STRING else slot.get("preset", ""))

static func slot_overrides_of(slot) -> Dictionary:
	return {} if typeof(slot) == TYPE_STRING else slot.get("overrides", {})

# Rebuilds a slot with the given preset and overrides, keeping any other keys the slot carries.
static func _make_slot(slot, preset: String, overrides: Dictionary):
	var out: Dictionary = {} if typeof(slot) == TYPE_STRING else slot.duplicate(true)
	out.erase("overrides")
	out["preset"] = preset
	if not overrides.is_empty():
		out["overrides"] = overrides
	return preset if out.size() == 1 else out

func set_slot_preset(station_id: String, slot_index: int, preset: String) -> void:
	var slots := _slot_at(station_id, slot_index)
	if slots.is_empty():
		return
	if slot_preset_name(slots[slot_index]) == preset:
		return
	# A new preset starts clean: overrides were tuned against the old one.
	slots[slot_index] = _make_slot(slots[slot_index], preset, {})
	_touch()

func add_slot(station_id: String) -> bool:
	var st := _station(station_id)
	if st.is_empty() or st["slots"].size() >= GalaxyData.STATION_MAX_SLOTS or doc["presets"].is_empty():
		return false
	var names: Array = doc["presets"].keys()
	names.sort()
	st["slots"].append(names[0])
	_touch()
	return true

func remove_slot(station_id: String, slot_index: int) -> bool:
	var slots := _slot_at(station_id, slot_index)
	if slots.is_empty():
		return false
	slots.remove_at(slot_index)
	_touch()
	return true

func set_override(station_id: String, slot_index: int, key: String, value) -> void:
	var slots := _slot_at(station_id, slot_index)
	if slots.is_empty():
		return
	var overrides := slot_overrides_of(slots[slot_index]).duplicate(true)
	overrides[key] = value
	slots[slot_index] = _make_slot(slots[slot_index], slot_preset_name(slots[slot_index]), overrides)
	_touch()

func reset_override(station_id: String, slot_index: int, key: String) -> void:
	var slots := _slot_at(station_id, slot_index)
	if slots.is_empty():
		return
	var overrides := slot_overrides_of(slots[slot_index]).duplicate(true)
	if not overrides.erase(key):
		return
	slots[slot_index] = _make_slot(slots[slot_index], slot_preset_name(slots[slot_index]), overrides)
	_touch()

# value null removes the key.
func set_station_extra(station_id: String, key: String, value) -> void:
	var st := _station(station_id)
	if st.is_empty():
		return
	if not st.has("extra"):
		st["extra"] = {}
	if value == null:
		st["extra"].erase(key)
	else:
		st["extra"][key] = value
	_touch()

# --- stock, quota, presets ---

# null or "" clears the entry so the game's default applies.
func set_stock(station_id: String, commodity: String, units) -> void:
	var st := _station(station_id)
	if st.is_empty():
		return
	if units == null or (typeof(units) == TYPE_STRING and str(units).is_empty()):
		st["stock"].erase(commodity)
	else:
		st["stock"][commodity] = float(units)
	_touch()

func set_quota(station_id: String, role: String, count: int) -> void:
	var st := _station(station_id)
	if st.is_empty():
		return
	if count <= 0:
		st["quota"].erase(role)
	else:
		st["quota"][role] = count
	_touch()

func set_preset_field(preset: String, key: String, value) -> void:
	if not doc["presets"].has(preset):
		return
	doc["presets"][preset][key] = value
	_touch()

func add_preset(name: String) -> bool:
	if name.is_empty() or doc["presets"].has(name):
		return false
	doc["presets"][name] = {"kind": "TRADE_HUB", "produces": {}, "consumes": {}, "housing": NEW_PRESET_HOUSING}
	_touch()
	return true
