class_name DirectPilot
extends Node

var ship: Ship
var enemy: Node2D

func setup(p_ship: Ship, p_enemy: Node2D) -> void:
	ship = p_ship
	enemy = p_enemy

func _physics_process(delta: float) -> void:
	if not is_instance_valid(ship):
		return
	var turn := Input.get_axis("pilot_turn_left", "pilot_turn_right")
	ship.rotation += turn * ship.engine.turn_rate * delta
	var thrust := Input.get_action_strength("pilot_thrust")
	if thrust > 0.0:
		var forward := Vector2.RIGHT.rotated(ship.rotation)
		ship.velocity = ship.velocity.move_toward(forward * ship.engine.max_speed, ship.engine.acceleration * delta)
	else:
		ship.velocity = ship.velocity.move_toward(Vector2.ZERO, ship.engine.acceleration * delta)
	ship.move_and_slide()
	ship.engine.velocity = ship.velocity
	if Input.is_action_pressed("pilot_fire") and is_instance_valid(enemy):
		for mount in ship.weapon_mounts:
			mount.try_fire(enemy)
