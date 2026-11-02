class_name Shield
extends Node

signal depleted
signal restored

@export var max_shield: float = 50.0
@export var regen_rate: float = 5.0
var current_shield: float
var regen_multiplier: float = 1.0

func _ready() -> void:
	current_shield = max_shield

func _physics_process(delta: float) -> void:
	if current_shield < max_shield:
		var was_depleted := current_shield <= 0.0
		current_shield = min(max_shield, current_shield + regen_rate * regen_multiplier * delta)
		if was_depleted and current_shield > 0.0:
			restored.emit()
	regen_multiplier = 1.0

func absorb(amount: float) -> float:
	if current_shield <= 0.0:
		return amount
	var remaining: float = max(0.0, current_shield - amount)
	var overflow: float = max(0.0, amount - current_shield)
	current_shield = remaining
	if current_shield <= 0.0:
		depleted.emit()
	return overflow

func health_fraction() -> float:
	return current_shield / max_shield if max_shield > 0.0 else 0.0
