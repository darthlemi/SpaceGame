class_name Shield
extends RefCounted

@export var max_shield: float = 50.0
@export var regen_rate: float = 5.0
var current_shield: float

func _init(p_max_shield: float = 50.0, p_regen_rate: float = 5.0) -> void:
	max_shield = p_max_shield
	regen_rate = p_regen_rate
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
