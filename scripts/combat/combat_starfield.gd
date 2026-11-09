class_name CombatStarfield
extends ParallaxBackground

@onready var _base_sprite: Sprite2D = $Base/Sprite2D

func setup(system_id: String) -> void:
	_base_sprite.texture = load(StarfieldAssignment.base_texture_path(system_id, StarfieldAssignment.COMBAT_CATEGORIES))
