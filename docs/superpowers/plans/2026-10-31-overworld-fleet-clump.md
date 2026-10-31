# Overworld Fleet Clump Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the overworld's single fleet-icon triangle with a scattered dot per ship, so fleet size is visible at a glance.

**Architecture:** `CampaignFleetIcon` (`scripts/campaign/campaign_fleet_icon.gd`) gains a `_sync_ship_dots()` method that reconciles a pool of small `Polygon2D` dot children against `fleet.ship_compositions.size()`, called once from `setup()` and every `_physics_process()` tick. The scene file (`scenes/campaign/campaign_fleet_icon.tscn`) drops its static triangle `Polygon2D` — dots are created entirely at runtime.

**Tech Stack:** Godot 4.7 / GDScript, existing project test harness (`tests/run_tests.gd`, static `run()`/`run_async(tree)` pattern, no external test framework).

## Global Constraints

- Scope is count/shape only — no ship-class field, no per-class visuals. Every dot looks identical. (See spec's "Out of scope" section.)
- Applies to all fleets (player, trader, pirate, faction) — this lives in the shared `CampaignFleetIcon`, so no per-faction branching is needed.
- `CampaignFleet` (`scripts/campaign/campaign_fleet.gd`) is not modified — this is a rendering-only change reading the existing `ship_compositions` array.
- The `Area2D` root and its `CollisionShape2D` (radius 24) are unchanged — click/interaction hitbox size does not scale with fleet size.
- Dot offsets are rolled once per index and cached, so surviving ships' dots never jump position when the fleet shrinks.
- No new `class_name` files are introduced, so no editor cache-warm pass is needed. Test command: `C:\Users\corbi\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`

---

### Task 1: Dot-based ship rendering on CampaignFleetIcon

**Files:**
- Modify: `scenes/campaign/campaign_fleet_icon.tscn` (remove the static `Polygon2D` triangle node)
- Modify: `scripts/campaign/campaign_fleet_icon.gd` (add `_sync_ship_dots()` and call sites)
- Test: `tests/test_campaign_fleet_icon.gd` (already registered in `tests/run_tests.gd` at line 99 — no registration step needed)

**Interfaces:**
- Consumes: `CampaignFleet.ship_compositions: Array[Dictionary]` (existing field, `scripts/campaign/campaign_fleet.gd:10`) — only `.size()` is read, no new fields.
- Produces: `CampaignFleetIcon.CLUMP_RADIUS: float` (new public constant, used by the test to bound dot offsets). No other new public surface — `_sync_ship_dots()`, `_ship_dots`, `_ship_dot_offsets`, and `_circle_polygon()` are internal (`_`-prefixed) and not consumed outside this file.

- [x] **Step 1: Write the failing tests**

Open `tests/test_campaign_fleet_icon.gd`. Insert the following block immediately before the final `return failures` line (after the existing "rewound" trader block that ends with `rewound_icon.queue_free()`):

```gdscript
	# Ship dots: setup() should create one Polygon2D dot per ship
	# composition, each within CLUMP_RADIUS of the icon's local origin.
	var dots_fleet := CampaignFleet.new()
	dots_fleet.position = Vector2(200, 200)
	dots_fleet.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
	]
	var dots_icon: CampaignFleetIcon = CampaignFleetIconScene.instantiate()
	tree.root.add_child(dots_icon)
	dots_icon.setup(dots_fleet, Vector2.ZERO)

	var dot_nodes: Array = dots_icon.get_children().filter(func(c): return c is Polygon2D)
	if dot_nodes.size() != 3:
		failures.append("ship dots: expected 3 dots for a 3-ship fleet, got %d" % dot_nodes.size())
	for dot in dot_nodes:
		if dot.position.length() > CampaignFleetIcon.CLUMP_RADIUS:
			failures.append("ship dots: expected dot offset within CLUMP_RADIUS, got %s" % dot.position)

	# Live update: shrinking ship_compositions and ticking physics should
	# remove dots to match, without moving the surviving dots' positions.
	var surviving_positions: Array = []
	for dot in dot_nodes.slice(0, 2):
		surviving_positions.append(dot.position)
	dots_fleet.ship_compositions = dots_fleet.ship_compositions.slice(0, 2)
	await tree.physics_frame
	var dot_nodes_after: Array = dots_icon.get_children().filter(func(c): return c is Polygon2D)
	if dot_nodes_after.size() != 2:
		failures.append("ship dots: expected dot count to drop to 2 after composition shrank, got %d" % dot_nodes_after.size())
	for i in dot_nodes_after.size():
		if dot_nodes_after[i].position != surviving_positions[i]:
			failures.append("ship dots: expected surviving dot %d to keep its position %s, got %s" % [i, surviving_positions[i], dot_nodes_after[i].position])

	dots_icon.queue_free()
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `C:\Users\corbi\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`

Expected: FAIL — `Invalid get index 'CLUMP_RADIUS'` (or similar: the constant doesn't exist yet) reported under `test_campaign_fleet_icon.gd`, plus the dot-count assertions failing (0 dots found, since nothing creates `Polygon2D` children yet).

- [x] **Step 3: Remove the static triangle from the scene**

Edit `scenes/campaign/campaign_fleet_icon.tscn`. Current contents:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/campaign/campaign_fleet_icon.gd" id="1"]

[sub_resource type="CircleShape2D" id="1"]
radius = 24.0

[node name="CampaignFleetIcon" type="Area2D"]
script = ExtResource("1")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("1")

[node name="Polygon2D" type="Polygon2D" parent="."]
polygon = PackedVector2Array(14, 0, -10, -8, -10, 8)
color = Color(0.9, 0.9, 0.3, 1)
```

Replace with (drop the trailing `Polygon2D` node, `load_steps` stays `3` since the ext_resource/sub_resource count is unchanged):

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/campaign/campaign_fleet_icon.gd" id="1"]

[sub_resource type="CircleShape2D" id="1"]
radius = 24.0

[node name="CampaignFleetIcon" type="Area2D"]
script = ExtResource("1")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("1")
```

- [x] **Step 4: Implement dot syncing in campaign_fleet_icon.gd**

In `scripts/campaign/campaign_fleet_icon.gd`, add these constants near the top, right after the existing `enum BehaviorType { PLAYER, PATROL, TRADER, PIRATE }` line:

```gdscript
const SHIP_DOT_RADIUS := 3.0
const SHIP_DOT_SIDES := 8
const CLUMP_RADIUS := 18.0
const DOT_COLOR := Color(0.9, 0.9, 0.3, 1)
```

Add these fields next to the existing `var _move_target: Vector2` block:

```gdscript
var _ship_dots: Array[Polygon2D] = []
var _ship_dot_offsets: Array[Vector2] = []
```

Change `setup()` to call the new sync method after assigning `fleet`:

```gdscript
func setup(campaign_fleet: CampaignFleet, home_pos: Vector2) -> void:
	fleet = campaign_fleet
	global_position = fleet.position
	_spawn_point = fleet.position
	_move_target = fleet.position
	_home_position = home_pos
	_sync_ship_dots()
```

Change `_physics_process()` so the dot sync runs every tick regardless of `frozen`, before the existing movement guard:

```gdscript
func _physics_process(delta: float) -> void:
	if fleet == null:
		return
	_sync_ship_dots()
	if frozen:
		return
	match behavior_type:
		BehaviorType.PATROL:
			_move_target = PatrolBehavior.next_wander_target(_spawn_point, _move_target, global_position, wander_radius, arrival_radius)
		BehaviorType.TRADER:
			_process_trader()
		BehaviorType.PIRATE:
			_process_pirate()
		BehaviorType.PLAYER:
			pass
	global_position = global_position.move_toward(_move_target, fleet.speed * delta)
	fleet.position = global_position
```

Add these two new methods at the end of the file:

```gdscript
func _sync_ship_dots() -> void:
	var target: int = fleet.ship_compositions.size()
	while _ship_dots.size() < target:
		var index := _ship_dots.size()
		if index >= _ship_dot_offsets.size():
			var angle := randf_range(0.0, TAU)
			var distance := randf_range(0.0, CLUMP_RADIUS)
			_ship_dot_offsets.append(Vector2.RIGHT.rotated(angle) * distance)
		var dot := Polygon2D.new()
		dot.polygon = _circle_polygon(SHIP_DOT_RADIUS, SHIP_DOT_SIDES)
		dot.color = DOT_COLOR
		dot.position = _ship_dot_offsets[index]
		add_child(dot)
		_ship_dots.append(dot)
	while _ship_dots.size() > target:
		var dot: Polygon2D = _ship_dots.pop_back()
		dot.queue_free()

func _circle_polygon(radius: float, sides: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in sides:
		var angle := TAU * i / sides
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
```

- [x] **Step 5: Run the tests to verify they pass**

Run: `C:\Users\corbi\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe --headless --script tests/run_tests.gd`

Expected: PASS — `test_campaign_fleet_icon.gd` reports no failures, and `total_failures` across the whole suite does not increase versus the pre-change baseline. (Run the same command once before Step 1 if you want an exact baseline count — the repo is clean on `master` per the last carry-forward note, so the baseline should be 0.)

- [x] **Step 6: Commit**

```bash
git add scenes/campaign/campaign_fleet_icon.tscn scripts/campaign/campaign_fleet_icon.gd tests/test_campaign_fleet_icon.gd
git commit -m "feat: render one dot per ship on overworld fleet icons"
```
