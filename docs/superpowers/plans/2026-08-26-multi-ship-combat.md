# Multi-Ship Combat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scale the combat-core-prototype's 1v1 duel to N-vs-M fleets: box/click select one or many player ships, right-click to move/attack them (optionally in a loose formation), while every ship — player or AI — autonomously auto-fires at nearby threats and briefly chases-then-disengages a locked target while idling.

**Architecture:** `Order` (`MOVE_TO`/`ATTACK_TARGET`/`HOLD`/`RETREAT`) is unchanged. Ships resolve "who's my enemy" the same way they already resolve "who's commanding me": not knowing in advance. Each `Ship` gets `enemy_group: StringName`; auto-fire and `AIController` both query `get_tree().get_nodes_in_group(enemy_group)` for the nearest living target instead of holding a fixed reference. `FleetCommander` (new) replaces `RTSCommander`/`DirectPilot`/`ControlToggle` (direct piloting is dropped this milestone) and issues individual `Order`s per selected ship — it never needs to know how a `Ship` executes an order, same separation of concerns as the 1v1 milestone.

**Tech Stack:** Godot 4.x (GDScript), no external addons. Pure-logic pieces (`Formation`, target-selection/disengage rules) get headless GDScript unit tests via `godot --headless --script res://tests/run_tests.gd`; selection input, formation visuals, and chase/disengage feel are playtest-verified in the editor.

## Global Constraints

- Godot version: 4.7.x (confirmed via `godot --version` at the end of the prior milestone).
- Every new tunable constant (spacing, slop, aggro/leash/loiter radii, etc.) is an `@export` field, inspector-tunable, per the spec's note that this is the intended hook for a future dedicated tuning editor — do not hardcode magic numbers for these.
- Direct piloting is out of scope this milestone: `DirectPilot`, `ControlToggle`, and the old single-ship `RTSCommander` are deleted, not just unwired (spec: Out of Scope / FleetCommander note).
- No coordinated/focus-fire AI — each `AIController` targets independently (spec: Out of Scope).
- Ship-to-ship physical spacing relies entirely on existing `CharacterBody2D` + `CircleShape2D` collision via `move_and_slide()` — no new steering/avoidance system (spec: Data Flow step 5).

---

### Task 1: `Formation` pure logic

**Files:**
- Create: `scripts/combat/formation.gd`
- Create: `tests/test_formation.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `class_name Formation` (extends `RefCounted`), `enum Type { NONE, LINE, WEDGE, BOX, CIRCLE }`, static `Formation.compute_slots(type: Type, count: int, anchor: Vector2, facing: Vector2, spacing: float, slop: float) -> Array[Vector2]`. `NONE` is never passed to `compute_slots` — callers special-case it themselves (Task 5).

- [ ] **Step 1: Write `Formation`**

`scripts/combat/formation.gd`:
```gdscript
class_name Formation
extends RefCounted

enum Type { NONE, LINE, WEDGE, BOX, CIRCLE }

static func compute_slots(type: Type, count: int, anchor: Vector2, facing: Vector2, spacing: float, slop: float) -> Array[Vector2]:
	var effective_facing := facing if facing.length() > 0.01 else Vector2.RIGHT
	effective_facing = effective_facing.normalized()
	var slots: Array[Vector2] = []
	match type:
		Type.LINE:
			slots = _line_slots(count, anchor, effective_facing, spacing)
		Type.WEDGE:
			slots = _wedge_slots(count, anchor, effective_facing, spacing)
		Type.CIRCLE:
			slots = _circle_slots(count, anchor, spacing)
		_:
			slots = _box_slots(count, anchor, effective_facing, spacing)
	if slop > 0.0:
		for i in slots.size():
			var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * spacing * slop
			slots[i] += jitter
	return slots

static func _line_slots(count: int, anchor: Vector2, facing: Vector2, spacing: float) -> Array[Vector2]:
	var perpendicular := facing.rotated(PI / 2.0)
	var slots: Array[Vector2] = []
	var center_index := (count - 1) / 2.0
	for i in count:
		slots.append(anchor + perpendicular * spacing * (i - center_index))
	return slots

static func _wedge_slots(count: int, anchor: Vector2, facing: Vector2, spacing: float) -> Array[Vector2]:
	var perpendicular := facing.rotated(PI / 2.0)
	var slots: Array[Vector2] = [anchor]
	for i in range(1, count):
		var rank := ceili(i / 2.0)
		var side := 1.0 if i % 2 == 1 else -1.0
		slots.append(anchor - facing * spacing * rank + perpendicular * spacing * rank * side)
	return slots

static func _box_slots(count: int, anchor: Vector2, facing: Vector2, spacing: float) -> Array[Vector2]:
	var perpendicular := facing.rotated(PI / 2.0)
	var columns := ceili(sqrt(count))
	var row_count := ceili(float(count) / columns)
	var slots: Array[Vector2] = []
	for i in count:
		var row := i / columns
		var col := i % columns
		var row_offset := row - (row_count - 1) / 2.0
		var col_offset := col - (columns - 1) / 2.0
		slots.append(anchor + perpendicular * spacing * col_offset - facing * spacing * row_offset)
	return slots

static func _circle_slots(count: int, anchor: Vector2, spacing: float) -> Array[Vector2]:
	var slots: Array[Vector2] = []
	var angle_step := TAU / count
	for i in count:
		slots.append(anchor + Vector2(spacing, 0).rotated(angle_step * i))
	return slots
```

- [ ] **Step 2: Write the `Formation` test**

`tests/test_formation.gd`:
```gdscript
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_line(failures)
	_check_wedge(failures)
	_check_box(failures)
	_check_circle(failures)
	return failures

static func _check_line(failures: Array[String]) -> void:
	var anchor := Vector2(100, 100)
	var facing := Vector2.RIGHT
	var slots := Formation.compute_slots(Formation.Type.LINE, 3, anchor, facing, 50.0, 0.0)
	if slots.size() != 3:
		failures.append("LINE: expected 3 slots, got %d" % slots.size())
		return
	for slot in slots:
		var along: float = (slot - anchor).dot(facing)
		if not is_equal_approx(along, 0.0):
			failures.append("LINE: expected slot perpendicular to facing, got along-facing offset %s" % along)
	if not is_equal_approx(slots[0].distance_to(slots[1]), 50.0):
		failures.append("LINE: expected 50.0 spacing between slots 0 and 1, got %s" % slots[0].distance_to(slots[1]))
	if not is_equal_approx(slots[1].distance_to(slots[2]), 50.0):
		failures.append("LINE: expected 50.0 spacing between slots 1 and 2, got %s" % slots[1].distance_to(slots[2]))

static func _check_wedge(failures: Array[String]) -> void:
	var anchor := Vector2(0, 0)
	var facing := Vector2.RIGHT
	var slots := Formation.compute_slots(Formation.Type.WEDGE, 3, anchor, facing, 50.0, 0.0)
	if slots.size() != 3:
		failures.append("WEDGE: expected 3 slots, got %d" % slots.size())
		return
	if not slots[0].is_equal_approx(anchor):
		failures.append("WEDGE: expected apex slot at anchor, got %s" % slots[0])
	for i in range(1, slots.size()):
		var along: float = (slots[i] - anchor).dot(facing)
		if along >= 0.0:
			failures.append("WEDGE: expected trailing slot %d behind the apex, got along-facing offset %s" % [i, along])

static func _check_box(failures: Array[String]) -> void:
	var anchor := Vector2(0, 0)
	var slots := Formation.compute_slots(Formation.Type.BOX, 4, anchor, Vector2.RIGHT, 50.0, 0.0)
	if slots.size() != 4:
		failures.append("BOX: expected 4 slots, got %d" % slots.size())
		return
	var max_dist := 0.0
	for slot in slots:
		max_dist = max(max_dist, slot.distance_to(anchor))
	if max_dist > 100.0:
		failures.append("BOX: expected slots within a tight grid of anchor, farthest slot was %s away" % max_dist)

static func _check_circle(failures: Array[String]) -> void:
	var anchor := Vector2(0, 0)
	var slots := Formation.compute_slots(Formation.Type.CIRCLE, 4, anchor, Vector2.RIGHT, 50.0, 0.0)
	if slots.size() != 4:
		failures.append("CIRCLE: expected 4 slots, got %d" % slots.size())
		return
	for slot in slots:
		if not is_equal_approx(slot.distance_to(anchor), 50.0):
			failures.append("CIRCLE: expected slot at radius 50.0 from anchor, got %s" % slot.distance_to(anchor))
```

- [ ] **Step 3: Register the test and run the suite**

In `tests/run_tests.gd`, add `preload("res://tests/test_formation.gd"),` to the `test_scripts` array.

Run: `godot --headless --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 4: Commit**

```bash
git add scripts/combat/formation.gd tests/test_formation.gd tests/run_tests.gd
git commit -m "Add Formation pure slot-layout logic"
```

---

### Task 2: `Ship` — generalized auto-fire targeting

**Files:**
- Modify: `scripts/ship/ship.gd`
- Modify: `tests/test_ship.gd`

**Interfaces:**
- Consumes: `Order` (unchanged).
- Produces: `Ship.enemy_group: StringName` (`@export`), static `Ship.nearest_in_range(candidates: Array, own_position: Vector2, max_range: float) -> Node2D`, static `Ship.pick_autofire_target(order: Order, candidates: Array, own_position: Vector2, max_range: float) -> Node2D`. Both are pure and reused by `AIController` in Task 4.

- [ ] **Step 1: Add `enemy_group` and the pure targeting helpers**

In `scripts/ship/ship.gd`, add near the top (after the existing `var control_mode` line):

```gdscript
@export var enemy_group: StringName = &""
```

Add these two static functions anywhere below `_on_hull_destroyed`:

```gdscript
static func nearest_in_range(candidates: Array, own_position: Vector2, max_range: float) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := max_range
	for c in candidates:
		if c is Node2D and is_instance_valid(c):
			var d: float = own_position.distance_to(c.global_position)
			if d <= nearest_dist:
				nearest_dist = d
				nearest = c
	return nearest

static func pick_autofire_target(order: Order, candidates: Array, own_position: Vector2, max_range: float) -> Node2D:
	if order.type == Order.Type.ATTACK_TARGET:
		return order.target_ship if is_instance_valid(order.target_ship) else null
	return Ship.nearest_in_range(candidates, own_position, max_range)
```

- [ ] **Step 2: Replace `_process_weapons` to auto-fire generally**

Replace the existing `_process_weapons` method with:

```gdscript
func _process_weapons() -> void:
	if weapon_mounts.is_empty():
		return
	var max_range := attack_range()
	var candidates: Array = get_tree().get_nodes_in_group(enemy_group) if enemy_group != &"" else []
	var target := Ship.pick_autofire_target(current_order, candidates, global_position, max_range)
	if target == null:
		return
	for mount in weapon_mounts:
		mount.try_fire(target)
```

- [ ] **Step 3: Write the targeting test**

In `tests/test_ship.gd`, add a new static check function and call it from `run()`:

```gdscript
static func run() -> Array[String]:
	var failures: Array[String] = []

	_check_scene_structure(failures)
	_check_ship_logic(failures)
	_check_autofire_targeting(failures)

	return failures
```

```gdscript
static func _check_autofire_targeting(failures: Array[String]) -> void:
	var near := Node2D.new()
	near.global_position = Vector2(20, 0)
	var far := Node2D.new()
	far.global_position = Vector2(80, 0)
	var candidates: Array = [far, near]

	var nearest := Ship.nearest_in_range(candidates, Vector2.ZERO, 100.0)
	if nearest != near:
		failures.append("nearest_in_range: expected the closer candidate, got %s" % nearest)

	var out_of_range := Ship.nearest_in_range(candidates, Vector2.ZERO, 10.0)
	if out_of_range != null:
		failures.append("nearest_in_range: expected null when all candidates exceed max_range, got %s" % out_of_range)

	var explicit_target := Node2D.new()
	explicit_target.global_position = Vector2(500, 0)
	var attack_order := Order.attack_target(explicit_target)
	var picked := Ship.pick_autofire_target(attack_order, candidates, Vector2.ZERO, 100.0)
	if picked != explicit_target:
		failures.append("pick_autofire_target: expected ATTACK_TARGET to override nearest-in-range, got %s" % picked)

	var hold_order := Order.hold()
	var auto_picked := Ship.pick_autofire_target(hold_order, candidates, Vector2.ZERO, 100.0)
	if auto_picked != near:
		failures.append("pick_autofire_target: expected HOLD to auto-target the nearest in range, got %s" % auto_picked)

	near.free()
	far.free()
	explicit_target.free()
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/ship.gd tests/test_ship.gd
git commit -m "Generalize Ship auto-fire to target nearest enemy_group member"
```

---

### Task 3: `Ship` — HOLD loiter / chase / disengage

**Files:**
- Modify: `scripts/ship/ship.gd`
- Modify: `tests/test_ship.gd`

**Interfaces:**
- Consumes: `Ship.nearest_in_range` (Task 2).
- Produces: `Ship.aggro_range`, `Ship.leash_distance`, `Ship.loiter_radius`, `Ship.loiter_interval`, `Ship.arrival_radius` (all `@export`), static `Ship.should_disengage(own_position: Vector2, target_position: Vector2, hold_center: Vector2, aggro_range: float, leash_distance: float) -> bool`.

- [ ] **Step 1: Add the new tunables and hold-state fields**

In `scripts/ship/ship.gd`, add alongside `enemy_group`:

```gdscript
@export var arrival_radius: float = 20.0
@export var aggro_range: float = 0.0
@export var leash_distance: float = 250.0
@export var loiter_radius: float = 40.0
@export var loiter_interval: float = 3.0
```

Add alongside `var current_order: Order`:

```gdscript
var _hold_center: Vector2 = Vector2.ZERO
var _loiter_target: Vector2 = Vector2.ZERO
var _loiter_timer: float = 0.0
var _chase_target: Node2D
```

- [ ] **Step 2: Initialize hold state through `execute_order` and `_ready`**

Replace `execute_order`:

```gdscript
func execute_order(order: Order) -> void:
	current_order = order
	if order.type == Order.Type.HOLD:
		_hold_center = global_position
		_loiter_target = global_position
		_loiter_timer = 0.0
		_chase_target = null
```

In `_ready`, replace `current_order = Order.hold()` with `execute_order(Order.hold())`.

- [ ] **Step 3: Add the disengage rule and hold sub-state machine**

Add this static function anywhere below `pick_autofire_target`:

```gdscript
static func should_disengage(own_position: Vector2, target_position: Vector2, hold_center: Vector2, aggro_range: float, leash_distance: float) -> bool:
	if own_position.distance_to(target_position) > aggro_range:
		return true
	if own_position.distance_to(hold_center) > leash_distance:
		return true
	return false
```

Replace the `Order.Type.HOLD:` branch in `_process_order_movement` with `_process_hold(delta)`, and the `Order.Type.MOVE_TO:` branch with an arrival check:

```gdscript
func _process_order_movement(delta: float) -> void:
	match current_order.type:
		Order.Type.MOVE_TO:
			if global_position.distance_to(current_order.target_position) <= arrival_radius:
				execute_order(Order.hold())
			else:
				_steer_to(current_order.target_position, delta)
		Order.Type.ATTACK_TARGET:
			if not is_instance_valid(current_order.target_ship):
				execute_order(Order.hold())
				return
			var target_pos: Vector2 = current_order.target_ship.global_position
			if global_position.distance_to(target_pos) > attack_range():
				_steer_to(target_pos, delta)
			else:
				velocity = velocity.move_toward(Vector2.ZERO, engine.acceleration * delta)
				engine.velocity = velocity
		Order.Type.RETREAT:
			var away := global_position + (global_position - current_order.target_position).normalized() * 500.0
			_steer_to(away, delta)
		Order.Type.HOLD:
			_process_hold(delta)
```

Add the hold sub-state machine below `_steer_to`:

```gdscript
func _process_hold(delta: float) -> void:
	var effective_aggro := aggro_range if aggro_range > 0.0 else attack_range()
	if _chase_target != null and is_instance_valid(_chase_target):
		if Ship.should_disengage(global_position, _chase_target.global_position, _hold_center, effective_aggro, leash_distance):
			_chase_target = null
		else:
			if global_position.distance_to(_chase_target.global_position) > attack_range():
				_steer_to(_chase_target.global_position, delta)
			else:
				velocity = velocity.move_toward(Vector2.ZERO, engine.acceleration * delta)
				engine.velocity = velocity
			return
	else:
		_chase_target = null

	var candidates: Array = get_tree().get_nodes_in_group(enemy_group) if enemy_group != &"" else []
	var candidate := Ship.nearest_in_range(candidates, global_position, effective_aggro)
	if candidate != null:
		_chase_target = candidate
		return

	_process_loiter(delta)

func _process_loiter(delta: float) -> void:
	if global_position.distance_to(_loiter_target) < 5.0:
		_loiter_timer -= delta
		if _loiter_timer <= 0.0:
			_loiter_target = _hold_center + Vector2(randf_range(-loiter_radius, loiter_radius), randf_range(-loiter_radius, loiter_radius))
			_loiter_timer = loiter_interval
	_steer_to(_loiter_target, delta)
```

- [ ] **Step 4: Write the disengage-rule test**

In `tests/test_ship.gd`, add and register `_check_disengage_rule`:

```gdscript
static func _check_disengage_rule(failures: Array[String]) -> void:
	var hold_center := Vector2.ZERO
	if Ship.should_disengage(Vector2(10, 0), Vector2(20, 0), hold_center, 100.0, 250.0):
		failures.append("should_disengage: expected false when target is within aggro_range and ship within leash")
	if not Ship.should_disengage(Vector2(10, 0), Vector2(300, 0), hold_center, 100.0, 250.0):
		failures.append("should_disengage: expected true when target exceeds aggro_range")
	if not Ship.should_disengage(Vector2(300, 0), Vector2(310, 0), hold_center, 100.0, 250.0):
		failures.append("should_disengage: expected true when ship exceeds leash_distance from hold_center")
```

Call it from `run()` alongside the other checks.

- [ ] **Step 5: Run the tests**

Run: `godot --headless --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 6: Commit**

```bash
git add scripts/ship/ship.gd tests/test_ship.gd
git commit -m "Add Ship HOLD loiter/chase/disengage sub-state machine"
```

---

### Task 4: `AIController` — fleet-aware targeting

**Files:**
- Modify: `scripts/controllers/ai_controller.gd`
- Create: `tests/test_ai_controller_targeting.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `Ship.nearest_in_range` (Task 2).
- Produces: `AIController.setup(ship: Ship, enemy_group: StringName)` (breaking change from `setup(ship, enemy: Ship)`). `AIController.next_state` is unchanged.

**Note:** `combat_scene.gd`/`combat_scene.tscn` still call the old `setup(enemy_ship, player_ship)` and will not compile correctly against this new signature. `tests/test_combat_scene.gd` is temporarily removed from the runner in this task — it gets rewritten and re-registered in Task 6 once `CombatScene` is rebuilt for fleets. This is intentional: don't patch the old single-ship `CombatScene` to limp along, per the design spec's replacement of `RTSCommander`/`DirectPilot`/`ControlToggle`.

- [ ] **Step 1: Change `AIController` to resolve targets via group membership**

Replace `scripts/controllers/ai_controller.gd` in full:

```gdscript
class_name AIController
extends Node

enum State { APPROACH, ENGAGE, RETREAT }

@export var retreat_hp_ratio: float = 0.25

var state: State = State.APPROACH
var ship: Ship
var enemy_group: StringName

func setup(p_ship: Ship, p_enemy_group: StringName) -> void:
	ship = p_ship
	enemy_group = p_enemy_group

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(ship):
		return
	var candidates: Array = get_tree().get_nodes_in_group(enemy_group)
	var enemy := Ship.nearest_in_range(candidates, ship.global_position, INF)
	if enemy == null:
		return
	var hp_ratio: float = ship.hull.current_hp / ship.hull.max_hp if ship.hull.max_hp > 0.0 else 0.0
	var in_range: bool = ship.global_position.distance_to(enemy.global_position) <= ship.attack_range()
	state = AIController.next_state(state, hp_ratio, retreat_hp_ratio, in_range)
	match state:
		State.APPROACH, State.ENGAGE:
			ship.execute_order(Order.attack_target(enemy))
		State.RETREAT:
			ship.execute_order(Order.retreat(enemy.global_position))

static func next_state(state: State, hp_ratio: float, retreat_hp_ratio: float, in_attack_range: bool) -> State:
	if hp_ratio <= retreat_hp_ratio:
		return State.RETREAT
	if state == State.RETREAT and hp_ratio > retreat_hp_ratio + 0.1:
		return State.APPROACH
	if state == State.APPROACH and in_attack_range:
		return State.ENGAGE
	if state == State.ENGAGE and not in_attack_range:
		return State.APPROACH
	return state
```

- [ ] **Step 2: Remove `test_combat_scene.gd` from the runner (temporarily)**

In `tests/run_tests.gd`, delete the `preload("res://tests/test_combat_scene.gd"),` line from `test_scripts`, and delete the entire block below the `for` loop that awaits `test_combat_scene.gd`'s `run_async` (the `var combat_scene_test = ...` through `total_failures += combat_scene_failures.size()` lines). Leave `tests/test_combat_scene.gd` itself in place on disk — Task 6 rewrites it.

- [ ] **Step 3: Write the group-targeting integration test**

`tests/test_ai_controller_targeting.gd`:
```gdscript
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

	await tree.process_frame

	if ai_ship.current_order.type != Order.Type.ATTACK_TARGET:
		failures.append("AIController: expected ATTACK_TARGET order once a group member is in range, got %s" % ai_ship.current_order.type)
	elif ai_ship.current_order.target_ship != target_ship:
		failures.append("AIController: expected to target the nearest group member, got %s" % ai_ship.current_order.target_ship)

	ai_ship.queue_free()
	target_ship.queue_free()
	far_ship.queue_free()
	controller.queue_free()

	return failures
```

- [ ] **Step 4: Register the new async test in the runner**

In `tests/run_tests.gd`, add a block mirroring the existing `test_ship.gd` async registration (place it after the synchronous `test_scripts` loop):

```gdscript
	var ai_targeting_test = preload("res://tests/test_ai_controller_targeting.gd")
	var ai_targeting_failures: Array[String] = await ai_targeting_test.run_async(self)
	for f in ai_targeting_failures:
		print("FAIL [%s]: %s" % [ai_targeting_test.resource_path, f])
	total_failures += ai_targeting_failures.size()
```

- [ ] **Step 5: Run the tests**

Run: `godot --headless --script res://tests/run_tests.gd`
Expected: `All tests passed.` (Note: `combat_scene.gd` will not be exercised by this run since nothing preloads it — confirm no unrelated failures appear.)

- [ ] **Step 6: Commit**

```bash
git add scripts/controllers/ai_controller.gd tests/test_ai_controller_targeting.gd tests/run_tests.gd
git commit -m "Make AIController resolve targets via enemy_group membership"
```

---

### Task 5: `FleetCommander` — selection, formations, orders

**Files:**
- Create: `scripts/controllers/fleet_commander.gd`
- Create: `tests/test_fleet_commander.gd`
- Modify: `tests/run_tests.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: `Ship.execute_order`, `Order.move_to`/`Order.attack_target`, `Formation.compute_slots` (Task 1).
- Produces: `class_name FleetCommander` (extends `Node2D`) with `setup(ships: Array[Ship], enemy_group: StringName) -> void`, `@export var formation_spacing: float`, `@export var formation_slop: float`, `selected_ships: Array[Ship]`, `active_formation: Formation.Type`. Static pure helpers `FleetCommander.ship_at_point`, `FleetCommander.ships_in_rect`, `FleetCommander.assign_slots` (used by `CombatScene`/tests, but not consumed elsewhere).

- [ ] **Step 1: Add formation hotkey input actions**

Open `project.godot`'s `[input]` section and add:
```ini
formation_none={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":49,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
formation_line={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":50,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
formation_wedge={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":51,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
formation_box={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":52,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
formation_circle={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":53,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```
(Physical keycodes 49-53 are the '1'-'5' number keys, following the same convention as the existing `pilot_thrust`/`toggle_control_mode` entries in this file.)

- [ ] **Step 2: Write `FleetCommander`**

`scripts/controllers/fleet_commander.gd`:
```gdscript
class_name FleetCommander
extends Node2D

const SELECT_RADIUS := 24.0
const CLICK_TARGET_RADIUS := 40.0
const DRAG_THRESHOLD := 6.0

@export var formation_spacing: float = 60.0
@export var formation_slop: float = 0.15

var ships: Array[Ship] = []
var enemy_group: StringName
var selected_ships: Array[Ship] = []
var active_formation: Formation.Type = Formation.Type.NONE

var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false

func setup(p_ships: Array[Ship], p_enemy_group: StringName) -> void:
	ships = p_ships
	enemy_group = p_enemy_group

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("formation_none"):
		active_formation = Formation.Type.NONE
	elif event.is_action_pressed("formation_line"):
		active_formation = Formation.Type.LINE
	elif event.is_action_pressed("formation_wedge"):
		active_formation = Formation.Type.WEDGE
	elif event.is_action_pressed("formation_box"):
		active_formation = Formation.Type.BOX
	elif event.is_action_pressed("formation_circle"):
		active_formation = Formation.Type.CIRCLE
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _dragging:
		queue_redraw()

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_start = world_pos
			_dragging = true
		else:
			_dragging = false
			if _drag_start.distance_to(world_pos) < DRAG_THRESHOLD:
				var picked := FleetCommander.ship_at_point(ships, world_pos, SELECT_RADIUS)
				selected_ships = [picked] if picked != null else []
			else:
				var rect := Rect2(_drag_start, Vector2.ZERO).expand(world_pos)
				selected_ships = FleetCommander.ships_in_rect(ships, rect)
			queue_redraw()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_issue_order(world_pos)

func _issue_order(world_pos: Vector2) -> void:
	if selected_ships.is_empty():
		return
	var enemy_candidates: Array = get_tree().get_nodes_in_group(enemy_group)
	var target_enemy := FleetCommander.ship_at_point(enemy_candidates, world_pos, CLICK_TARGET_RADIUS)
	if target_enemy != null:
		for ship in selected_ships:
			ship.execute_order(Order.attack_target(target_enemy))
		return
	var destinations := _compute_destinations(world_pos)
	for ship in selected_ships:
		if destinations.has(ship):
			ship.execute_order(Order.move_to(destinations[ship]))

func _compute_destinations(world_pos: Vector2) -> Dictionary:
	if active_formation == Formation.Type.NONE:
		var centroid := _group_centroid()
		var destinations: Dictionary = {}
		for ship in selected_ships:
			destinations[ship] = world_pos + (ship.global_position - centroid)
		return destinations
	var facing := _group_facing(world_pos)
	var slots := Formation.compute_slots(active_formation, selected_ships.size(), world_pos, facing, formation_spacing, formation_slop)
	return FleetCommander.assign_slots(selected_ships, slots)

func _group_centroid() -> Vector2:
	var sum := Vector2.ZERO
	for ship in selected_ships:
		sum += ship.global_position
	return sum / selected_ships.size()

func _group_facing(world_pos: Vector2) -> Vector2:
	var delta := world_pos - _group_centroid()
	return delta.normalized() if delta.length() > 0.01 else Vector2.RIGHT

func _draw() -> void:
	for ship in selected_ships:
		if is_instance_valid(ship):
			draw_arc(ship.global_position, SELECT_RADIUS, 0, TAU, 24, Color(0.2, 1.0, 0.4), 2.0)
	if _dragging:
		var rect := Rect2(_drag_start, Vector2.ZERO).expand(get_global_mouse_position())
		draw_rect(rect, Color(0.2, 1.0, 0.4, 0.3), false, 2.0)

static func ship_at_point(candidates: Array, point: Vector2, radius: float) -> Ship:
	var best: Ship = null
	var best_dist := radius
	for c in candidates:
		if c is Ship and is_instance_valid(c):
			var d: float = c.global_position.distance_to(point)
			if d <= best_dist:
				best_dist = d
				best = c
	return best

static func ships_in_rect(candidates: Array[Ship], rect: Rect2) -> Array[Ship]:
	var result: Array[Ship] = []
	for c in candidates:
		if is_instance_valid(c) and rect.has_point(c.global_position):
			result.append(c)
	return result

static func assign_slots(ships_to_assign: Array[Ship], slots: Array[Vector2]) -> Dictionary:
	var assignment: Dictionary = {}
	var remaining_ships := ships_to_assign.duplicate()
	var remaining_slots := slots.duplicate()
	while remaining_ships.size() > 0 and remaining_slots.size() > 0:
		var best_ship: Ship = null
		var best_slot_index := -1
		var best_dist := INF
		for ship in remaining_ships:
			for i in remaining_slots.size():
				var d: float = ship.global_position.distance_to(remaining_slots[i])
				if d < best_dist:
					best_dist = d
					best_ship = ship
					best_slot_index = i
		assignment[best_ship] = remaining_slots[best_slot_index]
		remaining_ships.erase(best_ship)
		remaining_slots.remove_at(best_slot_index)
	return assignment
```

- [ ] **Step 3: Write the pure-helper tests**

`tests/test_fleet_commander.gd`:
```gdscript
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_ship_at_point(failures)
	_check_ships_in_rect(failures)
	_check_assign_slots(failures)
	return failures

static func _make_ship(pos: Vector2) -> Ship:
	var ship := Ship.new()
	ship.position = pos
	return ship

static func _check_ship_at_point(failures: Array[String]) -> void:
	var near := _make_ship(Vector2(10, 0))
	var far := _make_ship(Vector2(200, 0))
	var picked := FleetCommander.ship_at_point([far, near], Vector2.ZERO, 50.0)
	if picked != near:
		failures.append("ship_at_point: expected the nearest ship within radius, got %s" % picked)
	var none := FleetCommander.ship_at_point([far], Vector2.ZERO, 50.0)
	if none != null:
		failures.append("ship_at_point: expected null when nothing is within radius, got %s" % none)
	near.free()
	far.free()

static func _check_ships_in_rect(failures: Array[String]) -> void:
	var inside := _make_ship(Vector2(10, 10))
	var outside := _make_ship(Vector2(1000, 1000))
	var rect := Rect2(Vector2(0, 0), Vector2(50, 50))
	var result := FleetCommander.ships_in_rect([inside, outside], rect)
	if result.size() != 1 or result[0] != inside:
		failures.append("ships_in_rect: expected only the ship inside the rect, got %s" % [result])
	inside.free()
	outside.free()

static func _check_assign_slots(failures: Array[String]) -> void:
	var ship_a := _make_ship(Vector2(0, 0))
	var ship_b := _make_ship(Vector2(100, 0))
	var slots: Array[Vector2] = [Vector2(90, 0), Vector2(0, 5)]
	var assignment := FleetCommander.assign_slots([ship_a, ship_b], slots)
	if assignment.get(ship_a) != Vector2(0, 5):
		failures.append("assign_slots: expected ship_a assigned its nearest slot (0,5), got %s" % assignment.get(ship_a))
	if assignment.get(ship_b) != Vector2(90, 0):
		failures.append("assign_slots: expected ship_b assigned its nearest slot (90,0), got %s" % assignment.get(ship_b))
	ship_a.free()
	ship_b.free()
```

- [ ] **Step 4: Register and run the tests**

In `tests/run_tests.gd`, add `preload("res://tests/test_fleet_commander.gd"),` to `test_scripts`.

Run: `godot --headless --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Manual verification**

Build a scratch scene: a `Node2D` root with 3 `scenes/ship/ship.tscn` instances in group `"scratch_player"` roughly 60px apart, 1 instance in group `"scratch_enemy"` far away, and a `FleetCommander` child (attach `fleet_commander.gd`). In a temporary `_ready()` on the root, call `$FleetCommander.setup([the 3 player ships], "scratch_enemy")`. Run the scene (F6) and confirm: click-drag a box over the 3 ships shows selection rings on all 3; single-click one ship selects only it; pressing `3` then right-clicking empty space sends the 3 selected ships into a wedge around the click point; right-clicking directly on the enemy ship issues `attack_target` to all selected. Delete the scratch scene afterward.

- [ ] **Step 6: Commit**

```bash
git add scripts/controllers/fleet_commander.gd tests/test_fleet_commander.gd tests/run_tests.gd project.godot
git commit -m "Add FleetCommander for multi-ship selection, formations, and orders"
```

---

### Task 6: `CombatScene` — assemble the N-vs-M fleet battle

**Files:**
- Modify: `scripts/combat/combat_scene.gd`
- Modify: `scenes/combat/combat_scene.tscn`
- Modify: `tests/test_combat_scene.gd`
- Modify: `tests/run_tests.gd`
- Modify: `project.godot`
- Delete: `scripts/controllers/rts_commander.gd`, `scripts/controllers/rts_commander.gd.uid`, `scripts/controllers/direct_pilot.gd`, `scripts/controllers/direct_pilot.gd.uid`, `scripts/controllers/control_toggle.gd`, `scripts/controllers/control_toggle.gd.uid`

**Interfaces:**
- Consumes: `Ship`, `Ship.enemy_group`, `FleetCommander.setup` (Task 5), `AIController.setup(ship, enemy_group)` (Task 4).
- Produces: the playable entry point. No later task consumes this one.

- [ ] **Step 1: Delete the superseded controllers**

```bash
git rm scripts/controllers/rts_commander.gd scripts/controllers/rts_commander.gd.uid scripts/controllers/direct_pilot.gd scripts/controllers/direct_pilot.gd.uid scripts/controllers/control_toggle.gd scripts/controllers/control_toggle.gd.uid
```

- [ ] **Step 2: Remove direct-pilot input actions and `Ship.ControlMode`**

In `project.godot`'s `[input]` section, delete the `pilot_turn_left`, `pilot_turn_right`, `pilot_thrust`, `pilot_fire`, and `toggle_control_mode` blocks entirely.

In `scripts/ship/ship.gd`, delete the line `enum ControlMode { ORDER_BASED, DIRECT }` and the line `var control_mode: ControlMode = ControlMode.ORDER_BASED`. Replace `_physics_process`:

```gdscript
func _physics_process(delta: float) -> void:
	_process_order_movement(delta)
	move_and_slide()
	_process_weapons()
```

- [ ] **Step 3: Rewrite `CombatScene` for configurable fleets**

`scripts/combat/combat_scene.gd`:
```gdscript
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
```

- [ ] **Step 4: Rebuild the `CombatScene` scene**

In the Godot editor: open `scenes/combat/combat_scene.tscn`. Delete the `PlayerShip`, `EnemyShip`, `RTSCommander`, `DirectPilot`, and `ControlToggle` nodes. Add a `FleetCommander` node (`Node2D`, attach `scripts/controllers/fleet_commander.gd`, keep it at position `(0, 0)` with no rotation — its `_draw()` calls assume its local space matches world space). Keep `AIController`'s script reference removed from the scene (it's now instantiated per-enemy-ship at runtime in `_ready`) — delete the old `AIController` node too. Keep `ResultLabel` as-is. Save.

Confirm `scripts/combat/combat_scene.gd`'s `@onready var fleet_commander: FleetCommander = $FleetCommander` matches the node name you gave it.

- [ ] **Step 5: Rewrite the `CombatScene` integration test**

Replace `tests/test_combat_scene.gd` in full:

```gdscript
extends RefCounted

const CombatSceneScene = preload("res://scenes/combat/combat_scene.tscn")

# See tests/test_ship.gd's run_async note: _ready()'s fleet spawning and signal wiring
# only runs on the next process frame after the scene enters the live SceneTree -- and
# combat_scene.gd's own _ready() now awaits an *additional* internal frame before wiring
# hull signals (see Task 6 Step 3), so this must await twice before asserting on any of it.
static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(scene)

	await tree.process_frame
	await tree.process_frame

	if scene.player_ships.size() != scene.player_spawn_points.size():
		failures.append("run_async: expected %d player ships spawned, got %d" % [scene.player_spawn_points.size(), scene.player_ships.size()])
	if scene.enemy_ships.size() != scene.enemy_spawn_points.size():
		failures.append("run_async: expected %d enemy ships spawned, got %d" % [scene.enemy_spawn_points.size(), scene.enemy_ships.size()])

	for ship in scene.player_ships:
		if ship.enemy_group != scene.ENEMY_GROUP:
			failures.append("run_async: expected player ship enemy_group == ENEMY_GROUP, got %s" % ship.enemy_group)
	for ship in scene.enemy_ships:
		if ship.enemy_group != scene.PLAYER_GROUP:
			failures.append("run_async: expected enemy ship enemy_group == PLAYER_GROUP, got %s" % ship.enemy_group)
		if ship.get_children().filter(func(c): return c is AIController).is_empty():
			failures.append("run_async: expected each enemy ship to own an AIController child")

	if scene.fleet_commander == null or scene.fleet_commander.ships != scene.player_ships:
		failures.append("run_async: expected fleet_commander.ships == player_ships")

	if scene.result_label == null:
		failures.append("run_async: expected result_label resolved by @onready, got null")
	elif scene.result_label.visible:
		failures.append("run_async: expected result_label.visible == false immediately after _ready()")

	# Victory: destroy every enemy ship's hull.
	for ship in scene.enemy_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	if scene.result_label != null:
		if scene.result_label.text != "Victory":
			failures.append("run_async: expected result_label.text == 'Victory' after all enemy ships destroyed, got '%s'" % scene.result_label.text)
		if not scene.result_label.visible:
			failures.append("run_async: expected result_label.visible == true after Victory")

	if is_instance_valid(scene) and not scene.is_queued_for_deletion():
		scene.queue_free()

	# Defeat path: fresh scene instance, mirrors the Victory check above.
	var defeat_scene: Node2D = CombatSceneScene.instantiate()
	tree.root.add_child(defeat_scene)
	await tree.process_frame
	await tree.process_frame

	for ship in defeat_scene.player_ships.duplicate():
		ship.hull.apply_damage(ship.hull.max_hp)
	if defeat_scene.result_label != null:
		if defeat_scene.result_label.text != "Defeat":
			failures.append("run_async: expected result_label.text == 'Defeat' after all player ships destroyed, got '%s'" % defeat_scene.result_label.text)
		if not defeat_scene.result_label.visible:
			failures.append("run_async: expected result_label.visible == true after Defeat")

	if is_instance_valid(defeat_scene) and not defeat_scene.is_queued_for_deletion():
		defeat_scene.queue_free()
	# Tree-pause from the Defeat result would otherwise freeze later tests' process_frame loop.
	tree.paused = false

	return failures
```

- [ ] **Step 6: Re-register the test and run the full suite**

In `tests/run_tests.gd`, re-add the `combat_scene_test` async block (the one removed in Task 4, Step 2), now pointing at the rewritten test:

```gdscript
	var combat_scene_test = preload("res://tests/test_combat_scene.gd")
	var combat_scene_failures: Array[String] = await combat_scene_test.run_async(self)
	for f in combat_scene_failures:
		print("FAIL [%s]: %s" % [combat_scene_test.resource_path, f])
	total_failures += combat_scene_failures.size()
```

Run: `godot --headless --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Rebuild CombatScene for N-vs-M fleets, dropping single-ship controllers"
```

---

### Task 7: Full fleet-battle playtest

**Files:** none (verification only).

- [ ] **Step 1: Playtest the fleet battle**

Run the project (F5). Verify:
- Click-drag a box around a cluster of player ships selects all of them (selection rings visible); single-click selects just one.
- With ships selected, pressing `1`-`5` and then right-clicking empty space sends them to that formation (`1`=loose/none, `2`=line, `3`=wedge, `4`=box, `5`=circle) around the click point, without ships passing through each other.
- Right-clicking directly on an enemy ship sends all selected ships to attack it.
- A ship that arrives at a `move_to` destination with nothing to fight drifts slowly within a small area instead of freezing in place.
- An idling ship near an approaching enemy breaks off to chase and fire, then gives up and returns if the enemy leads it too far from where it was idling.
- Enemy AI ships independently approach/engage/retreat based on their own hull, each picking its own nearest target.
- Destroying every enemy ship shows "Victory"; losing every player ship shows "Defeat".

If any of these don't hold, fix the relevant script from the earlier task before proceeding — do not patch around it in `combat_scene.gd`.

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "Confirm multi-ship fleet battle playtest"
```
