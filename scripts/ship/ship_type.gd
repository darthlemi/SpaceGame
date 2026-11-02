class_name ShipType
extends RefCounted

enum Kind { CORVETTE, FREIGHTER, CAPITAL }

const SCENES := {
	Kind.CORVETTE: "res://scenes/ship/ship_corvette.tscn",
	Kind.FREIGHTER: "res://scenes/ship/ship_freighter.tscn",
	Kind.CAPITAL: "res://scenes/ship/ship_capital.tscn",
}

const BASE_STATS := {
	Kind.CORVETTE: {"max_hp": 60.0, "max_shield": 20.0, "cargo_capacity": 20.0, "engine_hp": 25.0, "weapon_mount_hp": 15.0, "weapon_mount_count": 1},
	Kind.FREIGHTER: {"max_hp": 80.0, "max_shield": 20.0, "cargo_capacity": 60.0, "engine_hp": 35.0, "weapon_mount_hp": 0.0, "weapon_mount_count": 0},
	Kind.CAPITAL: {"max_hp": 220.0, "max_shield": 80.0, "cargo_capacity": 20.0, "engine_hp": 70.0, "weapon_mount_hp": 30.0, "weapon_mount_count": 3},
}

const WEAPON_POOL: Array[String] = [
	"res://resources/weapons/kinetic_cannon.tres",
	"res://resources/weapons/mass_driver.tres",
	"res://resources/weapons/flak_cannon.tres",
	"res://resources/weapons/railgun.tres",
	"res://resources/weapons/seeker_missile.tres",
	"res://resources/weapons/swarm_missile.tres",
	"res://resources/weapons/torpedo.tres",
	"res://resources/weapons/emp_missile.tres",
	"res://resources/weapons/pulse_laser.tres",
	"res://resources/weapons/heavy_beam.tres",
	"res://resources/weapons/disruptor_beam.tres",
	"res://resources/weapons/lance_graser.tres",
	"res://resources/weapons/pd_flak_turret.tres",
	"res://resources/weapons/pd_laser_turret.tres",
]

static func scene_for(kind: Kind) -> PackedScene:
	return load(SCENES[kind])

static func kind_of(comp: Dictionary) -> Kind:
	return comp.get("ship_type", Kind.CORVETTE)

static func cargo_capacity_for(kind: Kind) -> float:
	return BASE_STATS[kind]["cargo_capacity"]

static func new_composition(kind: Kind) -> Dictionary:
	var stats: Dictionary = BASE_STATS[kind]
	var mount_hp: Array[float] = []
	for i in int(stats["weapon_mount_count"]):
		mount_hp.append(stats["weapon_mount_hp"])
	return {
		"ship_type": kind,
		"max_hp": stats["max_hp"],
		"current_hp": stats["max_hp"],
		"max_shield": stats["max_shield"],
		"current_shield": stats["max_shield"],
		"engine_max_hp": stats["engine_hp"],
		"engine_current_hp": stats["engine_hp"],
		"weapon_mount_max_hp": mount_hp,
		"weapon_mount_current_hp": mount_hp.duplicate(),
	}
