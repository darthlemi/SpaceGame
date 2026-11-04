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

	var row: Control = scene.get_node("Row")
	var pause_button: Button = scene.get_node("Row/PauseButton")
	var speed_1x: Button = scene.get_node("Row/Speed1xButton")
	var speed_3x: Button = scene.get_node("Row/Speed3xButton")
	var speed_5x: Button = scene.get_node("Row/Speed5xButton")

	# Clicks on the panel must not fall through to fleet selection / the campaign map.
	var background: Control = scene.get_node("Background")
	if background.mouse_filter != Control.MOUSE_FILTER_STOP:
		failures.append("expected the Background panel to stop mouse input, got filter %s" % background.mouse_filter)

	# "||" and "5x" must not clip: the row's minimum size has to fit inside the panel.
	var row_end := row.position + row.get_combined_minimum_size()
	if row_end.x > background.size.x or row_end.y > background.size.y:
		failures.append("expected Row (ends at %s) to fit inside Background %s" % [row_end, background.size])

	speed_3x.pressed.emit()
	if not is_equal_approx(Engine.time_scale, 3.0):
		failures.append("expected 3x button to set time_scale to 3.0, got %s" % Engine.time_scale)

	speed_5x.pressed.emit()
	if not is_equal_approx(Engine.time_scale, 5.0):
		failures.append("expected 5x button to set time_scale to 5.0, got %s" % Engine.time_scale)

	pause_button.pressed.emit()
	if not tree.paused:
		failures.append("expected pause button to pause the tree")

	# Paused: pause lit, the resume speed (5x) shows the hover look instead of pressed.
	await tree.process_frame
	if not pause_button.button_pressed:
		failures.append("expected pause button to show pressed while paused")
	if speed_5x.button_pressed:
		failures.append("expected 5x button not pressed while paused")
	if not speed_5x.has_theme_stylebox_override("normal"):
		failures.append("expected 5x (resume speed) to get the hover look while paused")
	if speed_1x.has_theme_stylebox_override("normal"):
		failures.append("expected 1x (not the resume speed) to have no stylebox override")

	# Clicking a speed while paused unpauses at that speed and clears the resume look.
	speed_3x.pressed.emit()
	await tree.process_frame
	if tree.paused:
		failures.append("expected a speed button to unpause the tree")
	if not is_equal_approx(Engine.time_scale, 3.0):
		failures.append("expected 3x while paused to set time_scale to 3.0, got %s" % Engine.time_scale)
	if not speed_3x.button_pressed:
		failures.append("expected 3x button pressed after resuming at 3x")
	if pause_button.button_pressed:
		failures.append("expected pause button not pressed after resuming")
	if speed_5x.has_theme_stylebox_override("normal"):
		failures.append("expected 5x hover override cleared after resuming at 3x")
	if speed_3x.has_theme_stylebox_override("normal"):
		failures.append("expected 3x to have no override while running")

	pause_button.pressed.emit()
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
	await tree.process_frame
	if not pause_button.button_pressed:
		failures.append("expected pause button to show pressed after spacebar pause")

	tree.paused = false
	Engine.time_scale = 1.0
	scene.queue_free()
	return failures
