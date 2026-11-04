class_name Ship
extends CharacterBody2D

# Standoff sits this far inside the chosen weapon range so target drift doesn't break it.
const ENGAGE_RANGE_FRACTION := 0.8
# Share of total weapon dps the standoff range must keep in reach.
const ENGAGE_DPS_SHARE := 0.75
# Minimum clear space between hulls, so short-ranged ships don't ram.
const ENGAGE_HULL_GAP := 30.0

@onready var hull: Hull = $Hull
@onready var shield: Shield = $Shield
@onready var engine: ShipEngine = $Engine

var weapon_mounts: Array[WeaponMount] = []
var current_order: Order

@export var ship_type: ShipType.Kind = ShipType.Kind.CORVETTE
@export var hit_radius: float = 16.0
@export var player_targetable: bool = true
@export var enemy_group: StringName = &""
@export var arrival_radius: float = 20.0
@export var loiter_radius: float = 40.0
@export var loiter_interval: float = 3.0
@export var loiter_arrival_radius: float = 5.0
@export var randomize_loadout: bool = false

var _hold_center: Vector2 = Vector2.ZERO
# Spawners place a ship after its _ready issues HOLD, so the anchor waits for the first tick.
var _hold_anchored: bool = false
var _loiter_target: Vector2 = Vector2.ZERO
var _loiter_timer: float = 0.0

# complement 0 means crew isn't tracked (drones, non-campaign battles): full efficiency.
var crew: float = 0.0
var crew_complement: int = 0
var crew_floor: int = 0
var _last_hull_hp: float = 0.0

func _ready() -> void:
	for child in get_children():
		if child is WeaponMount:
			weapon_mounts.append(child)
	hull.destroyed.connect(_on_hull_destroyed)
	hull.damaged.connect(_on_hull_damaged)
	execute_order(Order.hold())
	if randomize_loadout:
		_assign_random_loadout()

# Must run after hull hp is applied: snapshots hull.current_hp as the crew-loss baseline.
func setup_crew(crew_count: int, complement: int, floor_count: int) -> void:
	crew = float(crew_count)
	crew_complement = complement
	crew_floor = floor_count
	_last_hull_hp = hull.current_hp
	_apply_crew_efficiency()

func crew_efficiency() -> float:
	return CrewRules.efficiency_for(crew, crew_complement)

func _on_hull_damaged(_amount: float, remaining: float) -> void:
	if crew_complement <= 0:
		return
	if _last_hull_hp > 0.0:
		crew = max(float(crew_floor), crew * remaining / _last_hull_hp)
	_last_hull_hp = remaining
	_apply_crew_efficiency()

func _apply_crew_efficiency() -> void:
	var efficiency := crew_efficiency()
	engine.crew_multiplier = efficiency
	shield.crew_multiplier = efficiency
	for mount in weapon_mounts:
		mount.fire_rate_multiplier = efficiency

func _assign_random_loadout() -> void:
	var pool: Array = ShipType.WEAPON_POOL.duplicate()
	pool.shuffle()
	for i in weapon_mounts.size():
		weapon_mounts[i].weapon = load(pool[i % pool.size()])

func execute_order(order: Order) -> void:
	current_order = order
	if order.type == Order.Type.HOLD:
		_hold_anchored = false
		_loiter_timer = 0.0

func attack_range() -> float:
	var max_range := 0.0
	for mount in weapon_mounts:
		if mount.weapon:
			max_range = max(max_range, mount.weapon.weapon_range)
	return max_range

# How far to sit from target: < 0 means don't close in (nothing working to shoot with).
# Drones without mounts override this.
func engagement_distance(target: Node2D) -> float:
	var weapons: Array[Weapon] = []
	for mount in weapon_mounts:
		if mount.weapon != null and not mount.is_destroyed():
			weapons.append(mount.weapon)
	if weapons.is_empty():
		return -1.0
	var target_radius: float = target.get_hit_radius() if target.has_method("get_hit_radius") else 0.0
	var hull_floor := hit_radius + target_radius + ENGAGE_HULL_GAP
	return maxf(Ship.best_engagement_range(weapons) * ENGAGE_RANGE_FRACTION, hull_floor)

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
			_engage(current_order.target_ship, delta)
		Order.Type.RETREAT:
			var away := global_position + (global_position - current_order.target_position).normalized() * 500.0
			_steer_to(away, delta)
		Order.Type.HOLD:
			_process_hold(delta, _enemy_candidates())

# Holds the standoff on the line from target to ship, nose on the target so fixed and
# limited-arc hardpoints bear.
func _enemy_candidates() -> Array:
	return get_tree().get_nodes_in_group(enemy_group) if enemy_group != &"" else []

func _engage(target: Node2D, delta: float) -> void:
	var standoff := engagement_distance(target)
	if standoff < 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, engine.acceleration * delta)
		engine.velocity = velocity
		return
	var target_pos := target.global_position
	var away := global_position - target_pos
	var bearing := away.normalized() if away.length() > 0.01 else Vector2.LEFT.rotated(rotation)
	var result := engine.hold_station(global_position, rotation, target_pos, target_pos + bearing * standoff, delta)
	rotation = result["rotation"]
	velocity = result["velocity"]

func _steer_to(target_pos: Vector2, delta: float) -> void:
	var result := engine.steer_toward(global_position, rotation, target_pos, delta)
	rotation = result["rotation"]
	velocity = result["velocity"]

# Idle ships hunt the nearest enemy anywhere, re-picking each tick so a closer threat
# takes over; they loiter only once no enemy is left.
func _process_hold(delta: float, candidates: Array) -> void:
	var nearest := Ship.nearest_in_range(candidates, global_position, INF)
	if nearest != null:
		# Re-anchor after the fight, so loitering starts where it ended, not back at spawn.
		_hold_anchored = false
		_engage(nearest, delta)
		return
	if not _hold_anchored:
		_hold_center = global_position
		_loiter_target = global_position
		_hold_anchored = true
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
	var candidates := _enemy_candidates()
	var primary := Ship.pick_autofire_target(current_order, candidates, global_position, attack_range())
	for mount in weapon_mounts:
		if not mount.can_fire():
			continue
		var target := Ship.pick_mount_target(mount, primary, candidates)
		if target != null:
			mount.try_fire(target)

func _on_hull_destroyed() -> void:
	queue_free()

# The longest weapon range that still keeps ENGAGE_DPS_SHARE of total dps in reach, so a
# light short weapon doesn't drag the ship in but a heavy one does.
static func best_engagement_range(weapons: Array[Weapon]) -> float:
	var total_dps := 0.0
	for weapon in weapons:
		total_dps += Ship._weapon_dps(weapon)
	var best_range := 0.0
	for candidate in weapons:
		if candidate.weapon_range <= best_range:
			continue
		var reach_dps := 0.0
		for weapon in weapons:
			if weapon.weapon_range >= candidate.weapon_range:
				reach_dps += Ship._weapon_dps(weapon)
		if reach_dps >= total_dps * ENGAGE_DPS_SHARE:
			best_range = candidate.weapon_range
	return best_range

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

# Mounts that can't bear on the primary target take any other enemy they can hit.
static func pick_mount_target(mount: WeaponMount, primary: Node2D, candidates: Array) -> Node2D:
	if primary != null and mount.can_engage(primary):
		return primary
	return mount.nearest_engageable(candidates)

static func _weapon_dps(weapon: Weapon) -> float:
	return weapon.damage * weapon.fire_rate * weapon.submissile_count
