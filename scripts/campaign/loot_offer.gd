class_name LootOffer
extends RefCounted

# What a defeated fleet leaves for the player to take. Ships keep their current crew;
# the crew pool is what can be transferred to the player's fleet.
var cargo: Dictionary = {}
var parts: Array[String] = []
var ships: Array[Dictionary] = []

func crew_pool() -> int:
	var sum := 0
	for comp in ships:
		sum += CrewRules.crew_of(comp)
	return sum

func is_empty() -> bool:
	for amount in cargo.values():
		if amount > 0.0:
			return false
	return parts.is_empty() and ships.is_empty()
