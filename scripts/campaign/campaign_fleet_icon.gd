class_name CampaignFleetIcon
extends Area2D

const PatrolBehavior = preload("res://scripts/campaign/behaviors/patrol_behavior.gd")
const TraderBehavior = preload("res://scripts/campaign/behaviors/trader_behavior.gd")
const PirateBehavior = preload("res://scripts/campaign/behaviors/pirate_behavior.gd")

enum BehaviorType { PLAYER, PATROL, TRADER, PIRATE }

const CLUMP_RADIUS := 36.0
const SHIP_ICON_MAX_DIM := 20.0
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
const FACTION_CIRCLE_PADDING := 12.0
const FACTION_CIRCLE_WIDTH := 2.0
const SHIP_OFFSET_SPACING := 14.0
const SHIP_OFFSET_GOLDEN_ANGLE := 2.39996
const FACTION_COLORS := {
	CampaignFleet.Faction.PLAYER: Color(0.2, 0.9, 0.2, 1.0),
	CampaignFleet.Faction.PIRATE: Color(0.9, 0.2, 0.2, 1.0),
	CampaignFleet.Faction.DOMINION: Color(0.95, 0.55, 0.1, 1.0),
	CampaignFleet.Faction.FREEHOLD: Color(0.2, 0.85, 0.85, 1.0),
	CampaignFleet.Faction.TRADER: Color(0.6, 0.6, 0.6, 1.0),
	CampaignFleet.Faction.NEUTRAL: Color(0.6, 0.6, 0.6, 1.0),
}

@export var behavior_type: BehaviorType = BehaviorType.PATROL
@export var wander_radius: float = 150.0
@export var arrival_radius: float = 10.0
@export var detection_range: float = 200.0
@export var flee_range: float = 150.0
@export var flee_distance: float = 300.0

var fleet: CampaignFleet
var player_target: CampaignFleetIcon
var frozen: bool = false
# Positions are local to the icon's SystemLayer. The scene keeps dest_position in step with
# fleet.dest_station_id; has_destination is false while that station is out of this system.
var dest_position: Vector2
var has_destination: bool = false

var _move_target: Vector2
var _spawn_point: Vector2

var _ship_dots: Array[Sprite2D] = []
var _ship_dot_offsets: Array[Vector2] = []
var _ship_trails: Array[CPUParticles2D] = []
var _heading_angle: float = 0.0
var _faction_circle_radius: float = 0.0

signal trader_arrived_at(station_id: String)

func _ready() -> void:
	# CampaignScene itself runs with PROCESS_MODE_ALWAYS (so its pause-aware
	# input handling keeps working while the tree is paused), which would
	# otherwise cascade down to every fleet icon via PROCESS_MODE_INHERIT and
	# make them immune to pause too. Pin icons back to the normal pausable
	# behavior explicitly.
	process_mode = Node.PROCESS_MODE_PAUSABLE

# spawn_point is the centre patrols and pirates wander around.
func setup(campaign_fleet: CampaignFleet, spawn_point: Vector2) -> void:
	fleet = campaign_fleet
	position = fleet.position
	_spawn_point = spawn_point
	_move_target = fleet.position
	_sync_ship_dots()

func set_move_target(target: Vector2) -> void:
	_move_target = target

func _physics_process(delta: float) -> void:
	if fleet == null:
		return
	_sync_ship_dots()
	if frozen:
		for trail in _ship_trails:
			trail.emitting = false
		return
	match behavior_type:
		BehaviorType.PATROL:
			_move_target = PatrolBehavior.next_wander_target(_spawn_point, _move_target, position, wander_radius, arrival_radius)
		BehaviorType.TRADER:
			_process_trader()
		BehaviorType.PIRATE:
			_process_pirate()
		BehaviorType.PLAYER:
			pass
	_move_target = JumpRules.clamp_to_system(_move_target)
	# Only the player runs on fuel; NPC fleets carry none and would crawl forever.
	var is_player := behavior_type == BehaviorType.PLAYER
	var step_speed := fleet.travel_speed() if is_player else fleet.speed
	var previous_position := position
	position = position.move_toward(_move_target, step_speed * delta)
	fleet.position = position
	var movement := position - previous_position
	if is_player:
		fleet.consume_fuel(movement.length())
	if movement.length() > HEADING_EPSILON:
		_heading_angle = movement.angle()
	var trails_on := movement.length() > HEADING_EPSILON and is_visible_in_tree()
	for i in _ship_dots.size():
		_ship_dots[i].rotation = _heading_angle
		_ship_trails[i].position = _ship_dot_offsets[i]
		_ship_trails[i].rotation = _heading_angle
		_ship_trails[i].emitting = trails_on

# Threat checks use global positions so icons in other system layers are never in range.
func _process_trader() -> void:
	if player_target != null and is_instance_valid(player_target) and TraderBehavior.should_flee(global_position, player_target.global_position, flee_range):
		_move_target = TraderBehavior.flee_target(position, _to_local_space(player_target.global_position), flee_distance)
		return
	if not has_destination:
		_move_target = position
		return
	_move_target = dest_position
	if position.distance_to(dest_position) <= arrival_radius:
		# Cleared first so a destination the handler sets is kept.
		has_destination = false
		trader_arrived_at.emit(fleet.dest_station_id)

func _process_pirate() -> void:
	if player_target != null and is_instance_valid(player_target) and player_target.fleet != null and PirateBehavior.in_detection_range(global_position, player_target.global_position, detection_range):
		if PirateBehavior.should_intercept(fleet.total_strength(), player_target.fleet.total_strength()):
			_move_target = _to_local_space(player_target.global_position)
			return
	_move_target = PatrolBehavior.next_wander_target(_spawn_point, _move_target, position, wander_radius, arrival_radius)

# Layers only translate, so a global point maps to this icon's parent space by the layer offset.
func _to_local_space(global_point: Vector2) -> Vector2:
	return global_point - global_position + position

func _sync_ship_dots() -> void:
	var target: int = fleet.ship_compositions.size()
	while _ship_dots.size() < target:
		var index := _ship_dots.size()
		if index >= _ship_dot_offsets.size():
			var angle := index * SHIP_OFFSET_GOLDEN_ANGLE
			var distance: float = min(CLUMP_RADIUS, SHIP_OFFSET_SPACING * sqrt(float(index)))
			_ship_dot_offsets.append(Vector2.RIGHT.rotated(angle) * distance)
		var dot := Sprite2D.new()
		dot.texture = _ship_icon_texture(fleet.ship_compositions[index])
		var longest_dim: float = max(dot.texture.get_width(), dot.texture.get_height())
		dot.scale = Vector2.ONE * (SHIP_ICON_MAX_DIM / longest_dim)
		dot.position = _ship_dot_offsets[index]
		dot.rotation = _heading_angle
		add_child(dot)
		_ship_dots.append(dot)
		_ship_trails.append(_make_engine_trail())
	while _ship_dots.size() > target:
		var dot: Sprite2D = _ship_dots.pop_back()
		dot.queue_free()
		var trail: CPUParticles2D = _ship_trails.pop_back()
		trail.queue_free()
	if _ship_dots.size() != target:
		return
	var new_radius := CLUMP_RADIUS + FACTION_CIRCLE_PADDING * sqrt(max(target, 1))
	if new_radius != _faction_circle_radius:
		_faction_circle_radius = new_radius
		queue_redraw()

func _make_engine_trail() -> CPUParticles2D:
	var trail := CPUParticles2D.new()
	trail.emitting = false
	trail.amount = max(1, ENGINE_TRAIL_AMOUNT / max(fleet.ship_compositions.size(), 1))
	trail.lifetime = ENGINE_TRAIL_LIFETIME
	trail.direction = Vector2(-1, 0)
	trail.spread = ENGINE_TRAIL_SPREAD
	trail.gravity = Vector2.ZERO
	trail.initial_velocity_min = ENGINE_TRAIL_VELOCITY_MIN
	trail.initial_velocity_max = ENGINE_TRAIL_VELOCITY_MAX
	trail.scale_amount_min = ENGINE_TRAIL_SCALE_MIN
	trail.scale_amount_max = ENGINE_TRAIL_SCALE_MAX
	trail.color = ENGINE_TRAIL_COLOR
	add_child(trail)
	return trail

func _ship_icon_texture(comp: Dictionary) -> Texture2D:
	var kind: ShipType.Kind = ShipType.kind_of(comp)
	return load(SHIP_ICON_TEXTURES[kind])

func _draw() -> void:
	if fleet == null or _faction_circle_radius <= 0.0:
		return
	var color: Color = FACTION_COLORS.get(fleet.faction, FACTION_COLORS[CampaignFleet.Faction.NEUTRAL])
	draw_arc(Vector2.ZERO, _faction_circle_radius, 0.0, TAU, 48, color, FACTION_CIRCLE_WIDTH)
