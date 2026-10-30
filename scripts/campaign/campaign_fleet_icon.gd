class_name CampaignFleetIcon
extends Area2D

const PatrolBehavior = preload("res://scripts/campaign/behaviors/patrol_behavior.gd")
const TraderBehavior = preload("res://scripts/campaign/behaviors/trader_behavior.gd")
const PirateBehavior = preload("res://scripts/campaign/behaviors/pirate_behavior.gd")

enum BehaviorType { PLAYER, PATROL, TRADER, PIRATE }

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

func setup(campaign_fleet: CampaignFleet, home_pos: Vector2) -> void:
	fleet = campaign_fleet
	global_position = fleet.position
	_spawn_point = fleet.position
	_move_target = fleet.position
	_home_position = home_pos

func set_move_target(target: Vector2) -> void:
	_move_target = target

func _physics_process(delta: float) -> void:
	if fleet == null or frozen:
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
	_route_state = TraderBehavior.next_route_state(_route_state, global_position, _home_position, _spawn_point, arrival_radius)
	_move_target = TraderBehavior.route_target(_route_state, _home_position, _spawn_point)

func _process_pirate() -> void:
	if player_target != null and is_instance_valid(player_target) and player_target.fleet != null and PirateBehavior.in_detection_range(global_position, player_target.global_position, detection_range):
		if PirateBehavior.should_intercept(fleet.total_strength(), player_target.fleet.total_strength()):
			_move_target = player_target.global_position
			return
	_move_target = PatrolBehavior.next_wander_target(_spawn_point, _move_target, global_position, wander_radius, arrival_radius)
