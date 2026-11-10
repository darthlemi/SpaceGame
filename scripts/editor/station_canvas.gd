class_name StationCanvas
extends Control

# Draws every station in one system as its real sprite at its real `pos`, 1:1 with the station
# `pos` field's own coordinate space (JumpRules.SYSTEM_MIN..MAX), and turns mouse input into
# signals; the editor applies them to the model. Mirrors MapCanvas's shape.

signal station_selected(id: String)
signal station_moved(id: String, pos: Vector2)

const BACKDROP_COLOR := Color(0.02, 0.03, 0.06, 1.0)
const ICON_RADIUS := 36.0
const SELECTED_RING_RADIUS := 44.0
const SELECTED_COLOR := Color(0.4, 0.8, 1.0, 1.0)

var selected: String = ""
# station id -> Vector2 in the document's own pos space.
var station_points: Dictionary = {}

var _doc: Dictionary = {}
var _system_id: String = ""
var _textures: Dictionary = {}
var _drag_id: String = ""

func set_system(doc: Dictionary, system_id: String) -> void:
	_doc = doc
	_system_id = system_id
	refresh()

func refresh() -> void:
	station_points.clear()
	_textures.clear()
	for st in _doc.get("stations", []):
		if st.get("system", "") != _system_id:
			continue
		var id := MapEditModel.station_id_of(st)
		var pos: Array = st.get("pos", [580.0, 350.0])
		station_points[id] = Vector2(pos[0], pos[1])
		var path := "res://assets/sprites/stations/%s.png" % str(st.get("art", "ring_2"))
		if ResourceLoader.exists(path):
			_textures[id] = load(path)
	queue_redraw()

func station_at(point: Vector2) -> String:
	var nearest := ""
	var nearest_dist := ICON_RADIUS
	for id in station_points:
		var dist: float = point.distance_to(station_points[id])
		if dist <= nearest_dist:
			nearest = id
			nearest_dist = dist
	return nearest

func handle_press(point: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	var id := station_at(point)
	if id != "":
		selected = id
		station_selected.emit(id)
		_drag_id = id
	queue_redraw()

func handle_drag(point: Vector2) -> void:
	if _drag_id != "":
		station_moved.emit(_drag_id, point)

func handle_release() -> void:
	_drag_id = ""

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
	for id in station_points:
		var point: Vector2 = station_points[id]
		if _textures.has(id):
			var tex: Texture2D = _textures[id]
			var longest: float = max(tex.get_width(), tex.get_height())
			var icon_scale: float = (ICON_RADIUS * 2.0) / longest
			var draw_size := Vector2(tex.get_width(), tex.get_height()) * icon_scale
			draw_texture_rect(tex, Rect2(point - draw_size * 0.5, draw_size), false)
		else:
			draw_circle(point, ICON_RADIUS, Color.GRAY)
		if id == selected:
			draw_arc(point, SELECTED_RING_RADIUS, 0.0, TAU, 32, SELECTED_COLOR, 2.0, true)
