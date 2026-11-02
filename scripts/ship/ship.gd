class_name Ship
extends CharacterBody2D

@onready var hull: Hull = $Hull
@onready var shield: Shield = $Shield
@onready var engine: ShipEngine = $Engine

var weapon_mounts: Array[WeaponMount] = []
var current_order: Order

@export var ship_type: ShipType.Kind = ShipType.Kind.CORVETTE
@export var hit_radius: float = 16.0
@export var enemy_group: StringName = &""
@export var arrival_radius: float = 20.0
@export var aggro_range: float = 0.0
@export var leash_distance: float = 250.0
@export var loiter_radius: float = 40.0
@export var loiter_interval: float = 3.0
@export var loiter_arrival_radius: float = 5.0

var _hold_center: Vector2 = Vector2.ZERO
var _loiter_target: Vector2 = Vector2.ZERO
var _loiter_timer: float = 0.0
var _chase_target: Node2D

func _ready() -> void:
	for child in get_children():
		if child is WeaponMount:
			weapon_mounts.append(child)
	hull.destroyed.connect(_on_hull_destroyed)
	execute_order(Order.hold())

func execute_order(order: Order) -> void:
	current_order = order
	if order.type == Order.Type.HOLD:
		_hold_center = global_position
		_loiter_target = global_position
		_loiter_timer = 0.0
		_chase_target = null

func attack_range() -> float:
	var max_range := 0.0
	for mount in weapon_mounts:
		if mount.weapon:
			max_range = max(max_range, mount.weapon.weapon_range)
	return max_range

func get_hit_radius() -> float:
	return hit_radius

func receive_damage(amount: float, impact_position: Vector2 = Vector2.INF) -> void:
	var overflow := shield.absorb(amount)
	if overflow <= 0.0:
		return
	var pos := global_position if impact_position == Vector2.INF else impact_position
	var hit_component := resolve_component_hit(pos)
	if hit_component != null:
		hit_component.apply_damage(overflow)
	else:
		hull.apply_damage(overflow)

func receive_weapon_damage(weapon: Weapon, impact_position: Vector2 = Vector2.INF) -> void:
	var pierce_damage: float = weapon.damage * weapon.pierce_pct
	var absorbable_damage: float = weapon.damage - pierce_damage
	var effective_shield_hit: float = absorbable_damage * weapon.shield_mult
	var overflow_effective := shield.absorb(effective_shield_hit)
	var raw_unabsorbed: float = overflow_effective / weapon.shield_mult if weapon.shield_mult > 0.0 else overflow_effective
	var total_raw: float = raw_unabsorbed + pierce_damage
	if total_raw <= 0.0:
		return
	var pos := global_position if impact_position == Vector2.INF else impact_position
	var hit_component := resolve_component_hit(pos)
	if hit_component != null:
		hit_component.apply_damage(total_raw * weapon.hull_mult + weapon.component_damage)
	else:
		hull.apply_damage(total_raw * weapon.hull_mult)

func resolve_component_hit(impact_pos: Vector2) -> ShipComponent:
	var best: ShipComponent = null
	var best_dist := INF
	var candidates: Array[ShipComponent] = []
	for mount in weapon_mounts:
		candidates.append(mount)
	candidates.append(engine)
	for comp in candidates:
		if comp == null or comp.is_destroyed() or comp.hitbox_radius <= 0.0:
			continue
		var d := comp.global_position.distance_to(impact_pos)
		if d <= comp.hitbox_radius and d < best_dist:
			best = comp
			best_dist = d
	return best

func _physics_process(delta: float) -> void:
	_process_order_movement(delta)
	move_and_slide()
	_process_weapons()

func _process_order_movement(delta: float) -> void:
	match current_order.type:
		Order.Type.MOVE_TO:
			if global_position.distance_to(current_order.target_position) <= arrival_radius:
				execute_order(Order.hold())
			else:
				_steer_to(current_order.target_position, delta)
		Order.Type.ATTACK_TARGET:
			if not is_instance_valid(current_order.target_ship):
				execute_order(Order.hold())
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
			_process_hold(delta)

func _steer_to(target_pos: Vector2, delta: float) -> void:
	var result := engine.steer_toward(global_position, rotation, target_pos, delta)
	rotation = result["rotation"]
	velocity = result["velocity"]

func _process_hold(delta: float) -> void:
	var effective_aggro := aggro_range if aggro_range > 0.0 else attack_range()
	if _chase_target != null and is_instance_valid(_chase_target):
		if Ship.should_disengage(global_position, _chase_target.global_position, _hold_center, effective_aggro, leash_distance):
			_chase_target = null
		else:
			if global_position.distance_to(_chase_target.global_position) > attack_range():
				_steer_to(_chase_target.global_position, delta)
			else:
				velocity = velocity.move_toward(Vector2.ZERO, engine.acceleration * delta)
				engine.velocity = velocity
			return
	else:
		_chase_target = null

	var candidates: Array = get_tree().get_nodes_in_group(enemy_group) if enemy_group != &"" else []
	var candidate := Ship.nearest_in_range(candidates, global_position, effective_aggro)
	if candidate != null:
		_chase_target = candidate
		return

	_process_loiter(delta)

func _process_loiter(delta: float) -> void:
	if global_position.distance_to(_loiter_target) < loiter_arrival_radius:
		_loiter_timer -= delta
		if _loiter_timer <= 0.0:
			_loiter_target = _hold_center + Vector2(randf_range(-loiter_radius, loiter_radius), randf_range(-loiter_radius, loiter_radius))
			_loiter_timer = loiter_interval
	_steer_to(_loiter_target, delta)

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

static func should_disengage(own_position: Vector2, target_position: Vector2, hold_center: Vector2, aggro_range: float, leash_distance: float) -> bool:
	if own_position.distance_to(target_position) > aggro_range:
		return true
	if own_position.distance_to(hold_center) > leash_distance:
		return true
	return false
