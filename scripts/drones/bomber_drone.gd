class_name BomberDrone
extends Ship

@export var detonate_radius: float = 15.0
@export var payload_weapon: Weapon

func attack_range() -> float:
	return detonate_radius

# Detonates on contact, so it closes all the way in.
func engagement_distance(_target: Node2D) -> float:
	return 0.0

func _process_weapons() -> void:
	if current_order == null or current_order.type != Order.Type.ATTACK_TARGET:
		return
	var target: Node2D = current_order.target_ship
	if not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) > detonate_radius:
		return
	if target.has_method("receive_weapon_damage") and payload_weapon != null:
		target.receive_weapon_damage(payload_weapon)
	hull.apply_damage(hull.max_hp)
