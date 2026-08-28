extends SceneTree

func _initialize() -> void:
	_run_all()

func _run_all() -> void:
	var test_scripts := [
		preload("res://tests/test_order.gd"),
		preload("res://tests/test_hull.gd"),
		preload("res://tests/test_shield.gd"),
		preload("res://tests/test_ship_engine.gd"),
		preload("res://tests/test_weapon_mount.gd"),
		preload("res://tests/test_ship.gd"),
		preload("res://tests/test_ai_controller_state.gd"),
		preload("res://tests/test_formation.gd"),
		preload("res://tests/test_fleet_commander.gd"),
		preload("res://tests/test_debug_console.gd"),
	]
	var total_failures := 0
	for script in test_scripts:
		var failures: Array[String] = script.run()
		for f in failures:
			print("FAIL [%s]: %s" % [script.resource_path, f])
		total_failures += failures.size()

	# Async integration test: requires a live SceneTree and a process frame for
	# _ready() to actually run, so it can't use the synchronous run() pattern above.
	var ship_test = preload("res://tests/test_ship.gd")
	var async_failures: Array[String] = await ship_test.run_async(self)
	for f in async_failures:
		print("FAIL [%s]: %s" % [ship_test.resource_path, f])
	total_failures += async_failures.size()

	var ai_targeting_test = preload("res://tests/test_ai_controller_targeting.gd")
	var ai_targeting_failures: Array[String] = await ai_targeting_test.run_async(self)
	for f in ai_targeting_failures:
		print("FAIL [%s]: %s" % [ai_targeting_test.resource_path, f])
	total_failures += ai_targeting_failures.size()

	var combat_scene_test = preload("res://tests/test_combat_scene.gd")
	var combat_scene_failures: Array[String] = await combat_scene_test.run_async(self)
	for f in combat_scene_failures:
		print("FAIL [%s]: %s" % [combat_scene_test.resource_path, f])
	total_failures += combat_scene_failures.size()

	if total_failures == 0:
		print("All tests passed.")
	else:
		print("%d test failure(s)." % total_failures)
	quit(1 if total_failures > 0 else 0)
