extends RefCounted

const EwDrone = preload("res://scripts/drones/ew_drone.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var drone := EwDrone.new()
	var hull := Hull.new()
	hull.max_hp = 6.0
	hull._ready()
	var shield := Shield.new()
	shield.max_shield = 0.0
	shield._ready()
	drone.hull = hull
	drone.shield = shield
	drone.aura_range = 150.0
	drone.regen_debuff_mult = 0.5
	drone.global_position = Vector2.ZERO

	var target := Ship.new()
	var target_hull := Hull.new()
	target_hull.max_hp = 100.0
	target_hull._ready()
	var target_shield := Shield.new()
	target_shield.max_shield = 50.0
	target_shield._ready()
	target.hull = target_hull
	target.shield = target_shield
	target.global_position = Vector2(50.0, 0.0)

	# EwDrone's _process_weapons() is exercised against an injected candidate
	# list (_test_candidates) rather than a live SceneTree group lookup, the
	# same tree-free pattern the rest of this codebase's Ship-adjacent unit
	# tests already use.
	drone._test_candidates = [target]
	drone._process_weapons()
	if not is_equal_approx(target.shield.regen_multiplier, 0.5):
		failures.append("_process_weapons: expected the nearest in-range enemy's shield.regen_multiplier debuffed to 0.5, got %s" % target.shield.regen_multiplier)

	hull.free()
	shield.free()
	drone.free()
	target_hull.free()
	target_shield.free()
	target.free()
	return failures
