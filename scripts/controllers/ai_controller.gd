class_name AIController
extends Node

enum State { APPROACH, ENGAGE, RETREAT }

@export var retreat_hp_ratio: float = 0.25

var state: State = State.APPROACH
var ship: Ship
var enemy: Ship

func setup(p_ship: Ship, p_enemy: Ship) -> void:
	ship = p_ship
	enemy = p_enemy

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(ship) or not is_instance_valid(enemy):
		return
	var hp_ratio: float = ship.hull.current_hp / ship.hull.max_hp if ship.hull.max_hp > 0.0 else 0.0
	var in_range: bool = ship.global_position.distance_to(enemy.global_position) <= ship.attack_range()
	state = AIController.next_state(state, hp_ratio, retreat_hp_ratio, in_range)
	match state:
		State.APPROACH, State.ENGAGE:
			ship.execute_order(Order.attack_target(enemy))
		State.RETREAT:
			ship.execute_order(Order.retreat(enemy.global_position))

static func next_state(state: State, hp_ratio: float, retreat_hp_ratio: float, in_attack_range: bool) -> State:
	if hp_ratio <= retreat_hp_ratio:
		return State.RETREAT
	if state == State.RETREAT and hp_ratio > retreat_hp_ratio + 0.1:
		return State.APPROACH
	if state == State.APPROACH and in_attack_range:
		return State.ENGAGE
	if state == State.ENGAGE and not in_attack_range:
		return State.APPROACH
	return state
