class_name JumpMapPanel
extends Control

signal jump_requested(system_id: String)
signal distress_requested
signal closed

const MAP_INSET := 24.0
const SELECT_RADIUS := 14.0
const NODE_RADIUS := 6.0
const HERE_RING_RADIUS := 10.0
const SELECTED_RING_RADIUS := 14.0
const RING_WIDTH := 2.0
const LINK_WIDTH := 1.5
const NAME_FONT_SIZE := 12
const NAME_OFFSET := Vector2(-60.0, 26.0)
const NAME_WIDTH := 120.0
# Holo palette: cobalt accent for links and "you are here".
const ACCENT_COLOR := Color("#3f9fff")
const LINK_COLOR := Color(0.247, 0.624, 1.0, 0.45)
const NAME_COLOR := Color("#9fd0ff")
const UNKNOWN_COLOR := Color(0.35, 0.37, 0.42, 1.0)
const SELECTED_COLOR := Color.WHITE

# system_id -> MapArea-local point, for every system drawn.
var node_points: Dictionary = {}

# The CampaignState autoload; passed in so the panel can be tested on its own.
var _state: Node = null
var _docked: bool = false
var _hostile_contact: bool = false
var _selected: String = ""

@onready var map_area: Control = $MapArea
@onready var info_label: Label = $Strip/InfoLabel
@onready var reason_label: Label = $Strip/ReasonLabel
@onready var jump_button: Button = $Strip/ButtonRow/JumpButton
@onready var distress_button: Button = $Strip/ButtonRow/DistressButton
@onready var close_button: Button = $Strip/ButtonRow/CloseButton

func _ready() -> void:
	jump_button.pressed.connect(_on_jump_pressed)
	distress_button.pressed.connect(_on_distress_pressed)
	close_button.pressed.connect(_request_close)
	map_area.draw.connect(_draw_map)
	map_area.gui_input.connect(_on_map_gui_input)
	map_area.resized.connect(refresh)
	visible = false

# hostile_contact blocks every jump; docked hides the distress signal.
func open_for(state: Node, docked: bool, hostile_contact: bool) -> void:
	_state = state
	_docked = docked
	_hostile_contact = hostile_contact
	_selected = state.player_fleet.system_id
	visible = true
	refresh()

func close() -> void:
	visible = false
	_state = null

func refresh() -> void:
	if _state == null:
		return
	_rebuild_points()
	_update_strip()
	map_area.queue_redraw()

func select_system(id: String) -> void:
	if _state == null or not node_points.has(id):
		return
	_selected = id
	_update_strip()
	map_area.queue_redraw()

func selected_system() -> String:
	return _selected

# Visited systems take their most common owner's colour from the last visit.
func node_color(id: String) -> Color:
	if not _state.visited.has(id):
		return UNKNOWN_COLOR
	var seen: Dictionary = _state.last_seen.get(id, {})
	var neutral: Color = CampaignFleetIcon.FACTION_COLORS[CampaignFleet.Faction.NEUTRAL]
	return CampaignFleetIcon.FACTION_COLORS.get(_dominant_owner(seen.get("owners", [])), neutral)

# Distinct owners in station order, e.g. "Player/Neutral".
func owner_text(owners: Array) -> String:
	if owners.is_empty():
		return "No stations"
	var names: Array[String] = []
	for owner in owners:
		var owner_name: String = CampaignFleet.Faction.keys()[owner].capitalize()
		if not names.has(owner_name):
			names.append(owner_name)
	return "/".join(names)

# -1 when there are no owners; ties go to the owner listed first.
static func _dominant_owner(owners: Array) -> int:
	var counts := {}
	var best := -1
	var best_count := 0
	for owner in owners:
		counts[owner] = counts.get(owner, 0) + 1
		if counts[owner] > best_count:
			best = owner
			best_count = counts[owner]
	return best

func _rebuild_points() -> void:
	node_points.clear()
	var inset := Vector2(MAP_INSET, MAP_INSET)
	var span := map_area.size - inset * 2.0
	for id in _state.discovered:
		var sys: StarSystem = _state.galaxy.system(id)
		if sys != null:
			node_points[id] = inset + sys.map_position * span

func _update_strip() -> void:
	var fleet: CampaignFleet = _state.player_fleet
	var cost_line := "Jump cost: %.1f fuel (you have %.1f)" % [JumpRules.jump_cost(fleet), fleet.fuel_amount()]
	info_label.text = _system_line(_selected) + "\n" + cost_line
	var reason: String = "You are here" if _selected == fleet.system_id else _state.jump_block_reason(_selected, _hostile_contact)
	jump_button.disabled = reason != ""
	var distress_reason := _update_distress()
	if distress_reason != "":
		reason = "%s. Distress unavailable: %s" % [reason, distress_reason] if reason != "" else "Distress unavailable: " + distress_reason
	reason_label.text = reason

func _system_line(id: String) -> String:
	if not _state.visited.has(id):
		return "Unknown system"
	var seen: Dictionary = _state.last_seen.get(id, {})
	var count: int = seen.get("stations", 0)
	var stations := "1 station" if count == 1 else "%d stations" % count
	var line := "%s - %s - %s - Danger %d" % [_state.galaxy.system(id).display_name, owner_text(seen.get("owners", [])), stations, seen.get("tier", 0)]
	if seen.get("pirates_seen", false):
		line += ", pirates seen"
	return line

# Shown only when no connected jump is affordable. Jump cost depends on the fleet, not the
# destination, so one check covers every link; that also keeps "Fuel not needed" off-screen.
# Returns the reason the shown signal can't be sent, or "".
func _update_distress() -> String:
	var fleet: CampaignFleet = _state.player_fleet
	distress_button.visible = not _docked and not JumpRules.can_afford(fleet)
	if not distress_button.visible:
		return ""
	var quote := JumpRules.distress_quote(fleet, _state.credits)
	distress_button.text = "Distress signal (%d cr for %.1f fuel)" % [quote["price"], quote["fuel"]]
	distress_button.disabled = not quote["ok"]
	return "" if quote["ok"] else quote["reason"]

func _on_jump_pressed() -> void:
	if not jump_button.disabled:
		jump_requested.emit(_selected)

func _on_distress_pressed() -> void:
	if not distress_button.disabled:
		distress_requested.emit()

func _request_close() -> void:
	close()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("open_jump_map"):
		get_viewport().set_input_as_handled()
		_request_close()

func _on_map_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var nearest := ""
	var nearest_dist := SELECT_RADIUS
	for id in node_points:
		var dist: float = event.position.distance_to(node_points[id])
		if dist <= nearest_dist:
			nearest = id
			nearest_dist = dist
	if nearest != "":
		select_system(nearest)

func _draw_map() -> void:
	if _state == null:
		return
	for id in node_points:
		for other in _state.galaxy.system(id).links:
			# Each link once, and only between two systems on the map.
			if id < other and node_points.has(other):
				map_area.draw_line(node_points[id], node_points[other], LINK_COLOR, LINK_WIDTH, true)
	var font := get_theme_default_font()
	for id in node_points:
		var point: Vector2 = node_points[id]
		var known: bool = _state.visited.has(id)
		map_area.draw_circle(point, NODE_RADIUS, node_color(id))
		if id == _state.player_fleet.system_id:
			map_area.draw_arc(point, HERE_RING_RADIUS, 0.0, TAU, 32, ACCENT_COLOR, RING_WIDTH, true)
		if id == _selected:
			map_area.draw_arc(point, SELECTED_RING_RADIUS, 0.0, TAU, 32, SELECTED_COLOR, RING_WIDTH, true)
		var name_color := NAME_COLOR if known else UNKNOWN_COLOR
		map_area.draw_string(font, point + NAME_OFFSET, _state.galaxy.system(id).display_name, HORIZONTAL_ALIGNMENT_CENTER, NAME_WIDTH, NAME_FONT_SIZE, name_color)
