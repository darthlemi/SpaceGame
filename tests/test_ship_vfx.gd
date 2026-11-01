extends RefCounted

const ShipScene = preload("res://scenes/ship/ship.tscn")

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_should_emit_smoke(failures)
	return failures

static func _check_should_emit_smoke(failures: Array[String]) -> void:
	if ShipVfx.should_emit_smoke(0.5, 0.25):
		failures.append("should_emit_smoke: expected false when hp_ratio is above threshold")
	if not ShipVfx.should_emit_smoke(0.25, 0.25):
		failures.append("should_emit_smoke: expected true when hp_ratio equals threshold (inclusive)")
	if not ShipVfx.should_emit_smoke(0.1, 0.25):
		failures.append("should_emit_smoke: expected true when hp_ratio is below threshold")

# Integration test: needs a live SceneTree for ShipVfx._ready()'s get_parent()/$ node
# resolution to actually run -- see tests/test_ship.gd's run_async note.
static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var ship: Ship = ShipScene.instantiate()
	tree.root.add_child(ship)
	await tree.process_frame

	var vfx: ShipVfx = ship.get_node("VFX")
	var polygon: Polygon2D = ship.get_node("Polygon2D")
	var smoke: CPUParticles2D = vfx.get_node("SmokeTrail")

	ship.hull.apply_damage(10.0)

	if not polygon.modulate.is_equal_approx(vfx.flash_color):
		failures.append("ShipVfx: expected polygon.modulate to flash immediately on damage, got %s" % polygon.modulate)
	if smoke.emitting:
		failures.append("ShipVfx: expected SmokeTrail not emitting while hp_ratio is above low_hp_threshold")

	var engine_trail: CPUParticles2D = vfx.get_node("EngineTrail")
	if engine_trail.emitting:
		failures.append("ShipVfx: expected EngineTrail not emitting before any movement")

	# Drive ShipVfx._physics_process directly (same pattern as
	# tests/test_weapon_mount.gd's direct mount._physics_process(0.5) call)
	# rather than ticking the tree and relying on Ship's own AI steering --
	# Order.hold()'s loiter behavior never truly settles to zero velocity,
	# so it can't be used to exercise the "stopped" case.
	ship.velocity = Vector2(50, 0)
	vfx._physics_process(0.016)
	if not engine_trail.emitting:
		failures.append("ShipVfx: expected EngineTrail emitting once ship.velocity exceeds ENGINE_TRAIL_SPEED_THRESHOLD")

	ship.velocity = Vector2.ZERO
	vfx._physics_process(0.016)
	if engine_trail.emitting:
		failures.append("ShipVfx: expected EngineTrail not emitting once ship.velocity drops back to zero")

	ship.hull.apply_damage(ship.hull.max_hp * 0.8)
	if not smoke.emitting:
		failures.append("ShipVfx: expected SmokeTrail emitting once hp_ratio drops at/below low_hp_threshold")

	if is_instance_valid(ship) and not ship.is_queued_for_deletion():
		ship.queue_free()

	await _check_explosion_on_destroyed(tree, failures)

	return failures

static func _check_explosion_on_destroyed(tree: SceneTree, failures: Array[String]) -> void:
	var ship: Ship = ShipScene.instantiate()
	tree.root.add_child(ship)
	await tree.process_frame

	var last_position: Vector2 = ship.global_position
	var explosion_script: Script = preload("res://scripts/vfx/explosion.gd")
	var explosions_before := tree.root.get_children().filter(func(c): return c.get_script() == explosion_script).size()

	ship.hull.apply_damage(ship.hull.max_hp)

	var explosions_after: Array = tree.root.get_children().filter(func(c): return c.get_script() == explosion_script)
	if explosions_after.size() != explosions_before + 1:
		failures.append("ShipVfx: expected exactly one new explosion added to the ship's parent on hull.destroyed, got %d new" % (explosions_after.size() - explosions_before))
	elif not explosions_after[explosions_after.size() - 1].global_position.is_equal_approx(last_position):
		failures.append("ShipVfx: expected explosion spawned at the ship's last position %s, got %s" % [last_position, explosions_after[explosions_after.size() - 1].global_position])

	for e in explosions_after:
		if is_instance_valid(e):
			e.queue_free()
