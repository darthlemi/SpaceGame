class_name EconomyRole
extends Resource

enum RoleType { MINING, AGRICULTURE, INDUSTRIAL, POPULATION, TRADE_HUB, REFINERY }

# Population each role can house; a base's population is capped by the sum.
const HOUSING := {
	RoleType.MINING: 800.0,
	RoleType.AGRICULTURE: 1200.0,
	RoleType.INDUSTRIAL: 1500.0,
	RoleType.POPULATION: 5000.0,
	RoleType.TRADE_HUB: 2000.0,
	RoleType.REFINERY: 800.0,
}

@export var role_type: RoleType = RoleType.TRADE_HUB
@export var produces: Dictionary = {}
@export var consumes: Dictionary = {}
# Name of the preset this slot came from, and its housing (a per-slot override may change it).
@export var preset: String = ""
@export var housing: float = 0.0

# Builds a slot from a galaxy-document preset (names as keys) plus per-slot overrides.
static func from_preset(preset_name: String, preset_data: Dictionary, overrides: Dictionary) -> EconomyRole:
	var role := EconomyRole.new()
	role.preset = preset_name
	var kind: String = preset_data["kind"]
	var kind_index := RoleType.keys().find(kind)
	assert(kind_index >= 0, "EconomyRole: unknown role kind '%s'" % kind)
	role.role_type = RoleType.values()[kind_index]
	role.produces = _commodity_map(overrides.get("produces", preset_data.get("produces", {})))
	role.consumes = _commodity_map(overrides.get("consumes", preset_data.get("consumes", {})))
	role.housing = float(overrides.get("housing", preset_data.get("housing", HOUSING[role.role_type])))
	return role

static func _commodity_map(named: Dictionary) -> Dictionary:
	var out := {}
	for key in named:
		var index := Commodity.Type.keys().find(key)
		assert(index >= 0, "EconomyRole: unknown commodity '%s'" % key)
		out[Commodity.Type.values()[index]] = float(named[key])
	return out

static func _make(type: RoleType, preset_name: String) -> EconomyRole:
	var role := EconomyRole.new()
	role.role_type = type
	role.preset = preset_name
	role.housing = HOUSING[type]
	return role

static func mining() -> EconomyRole:
	var role := _make(RoleType.MINING, "mining")
	role.produces = {Commodity.Type.ORE: 5.0}
	return role

static func agriculture() -> EconomyRole:
	var role := _make(RoleType.AGRICULTURE, "agriculture")
	role.produces = {Commodity.Type.FOOD: 5.0}
	return role

static func housing_for(role_type: RoleType) -> float:
	return HOUSING[role_type]

static func industrial() -> EconomyRole:
	var role := _make(RoleType.INDUSTRIAL, "industrial")
	role.consumes = {Commodity.Type.ORE: 3.0, Commodity.Type.FUEL: 2.0}
	role.produces = {Commodity.Type.WEAPONS: 2.0}
	return role

static func population() -> EconomyRole:
	var role := _make(RoleType.POPULATION, "population")
	role.consumes = {Commodity.Type.FOOD: 4.0}
	return role

static func trade_hub() -> EconomyRole:
	var role := _make(RoleType.TRADE_HUB, "trade_hub")
	return role

static func refinery() -> EconomyRole:
	var role := _make(RoleType.REFINERY, "refinery")
	role.produces = {Commodity.Type.FUEL: 3.0}
	return role
