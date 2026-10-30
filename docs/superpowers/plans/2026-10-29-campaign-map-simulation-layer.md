# Campaign Map Simulation Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the data model and behavior logic for campaign-map fleets
(player, patrol, trader, pirate) as independently testable units, plus the
`CampaignState` autoload that will later bridge to combat. This plan does
not produce a playable scene — that's Plan B
(`2026-10-29-campaign-map-scene-integration.md`), which wires these pieces
into `CampaignScene` and the combat transition.

**Architecture:** Fleets are represented by a lightweight `CampaignFleet`
Resource (composition + position, no combat components). Movement
behaviors (patrol/trader/pirate) are pure static logic classes, following
the existing `Formation` pattern in this codebase, so they're unit
testable without a live scene tree. A thin `CampaignFleetIcon` node
applies that logic each physics frame. `CampaignState` is an autoload
singleton holding the player fleet and all non-player fleets.

**Tech Stack:** Godot 4.7, GDScript. Tests follow this repo's existing
pattern: `extends RefCounted` with a static `run() -> Array[String]`
(synchronous) or `run_async(tree) -> Array[String]` (needs a live
SceneTree), registered in `tests/run_tests.gd`.

## Global Constraints

- Tabs for indentation, matching every existing `.gd` file in this repo.
- No `class_name` on the `CampaignState` autoload script — it's accessed
  by its autoload node name (`CampaignState`), not as a type.
- Ship compositions in `CampaignFleet` do **not** include a hull-type
  field — only one ship type exists in this codebase today (hull variety
  is a later Refit milestone), so `{max_hp, current_hp, max_shield,
  current_shield}` is the complete per-ship record for now.
- Every new behavior class exposes pure static functions (no instance
  state), mirroring `scripts/combat/formation.gd`.

---

### Task 1: CampaignFleet data model

**Files:**
- Create: `scripts/campaign/campaign_fleet.gd`
- Test: `tests/test_campaign_fleet.gd`

**Interfaces:**
- Produces: `class_name CampaignFleet extends Resource` with
  `enum Faction { PLAYER, NEUTRAL, TRADER, PIRATE }`, exported fields
  `fleet_id: String`, `faction: Faction`,
  `ship_compositions: Array[Dictionary]`, `position: Vector2`,
  `heading: Vector2`, `speed: float`; methods `total_strength() ->
  float`, `is_destroyed() -> bool`, `repair_to_full() -> void`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var fleet := CampaignFleet.new()
	fleet.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 60.0, "max_shield": 50.0, "current_shield": 20.0},
		{"max_hp": 100.0, "current_hp": 0.0, "max_shield": 50.0, "current_shield": 0.0},
	]

	if fleet.total_strength() != 80.0:
		failures.append("total_strength: expected 80.0, got %s" % fleet.total_strength())
	if fleet.is_destroyed():
		failures.append("is_destroyed: expected false with one ship alive")

	fleet.repair_to_full()
	for comp in fleet.ship_compositions:
		if comp["current_hp"] != comp["max_hp"] or comp["current_shield"] != comp["max_shield"]:
			failures.append("repair_to_full: expected all ships at max, got %s" % comp)

	var wiped := CampaignFleet.new()
	wiped.ship_compositions = [
		{"max_hp": 100.0, "current_hp": 0.0, "max_shield": 50.0, "current_shield": 0.0},
	]
	if not wiped.is_destroyed():
		failures.append("is_destroyed: expected true when all ships at 0 hp")

	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/test_campaign_fleet.gd` (or add it
temporarily to `run_tests.gd` — see Task 7 for permanent registration).
Expected: FAIL to parse / "campaign_fleet.gd" not found.

- [ ] **Step 3: Write minimal implementation**

```gdscript
class_name CampaignFleet
extends Resource

enum Faction { PLAYER, NEUTRAL, TRADER, PIRATE }

@export var fleet_id: String = ""
@export var faction: Faction = Faction.NEUTRAL
@export var ship_compositions: Array[Dictionary] = []
@export var position: Vector2 = Vector2.ZERO
@export var heading: Vector2 = Vector2.RIGHT
@export var speed: float = 80.0

func total_strength() -> float:
	var sum := 0.0
	for comp in ship_compositions:
		sum += comp["current_hp"] + comp["current_shield"]
	return sum

func is_destroyed() -> bool:
	for comp in ship_compositions:
		if comp["current_hp"] > 0.0:
			return false
	return true

func repair_to_full() -> void:
	for comp in ship_compositions:
		comp["current_hp"] = comp["max_hp"]
		comp["current_shield"] = comp["max_shield"]
```

- [ ] **Step 4: Run test to verify it passes**

Same run command as Step 2. Expected: PASS, no failures printed.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_fleet.gd tests/test_campaign_fleet.gd
git commit -m "Add CampaignFleet data model for campaign-map ship state"
```

---

### Task 2: PatrolBehavior pure logic

**Files:**
- Create: `scripts/campaign/behaviors/patrol_behavior.gd`
- Test: `tests/test_patrol_behavior.gd`

**Interfaces:**
- Produces: `class_name PatrolBehavior extends RefCounted` with static
  `next_wander_target(spawn_point: Vector2, current_target: Vector2,
  position: Vector2, radius: float, arrival_radius: float) -> Vector2`.
- Consumes: nothing (pure function, no dependency on Task 1).

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

const PatrolBehavior = preload("res://scripts/campaign/behaviors/patrol_behavior.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var spawn := Vector2(100, 100)
	var target := Vector2(120, 100)
	var far_position := Vector2(50, 100)

	var unchanged := PatrolBehavior.next_wander_target(spawn, target, far_position, 50.0, 5.0)
	if unchanged != target:
		failures.append("next_wander_target: expected unchanged target when not arrived, got %s" % unchanged)

	var arrived_position := Vector2(120, 100)
	var new_target := PatrolBehavior.next_wander_target(spawn, target, arrived_position, 50.0, 5.0)
	if new_target.distance_to(spawn) > 50.0:
		failures.append("next_wander_target: expected new target within radius of spawn, got %s" % new_target)

	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Run via `run_tests.gd` (temporarily add the preload/call, or run standalone
headless as in Task 1). Expected: FAIL, script not found.

- [ ] **Step 3: Write minimal implementation**

```gdscript
class_name PatrolBehavior
extends RefCounted

static func next_wander_target(spawn_point: Vector2, current_target: Vector2, position: Vector2, radius: float, arrival_radius: float) -> Vector2:
	if position.distance_to(current_target) > arrival_radius:
		return current_target
	return spawn_point + Vector2(randf_range(-radius, radius), randf_range(-radius, radius))
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/behaviors/patrol_behavior.gd tests/test_patrol_behavior.gd
git commit -m "Add PatrolBehavior wander logic for campaign-map fleets"
```

---

### Task 3: TraderBehavior pure logic

**Files:**
- Create: `scripts/campaign/behaviors/trader_behavior.gd`
- Test: `tests/test_trader_behavior.gd`

**Interfaces:**
- Produces: `class_name TraderBehavior extends RefCounted` with
  `enum RouteState { TO_BASE, FROM_BASE }` and static functions
  `next_route_state(state: RouteState, position: Vector2, home_position:
  Vector2, away_point: Vector2, arrival_radius: float) -> RouteState`,
  `route_target(state: RouteState, home_position: Vector2, away_point:
  Vector2) -> Vector2`, `should_flee(position: Vector2, threat_position:
  Vector2, flee_range: float) -> bool`, `flee_target(position: Vector2,
  threat_position: Vector2, flee_distance: float) -> Vector2`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

const TraderBehavior = preload("res://scripts/campaign/behaviors/trader_behavior.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var home := Vector2(0, 0)
	var away := Vector2(200, 0)

	var still_to_base := TraderBehavior.next_route_state(TraderBehavior.RouteState.TO_BASE, Vector2(100, 0), home, away, 5.0)
	if still_to_base != TraderBehavior.RouteState.TO_BASE:
		failures.append("next_route_state: expected TO_BASE unchanged before arrival")

	var flipped_to_from := TraderBehavior.next_route_state(TraderBehavior.RouteState.TO_BASE, home, home, away, 5.0)
	if flipped_to_from != TraderBehavior.RouteState.FROM_BASE:
		failures.append("next_route_state: expected flip to FROM_BASE on arrival at home")

	if TraderBehavior.route_target(TraderBehavior.RouteState.TO_BASE, home, away) != home:
		failures.append("route_target: expected home_position for TO_BASE")
	if TraderBehavior.route_target(TraderBehavior.RouteState.FROM_BASE, home, away) != away:
		failures.append("route_target: expected away_point for FROM_BASE")

	if not TraderBehavior.should_flee(Vector2(0, 0), Vector2(50, 0), 100.0):
		failures.append("should_flee: expected true when threat within flee_range")
	if TraderBehavior.should_flee(Vector2(0, 0), Vector2(500, 0), 100.0):
		failures.append("should_flee: expected false when threat outside flee_range")

	var fled := TraderBehavior.flee_target(Vector2(0, 0), Vector2(100, 0), 50.0)
	if fled.distance_to(Vector2(0, 0)) < 49.0:
		failures.append("flee_target: expected to move roughly flee_distance away from threat, got %s" % fled)

	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, script not found.

- [ ] **Step 3: Write minimal implementation**

```gdscript
class_name TraderBehavior
extends RefCounted

enum RouteState { TO_BASE, FROM_BASE }

static func next_route_state(state: RouteState, position: Vector2, home_position: Vector2, away_point: Vector2, arrival_radius: float) -> RouteState:
	var target := home_position if state == RouteState.TO_BASE else away_point
	if position.distance_to(target) > arrival_radius:
		return state
	return RouteState.FROM_BASE if state == RouteState.TO_BASE else RouteState.TO_BASE

static func route_target(state: RouteState, home_position: Vector2, away_point: Vector2) -> Vector2:
	return home_position if state == RouteState.TO_BASE else away_point

static func should_flee(position: Vector2, threat_position: Vector2, flee_range: float) -> bool:
	return position.distance_to(threat_position) <= flee_range

static func flee_target(position: Vector2, threat_position: Vector2, flee_distance: float) -> Vector2:
	return position + (position - threat_position).normalized() * flee_distance
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/behaviors/trader_behavior.gd tests/test_trader_behavior.gd
git commit -m "Add TraderBehavior route and flee logic for campaign-map fleets"
```

---

### Task 4: PirateBehavior pure logic

**Files:**
- Create: `scripts/campaign/behaviors/pirate_behavior.gd`
- Test: `tests/test_pirate_behavior.gd`

**Interfaces:**
- Produces: `class_name PirateBehavior extends RefCounted` with static
  `should_intercept(own_strength: float, target_strength: float) ->
  bool` and `in_detection_range(position: Vector2, target_position:
  Vector2, detection_range: float) -> bool`.
- Consumes: nothing directly (callers combine this with
  `PatrolBehavior.next_wander_target` for the non-intercepting case —
  that composition happens in `CampaignFleetIcon`, Task 5).

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

const PirateBehavior = preload("res://scripts/campaign/behaviors/pirate_behavior.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	if not PirateBehavior.should_intercept(150.0, 100.0):
		failures.append("should_intercept: expected true when own_strength > target_strength")
	if PirateBehavior.should_intercept(80.0, 100.0):
		failures.append("should_intercept: expected false when own_strength <= target_strength")

	if not PirateBehavior.in_detection_range(Vector2(0, 0), Vector2(50, 0), 100.0):
		failures.append("in_detection_range: expected true within range")
	if PirateBehavior.in_detection_range(Vector2(0, 0), Vector2(500, 0), 100.0):
		failures.append("in_detection_range: expected false outside range")

	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, script not found.

- [ ] **Step 3: Write minimal implementation**

```gdscript
class_name PirateBehavior
extends RefCounted

static func should_intercept(own_strength: float, target_strength: float) -> bool:
	return own_strength > target_strength

static func in_detection_range(position: Vector2, target_position: Vector2, detection_range: float) -> bool:
	return position.distance_to(target_position) <= detection_range
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/behaviors/pirate_behavior.gd tests/test_pirate_behavior.gd
git commit -m "Add PirateBehavior strength-check and detection logic"
```

---

### Task 5: CampaignFleetIcon scene and script

**Files:**
- Create: `scripts/campaign/campaign_fleet_icon.gd`
- Create: `scenes/campaign/campaign_fleet_icon.tscn`
- Test: `tests/test_campaign_fleet_icon.gd`

**Interfaces:**
- Consumes: `CampaignFleet` (Task 1), `PatrolBehavior`,
  `TraderBehavior`, `PirateBehavior` (Tasks 2-4).
- Produces: `class_name CampaignFleetIcon extends Area2D` with
  `enum BehaviorType { PLAYER, PATROL, TRADER, PIRATE }`, exported
  `behavior_type`, `wander_radius`, `arrival_radius`, `detection_range`,
  `flee_range`, `flee_distance`; `var fleet: CampaignFleet`,
  `var player_target: CampaignFleetIcon`; methods
  `setup(campaign_fleet: CampaignFleet, home_pos: Vector2) -> void`,
  `set_move_target(target: Vector2) -> void`. Signal `area_entered`
  (inherited from `Area2D`) fires when another `CampaignFleetIcon`
  overlaps — used by `CampaignScene` in Plan B.

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

const CampaignFleetIconScene = preload("res://scenes/campaign/campaign_fleet_icon.tscn")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	# Patrol: should wander and stay within radius of its spawn point.
	var patrol_fleet := CampaignFleet.new()
	patrol_fleet.position = Vector2(500, 500)
	patrol_fleet.speed = 400.0
	var patrol_icon: Area2D = CampaignFleetIconScene.instantiate()
	patrol_icon.behavior_type = patrol_icon.BehaviorType.PATROL
	patrol_icon.wander_radius = 50.0
	tree.root.add_child(patrol_icon)
	patrol_icon.setup(patrol_fleet, Vector2.ZERO)

	for i in 30:
		await tree.physics_frame
	if patrol_icon.global_position.distance_to(Vector2(500, 500)) > 50.0:
		failures.append("patrol: expected to stay within wander_radius of spawn, got %s" % patrol_icon.global_position)

	patrol_icon.queue_free()

	# Pirate: stronger than target, within detection range -> moves toward target.
	var pirate_fleet := CampaignFleet.new()
	pirate_fleet.position = Vector2(0, 0)
	pirate_fleet.speed = 400.0
	pirate_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 0.0, "current_shield": 0.0}]
	var weak_fleet := CampaignFleet.new()
	weak_fleet.ship_compositions = [{"max_hp": 10.0, "current_hp": 10.0, "max_shield": 0.0, "current_shield": 0.0}]

	var target_icon: Area2D = CampaignFleetIconScene.instantiate()
	target_icon.behavior_type = target_icon.BehaviorType.PLAYER
	tree.root.add_child(target_icon)
	target_icon.setup(weak_fleet, Vector2.ZERO)
	target_icon.global_position = Vector2(100, 0)

	var pirate_icon: Area2D = CampaignFleetIconScene.instantiate()
	pirate_icon.behavior_type = pirate_icon.BehaviorType.PIRATE
	pirate_icon.detection_range = 500.0
	tree.root.add_child(pirate_icon)
	pirate_icon.setup(pirate_fleet, Vector2.ZERO)
	pirate_icon.player_target = target_icon

	var start_distance: float = pirate_icon.global_position.distance_to(target_icon.global_position)
	for i in 10:
		await tree.physics_frame
	var end_distance: float = pirate_icon.global_position.distance_to(target_icon.global_position)
	if end_distance >= start_distance:
		failures.append("pirate: expected to close distance on a weaker target, start=%s end=%s" % [start_distance, end_distance])

	pirate_icon.queue_free()
	target_icon.queue_free()

	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, scene/script not found.

- [ ] **Step 3: Write minimal implementation**

`scripts/campaign/campaign_fleet_icon.gd`:

```gdscript
class_name CampaignFleetIcon
extends Area2D

const PatrolBehavior = preload("res://scripts/campaign/behaviors/patrol_behavior.gd")
const TraderBehavior = preload("res://scripts/campaign/behaviors/trader_behavior.gd")
const PirateBehavior = preload("res://scripts/campaign/behaviors/pirate_behavior.gd")

enum BehaviorType { PLAYER, PATROL, TRADER, PIRATE }

@export var behavior_type: BehaviorType = BehaviorType.PATROL
@export var wander_radius: float = 150.0
@export var arrival_radius: float = 10.0
@export var detection_range: float = 200.0
@export var flee_range: float = 150.0
@export var flee_distance: float = 300.0

var fleet: CampaignFleet
var player_target: CampaignFleetIcon

var _move_target: Vector2
var _spawn_point: Vector2
var _home_position: Vector2
var _route_state: TraderBehavior.RouteState = TraderBehavior.RouteState.TO_BASE

func setup(campaign_fleet: CampaignFleet, home_pos: Vector2) -> void:
	fleet = campaign_fleet
	global_position = fleet.position
	_spawn_point = fleet.position
	_move_target = fleet.position
	_home_position = home_pos

func set_move_target(target: Vector2) -> void:
	_move_target = target

func _physics_process(delta: float) -> void:
	if fleet == null:
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

func _process_trader() -> void:
	if player_target != null and is_instance_valid(player_target) and TraderBehavior.should_flee(global_position, player_target.global_position, flee_range):
		_move_target = TraderBehavior.flee_target(global_position, player_target.global_position, flee_distance)
		return
	_route_state = TraderBehavior.next_route_state(_route_state, global_position, _home_position, _spawn_point, arrival_radius)
	_move_target = TraderBehavior.route_target(_route_state, _home_position, _spawn_point)

func _process_pirate() -> void:
	if player_target != null and is_instance_valid(player_target) and PirateBehavior.in_detection_range(global_position, player_target.global_position, detection_range):
		if PirateBehavior.should_intercept(fleet.total_strength(), player_target.fleet.total_strength()):
			_move_target = player_target.global_position
			return
	_move_target = PatrolBehavior.next_wander_target(_spawn_point, _move_target, global_position, wander_radius, arrival_radius)
```

`scenes/campaign/campaign_fleet_icon.tscn`:

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

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS. Note `tree.physics_frame` requires the test tree to be
running physics ticks; if using `run_async` with a `SceneTree` created by
`godot --headless`, physics frames advance automatically each iteration
of the main loop — matching how `tests/test_ship.gd` already exercises
physics-driven movement.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_fleet_icon.gd scenes/campaign/campaign_fleet_icon.tscn tests/test_campaign_fleet_icon.gd
git commit -m "Add CampaignFleetIcon driving patrol/trader/pirate movement on the map"
```

---

### Task 6: HomeBase scene and script

**Files:**
- Create: `scripts/campaign/home_base.gd`
- Create: `scenes/campaign/home_base.tscn`
- Test: `tests/test_home_base.gd`

**Interfaces:**
- Consumes: `CampaignFleetIcon.BehaviorType.PLAYER` (Task 5),
  `CampaignFleet.repair_to_full()` (Task 1).
- Produces: `class_name HomeBase extends Area2D` with signal
  `player_docked`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

const HomeBaseScene = preload("res://scenes/campaign/home_base.tscn")
const CampaignFleetIconScene = preload("res://scenes/campaign/campaign_fleet_icon.tscn")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

class DockedTracker:
	var fired := false
	func on_docked() -> void:
		fired = true

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var fleet := CampaignFleet.new()
	fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 10.0, "max_shield": 50.0, "current_shield": 0.0}]
	fleet.speed = 1000.0

	var base: Area2D = HomeBaseScene.instantiate()
	base.global_position = Vector2(0, 0)
	tree.root.add_child(base)

	var tracker := DockedTracker.new()
	base.player_docked.connect(tracker.on_docked)

	var icon: Area2D = CampaignFleetIconScene.instantiate()
	icon.behavior_type = icon.BehaviorType.PLAYER
	tree.root.add_child(icon)
	icon.setup(fleet, Vector2.ZERO)
	icon.global_position = Vector2(500, 0)
	icon.set_move_target(Vector2(0, 0))

	for i in 10:
		await tree.physics_frame

	if not tracker.fired:
		failures.append("HomeBase: expected player_docked to fire once the player icon reaches the base")
	if fleet.ship_compositions[0]["current_hp"] != 100.0 or fleet.ship_compositions[0]["current_shield"] != 50.0:
		failures.append("HomeBase: expected fleet repaired to full on docking, got %s" % fleet.ship_compositions[0])

	icon.queue_free()
	base.queue_free()
	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, scene/script not found.

- [ ] **Step 3: Write minimal implementation**

`scripts/campaign/home_base.gd`:

```gdscript
class_name HomeBase
extends Area2D

signal player_docked

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	if area is CampaignFleetIcon and area.behavior_type == CampaignFleetIcon.BehaviorType.PLAYER:
		area.fleet.repair_to_full()
		player_docked.emit()
```

`scenes/campaign/home_base.tscn`:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/campaign/home_base.gd" id="1"]

[sub_resource type="CircleShape2D" id="1"]
radius = 30.0

[node name="HomeBase" type="Area2D"]
script = ExtResource("1")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("1")

[node name="Polygon2D" type="Polygon2D" parent="."]
polygon = PackedVector2Array(-20, -20, 20, -20, 20, 20, -20, 20)
color = Color(0.3, 0.9, 0.5, 1)
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/home_base.gd scenes/campaign/home_base.tscn tests/test_home_base.gd
git commit -m "Add HomeBase repair-on-dock trigger"
```

---

### Task 7: CampaignState autoload

**Files:**
- Create: `scripts/campaign/campaign_state.gd`
- Modify: `project.godot` (add `[autoload]` section)
- Modify: `tests/run_tests.gd` (register all new synchronous tests from
  Tasks 1-4 and 7; async tests from Tasks 5-6 run alongside the existing
  async tests)
- Test: `tests/test_campaign_state.gd`

**Interfaces:**
- Consumes: `CampaignFleet` (Task 1).
- Produces: autoload singleton `CampaignState` (accessed globally as
  `CampaignState`, no `class_name`) with `var player_fleet:
  CampaignFleet`, `var enemy_fleets: Array[CampaignFleet]`,
  `var active_enemy_fleet: CampaignFleet`; methods
  `start_engagement(enemy_fleet: CampaignFleet) -> void`,
  `resolve_engagement(player_survivors: Array[Dictionary],
  enemy_survivors: Array[Dictionary]) -> void`, `reset() -> void` (clears
  all state — needed so standalone combat tests in the existing
  `test_combat_scene.gd` aren't affected by `CampaignState` being a
  process-wide autoload shared across the whole test run).

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

const CampaignState = preload("res://scripts/campaign/campaign_state.gd")
const CampaignFleet = preload("res://scripts/campaign/campaign_fleet.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var state := CampaignState.new()
	var player := CampaignFleet.new()
	player.ship_compositions = [{"max_hp": 100.0, "current_hp": 50.0, "max_shield": 50.0, "current_shield": 10.0}]
	var enemy := CampaignFleet.new()
	enemy.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
	state.player_fleet = player
	state.enemy_fleets = [enemy]

	state.start_engagement(enemy)
	if state.active_enemy_fleet != enemy:
		failures.append("start_engagement: expected active_enemy_fleet == enemy")

	state.resolve_engagement(
		[{"max_hp": 100.0, "current_hp": 30.0, "max_shield": 50.0, "current_shield": 0.0}],
		[]
	)
	if player.ship_compositions[0]["current_hp"] != 30.0:
		failures.append("resolve_engagement: expected player fleet updated with survivor data")
	if not enemy.is_destroyed():
		failures.append("resolve_engagement: expected enemy fleet marked destroyed with empty survivors")
	if state.enemy_fleets.has(enemy):
		failures.append("resolve_engagement: expected destroyed enemy fleet removed from enemy_fleets")
	if state.active_enemy_fleet != null:
		failures.append("resolve_engagement: expected active_enemy_fleet cleared after resolution")

	state.reset()
	if state.player_fleet != null or not state.enemy_fleets.is_empty() or state.active_enemy_fleet != null:
		failures.append("reset: expected all state cleared")

	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL, script not found.

- [ ] **Step 3: Write minimal implementation**

```gdscript
extends Node

var player_fleet: CampaignFleet
var enemy_fleets: Array[CampaignFleet] = []
var active_enemy_fleet: CampaignFleet

func start_engagement(enemy_fleet: CampaignFleet) -> void:
	active_enemy_fleet = enemy_fleet

func resolve_engagement(player_survivors: Array[Dictionary], enemy_survivors: Array[Dictionary]) -> void:
	player_fleet.ship_compositions = player_survivors
	if active_enemy_fleet != null:
		active_enemy_fleet.ship_compositions = enemy_survivors
		if active_enemy_fleet.is_destroyed():
			enemy_fleets.erase(active_enemy_fleet)
	active_enemy_fleet = null

func reset() -> void:
	player_fleet = null
	enemy_fleets = []
	active_enemy_fleet = null
```

- [ ] **Step 4: Add the autoload registration**

In `project.godot`, add a new section (after `[application]`, before
`[input]`):

```
[autoload]

CampaignState="*res://scripts/campaign/campaign_state.gd"
```

- [ ] **Step 5: Register new tests in run_tests.gd**

Add the four new synchronous test scripts from Tasks 1-4 and 7 to the
`test_scripts` array in `tests/run_tests.gd` (alongside the existing
entries), and add two new `await`-based blocks for the Task 5 and Task 6
async tests, following the exact pattern already used for
`test_ai_controller_targeting.gd` and `test_combat_scene.gd`:

```gdscript
		preload("res://tests/test_campaign_fleet.gd"),
		preload("res://tests/test_patrol_behavior.gd"),
		preload("res://tests/test_trader_behavior.gd"),
		preload("res://tests/test_pirate_behavior.gd"),
		preload("res://tests/test_campaign_state.gd"),
```
(added to the existing `test_scripts` array), and:

```gdscript
	var campaign_fleet_icon_test = preload("res://tests/test_campaign_fleet_icon.gd")
	var campaign_fleet_icon_failures: Array[String] = await campaign_fleet_icon_test.run_async(self)
	for f in campaign_fleet_icon_failures:
		print("FAIL [%s]: %s" % [campaign_fleet_icon_test.resource_path, f])
	total_failures += campaign_fleet_icon_failures.size()

	var home_base_test = preload("res://tests/test_home_base.gd")
	var home_base_failures: Array[String] = await home_base_test.run_async(self)
	for f in home_base_failures:
		print("FAIL [%s]: %s" % [home_base_test.resource_path, f])
	total_failures += home_base_failures.size()
```
(added after the existing async blocks, before the final pass/fail
summary).

- [ ] **Step 6: Run the full test suite to verify everything passes**

Run: `godot --headless --script tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 7: Commit**

```bash
git add scripts/campaign/campaign_state.gd project.godot tests/run_tests.gd tests/test_campaign_state.gd
git commit -m "Add CampaignState autoload and register all campaign-layer tests"
```

## What This Plan Does Not Do

No `CampaignScene` exists yet — these pieces aren't wired into a playable
map, and `CombatScene` doesn't yet know about `CampaignState`. That's
Plan B: `docs/superpowers/plans/2026-10-29-campaign-map-scene-integration.md`.
