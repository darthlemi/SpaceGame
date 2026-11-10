class_name SystemLayer
extends Node2D

const CampaignStationScene = preload("res://scenes/campaign/campaign_station.tscn")

var system_id: String = ""

# Hidden layers stay processing so the rest of the galaxy keeps living; the offset keeps
# their Area2Ds from ever overlapping the current system's.
func set_current(is_current: bool, offset: Vector2) -> void:
	visible = is_current
	position = Vector2.ZERO if is_current else offset

func add_station(data: StationData) -> CampaignStation:
	var node: CampaignStation = CampaignStationScene.instantiate()
	node.setup(data)
	add_child(node)
	return node

# Layers at or before this draw before stations; later ones draw in front, matching the real
# asset names (deep_background, mid_distance draw behind; foreground draws in front).
const BEHIND_STATION_LAYERS := ["deep_background", "mid_distance"]

# The editor's SceneryCanvas plans scenery in a 3200x3200 "world" space and outlines the
# actually-visible 1152x648 campaign viewport centered in it (see scenery_canvas.gd). At
# runtime SystemLayer sits at the scene origin with no camera, so a scenery item's world
# position must be shifted back by that same centering offset to land where the editor
# showed it would be visible.
const SCENERY_SPACE := Vector2(3200.0, 3200.0)
const SCENERY_VIEWPORT := Vector2(1152.0, 648.0)

func add_scenery(item: Dictionary) -> Sprite2D:
	var folder: String = SceneryFolder.type_to_folder(item.get("type", ""))
	var path := "res://assets/sprites/backgrounds/%s/%s" % [folder, item.get("texture", "")]
	var sprite := Sprite2D.new()
	if folder != "" and ResourceLoader.exists(path):
		sprite.texture = load(path)
	var world_pos := Vector2(item["pos"][0], item["pos"][1])
	sprite.position = world_pos - (SCENERY_SPACE - SCENERY_VIEWPORT) / 2.0
	sprite.scale = Vector2.ONE * float(item.get("scale", 1.0))
	if BEHIND_STATION_LAYERS.has(item.get("layer", "")):
		add_child(sprite)
		move_child(sprite, 0)
	else:
		add_child(sprite)
	return sprite
