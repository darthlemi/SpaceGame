class_name CombatCamera
extends Camera2D

# Pans and zooms over the combat arena: mouse wheel zooms about the cursor, WASD/arrows
# pan, middle-drag grabs the view. Runs while paused and uses wall-clock time, so the
# player can look around a paused or slowed fight.

const PAN_SPEED := 900.0  # screen px per second, so panning feels the same at any zoom
const ZOOM_STEP := 1.15
const MAX_ZOOM := 1.5
const START_ZOOM := 0.75

@export var arena_size := Vector2(2304, 1296)

var _dragging := false
var _last_usec := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_usec = Time.get_ticks_usec()
	zoom = Vector2.ONE * clampf(START_ZOOM, fit_zoom(_view_size(), arena_size), MAX_ZOOM)
	position = clamp_center(position, _view_size(), zoom.x, arena_size)

# Centre the view on a world point (clamped to the arena).
func focus(point: Vector2) -> void:
	position = clamp_center(point, _view_size(), zoom.x, arena_size)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := (now - _last_usec) / 1_000_000.0
	_last_usec = now
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return  # typing in the debug console must not pan
	var dir := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	if dir != Vector2.ZERO:
		position = clamp_center(position + dir.normalized() * PAN_SPEED * dt / zoom.x,
			_view_size(), zoom.x, arena_size)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					var step := ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
					_zoom_at(event.position, zoom.x * step)
			MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		position = clamp_center(position - event.relative / zoom.x, _view_size(), zoom.x, arena_size)

func _zoom_at(cursor: Vector2, wanted: float) -> void:
	var view := _view_size()
	var new_zoom := clampf(wanted, fit_zoom(view, arena_size), MAX_ZOOM)
	var centre := zoom_about(position, view, cursor, zoom.x, new_zoom)
	zoom = Vector2.ONE * new_zoom
	position = clamp_center(centre, view, new_zoom, arena_size)

func _view_size() -> Vector2:
	return get_viewport_rect().size

# Smallest zoom that still shows nothing outside the arena.
static func fit_zoom(view: Vector2, arena: Vector2) -> float:
	return maxf(view.x / arena.x, view.y / arena.y)

# Keep the visible rect inside the arena; centre an axis the view is wider than.
static func clamp_center(centre: Vector2, view: Vector2, zoom_level: float, arena: Vector2) -> Vector2:
	var half := view / zoom_level / 2.0
	var x := arena.x / 2.0 if half.x * 2.0 >= arena.x else clampf(centre.x, half.x, arena.x - half.x)
	var y := arena.y / 2.0 if half.y * 2.0 >= arena.y else clampf(centre.y, half.y, arena.y - half.y)
	return Vector2(x, y)

# New camera centre that keeps the world point under the cursor fixed across a zoom change.
static func zoom_about(centre: Vector2, view: Vector2, cursor: Vector2, old_zoom: float, new_zoom: float) -> Vector2:
	var offset := cursor - view / 2.0
	var world := centre + offset / old_zoom
	return world - offset / new_zoom
