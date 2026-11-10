class_name FleetCommander
extends Node2D

# Weapon frustums on selected ships: #ffb347 lines and a red hatch, both at 20% opacity.
const FRUSTUM_COLOR := Color(1.0, 0.702, 0.278, 0.2)
const FRUSTUM_LINE_WIDTH := 3.0
const FRUSTUM_DASH := 6.0
const FRUSTUM_HATCH_COLOR := Color(1.0, 0.231, 0.231, 0.06)
const FRUSTUM_HATCH_WIDTH := 1.0
const FRUSTUM_HATCH_SPACING := 20.0
const FRUSTUM_SEGMENTS := 32

# Selection brackets: 4 corner Ls fit around the ship's own hit radius.
const SELECT_COLOR := Color(0.2, 1.0, 0.4)
const SELECT_LINE_WIDTH := 2.0
const SELECT_PADDING := 6.0
const SELECT_ARM_FRACTION := 0.35
const DRAG_BOX_LINE_WIDTH := 2.0

# Order-direction arrows: a faint pulsing chevron chain from ship to its order's destination.
const ARROW_COLOR := Color(0.2, 1.0, 0.4, 0.12)
const ARROW_LINE_WIDTH := 1.5
const ARROW_SPACING := 48.0
const ARROW_SIZE := 14.0
const ARROW_SIZE_PULSE := 0.25  # fraction of ARROW_SIZE added/removed at the pulse's peak
const ARROW_MIN_DISTANCE := 32.0
const ARROW_PULSE_SPEED := 0.7  # cycles per second, travelling from ship to destination
const ARROW_PULSE_PHASE := 0.9  # radians of phase shift between consecutive chevrons

@export var select_radius: float = 24.0
@export var click_target_radius: float = 24.0
@export var drag_threshold: float = 6.0

@export var formation_spacing: float = 120.0
@export var formation_slop: float = 0.15

var ships: Array[Ship] = []
var enemy_group: StringName
# Reassign rather than mutate: the setter is what tells the order bar.
var selected_ships: Array[Ship] = []:
	set(value):
		selected_ships = value
		_last_has_selection = _has_live_selection()
		selection_changed.emit(_last_has_selection)
var active_formation: Formation.Type = Formation.Type.NONE
var armed_command: Order.Type = Order.Type.ATTACK_TARGET

signal formation_changed(type: Formation.Type)
signal selection_changed(has_selection: bool)
signal armed_command_changed(has_command: bool, type: Order.Type)

var _last_has_selection: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _has_armed_command: bool = false

func _ready() -> void:
	# The player must be able to select ships and issue orders while the tree is
	# paused, with execution picking up once they unpause.
	process_mode = Node.PROCESS_MODE_ALWAYS

func setup(p_ships: Array[Ship], p_enemy_group: StringName) -> void:
	ships = p_ships
	enemy_group = p_enemy_group

func order_flee() -> void:
	_order_live_selection(func(): return Order.flee())
	_clear_armed_command()

func order_hold() -> void:
	_order_live_selection(func(): return Order.hold_position())
	_clear_armed_command()

func set_formation(type: Formation.Type) -> void:
	active_formation = type
	formation_changed.emit(type)

# Re-arming the already-armed command un-arms it; arming a different one swaps cleanly.
func set_armed_command(type: Order.Type) -> void:
	if _has_armed_command and armed_command == type:
		_clear_armed_command()
		return
	armed_command = type
	_has_armed_command = true
	armed_command_changed.emit(true, armed_command)

func _clear_armed_command() -> void:
	_has_armed_command = false
	armed_command_changed.emit(false, armed_command)

func _process(_delta: float) -> void:
	# A selected ship can jump out mid-battle; the bar must notice without a new selection.
	if _has_live_selection() != _last_has_selection:
		selected_ships = selected_ships
	if not selected_ships.is_empty() or _dragging:
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("formation_none"):
		set_formation(Formation.Type.NONE)
	elif event.is_action_pressed("formation_line"):
		set_formation(Formation.Type.LINE)
	elif event.is_action_pressed("formation_wedge"):
		set_formation(Formation.Type.WEDGE)
	elif event.is_action_pressed("formation_box"):
		set_formation(Formation.Type.BOX)
	elif event.is_action_pressed("formation_circle"):
		set_formation(Formation.Type.CIRCLE)
	elif event.is_action_pressed("order_hold"):
		order_hold()
	elif event.is_action_pressed("order_flee"):
		order_flee()
	elif event.is_action_pressed("order_attack"):
		set_armed_command(Order.Type.ATTACK_TARGET)
	elif event.is_action_pressed("order_protect"):
		set_armed_command(Order.Type.PROTECT)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _dragging:
		queue_redraw()

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_start = world_pos
			_dragging = true
		else:
			_dragging = false
			_on_left_release(_drag_start, world_pos)
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_on_right_press()

# Untyped: a freed ship fails an Object-typed parameter check.
func _is_live(ship) -> bool:
	return is_instance_valid(ship) and not ship.is_queued_for_deletion() and not ship.has_fled

func _has_live_selection() -> bool:
	for ship in selected_ships:
		if _is_live(ship):
			return true
	return false

func _prune_selection() -> void:
	selected_ships = selected_ships.filter(_is_live)

# A fresh Order per ship: orders hold per-ship state.
func _order_live_selection(make_order: Callable) -> void:
	_prune_selection()
	for ship in selected_ships:
		ship.execute_order(make_order.call())

# Armed Attack/Protect are one-shot: whatever this click resolves to (a hit on the armed
# command's own target type, or a plain move if the click didn't land on one), the command
# disarms afterward so the button un-presses and the next right-click goes back to smart.
func _issue_armed_command(world_pos: Vector2) -> void:
	_prune_selection()
	if selected_ships.is_empty():
		return
	var issued := false
	match armed_command:
		Order.Type.ATTACK_TARGET:
			var enemy_candidates: Array = get_tree().get_nodes_in_group(enemy_group)
			var target_enemy := FleetCommander.ship_at_point(enemy_candidates, world_pos, click_target_radius)
			if target_enemy != null:
				for ship in selected_ships:
					ship.execute_order(Order.attack_target(target_enemy))
				issued = true
		Order.Type.PROTECT:
			var protectee := FleetCommander.ship_at_point(ships, world_pos, click_target_radius)
			if protectee != null:
				for ship in selected_ships:
					if ship != protectee:
						ship.execute_order(Order.protect(protectee))
				issued = true
	if not issued:
		_move_selection_to(world_pos)
	_clear_armed_command()

# The right-click default with nothing armed: attack if the click lands on an enemy,
# otherwise move the selection there. Never arms the Attack button -- that only reflects
# an explicit arm via the button or hotkey.
func _issue_smart_order(world_pos: Vector2) -> void:
	_prune_selection()
	if selected_ships.is_empty():
		return
	var enemy_candidates: Array = get_tree().get_nodes_in_group(enemy_group)
	var target_enemy := FleetCommander.ship_at_point(enemy_candidates, world_pos, click_target_radius)
	if target_enemy != null:
		for ship in selected_ships:
			ship.execute_order(Order.attack_target(target_enemy))
		return
	_move_selection_to(world_pos)

func _move_selection_to(world_pos: Vector2) -> void:
	var destinations := _compute_destinations(world_pos)
	for ship in selected_ships:
		if destinations.has(ship):
			ship.execute_order(Order.move_to(destinations[ship]))

# Left click only selects: a drag box-selects, a click on an own ship selects only it, and
# any other click (empty space, or on an enemy) deselects. Orders come from right-click.
func _on_left_release(start: Vector2, end: Vector2) -> void:
	if start.distance_to(end) >= drag_threshold:
		# An empty box keeps the current selection rather than dropping it.
		var boxed := FleetCommander.ships_in_rect(ships, Rect2(start, Vector2.ZERO).expand(end))
		if not boxed.is_empty():
			selected_ships = boxed
	else:
		var picked := FleetCommander.ship_at_point(ships, end, select_radius)
		var picked_ships: Array[Ship] = []
		if picked != null:
			picked_ships.append(picked)
		selected_ships = picked_ships
	queue_redraw()

# Right click is the smart action: with nothing armed, it attacks an enemy under the
# cursor or moves the selection there; with Attack or Protect armed, that command's own
# resolution takes over instead (falling back to a move, and disarming, if the click
# doesn't land on a valid target). The selection stays after issuing an order -- only a
# left click on empty space clears it.
func _on_right_press() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	if _has_armed_command:
		_issue_armed_command(world_pos)
	else:
		_issue_smart_order(world_pos)
	queue_redraw()

func _compute_destinations(world_pos: Vector2) -> Dictionary:
	if active_formation == Formation.Type.NONE:
		var centroid := _group_centroid()
		var destinations: Dictionary = {}
		for ship in selected_ships:
			destinations[ship] = world_pos + (ship.global_position - centroid)
		return destinations
	var facing := _group_facing(world_pos)
	var slots := Formation.compute_slots(active_formation, selected_ships.size(), world_pos, facing, formation_spacing, formation_slop)
	return FleetCommander.assign_slots(selected_ships, slots)

func _group_centroid() -> Vector2:
	var sum := Vector2.ZERO
	for ship in selected_ships:
		sum += ship.global_position
	return sum / selected_ships.size()

func _group_facing(world_pos: Vector2) -> Vector2:
	var delta := world_pos - _group_centroid()
	return delta.normalized() if delta.length() > 0.01 else Vector2.RIGHT

func _draw() -> void:
	var zoom_scale := _camera_zoom_scale()
	for ship in selected_ships:
		if is_instance_valid(ship) and not ship.has_fled:
			_draw_frustums(ship, zoom_scale)
			_draw_selection_bracket(ship, zoom_scale)
			_draw_order_arrows(ship, zoom_scale)
	if _dragging:
		var rect := Rect2(_drag_start, Vector2.ZERO).expand(get_global_mouse_position())
		draw_rect(rect, Color(0.2, 1.0, 0.4, 0.3), false, DRAG_BOX_LINE_WIDTH / zoom_scale)

# Line widths are drawn in world space, so they thin out to nothing as the camera zooms
# out; dividing by zoom keeps every overlay stroke a constant width on screen.
func _camera_zoom_scale() -> float:
	var camera := get_viewport().get_camera_2d()
	return camera.zoom.x if camera != null else 1.0

# Mirrors WeaponMount.can_engage: the arc is centred on the mount's facing.
func _draw_frustums(ship: Ship, zoom_scale: float) -> void:
	for mount in FleetCommander.frustum_mounts(ship.weapon_mounts):
		var origin := mount.global_position
		var facing := mount.global_rotation
		var arc := mount.weapon.fire_arc_degrees
		var reach := mount.weapon.weapon_range
		var polygon := FleetCommander.frustum_polygon(origin, facing, arc, reach, FRUSTUM_SEGMENTS)
		var hatch := FleetCommander.hatch_segments(polygon, FRUSTUM_HATCH_SPACING)
		if not hatch.is_empty():
			draw_multiline(hatch, FRUSTUM_HATCH_COLOR, FRUSTUM_HATCH_WIDTH / zoom_scale)
		var line_width := FRUSTUM_LINE_WIDTH / zoom_scale
		if arc >= 360.0:
			draw_arc(origin, reach, 0.0, TAU, FRUSTUM_SEGMENTS * 2, FRUSTUM_COLOR, line_width)
			continue
		var half := deg_to_rad(arc) * 0.5
		draw_dashed_line(origin, polygon[1], FRUSTUM_COLOR, line_width, FRUSTUM_DASH / zoom_scale)
		draw_dashed_line(origin, polygon[polygon.size() - 1], FRUSTUM_COLOR, line_width, FRUSTUM_DASH / zoom_scale)
		draw_arc(origin, reach, facing - half, facing + half, FRUSTUM_SEGMENTS, FRUSTUM_COLOR, line_width)

# 4 L-shaped corner brackets sized to the ship's own hit radius, so bigger hulls get
# bigger brackets instead of everyone sharing one fixed circle.
func _draw_selection_bracket(ship: Ship, zoom_scale: float) -> void:
	var half := ship.get_hit_radius() + SELECT_PADDING
	var arm := half * SELECT_ARM_FRACTION
	var segments := FleetCommander.bracket_segments(ship.global_position, half, arm)
	draw_multiline(segments, SELECT_COLOR, SELECT_LINE_WIDTH / zoom_scale)

# A faint pulsing chevron chain from the ship to its current order's destination (a move
# point, or an attack/protect target's live position). The pulse travels from the ship-end
# chevron to the destination-end one, looping, so the direction reads at a glance.
func _draw_order_arrows(ship: Ship, zoom_scale: float) -> void:
	var dest: Variant = FleetCommander.order_destination(ship.current_order)
	if dest == null:
		return
	var from: Vector2 = ship.global_position
	var to: Vector2 = dest
	var delta := to - from
	var distance := delta.length()
	if distance < ARROW_MIN_DISTANCE:
		return
	var dir := delta / distance
	var perp := dir.rotated(PI / 2.0)
	var count := maxi(1, floori(distance / ARROW_SPACING))
	var line_width := ARROW_LINE_WIDTH / zoom_scale
	var now := Time.get_ticks_msec() / 1000.0
	for i in count:
		var t := (i + 1.0) / (count + 1.0)
		var pos := from + delta * t
		var phase := now * ARROW_PULSE_SPEED * TAU - i * ARROW_PULSE_PHASE
		var pulse := (sin(phase) + 1.0) * 0.5
		var color := ARROW_COLOR
		color.a *= 0.3 + 0.7 * pulse
		var size := ARROW_SIZE * (1.0 + ARROW_SIZE_PULSE * (pulse * 2.0 - 1.0))
		var tip := pos + dir * size * 0.5
		var base_a := pos - dir * size * 0.5 + perp * size * 0.4
		var base_b := pos - dir * size * 0.5 - perp * size * 0.4
		draw_line(tip, base_a, color, line_width)
		draw_line(tip, base_b, color, line_width)

# The point a ship's current order is steering it toward, or null if the order has no
# destination to point at (hold/flee) or its target is no longer live.
static func order_destination(order: Order) -> Variant:
	if order == null:
		return null
	match order.type:
		Order.Type.MOVE_TO:
			return order.target_position
		Order.Type.ATTACK_TARGET, Order.Type.PROTECT:
			var target := order.target_ship
			if is_instance_valid(target) and not target.is_queued_for_deletion() and not (target is Ship and target.has_fled):
				return target.global_position
			return null
		_:
			return null

# Corner-bracket segments as from/to pairs for draw_multiline: an L at each corner of a
# box of half-size `half` centred on `center`, with arms of length `arm`.
static func bracket_segments(center: Vector2, half: float, arm: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var corner_signs: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for s in corner_signs:
		var corner := center + s * half
		var inward := -s
		points.append(corner)
		points.append(corner + Vector2(inward.x * arm, 0))
		points.append(corner)
		points.append(corner + Vector2(0, inward.y * arm))
	return points

# Mounts whose firing area is worth showing: armed and not destroyed.
static func frustum_mounts(mounts: Array[WeaponMount]) -> Array[WeaponMount]:
	var shown: Array[WeaponMount] = []
	for mount in mounts:
		if mount.weapon != null and not mount.is_destroyed():
			shown.append(mount)
	return shown

# A wedge from origin (origin first, then the arc), or a circle without origin for a
# 360-degree weapon, matching WeaponMount._within_arc.
static func frustum_polygon(origin: Vector2, facing: float, arc_degrees: float, weapon_range: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	if arc_degrees >= 360.0:
		for i in segments:
			points.append(origin + Vector2.RIGHT.rotated(TAU * i / segments) * weapon_range)
		return points
	var half := deg_to_rad(arc_degrees) * 0.5
	points.append(origin)
	for i in segments + 1:
		points.append(origin + Vector2.RIGHT.rotated(facing - half + 2.0 * half * i / segments) * weapon_range)
	return points

# Diagonal hatch clipped to polygon, as from/to pairs for draw_multiline. Lines sit on
# world-fixed offsets so the pattern doesn't crawl as the ship turns.
static func hatch_segments(polygon: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var segments := PackedVector2Array()
	if polygon.size() < 3:
		return segments
	var normal := Vector2(1, 1).normalized()
	var along := Vector2(1, -1).normalized()
	var centre := Vector2.ZERO
	for point in polygon:
		centre += point
	centre /= polygon.size()
	var low := INF
	var high := -INF
	var reach := 0.0
	for point in polygon:
		low = minf(low, point.dot(normal))
		high = maxf(high, point.dot(normal))
		reach = maxf(reach, point.distance_to(centre))
	var centre_along := along * centre.dot(along)
	for k in range(ceili(low / spacing), floori(high / spacing) + 1):
		var base := normal * (k * spacing) + centre_along
		var line := PackedVector2Array([base - along * reach, base + along * reach])
		for piece in Geometry2D.intersect_polyline_with_polygon(line, polygon):
			for j in piece.size() - 1:
				segments.append(piece[j])
				segments.append(piece[j + 1])
	return segments

static func ship_at_point(candidates: Array, point: Vector2, radius: float) -> Ship:
	var best: Ship = null
	var best_dist := radius
	for c in candidates:
		if is_instance_valid(c) and c is Ship and c.player_targetable and not c.has_fled:
			var d: float = c.global_position.distance_to(point)
			if d <= best_dist:
				best_dist = d
				best = c
	return best

static func ships_in_rect(candidates: Array[Ship], rect: Rect2) -> Array[Ship]:
	var result: Array[Ship] = []
	for c in candidates:
		if is_instance_valid(c) and not c.has_fled and rect.has_point(c.global_position):
			result.append(c)
	return result

static func assign_slots(ships_to_assign: Array[Ship], slots: Array[Vector2]) -> Dictionary:
	var assignment: Dictionary = {}
	var remaining_ships := ships_to_assign.duplicate()
	var remaining_slots := slots.duplicate()
	while remaining_ships.size() > 0 and remaining_slots.size() > 0:
		var best_ship: Ship = null
		var best_slot_index := -1
		var best_dist := INF
		for ship in remaining_ships:
			for i in remaining_slots.size():
				var d: float = ship.global_position.distance_to(remaining_slots[i])
				if d < best_dist:
					best_dist = d
					best_ship = ship
					best_slot_index = i
		assignment[best_ship] = remaining_slots[best_slot_index]
		remaining_ships.erase(best_ship)
		remaining_slots.remove_at(best_slot_index)
	return assignment
