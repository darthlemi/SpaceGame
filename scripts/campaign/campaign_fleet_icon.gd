class_name CampaignFleetIcon
extends Area2D

const PatrolBehavior = preload("res://scripts/campaign/behaviors/patrol_behavior.gd")
const TraderBehavior = preload("res://scripts/campaign/behaviors/trader_behavior.gd")
const PirateBehavior = preload("res://scripts/campaign/behaviors/pirate_behavior.gd")

enum BehaviorType { PLAYER, PATROL, TRADER, PIRATE }

const SHIP_DOT_RADIUS := 3.0
const SHIP_DOT_SIDES := 8
const CLUMP_RADIUS := 18.0
const DOT_COLOR := Color(0.9, 0.9, 0.3, 1)

@export var behavior_type: BehaviorType = BehaviorType.PATROL
@export var wander_radius: float = 150.0
@export var arrival_radius: float = 10.0
@export var detection_range: float = 200.0
@export var flee_range: float = 150.0
@export var flee_distance: float = 300.0

var fleet: CampaignFleet
var player_target: CampaignFleetIcon
var frozen: bool = false

var _move_target: Vector2
var _spawn_point: Vector2
var _home_position: Vector2
var _route_state: TraderBehavior.RouteState = TraderBehavior.RouteState.TO_BASE

var _ship_dots: Array[Polygon2D] = []
var _ship_dot_offsets: Array[Vector2] = []

signal trader_arrived(at_home: bool)

func setup(campaign_fleet: CampaignFleet, home_pos: Vector2) -> void:
	fleet = campaign_fleet
	global_position = fleet.position
	_spawn_point = fleet.position
	_move_target = fleet.position
	_home_position = home_pos
	_sync_ship_dots()

func set_move_target(target: Vector2) -> void:
	_move_target = target

func set_route_endpoints(home_pos: Vector2, away_pos: Vector2, reset_state: bool = true) -> void:
	_home_position = home_pos
	_spawn_point = away_pos
	if reset_state:
		_route_state = TraderBehavior.RouteState.FROM_BASE

func route_endpoints_match(home_pos: Vector2, away_pos: Vector2) -> bool:
	return _home_position == home_pos and _spawn_point == away_pos

func route_away_point() -> Vector2:
	return _spawn_point

func _physics_process(delta: float) -> void:
	if fleet == null:
		return
	_sync_ship_dots()
	if frozen:
		return
	match behavior_type:
		BehaviorType.PATROL:
			_move_target = PatrolBehavior.next_wander_target(_spawn_point, _move_target, global_position, wander_radius, arrival_radius)
		BehaviorType.TRADER:
			_process_trader()
		BehaviorType.PIRATE:
			_process_pirate()
		BehaviorType.PLAYER:
			pass
	global_position = global_position.move_toward(_move_target, fleet.speed * delta)
	fleet.position = global_position

func _process_trader() -> void:
	if player_target != null and is_instance_valid(player_target) and TraderBehavior.should_flee(global_position, player_target.global_position, flee_range):
		_move_target = TraderBehavior.flee_target(global_position, player_target.global_position, flee_distance)
		return
	var previous_state := _route_state
	_route_state = TraderBehavior.next_route_state(_route_state, global_position, _home_position, _spawn_point, arrival_radius)
	_move_target = TraderBehavior.route_target(_route_state, _home_position, _spawn_point)
	if _route_state != previous_state:
		trader_arrived.emit(_route_state == TraderBehavior.RouteState.FROM_BASE)

func _process_pirate() -> void:
	if player_target != null and is_instance_valid(player_target) and player_target.fleet != null and PirateBehavior.in_detection_range(global_position, player_target.global_position, detection_range):
		if PirateBehavior.should_intercept(fleet.total_strength(), player_target.fleet.total_strength()):
			_move_target = player_target.global_position
			return
	_move_target = PatrolBehavior.next_wander_target(_spawn_point, _move_target, global_position, wander_radius, arrival_radius)

func _sync_ship_dots() -> void:
	var target: int = fleet.ship_compositions.size()
	while _ship_dots.size() < target:
		var index := _ship_dots.size()
		if index >= _ship_dot_offsets.size():
			var angle := randf_range(0.0, TAU)
			var distance := randf_range(0.0, CLUMP_RADIUS)
			_ship_dot_offsets.append(Vector2.RIGHT.rotated(angle) * distance)
		var dot := Polygon2D.new()
		dot.polygon = _circle_polygon(SHIP_DOT_RADIUS, SHIP_DOT_SIDES)
		dot.color = DOT_COLOR
		dot.position = _ship_dot_offsets[index]
		add_child(dot)
		_ship_dots.append(dot)
	while _ship_dots.size() > target:
		var dot: Polygon2D = _ship_dots.pop_back()
		dot.queue_free()

func _circle_polygon(radius: float, sides: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in sides:
		var angle := TAU * i / sides
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
