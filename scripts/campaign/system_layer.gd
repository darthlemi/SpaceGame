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

const FOLDER_BY_TYPE := {"planet": "planets", "asteroid": "asteroids"}
# Layers at or before this draw before stations; later ones draw in front, matching the real
# asset names (deep_background, mid_distance draw behind; foreground draws in front).
const BEHIND_STATION_LAYERS := ["deep_background", "mid_distance"]

func add_scenery(item: Dictionary) -> Sprite2D:
	var folder: String = FOLDER_BY_TYPE.get(item.get("type", ""), "")
	var path := "res://assets/sprites/backgrounds/%s/%s" % [folder, item.get("texture", "")]
	var sprite := Sprite2D.new()
	if folder != "" and ResourceLoader.exists(path):
		sprite.texture = load(path)
	sprite.position = Vector2(item["pos"][0], item["pos"][1])
	sprite.scale = Vector2.ONE * float(item.get("scale", 1.0))
	if BEHIND_STATION_LAYERS.has(item.get("layer", "")):
		add_child(sprite)
		move_child(sprite, 0)
	else:
		add_child(sprite)
	return sprite
