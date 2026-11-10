class_name GalaxyData
extends RefCounted

# The galaxy lives in data/galaxy.json (see GalaxyDocument); edit it by hand or with the map editor.
const STATION_MAX_SLOTS := 2

# A missing or corrupt file is a hard failure: there is no fallback to a stale galaxy.
static func build() -> Galaxy:
	var result := GalaxyDocument.load_file()
	if not result["ok"]:
		push_error("GalaxyData: cannot load %s: %s" % [GalaxyDocument.PATH, result["error"]])
		assert(false, "GalaxyData: cannot load %s" % GalaxyDocument.PATH)
		return Galaxy.new()
	return build_from(result["doc"])

static func build_from(doc: Dictionary) -> Galaxy:
	var galaxy := Galaxy.new()
	galaxy.start_system_id = doc["start_system"]
	for entry in doc["systems"]:
		var sys := _make_system(entry)
		galaxy.systems[sys.id] = sys
	for entry in doc["stations"]:
		galaxy.add_station(_make_station(entry, doc["presets"]))
	for pair in doc["links"]:
		galaxy.link(pair[0], pair[1])
	galaxy.assign_tiers()
	return galaxy

# The six built-in presets in document shape (names as keys), at the EconomyRole factory numbers.
static func default_presets() -> Dictionary:
	var presets := {}
	for role in [EconomyRole.agriculture(), EconomyRole.industrial(), EconomyRole.mining(),
			EconomyRole.population(), EconomyRole.refinery(), EconomyRole.trade_hub()]:
		presets[role.preset] = {
			"kind": EconomyRole.RoleType.keys()[role.role_type],
			"produces": _named(role.produces, Commodity.Type.keys()),
			"consumes": _named(role.consumes, Commodity.Type.keys()),
			"housing": role.housing,
		}
	return presets

static func _named(map: Dictionary, names: Array) -> Dictionary:
	var out := {}
	for key in map:
		out[names[key]] = map[key]
	return out

static func _make_system(entry: Dictionary) -> StarSystem:
	var sys := StarSystem.new()
	sys.id = entry["id"]
	sys.display_name = entry["name"]
	sys.map_position = Vector2(entry["map"][0], entry["map"][1])
	sys.tier_override = int(entry.get("tier", 0))
	sys.background_override = entry.get("background", {})
	sys.scenery = entry.get("scenery", [])
	return sys

static func _make_station(entry: Dictionary, presets: Dictionary) -> StationData:
	var st := StationData.new()
	st.display_name = entry["name"]
	st.id = GalaxyDocument.station_id(st.display_name)
	st.system_id = entry["system"]
	st.position = Vector2(entry["pos"][0], entry["pos"][1])
	var owner_index := CampaignFleet.Faction.keys().find(entry["owner"])
	assert(owner_index >= 0, "GalaxyData: unknown owner '%s'" % entry["owner"])
	st.owner = CampaignFleet.Faction.values()[owner_index]
	st.art = entry["art"]
	for role_name in entry.get("quota", {}):
		var role_index := CampaignFleet.Role.keys().find(role_name)
		assert(role_index >= 0, "GalaxyData: unknown fleet role '%s'" % role_name)
		st.fleet_quota[CampaignFleet.Role.values()[role_index]] = int(entry["quota"][role_name])
	for commodity_name in entry.get("stock", {}):
		var commodity_index := Commodity.Type.keys().find(commodity_name)
		assert(commodity_index >= 0, "GalaxyData: unknown commodity '%s'" % commodity_name)
		st.starting_stock[Commodity.Type.values()[commodity_index]] = float(entry["stock"][commodity_name])
	st.economy = BaseEconomy.new()
	for slot in entry["slots"]:
		var preset_name: String = slot if typeof(slot) == TYPE_STRING else slot["preset"]
		var overrides: Dictionary = {} if typeof(slot) == TYPE_STRING else slot.get("overrides", {})
		assert(presets.has(preset_name), "GalaxyData: unknown preset '%s'" % preset_name)
		st.economy.slots.append(EconomyRole.from_preset(preset_name, presets[preset_name], overrides))
	st.economy.max_slots = STATION_MAX_SLOTS
	return st
