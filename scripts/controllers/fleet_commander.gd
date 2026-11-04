class_name FleetCommander
extends Node2D

# Weapon frustums on selected ships: #ffb347 lines and a red hatch, both at 20% opacity.
const FRUSTUM_COLOR := Color(1.0, 0.702, 0.278, 0.2)
const FRUSTUM_DASH := 6.0
const FRUSTUM_HATCH_COLOR := Color(1.0, 0.231, 0.231, 0.06)
const FRUSTUM_HATCH_SPACING := 20.0
const FRUSTUM_SEGMENTS := 32

@export var select_radius: float = 24.0
@export var click_target_radius: float = 24.0
@export var drag_threshold: float = 6.0

@export var formation_spacing: float = 120.0
@export var formation_slop: float = 0.15

var ships: Array[Ship] = []
var enemy_group: StringName
var selected_ships: Array[Ship] = []
var active_formation: Formation.Type = Formation.Type.NONE

var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false

func setup(p_ships: Array[Ship], p_enemy_group: StringName) -> void:
	ships = p_ships
	enemy_group = p_enemy_group

func _process(_delta: float) -> void:
	if not selected_ships.is_empty() or _dragging:
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("formation_none"):
		active_formation = Formation.Type.NONE
	elif event.is_action_pressed("formation_line"):
		active_formation = Formation.Type.LINE
	elif event.is_action_pressed("formation_wedge"):
		active_formation = Formation.Type.WEDGE
	elif event.is_action_pressed("formation_box"):
		active_formation = Formation.Type.BOX
	elif event.is_action_pressed("formation_circle"):
		active_formation = Formation.Type.CIRCLE
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

func _issue_order(world_pos: Vector2) -> void:
	selected_ships = selected_ships.filter(func(s): return is_instance_valid(s) and not s.is_queued_for_deletion())
	if selected_ships.is_empty():
		return
	var enemy_candidates: Array = get_tree().get_nodes_in_group(enemy_group)
	var target_enemy := FleetCommander.ship_at_point(enemy_candidates, world_pos, click_target_radius)
	if target_enemy != null:
		for ship in selected_ships:
			ship.execute_order(Order.attack_target(target_enemy))
		return
	var destinations := _compute_destinations(world_pos)
	for ship in selected_ships:
		if destinations.has(ship):
			ship.execute_order(Order.move_to(destinations[ship]))

# Left click mirrors the overworld's click-to-move: a drag box-selects, a click on an
# own ship selects it, and any other click orders the selection there.
func _on_left_release(start: Vector2, end: Vector2) -> void:
	if start.distance_to(end) >= drag_threshold:
		# An empty box keeps the current selection rather than dropping it.
		var boxed := FleetCommander.ships_in_rect(ships, Rect2(start, Vector2.ZERO).expand(end))
		if not boxed.is_empty():
			selected_ships = boxed
	else:
		var picked := FleetCommander.ship_at_point(ships, end, select_radius)
		if picked != null:
			var picked_ships: Array[Ship] = [picked]
			selected_ships = picked_ships
		else:
			_issue_order(end)
	queue_redraw()

func _on_right_press() -> void:
	var none: Array[Ship] = []
	selected_ships = none
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
	for ship in selected_ships:
		if is_instance_valid(ship):
			_draw_frustums(ship)
			draw_arc(ship.global_position, select_radius, 0, TAU, 24, Color(0.2, 1.0, 0.4), 2.0)
	if _dragging:
		var rect := Rect2(_drag_start, Vector2.ZERO).expand(get_global_mouse_position())
		draw_rect(rect, Color(0.2, 1.0, 0.4, 0.3), false, 2.0)

# Mirrors WeaponMount.can_engage: the arc is centred on the mount's facing.
func _draw_frustums(ship: Ship) -> void:
	for mount in FleetCommander.frustum_mounts(ship.weapon_mounts):
		var origin := mount.global_position
		var facing := mount.global_rotation
		var arc := mount.weapon.fire_arc_degrees
		var reach := mount.weapon.weapon_range
		var polygon := FleetCommander.frustum_polygon(origin, facing, arc, reach, FRUSTUM_SEGMENTS)
		var hatch := FleetCommander.hatch_segments(polygon, FRUSTUM_HATCH_SPACING)
		if not hatch.is_empty():
			draw_multiline(hatch, FRUSTUM_HATCH_COLOR, 1.0)
		if arc >= 360.0:
			draw_arc(origin, reach, 0.0, TAU, FRUSTUM_SEGMENTS * 2, FRUSTUM_COLOR, 3.0)
			continue
		var half := deg_to_rad(arc) * 0.5
		draw_dashed_line(origin, polygon[1], FRUSTUM_COLOR, 2.0, FRUSTUM_DASH)
		draw_dashed_line(origin, polygon[polygon.size() - 1], FRUSTUM_COLOR, 2.0, FRUSTUM_DASH)
		draw_arc(origin, reach, facing - half, facing + half, FRUSTUM_SEGMENTS, FRUSTUM_COLOR, 3.0)

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
		if is_instance_valid(c) and c is Ship and c.player_targetable:
			var d: float = c.global_position.distance_to(point)
			if d <= best_dist:
				best_dist = d
				best = c
	return best

static func ships_in_rect(candidates: Array[Ship], rect: Rect2) -> Array[Ship]:
	var result: Array[Ship] = []
	for c in candidates:
		if is_instance_valid(c) and rect.has_point(c.global_position):
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
