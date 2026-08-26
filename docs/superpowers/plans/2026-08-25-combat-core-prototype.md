# Combat Core Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a playable 1v1 real-time space combat prototype in Godot 4.x, with the player able to toggle between RTS-style command and direct piloting of their capital ship, fighting one AI-controlled enemy ship, with a weapon system architected for easy extension.

**Architecture:** Ships are composed from independent components (Hull, Shield, Engine, WeaponMounts) rather than monolithic scripts. Weapons are Resources paired with pluggable behavior scenes. A single `Order` type (`move_to`, `attack_target`, `hold`, `retreat`) is issued by three interchangeable sources — RTS clicks, direct-pilot input, or AI logic — through one shared `Ship.execute_order()` entry point.

**Tech Stack:** Godot 4.x (GDScript), no external addons. Pure-logic pieces (Order, Hull, Shield, Engine math) get a small headless GDScript test suite run via `godot --headless --script`; scene/controller integration is verified by manual playtest in the editor, per the design spec's testing section.

## Global Constraints

- Godot version: 4.x (verify with `godot --version` before starting — if not on PATH, stop and ask the user for the executable path).
- 2D top-down perspective (spec: Perspective decision).
- No damage-type multipliers in this milestone (spec: Shield component note).
- Weapon content stays minimal (one weapon type) but the Weapon/behavior split must make adding a new style a new file, not an edit to existing files (spec: Goals).
- Out of scope, do not build: campaign map, factions, ship refit UI, rift system, multi-ship fleets (spec: Out of Scope).

---

### Task 1: Project scaffold and the `Order` type

**Files:**
- Create: `project.godot`
- Create: `scripts/orders/order.gd`
- Create: `tests/test_order.gd`
- Create: `tests/run_tests.gd`

**Interfaces:**
- Produces: `class_name Order`, enum `Order.Type { MOVE_TO, ATTACK_TARGET, HOLD, RETREAT }`, static constructors `Order.move_to(pos: Vector2)`, `Order.attack_target(ship: Node2D)`, `Order.hold()`, `Order.retreat(from_position: Vector2)`, instance fields `type`, `target_position`, `target_ship`.
- Produces: `tests/run_tests.gd`, a headless test runner every later task's tests plug into by adding `preload("res://tests/test_X.gd")` to its `test_scripts` array.

- [ ] **Step 1: Verify Godot is available**

Run: `godot --version`
Expected: prints a 4.x version string. If this fails, stop and ask the user for the correct Godot executable/path before continuing.

- [ ] **Step 2: Create the Godot project**

Run (from `C:\Users\corbi\Desktop\SpaceGame`):
```bash
godot --headless --path . --editor --quit
```
This generates a default `project.godot` and `.godot/` cache. Open `project.godot` and confirm it has a `[application]` section with `config/name="SpaceGame"`. If the name is wrong, edit it directly to:
```ini
[application]

config/name="SpaceGame"
config/features=PackedStringArray("4.2")
```

- [ ] **Step 3: Write `Order`**

`scripts/orders/order.gd`:
```gdscript
class_name Order
extends RefCounted

enum Type { MOVE_TO, ATTACK_TARGET, HOLD, RETREAT }

var type: Type
var target_position: Vector2
var target_ship: Node2D

static func move_to(pos: Vector2) -> Order:
	var o := Order.new()
	o.type = Type.MOVE_TO
	o.target_position = pos
	return o

static func attack_target(ship: Node2D) -> Order:
	var o := Order.new()
	o.type = Type.ATTACK_TARGET
	o.target_ship = ship
	return o

static func hold() -> Order:
	var o := Order.new()
	o.type = Type.HOLD
	return o

static func retreat(from_position: Vector2) -> Order:
	var o := Order.new()
	o.type = Type.RETREAT
	o.target_position = from_position
	return o
```

- [ ] **Step 4: Write the test for `Order`**

`tests/test_order.gd`:
```gdscript
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []

	var move := Order.move_to(Vector2(10, 20))
	if move.type != Order.Type.MOVE_TO:
		failures.append("move_to: expected type MOVE_TO, got %s" % move.type)
	if move.target_position != Vector2(10, 20):
		failures.append("move_to: expected position (10,20), got %s" % move.target_position)

	var attack := Order.attack_target(null)
	if attack.type != Order.Type.ATTACK_TARGET:
		failures.append("attack_target: expected type ATTACK_TARGET, got %s" % attack.type)

	var hold := Order.hold()
	if hold.type != Order.Type.HOLD:
		failures.append("hold: expected type HOLD, got %s" % hold.type)

	var retreat := Order.retreat(Vector2(5, 5))
	if retreat.type != Order.Type.RETREAT:
		failures.append("retreat: expected type RETREAT, got %s" % retreat.type)
	if retreat.target_position != Vector2(5, 5):
		failures.append("retreat: expected position (5,5), got %s" % retreat.target_position)

	return failures
```

- [ ] **Step 5: Write the test runner**

`tests/run_tests.gd`:
```gdscript
extends SceneTree

func _init() -> void:
	var test_scripts := [
		preload("res://tests/test_order.gd"),
	]
	var total_failures := 0
	for script in test_scripts:
		var failures: Array[String] = script.run()
		for f in failures:
			print("FAIL [%s]: %s" % [script.resource_path, f])
		total_failures += failures.size()
	if total_failures == 0:
		print("All tests passed.")
	else:
		print("%d test failure(s)." % total_failures)
	quit(1 if total_failures > 0 else 0)
```

- [ ] **Step 6: Run the tests and verify they pass**

Run: `godot --headless --script res://tests/run_tests.gd`
Expected: `All tests passed.` and exit code 0.

- [ ] **Step 7: Commit**

```bash
git add project.godot scripts/orders/order.gd tests/test_order.gd tests/run_tests.gd .godot 2>/dev/null
git add project.godot scripts/orders/order.gd tests/test_order.gd tests/run_tests.gd
git commit -m "Add project scaffold and Order type"
```

---

### Task 2: `Hull` and `Shield` components

**Files:**
- Create: `scripts/ship/hull.gd`
- Create: `scripts/ship/shield.gd`
- Create: `tests/test_hull.gd`
- Create: `tests/test_shield.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `class_name Hull` (extends `Node`) with `max_hp: float`, `current_hp: float`, `apply_damage(amount: float) -> void`, `is_destroyed() -> bool`, signal `destroyed`, signal `damaged(amount: float, remaining: float)`.
- Produces: `class_name Shield` (extends `Node`) with `max_shield: float`, `regen_rate: float`, `current_shield: float`, `absorb(amount: float) -> float` (returns overflow damage not absorbed).

- [ ] **Step 1: Write `Hull`**

`scripts/ship/hull.gd`:
```gdscript
class_name Hull
extends Node

signal destroyed
signal damaged(amount: float, remaining: float)

@export var max_hp: float = 100.0
var current_hp: float

func _ready() -> void:
	current_hp = max_hp

func apply_damage(amount: float) -> void:
	if current_hp <= 0.0:
		return
	current_hp = max(0.0, current_hp - amount)
	damaged.emit(amount, current_hp)
	if current_hp <= 0.0:
		destroyed.emit()

func is_destroyed() -> bool:
	return current_hp <= 0.0
```

- [ ] **Step 2: Write the `Hull` test**

`tests/test_hull.gd`:
```gdscript
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	var hull := Hull.new()
	hull.max_hp = 100.0
	hull.current_hp = 100.0

	var destroyed_fired := false
	hull.destroyed.connect(func(): destroyed_fired = true)

	hull.apply_damage(30.0)
	if hull.current_hp != 70.0:
		failures.append("apply_damage: expected 70.0 remaining, got %s" % hull.current_hp)
	if destroyed_fired:
		failures.append("apply_damage: destroyed fired prematurely")

	hull.apply_damage(1000.0)
	if hull.current_hp != 0.0:
		failures.append("apply_damage: expected 0.0 after overkill, got %s" % hull.current_hp)
	if not destroyed_fired:
		failures.append("apply_damage: destroyed signal did not fire at 0 hp")

	hull.free()
	return failures
```

- [ ] **Step 3: Write `Shield`**

`scripts/ship/shield.gd`:
```gdscript
class_name Shield
extends Node

@export var max_shield: float = 50.0
@export var regen_rate: float = 5.0
var current_shield: float

func _ready() -> void:
	current_shield = max_shield

func _physics_process(delta: float) -> void:
	if current_shield < max_shield:
		current_shield = min(max_shield, current_shield + regen_rate * delta)

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

- [ ] **Step 4: Write the `Shield` test**

`tests/test_shield.gd`:
```gdscript
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	var shield := Shield.new()
	shield.max_shield = 50.0
	shield.current_shield = 50.0

	var overflow := shield.absorb(20.0)
	if overflow != 0.0:
		failures.append("absorb: expected 0 overflow, got %s" % overflow)
	if shield.current_shield != 30.0:
		failures.append("absorb: expected 30.0 remaining shield, got %s" % shield.current_shield)

	overflow = shield.absorb(50.0)
	if overflow != 20.0:
		failures.append("absorb: expected 20.0 overflow, got %s" % overflow)
	if shield.current_shield != 0.0:
		failures.append("absorb: expected 0.0 remaining shield, got %s" % shield.current_shield)

	overflow = shield.absorb(10.0)
	if overflow != 10.0:
		failures.append("absorb: expected full passthrough at 0 shield, got %s" % overflow)

	shield.free()
	return failures
```

- [ ] **Step 5: Register new tests in the runner**

In `tests/run_tests.gd`, update `test_scripts`:
```gdscript
	var test_scripts := [
		preload("res://tests/test_order.gd"),
		preload("res://tests/test_hull.gd"),
		preload("res://tests/test_shield.gd"),
	]
```

- [ ] **Step 6: Run tests and verify they pass**

Run: `godot --headless --script res://tests/run_tests.gd`
Expected: `All tests passed.`, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add scripts/ship/hull.gd scripts/ship/shield.gd tests/test_hull.gd tests/test_shield.gd tests/run_tests.gd
git commit -m "Add Hull and Shield components"
```

---

### Task 3: `Engine` component (steering math)

**Files:**
- Create: `scripts/ship/engine.gd`
- Create: `tests/test_engine.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces: `class_name Engine` (extends `Node`) with `max_speed: float`, `turn_rate: float`, `acceleration: float`, `velocity: Vector2`, `steer_toward(current_pos: Vector2, current_rotation: float, target_pos: Vector2, delta: float) -> Dictionary` returning `{"rotation": float, "velocity": Vector2}`, and static `Engine.rotate_toward_angle(current: float, target: float, max_delta: float) -> float`.

- [ ] **Step 1: Write `Engine`**

`scripts/ship/engine.gd`:
```gdscript
class_name Engine
extends Node

@export var max_speed: float = 200.0
@export var turn_rate: float = 3.0
@export var acceleration: float = 150.0

var velocity: Vector2 = Vector2.ZERO

func steer_toward(current_pos: Vector2, current_rotation: float, target_pos: Vector2, delta: float) -> Dictionary:
	var to_target := target_pos - current_pos
	if to_target.length() < 1.0:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		return {"rotation": current_rotation, "velocity": velocity}
	var desired_angle := to_target.angle()
	var new_rotation := Engine.rotate_toward_angle(current_rotation, desired_angle, turn_rate * delta)
	var forward := Vector2.RIGHT.rotated(new_rotation)
	velocity = velocity.move_toward(forward * max_speed, acceleration * delta)
	return {"rotation": new_rotation, "velocity": velocity}

static func rotate_toward_angle(current: float, target: float, max_delta: float) -> float:
	var diff := wrapf(target - current, -PI, PI)
	if abs(diff) <= max_delta:
		return target
	return current + sign(diff) * max_delta
```

- [ ] **Step 2: Write the `Engine` test**

`tests/test_engine.gd`:
```gdscript
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []

	var result := Engine.rotate_toward_angle(0.0, PI / 2.0, 0.1)
	if not is_equal_approx(result, 0.1):
		failures.append("rotate_toward_angle: expected small step of 0.1, got %s" % result)

	result = Engine.rotate_toward_angle(0.0, 0.05, 0.1)
	if not is_equal_approx(result, 0.05):
		failures.append("rotate_toward_angle: expected snap to target 0.05, got %s" % result)

	var engine := Engine.new()
	engine.max_speed = 100.0
	engine.acceleration = 1000.0
	engine.turn_rate = 10.0
	var steer := engine.steer_toward(Vector2.ZERO, 0.0, Vector2(100, 0), 1.0)
	var vel: Vector2 = steer["velocity"]
	if vel.length() < 50.0:
		failures.append("steer_toward: expected ship to accelerate toward target, velocity length was %s" % vel.length())

	engine.free()
	return failures
```

- [ ] **Step 3: Register the test in the runner**

In `tests/run_tests.gd`, add `preload("res://tests/test_engine.gd"),` to `test_scripts`.

- [ ] **Step 4: Run tests and verify they pass**

Run: `godot --headless --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/engine.gd tests/test_engine.gd tests/run_tests.gd
git commit -m "Add Engine steering component"
```

---

### Task 4: `Weapon` resource, `WeaponMount`, and a kinetic `Projectile`

**Files:**
- Create: `scripts/weapons/weapon.gd`
- Create: `scripts/weapons/weapon_mount.gd`
- Create: `scripts/weapons/projectile.gd`
- Create: `scenes/weapons/projectile.tscn`
- Create: `resources/weapons/kinetic_cannon.tres`

**Interfaces:**
- Consumes: nothing from prior tasks directly (weapons are self-contained), but `try_fire` will later be driven by `Ship`/controllers in Task 5+.
- Produces: `class_name Weapon` (extends `Resource`) fields `weapon_name: String`, `damage: float`, `fire_rate: float`, `range: float`, `projectile_scene: PackedScene`.
- Produces: `class_name WeaponMount` (extends `Node2D`) with `weapon: Weapon`, `can_fire() -> bool`, `try_fire(target: Node2D) -> bool`.
- Produces: `class_name Projectile` (extends `Area2D`) with `setup(target: Node2D, damage: float) -> void`. Expects any target passed to `setup` to implement `receive_damage(amount: float) -> void` (implemented by `Ship` in Task 5).

- [ ] **Step 1: Write `Weapon`**

`scripts/weapons/weapon.gd`:
```gdscript
class_name Weapon
extends Resource

@export var weapon_name: String = "Kinetic Cannon"
@export var damage: float = 10.0
@export var fire_rate: float = 1.0
@export var range: float = 300.0
@export var projectile_scene: PackedScene
```

- [ ] **Step 2: Write `Projectile`**

`scripts/weapons/projectile.gd`:
```gdscript
class_name Projectile
extends Area2D

@export var speed: float = 500.0
var target: Node2D
var damage: float = 0.0

func setup(p_target: Node2D, p_damage: float) -> void:
	target = p_target
	damage = p_damage

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		queue_free()
		return
	var direction := (target.global_position - global_position).normalized()
	global_position += direction * speed * delta
	if global_position.distance_to(target.global_position) < 10.0:
		_hit()

func _hit() -> void:
	if is_instance_valid(target) and target.has_method("receive_damage"):
		target.receive_damage(damage)
	queue_free()
```

- [ ] **Step 3: Build the `Projectile` scene**

In the Godot editor: create a new scene, root node `Area2D` named `Projectile`, attach `scripts/weapons/projectile.gd`. Add a child `CollisionShape2D` with a small `CircleShape2D` (radius 4). Add a child `Sprite2D` or `ColorRect` (8x8, any bright color) for visibility. Save as `scenes/weapons/projectile.tscn`.

- [ ] **Step 4: Write `WeaponMount`**

`scripts/weapons/weapon_mount.gd`:
```gdscript
class_name WeaponMount
extends Node2D

@export var weapon: Weapon
var cooldown_remaining: float = 0.0

func _physics_process(delta: float) -> void:
	if cooldown_remaining > 0.0:
		cooldown_remaining -= delta

func can_fire() -> bool:
	return weapon != null and cooldown_remaining <= 0.0

func try_fire(target: Node2D) -> bool:
	if not can_fire() or target == null or not is_instance_valid(target):
		return false
	if global_position.distance_to(target.global_position) > weapon.range:
		return false
	_spawn_projectile(target)
	cooldown_remaining = 1.0 / weapon.fire_rate
	return true

func _spawn_projectile(target: Node2D) -> void:
	if weapon.projectile_scene == null:
		return
	var projectile: Node2D = weapon.projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position
	projectile.setup(target, weapon.damage)
```

- [ ] **Step 5: Create the kinetic cannon resource**

In the Godot editor: create a new `Resource` of type `Weapon` (FileSystem panel → right-click → New Resource → Weapon). Set `weapon_name = "Kinetic Cannon"`, `damage = 10.0`, `fire_rate = 2.0`, `range = 300.0`, `projectile_scene = res://scenes/weapons/projectile.tscn`. Save as `resources/weapons/kinetic_cannon.tres`.

- [ ] **Step 6: Manual verification**

Create a scratch test scene: two `Node2D`s 200px apart, one with a `WeaponMount` (child of it) using `kinetic_cannon.tres`, the other a plain `Node2D` with a script exposing `receive_damage(amount)` that just prints the amount. Call `try_fire(other_node)` once via a `_ready()` test call. Run the scene (F6) and confirm a projectile spawns, travels toward the target, and the print statement fires once on contact. Delete the scratch scene afterward.

- [ ] **Step 7: Commit**

```bash
git add scripts/weapons/weapon.gd scripts/weapons/weapon_mount.gd scripts/weapons/projectile.gd scenes/weapons/projectile.tscn resources/weapons/kinetic_cannon.tres
git commit -m "Add Weapon resource, WeaponMount, and kinetic Projectile"
```

---

### Task 5: `Ship` scene composing Hull, Shield, Engine, and WeaponMounts

**Files:**
- Create: `scripts/ship/ship.gd`
- Create: `scenes/ship/ship.tscn`

**Interfaces:**
- Consumes: `Hull`, `Shield`, `Engine` (Task 2/3), `WeaponMount` (Task 4), `Order` (Task 1).
- Produces: `class_name Ship` (extends `CharacterBody2D`) with `hull: Hull`, `shield: Shield`, `engine: Engine`, `weapon_mounts: Array[WeaponMount]`, `execute_order(order: Order) -> void`, `receive_damage(amount: float) -> void`, `attack_range() -> float`, `control_mode: ControlMode` enum `{ORDER_BASED, DIRECT}` (default `ORDER_BASED`, used starting Task 8).

- [ ] **Step 1: Write `Ship`**

`scripts/ship/ship.gd`:
```gdscript
class_name Ship
extends CharacterBody2D

enum ControlMode { ORDER_BASED, DIRECT }

@onready var hull: Hull = $Hull
@onready var shield: Shield = $Shield
@onready var engine: Engine = $Engine

var weapon_mounts: Array[WeaponMount] = []
var current_order: Order
var control_mode: ControlMode = ControlMode.ORDER_BASED

func _ready() -> void:
	for child in get_children():
		if child is WeaponMount:
			weapon_mounts.append(child)
	hull.destroyed.connect(_on_hull_destroyed)
	current_order = Order.hold()

func execute_order(order: Order) -> void:
	current_order = order

func attack_range() -> float:
	var max_range := 0.0
	for mount in weapon_mounts:
		if mount.weapon:
			max_range = max(max_range, mount.weapon.range)
	return max_range

func receive_damage(amount: float) -> void:
	var overflow := shield.absorb(amount)
	if overflow > 0.0:
		hull.apply_damage(overflow)

func _physics_process(delta: float) -> void:
	if control_mode == ControlMode.ORDER_BASED:
		_process_order_movement(delta)
		move_and_slide()
	_process_weapons()

func _process_order_movement(delta: float) -> void:
	match current_order.type:
		Order.Type.MOVE_TO:
			_steer_to(current_order.target_position, delta)
		Order.Type.ATTACK_TARGET:
			if not is_instance_valid(current_order.target_ship):
				current_order = Order.hold()
				return
			var target_pos: Vector2 = current_order.target_ship.global_position
			if global_position.distance_to(target_pos) > attack_range():
				_steer_to(target_pos, delta)
			else:
				velocity = velocity.move_toward(Vector2.ZERO, engine.acceleration * delta)
		Order.Type.RETREAT:
			var away := global_position + (global_position - current_order.target_position).normalized() * 500.0
			_steer_to(away, delta)
		Order.Type.HOLD:
			velocity = velocity.move_toward(Vector2.ZERO, engine.acceleration * delta)

func _steer_to(target_pos: Vector2, delta: float) -> void:
	var result := engine.steer_toward(global_position, rotation, target_pos, delta)
	rotation = result["rotation"]
	velocity = result["velocity"]

func _process_weapons() -> void:
	if current_order.type != Order.Type.ATTACK_TARGET or not is_instance_valid(current_order.target_ship):
		return
	for mount in weapon_mounts:
		mount.try_fire(current_order.target_ship)

func _on_hull_destroyed() -> void:
	queue_free()
```

- [ ] **Step 2: Build the `Ship` scene**

In the Godot editor: create a new scene, root node `CharacterBody2D` named `Ship`, attach `scripts/ship/ship.gd`. Add children: `CollisionShape2D` (a small capsule/circle), `Sprite2D` or `Polygon2D` for the ship body (e.g. a simple triangle polygon pointing along `+X`, since `Engine`'s forward direction is `Vector2.RIGHT.rotated(rotation)`), `Hull` node (attach `hull.gd`), `Shield` node (attach `shield.gd`), `Engine` node (attach `engine.gd`), and one `WeaponMount` node (attach `weapon_mount.gd`, assign `resources/weapons/kinetic_cannon.tres` as its `weapon`). Save as `scenes/ship/ship.tscn`.

- [ ] **Step 3: Manual verification**

Create a scratch scene with two `Ship` instances 400px apart. In a temporary test script on the scene root's `_ready()`, call `ship_a.execute_order(Order.attack_target(ship_b))`. Run the scene (F6) and confirm: ship_a turns toward and moves within range of ship_b, then stops closing and fires; ship_b's shield depletes first (watch via a temporary `print` in `receive_damage` or breakpoint), then hull damage begins, then ship_b is freed (disappears) when hull hits 0. Delete the scratch scene and temporary script afterward.

- [ ] **Step 4: Commit**

```bash
git add scripts/ship/ship.gd scenes/ship/ship.tscn
git commit -m "Add Ship scene composing Hull, Shield, Engine, and weapon mounts"
```

---

### Task 6: `AIController`

**Files:**
- Create: `scripts/controllers/ai_controller.gd`
- Create: `tests/test_ai_controller_state.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `Ship.attack_range()`, `Ship.hull.current_hp`/`max_hp`, `Order` (Task 1/5).
- Produces: `class_name AIController` (extends `Node`) with `retreat_hp_ratio: float`, `setup(ship: Ship, enemy: Ship) -> void`, internal `state: State` enum `{APPROACH, ENGAGE, RETREAT}`, and a pure helper `AIController.next_state(state: State, hp_ratio: float, retreat_hp_ratio: float, in_attack_range: bool) -> State` used by both `_physics_process` and the unit test.

- [ ] **Step 1: Write `AIController`**

`scripts/controllers/ai_controller.gd`:
```gdscript
class_name AIController
extends Node

enum State { APPROACH, ENGAGE, RETREAT }

@export var retreat_hp_ratio: float = 0.25

var state: State = State.APPROACH
var ship: Ship
var enemy: Ship

func setup(p_ship: Ship, p_enemy: Ship) -> void:
	ship = p_ship
	enemy = p_enemy

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(ship) or not is_instance_valid(enemy):
		return
	var hp_ratio: float = ship.hull.current_hp / ship.hull.max_hp
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

- [ ] **Step 2: Write the state-transition test**

`tests/test_ai_controller_state.gd`:
```gdscript
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []

	var s := AIController.next_state(AIController.State.APPROACH, 1.0, 0.25, false)
	if s != AIController.State.APPROACH:
		failures.append("expected to stay APPROACH when out of range, got %s" % s)

	s = AIController.next_state(AIController.State.APPROACH, 1.0, 0.25, true)
	if s != AIController.State.ENGAGE:
		failures.append("expected APPROACH->ENGAGE when in range, got %s" % s)

	s = AIController.next_state(AIController.State.ENGAGE, 0.2, 0.25, true)
	if s != AIController.State.RETREAT:
		failures.append("expected ENGAGE->RETREAT when hp low, got %s" % s)

	s = AIController.next_state(AIController.State.RETREAT, 0.9, 0.25, false)
	if s != AIController.State.APPROACH:
		failures.append("expected RETREAT->APPROACH when healed, got %s" % s)

	s = AIController.next_state(AIController.State.RETREAT, 0.3, 0.25, false)
	if s != AIController.State.RETREAT:
		failures.append("expected to stay RETREAT until healed past threshold, got %s" % s)

	return failures
```

- [ ] **Step 3: Register the test in the runner**

Add `preload("res://tests/test_ai_controller_state.gd"),` to `tests/run_tests.gd`'s `test_scripts`.

- [ ] **Step 4: Run tests and verify they pass**

Run: `godot --headless --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/controllers/ai_controller.gd tests/test_ai_controller_state.gd tests/run_tests.gd
git commit -m "Add AIController state machine"
```

---

### Task 7: `RTSCommander`

**Files:**
- Create: `scripts/controllers/rts_commander.gd`

**Interfaces:**
- Consumes: `Ship.execute_order()`, `Order.move_to`/`Order.attack_target` (Task 1/5).
- Produces: `class_name RTSCommander` (extends `Node`) with `setup(ship: Ship, enemy: Ship) -> void`. Left-click near the enemy issues `attack_target`; right-click elsewhere issues `move_to`.

- [ ] **Step 1: Write `RTSCommander`**

`scripts/controllers/rts_commander.gd`:
```gdscript
class_name RTSCommander
extends Node

const CLICK_TARGET_RADIUS := 40.0

var ship: Ship
var enemy: Ship

func setup(p_ship: Ship, p_enemy: Ship) -> void:
	ship = p_ship
	enemy = p_enemy

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(ship):
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var world_pos: Vector2 = ship.get_global_mouse_position()
	if event.button_index == MOUSE_BUTTON_LEFT:
		if is_instance_valid(enemy) and enemy.global_position.distance_to(world_pos) < CLICK_TARGET_RADIUS:
			ship.execute_order(Order.attack_target(enemy))
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		ship.execute_order(Order.move_to(world_pos))
```

- [ ] **Step 2: Manual verification**

In a scratch scene with a player `Ship` and an enemy `Ship`, add an `RTSCommander` node, call `setup(player_ship, enemy_ship)` from a temporary `_ready()`. Run the scene: right-click empty space and confirm the player ship moves there; left-click on/near the enemy ship and confirm the player ship turns to attack and fires within range. Delete scratch scene afterward.

- [ ] **Step 3: Commit**

```bash
git add scripts/controllers/rts_commander.gd
git commit -m "Add RTSCommander click-to-order controller"
```

---

### Task 8: `DirectPilot` and `ControlToggle`

**Files:**
- Create: `scripts/controllers/direct_pilot.gd`
- Create: `scripts/controllers/control_toggle.gd`
- Modify: `project.godot` (input map)

**Interfaces:**
- Consumes: `Ship.control_mode`, `Ship.engine`, `Ship.weapon_mounts`, `RTSCommander` (Task 5/7).
- Produces: `class_name DirectPilot` (extends `Node`) with `setup(ship: Ship, enemy: Node2D) -> void`. Produces `class_name ControlToggle` (extends `Node`) with `setup(ship: Ship, rts: RTSCommander, direct: DirectPilot) -> void`, toggled by the `toggle_control_mode` input action.

- [ ] **Step 1: Add input actions**

Open `project.godot` in the editor's Project Settings → Input Map (or edit the `[input]` section directly) and add these actions with the given default bindings:
- `pilot_turn_left` → A key
- `pilot_turn_right` → D key
- `pilot_thrust` → W key
- `pilot_fire` → Space key
- `toggle_control_mode` → Tab key

- [ ] **Step 2: Write `DirectPilot`**

`scripts/controllers/direct_pilot.gd`:
```gdscript
class_name DirectPilot
extends Node

var ship: Ship
var enemy: Node2D

func setup(p_ship: Ship, p_enemy: Node2D) -> void:
	ship = p_ship
	enemy = p_enemy

func _physics_process(delta: float) -> void:
	if not is_instance_valid(ship):
		return
	var turn := Input.get_axis("pilot_turn_left", "pilot_turn_right")
	ship.rotation += turn * ship.engine.turn_rate * delta
	var thrust := Input.get_action_strength("pilot_thrust")
	if thrust > 0.0:
		var forward := Vector2.RIGHT.rotated(ship.rotation)
		ship.velocity = ship.velocity.move_toward(forward * ship.engine.max_speed, ship.engine.acceleration * delta)
	else:
		ship.velocity = ship.velocity.move_toward(Vector2.ZERO, ship.engine.acceleration * delta)
	ship.move_and_slide()
	if Input.is_action_pressed("pilot_fire") and is_instance_valid(enemy):
		for mount in ship.weapon_mounts:
			mount.try_fire(enemy)
```

- [ ] **Step 3: Write `ControlToggle`**

`scripts/controllers/control_toggle.gd`:
```gdscript
class_name ControlToggle
extends Node

enum Mode { RTS_COMMAND, DIRECT_PILOT }

var mode: Mode = Mode.RTS_COMMAND
var ship: Ship
var rts_commander: RTSCommander
var direct_pilot: DirectPilot

func setup(p_ship: Ship, p_rts: RTSCommander, p_direct: DirectPilot) -> void:
	ship = p_ship
	rts_commander = p_rts
	direct_pilot = p_direct
	_apply_mode()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_control_mode"):
		mode = Mode.DIRECT_PILOT if mode == Mode.RTS_COMMAND else Mode.RTS_COMMAND
		_apply_mode()

func _apply_mode() -> void:
	var is_direct := mode == Mode.DIRECT_PILOT
	ship.control_mode = Ship.ControlMode.DIRECT if is_direct else Ship.ControlMode.ORDER_BASED
	rts_commander.set_process_unhandled_input(not is_direct)
	direct_pilot.set_physics_process(is_direct)
```

- [ ] **Step 4: Manual verification**

In a scratch scene with a player `Ship`, `RTSCommander`, and `DirectPilot` all set up, add a `ControlToggle` and call `setup()`. Run the scene: confirm right/left-click commands work by default (RTS mode), press Tab, confirm WASD+Space now directly pilots the ship and clicks no longer issue orders, press Tab again and confirm RTS control returns with the ship's prior velocity/rotation intact (no snap/reset). Delete scratch scene afterward.

- [ ] **Step 5: Commit**

```bash
git add scripts/controllers/direct_pilot.gd scripts/controllers/control_toggle.gd project.godot
git commit -m "Add DirectPilot and ControlToggle for dual control modes"
```

---

### Task 9: `CombatScene` — assemble the 1v1 duel

**Files:**
- Create: `scripts/combat/combat_scene.gd`
- Create: `scenes/combat/combat_scene.tscn`

**Interfaces:**
- Consumes: `Ship`, `RTSCommander`, `DirectPilot`, `ControlToggle`, `AIController` (all prior tasks).
- Produces: the playable entry point. No later task consumes this one — it's the milestone's deliverable.

- [ ] **Step 1: Write `CombatScene`**

`scripts/combat/combat_scene.gd`:
```gdscript
extends Node2D

@onready var player_ship: Ship = $PlayerShip
@onready var enemy_ship: Ship = $EnemyShip
@onready var rts_commander: RTSCommander = $RTSCommander
@onready var direct_pilot: DirectPilot = $DirectPilot
@onready var control_toggle: ControlToggle = $ControlToggle
@onready var ai_controller: AIController = $AIController
@onready var result_label: Label = $ResultLabel

func _ready() -> void:
	result_label.visible = false
	rts_commander.setup(player_ship, enemy_ship)
	direct_pilot.setup(player_ship, enemy_ship)
	control_toggle.setup(player_ship, rts_commander, direct_pilot)
	ai_controller.setup(enemy_ship, player_ship)

	player_ship.hull.destroyed.connect(_on_player_destroyed)
	enemy_ship.hull.destroyed.connect(_on_enemy_destroyed)

func _on_player_destroyed() -> void:
	_show_result("Defeat")

func _on_enemy_destroyed() -> void:
	_show_result("Victory")

func _show_result(text: String) -> void:
	result_label.text = text
	result_label.visible = true
	set_physics_process(false)
```

- [ ] **Step 2: Build the `CombatScene` scene**

In the Godot editor: create a new scene, root `Node2D` named `CombatScene`. Add children:
- `PlayerShip` — instance of `scenes/ship/ship.tscn`, positioned at e.g. `(200, 300)`.
- `EnemyShip` — instance of `scenes/ship/ship.tscn`, positioned at e.g. `(800, 300)`, rotated 180° to face the player.
- `RTSCommander` (attach `rts_commander.gd`)
- `DirectPilot` (attach `direct_pilot.gd`)
- `ControlToggle` (attach `control_toggle.gd`)
- `AIController` (attach `ai_controller.gd`)
- `ResultLabel` — a `Label` node, large font, centered on screen, initially hidden.

Attach `scripts/combat/combat_scene.gd` to the root. Save as `scenes/combat/combat_scene.tscn`. In Project Settings → Application → Run, set this as the main scene.

- [ ] **Step 3: Playtest the full 1v1 duel**

Run the project (F5). Verify:
- Right-click moves the player ship; left-clicking the enemy issues an attack order and the player ship closes to range and autofires.
- Pressing Tab switches to direct-pilot mode; WASD + Space fly and fire the player ship directly; Tab again returns to RTS mode without a position/velocity snap.
- The enemy AI approaches, engages, fires back, and retreats when its hull drops below 25%, resuming approach once it recovers (shield regen may allow this if you back off).
- Destroying the enemy shows "Victory"; letting the player ship's hull reach 0 shows "Defeat"; the losing ship visually disappears (`queue_free`) in both cases.

If any of these don't hold, fix the relevant script from the earlier task before proceeding — do not patch around it in `combat_scene.gd`.

- [ ] **Step 4: Commit**

```bash
git add scripts/combat/combat_scene.gd scenes/combat/combat_scene.tscn project.godot
git commit -m "Add CombatScene assembling the 1v1 duel"
```
