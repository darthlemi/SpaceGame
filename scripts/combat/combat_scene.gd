extends Node2D

const ShipScene = preload("res://scenes/ship/ship.tscn")
const PLAYER_GROUP := &"player_fleet"
const ENEMY_GROUP := &"enemy_fleet"

@export var player_spawn_points: Array[Vector2] = [Vector2(200, 200), Vector2(200, 300), Vector2(200, 400)]
@export var enemy_spawn_points: Array[Vector2] = [Vector2(800, 200), Vector2(800, 300), Vector2(800, 400)]

@onready var fleet_commander: FleetCommander = $FleetCommander
@onready var result_label: Label = $ResultLabel
@onready var debug_console: Control = $DebugConsole/Panel

var player_ships: Array[Ship] = []
var enemy_ships: Array[Ship] = []
var _resolved := false

func _ready() -> void:
	result_label.visible = false
	if CampaignState.active_enemy_fleet != null:
		player_ships = _spawn_fleet_from_data(CampaignState.player_fleet, player_spawn_points, PLAYER_GROUP, ENEMY_GROUP, 0.0)
		enemy_ships = _spawn_fleet_from_data(CampaignState.active_enemy_fleet, enemy_spawn_points, ENEMY_GROUP, PLAYER_GROUP, PI)
	else:
		player_ships = _spawn_fleet(player_spawn_points, PLAYER_GROUP, ENEMY_GROUP, 0.0)
		enemy_ships = _spawn_fleet(enemy_spawn_points, ENEMY_GROUP, PLAYER_GROUP, PI)

	# Ships are instantiated dynamically here rather than as static scene children, so
	# their own _ready() (which resolves @onready hull/shield/engine) hasn't run yet at
	# this point in the same frame -- wait for it before touching ship.hull below. See
	# tests/test_ship.gd's run_async note for the general rule this follows.
	await get_tree().process_frame

	if CampaignState.active_enemy_fleet != null:
		_apply_fleet_data(player_ships, CampaignState.player_fleet)
		_apply_fleet_data(enemy_ships, CampaignState.active_enemy_fleet)

	for ship in player_ships:
		ship.hull.destroyed.connect(_on_ship_destroyed.bind(PLAYER_GROUP))
	for ship in enemy_ships:
		ship.hull.destroyed.connect(_on_ship_destroyed.bind(ENEMY_GROUP))
		_wire_ai(ship)

	fleet_commander.setup(player_ships, ENEMY_GROUP)
	debug_console.command_entered.connect(_on_debug_command)

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

func _spawn_fleet_from_data(fleet_data: CampaignFleet, points: Array[Vector2], own_group: StringName, opposing_group: StringName, facing_rotation: float) -> Array[Ship]:
	var spawned: Array[Ship] = []
	for i in fleet_data.ship_compositions.size():
		var point: Vector2 = points[i % points.size()]
		var ship: Ship = ShipScene.instantiate()
		add_child(ship)
		ship.global_position = point
		ship.rotation = facing_rotation
		ship.enemy_group = opposing_group
		ship.add_to_group(own_group)
		spawned.append(ship)
	return spawned

func _apply_fleet_data(ships: Array[Ship], fleet_data: CampaignFleet) -> void:
	for i in ships.size():
		var comp: Dictionary = fleet_data.ship_compositions[i]
		ships[i].hull.max_hp = comp["max_hp"]
		ships[i].hull.current_hp = comp["current_hp"]
		ships[i].shield.max_shield = comp["max_shield"]
		ships[i].shield.current_shield = comp["current_shield"]

func _wire_ai(ship: Ship) -> void:
	var ai := AIController.new()
	ship.add_child(ai)
	ai.setup(ship, PLAYER_GROUP)

func _on_debug_command(command: String) -> void:
	match command:
		"AddFriend":
			await _spawn_extra_ship(PLAYER_GROUP, ENEMY_GROUP, 0.0, player_ships)
		"AddEnemy":
			await _spawn_extra_ship(ENEMY_GROUP, PLAYER_GROUP, PI, enemy_ships)
		"GodMode":
			_toggle_god_mode()
		"KillAll":
			_kill_all_enemies()

func _spawn_extra_ship(own_group: StringName, opposing_group: StringName, facing_rotation: float, fleet: Array[Ship]) -> void:
	var spawn_base := _fleet_centroid(fleet)
	var ship: Ship = ShipScene.instantiate()
	add_child(ship)
	ship.global_position = spawn_base + Vector2(randf_range(-60.0, 60.0), randf_range(-60.0, 60.0))
	ship.rotation = facing_rotation
	ship.enemy_group = opposing_group
	ship.add_to_group(own_group)

	await get_tree().process_frame

	ship.hull.destroyed.connect(_on_ship_destroyed.bind(own_group))
	fleet.append(ship)
	if own_group == ENEMY_GROUP:
		_wire_ai(ship)

func _fleet_centroid(fleet: Array[Ship]) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for ship in fleet:
		if is_instance_valid(ship):
			sum += ship.global_position
			count += 1
	return sum / count if count > 0 else Vector2(500, 300)

func _toggle_god_mode() -> void:
	for ship in fleet_commander.selected_ships:
		if is_instance_valid(ship):
			ship.hull.invulnerable = not ship.hull.invulnerable

func _kill_all_enemies() -> void:
	for ship in enemy_ships.duplicate():
		if is_instance_valid(ship):
			ship.hull.invulnerable = false
			ship.hull.apply_damage(ship.hull.max_hp)

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
	if CampaignState.active_enemy_fleet != null:
		call_deferred("_report_to_campaign")

func _report_to_campaign() -> void:
	CampaignState.resolve_engagement(_collect_survivor_data(player_ships), _collect_survivor_data(enemy_ships))
	if CampaignState.player_fleet == null:
		return
	if CampaignState.player_fleet.is_destroyed():
		get_tree().change_scene_to_file("res://scenes/ui/game_over.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/campaign/campaign_scene.tscn")

func _collect_survivor_data(ships: Array[Ship]) -> Array[Dictionary]:
	var survivors: Array[Dictionary] = []
	for ship in ships:
		if is_instance_valid(ship) and not ship.hull.is_destroyed():
			survivors.append({
				"max_hp": ship.hull.max_hp,
				"current_hp": ship.hull.current_hp,
				"max_shield": ship.shield.max_shield,
				"current_shield": ship.shield.current_shield,
			})
	return survivors

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
