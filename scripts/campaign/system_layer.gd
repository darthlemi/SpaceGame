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
