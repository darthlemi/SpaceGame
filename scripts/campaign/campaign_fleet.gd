class_name CampaignFleet
extends Resource

enum Faction { PLAYER, NEUTRAL, TRADER, PIRATE, DOMINION, FREEHOLD }
enum Role { COMBAT, TRADER }

# Out of fuel the fleet still crawls, so the player can always limp to a base.
const EMPTY_FUEL_SPEED_FACTOR := 0.25
const FUEL_BURN_DISTANCE := 1000.0

@export var fleet_id: String = ""
@export var role: Role = Role.COMBAT
@export var faction: Faction = Faction.NEUTRAL
@export var ship_compositions: Array[Dictionary] = []
@export var position: Vector2 = Vector2.ZERO
@export var heading: Vector2 = Vector2.RIGHT
@export var speed: float = 80.0

@export var cargo: Dictionary = {}
@export var part_inventory: Array[String] = []

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

func apply_fractional_damage(fraction: float) -> void:
	for comp in ship_compositions:
		comp["current_hp"] = max(0.0, comp["current_hp"] * (1.0 - fraction))
		comp["current_shield"] = max(0.0, comp["current_shield"] * (1.0 - fraction))

func cargo_capacity() -> float:
	var sum := 0.0
	for comp in ship_compositions:
		sum += ShipType.cargo_capacity_for(ShipType.kind_of(comp))
	return sum

func cargo_total() -> float:
	var sum := 0.0
	for amount in cargo.values():
		sum += amount
	sum += part_inventory.size()
	return sum

func consume_fuel(distance: float) -> void:
	var held := fuel_amount()
	if held <= 0.0 or distance <= 0.0:
		return
	cargo[Commodity.Type.FUEL] = max(0.0, held - fuel_burn_per_distance() * distance)

func crew_total() -> int:
	var sum := 0
	for comp in ship_compositions:
		sum += ShipType.crew_for(ShipType.kind_of(comp))
	return sum

func fuel_amount() -> float:
	return cargo.get(Commodity.Type.FUEL, 0.0)

func fuel_burn_per_distance() -> float:
	var sum := 0.0
	for comp in ship_compositions:
		sum += ShipType.fuel_burn_for(ShipType.kind_of(comp))
	return sum / FUEL_BURN_DISTANCE

# Fuel per second at full cruise speed (what the player burns while moving).
func fuel_burn_rate() -> float:
	return fuel_burn_per_distance() * speed

func travel_speed() -> float:
	return speed if fuel_amount() > 0.0 else speed * EMPTY_FUEL_SPEED_FACTOR
