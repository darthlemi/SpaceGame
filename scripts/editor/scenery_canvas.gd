class_name SceneryCanvas
extends Control

# Draws a system's background and placed planets/asteroids at the 3200x3200 scale the combat
# arena uses (future-proofed for camera panning, even though nothing scrolls today), with the
# actual 1152x648 campaign viewport outlined so it's clear what's visible in-game right now.

signal scenery_selected(index: int)
signal scenery_moved(index: int, pos: Vector2)

const SPACE := Vector2(3200.0, 3200.0)
const VIEWPORT_SIZE := Vector2(1152.0, 648.0)
const BACKDROP_COLOR := Color(0.02, 0.03, 0.06, 1.0)
const VIEWPORT_OUTLINE_COLOR := Color(0.4, 0.8, 1.0, 0.5)
const PICK_RADIUS := 24.0
const SELECTED_COLOR := Color(0.4, 0.8, 1.0, 1.0)

var selected_index: int = -1
var items: Array = []

var _textures: Array = []
var _background_texture: Texture2D = null
var _drag_index: int = -1

func set_scenery(scenery: Array, background_texture: Texture2D) -> void:
	items = scenery.duplicate(true)
	_background_texture = background_texture
	_textures.clear()
	for item in items:
		var folder: String = SceneryFolder.type_to_folder(item.get("type", ""))
		var path := "res://assets/sprites/backgrounds/%s/%s" % [folder, item.get("texture", "")]
		_textures.append(load(path) if folder != "" and ResourceLoader.exists(path) else null)
	queue_redraw()

func _world_to_canvas(world: Vector2) -> Vector2:
	return world * (size / SPACE)

func _canvas_to_world(point: Vector2) -> Vector2:
	return (point * (SPACE / size)).clamp(Vector2.ZERO, SPACE)

func item_at(point: Vector2) -> int:
	var nearest := -1
	var nearest_dist := PICK_RADIUS
	for i in items.size():
		var world := Vector2(items[i]["pos"][0], items[i]["pos"][1])
		var dist: float = point.distance_to(_world_to_canvas(world))
		if dist <= nearest_dist:
			nearest = i
			nearest_dist = dist
	return nearest

func handle_press(point: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var index := item_at(point)
	selected_index = index
	if index >= 0:
		scenery_selected.emit(index)
		_drag_index = index
	queue_redraw()

func handle_drag(point: Vector2) -> void:
	if _drag_index >= 0:
		scenery_moved.emit(_drag_index, _canvas_to_world(point))

func handle_release() -> void:
	_drag_index = -1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			handle_press(event.position, event.button_index)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			handle_release()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		handle_drag(event.position)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP_COLOR)
	if _background_texture != null:
		draw_texture_rect(_background_texture, Rect2(Vector2.ZERO, size), true)
	var viewport_origin: Vector2 = _world_to_canvas((SPACE - VIEWPORT_SIZE) / 2.0)
	var viewport_size: Vector2 = VIEWPORT_SIZE * (size / SPACE)
	draw_rect(Rect2(viewport_origin, viewport_size), VIEWPORT_OUTLINE_COLOR, false, 2.0)
	for i in items.size():
		var world := Vector2(items[i]["pos"][0], items[i]["pos"][1])
		var point := _world_to_canvas(world)
		var tex: Texture2D = _textures[i]
		if tex != null:
			var scale_factor: float = float(items[i].get("scale", 1.0))
			var draw_size := Vector2(tex.get_width(), tex.get_height()) * scale_factor * (size.x / SPACE.x)
			draw_texture_rect(tex, Rect2(point - draw_size * 0.5, draw_size), false)
		else:
			draw_circle(point, PICK_RADIUS, Color.GRAY)
		if i == selected_index:
			draw_arc(point, PICK_RADIUS + 6.0, 0.0, TAU, 32, SELECTED_COLOR, 2.0, true)
