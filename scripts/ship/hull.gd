class_name Hull
extends Node

signal destroyed
signal damaged(amount: float, remaining: float)

@export var max_hp: float = 100.0
var current_hp: float
var invulnerable: bool = false

func _ready() -> void:
	current_hp = max_hp

func apply_damage(amount: float) -> void:
	if invulnerable or current_hp <= 0.0:
		return
	current_hp = max(0.0, current_hp - amount)
	damaged.emit(amount, current_hp)
	if current_hp <= 0.0:
		destroyed.emit()

func is_destroyed() -> bool:
	return current_hp <= 0.0
