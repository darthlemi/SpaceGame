class_name EconomyRole
extends Resource

enum RoleType { MINING, AGRICULTURE, INDUSTRIAL, POPULATION, TRADE_HUB }

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
