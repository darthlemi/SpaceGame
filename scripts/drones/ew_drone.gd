class_name EwDrone
extends Ship

@export var aura_range: float = 150.0
@export var regen_debuff_mult: float = 0.5

var _test_candidates: Array = []

func engagement_distance(_target: Node2D) -> float:
	return aura_range * ENGAGE_RANGE_FRACTION

func _process_weapons() -> void:
	var candidates: Array = get_tree().get_nodes_in_group(enemy_group) if is_inside_tree() and enemy_group != &"" else _test_candidates
	var target := Ship.nearest_in_range(candidates, global_position, aura_range)
	if target == null:
		return
	target.shield.regen_multiplier = regen_debuff_mult
