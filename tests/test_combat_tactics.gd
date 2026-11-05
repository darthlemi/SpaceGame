extends RefCounted

class HullStub extends Node2D:
	func get_hit_radius() -> float:
		return 54.0

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_range_weapons(failures)
	_check_edge_distance(failures)
	_check_tactic(failures)
	_check_run_phase(failures)
	_check_kite(failures)
	_check_spread(failures)
	return failures

static func _weapon(weapon_range: float, damage: float, fire_rate: float, arc: float, pd: bool) -> Weapon:
	var weapon := Weapon.new()
	weapon.weapon_range = weapon_range
	weapon.damage = damage
	weapon.fire_rate = fire_rate
	weapon.fire_arc_degrees = arc
	weapon.point_defense = pd
	return weapon

static func _check_range_weapons(failures: Array[String]) -> void:
	var railgun := _weapon(500.0, 35.0, 0.25, 10.0, false)
	var pd := _weapon(150.0, 6.0, 3.0, 360.0, true)
	var mixed: Array[Weapon] = [railgun, pd]
	var kept := CombatTactics.range_weapons(mixed)
	if kept.size() != 1 or kept[0] != railgun:
		failures.append("range_weapons_excludes_pd: expected only the railgun, got %s" % [kept])
	var all_pd: Array[Weapon] = [pd, _weapon(120.0, 3.0, 6.0, 360.0, true)]
	if CombatTactics.range_weapons(all_pd).size() != 2:
		failures.append("range_weapons_all_pd_keeps_all: expected both PD weapons kept")

	var driver := _weapon(400.0, 14.0, 0.8, 120.0, false)
	var loud_pd := _weapon(150.0, 20.0, 5.0, 360.0, true)
	var driver_and_pd: Array[Weapon] = [driver, loud_pd]
	if not is_equal_approx(Ship.best_engagement_range(driver_and_pd), 400.0):
		failures.append("best_engagement_range_ignores_pd: expected 400, got %s" % Ship.best_engagement_range(driver_and_pd))
	if not is_equal_approx(CombatTactics.threat_range(driver_and_pd), 400.0):
		failures.append("threat_range: expected 400, got %s" % CombatTactics.threat_range(driver_and_pd))
	var none: Array[Weapon] = []
	if not is_zero_approx(CombatTactics.threat_range(none)):
		failures.append("threat_range: expected 0 for no weapons")
	if not is_zero_approx(CombatTactics.threat_range(all_pd)):
		failures.append("threat_range: expected 0 when every weapon is PD")

static func _check_edge_distance(failures: Array[String]) -> void:
	var big := HullStub.new()
	big.position = Vector2(300.0, 0.0)
	var d := CombatTactics.edge_distance(Vector2.ZERO, big)
	if not is_equal_approx(d, 246.0):
		failures.append("edge_distance_subtracts_radius: expected 246, got %s" % d)
	big.position = Vector2(20.0, 0.0)
	d = CombatTactics.edge_distance(Vector2.ZERO, big)
	if not is_zero_approx(d):
		failures.append("edge_distance_subtracts_radius: expected 0 inside the hull, got %s" % d)
	var plain := Node2D.new()
	plain.position = Vector2(300.0, 0.0)
	d = CombatTactics.edge_distance(Vector2.ZERO, plain)
	if not is_equal_approx(d, 300.0):
		failures.append("edge_distance_subtracts_radius: expected 300 without a radius, got %s" % d)
	big.free()
	plain.free()

static func _check_tactic(failures: Array[String]) -> void:
	var railgun: Array[Weapon] = [_weapon(500.0, 35.0, 0.25, 10.0, false)]
	if CombatTactics.tactic_for(railgun, 5.0) != CombatTactics.Tactic.RUN:
		failures.append("tactic_run_for_agile_narrow: expected RUN")
	if CombatTactics.tactic_for(railgun, 1.0) != CombatTactics.Tactic.PARK:
		failures.append("tactic_park_for_slow_narrow: expected PARK")
	var cannon: Array[Weapon] = [_weapon(300.0, 10.0, 2.0, 100.0, false)]
	if CombatTactics.tactic_for(cannon, 5.0) != CombatTactics.Tactic.PARK:
		failures.append("tactic_park_for_turrets: expected PARK")
	var mixed: Array[Weapon] = [_weapon(500.0, 35.0, 0.25, 10.0, false), _weapon(220.0, 16.0, 1.0, 90.0, false)]
	if CombatTactics.tactic_for(mixed, 5.0) != CombatTactics.Tactic.PARK:
		failures.append("tactic_mixed_below_share: expected PARK")
	var none: Array[Weapon] = []
	if CombatTactics.tactic_for(none, 5.0) != CombatTactics.Tactic.PARK:
		failures.append("tactic_for: expected PARK with no weapons")

static func _check_run_phase(failures: Array[String]) -> void:
	var inbound := CombatTactics.RunPhase.INBOUND
	var brk := CombatTactics.RunPhase.BREAK
	if CombatTactics.next_run_phase(inbound, 100.0, 500.0, 70.0) != brk:
		failures.append("run_phase_breaks_close: expected BREAK")
	if CombatTactics.next_run_phase(inbound, 300.0, 500.0, 70.0) != inbound:
		failures.append("run_phase_holds_inbound: expected INBOUND")
	if CombatTactics.next_run_phase(inbound, 60.0, 100.0, 70.0) != brk:
		failures.append("run_phase_hull_floor: expected BREAK at the floor for a short run range")
	if CombatTactics.next_run_phase(brk, 460.0, 500.0, 70.0) != inbound:
		failures.append("run_phase_resets_far: expected INBOUND")
	if CombatTactics.next_run_phase(brk, 300.0, 500.0, 70.0) != brk:
		failures.append("run_phase_holds_between: expected BREAK")

static func _check_kite(failures: Array[String]) -> void:
	var got := CombatTactics.kite_standoff(200.0, 400.0, 220.0, 280.0, 90.0)
	if not is_equal_approx(got, 260.0):
		failures.append("kite_outranged: expected 260, got %s" % got)
	got = CombatTactics.kite_standoff(320.0, 400.0, 220.0, 280.0, 90.0)
	if not is_equal_approx(got, 320.0):
		failures.append("kite_already_outside: expected 320, got %s" % got)
	got = CombatTactics.kite_standoff(200.0, 400.0, 220.0, 90.0, 280.0)
	if not is_equal_approx(got, 200.0):
		failures.append("kite_slower_does_not: expected 200, got %s" % got)
	got = CombatTactics.kite_standoff(200.0, 400.0, 450.0, 280.0, 90.0)
	if not is_equal_approx(got, 200.0):
		failures.append("kite_outranging_enemy_does_not: expected 200, got %s" % got)
	got = CombatTactics.kite_standoff(200.0, 400.0, 0.0, 280.0, 90.0)
	if not is_equal_approx(got, 200.0):
		failures.append("kite_unarmed_target: expected 200, got %s" % got)

static func _check_spread(failures: Array[String]) -> void:
	var expected := [-0.6, 0.0, 0.6]
	for slot in 3:
		var got := CombatTactics.approach_bearing(0.0, slot, 3)
		if not is_equal_approx(got, expected[slot]):
			failures.append("approach_bearing_spreads: slot %d expected %s, got %s" % [slot, expected[slot], got])
	if not is_equal_approx(CombatTactics.approach_bearing(1.2, 0, 1), 1.2):
		failures.append("approach_bearing_spreads: count 1 should leave the bearing unchanged")

	var far: Array[Vector2] = [Vector2(200.0, 0.0)]
	if CombatTactics.separation_push(Vector2.ZERO, far, 60.0) != Vector2.ZERO:
		failures.append("separation_none_when_clear: expected zero push")
	var near: Array[Vector2] = [Vector2(10.0, 0.0)]
	if CombatTactics.separation_push(Vector2.ZERO, near, 60.0).x >= 0.0:
		failures.append("separation_pushes_away: expected a push to -x")
	var stacked: Array[Vector2] = [Vector2.ZERO]
	if not CombatTactics.separation_push(Vector2.ZERO, stacked, 60.0).is_finite():
		failures.append("separation: expected a finite push for an ally at the same spot")
