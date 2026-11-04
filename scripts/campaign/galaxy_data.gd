class_name GalaxyData
extends RefCounted

const START_SYSTEM_ID := "haven"
const STATION_MAX_SLOTS := 2

const D := CampaignFleet.Faction.DOMINION
const F := CampaignFleet.Faction.FREEHOLD
const N := CampaignFleet.Faction.NEUTRAL
const P := CampaignFleet.Faction.PIRATE
const HOME := CampaignFleet.Faction.PLAYER
const COMBAT := CampaignFleet.Role.COMBAT
const TRADER := CampaignFleet.Role.TRADER

# Jump-map position is normalised 0..1. Tier is the jump distance from START_SYSTEM_ID.
const SYSTEMS := [
	{"id": "aurum", "name": "Aurum", "map": Vector2(0.70, 0.76)},
	{"id": "ashfall", "name": "Ashfall", "map": Vector2(0.97, 0.08)},
	{"id": "bastion", "name": "Bastion", "map": Vector2(0.73, 0.58)},
	{"id": "blackwake", "name": "Blackwake", "map": Vector2(0.66, 0.16)},
	{"id": "cinder", "name": "Cinder", "map": Vector2(0.36, 0.34)},
	{"id": "crownspire", "name": "Crownspire", "map": Vector2(0.92, 0.26)},
	{"id": "deadreach", "name": "Deadreach", "map": Vector2(0.04, 0.08)},
	{"id": "farhaven", "name": "Farhaven", "map": Vector2(0.08, 0.26)},
	{"id": "freeport", "name": "Freeport", "map": Vector2(0.17, 0.42)},
	{"id": "frostline", "name": "Frostline", "map": Vector2(0.50, 0.08)},
	{"id": "gallows", "name": "Gallows", "map": Vector2(0.34, 0.16)},
	{"id": "greenreach", "name": "Greenreach", "map": Vector2(0.27, 0.58)},
	{"id": "haven", "name": "Haven", "map": Vector2(0.50, 0.50)},
	{"id": "ironhold", "name": "Ironhold", "map": Vector2(0.83, 0.42)},
	{"id": "kestrel", "name": "Kestrel", "map": Vector2(0.62, 0.50)},
	{"id": "marrow", "name": "Marrow", "map": Vector2(0.50, 0.64)},
	{"id": "northgate", "name": "Northgate", "map": Vector2(0.50, 0.22)},
	{"id": "redtide", "name": "Redtide", "map": Vector2(0.82, 0.90)},
	{"id": "saltmarsh", "name": "Saltmarsh", "map": Vector2(0.18, 0.90)},
	{"id": "slagfall", "name": "Slagfall", "map": Vector2(0.64, 0.34)},
	{"id": "southdeep", "name": "Southdeep", "map": Vector2(0.50, 0.78)},
	{"id": "thornfield", "name": "Thornfield", "map": Vector2(0.30, 0.76)},
	{"id": "tollgate", "name": "Tollgate", "map": Vector2(0.50, 0.36)},
	{"id": "voidmouth", "name": "Voidmouth", "map": Vector2(0.62, 0.03)},
	{"id": "wexford", "name": "Wexford", "map": Vector2(0.38, 0.50)},
	{"id": "wreckyard", "name": "Wreckyard", "map": Vector2(0.50, 0.92)},
]

# roles are EconomyRole factory names; quota maps Role -> target fleet count.
const STATIONS := [
	{"name": "Aurum Spire", "system": "aurum", "owner": D, "pos": Vector2(300, 250), "art": "spoke_3", "roles": ["industrial", "refinery"], "quota": {COMBAT: 1, TRADER: 1}},
	{"name": "Aurum Bazaar", "system": "aurum", "owner": N, "pos": Vector2(850, 420), "art": "cross_2", "roles": ["trade_hub", "population"], "quota": {TRADER: 1}},
	{"name": "Ashfall Citadel", "system": "ashfall", "owner": P, "pos": Vector2(850, 420), "art": "ring_2", "roles": ["refinery", "population"], "quota": {COMBAT: 2}},
	{"name": "Ashfall Yard", "system": "ashfall", "owner": P, "pos": Vector2(300, 250), "art": "cross_3", "roles": ["refinery", "trade_hub"], "quota": {COMBAT: 1}},
	{"name": "Bastion", "system": "bastion", "owner": D, "pos": Vector2(580, 350), "art": "ring_4", "roles": ["industrial", "population"], "quota": {COMBAT: 2, TRADER: 1}},
	{"name": "Bastion Yards", "system": "bastion", "owner": D, "pos": Vector2(850, 500), "art": "truss_6", "roles": ["industrial", "refinery"], "quota": {TRADER: 1}},
	{"name": "Blackwake Den", "system": "blackwake", "owner": P, "pos": Vector2(580, 350), "art": "spoke_4", "roles": ["refinery", "trade_hub"], "quota": {COMBAT: 2}},
	{"name": "Cinder Works", "system": "cinder", "owner": F, "pos": Vector2(300, 250), "art": "truss_5", "roles": ["mining", "refinery"], "quota": {COMBAT: 1, TRADER: 1}},
	{"name": "Cinder Market", "system": "cinder", "owner": N, "pos": Vector2(850, 420), "art": "cross_2", "roles": ["trade_hub", "population"], "quota": {TRADER: 1}},
	{"name": "Crownspire", "system": "crownspire", "owner": D, "pos": Vector2(580, 350), "art": "ring_3", "roles": ["industrial", "population"], "quota": {COMBAT: 2, TRADER: 1}},
	{"name": "Deadreach Citadel", "system": "deadreach", "owner": P, "pos": Vector2(300, 250), "art": "truss_1", "roles": ["refinery", "population"], "quota": {COMBAT: 2}},
	{"name": "Deadreach Yard", "system": "deadreach", "owner": P, "pos": Vector2(850, 420), "art": "spoke_4", "roles": ["refinery", "trade_hub"], "quota": {COMBAT: 1}},
	{"name": "Farhaven", "system": "farhaven", "owner": N, "pos": Vector2(580, 350), "art": "arcs_2", "roles": ["agriculture", "mining"], "quota": {COMBAT: 1, TRADER: 1}},
	{"name": "Freeport", "system": "freeport", "owner": N, "pos": Vector2(300, 250), "art": "cross_1", "roles": ["trade_hub", "population"], "quota": {TRADER: 1}},
	{"name": "Freehold Watch", "system": "freeport", "owner": F, "pos": Vector2(850, 420), "art": "truss_1", "roles": ["mining", "agriculture"], "quota": {COMBAT: 1}},
	{"name": "Frostline Relay", "system": "frostline", "owner": N, "pos": Vector2(580, 350), "art": "ring_4", "roles": ["mining", "refinery"], "quota": {COMBAT: 1, TRADER: 1}},
	{"name": "Gallows Roost", "system": "gallows", "owner": P, "pos": Vector2(580, 350), "art": "truss_3", "roles": ["refinery", "trade_hub"], "quota": {COMBAT: 2}},
	{"name": "Greenreach", "system": "greenreach", "owner": F, "pos": Vector2(580, 350), "art": "ring_3", "roles": ["mining", "agriculture"], "quota": {COMBAT: 2, TRADER: 1}},
	{"name": "Greenreach Fields", "system": "greenreach", "owner": F, "pos": Vector2(300, 500), "art": "arcs_2", "roles": ["agriculture", "population"], "quota": {TRADER: 1}},
	{"name": "Home Base", "system": "haven", "owner": HOME, "pos": Vector2(600, 400), "art": "ring_2", "roles": ["trade_hub", "refinery"], "quota": {}},
	{"name": "Haven Exchange", "system": "haven", "owner": N, "pos": Vector2(300, 250), "art": "cross_1", "roles": ["trade_hub", "population"], "quota": {TRADER: 1}},
	{"name": "Ironhold", "system": "ironhold", "owner": D, "pos": Vector2(580, 350), "art": "ring_2", "roles": ["industrial", "population"], "quota": {COMBAT: 2, TRADER: 1}},
	{"name": "Kestrel Picket", "system": "kestrel", "owner": D, "pos": Vector2(300, 250), "art": "spoke_2", "roles": ["industrial", "refinery"], "quota": {COMBAT: 1, TRADER: 1}},
	{"name": "Marrow Depot", "system": "marrow", "owner": N, "pos": Vector2(300, 250), "art": "truss_3", "roles": ["agriculture", "trade_hub"], "quota": {TRADER: 1}},
	{"name": "Marrow Hideout", "system": "marrow", "owner": P, "pos": Vector2(850, 420), "art": "spoke_3", "roles": ["refinery", "trade_hub"], "quota": {COMBAT: 1}},
	{"name": "Northgate Hub", "system": "northgate", "owner": N, "pos": Vector2(580, 350), "art": "arcs_3", "roles": ["trade_hub", "population"], "quota": {COMBAT: 1, TRADER: 1}},
	{"name": "Redtide Lair", "system": "redtide", "owner": P, "pos": Vector2(580, 350), "art": "spoke_3", "roles": ["refinery", "trade_hub"], "quota": {COMBAT: 2}},
	{"name": "Saltmarsh Den", "system": "saltmarsh", "owner": P, "pos": Vector2(580, 350), "art": "truss_6", "roles": ["refinery", "trade_hub"], "quota": {COMBAT: 2}},
	{"name": "Slagfall Foundry", "system": "slagfall", "owner": D, "pos": Vector2(850, 420), "art": "spoke_4", "roles": ["industrial", "refinery"], "quota": {COMBAT: 1, TRADER: 1}},
	{"name": "Slagfall Exchange", "system": "slagfall", "owner": N, "pos": Vector2(300, 250), "art": "cross_3", "roles": ["trade_hub", "agriculture"], "quota": {TRADER: 1}},
	{"name": "Southdeep Den", "system": "southdeep", "owner": P, "pos": Vector2(580, 350), "art": "spoke_2", "roles": ["refinery", "trade_hub"], "quota": {COMBAT: 2}},
	{"name": "Thornfield", "system": "thornfield", "owner": F, "pos": Vector2(580, 350), "art": "arcs_1", "roles": ["agriculture", "population"], "quota": {COMBAT: 1, TRADER: 1}},
	{"name": "Tollgate Station", "system": "tollgate", "owner": N, "pos": Vector2(580, 520), "art": "arcs_1", "roles": ["trade_hub", "refinery"], "quota": {COMBAT: 1, TRADER: 1}},
	{"name": "Voidmouth Hold", "system": "voidmouth", "owner": P, "pos": Vector2(580, 350), "art": "arcs_3", "roles": ["refinery", "trade_hub"], "quota": {COMBAT: 2}},
	{"name": "Wexford Outpost", "system": "wexford", "owner": F, "pos": Vector2(850, 420), "art": "truss_1", "roles": ["mining", "refinery"], "quota": {COMBAT: 1, TRADER: 1}},
	{"name": "Wreckyard Salvage", "system": "wreckyard", "owner": N, "pos": Vector2(300, 250), "art": "truss_5", "roles": ["industrial", "trade_hub"], "quota": {TRADER: 1}},
	{"name": "Wreckyard Roost", "system": "wreckyard", "owner": P, "pos": Vector2(850, 420), "art": "spoke_2", "roles": ["refinery", "trade_hub"], "quota": {COMBAT: 1}},
]

const LINKS := [
	["haven", "wexford"], ["haven", "kestrel"], ["haven", "tollgate"], ["haven", "marrow"],
	["wexford", "greenreach"], ["wexford", "cinder"],
	["kestrel", "bastion"], ["kestrel", "slagfall"],
	["tollgate", "cinder"], ["tollgate", "slagfall"], ["tollgate", "northgate"],
	["marrow", "greenreach"], ["marrow", "bastion"], ["marrow", "southdeep"],
	["greenreach", "freeport"], ["greenreach", "thornfield"],
	["cinder", "freeport"], ["cinder", "gallows"],
	["bastion", "ironhold"], ["bastion", "aurum"],
	["slagfall", "ironhold"], ["slagfall", "blackwake"],
	["northgate", "gallows"], ["northgate", "blackwake"], ["northgate", "frostline"],
	["southdeep", "thornfield"], ["southdeep", "aurum"], ["southdeep", "wreckyard"],
	["freeport", "farhaven"], ["thornfield", "saltmarsh"],
	["ironhold", "crownspire"], ["aurum", "redtide"],
	["gallows", "farhaven"], ["blackwake", "crownspire"], ["blackwake", "voidmouth"],
	["frostline", "voidmouth"], ["wreckyard", "saltmarsh"], ["wreckyard", "redtide"],
	["farhaven", "deadreach"], ["crownspire", "ashfall"],
]

static func build() -> Galaxy:
	var galaxy := Galaxy.new()
	galaxy.start_system_id = START_SYSTEM_ID
	for entry in SYSTEMS:
		var sys := StarSystem.new()
		sys.id = entry["id"]
		sys.display_name = entry["name"]
		sys.map_position = entry["map"]
		galaxy.systems[sys.id] = sys
	for entry in STATIONS:
		galaxy.add_station(_make_station(entry))
	for pair in LINKS:
		galaxy.link(pair[0], pair[1])
	galaxy.assign_tiers()
	return galaxy

static func _make_station(entry: Dictionary) -> StationData:
	var st := StationData.new()
	st.display_name = entry["name"]
	st.id = st.display_name.to_lower().replace(" ", "_")
	st.system_id = entry["system"]
	st.position = entry["pos"]
	st.owner = entry["owner"]
	st.art = entry["art"]
	st.fleet_quota = entry["quota"].duplicate()
	st.economy = BaseEconomy.new()
	for role_name in entry["roles"]:
		st.economy.slots.append(_make_role(role_name))
	st.economy.max_slots = STATION_MAX_SLOTS
	return st

static func _make_role(role_name: String) -> EconomyRole:
	match role_name:
		"agriculture":
			return EconomyRole.agriculture()
		"industrial":
			return EconomyRole.industrial()
		"mining":
			return EconomyRole.mining()
		"population":
			return EconomyRole.population()
		"refinery":
			return EconomyRole.refinery()
		"trade_hub":
			return EconomyRole.trade_hub()
	assert(false, "GalaxyData: unknown economy role '%s'" % role_name)
	return null
