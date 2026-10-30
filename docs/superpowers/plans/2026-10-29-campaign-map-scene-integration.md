# Campaign Map Scene Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Assemble a playable `CampaignScene` from the simulation-layer
pieces built in Plan A (`2026-10-29-campaign-map-simulation-layer.md`),
wire the existing `CombatScene` to read/write `CampaignState` so battles
fought from the map persist results back onto it, and make the campaign
map the game's entry point.

**Architecture:** `CampaignScene` spawns one `CampaignFleetIcon` per
`CampaignState` fleet, takes player click-to-move input, and shows an
Engage/Disengage prompt when the player's icon overlaps another fleet's
icon (`Area2D.area_entered`). Engaging calls
`CampaignState.start_engagement` and swaps to `CombatScene` via
`get_tree().change_scene_to_file`. `CombatScene._ready()` checks
`CampaignState.active_enemy_fleet`: if set, it spawns ships sized from
that fleet's composition instead of the existing fixed 3v3 default, and
on battle resolution reports survivor data back to
`CampaignState.resolve_engagement` before swapping back to the map (or to
a game-over screen if the player fleet was wiped out).

**Tech Stack:** Godot 4.7, GDScript. Tests follow the existing repo
pattern (`extends RefCounted`, `run()`/`run_async(tree)` returning
`Array[String]`), registered in `tests/run_tests.gd`.

## Global Constraints

- Tabs for indentation, matching every existing `.gd` file in this repo.
- Modifications to `scripts/combat/combat_scene.gd` must preserve its
  existing standalone behavior (fixed 3v3 spawn, label-only result)
  when `CampaignState.active_enemy_fleet` is null — the existing
  `tests/test_combat_scene.gd` must keep passing unchanged.
- Any test that sets `CampaignState.active_enemy_fleet` or
  `CampaignState.player_fleet` must call `CampaignState.reset()` before
  returning, since the autoload is shared process-wide across the whole
  `run_tests.gd` run.
- "Overlap" between the player's `CampaignFleetIcon` and another fleet's
  icon always shows the Engage/Disengage prompt (resolves the ambiguity
  in the original design note about disengage only being offered before
  contact — here, the icons' collision shapes act as an engagement-range
  trigger, not literal touching, so a real Disengage choice is always
  meaningful).

---

### Task 8: CampaignScene — spawning, player input, and the engage prompt

**Files:**
- Create: `scripts/campaign/campaign_scene.gd`
- Create: `scenes/campaign/campaign_scene.tscn`
- Test: `tests/test_campaign_scene.gd`

**Interfaces:**
- Consumes: `CampaignFleet`, `CampaignFleetIcon`, `HomeBase`,
  `CampaignState` (all from Plan A).
- Produces: `extends Node2D` (no `class_name` needed — this is a leaf
  scene, not referenced by type elsewhere) with `var player_icon:
  CampaignFleetIcon`, `var enemy_icons: Array[CampaignFleetIcon]`;
  method `_bootstrap_default_campaign() -> void` (called from `_ready()`
  only when `CampaignState.player_fleet` is null, i.e. first run).

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")
const CampaignState = preload("res://scripts/campaign/campaign_state.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame

	if scene.player_icon == null:
		failures.append("expected player_icon spawned on first run (bootstrap)")
	if scene.enemy_icons.is_empty():
		failures.append("expected at least one enemy_icon spawned on first run (bootstrap)")
	if campaign_state.player_fleet == null:
		failures.append("expected CampaignState.player_fleet populated by bootstrap")

	# Simulate the player clicking to engage: directly overlap player_icon with
	# the first enemy icon's position and let physics process the area_entered signal.
	var target_icon: CampaignFleetIcon = scene.enemy_icons[0]
	scene.player_icon.global_position = target_icon.global_position
	for i in 5:
		await tree.physics_frame

	var prompt: Control = scene.get_node("EngagePrompt")
	if not prompt.visible:
		failures.append("expected EngagePrompt visible after player icon overlaps an enemy icon")

	prompt.get_node("EngageButton").pressed.emit()
	if campaign_state.active_enemy_fleet != target_icon.fleet:
		failures.append("expected Engage button to call CampaignState.start_engagement with the overlapped fleet")

	campaign_state.reset()
	scene.queue_free()
	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, scene/script not found.

- [ ] **Step 3: Write minimal implementation**

`scripts/campaign/campaign_scene.gd`:

```gdscript
extends Node2D

const CampaignFleetIconScene = preload("res://scenes/campaign/campaign_fleet_icon.tscn")
const HomeBaseScene = preload("res://scenes/campaign/home_base.tscn")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

const HOME_BASE_POSITION := Vector2(600, 400)

var player_icon: CampaignFleetIcon
var enemy_icons: Array[CampaignFleetIcon] = []

@onready var engage_prompt: Control = $EngagePrompt

var _pending_enemy_icon: CampaignFleetIcon

func _ready() -> void:
	if CampaignState.player_fleet == null:
		_bootstrap_default_campaign()

	var base: Area2D = HomeBaseScene.instantiate()
	base.global_position = HOME_BASE_POSITION
	add_child(base)

	player_icon = _spawn_icon(CampaignState.player_fleet, CampaignFleetIcon.BehaviorType.PLAYER)
	player_icon.area_entered.connect(_on_player_area_entered)

	for enemy_fleet in CampaignState.enemy_fleets:
		var behavior := _behavior_for_faction(enemy_fleet.faction)
		var icon := _spawn_icon(enemy_fleet, behavior)
		icon.player_target = player_icon
		enemy_icons.append(icon)

	engage_prompt.visible = false
	engage_prompt.get_node("EngageButton").pressed.connect(_on_engage_pressed)
	engage_prompt.get_node("DisengageButton").pressed.connect(_on_disengage_pressed)

func _bootstrap_default_campaign() -> void:
	var player := CampaignFleet.new()
	player.faction = CampaignFleet.Faction.PLAYER
	player.position = HOME_BASE_POSITION
	player.speed = 120.0
	player.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
	]
	CampaignState.player_fleet = player

	var pirate := CampaignFleet.new()
	pirate.faction = CampaignFleet.Faction.PIRATE
	pirate.position = Vector2(1000, 200)
	pirate.speed = 100.0
	pirate.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]

	var trader := CampaignFleet.new()
	trader.faction = CampaignFleet.Faction.TRADER
	trader.position = Vector2(200, 700)
	trader.speed = 80.0
	trader.ship_compositions = [{"max_hp": 60.0, "current_hp": 60.0, "max_shield": 20.0, "current_shield": 20.0}]

	var patrol := CampaignFleet.new()
	patrol.faction = CampaignFleet.Faction.NEUTRAL
	patrol.position = Vector2(900, 800)
	patrol.speed = 90.0
	patrol.ship_compositions = [{"max_hp": 80.0, "current_hp": 80.0, "max_shield": 30.0, "current_shield": 30.0}]

	CampaignState.enemy_fleets = [pirate, trader, patrol]

func _behavior_for_faction(faction: CampaignFleet.Faction) -> CampaignFleetIcon.BehaviorType:
	match faction:
		CampaignFleet.Faction.PIRATE:
			return CampaignFleetIcon.BehaviorType.PIRATE
		CampaignFleet.Faction.TRADER:
			return CampaignFleetIcon.BehaviorType.TRADER
		_:
			return CampaignFleetIcon.BehaviorType.PATROL

func _spawn_icon(fleet: CampaignFleet, behavior: CampaignFleetIcon.BehaviorType) -> CampaignFleetIcon:
	var icon: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	icon.behavior_type = behavior
	add_child(icon)
	icon.setup(fleet, HOME_BASE_POSITION)
	return icon

func _on_player_area_entered(area: Area2D) -> void:
	if area is CampaignFleetIcon and area != player_icon and not engage_prompt.visible:
		_pending_enemy_icon = area
		engage_prompt.visible = true

func _on_engage_pressed() -> void:
	engage_prompt.visible = false
	CampaignState.start_engagement(_pending_enemy_icon.fleet)
	get_tree().change_scene_to_file("res://scenes/combat/combat_scene.tscn")

func _on_disengage_pressed() -> void:
	engage_prompt.visible = false
	_pending_enemy_icon = null

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		player_icon.set_move_target(get_global_mouse_position())
```

`scenes/campaign/campaign_scene.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/campaign/campaign_scene.gd" id="1"]

[node name="CampaignScene" type="Node2D"]
script = ExtResource("1")

[node name="EngagePrompt" type="Control" parent="."]
offset_left = 450.0
offset_top = 250.0
offset_right = 750.0
offset_bottom = 350.0
visible = false

[node name="Label" type="Label" parent="EngagePrompt"]
offset_top = 0.0
offset_right = 300.0
offset_bottom = 30.0
text = "Engage this fleet?"

[node name="EngageButton" type="Button" parent="EngagePrompt"]
offset_top = 40.0
offset_right = 140.0
offset_bottom = 70.0
text = "Engage"

[node name="DisengageButton" type="Button" parent="EngagePrompt"]
offset_left = 160.0
offset_top = 40.0
offset_right = 300.0
offset_bottom = 70.0
text = "Disengage"
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_scene.gd scenes/campaign/campaign_scene.tscn tests/test_campaign_scene.gd
git commit -m "Add CampaignScene assembling fleets, player input, and the engage prompt"
```

---

### Task 9: Wire CombatScene to CampaignState

**Files:**
- Modify: `scripts/combat/combat_scene.gd`
- Modify: `tests/test_combat_scene.gd` (add a new case; existing
  assertions must still pass unchanged)

**Interfaces:**
- Consumes: `CampaignState.active_enemy_fleet`, `CampaignState.player_fleet`
  (Plan A Task 7), `CampaignFleet.ship_compositions` (Plan A Task 1).
- Produces: `combat_scene.gd` now reports results to
  `CampaignState.resolve_engagement` and transitions back to
  `res://scenes/campaign/campaign_scene.tscn` (or
  `res://scenes/ui/game_over.tscn`) when launched from the campaign map.

- [ ] **Step 1: Write the failing test**

Add this case to `tests/test_combat_scene.gd`'s `run_async`, after the
existing Victory/Defeat checks and before the final `return failures`
(the existing checks are untouched — this is additive):

```gdscript
	# Campaign-driven battle: CombatScene should spawn from CampaignState
	# fleet data and report results back instead of using fixed spawn points.
	var campaign_state = tree.root.get_node("/root/CampaignState")
	campaign_state.reset()

	var CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")
	var player_fleet := CampaignFleet.new()
	player_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	var enemy_fleet := CampaignFleet.new()
	enemy_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	campaign_state.player_fleet = player_fleet
	campaign_state.start_engagement(enemy_fleet)

	var campaign_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(campaign_scene)
	await tree.process_frame
	await tree.process_frame

	if campaign_scene.player_ships.size() != 1:
		failures.append("campaign battle: expected 1 player ship spawned from fleet data, got %d" % campaign_scene.player_ships.size())
	if campaign_scene.enemy_ships.size() != 1:
		failures.append("campaign battle: expected 1 enemy ship spawned from fleet data, got %d" % campaign_scene.enemy_ships.size())

	for ship in campaign_scene.enemy_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	await tree.process_frame

	if not enemy_fleet.is_destroyed():
		failures.append("campaign battle: expected enemy_fleet marked destroyed after losing all ships")
	if campaign_state.active_enemy_fleet != null:
		failures.append("campaign battle: expected active_enemy_fleet cleared after resolution")

	campaign_state.reset()
	if is_instance_valid(campaign_scene) and not campaign_scene.is_queued_for_deletion():
		campaign_scene.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/run_tests.gd`
Expected: FAIL on the new assertions (combat_scene still always uses
fixed spawn points; `CampaignState.resolve_engagement` never called).

- [ ] **Step 3: Write minimal implementation**

In `scripts/combat/combat_scene.gd`, replace the spawn lines in
`_ready()`:

```gdscript
func _ready() -> void:
	result_label.visible = false
	if CampaignState.active_enemy_fleet != null:
		player_ships = _spawn_fleet_from_data(CampaignState.player_fleet, player_spawn_points, PLAYER_GROUP, ENEMY_GROUP, 0.0)
		enemy_ships = _spawn_fleet_from_data(CampaignState.active_enemy_fleet, enemy_spawn_points, ENEMY_GROUP, PLAYER_GROUP, PI)
	else:
		player_ships = _spawn_fleet(player_spawn_points, PLAYER_GROUP, ENEMY_GROUP, 0.0)
		enemy_ships = _spawn_fleet(enemy_spawn_points, ENEMY_GROUP, PLAYER_GROUP, PI)

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
```

Add these new methods (near `_spawn_fleet`):

```gdscript
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
```

Modify `_show_result` to report back to the campaign when applicable:

```gdscript
func _show_result(text: String) -> void:
	_resolved = true
	result_label.text = text
	result_label.visible = true
	if CampaignState.active_enemy_fleet != null:
		call_deferred("_report_to_campaign")
```

Add these new methods:

```gdscript
func _report_to_campaign() -> void:
	CampaignState.resolve_engagement(_collect_survivor_data(player_ships), _collect_survivor_data(enemy_ships))
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
```

Note: `call_deferred` avoids changing the scene tree from inside a
signal callback that may still be mid-iteration (the `hull.destroyed` ->
`_on_ship_destroyed` -> `_show_result` chain).

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script tests/run_tests.gd`
Expected: `All tests passed.` — both the new campaign-battle case and
every pre-existing `test_combat_scene.gd` assertion (which exercises the
`CampaignState.active_enemy_fleet == null` branch, since no earlier test
leaves it set — confirm by checking `tests/run_tests.gd` ordering runs
this file before the new campaign test case within it executes its own
`reset()` calls).

- [ ] **Step 5: Commit**

```bash
git add scripts/combat/combat_scene.gd tests/test_combat_scene.gd
git commit -m "Wire CombatScene to build from and report back to CampaignState"
```

---

### Task 10: Game-over screen and making the campaign map the entry point

**Files:**
- Create: `scripts/ui/game_over.gd`
- Create: `scenes/ui/game_over.tscn`
- Modify: `project.godot` (`run/main_scene`)
- Test: `tests/test_game_over.gd`

**Interfaces:**
- Produces: `extends Control` game-over screen with no exported API —
  it's a terminal screen, quit-only.

- [ ] **Step 1: Write the failing test**

```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, scene not found.

- [ ] **Step 3: Write minimal implementation**

`scripts/ui/game_over.gd`:

```gdscript
extends Control

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
```

`scenes/ui/game_over.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/game_over.gd" id="1"]

[node name="GameOver" type="Control"]
script = ExtResource("1")

[node name="Label" type="Label" parent="."]
offset_left = 450.0
offset_top = 280.0
offset_right = 750.0
offset_bottom = 340.0
theme_override_font_sizes/font_size = 48
text = "Game Over"
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Set the campaign map as the game's entry point**

In `project.godot`, change:

```
run/main_scene="res://scenes/combat/combat_scene.tscn"
```

to:

```
run/main_scene="res://scenes/campaign/campaign_scene.tscn"
```

- [ ] **Step 6: Register the new test and run the full suite**

Add `preload("res://tests/test_game_over.gd")` as a new `await`-based
block in `tests/run_tests.gd`, following the same pattern as Task 7 Step
5. Then run: `godot --headless --script tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 7: Manual playtest**

Run the game (`godot .` or press Play in the editor). Verify: the
campaign map loads first, the player fleet icon moves to mouse clicks,
approaching the pirate/trader/patrol icons shows the Engage/Disengage
prompt, Engage transitions into `CombatScene` with the right ship count,
winning or losing returns to the map (or game-over) with damage carried
over, and docking at the home base repairs the fleet.

- [ ] **Step 8: Commit**

```bash
git add scripts/ui/game_over.gd scenes/ui/game_over.tscn project.godot tests/run_tests.gd tests/test_game_over.gd
git commit -m "Add game-over screen and make the campaign map the entry point"
```
