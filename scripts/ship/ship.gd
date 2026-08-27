class_name Ship
extends CharacterBody2D

enum ControlMode { ORDER_BASED, DIRECT }

@onready var hull: Hull = $Hull
@onready var shield: Shield = $Shield
@onready var engine: ShipEngine = $Engine

var weapon_mounts: Array[WeaponMount] = []
var current_order: Order
var control_mode: ControlMode = ControlMode.ORDER_BASED

@export var enemy_group: StringName = &""

func _ready() -> void:
	for child in get_children():
		if child is WeaponMount:
			weapon_mounts.append(child)
	hull.destroyed.connect(_on_hull_destroyed)
	current_order = Order.hold()

func execute_order(order: Order) -> void:
	current_order = order

func attack_range() -> float:
	var max_range := 0.0
	for mount in weapon_mounts:
		if mount.weapon:
			max_range = max(max_range, mount.weapon.weapon_range)
	return max_range

func receive_damage(amount: float) -> void:
	var overflow := shield.absorb(amount)
	if overflow > 0.0:
		hull.apply_damage(overflow)

func _physics_process(delta: float) -> void:
	if control_mode == ControlMode.ORDER_BASED:
		_process_order_movement(delta)
		move_and_slide()
		_process_weapons()

func _process_order_movement(delta: float) -> void:
	match current_order.type:
		Order.Type.MOVE_TO:
			_steer_to(current_order.target_position, delta)
		Order.Type.ATTACK_TARGET:
			if not is_instance_valid(current_order.target_ship):
				current_order = Order.hold()
				return
			var target_pos: Vector2 = current_order.target_ship.global_position
			if global_position.distance_to(target_pos) > attack_range():
				_steer_to(target_pos, delta)
			else:
				velocity = velocity.move_toward(Vector2.ZERO, engine.acceleration * delta)
				engine.velocity = velocity
		Order.Type.RETREAT:
			var away := global_position + (global_position - current_order.target_position).normalized() * 500.0
			_steer_to(away, delta)
		Order.Type.HOLD:
			velocity = velocity.move_toward(Vector2.ZERO, engine.acceleration * delta)
			engine.velocity = velocity

func _steer_to(target_pos: Vector2, delta: float) -> void:
	var result := engine.steer_toward(global_position, rotation, target_pos, delta)
	rotation = result["rotation"]
	velocity = result["velocity"]

func _process_weapons() -> void:
	if weapon_mounts.is_empty():
		return
	var max_range := attack_range()
	var candidates: Array = get_tree().get_nodes_in_group(enemy_group) if enemy_group != &"" else []
	var target := Ship.pick_autofire_target(current_order, candidates, global_position, max_range)
	if target == null:
		return
	for mount in weapon_mounts:
		mount.try_fire(target)

func _on_hull_destroyed() -> void:
	queue_free()

static func nearest_in_range(candidates: Array, own_position: Vector2, max_range: float) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := max_range
	for c in candidates:
		if c is Node2D and is_instance_valid(c):
			var d: float = own_position.distance_to(c.global_position)
			if d <= nearest_dist:
				nearest_dist = d
				nearest = c
	return nearest

static func pick_autofire_target(order: Order, candidates: Array, own_position: Vector2, max_range: float) -> Node2D:
	if order.type == Order.Type.ATTACK_TARGET:
		return order.target_ship if is_instance_valid(order.target_ship) else null
	return Ship.nearest_in_range(candidates, own_position, max_range)
