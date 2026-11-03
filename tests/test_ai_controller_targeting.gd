extends RefCounted

const ShipScene = preload("res://scenes/ship/ship.tscn")

# Exercises the real group-membership resolution _physics_process depends on, which
# needs a live SceneTree -- see tests/test_ship.gd's run_async note for why this can't
# be a synchronous run() test.
static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var ai_ship: Ship = ShipScene.instantiate()
	ai_ship.global_position = Vector2(0, 0)
	ai_ship.enemy_group = &"test_targets"
	tree.root.add_child(ai_ship)

	var target_ship: Ship = ShipScene.instantiate()
	target_ship.global_position = Vector2(50, 0)
	target_ship.add_to_group("test_targets")
	tree.root.add_child(target_ship)

	var far_ship: Ship = ShipScene.instantiate()
	far_ship.global_position = Vector2(5000, 0)
	far_ship.add_to_group("test_targets")
	tree.root.add_child(far_ship)

	var controller := AIController.new()
	tree.root.add_child(controller)
	controller.setup(ai_ship, &"test_targets")

	# A headless frame can hold 0 physics ticks, so poll physics ticks (bounded) for
	# AIController._physics_process instead of assuming one process frame ran it.
	for i in 5:
		await tree.physics_frame
		if ai_ship.current_order.type == Order.Type.ATTACK_TARGET:
			break

	if ai_ship.current_order.type != Order.Type.ATTACK_TARGET:
		failures.append("AIController: expected ATTACK_TARGET order once a group member is in range, got %s" % ai_ship.current_order.type)
	elif ai_ship.current_order.target_ship != target_ship:
		failures.append("AIController: expected to target the nearest group member, got %s" % ai_ship.current_order.target_ship)

	ai_ship.queue_free()
	target_ship.queue_free()
	far_ship.queue_free()
	controller.queue_free()

	return failures
