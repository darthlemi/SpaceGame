class_name DroneBay
extends ShipComponent

@export var max_drones: int = 3
@export var launch_interval: float = 0.3
@export var respawn_delay: float = 15.0
@export var drone_scene: PackedScene

var _slot_cooldowns: Array[float] = []
var _slot_drones: Array[Ship] = []
var _launch_cooldown: float = 0.0

func _ready() -> void:
	super._ready()
	_slot_cooldowns.clear()
	_slot_drones.clear()
	_launch_cooldown = 0.0
	for i in max_drones:
		_slot_cooldowns.append(0.0)
		_slot_drones.append(null)

func _physics_process(delta: float) -> void:
	_launch_cooldown = max(0.0, _launch_cooldown - delta)
	for i in _slot_cooldowns.size():
		if _slot_cooldowns[i] > 0.0:
			_slot_cooldowns[i] = max(0.0, _slot_cooldowns[i] - delta)

func try_launch(target: Node2D) -> Ship:
	if is_destroyed() or drone_scene == null or _launch_cooldown > 0.0:
		return null
	for i in _slot_drones.size():
		if _slot_drones[i] != null and is_instance_valid(_slot_drones[i]) and not _slot_drones[i].hull.is_destroyed():
			continue
		if _slot_cooldowns[i] > 0.0:
			continue
		var drone: Ship = drone_scene.instantiate()
		drone._ready()
		drone.global_position = global_position
		_slot_drones[i] = drone
		_launch_cooldown = launch_interval
		drone.hull.destroyed.connect(_on_drone_destroyed.bind(i))
		if target != null:
			drone.execute_order(Order.attack_target(target))
		return drone
	return null

func _on_drone_destroyed(slot_index: int) -> void:
	_slot_cooldowns[slot_index] = respawn_delay
