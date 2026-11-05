extends Node2D

const ShipScene = preload("res://scenes/ship/ship_corvette.tscn")
const PLAYER_GROUP := &"player_fleet"
const ENEMY_GROUP := &"enemy_fleet"

@export var player_spawn_points: Array[Vector2] = [Vector2(400, 400), Vector2(400, 600), Vector2(400, 800)]
@export var enemy_spawn_points: Array[Vector2] = [Vector2(1600, 400), Vector2(1600, 600), Vector2(1600, 800)]

@onready var fleet_commander: FleetCommander = $FleetCommander
@onready var combat_camera: CombatCamera = $CombatCamera
@onready var result_label: Label = $UILayer/ResultLabel
@onready var debug_console: Control = $UILayer/DebugConsole/Panel
@onready var order_bar: OrderBar = $UILayer/OrderBar

var player_ships: Array[Ship] = []
var enemy_ships: Array[Ship] = []
# Comp index for each spawned ship, in spawn order; un-listed comps were held back.
var _player_spawned_indices: Array[int] = []
var _enemy_spawned_indices: Array[int] = []
var _player_won := false
var _resolved := false
# Tests inject a seeded rng before _ready.
var escape_rng: RandomNumberGenerator = null

func _ready() -> void:
	if escape_rng == null:
		escape_rng = RandomNumberGenerator.new()
		escape_rng.randomize()
	result_label.visible = false
	if CampaignState.active_enemy_fleet != null:
		_player_spawned_indices = CrewRules.deploy_indices(CampaignState.player_fleet.ship_compositions)
		_enemy_spawned_indices = CrewRules.deploy_indices(CampaignState.active_enemy_fleet.ship_compositions)
		player_ships = _spawn_fleet_from_data(CampaignState.player_fleet, _player_spawned_indices, player_spawn_points, PLAYER_GROUP, ENEMY_GROUP, 0.0)
		enemy_ships = _spawn_fleet_from_data(CampaignState.active_enemy_fleet, _enemy_spawned_indices, enemy_spawn_points, ENEMY_GROUP, PLAYER_GROUP, PI)
	else:
		player_ships = _spawn_fleet(player_spawn_points, PLAYER_GROUP, ENEMY_GROUP, 0.0)
		enemy_ships = _spawn_fleet(enemy_spawn_points, ENEMY_GROUP, PLAYER_GROUP, PI)
	combat_camera.focus(_spawn_centre())

	# Ships are instantiated dynamically here rather than as static scene children, so
	# their own _ready() (which resolves @onready hull/shield/engine) hasn't run yet at
	# this point in the same frame -- wait for it before touching ship.hull below. See
	# tests/test_ship.gd's run_async note for the general rule this follows.
	await get_tree().process_frame

	if CampaignState.active_enemy_fleet != null:
		_apply_fleet_data(player_ships, CampaignState.player_fleet, _player_spawned_indices, 0)
		_apply_fleet_data(enemy_ships, CampaignState.active_enemy_fleet, _enemy_spawned_indices, CrewRules.NPC_CREW_FLOOR)

	var arena := Rect2(Vector2.ZERO, combat_camera.arena_size)
	for ship in player_ships:
		ship.arena_rect = arena
		_wire_battle_end(ship)
	for ship in enemy_ships:
		ship.arena_rect = arena
		_wire_battle_end(ship)
		_wire_ai(ship)

	fleet_commander.setup(player_ships, ENEMY_GROUP)
	order_bar.hold_pressed.connect(fleet_commander.order_hold)
	order_bar.flee_pressed.connect(fleet_commander.order_flee)
	order_bar.formation_picked.connect(fleet_commander.set_formation)
	fleet_commander.formation_changed.connect(order_bar.show_formation)
	fleet_commander.selection_changed.connect(order_bar.set_has_selection)
	fleet_commander.selected_ships = _initial_selection()
	debug_console.command_entered.connect(_on_debug_command)
	# An unarmed side loses before a shot is fired.
	_check_battle_end()

# Midpoint between the two fleets' spawn areas, where the fight opens.
func _spawn_centre() -> Vector2:
	var points := player_spawn_points + enemy_spawn_points
	if points.is_empty():
		return combat_camera.arena_size / 2.0
	var total := Vector2.ZERO
	for point in points:
		total += point
	return total / float(points.size())

func _spawn_fleet(points: Array[Vector2], own_group: StringName, opposing_group: StringName, facing_rotation: float) -> Array[Ship]:
	var spawned: Array[Ship] = []
	for point in points:
		var ship: Ship = ShipScene.instantiate()
		add_child(ship)
		ship.global_position = point
		ship.rotation = facing_rotation
		ship.enemy_group = opposing_group
		ship.ally_group = own_group
		ship.add_to_group(own_group)
		spawned.append(ship)
	return spawned

func _spawn_fleet_from_data(fleet_data: CampaignFleet, indices: Array[int], points: Array[Vector2], own_group: StringName, opposing_group: StringName, facing_rotation: float) -> Array[Ship]:
	var spawned: Array[Ship] = []
	for k in indices.size():
		var point: Vector2 = points[k % points.size()]
		var comp: Dictionary = fleet_data.ship_compositions[indices[k]]
		var ship_scene: PackedScene = ShipType.scene_for(ShipType.kind_of(comp))
		var ship: Ship = ship_scene.instantiate()
		add_child(ship)
		ship.global_position = point
		ship.rotation = facing_rotation
		ship.enemy_group = opposing_group
		ship.ally_group = own_group
		ship.add_to_group(own_group)
		spawned.append(ship)
	return spawned

func _apply_fleet_data(ships: Array[Ship], fleet_data: CampaignFleet, indices: Array[int], crew_floor: int) -> void:
	for i in ships.size():
		var comp: Dictionary = fleet_data.ship_compositions[indices[i]]
		ships[i].hull.max_hp = comp["max_hp"]
		ships[i].hull.current_hp = comp["current_hp"]
		ships[i].shield.max_shield = comp["max_shield"]
		ships[i].shield.current_shield = comp["current_shield"]
		if comp.get("shield_item", "") != "":
			var shield_item: ShieldGenerator = load(comp["shield_item"])
			ships[i].shield.max_shield = shield_item.max_shield
			ships[i].shield.regen_rate = shield_item.regen_rate
		if comp.has("engine_max_hp"):
			ships[i].engine.max_hp = comp["engine_max_hp"]
			ships[i].engine.current_hp = comp["engine_current_hp"]
		if comp.get("engine_item", "") != "":
			var engine_item: EngineCore = load(comp["engine_item"])
			ships[i].engine.max_speed = engine_item.max_speed
			ships[i].engine.turn_rate = engine_item.turn_rate
			ships[i].engine.acceleration = engine_item.acceleration
		if comp.has("weapon_mount_max_hp"):
			var mount_max: Array = comp["weapon_mount_max_hp"]
			var mount_cur: Array = comp["weapon_mount_current_hp"]
			for j in ships[i].weapon_mounts.size():
				if j < mount_max.size():
					ships[i].weapon_mounts[j].max_hp = mount_max[j]
					ships[i].weapon_mounts[j].current_hp = mount_cur[j]
		var mount_items: Array = comp.get("weapon_mount_items", [])
		for j in ships[i].weapon_mounts.size():
			if j < mount_items.size() and mount_items[j] != "":
				ships[i].weapon_mounts[j].weapon = load(mount_items[j])
		# After the hull hp above: setup_crew snapshots it as the crew-loss baseline.
		ships[i].setup_crew(CrewRules.crew_of(comp), CrewRules.complement(comp), crew_floor)

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
	ship.ally_group = own_group
	ship.add_to_group(own_group)

	await get_tree().process_frame

	ship.arena_rect = Rect2(Vector2.ZERO, combat_camera.arena_size)
	_wire_battle_end(ship)
	fleet.append(ship)
	if own_group == ENEMY_GROUP:
		_wire_ai(ship)

func _fleet_centroid(fleet: Array[Ship]) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for ship in fleet:
		# A fled ship is hidden where it jumped, so spawning there looks like thin air.
		if is_instance_valid(ship) and not ship.has_fled:
			sum += ship.global_position
			count += 1
	return sum / count if count > 0 else Vector2(500, 300)

func _toggle_god_mode() -> void:
	for ship in fleet_commander.selected_ships:
		if is_instance_valid(ship):
			ship.hull.invulnerable = not ship.hull.invulnerable

func _kill_all_enemies() -> void:
	for ship in enemy_ships.duplicate():
		if is_instance_valid(ship) and not ship.has_fled:
			ship.hull.invulnerable = false
			ship.hull.apply_damage(ship.hull.max_hp)

# Must connect after Ship._ready's hull.destroyed -> queue_free, so a destroyed ship
# already reads as queued for deletion when the check runs.
func _wire_battle_end(ship: Ship) -> void:
	ship.hull.destroyed.connect(_check_battle_end)
	ship.jumped_out.connect(_check_battle_end.unbind(1))
	for mount in ship.weapon_mounts:
		mount.destroyed.connect(_check_battle_end)

# A side without a working weapon loses, so every battle ends. Player side first: if both
# sides are out in the same check, the player loses.
func _check_battle_end() -> void:
	if _resolved:
		return
	if not _has_armed_active_ship(PLAYER_GROUP):
		_show_result("Withdrew" if _any_armed_fled(player_ships) else "Defeat")
	elif not _has_armed_active_ship(ENEMY_GROUP):
		_player_won = true
		_show_result("Victory")

func _has_armed_active_ship(group: StringName) -> bool:
	for member in get_tree().get_nodes_in_group(group):
		if not _is_active(member):
			continue
		for mount in member.weapon_mounts:
			if mount.weapon != null and not mount.is_destroyed():
				return true
	return false

# A ship that jumped out with no working mount left is no withdrawal, just a lost fleet.
func _any_armed_fled(ships: Array[Ship]) -> bool:
	for ship in ships:
		if not is_instance_valid(ship) or not ship.has_fled:
			continue
		for mount in ship.weapon_mounts:
			if mount.weapon != null and not mount.is_destroyed():
				return true
	return false

# The flagship, or the first deployed ship when it was held back or there's no campaign.
func _initial_selection() -> Array[Ship]:
	var selection: Array[Ship] = []
	if player_ships.is_empty():
		return selection
	var pick := player_ships[0]
	if CampaignState.active_enemy_fleet != null:
		var comps: Array[Dictionary] = CampaignState.player_fleet.ship_compositions
		for k in _player_spawned_indices.size():
			if CrewRules.is_flagship(comps[_player_spawned_indices[k]]):
				pick = player_ships[k]
				break
	selection.append(pick)
	return selection

func _is_active(member: Node) -> bool:
	return is_instance_valid(member) and not member.is_queued_for_deletion() and not member.has_fled

func _show_result(text: String) -> void:
	_resolved = true
	result_label.text = text
	result_label.visible = true
	if CampaignState.active_enemy_fleet != null:
		call_deferred("_report_to_campaign")

func _report_to_campaign() -> void:
	var player_comps: Array[Dictionary] = CampaignState.player_fleet.ship_compositions
	var enemy_comps: Array[Dictionary] = CampaignState.active_enemy_fleet.ship_compositions
	var player_speeds: Array[float] = []
	var enemy_speeds: Array[float] = []
	var player_fled: Array[bool] = []
	var enemy_fled: Array[bool] = []
	var player_survivors := _collect_survivor_data(player_ships, player_comps, _player_spawned_indices, player_speeds, player_fled)
	var enemy_survivors := _collect_survivor_data(enemy_ships, enemy_comps, _enemy_spawned_indices, enemy_speeds, enemy_fled)
	# Every surviving loser, deployed or held back, rolls to escape; the caught are captured.
	var captured: Array[Dictionary] = []
	if _player_won:
		enemy_survivors = _roll_escapes(enemy_survivors, enemy_speeds, enemy_fled, _pursuer_speed(player_ships), captured)
	else:
		player_survivors = _roll_escapes(player_survivors, player_speeds, player_fled, _pursuer_speed(enemy_ships), captured)
	CampaignState.resolve_engagement(player_survivors, enemy_survivors, _player_won, captured)
	if CampaignState.player_fleet == null:
		return
	# A total loss respawns at home base instead of ending the game.
	if CampaignState.player_fleet.is_destroyed():
		CampaignState.begin_respawn()
	get_tree().change_scene_to_file("res://scenes/campaign/campaign_scene.tscn")

# Keeps comp order: each spawned comp becomes its ship's state (or is dropped if lost)
# and held-back comps pass through. Debug-spawned extras go last with no orig comp.
# Appends each survivor's escape speed to speeds and whether it jumped out to fled, in the same order.
func _collect_survivor_data(ships: Array[Ship], original_compositions: Array[Dictionary], spawned_indices: Array[int], speeds: Array[float], fled: Array[bool]) -> Array[Dictionary]:
	var survivors: Array[Dictionary] = []
	for i in original_compositions.size():
		var k := spawned_indices.find(i)
		if k == -1:
			survivors.append(original_compositions[i].duplicate(true))
			speeds.append(CrewRules.comp_top_speed(original_compositions[i]))
			fled.append(false)
		elif _is_surviving(ships[k]):
			survivors.append(_survivor_comp(ships[k], original_compositions[i]))
			speeds.append(ships[k].engine.effective_max_speed())
			fled.append(ships[k].has_fled)
	for k in range(spawned_indices.size(), ships.size()):
		if _is_surviving(ships[k]):
			survivors.append(_survivor_comp(ships[k], {}))
			speeds.append(ships[k].engine.effective_max_speed())
			fled.append(ships[k].has_fled)
	return survivors

# 0 when the winner has no ship left, which lets every loser escape.
func _pursuer_speed(winner_ships: Array[Ship]) -> float:
	var fastest := 0.0
	for ship in winner_ships:
		if _is_surviving(ship) and not ship.has_fled:
			fastest = maxf(fastest, ship.engine.effective_max_speed())
	return fastest

# Returns the escaped comps; the caught ones are appended to captured. A ship that jumped out
# escaped already and draws no roll.
func _roll_escapes(survivors: Array[Dictionary], speeds: Array[float], fled: Array[bool], pursuer_speed: float, captured: Array[Dictionary]) -> Array[Dictionary]:
	var escaped: Array[Dictionary] = []
	var rolling_speeds: Array[float] = []
	for i in survivors.size():
		if not fled[i]:
			rolling_speeds.append(speeds[i])
	var rolls := BattleResolution.roll_escapes(rolling_speeds, pursuer_speed, escape_rng)
	var next_roll := 0
	for i in survivors.size():
		var escaped_ship := true
		if not fled[i]:
			escaped_ship = rolls[next_roll]
			next_roll += 1
		if escaped_ship:
			escaped.append(survivors[i])
		else:
			captured.append(survivors[i])
	return escaped

# Untyped: lost ships are freed by report time, and a freed object fails any
# Object-typed parameter check before is_instance_valid can run.
func _is_surviving(ship) -> bool:
	return is_instance_valid(ship) and not ship.hull.is_destroyed()

func _survivor_comp(ship: Ship, orig: Dictionary) -> Dictionary:
	var orig_items: Array = orig.get("weapon_mount_items", [])
	var mount_max: Array[float] = []
	var mount_cur: Array[float] = []
	var mount_items: Array[String] = []
	for j in ship.weapon_mounts.size():
		var mount := ship.weapon_mounts[j]
		mount_max.append(mount.max_hp)
		mount_cur.append(mount.current_hp)
		mount_items.append(orig_items[j] if j < orig_items.size() else "")
	var comp := {
		"ship_type": ship.ship_type,
		"max_hp": ship.hull.max_hp,
		"current_hp": ship.hull.current_hp,
		"max_shield": ship.shield.max_shield,
		"current_shield": ship.shield.current_shield,
		"engine_max_hp": ship.engine.max_hp,
		"engine_current_hp": ship.engine.current_hp,
		"weapon_mount_max_hp": mount_max,
		"weapon_mount_current_hp": mount_cur,
		"weapon_mount_items": mount_items,
		"shield_item": orig.get("shield_item", ""),
		"engine_item": orig.get("engine_item", ""),
		"deploy": CrewRules.wants_deploy(orig),
		"flagship": CrewRules.is_flagship(orig),
	}
	# Untracked crew (debug-spawned extras) stays keyless, which reads as full crew.
	# Floor so rounding never grants crew the ship lost.
	if ship.crew_complement > 0:
		comp["crew"] = floori(ship.crew + CrewRules.ROUND_EPSILON)
	return comp

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
