class_name FactionBase
extends Area2D

const DOMINION_TEXTURE := preload("res://assets/sprites/bases/dominion_base.png")
const FREEHOLD_TEXTURE := preload("res://assets/sprites/bases/freehold_base.png")

@export var faction_enum: CampaignFleet.Faction = CampaignFleet.Faction.NEUTRAL


func _ready() -> void:
	var sprite: Sprite2D = get_node("Sprite2D")
	if faction_enum == CampaignFleet.Faction.FREEHOLD:
		sprite.texture = FREEHOLD_TEXTURE
	else:
		sprite.texture = DOMINION_TEXTURE
