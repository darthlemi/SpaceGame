extends SceneTree

func _init() -> void:
	var test_scripts := [
		preload("res://tests/test_order.gd"),
	]
	var total_failures := 0
	for script in test_scripts:
		var failures: Array[String] = script.run()
		for f in failures:
			print("FAIL [%s]: %s" % [script.resource_path, f])
		total_failures += failures.size()
	if total_failures == 0:
		print("All tests passed.")
	else:
		print("%d test failure(s)." % total_failures)
	quit(1 if total_failures > 0 else 0)
