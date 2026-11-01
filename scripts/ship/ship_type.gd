class_name ShipType
extends RefCounted

enum Kind { CORVETTE, FREIGHTER, CAPITAL }

const SCENES := {
	Kind.CORVETTE: "res://scenes/ship/ship_corvette.tscn",
	Kind.FREIGHTER: "res://scenes/ship/ship_freighter.tscn",
	Kind.CAPITAL: "res://scenes/ship/ship_capital.tscn",
}

const BASE_STATS := {
	Kind.CORVETTE: {"max_hp": 60.0, "max_shield": 20.0, "cargo_capacity": 20.0},
	Kind.FREIGHTER: {"max_hp": 80.0, "max_shield": 20.0, "cargo_capacity": 60.0},
	Kind.CAPITAL: {"max_hp": 220.0, "max_shield": 80.0, "cargo_capacity": 20.0},
}

static func scene_for(kind: Kind) -> PackedScene:
	return load(SCENES[kind])

static func kind_of(comp: Dictionary) -> Kind:
	return comp.get("ship_type", Kind.CORVETTE)

static func cargo_capacity_for(kind: Kind) -> float:
	return BASE_STATS[kind]["cargo_capacity"]

static func new_composition(kind: Kind) -> Dictionary:
	var stats: Dictionary = BASE_STATS[kind]
	return {
		"ship_type": kind,
		"max_hp": stats["max_hp"],
		"current_hp": stats["max_hp"],
		"max_shield": stats["max_shield"],
		"current_shield": stats["max_shield"],
	}
