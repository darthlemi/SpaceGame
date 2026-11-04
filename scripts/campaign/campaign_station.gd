class_name CampaignStation
extends Area2D

const STATION_ICON_SIZE := 72.0
const RING_PADDING := 6.0
const RING_WIDTH := 2.0

var station: StationData

func setup(data: StationData) -> void:
	station = data
	position = data.position
	var sprite: Sprite2D = $Sprite2D
	sprite.texture = load(data.texture_path())
	var longest: float = max(sprite.texture.get_width(), sprite.texture.get_height())
	sprite.scale = Vector2.ONE * (STATION_ICON_SIZE / longest)
	queue_redraw()

func _draw() -> void:
	if station == null:
		return
	var color: Color = CampaignFleetIcon.FACTION_COLORS.get(station.owner, CampaignFleetIcon.FACTION_COLORS[CampaignFleet.Faction.NEUTRAL])
	draw_arc(Vector2.ZERO, STATION_ICON_SIZE * 0.5 + RING_PADDING, 0.0, TAU, 48, color, RING_WIDTH)
