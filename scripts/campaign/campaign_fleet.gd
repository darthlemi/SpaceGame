class_name CampaignFleet
extends Resource

enum Faction { PLAYER, NEUTRAL, TRADER, PIRATE }

@export var fleet_id: String = ""
@export var faction: Faction = Faction.NEUTRAL
@export var ship_compositions: Array[Dictionary] = []
@export var position: Vector2 = Vector2.ZERO
@export var heading: Vector2 = Vector2.RIGHT
@export var speed: float = 80.0

func total_strength() -> float:
	var sum := 0.0
	for comp in ship_compositions:
		sum += comp["current_hp"] + comp["current_shield"]
	return sum

func is_destroyed() -> bool:
	for comp in ship_compositions:
		if comp["current_hp"] > 0.0:
			return false
	return true

func repair_to_full() -> void:
	for comp in ship_compositions:
		comp["current_hp"] = comp["max_hp"]
		comp["current_shield"] = comp["max_shield"]
