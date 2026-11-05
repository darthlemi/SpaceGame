class_name CombatTactics
extends RefCounted

enum Tactic { PARK, RUN }
enum RunPhase { INBOUND, BREAK }

# Fixed forward weapons at or under this arc can't track, so the ship flies them at the target.
const NARROW_ARC_DEGREES := 30.0
# Share of range-weapon dps that must be narrow-arc for the ship to make attack runs.
const RUN_DPS_SHARE := 0.5
# Slower ships can't turn out of a run in time, so they park instead.
const RUN_MIN_TURN_RATE := 3.0
# Break off at this fraction of run range (or the hull floor, whichever is larger).
const RUN_BREAK_FRACTION := 0.35
# Turn back in once the ship has opened out to this fraction of run range.
const RUN_RESET_FRACTION := 0.9
# Seconds of closing speed added to the break distance: a fast ship turns away before it rams.
const RUN_BREAK_LEAD_TIME := 0.8
# Within this many pixels of its latched break point, a ship counts as out and turns back in.
const RUN_BREAK_ARRIVAL_RADIUS := 40.0
# Extra room beyond the enemy's reach when kiting.
const KITE_MARGIN := 40.0
# Radians between neighbouring attackers' approach bearings.
const SPREAD_STEP := 0.6
# Allies closer than this many own hit radii push each other apart.
const SEPARATION_RADIUS_FACTOR := 2.5
# Pixels added to the station point at full push.
const SEPARATION_STRENGTH := 60.0

# Target scoring; each term is in "points", higher total wins.
const DIST_WEIGHT := 1.0
const TURN_WEIGHT := 2.0
const MATCH_WEIGHT := 1.5
const LOW_HULL_WEIGHT := 3.0
const REFERENCE_DPS := 20.0
const STICKY_BONUS := 2.0
# Seconds between re-picks; in between a ship keeps its target while it is valid.
const RETARGET_INTERVAL := 0.5

# Point defense shoots missiles and drones, so it says nothing about how a ship should fight
# a hull. A PD-only ship keeps them so it still has something to close to.
static func range_weapons(weapons: Array[Weapon]) -> Array[Weapon]:
	var kept: Array[Weapon] = []
	for weapon in weapons:
		if not weapon.point_defense:
			kept.append(weapon)
	return kept if not kept.is_empty() else weapons

# Untyped target: callers pass nodes that may have been freed or lack get_hit_radius.
static func edge_distance(from: Vector2, target) -> float:
	var radius: float = target.get_hit_radius() if target.has_method("get_hit_radius") else 0.0
	return maxf(from.distance_to(target.global_position) - radius, 0.0)

static func threat_range(weapons: Array[Weapon]) -> float:
	var longest := 0.0
	for weapon in weapons:
		if not weapon.point_defense:
			longest = maxf(longest, weapon.weapon_range)
	return longest

# Dps share of narrow-arc weapons among the range weapons: how much the ship must point its nose.
static func narrow_share(weapons: Array[Weapon]) -> float:
	var total_dps := 0.0
	var narrow_dps := 0.0
	for weapon in range_weapons(weapons):
		var dps := weapon_dps(weapon)
		total_dps += dps
		if weapon.fire_arc_degrees <= NARROW_ARC_DEGREES:
			narrow_dps += dps
	return narrow_dps / total_dps if total_dps > 0.0 else 0.0

static func tactic_for(weapons: Array[Weapon], turn_rate: float) -> Tactic:
	if turn_rate < RUN_MIN_TURN_RATE:
		return Tactic.PARK
	if narrow_share(weapons) >= RUN_DPS_SHARE:
		return Tactic.RUN
	return Tactic.PARK

# Hysteresis between the two thresholds, so the ship doesn't flip phase every tick.
static func next_run_phase(phase: RunPhase, edge_dist: float, run_range: float, hull_floor: float) -> RunPhase:
	if phase == RunPhase.INBOUND and edge_dist <= maxf(run_range * RUN_BREAK_FRACTION, hull_floor):
		return RunPhase.BREAK
	if phase == RunPhase.BREAK and edge_dist >= run_range * RUN_RESET_FRACTION:
		return RunPhase.INBOUND
	return phase

# Sit just outside an enemy's reach when we out-range it and can keep the gap by speed.
static func kite_standoff(own_standoff: float, own_reach: float, enemy_threat: float, own_speed: float, enemy_speed: float) -> float:
	if enemy_threat <= 0.0:
		return own_standoff
	var kite_at := enemy_threat + KITE_MARGIN
	if kite_at < own_reach and own_speed >= enemy_speed:
		return maxf(own_standoff, kite_at)
	return own_standoff

static func approach_bearing(base_bearing: float, slot: int, count: int) -> float:
	return base_bearing + (float(slot) - float(count - 1) * 0.5) * SPREAD_STEP

static func separation_push(own_pos: Vector2, ally_positions: Array[Vector2], radius: float) -> Vector2:
	var push := Vector2.ZERO
	for ally_pos in ally_positions:
		var d := own_pos.distance_to(ally_pos)
		if d < 0.01 or d >= radius:
			continue
		push += (own_pos - ally_pos).normalized() * (1.0 - d / radius)
	return push

static func weapon_dps(weapon: Weapon) -> float:
	return weapon.damage * weapon.fire_rate * weapon.submissile_count

# Positive: the loadout does better against shields that are up (dps-weighted, in [-1, 1]).
static func loadout_shield_bias(weapons: Array[Weapon]) -> float:
	var total_dps := 0.0
	var weighted := 0.0
	for weapon in range_weapons(weapons):
		var dps := weapon_dps(weapon)
		total_dps += dps
		weighted += dps * (weapon.shield_mult - weapon.hull_mult - weapon.pierce_pct)
	return clampf(weighted / total_dps, -1.0, 1.0) if total_dps > 0.0 else 0.0

# Untyped target: it may have been freed (or be about to be) while candidates are scored.
static func score_target(own_pos: Vector2, own_rotation: float, turn_rate: float, shield_bias: float, narrow: float, target, is_current: bool) -> float:
	if not is_instance_valid(target) or (target is Node and target.is_queued_for_deletion()):
		return -INF
	var score := -edge_distance(own_pos, target) / 100.0 * DIST_WEIGHT
	var angle := absf(angle_difference(own_rotation, own_pos.angle_to_point(target.global_position)))
	score -= angle / maxf(turn_rate, 0.01) * narrow * TURN_WEIGHT
	# Bare nodes (no shield or hull children) score as shieldless and undamaged.
	var shield_ratio := 0.0
	if target.shield != null and target.shield.max_shield > 0.0:
		shield_ratio = target.shield.current_shield / target.shield.max_shield
	score += shield_bias * (shield_ratio - 0.5) * 2.0 * MATCH_WEIGHT
	var hull_ratio := 1.0
	if target.hull != null and target.hull.max_hp > 0.0:
		hull_ratio = target.hull.current_hp / target.hull.max_hp
	var target_dps := 0.0
	if target.has_method("working_weapons"):
		for weapon in range_weapons(target.working_weapons()):
			target_dps += weapon_dps(weapon)
	score += (1.0 - hull_ratio) * LOW_HULL_WEIGHT * clampf(target_dps / REFERENCE_DPS, 0.25, 2.0)
	if is_current:
		score += STICKY_BONUS
	return score

static func pick_target(ship: Ship, candidates: Array, current) -> Node2D:
	var weapons := ship.working_weapons()
	var bias := loadout_shield_bias(weapons)
	var narrow := narrow_share(weapons)
	var best: Node2D = null
	var best_score := -INF
	for candidate in candidates:
		if not is_instance_valid(candidate) or not candidate is Node2D:
			continue
		var score := score_target(ship.global_position, ship.rotation, ship.engine.turn_rate if ship.engine != null else 0.0, bias, narrow, candidate, candidate == current)
		if score > best_score:
			best_score = score
			best = candidate
	return best
