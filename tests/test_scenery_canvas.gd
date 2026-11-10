extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	var canvas := SceneryCanvas.new()
	canvas.size = Vector2(800, 800)
	var scenery := [
		{"type": "planet", "texture": "planet_gas_purple.png", "pos": [1600.0, 1600.0], "scale": 3.5, "layer": "mid_distance"},
		{"type": "asteroid", "texture": "v1_round_a.png", "pos": [400.0, 400.0], "scale": 1.5, "layer": "foreground"},
	]
	canvas.set_scenery(scenery, null)

	var moved_signals: Array = []
	canvas.scenery_moved.connect(func(index: int, pos: Vector2): moved_signals.append([index, pos]))
	var selected_signals: Array[int] = []
	canvas.scenery_selected.connect(func(index: int): selected_signals.append(index))

	var point := canvas._world_to_canvas(Vector2(1600.0, 1600.0))
	canvas.handle_press(point, MOUSE_BUTTON_LEFT)
	if selected_signals != [0] or canvas.selected_index != 0:
		failures.append("scenery canvas: expected index 0 selected at the planet's point, got %s" % [selected_signals])
	canvas.handle_drag(point + Vector2(40.0, 10.0))
	if moved_signals.size() != 1 or moved_signals[0][0] != 0:
		failures.append("scenery canvas: expected a scenery_moved signal for index 0, got %s" % [moved_signals])
	var moved_world: Vector2 = moved_signals[0][1]
	if moved_world.x < 0.0 or moved_world.x > SceneryCanvas.SPACE.x or moved_world.y < 0.0 or moved_world.y > SceneryCanvas.SPACE.y:
		failures.append("scenery canvas: expected the moved position clamped inside SPACE, got %s" % moved_world)
	canvas.handle_release()

	var far_point := canvas._world_to_canvas(Vector2(10.0, 10.0))
	canvas.handle_press(far_point, MOUSE_BUTTON_LEFT)
	if selected_signals.size() != 1:
		failures.append("scenery canvas: expected a click far from any item to not select, got %s selections" % selected_signals.size())
	canvas.queue_free()
	return failures
