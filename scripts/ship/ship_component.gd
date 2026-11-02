class_name ShipComponent
extends Node2D

signal destroyed
signal damaged(amount: float, remaining: float)

@export var max_hp: float = 10.0
@export var hitbox_radius: float = 0.0
var current_hp: float

func _ready() -> void:
	current_hp = max_hp

func apply_damage(amount: float) -> void:
	if current_hp <= 0.0:
		return
	current_hp = max(0.0, current_hp - amount)
	damaged.emit(amount, current_hp)
	if current_hp <= 0.0:
		destroyed.emit()

func is_destroyed() -> bool:
	return current_hp <= 0.0

func health_fraction() -> float:
	return current_hp / max_hp if max_hp > 0.0 else 0.0
