class_name ShipVfx
extends Node2D

@export var flash_color: Color = Color(1, 0.3, 0.3, 1)
@export var flash_duration: float = 0.12
@export var low_hp_threshold: float = 0.25

const ENGINE_TRAIL_SPEED_THRESHOLD := 5.0
const ExplosionScene = preload("res://scenes/vfx/explosion.tscn")
const SHIELD_GLOW_BASE_ALPHA := 0.35

@onready var _visual: CanvasItem = (
	get_parent().get_node_or_null("Sprite2D") as CanvasItem
	if get_parent().has_node("Sprite2D")
	else get_parent().get_node("Polygon2D") as CanvasItem
)
@onready var _hull: Hull = get_parent().get_node("Hull")
@onready var _engine: ShipEngine = get_parent().get_node("Engine")
@onready var _shield: Shield = get_parent().get_node("Shield")
@onready var _shield_glow: Polygon2D = get_parent().get_node("ShieldGlow")
@onready var _hit_spark: CPUParticles2D = $HitSpark
@onready var _smoke_trail: CPUParticles2D = $SmokeTrail
@onready var _engine_trail: CPUParticles2D = $EngineTrail
@onready var _body: CharacterBody2D = get_parent()

var _flash_tween: Tween
var _shield_flicker_tween: Tween
var _engine_disabled := false

func _ready() -> void:
	_hull.damaged.connect(_on_hull_damaged)
	_hull.destroyed.connect(_on_hull_destroyed)
	_engine.destroyed.connect(_on_engine_destroyed)
	_shield.depleted.connect(_on_shield_depleted)
	_shield.restored.connect(_on_shield_restored)
	call_deferred("_wire_weapon_mount_signals")

func _wire_weapon_mount_signals() -> void:
	for mount in _body.weapon_mounts:
		mount.destroyed.connect(_on_weapon_mount_destroyed.bind(mount))

func _physics_process(_delta: float) -> void:
	_engine_trail.emitting = not _engine_disabled and _body.velocity.length() > ENGINE_TRAIL_SPEED_THRESHOLD
	if _shield_flicker_tween == null or not _shield_flicker_tween.is_running():
		_shield_glow.modulate.a = SHIELD_GLOW_BASE_ALPHA * _shield.health_fraction()

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
	_spawn_explosion_at(get_parent().global_position)

func _on_engine_destroyed() -> void:
	_engine_disabled = true
	_engine_trail.emitting = false
	_spawn_explosion_at(_engine.global_position)

func _on_weapon_mount_destroyed(mount: WeaponMount) -> void:
	_spawn_explosion_at(mount.global_position)

func _on_shield_depleted() -> void:
	if _shield_flicker_tween:
		_shield_flicker_tween.kill()
	_shield_glow.modulate.a = 1.0
	_shield_flicker_tween = create_tween()
	_shield_flicker_tween.tween_property(_shield_glow, "modulate:a", 0.0, flash_duration)

func _on_shield_restored() -> void:
	if _shield_flicker_tween:
		_shield_flicker_tween.kill()
	_shield_glow.modulate.a = 0.0
	_shield_flicker_tween = create_tween()
	_shield_flicker_tween.tween_property(_shield_glow, "modulate:a", SHIELD_GLOW_BASE_ALPHA * _shield.health_fraction(), flash_duration)

func _spawn_explosion_at(pos: Vector2) -> void:
	var ship_node := get_parent()
	var explosion: Node2D = ExplosionScene.instantiate()
	ship_node.get_parent().add_child(explosion)
	explosion.global_position = pos

static func should_emit_smoke(hp_ratio: float, threshold: float) -> bool:
	return hp_ratio <= threshold
