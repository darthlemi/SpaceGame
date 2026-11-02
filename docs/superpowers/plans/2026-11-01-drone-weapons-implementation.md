# Drone Weapon Type Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Drone weapon type (Attack, Interceptor, Bomber, EW) per `docs/superpowers/specs/2026-11-01-drone-weapons-design.md`, reusing `Ship`/`AIController`/`Order`/`ShipComponent` instead of a new entity type.

**Architecture:** A new `DroneBay` (`ShipComponent` subclass) launches drone scenes on a per-slot cooldown. Attack/Interceptor drones are plain `Ship` scenes with no new code. `BomberDrone`/`EwDrone` are small `Ship` subclasses overriding `_process_weapons()`. `Ship.player_targetable` + a `FleetCommander.ship_at_point` filter keep drones out of the player's right-click target picker.

**Tech Stack:** Godot 4.7, GDScript. Tests use this repo's custom runner convention (`run()`/`run_async()`, registered in `tests/run_tests.gd`).

## Global Constraints

- No missile/drone-specific targeting bonuses (deferred per spec).
- No ammo/lifetime limit on drones.
- Drones are independent entities once launched (not children of the launching ship), and keep fighting if their carrier dies.
- Follow existing code style: tabs, `class_name`+`extends` header, static pure-logic helpers for testable branching logic.

---

### Task 1: Shield regen_multiplier

**Files:**
- Modify: `scripts/ship/shield.gd`
- Test: `tests/test_shield.gd` (modify)

**Interfaces:**
- Produces: `Shield.regen_multiplier: float = 1.0`, applied to regen each frame then reset to `1.0`.

- [ ] **Step 1: Write the failing test**

Append to `run()` in `tests/test_shield.gd`, before `shield.free()`:

```gdscript
	var debuffed := Shield.new()
	debuffed.max_shield = 50.0
	debuffed.current_shield = 0.0
	debuffed.regen_rate = 10.0
	debuffed.regen_multiplier = 0.5
	debuffed._physics_process(1.0)
	if not is_equal_approx(debuffed.current_shield, 5.0):
		failures.append("regen_multiplier: expected 10.0*0.5*1.0=5.0 regen, got %s" % debuffed.current_shield)
	if not is_equal_approx(debuffed.regen_multiplier, 1.0):
		failures.append("regen_multiplier: expected reset to 1.0 after one frame, got %s" % debuffed.regen_multiplier)
	debuffed.free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `Invalid set index 'regen_multiplier'`.

- [ ] **Step 3: Implement**

```gdscript
# scripts/ship/shield.gd
class_name Shield
extends Node

@export var max_shield: float = 50.0
@export var regen_rate: float = 5.0
var current_shield: float
var regen_multiplier: float = 1.0

func _ready() -> void:
	current_shield = max_shield

func _physics_process(delta: float) -> void:
	if current_shield < max_shield:
		current_shield = min(max_shield, current_shield + regen_rate * regen_multiplier * delta)
	regen_multiplier = 1.0

func absorb(amount: float) -> float:
	if current_shield <= 0.0:
		return amount
	if amount <= current_shield:
		current_shield -= amount
		return 0.0
	var overflow := amount - current_shield
	current_shield = 0.0
	return overflow
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . --script res://tests/run_tests.gd`
Expected: PASS — no `FAIL [res://tests/test_shield.gd]` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/shield.gd tests/test_shield.gd
git commit -m "Add Shield.regen_multiplier for continuous debuff auras"
```

---

### Task 2: Ship.player_targetable + FleetCommander filter

**Files:**
- Modify: `scripts/ship/ship.gd`
- Modify: `scripts/controllers/fleet_commander.gd`
- Test: `tests/test_fleet_commander.gd` (modify)

**Interfaces:**
- Produces: `Ship.player_targetable: bool = true`. `FleetCommander.ship_at_point` skips ships where this is `false`.

- [ ] **Step 1: Write the failing test**

Append to `_check_ship_at_point` in `tests/test_fleet_commander.gd`, before `near.free()`:

```gdscript
	var drone := _make_ship(Vector2(5, 0))
	drone.player_targetable = false
	var picked_over_drone := FleetCommander.ship_at_point([drone, near], Vector2.ZERO, 50.0)
	if picked_over_drone != near:
		failures.append("ship_at_point: expected a non-player_targetable ship to be skipped, got %s" % picked_over_drone)
	var only_drone := FleetCommander.ship_at_point([drone], Vector2.ZERO, 50.0)
	if only_drone != null:
		failures.append("ship_at_point: expected null when the only candidate is not player_targetable, got %s" % only_drone)
	drone.free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `Invalid set index 'player_targetable'` (field doesn't exist yet).

- [ ] **Step 3: Implement**

In `scripts/ship/ship.gd`, add near `hit_radius`:

```gdscript
@export var player_targetable: bool = true
```

In `scripts/controllers/fleet_commander.gd`, update `ship_at_point`:

```gdscript
static func ship_at_point(candidates: Array, point: Vector2, radius: float) -> Ship:
	var best: Ship = null
	var best_dist := radius
	for c in candidates:
		if c is Ship and is_instance_valid(c) and c.player_targetable:
			var d: float = c.global_position.distance_to(point)
			if d <= best_dist:
				best_dist = d
				best = c
	return best
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . --script res://tests/run_tests.gd`
Expected: PASS — no `FAIL [res://tests/test_fleet_commander.gd]` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/ship.gd scripts/controllers/fleet_commander.gd tests/test_fleet_commander.gd
git commit -m "Exclude non-player-targetable ships (drones) from right-click target picking"
```

---

### Task 3: DroneBay

**Files:**
- Create: `scripts/drones/drone_bay.gd`
- Test: `tests/test_drone_bay.gd` (create)
- Modify: `tests/run_tests.gd` (register new test)

**Interfaces:**
- Consumes: `ShipComponent` (`apply_damage`/`is_destroyed`), `Order.attack_target`.
- Produces: `class_name DroneBay extends ShipComponent` with `@export var max_drones: int`, `@export var launch_interval: float`, `@export var respawn_delay: float`, `@export var drone_scene: PackedScene`, method `try_launch(target: Node2D) -> Ship` (returns the spawned drone, or `null` if no slot is ready — spawning logic kept separate from scene-tree `add_child` so it's testable without a live tree; the caller adds the returned node to the tree).

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_drone_bay.gd
extends RefCounted

const DroneBay = preload("res://scripts/drones/drone_bay.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []
	var bay := DroneBay.new()
	bay.max_drones = 2
	bay.launch_interval = 0.3
	bay.respawn_delay = 15.0
	bay._ready()

	var target := Node2D.new()

	# Both slots start ready: first launch succeeds immediately.
	var first: Ship = bay.try_launch(target)
	if first == null:
		failures.append("try_launch: expected a drone from the first ready slot")

	# Second slot is still on its initial 0.0 cooldown too, but launch_interval
	# staggers it -- immediately re-calling try_launch before ticking should fail.
	var immediate_second: Ship = bay.try_launch(target)
	if immediate_second != null:
		failures.append("try_launch: expected the second slot to be staggered by launch_interval, got a drone immediately")

	bay._physics_process(0.3)
	var second: Ship = bay.try_launch(target)
	if second == null:
		failures.append("try_launch: expected the second slot ready after launch_interval elapses")

	# No slots left: a third call must fail.
	var third: Ship = bay.try_launch(target)
	if third != null:
		failures.append("try_launch: expected null once all max_drones slots are occupied")

	# Destroying a launched drone frees its slot, but only after respawn_delay.
	first.hull.apply_damage(first.hull.max_hp)
	var too_soon: Ship = bay.try_launch(target)
	if too_soon != null:
		failures.append("try_launch: expected null immediately after a drone dies (slot on respawn_delay)")
	bay._physics_process(15.0)
	var respawned: Ship = bay.try_launch(target)
	if respawned == null:
		failures.append("try_launch: expected the dead drone's slot to be ready after respawn_delay")

	target.free()
	if is_instance_valid(first):
		first.free()
	if is_instance_valid(second):
		second.free()
	if is_instance_valid(respawned):
		respawned.free()
	bay.free()
	return failures
```

Register `preload("res://tests/test_drone_bay.gd")` in `tests/run_tests.gd`'s `test_scripts` array, after the `test_weapon_resources.gd` entry.

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — script `scripts/drones/drone_bay.gd` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```gdscript
# scripts/drones/drone_bay.gd
class_name DroneBay
extends ShipComponent

@export var max_drones: int = 3
@export var launch_interval: float = 0.3
@export var respawn_delay: float = 15.0
@export var drone_scene: PackedScene

var _slot_cooldowns: Array[float] = []
var _slot_drones: Array[Ship] = []

func _ready() -> void:
	super._ready()
	_slot_cooldowns.clear()
	_slot_drones.clear()
	for i in max_drones:
		_slot_cooldowns.append(0.0)
		_slot_drones.append(null)

func _physics_process(delta: float) -> void:
	for i in _slot_cooldowns.size():
		if _slot_cooldowns[i] > 0.0:
			_slot_cooldowns[i] = max(0.0, _slot_cooldowns[i] - delta)

func try_launch(target: Node2D) -> Ship:
	if is_destroyed() or drone_scene == null:
		return null
	for i in _slot_drones.size():
		if _slot_drones[i] != null and is_instance_valid(_slot_drones[i]) and not _slot_drones[i].hull.is_destroyed():
			continue
		if _slot_cooldowns[i] > 0.0:
			continue
		var drone: Ship = drone_scene.instantiate()
		drone._ready()  # resolve hull/shield/engine now; harmless to re-run on real tree entry
		drone.global_position = global_position
		_slot_drones[i] = drone
		_slot_cooldowns[i] = launch_interval
		drone.hull.destroyed.connect(_on_drone_destroyed.bind(i))
		if target != null:
			drone.execute_order(Order.attack_target(target))
		return drone
	return null

func _on_drone_destroyed(slot_index: int) -> void:
	_slot_cooldowns[slot_index] = respawn_delay
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . --script res://tests/run_tests.gd`
Expected: PASS — no `FAIL [res://tests/test_drone_bay.gd]` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/drones/drone_bay.gd tests/test_drone_bay.gd tests/run_tests.gd
git commit -m "Add DroneBay component for launching autonomous drones"
```

---

### Task 4: BomberDrone

**Files:**
- Create: `scripts/drones/bomber_drone.gd`
- Test: `tests/test_bomber_drone.gd` (create)
- Modify: `tests/run_tests.gd` (register new test)

**Interfaces:**
- Consumes: `Ship.receive_weapon_damage`, `Ship._process_weapons` override point, `Order.Type.ATTACK_TARGET`.
- Produces: `class_name BomberDrone extends Ship` with `@export var detonate_radius: float`, `@export var payload_weapon: Weapon`; overrides `attack_range()` and `_process_weapons()`.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_bomber_drone.gd
extends RefCounted

const BomberDrone = preload("res://scripts/drones/bomber_drone.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var bomber := BomberDrone.new()
	var hull := Hull.new()
	hull.max_hp = 10.0
	hull._ready()
	var shield := Shield.new()
	shield.max_shield = 0.0
	shield._ready()
	bomber.hull = hull
	bomber.shield = shield
	bomber.detonate_radius = 15.0
	bomber.payload_weapon = Weapon.new()
	bomber.payload_weapon.damage = 40.0
	bomber.payload_weapon.hull_mult = 1.3

	if not is_equal_approx(bomber.attack_range(), 15.0):
		failures.append("attack_range: expected detonate_radius 15.0, got %s" % bomber.attack_range())

	var target := Ship.new()
	var target_hull := Hull.new()
	target_hull.max_hp = 100.0
	target_hull._ready()
	var target_shield := Shield.new()
	target_shield.max_shield = 0.0
	target_shield._ready()
	target.hull = target_hull
	target.shield = target_shield
	target.global_position = Vector2(10.0, 0.0)

	bomber.global_position = Vector2.ZERO
	bomber.execute_order(Order.attack_target(target))
	bomber._process_weapons()

	if not is_equal_approx(target_hull.current_hp, 100.0 - 40.0 * 1.3):
		failures.append("_process_weapons: expected the payload to hit the target on detonation, got hull=%s" % target_hull.current_hp)
	if not bomber.hull.is_destroyed():
		failures.append("_process_weapons: expected the bomber to self-destruct on detonation")

	hull.free()
	shield.free()
	bomber.free()
	target_hull.free()
	target_shield.free()
	target.free()
	return failures
```

Register `preload("res://tests/test_bomber_drone.gd")` in `tests/run_tests.gd`, after `test_drone_bay.gd`.

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — script `scripts/drones/bomber_drone.gd` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

```gdscript
# scripts/drones/bomber_drone.gd
class_name BomberDrone
extends Ship

@export var detonate_radius: float = 15.0
@export var payload_weapon: Weapon

func attack_range() -> float:
	return detonate_radius

func _process_weapons() -> void:
	if current_order == null or current_order.type != Order.Type.ATTACK_TARGET:
		return
	var target: Node2D = current_order.target_ship
	if not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) > detonate_radius:
		return
	if target.has_method("receive_weapon_damage") and payload_weapon != null:
		target.receive_weapon_damage(payload_weapon)
	hull.apply_damage(hull.max_hp)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . --script res://tests/run_tests.gd`
Expected: PASS — no `FAIL [res://tests/test_bomber_drone.gd]` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/drones/bomber_drone.gd tests/test_bomber_drone.gd tests/run_tests.gd
git commit -m "Add BomberDrone: ram-and-detonate kamikaze behavior"
```

---

### Task 5: EwDrone

**Files:**
- Create: `scripts/drones/ew_drone.gd`
- Test: `tests/test_ew_drone.gd` (create)
- Modify: `tests/run_tests.gd` (register new test)

**Interfaces:**
- Consumes: `Shield.regen_multiplier` (Task 1), `Ship.nearest_in_range`.
- Produces: `class_name EwDrone extends Ship` with `@export var aura_range: float`, `@export var regen_debuff_mult: float`; overrides `_process_weapons()`.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_ew_drone.gd
extends RefCounted

const EwDrone = preload("res://scripts/drones/ew_drone.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var drone := EwDrone.new()
	var hull := Hull.new()
	hull.max_hp = 6.0
	hull._ready()
	var shield := Shield.new()
	shield.max_shield = 0.0
	shield._ready()
	drone.hull = hull
	drone.shield = shield
	drone.aura_range = 150.0
	drone.regen_debuff_mult = 0.5
	drone.global_position = Vector2.ZERO

	var target := Ship.new()
	var target_hull := Hull.new()
	target_hull.max_hp = 100.0
	target_hull._ready()
	var target_shield := Shield.new()
	target_shield.max_shield = 50.0
	target_shield._ready()
	target.hull = target_hull
	target.shield = target_shield
	target.global_position = Vector2(50.0, 0.0)

	# EwDrone's _process_weapons() is exercised against an injected candidate
	# list (_test_candidates) rather than a live SceneTree group lookup, the
	# same tree-free pattern the rest of this codebase's Ship-adjacent unit
	# tests already use.
	drone._test_candidates = [target]
	drone._process_weapons()
	if not is_equal_approx(target.shield.regen_multiplier, 0.5):
		failures.append("_process_weapons: expected the nearest in-range enemy's shield.regen_multiplier debuffed to 0.5, got %s" % target.shield.regen_multiplier)

	hull.free()
	shield.free()
	drone.free()
	target_hull.free()
	target_shield.free()
	target.free()
	return failures
```

Register `preload("res://tests/test_ew_drone.gd")` in `tests/run_tests.gd`, after `test_bomber_drone.gd`.

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — script `scripts/drones/ew_drone.gd` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

`_process_weapons()` needs a list of enemy candidates to search. Live gameplay
gets that from `get_tree().get_nodes_in_group(enemy_group)` (only valid once
the node is inside a tree); the unit test above has no live tree, so it
injects candidates directly via `_test_candidates`. `is_inside_tree()` picks
which source to use:

```gdscript
# scripts/drones/ew_drone.gd
class_name EwDrone
extends Ship

@export var aura_range: float = 150.0
@export var regen_debuff_mult: float = 0.5

var _test_candidates: Array = []

func _process_weapons() -> void:
	var candidates: Array = get_tree().get_nodes_in_group(enemy_group) if is_inside_tree() and enemy_group != &"" else _test_candidates
	var target := Ship.nearest_in_range(candidates, global_position, aura_range)
	if target == null:
		return
	target.shield.regen_multiplier = regen_debuff_mult
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path . --script res://tests/run_tests.gd`
Expected: PASS — no `FAIL [res://tests/test_ew_drone.gd]` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/drones/ew_drone.gd tests/test_ew_drone.gd tests/run_tests.gd
git commit -m "Add EwDrone: continuous shield-regen debuff aura"
```

---

### Task 6: Drone scenes and weapon/payload resources

**Files:**
- Create: `scenes/drones/attack_drone.tscn`, `scenes/drones/interceptor_drone.tscn`, `scenes/drones/bomber_drone.tscn`, `scenes/drones/ew_drone.tscn`
- Create: `resources/weapons/drone_attack_gun.tres`, `resources/weapons/drone_interceptor_gun.tres`, `resources/weapons/drone_bomber_payload.tres`
- Test: `tests/test_drone_scenes.gd` (create)
- Modify: `tests/run_tests.gd` (register new test)

**Interfaces:**
- Consumes: `Ship`, `BomberDrone`, `EwDrone`, `Weapon`, `Hull`, `Shield`, `ShipEngine`, `WeaponMount` — all existing/already built.
- Produces: nothing further downstream — this is the leaf task.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_drone_scenes.gd
extends RefCounted

const AttackDroneScene = preload("res://scenes/drones/attack_drone.tscn")
const InterceptorDroneScene = preload("res://scenes/drones/interceptor_drone.tscn")
const BomberDroneScene = preload("res://scenes/drones/bomber_drone.tscn")
const EwDroneScene = preload("res://scenes/drones/ew_drone.tscn")
const BomberDrone = preload("res://scripts/drones/bomber_drone.gd")
const EwDrone = preload("res://scripts/drones/ew_drone.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []

	var attack: Ship = AttackDroneScene.instantiate()
	if attack.player_targetable:
		failures.append("attack_drone.tscn: expected player_targetable false")
	if attack.hull == null or not is_equal_approx(attack.hull.max_hp, 15.0):
		failures.append("attack_drone.tscn: expected Hull max_hp 15.0")
	attack.free()

	var interceptor: Ship = InterceptorDroneScene.instantiate()
	if interceptor.player_targetable:
		failures.append("interceptor_drone.tscn: expected player_targetable false")
	if interceptor.hull == null or not is_equal_approx(interceptor.hull.max_hp, 8.0):
		failures.append("interceptor_drone.tscn: expected Hull max_hp 8.0")
	interceptor.free()

	var bomber: BomberDrone = BomberDroneScene.instantiate()
	if not (bomber is BomberDrone):
		failures.append("bomber_drone.tscn: expected root script BomberDrone")
	if bomber.payload_weapon == null or not is_equal_approx(bomber.payload_weapon.damage, 40.0):
		failures.append("bomber_drone.tscn: expected payload_weapon damage 40.0")
	bomber.free()

	var ew: EwDrone = EwDroneScene.instantiate()
	if not (ew is EwDrone):
		failures.append("ew_drone.tscn: expected root script EwDrone")
	ew.free()

	return failures
```

Register `preload("res://tests/test_drone_scenes.gd")` in `tests/run_tests.gd`, after `test_ew_drone.gd`.

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — scene files don't exist yet.

- [ ] **Step 3: Create the weapon/payload resources**

`resources/weapons/drone_attack_gun.tres`:

```
[gd_resource type="Resource" script_class="Weapon" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/weapons/weapon.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/weapons/projectile.tscn" id="2"]

[resource]
script = ExtResource("1")
weapon_name = "Drone Attack Gun"
damage = 4.0
fire_rate = 1.5
weapon_range = 150.0
projectile_scene = ExtResource("2")
mount_type = 1
fire_arc_degrees = 360.0
rarity = 0
```

`resources/weapons/drone_interceptor_gun.tres`:

```
[gd_resource type="Resource" script_class="Weapon" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/weapons/weapon.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/weapons/projectile.tscn" id="2"]

[resource]
script = ExtResource("1")
weapon_name = "Drone Interceptor Gun"
damage = 2.0
fire_rate = 2.0
weapon_range = 150.0
projectile_scene = ExtResource("2")
mount_type = 1
fire_arc_degrees = 360.0
rarity = 1
```

`resources/weapons/drone_bomber_payload.tres`:

```
[gd_resource type="Resource" script_class="Weapon" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/weapons/weapon.gd" id="1"]

[resource]
script = ExtResource("1")
weapon_name = "Bomber Payload"
damage = 40.0
hull_mult = 1.3
shield_mult = 0.8
rarity = 2
```

- [ ] **Step 4: Create the drone scenes**

`scenes/drones/attack_drone.tscn`:

```
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/ship/ship.gd" id="1"]
[ext_resource type="Script" path="res://scripts/ship/hull.gd" id="2"]
[ext_resource type="Script" path="res://scripts/ship/shield.gd" id="3"]
[ext_resource type="Script" path="res://scripts/ship/ship_engine.gd" id="4"]
[ext_resource type="Script" path="res://scripts/weapons/weapon_mount.gd" id="5"]
[ext_resource type="Resource" path="res://resources/weapons/drone_attack_gun.tres" id="6"]

[node name="AttackDrone" type="CharacterBody2D"]
script = ExtResource("1")
player_targetable = false
hit_radius = 6.0

[node name="Hull" type="Node2D" parent="."]
script = ExtResource("2")
max_hp = 15.0

[node name="Shield" type="Node" parent="."]
script = ExtResource("3")
max_shield = 0.0

[node name="Engine" type="Node2D" parent="."]
script = ExtResource("4")
max_speed = 220.0
turn_rate = 6.0
acceleration = 260.0

[node name="WeaponMount" type="Node2D" parent="."]
script = ExtResource("5")
weapon = ExtResource("6")
```

`scenes/drones/interceptor_drone.tscn` (same template, swap stats/weapon):

```
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/ship/ship.gd" id="1"]
[ext_resource type="Script" path="res://scripts/ship/hull.gd" id="2"]
[ext_resource type="Script" path="res://scripts/ship/shield.gd" id="3"]
[ext_resource type="Script" path="res://scripts/ship/ship_engine.gd" id="4"]
[ext_resource type="Script" path="res://scripts/weapons/weapon_mount.gd" id="5"]
[ext_resource type="Resource" path="res://resources/weapons/drone_interceptor_gun.tres" id="6"]

[node name="InterceptorDrone" type="CharacterBody2D"]
script = ExtResource("1")
player_targetable = false
hit_radius = 5.0

[node name="Hull" type="Node2D" parent="."]
script = ExtResource("2")
max_hp = 8.0

[node name="Shield" type="Node" parent="."]
script = ExtResource("3")
max_shield = 0.0

[node name="Engine" type="Node2D" parent="."]
script = ExtResource("4")
max_speed = 300.0
turn_rate = 8.0
acceleration = 320.0

[node name="WeaponMount" type="Node2D" parent="."]
script = ExtResource("5")
weapon = ExtResource("6")
```

`scenes/drones/bomber_drone.tscn` (root script is `BomberDrone`, no `WeaponMount` — the payload is applied in code, not fired as a projectile):

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/drones/bomber_drone.gd" id="1"]
[ext_resource type="Script" path="res://scripts/ship/hull.gd" id="2"]
[ext_resource type="Script" path="res://scripts/ship/shield.gd" id="3"]
[ext_resource type="Script" path="res://scripts/ship/ship_engine.gd" id="4"]
[ext_resource type="Resource" path="res://resources/weapons/drone_bomber_payload.tres" id="5"]

[node name="BomberDrone" type="CharacterBody2D"]
script = ExtResource("1")
player_targetable = false
hit_radius = 6.0
detonate_radius = 15.0
payload_weapon = ExtResource("5")

[node name="Hull" type="Node2D" parent="."]
script = ExtResource("2")
max_hp = 10.0

[node name="Shield" type="Node" parent="."]
script = ExtResource("3")
max_shield = 0.0

[node name="Engine" type="Node2D" parent="."]
script = ExtResource("4")
max_speed = 160.0
turn_rate = 4.0
acceleration = 180.0
```

`scenes/drones/ew_drone.tscn` (root script is `EwDrone`, no `WeaponMount`):

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/drones/ew_drone.gd" id="1"]
[ext_resource type="Script" path="res://scripts/ship/hull.gd" id="2"]
[ext_resource type="Script" path="res://scripts/ship/shield.gd" id="3"]
[ext_resource type="Script" path="res://scripts/ship/ship_engine.gd" id="4"]

[node name="EwDrone" type="CharacterBody2D"]
script = ExtResource("1")
player_targetable = false
hit_radius = 5.0
aura_range = 150.0
regen_debuff_mult = 0.5

[node name="Hull" type="Node2D" parent="."]
script = ExtResource("2")
max_hp = 6.0

[node name="Shield" type="Node" parent="."]
script = ExtResource("3")
max_shield = 0.0

[node name="Engine" type="Node2D" parent="."]
script = ExtResource("4")
max_speed = 200.0
turn_rate = 5.0
acceleration = 200.0
```

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless --path . --script res://tests/run_tests.gd`
Expected: PASS — no `FAIL [res://tests/test_drone_scenes.gd]` lines, and `All tests passed.` (modulo the pre-existing, unrelated `test_campaign_long_run_sim.gd` flakiness).

- [ ] **Step 6: Commit**

```bash
git add scenes/drones/ resources/weapons/drone_attack_gun.tres resources/weapons/drone_interceptor_gun.tres resources/weapons/drone_bomber_payload.tres tests/test_drone_scenes.gd tests/run_tests.gd
git commit -m "Add Attack/Interceptor/Bomber/EW drone scenes and weapon resources"
```
