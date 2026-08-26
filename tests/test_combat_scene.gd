extends RefCounted

const CombatSceneScene = preload("res://scenes/combat/combat_scene.tscn")

# INTEGRATION TEST NOTE (see tests/test_ship.gd for the pattern this follows):
# CombatScene's _ready() wires up all the controller nodes via setup() calls and
# connects hull.destroyed signals -- none of that runs synchronously on
# instantiate() or add_child(). It fires on the *next process frame* after the
# scene enters the live SceneTree, so this suite must be async (run_async) and
# await tree.process_frame before asserting on any of it.
#
# What remains UNVERIFIED here (needs a real editor/F6 playtest): all visual and
# input-driven behavior -- right-click move, left-click attack, Tab toggling,
# WASD+Space direct pilot, the AI actually approaching/engaging/retreating,
# projectiles visibly flying and hitting, and the Victory/Defeat label actually
# being readable on screen.

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(scene)

	await tree.process_frame

	if not scene.is_inside_tree():
		failures.append("run_async: expected combat scene is_inside_tree() true after a process frame")

	var player: Ship = scene.player_ship
	var enemy: Ship = scene.enemy_ship

	if player == null:
		failures.append("run_async: expected player_ship resolved by @onready, got null")
	if enemy == null:
		failures.append("run_async: expected enemy_ship resolved by @onready, got null")
	if player != null and enemy != null and player == enemy:
		failures.append("run_async: expected player_ship and enemy_ship to be distinct instances")

	# Use a loose distance tolerance rather than is_equal_approx: a physics tick can
	# land inside the awaited process_frame and nudge a ship a few pixels toward its
	# target before this assertion runs, which made an exact-position check flaky.
	const SPAWN_POSITION_TOLERANCE := 20.0
	if player != null and player.global_position.distance_to(Vector2(200, 300)) > SPAWN_POSITION_TOLERANCE:
		failures.append("run_async: expected player_ship near (200, 300), got %s" % player.global_position)
	if enemy != null and enemy.global_position.distance_to(Vector2(800, 300)) > SPAWN_POSITION_TOLERANCE:
		failures.append("run_async: expected enemy_ship near (800, 300), got %s" % enemy.global_position)

	if scene.result_label == null:
		failures.append("run_async: expected result_label resolved by @onready, got null")
	elif scene.result_label.visible:
		failures.append("run_async: expected result_label.visible == false immediately after _ready()")

	# Verify controller wiring: each controller's setup() call in _ready() should
	# have run and assigned the correct ship instances.
	if scene.ai_controller == null or scene.ai_controller.ship != enemy:
		failures.append("run_async: expected ai_controller.ship == enemy_ship")
	if scene.ai_controller == null or scene.ai_controller.enemy != player:
		failures.append("run_async: expected ai_controller.enemy == player_ship")

	if scene.rts_commander == null or scene.rts_commander.ship != player:
		failures.append("run_async: expected rts_commander.ship == player_ship")
	if scene.rts_commander == null or scene.rts_commander.enemy != enemy:
		failures.append("run_async: expected rts_commander.enemy == enemy_ship")

	if scene.direct_pilot == null or scene.direct_pilot.ship != player:
		failures.append("run_async: expected direct_pilot.ship == player_ship")
	if scene.direct_pilot == null or scene.direct_pilot.enemy != enemy:
		failures.append("run_async: expected direct_pilot.enemy == enemy_ship")

	if scene.control_toggle == null or scene.control_toggle.ship != player:
		failures.append("run_async: expected control_toggle.ship == player_ship")

	# Exercise the real win/lose wiring end-to-end: destroying the enemy's hull
	# should trigger enemy_ship.hull.destroyed -> scene._on_enemy_destroyed()
	# (connected in _ready()) -> "Victory" shown on result_label.
	if enemy != null and enemy.hull != null:
		enemy.hull.apply_damage(enemy.hull.max_hp)
		if scene.result_label != null:
			if scene.result_label.text != "Victory":
				failures.append("run_async: expected result_label.text == 'Victory' after enemy hull destroyed, got '%s'" % scene.result_label.text)
			if not scene.result_label.visible:
				failures.append("run_async: expected result_label.visible == true after enemy hull destroyed")
	else:
		failures.append("run_async: expected enemy_ship.hull resolved, cannot exercise destroyed wiring")

	if is_instance_valid(scene) and not scene.is_queued_for_deletion():
		scene.queue_free()

	# Defeat path: mirror the Victory check above with a fresh scene instance so it
	# doesn't collide with/reuse state from the Victory assertions (the first scene's
	# tree is already paused by that point, which would confuse a shared-instance check).
	var defeat_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(defeat_scene)

	await tree.process_frame

	var defeat_player: Ship = defeat_scene.player_ship
	if defeat_player != null and defeat_player.hull != null:
		defeat_player.hull.apply_damage(defeat_player.hull.max_hp)
		if defeat_scene.result_label != null:
			if defeat_scene.result_label.text != "Defeat":
				failures.append("run_async: expected result_label.text == 'Defeat' after player hull destroyed, got '%s'" % defeat_scene.result_label.text)
			if not defeat_scene.result_label.visible:
				failures.append("run_async: expected result_label.visible == true after player hull destroyed")
	else:
		failures.append("run_async: expected player_ship.hull resolved on defeat_scene, cannot exercise destroyed wiring")

	if is_instance_valid(defeat_scene) and not defeat_scene.is_queued_for_deletion():
		defeat_scene.queue_free()
	# The tree-pause triggered by the Defeat result would otherwise freeze the test
	# runner's own process_frame loop for any tests that run after this one, so restore
	# it before returning control.
	tree.paused = false

	return failures
