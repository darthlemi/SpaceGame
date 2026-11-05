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

static func mining() -> EconomyRole:
	var role := EconomyRole.new()
	role.role_type = RoleType.MINING
	role.produces = {Commodity.Type.ORE: 5.0}
	return role

static func agriculture() -> EconomyRole:
	var role := EconomyRole.new()
	role.role_type = RoleType.AGRICULTURE
	role.produces = {Commodity.Type.FOOD: 5.0}
	return role

static func housing_for(role_type: RoleType) -> float:
	return HOUSING[role_type]

static func industrial() -> EconomyRole:
	var role := EconomyRole.new()
	role.role_type = RoleType.INDUSTRIAL
	role.consumes = {Commodity.Type.ORE: 3.0, Commodity.Type.FUEL: 2.0}
	role.produces = {Commodity.Type.WEAPONS: 2.0}
	return role

static func population() -> EconomyRole:
	var role := EconomyRole.new()
	role.role_type = RoleType.POPULATION
	role.consumes = {Commodity.Type.FOOD: 4.0}
	return role

static func trade_hub() -> EconomyRole:
	var role := EconomyRole.new()
	role.role_type = RoleType.TRADE_HUB
	return role

static func refinery() -> EconomyRole:
	var role := EconomyRole.new()
	role.role_type = RoleType.REFINERY
	role.produces = {Commodity.Type.FUEL: 3.0}
	return role
