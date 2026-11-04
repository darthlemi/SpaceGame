class_name StarSystem
extends Resource

@export var id: String = ""
@export var display_name: String = ""
# Normalised 0..1 jump-map coordinates.
@export var map_position: Vector2 = Vector2.ZERO
@export var links: Array[String] = []
@export var tier: int = 1
# Hand-set tier; 0 means derive from jump distance to the start system.
@export var tier_override: int = 0
