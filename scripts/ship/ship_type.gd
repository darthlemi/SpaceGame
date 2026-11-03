class_name ShipType
extends RefCounted

enum Kind { CORVETTE, FREIGHTER, CAPITAL }

enum SlotType { WEAPON, SHIELD, ENGINE }

const SCENES := {
	Kind.CORVETTE: "res://scenes/ship/ship_corvette.tscn",
	Kind.FREIGHTER: "res://scenes/ship/ship_freighter.tscn",
	Kind.CAPITAL: "res://scenes/ship/ship_capital.tscn",
}

# fuel_burn: Fuel units consumed per CampaignFleet.FUEL_BURN_DISTANCE map units travelled.
const BASE_STATS := {
	Kind.CORVETTE: {"max_hp": 60.0, "max_shield": 20.0, "cargo_capacity": 20.0, "engine_hp": 25.0, "weapon_mount_hp": 15.0, "weapon_mount_count": 1, "crew": 12, "fuel_burn": 1.0},
	Kind.FREIGHTER: {"max_hp": 80.0, "max_shield": 20.0, "cargo_capacity": 60.0, "engine_hp": 35.0, "weapon_mount_hp": 0.0, "weapon_mount_count": 0, "crew": 6, "fuel_burn": 1.5},
	Kind.CAPITAL: {"max_hp": 220.0, "max_shield": 80.0, "cargo_capacity": 20.0, "engine_hp": 70.0, "weapon_mount_hp": 30.0, "weapon_mount_count": 3, "crew": 40, "fuel_burn": 3.0},
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

const LOADOUT_POINTS := {
	Kind.CORVETTE: 20,
	Kind.FREIGHTER: 15,
	Kind.CAPITAL: 40,
}

static func points_budget_for(kind: Kind) -> int:
	return LOADOUT_POINTS[kind]

static func equipped_path(comp: Dictionary, slot_type: SlotType, slot_index: int) -> String:
	match slot_type:
		SlotType.WEAPON:
			var items: Array = comp.get("weapon_mount_items", [])
			return items[slot_index] if slot_index < items.size() else ""
		SlotType.SHIELD:
			return comp.get("shield_item", "")
		SlotType.ENGINE:
			return comp.get("engine_item", "")
	return ""

static func set_equipped_path(comp: Dictionary, slot_type: SlotType, slot_index: int, path: String) -> void:
	match slot_type:
		SlotType.WEAPON:
			var items: Array = comp.get("weapon_mount_items", [])
			# Resize array to ensure it's large enough for the assignment
			while items.size() <= slot_index:
				items.append("")
			items[slot_index] = path
			comp["weapon_mount_items"] = items
		SlotType.SHIELD:
			comp["shield_item"] = path
		SlotType.ENGINE:
			comp["engine_item"] = path

static func points_of_path(path: String) -> int:
	if path == "":
		return 0
	var item: Resource = load(path)
	return PartRarity.points_for(item.rarity)

static func points_used(comp: Dictionary) -> int:
	var total := 0
	for path in comp.get("weapon_mount_items", []):
		total += points_of_path(path)
	total += points_of_path(comp.get("shield_item", ""))
	total += points_of_path(comp.get("engine_item", ""))
	return total

static func scene_for(kind: Kind) -> PackedScene:
	return load(SCENES[kind])

static func kind_of(comp: Dictionary) -> Kind:
	return comp.get("ship_type", Kind.CORVETTE)

static func cargo_capacity_for(kind: Kind) -> float:
	return BASE_STATS[kind]["cargo_capacity"]

static func crew_for(kind: Kind) -> int:
	return BASE_STATS[kind]["crew"]

static func fuel_burn_for(kind: Kind) -> float:
	return BASE_STATS[kind]["fuel_burn"]

static func new_composition(kind: Kind) -> Dictionary:
	var stats: Dictionary = BASE_STATS[kind]
	var mount_hp: Array[float] = []
	var mount_items: Array[String] = []
	for i in int(stats["weapon_mount_count"]):
		mount_hp.append(stats["weapon_mount_hp"])
		mount_items.append("")
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
		"weapon_mount_items": mount_items,
		"shield_item": "",
		"engine_item": "",
	}
