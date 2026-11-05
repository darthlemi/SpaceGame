class_name MapCanvas
extends Control

# Draws the galaxy document's systems and links like the in-game jump map and turns mouse input
# into signals; the editor applies them to the model.

signal system_selected(id: String)
signal system_moved(id: String, map: Vector2)
signal link_requested(a: String, b: String)
signal link_delete_requested(a: String, b: String)
signal add_requested(map: Vector2)

enum Mode { MOVE, LINK, ADD }

const LINK_PICK_DISTANCE := 6.0
const BACKDROP_COLOR := Color(0.02, 0.03, 0.06, 1.0)
const FLAG_RING_RADIUS := 10.0
const FLAG_COLORS := {"block": Color(0.95, 0.25, 0.25, 1.0), "warn": Color(0.95, 0.8, 0.2, 1.0)}

var mode: int = Mode.MOVE
var selected: String = ""
# system id -> "block" | "warn", shown as a ring around the node.
var flags: Dictionary = {}
# system id -> canvas-local point, for every system drawn.
var node_points: Dictionary = {}

var _doc: Dictionary = {}
var _colors: Dictionary = {}
var _drag_id: String = ""
var _link_from: String = ""

func _ready() -> void:
	resized.connect(refresh)

func set_document(doc: Dictionary) -> void:
	_doc = doc
	refresh()

func refresh() -> void:
	node_points.clear()
	_colors.clear()
	var inset := Vector2(JumpMapPanel.MAP_INSET, JumpMapPanel.MAP_INSET)
	var span := size - inset * 2.0
	var owners := {}
	for st in _doc.get("stations", []):
		var index := CampaignFleet.Faction.keys().find(st.get("owner", ""))
		if index >= 0:
			owners[st.get("system", "")] = owners.get(st.get("system", ""), []) + [CampaignFleet.Faction.values()[index]]
	for sys in _doc.get("systems", []):
		var map: Array = sys.get("map", [0.5, 0.5])
		node_points[sys["id"]] = inset + Vector2(map[0], map[1]) * span
		# Reuses the jump map's tie-break so a system looks the same in both places.
		var dominant: int = JumpMapPanel._dominant_owner(owners.get(sys["id"], []))
		_colors[sys["id"]] = CampaignFleetIcon.FACTION_COLORS.get(dominant, JumpMapPanel.UNKNOWN_COLOR)
	queue_redraw()

func system_at(point: Vector2) -> String:
	var nearest := ""
	var nearest_dist := JumpMapPanel.SELECT_RADIUS
	for id in node_points:
		var dist: float = point.distance_to(node_points[id])
		if dist <= nearest_dist:
			nearest = id
			nearest_dist = dist
	return nearest

# The linked pair [a, b] whose line passes within LINK_PICK_DISTANCE of the point, else [].
func link_at(point: Vector2) -> Array:
	for pair in _doc.get("links", []):
		if not node_points.has(pair[0]) or not node_points.has(pair[1]):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(point, node_points[pair[0]], node_points[pair[1]])
		if point.distance_to(closest) <= LINK_PICK_DISTANCE:
			return [pair[0], pair[1]]
	return []

func map_at(point: Vector2) -> Vector2:
	var inset := Vector2(JumpMapPanel.MAP_INSET, JumpMapPanel.MAP_INSET)
	var span := (size - inset * 2.0).max(Vector2.ONE)
	return ((point - inset) / span).clamp(Vector2.ZERO, Vector2.ONE)

# Input handlers are public so tests can drive them without synthesising events.
func handle_press(point: Vector2, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		var pair := link_at(point)
		if not pair.is_empty():
			link_delete_requested.emit(pair[0], pair[1])
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	var id := system_at(point)
	match mode:
		Mode.MOVE:
			if id != "":
				_select(id)
				_drag_id = id
		Mode.LINK:
			_press_link_mode(id)
		Mode.ADD:
			if id == "":
				add_requested.emit(map_at(point))
			else:
				_select(id)
	queue_redraw()

func handle_drag(point: Vector2) -> void:
	if _drag_id != "":
		system_moved.emit(_drag_id, map_at(point))

func handle_release() -> void:
	_drag_id = ""

func set_mode(new_mode: int) -> void:
	mode = new_mode
	_link_from = ""
	_drag_id = ""
	queue_redraw()

func _press_link_mode(id: String) -> void:
	if id == "":
		_link_from = ""
	elif _link_from == "":
		_link_from = id
		_select(id)
	elif id == _link_from:
		_link_from = ""
	else:
		var from := _link_from
		_link_from = ""
		link_requested.emit(from, id)

func _select(id: String) -> void:
	selected = id
	system_selected.emit(id)

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
	for pair in _doc.get("links", []):
		if node_points.has(pair[0]) and node_points.has(pair[1]):
			draw_line(node_points[pair[0]], node_points[pair[1]], JumpMapPanel.LINK_COLOR, JumpMapPanel.LINK_WIDTH, true)
	var font := get_theme_default_font()
	for sys in _doc.get("systems", []):
		var id: String = sys["id"]
		if not node_points.has(id):
			continue
		var point: Vector2 = node_points[id]
		draw_circle(point, JumpMapPanel.NODE_RADIUS, _colors.get(id, JumpMapPanel.UNKNOWN_COLOR))
		if flags.has(id):
			draw_arc(point, FLAG_RING_RADIUS, 0.0, TAU, 32, FLAG_COLORS[flags[id]], JumpMapPanel.RING_WIDTH, true)
		if id == _link_from:
			draw_arc(point, JumpMapPanel.HERE_RING_RADIUS, 0.0, TAU, 32, JumpMapPanel.ACCENT_COLOR, JumpMapPanel.RING_WIDTH, true)
		if id == selected:
			draw_arc(point, JumpMapPanel.SELECTED_RING_RADIUS, 0.0, TAU, 32, JumpMapPanel.SELECTED_COLOR, JumpMapPanel.RING_WIDTH, true)
		draw_string(font, point + JumpMapPanel.NAME_OFFSET, str(sys.get("name", id)), HORIZONTAL_ALIGNMENT_CENTER,
				JumpMapPanel.NAME_WIDTH, JumpMapPanel.NAME_FONT_SIZE, JumpMapPanel.NAME_COLOR)
