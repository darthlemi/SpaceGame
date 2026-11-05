class_name AIController
extends Node

# Share of the battle-start hull that must be lost before an armed ship flees.
const FLEE_LOSS_FRACTION := {ShipType.Kind.CORVETTE: 0.65, ShipType.Kind.CAPITAL: 0.85}
# An unarmed ship flees once an enemy hull edge is this close.
const UNARMED_FLEE_RANGE := 500.0

var ship: Ship
var enemy_group: StringName
var start_hp: float = 0.0
var _target: Node2D = null
var _retarget_timer: float = 0.0
var _fleeing: bool = false

# Must run after the fleet data is applied: the hull then is the battle-start hull.
func setup(p_ship: Ship, p_enemy_group: StringName) -> void:
	ship = p_ship
	enemy_group = p_enemy_group
	start_hp = ship.hull.current_hp

func _physics_process(delta: float) -> void:
	if not is_instance_valid(ship) or _fleeing:
		return
	_retarget_timer -= delta
	var candidates: Array = get_tree().get_nodes_in_group(enemy_group)
	# A target freed this frame stays valid until the queue flushes, so check both.
	var target_gone := not Ship._is_live_target(_target)
	if _retarget_timer <= 0.0 or target_gone:
		_target = CombatTactics.pick_target(ship, candidates, _target)
		_retarget_timer = CombatTactics.RETARGET_INTERVAL
	var armed := ship.engagement_distance(_target if _target != null else ship) >= 0.0
	if AIController.should_flee(ship.ship_type, start_hp, ship.hull.current_hp, armed, _nearest_enemy_edge(candidates)):
		_fleeing = true
		ship.execute_order(Order.flee())
		return
	if _target != null:
		ship.execute_order(Order.attack_target(_target))

func _nearest_enemy_edge(candidates: Array) -> float:
	var nearest := INF
	for candidate in candidates:
		if is_instance_valid(candidate) and candidate is Node2D:
			nearest = minf(nearest, CombatTactics.edge_distance(ship.global_position, candidate))
	return nearest

# A freighter has no key of its own, so an armed one reads like a corvette.
static func should_flee(kind: ShipType.Kind, start_hp: float, current_hp: float, armed: bool, nearest_enemy_edge: float) -> bool:
	if start_hp <= 0.0:
		return false
	if not armed:
		return nearest_enemy_edge <= UNARMED_FLEE_RANGE
	var loss_fraction: float = FLEE_LOSS_FRACTION.get(kind, FLEE_LOSS_FRACTION[ShipType.Kind.CORVETTE])
	return current_hp <= start_hp * (1.0 - loss_fraction)
