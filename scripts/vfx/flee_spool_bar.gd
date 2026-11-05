class_name FleeSpoolBar
extends Node2D

const BAR_COLOR := Color(1.0, 0.702, 0.278)
const BAR_GAP := 10.0
const BAR_HEIGHT := 4.0

var _ship: Ship

func setup(ship: Ship) -> void:
	_ship = ship
	# Detached from the ship's transform so the bar stays level whatever the heading.
	top_level = true
	visible = false

func _process(_delta: float) -> void:
	var fleeing := _ship.current_order != null and _ship.current_order.type == Order.Type.FLEE
	visible = fleeing
	if not fleeing:
		return
	global_rotation = 0.0
	global_position = _ship.global_position + Vector2(0.0, _ship.hit_radius + BAR_GAP)
	queue_redraw()

func _draw() -> void:
	if _ship == null:
		return
	var width := 2.0 * _ship.hit_radius
	var origin := Vector2(-_ship.hit_radius, 0.0)
	draw_rect(Rect2(origin, Vector2(width * _ship.flee_progress(), BAR_HEIGHT)), BAR_COLOR, true)
	draw_rect(Rect2(origin, Vector2(width, BAR_HEIGHT)), BAR_COLOR, false)
