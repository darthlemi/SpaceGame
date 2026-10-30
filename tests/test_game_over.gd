extends RefCounted

const GameOverScene = preload("res://scenes/ui/game_over.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var scene: Control = GameOverScene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame

	var label: Label = scene.get_node("Label")
	if label == null or label.text == "":
		failures.append("expected a non-empty game-over label")

	scene.queue_free()
	return failures
