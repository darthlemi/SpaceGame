class_name CampaignFleetIcon
extends Area2D

const PatrolBehavior = preload("res://scripts/campaign/behaviors/patrol_behavior.gd")
const TraderBehavior = preload("res://scripts/campaign/behaviors/trader_behavior.gd")
const PirateBehavior = preload("res://scripts/campaign/behaviors/pirate_behavior.gd")

enum BehaviorType { PLAYER, PATROL, TRADER, PIRATE }

const CLUMP_RADIUS := 18.0
const SHIP_ICON_MAX_DIM := 10.0
const SHIP_ICON_TEXTURES := {
	ShipType.Kind.CORVETTE: "res://assets/sprites/ships/corvette.png",
	ShipType.Kind.FREIGHTER: "res://assets/sprites/ships/freighter.png",
	ShipType.Kind.CAPITAL: "res://assets/sprites/ships/capital.png",
}
const HEADING_EPSILON := 0.5
const ENGINE_TRAIL_COLOR := Color(0.3, 0.7, 1.0, 0.8)
const ENGINE_TRAIL_AMOUNT := 10
const ENGINE_TRAIL_LIFETIME := 0.4
const ENGINE_TRAIL_SPREAD := 10.0
const ENGINE_TRAIL_VELOCITY_MIN := 20.0
const ENGINE_TRAIL_VELOCITY_MAX := 40.0
const ENGINE_TRAIL_SCALE_MIN := 1.5
const ENGINE_TRAIL_SCALE_MAX := 2.5

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

var _ship_dots: Array[Sprite2D] = []
var _ship_dot_offsets: Array[Vector2] = []
var _heading_angle: float = 0.0
var _engine_trail: CPUParticles2D

signal trader_arrived(at_home: bool)

func setup(campaign_fleet: CampaignFleet, home_pos: Vector2) -> void:
	fleet = campaign_fleet
	global_position = fleet.position
	_spawn_point = fleet.position
	_move_target = fleet.position
	_home_position = home_pos
	_ensure_engine_trail()
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
		_engine_trail.emitting = false
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
	var previous_position := global_position
	global_position = global_position.move_toward(_move_target, fleet.speed * delta)
	fleet.position = global_position
	var movement := global_position - previous_position
	if movement.length() > HEADING_EPSILON:
		_heading_angle = movement.angle()
	for dot in _ship_dots:
		dot.rotation = _heading_angle
	_engine_trail.rotation = _heading_angle
	_engine_trail.emitting = movement.length() > HEADING_EPSILON

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

func _ensure_engine_trail() -> void:
	if _engine_trail != null:
		return
	_engine_trail = CPUParticles2D.new()
	_engine_trail.emitting = false
	_engine_trail.amount = ENGINE_TRAIL_AMOUNT
	_engine_trail.lifetime = ENGINE_TRAIL_LIFETIME
	_engine_trail.direction = Vector2(-1, 0)
	_engine_trail.spread = ENGINE_TRAIL_SPREAD
	_engine_trail.gravity = Vector2.ZERO
	_engine_trail.initial_velocity_min = ENGINE_TRAIL_VELOCITY_MIN
	_engine_trail.initial_velocity_max = ENGINE_TRAIL_VELOCITY_MAX
	_engine_trail.scale_amount_min = ENGINE_TRAIL_SCALE_MIN
	_engine_trail.scale_amount_max = ENGINE_TRAIL_SCALE_MAX
	_engine_trail.color = ENGINE_TRAIL_COLOR
	add_child(_engine_trail)

func _sync_ship_dots() -> void:
	var target: int = fleet.ship_compositions.size()
	while _ship_dots.size() < target:
		var index := _ship_dots.size()
		if index >= _ship_dot_offsets.size():
			var angle := randf_range(0.0, TAU)
			var distance := randf_range(0.0, CLUMP_RADIUS)
			_ship_dot_offsets.append(Vector2.RIGHT.rotated(angle) * distance)
		var dot := Sprite2D.new()
		dot.texture = _ship_icon_texture(fleet.ship_compositions[index])
		var longest_dim: float = max(dot.texture.get_width(), dot.texture.get_height())
		dot.scale = Vector2.ONE * (SHIP_ICON_MAX_DIM / longest_dim)
		dot.position = _ship_dot_offsets[index]
		dot.rotation = _heading_angle
		add_child(dot)
		_ship_dots.append(dot)
	while _ship_dots.size() > target:
		var dot: Sprite2D = _ship_dots.pop_back()
		dot.queue_free()

func _ship_icon_texture(comp: Dictionary) -> Texture2D:
	var kind: ShipType.Kind = ShipType.kind_of(comp)
	return load(SHIP_ICON_TEXTURES[kind])
