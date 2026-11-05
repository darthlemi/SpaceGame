class_name Ship
extends CharacterBody2D

# Standoff sits this far inside the chosen weapon range so target drift doesn't break it.
const ENGAGE_RANGE_FRACTION := 0.8
# Share of total weapon dps the standoff range must keep in reach.
const ENGAGE_DPS_SHARE := 0.75
# Minimum clear space between hulls, so short-ranged ships don't ram.
const ENGAGE_HULL_GAP := 30.0
# Seconds of unbroken flight, untouched past the shields, before a fleeing ship jumps out.
const FLEE_SPOOL_TIME := {ShipType.Kind.CORVETTE: 6.0, ShipType.Kind.FREIGHTER: 6.0, ShipType.Kind.CAPITAL: 8.0}

# Fleeing ships run from enemies this close, and each flee leg is this long.
const FLEE_THREAT_RADIUS := 800.0
const FLEE_STEP := 500.0

signal jumped_out(ship: Ship)

@onready var hull: Hull = $Hull
@onready var shield: Shield = $Shield
@onready var engine: ShipEngine = $Engine

var weapon_mounts: Array[WeaponMount] = []
var current_order: Order

@export var ship_type: ShipType.Kind = ShipType.Kind.CORVETTE
@export var hit_radius: float = 16.0
@export var player_targetable: bool = true
@export var enemy_group: StringName = &""
@export var ally_group: StringName = &""
@export var arrival_radius: float = 20.0
@export var loiter_radius: float = 40.0
@export var loiter_interval: float = 3.0
@export var loiter_arrival_radius: float = 5.0
@export var randomize_loadout: bool = false

# Empty means no clamping.
var arena_rect: Rect2 = Rect2()
var has_fled: bool = false
var _flee_spool: float = 0.0

var _hold_position_anchor: Vector2 = Vector2.ZERO
var _hold_center: Vector2 = Vector2.ZERO
# Spawners place a ship after its _ready issues HOLD, so the anchor waits for the first tick.
var _hold_anchored: bool = false
var _loiter_target: Vector2 = Vector2.ZERO
var _loiter_timer: float = 0.0
var _run_phase: CombatTactics.RunPhase = CombatTactics.RunPhase.INBOUND
# Cleared every tick, so a ship that stops fighting drops out of its allies' spread.
var _engaged_target: Node2D = null
var _run_target_id: int = 0
# What idle HOLD is engaging, re-picked every RETARGET_INTERVAL.
var _idle_target: Node2D = null
var _retarget_timer: float = 0.0

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
	var spool_bar := FleeSpoolBar.new()
	add_child(spool_bar)
	spool_bar.setup(self)
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
	# Any other order cancels a flee in progress.
	if order.type != Order.Type.FLEE:
		_flee_spool = 0.0
	if order.type == Order.Type.HOLD_POSITION:
		_hold_position_anchor = global_position
		_idle_target = null
	if order.type == Order.Type.HOLD:
		_hold_anchored = false
		_loiter_timer = 0.0

func flee_progress() -> float:
	return clampf(_flee_spool / _flee_spool_time(), 0.0, 1.0)

func _flee_spool_time() -> float:
	return FLEE_SPOOL_TIME.get(ship_type, FLEE_SPOOL_TIME[ShipType.Kind.CORVETTE])

func attack_range() -> float:
	var max_range := 0.0
	for mount in weapon_mounts:
		if mount.weapon:
			max_range = max(max_range, mount.weapon.weapon_range)
	return max_range

# Mounts that are intact and armed.
func working_weapons() -> Array[Weapon]:
	var weapons: Array[Weapon] = []
	for mount in weapon_mounts:
		if mount.weapon != null and not mount.is_destroyed():
			weapons.append(mount.weapon)
	return weapons

# The longest reach of anything that can hurt a hull: what a rival must stay out of to kite.
func threat_range() -> float:
	return CombatTactics.threat_range(working_weapons())

# The target _engage last ran against, or null. Allies use it to find who shares a target.
func engaging_target() -> Node2D:
	return _engaged_target if is_instance_valid(_engaged_target) else null

# What idle HOLD is currently engaging, or null.
func idle_target() -> Node2D:
	return _idle_target if is_instance_valid(_idle_target) else null

# How far to sit from the target's hull edge: < 0 means don't close in (nothing working to
# shoot with). Drones without mounts override this.
func engagement_distance(target: Node2D) -> float:
	var weapons := working_weapons()
	if weapons.is_empty():
		return -1.0
	# The edge measure already takes the target's radius off.
	var hull_floor := hit_radius + ENGAGE_HULL_GAP
	return maxf(Ship.best_engagement_range(weapons) * ENGAGE_RANGE_FRACTION, hull_floor)

func get_hit_radius() -> float:
	return hit_radius

func receive_damage(amount: float, impact_position: Vector2 = Vector2.INF) -> void:
	var overflow := shield.absorb(amount)
	if overflow <= 0.0:
		return
	_flee_spool = 0.0
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
	_flee_spool = 0.0
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
	_engaged_target = null
	_process_order_movement(delta)
	move_and_slide()
	_process_weapons()
	if current_order.type == Order.Type.FLEE and _flee_spool >= _flee_spool_time():
		_jump_out()

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
		Order.Type.HOLD_POSITION:
			_process_hold_position(delta, _enemy_candidates())
		Order.Type.FLEE:
			_process_flee(delta)

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
	_engaged_target = target
	var weapons := working_weapons()
	if CombatTactics.tactic_for(weapons, engine.turn_rate) == CombatTactics.Tactic.RUN:
		_run_at(target, weapons, delta)
	else:
		_park_at(target, standoff, delta)

# Fixed forward guns can't track: fly at the target, then peel off and come round again.
func _run_at(target: Node2D, weapons: Array[Weapon], delta: float) -> void:
	var target_pos := target.global_position
	# A phase carried over from another target would fly away from a nearby new one.
	if target.get_instance_id() != _run_target_id:
		_run_target_id = target.get_instance_id()
		_run_phase = CombatTactics.RunPhase.INBOUND
	var run_range := Ship.best_engagement_range(weapons)
	var hull_floor := hit_radius + ENGAGE_HULL_GAP
	_run_phase = CombatTactics.next_run_phase(_run_phase, CombatTactics.edge_distance(global_position, target), run_range, hull_floor)
	if _run_phase == CombatTactics.RunPhase.INBOUND:
		_steer_to(target_pos, delta)
		return
	var away := global_position - target_pos
	var away_dir := away.normalized() if away.length() > 0.01 else Vector2.LEFT.rotated(rotation)
	var side := 1.0 if get_instance_id() % 2 == 0 else -1.0
	# Run range is an edge distance, so add the radius to land at it.
	var break_point := target_pos + away_dir.rotated(side * PI / 3.0) * (run_range + _hit_radius_of(target))
	_steer_to(break_point, delta)

# Holds the standoff on the line from target to ship, nose on the target so fixed and
# limited-arc hardpoints bear. Allies on one target take different bearings.
func _park_at(target: Node2D, standoff: float, delta: float) -> void:
	var target_pos := target.global_position
	var enemy := target as Ship
	if enemy != null:
		var enemy_speed := enemy.engine.effective_max_speed() if enemy.engine != null else 0.0
		var own_reach := Ship.best_engagement_range(working_weapons())
		standoff = CombatTactics.kite_standoff(standoff, own_reach, enemy.threat_range(), engine.effective_max_speed(), enemy_speed)
	var allies := _live_allies()
	var attackers := _attackers_of(target, allies)
	var away := global_position - target_pos
	var bearing := away.normalized() if away.length() > 0.01 else Vector2.LEFT.rotated(rotation)
	if attackers.size() > 1:
		var centroid := Vector2.ZERO
		for attacker in attackers:
			centroid += attacker.global_position
		centroid /= float(attackers.size())
		var base := (centroid - target_pos).angle() if centroid.distance_to(target_pos) > 0.01 else bearing.angle()
		bearing = Vector2.RIGHT.rotated(CombatTactics.approach_bearing(base, attackers.find(self), attackers.size()))
	# Bombers pass 0 to ram the centre; everything else stands off from the hull edge.
	var centre_gap := standoff + _hit_radius_of(target) if standoff > 0.0 else 0.0
	var station := target_pos + bearing * centre_gap
	var ally_positions: Array[Vector2] = []
	for ally in allies:
		if ally != self:
			ally_positions.append(ally.global_position)
	station += CombatTactics.separation_push(global_position, ally_positions, hit_radius * CombatTactics.SEPARATION_RADIUS_FACTOR) * CombatTactics.SEPARATION_STRENGTH
	var result := engine.hold_station(global_position, rotation, target_pos, station, delta)
	rotation = result["rotation"]
	velocity = result["velocity"]

func _hit_radius_of(target: Node2D) -> float:
	return target.get_hit_radius() if target.has_method("get_hit_radius") else 0.0

# Live ships in ally_group, including self. Bare ships outside a tree have no allies.
func _live_allies() -> Array[Ship]:
	var allies: Array[Ship] = []
	if ally_group == &"" or not is_inside_tree():
		return allies
	for node in get_tree().get_nodes_in_group(ally_group):
		if is_instance_valid(node) and node is Ship and not node.is_queued_for_deletion():
			allies.append(node)
	return allies

# Stable order, so each attacker keeps its slot while the set is unchanged.
func _attackers_of(target: Node2D, allies: Array[Ship]) -> Array[Ship]:
	var attackers: Array[Ship] = []
	for ally in allies:
		if ally == self or ally.engaging_target() == target:
			attackers.append(ally)
	if not attackers.has(self):
		attackers.append(self)
	attackers.sort_custom(func(a: Ship, b: Ship) -> bool: return a.get_instance_id() < b.get_instance_id())
	return attackers

func _steer_to(target_pos: Vector2, delta: float) -> void:
	var result := engine.steer_toward(global_position, rotation, target_pos, delta)
	rotation = result["rotation"]
	velocity = result["velocity"]

# Idle ships hunt the best-scored enemy anywhere, re-picking every RETARGET_INTERVAL (or at
# once when the target is gone); they loiter only once no enemy is left.
func _process_hold(delta: float, candidates: Array) -> void:
	_retarget_timer -= delta
	if _retarget_timer <= 0.0 or not _is_live_target(_idle_target):
		_idle_target = CombatTactics.pick_target(self, candidates, _idle_target)
		_retarget_timer = CombatTactics.RETARGET_INTERVAL
	if _idle_target != null:
		# Re-anchor after the fight, so loitering starts where it ended, not back at spawn.
		_hold_anchored = false
		_engage(_idle_target, delta)
		return
	if not _hold_anchored:
		_hold_center = global_position
		_loiter_target = global_position
		_hold_anchored = true
	_process_loiter(delta)

# Stays on the anchor and turns to the best enemy in reach; never moves toward one.
func _process_hold_position(delta: float, candidates: Array) -> void:
	var reach := attack_range()
	var in_reach: Array = []
	for candidate in candidates:
		if _is_live_target(candidate) and candidate is Node2D and CombatTactics.edge_distance(global_position, candidate) <= reach:
			in_reach.append(candidate)
	_idle_target = CombatTactics.pick_target(self, in_reach, _idle_target)
	var face := global_position + Vector2.RIGHT.rotated(rotation) * 100.0
	if _idle_target != null:
		face = _idle_target.global_position
	var result := engine.hold_station(global_position, rotation, face, _hold_position_anchor, delta)
	rotation = result["rotation"]
	velocity = result["velocity"]

# Runs flat out away from nearby enemies; weapons keep firing through _process_weapons.
func _process_flee(delta: float) -> void:
	_flee_spool += delta
	var away_dir := Vector2.RIGHT.rotated(rotation)
	var centroid := Vector2.ZERO
	var count := 0
	for candidate in _enemy_candidates():
		if _is_live_target(candidate) and candidate is Node2D and global_position.distance_to(candidate.global_position) <= FLEE_THREAT_RADIUS:
			centroid += candidate.global_position
			count += 1
	if count > 0:
		var away := global_position - centroid / float(count)
		if away.length() > 0.01:
			away_dir = away.normalized()
	var destination := global_position + away_dir * FLEE_STEP
	var inner := arena_rect.grow(-2.0 * hit_radius)
	if arena_rect.has_area() and inner.size.x > 0.0 and inner.size.y > 0.0:
		destination = destination.clamp(inner.position, inner.end)
	_steer_to(destination, delta)

# Checked at the jump itself: a hull destroyed this frame is only queued for deletion.
func _jump_out() -> void:
	if has_fled or hull.is_destroyed() or is_queued_for_deletion():
		return
	has_fled = true
	for group in get_groups():
		remove_from_group(group)
	hide()
	collision_layer = 0
	collision_mask = 0
	process_mode = Node.PROCESS_MODE_DISABLED
	_spawn_jump_flash()
	jumped_out.emit(self)

func _spawn_jump_flash() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var flash := CPUParticles2D.new()
	flash.emitting = false
	flash.one_shot = true
	flash.amount = 20
	flash.lifetime = 0.4
	flash.explosiveness = 1.0
	flash.spread = 180.0
	flash.gravity = Vector2.ZERO
	flash.initial_velocity_min = 80.0
	flash.initial_velocity_max = 160.0
	flash.scale_amount_min = 2.0
	flash.scale_amount_max = 4.0
	flash.color = FleeSpoolBar.BAR_COLOR
	parent.add_child(flash)
	flash.global_position = global_position
	flash.finished.connect(flash.queue_free)
	flash.emitting = true

func _process_loiter(delta: float) -> void:
	if global_position.distance_to(_loiter_target) < loiter_arrival_radius:
		_loiter_timer -= delta
		if _loiter_timer <= 0.0:
			_loiter_target = _hold_center + Vector2(randf_range(-loiter_radius, loiter_radius), randf_range(-loiter_radius, loiter_radius))
			_loiter_timer = loiter_interval
	_steer_to(_loiter_target, delta)

# A target freed this frame is still valid until the queue is flushed, so check both.
func _is_live_target(target) -> bool:
	return is_instance_valid(target) and not target.is_queued_for_deletion()

func _process_weapons() -> void:
	if weapon_mounts.is_empty():
		return
	var candidates := _enemy_candidates()
	var primary := Ship.pick_autofire_target(current_order, candidates, global_position, attack_range(), idle_target())
	for mount in weapon_mounts:
		if not mount.can_fire():
			continue
		var target := Ship.pick_mount_target(mount, primary, candidates)
		if target != null:
			mount.try_fire(target)

func _on_hull_destroyed() -> void:
	queue_free()

# The longest weapon range that still keeps ENGAGE_DPS_SHARE of total dps in reach, so a
# light short weapon doesn't drag the ship in but a heavy one does. Point defense doesn't
# count unless it is all there is.
static func best_engagement_range(all_weapons: Array[Weapon]) -> float:
	var weapons := CombatTactics.range_weapons(all_weapons)
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
			var d: float = CombatTactics.edge_distance(own_position, c)
			if d <= nearest_dist:
				nearest_dist = d
				nearest = c
	return nearest

static func pick_autofire_target(order: Order, candidates: Array, own_position: Vector2, max_range: float, idle: Node2D = null) -> Node2D:
	if order.type == Order.Type.ATTACK_TARGET:
		return order.target_ship if is_instance_valid(order.target_ship) else null
	if (order.type == Order.Type.HOLD or order.type == Order.Type.HOLD_POSITION) and idle != null and CombatTactics.edge_distance(own_position, idle) <= max_range:
		return idle
	return Ship.nearest_in_range(candidates, own_position, max_range)

# Mounts that can't bear on the primary target take any other enemy they can hit.
static func pick_mount_target(mount: WeaponMount, primary: Node2D, candidates: Array) -> Node2D:
	if primary != null and mount.can_engage(primary):
		return primary
	return mount.nearest_engageable(candidates)

static func _weapon_dps(weapon: Weapon) -> float:
	return CombatTactics.weapon_dps(weapon)
