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
# Extra room beyond the enemy's reach when kiting.
const KITE_MARGIN := 40.0
# Radians between neighbouring attackers' approach bearings.
const SPREAD_STEP := 0.6
# Allies closer than this many own hit radii push each other apart.
const SEPARATION_RADIUS_FACTOR := 2.5
# Pixels added to the station point at full push.
const SEPARATION_STRENGTH := 60.0

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

static func tactic_for(weapons: Array[Weapon], turn_rate: float) -> Tactic:
	if turn_rate < RUN_MIN_TURN_RATE:
		return Tactic.PARK
	var total_dps := 0.0
	var narrow_dps := 0.0
	for weapon in range_weapons(weapons):
		var dps := weapon_dps(weapon)
		total_dps += dps
		if weapon.fire_arc_degrees <= NARROW_ARC_DEGREES:
			narrow_dps += dps
	if total_dps > 0.0 and narrow_dps >= total_dps * RUN_DPS_SHARE:
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
