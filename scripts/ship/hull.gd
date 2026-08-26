class_name Hull
extends RefCounted

signal destroyed
signal damaged(amount: float, remaining: float)

@export var max_hp: float = 100.0
var current_hp: float

func _init(p_max_hp: float = 100.0) -> void:
	max_hp = p_max_hp
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
