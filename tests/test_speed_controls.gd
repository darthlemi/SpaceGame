extends RefCounted

const SpeedControlsScene = preload("res://scenes/ui/speed_controls.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var scene: Control = SpeedControlsScene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame

	if not is_equal_approx(Engine.time_scale, 1.0):
		failures.append("expected default time_scale to be 1.0, got %s" % Engine.time_scale)
	if tree.paused:
		failures.append("expected tree to start unpaused")

	var speed_3x: Button = scene.get_node("Speed3xButton")
	var speed_5x: Button = scene.get_node("Speed5xButton")
	var pause_button: Button = scene.get_node("PauseButton")
	var paused_label: Label = scene.get_node("PausedLabel")

	speed_3x.pressed.emit()
	if not is_equal_approx(Engine.time_scale, 3.0):
		failures.append("expected 3x button to set time_scale to 3.0, got %s" % Engine.time_scale)

	speed_5x.pressed.emit()
	if not is_equal_approx(Engine.time_scale, 5.0):
		failures.append("expected 5x button to set time_scale to 5.0, got %s" % Engine.time_scale)

	pause_button.pressed.emit()
	if not tree.paused:
		failures.append("expected pause button to pause the tree")

	await tree.process_frame
	if not paused_label.visible:
		failures.append("expected PAUSED label to be visible while paused")

	pause_button.pressed.emit()
	if tree.paused:
		failures.append("expected pause button to unpause the tree on second press")

	scene._unhandled_input(InputEventKey.new())
	if tree.paused:
		failures.append("expected a non-space key event to be ignored")

	var space_event := InputEventKey.new()
	space_event.keycode = KEY_SPACE
	space_event.pressed = true
	scene._unhandled_input(space_event)
	if not tree.paused:
		failures.append("expected spacebar to pause the tree")

	tree.paused = false
	Engine.time_scale = 1.0
	scene.queue_free()
	return failures
