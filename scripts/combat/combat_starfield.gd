class_name CombatStarfield
extends ParallaxBackground

@onready var _base_sprite: Sprite2D = $Base/Sprite2D
@onready var _scenery_layer: ParallaxLayer = $Scenery

func setup(system_id: String) -> void:
	_base_sprite.texture = load(StarfieldAssignment.base_texture_path(system_id, StarfieldAssignment.COMBAT_CATEGORIES))
	for placement in CombatScenery.pick(system_id):
		var sprite := Sprite2D.new()
		sprite.texture = load(CombatScenery.texture_path(placement))
		sprite.position = placement.position
		sprite.scale = Vector2.ONE * placement.scale
		_scenery_layer.add_child(sprite)
