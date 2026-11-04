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

@export var system_id: String = ""
var home_station_id: String = ""
var warp_remaining: float = 0.0
var warp_target: String = ""
var jump_path: Array[String] = []
var dest_station_id: String = ""
var jump_cooldown: float = 0.0

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

func is_warping() -> bool:
	return warp_remaining > 0.0

func max_strength() -> float:
	var sum := 0.0
	for comp in ship_compositions:
		sum += comp["max_hp"] + comp["max_shield"]
	return sum

func start_warp(target: String) -> void:
	warp_target = target
	warp_remaining = JumpRules.WARP_DURATION

func repair_to_full() -> void:
	for comp in ship_compositions:
		comp["current_hp"] = comp["max_hp"]
		comp["current_shield"] = comp["max_shield"]

func apply_fractional_damage(fraction: float) -> void:
	for comp in ship_compositions:
		comp["current_hp"] = max(0.0, comp["current_hp"] * (1.0 - fraction))
		comp["current_shield"] = max(0.0, comp["current_shield"] * (1.0 - fraction))

func cancel_warp() -> void:
	warp_remaining = 0.0
	warp_target = ""

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

func crew_capacity() -> int:
	var sum := 0
	for comp in ship_compositions:
		sum += CrewRules.complement(comp)
	return sum

func crew_total() -> int:
	var sum := 0
	for comp in ship_compositions:
		sum += CrewRules.crew_of(comp)
	return sum

# Flags the largest class when none is flagged; ties go to the lowest index.
func ensure_flagship() -> void:
	if ship_compositions.is_empty() or flagship_index() != -1:
		return
	var best := 0
	for i in ship_compositions.size():
		if CrewRules.class_size_rank(ship_compositions[i]) > CrewRules.class_size_rank(ship_compositions[best]):
			best = i
	set_flagship(best)

func flagship_index() -> int:
	for i in ship_compositions.size():
		if CrewRules.is_flagship(ship_compositions[i]):
			return i
	return -1

func has_uncrewed_ship() -> bool:
	for comp in ship_compositions:
		if CrewRules.crew_of(comp) <= 0:
			return true
	return false

func set_flagship(index: int) -> void:
	for i in ship_compositions.size():
		ship_compositions[i]["flagship"] = (i == index)

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
	# An uncrewed ship crawls the whole fleet, same as no fuel; the two don't stack.
	if fuel_amount() <= 0.0 or has_uncrewed_ship():
		return speed * EMPTY_FUEL_SPEED_FACTOR
	return speed
