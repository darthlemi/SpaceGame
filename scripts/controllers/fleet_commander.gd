class_name FleetCommander
extends Node2D

const SELECT_RADIUS := 24.0
const CLICK_TARGET_RADIUS := 40.0
const DRAG_THRESHOLD := 6.0

@export var formation_spacing: float = 60.0
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
			if _drag_start.distance_to(world_pos) < DRAG_THRESHOLD:
				var picked := FleetCommander.ship_at_point(ships, world_pos, SELECT_RADIUS)
				selected_ships = [picked] if picked != null else []
			else:
				var rect := Rect2(_drag_start, Vector2.ZERO).expand(world_pos)
				selected_ships = FleetCommander.ships_in_rect(ships, rect)
			queue_redraw()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_issue_order(world_pos)

func _issue_order(world_pos: Vector2) -> void:
	if selected_ships.is_empty():
		return
	var enemy_candidates: Array = get_tree().get_nodes_in_group(enemy_group)
	var target_enemy := FleetCommander.ship_at_point(enemy_candidates, world_pos, CLICK_TARGET_RADIUS)
	if target_enemy != null:
		for ship in selected_ships:
			ship.execute_order(Order.attack_target(target_enemy))
		return
	var destinations := _compute_destinations(world_pos)
	for ship in selected_ships:
		if destinations.has(ship):
			ship.execute_order(Order.move_to(destinations[ship]))

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
			draw_arc(ship.global_position, SELECT_RADIUS, 0, TAU, 24, Color(0.2, 1.0, 0.4), 2.0)
	if _dragging:
		var rect := Rect2(_drag_start, Vector2.ZERO).expand(get_global_mouse_position())
		draw_rect(rect, Color(0.2, 1.0, 0.4, 0.3), false, 2.0)

static func ship_at_point(candidates: Array, point: Vector2, radius: float) -> Ship:
	var best: Ship = null
	var best_dist := radius
	for c in candidates:
		if c is Ship and is_instance_valid(c):
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
