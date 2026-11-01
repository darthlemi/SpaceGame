class_name ShipVfx
extends Node2D

@export var flash_color: Color = Color(1, 0.3, 0.3, 1)
@export var flash_duration: float = 0.12
@export var low_hp_threshold: float = 0.25

const ENGINE_TRAIL_SPEED_THRESHOLD := 5.0
const ExplosionScene = preload("res://scenes/vfx/explosion.tscn")

@onready var _visual: CanvasItem = (
	get_parent().get_node_or_null("Sprite2D") as CanvasItem
	if get_parent().has_node("Sprite2D")
	else get_parent().get_node("Polygon2D") as CanvasItem
)
@onready var _hull: Hull = get_parent().get_node("Hull")
@onready var _hit_spark: CPUParticles2D = $HitSpark
@onready var _smoke_trail: CPUParticles2D = $SmokeTrail
@onready var _engine_trail: CPUParticles2D = $EngineTrail
@onready var _body: CharacterBody2D = get_parent()

var _flash_tween: Tween

func _ready() -> void:
	_hull.damaged.connect(_on_hull_damaged)
	_hull.destroyed.connect(_on_hull_destroyed)

func _physics_process(_delta: float) -> void:
	_engine_trail.emitting = _body.velocity.length() > ENGINE_TRAIL_SPEED_THRESHOLD

func _on_hull_damaged(_amount: float, remaining: float) -> void:
	_flash()
	_hit_spark.restart()
	var hp_ratio: float = remaining / _hull.max_hp if _hull.max_hp > 0.0 else 0.0
	_smoke_trail.emitting = should_emit_smoke(hp_ratio, low_hp_threshold)

func _flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_visual.modulate = flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_visual, "modulate", Color.WHITE, flash_duration)

func _on_hull_destroyed() -> void:
	var ship_node := get_parent()
	var explosion: Node2D = ExplosionScene.instantiate()
	ship_node.get_parent().add_child(explosion)
	explosion.global_position = ship_node.global_position

static func should_emit_smoke(hp_ratio: float, threshold: float) -> bool:
	return hp_ratio <= threshold
