extends Node2D

const ShipScene = preload("res://scenes/ship/ship.tscn")
const PLAYER_GROUP := &"player_fleet"
const ENEMY_GROUP := &"enemy_fleet"

@export var player_spawn_points: Array[Vector2] = [Vector2(200, 200), Vector2(200, 300), Vector2(200, 400)]
@export var enemy_spawn_points: Array[Vector2] = [Vector2(800, 200), Vector2(800, 300), Vector2(800, 400)]

@onready var fleet_commander: FleetCommander = $FleetCommander
@onready var result_label: Label = $ResultLabel

var player_ships: Array[Ship] = []
var enemy_ships: Array[Ship] = []
var _resolved := false

func _ready() -> void:
	result_label.visible = false
	player_ships = _spawn_fleet(player_spawn_points, PLAYER_GROUP, ENEMY_GROUP, 0.0)
	enemy_ships = _spawn_fleet(enemy_spawn_points, ENEMY_GROUP, PLAYER_GROUP, PI)

	# Ships are instantiated dynamically here rather than as static scene children, so
	# their own _ready() (which resolves @onready hull/shield/engine) hasn't run yet at
	# this point in the same frame -- wait for it before touching ship.hull below. See
	# tests/test_ship.gd's run_async note for the general rule this follows.
	await get_tree().process_frame

	for ship in player_ships:
		ship.hull.destroyed.connect(_on_ship_destroyed.bind(PLAYER_GROUP))
	for ship in enemy_ships:
		ship.hull.destroyed.connect(_on_ship_destroyed.bind(ENEMY_GROUP))
		var ai := AIController.new()
		ship.add_child(ai)
		ai.setup(ship, PLAYER_GROUP)

	fleet_commander.setup(player_ships, ENEMY_GROUP)

func _spawn_fleet(points: Array[Vector2], own_group: StringName, opposing_group: StringName, facing_rotation: float) -> Array[Ship]:
	var spawned: Array[Ship] = []
	for point in points:
		var ship: Ship = ShipScene.instantiate()
		add_child(ship)
		ship.global_position = point
		ship.rotation = facing_rotation
		ship.enemy_group = opposing_group
		ship.add_to_group(own_group)
		spawned.append(ship)
	return spawned

func _on_ship_destroyed(dying_group: StringName) -> void:
	if _resolved:
		return
	var remaining := 0
	for member in get_tree().get_nodes_in_group(dying_group):
		if is_instance_valid(member) and not member.is_queued_for_deletion():
			remaining += 1
	if remaining == 0:
		_show_result("Defeat" if dying_group == PLAYER_GROUP else "Victory")

func _show_result(text: String) -> void:
	_resolved = true
	result_label.text = text
	result_label.visible = true
	get_tree().paused = true
