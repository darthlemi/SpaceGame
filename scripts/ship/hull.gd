class_name Hull
extends ShipComponent

var invulnerable: bool = false

func apply_damage(amount: float) -> void:
	if invulnerable:
		return
	super.apply_damage(amount)
