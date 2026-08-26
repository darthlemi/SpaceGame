class_name Shield
extends Node

@export var max_shield: float = 50.0
@export var regen_rate: float = 5.0
var current_shield: float

func _ready() -> void:
	current_shield = max_shield

func _physics_process(delta: float) -> void:
	if current_shield < max_shield:
		current_shield = min(max_shield, current_shield + regen_rate * delta)

func absorb(amount: float) -> float:
	if current_shield <= 0.0:
		return amount
	if amount <= current_shield:
		current_shield -= amount
		return 0.0
	var overflow := amount - current_shield
	current_shield = 0.0
	return overflow
