# Ship Components, Component Damage, and Station Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give engines and weapon mounts their own hittable health (separate from hull/shield), make damaged engines lose thrust and destroyed weapon mounts stop firing, add matching visual feedback (engine/mount explosions, a shield glow that dims and blinks out), persist this damage across the campaign layer, and let the player pay a flat per-ship fee to repair at any station.

**Architecture:** A new `ShipComponent` base (`extends Node2D`, HP + `destroyed` signal) is adopted by `Hull`, `ShipEngine`, and `WeaponMount`. Hit location is resolved geometrically (no real physics collision) against each component's `hitbox_radius`, matching the existing distance-check style in `Projectile`. Component state round-trips through the same composition-dict mechanism `Hull`/`Shield` already use between combat and the campaign layer.

**Tech Stack:** Godot 4.x GDScript. Headless test command: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`.

## Global Constraints

- Hit detection stays geometric/manual — no `Area2D` monitoring signals (spec: Non-goals).
- A component hit is exclusive: full overflow goes to that component, never spills to hull (spec: Damage routing).
- Shield absorbs first, unconditionally, everywhere on the ship (spec: Damage routing).
- Weapon mount destruction never damages the hull (spec: Weapon mount behavior).
- Repair is a single flat fee (`REPAIR_COST`) per damaged ship, not per component (spec: Station repair).
- Existing `Hull`/`Shield`/`WeaponMount` public APIs used by other scripts must keep working unchanged unless this plan explicitly says otherwise.
- All new composition-dict fields must be read with safe fallbacks so existing hand-built test dicts (which lack the new fields) keep working.

---

### Task 1: `ShipComponent` base class

**Files:**
- Create: `scripts/ship/ship_component.gd`
- Test: `tests/test_ship_component.gd`
- Modify: `tests/run_tests.gd` (register new test)

**Interfaces:**
- Produces: `class_name ShipComponent extends Node2D` with `@export var max_hp: float`, `@export var hitbox_radius: float = 0.0`, `var current_hp: float`, `signal destroyed`, `signal damaged(amount, remaining)`, `apply_damage(amount) -> void`, `is_destroyed() -> bool`, `health_fraction() -> float`.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_ship_component.gd
extends RefCounted

const ShipComponent = preload("res://scripts/ship/ship_component.gd")

class CallbackTracker:
	var fired := false
	func on_destroyed() -> void:
		fired = true

static func run() -> Array[String]:
	var failures: Array[String] = []
	var comp := ShipComponent.new()
	comp.max_hp = 40.0
	comp._ready()

	var tracker := CallbackTracker.new()
	comp.destroyed.connect(tracker.on_destroyed)

	if not is_equal_approx(comp.current_hp, 40.0):
		failures.append("_ready: expected current_hp seeded to max_hp, got %s" % comp.current_hp)
	if not is_equal_approx(comp.health_fraction(), 1.0):
		failures.append("health_fraction: expected 1.0 at full health, got %s" % comp.health_fraction())

	comp.apply_damage(10.0)
	if not is_equal_approx(comp.current_hp, 30.0):
		failures.append("apply_damage: expected 30.0 remaining, got %s" % comp.current_hp)
	if tracker.fired:
		failures.append("apply_damage: destroyed fired prematurely")
	if not is_equal_approx(comp.health_fraction(), 0.75):
		failures.append("health_fraction: expected 0.75, got %s" % comp.health_fraction())

	comp.apply_damage(1000.0)
	if comp.current_hp != 0.0:
		failures.append("apply_damage: expected 0.0 after overkill, got %s" % comp.current_hp)
	if not tracker.fired:
		failures.append("apply_damage: destroyed signal did not fire at 0 hp")
	if not comp.is_destroyed():
		failures.append("is_destroyed: expected true at 0 hp")

	tracker.fired = false
	comp.apply_damage(5.0)
	if tracker.fired:
		failures.append("apply_damage: destroyed re-fired on an already-dead component")

	comp.free()
	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: compile error (`ship_component.gd` does not exist).

- [ ] **Step 3: Write minimal implementation**

```gdscript
# scripts/ship/ship_component.gd
class_name ShipComponent
extends Node2D

signal destroyed
signal damaged(amount: float, remaining: float)

@export var max_hp: float = 10.0
@export var hitbox_radius: float = 0.0
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

func health_fraction() -> float:
	return current_hp / max_hp if max_hp > 0.0 else 0.0
```

- [ ] **Step 4: Register the test and run again**

Add `preload("res://tests/test_ship_component.gd"),` to the `test_scripts` array in `tests/run_tests.gd`, right after the `test_order.gd` entry.

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/ship_component.gd tests/test_ship_component.gd tests/run_tests.gd
git commit -m "Add ShipComponent base class for hittable ship subsystems"
```

---

### Task 2: Migrate `Hull` to `ShipComponent`

**Files:**
- Modify: `scripts/ship/hull.gd`
- Modify: `scenes/ship/ship.tscn`, `scenes/ship/ship_corvette.tscn`, `scenes/ship/ship_freighter.tscn`, `scenes/ship/ship_capital.tscn` (one-line node-type fix only — see Step 3b)
- Test: `tests/test_hull.gd` (extend)

**Interfaces:**
- Consumes: `ShipComponent` (Task 1).
- Produces: `Hull` keeps `max_hp`, `current_hp`, `apply_damage()`, `destroyed`, `damaged`, `is_destroyed()`, plus new `invulnerable: bool` behavior unchanged, now inherited `health_fraction()`.

**Why the scenes move here too:** `ShipComponent` extends `Node2D`, but every scene currently declares its `Hull` child as `[node name="Hull" type="Node" ...]`. Godot refuses to attach a script whose base class (`Node2D`) doesn't match the declared node type (`Node`) — so the moment `hull.gd` extends `ShipComponent`, every ship scene fails to instantiate until the node's declared type is bumped to `Node2D` too. That bump has to land in this same commit, not deferred to Task 9's scene-polish pass, or every integration test in Tasks 3–8 (anything that instantiates a ship scene) breaks.

- [ ] **Step 1: Write the failing test (append to existing file)**

```gdscript
# Append inside tests/test_hull.gd's run(), before `hull.free()`:
	var guarded := Hull.new()
	guarded.max_hp = 50.0
	guarded.current_hp = 50.0
	guarded.invulnerable = true
	guarded.apply_damage(50.0)
	if guarded.current_hp != 50.0:
		failures.append("apply_damage: expected invulnerable hull to take no damage, got %s" % guarded.current_hp)
	if not is_equal_approx(guarded.health_fraction(), 1.0):
		failures.append("health_fraction: expected inherited health_fraction() to work on Hull, got %s" % guarded.health_fraction())
	guarded.free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'health_fraction'`.

- [ ] **Step 3: Rewrite `hull.gd` as a `ShipComponent` subclass**

```gdscript
# scripts/ship/hull.gd
class_name Hull
extends ShipComponent

var invulnerable: bool = false

func apply_damage(amount: float) -> void:
	if invulnerable:
		return
	super.apply_damage(amount)
```

- [ ] **Step 3b: Bump `Hull`'s declared node type in every ship scene**

In each of `scenes/ship/ship.tscn`, `scenes/ship/ship_corvette.tscn`, `scenes/ship/ship_freighter.tscn`, `scenes/ship/ship_capital.tscn`, change:

```
[node name="Hull" type="Node" parent="."]
```

to:

```
[node name="Hull" type="Node2D" parent="."]
```

(Only the `type` attribute changes — every other line on that node, e.g. `script = ExtResource(...)` or `max_hp = ...`, stays exactly as-is.)

- [ ] **Step 4: Run test to verify it passes**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.` (This now also re-validates every integration test that instantiates a ship scene — `test_ship.gd`'s `run_async`, `test_ship_type_scenes.gd`, `test_combat_scene.gd`, etc. — since they all transitively depend on `Hull` loading correctly.)

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/hull.gd scenes/ship/ship.tscn scenes/ship/ship_corvette.tscn scenes/ship/ship_freighter.tscn scenes/ship/ship_capital.tscn tests/test_hull.gd
git commit -m "Migrate Hull to the ShipComponent base class"
```

---

### Task 3: Engine health and thrust loss

**Files:**
- Modify: `scripts/ship/ship_engine.gd`
- Modify: `scenes/ship/ship.tscn`, `scenes/ship/ship_corvette.tscn`, `scenes/ship/ship_freighter.tscn`, `scenes/ship/ship_capital.tscn` (one-line node-type fix only — same reason as Task 2's Step 3b)
- Test: `tests/test_ship_engine.gd` (extend)

**Interfaces:**
- Consumes: `ShipComponent` (Task 1).
- Produces: `ShipEngine.effective_acceleration() -> float`, `ShipEngine.effective_max_speed() -> float`; `steer_toward`/`stopping_distance` now scale with engine health.

- [ ] **Step 1: Write the failing test (modify existing file)**

First, fix a latent regression in the existing block: `ship_engine` there is never seeded via `_ready()`, so once `effective_acceleration()` exists, its `current_hp` (inherited from `ShipComponent`, default 0.0 until `_ready()` runs) would make it read as fully destroyed and this already-passing assertion would start failing. Add a `_ready()` call right after the existing `ship_engine.turn_rate = 10.0` line (before `steer_toward` is called):

```gdscript
	ship_engine.turn_rate = 10.0
	ship_engine._ready()  # seed current_hp = max_hp now that ShipEngine extends ShipComponent
```

Then append this new block, before `ship_engine.free()`:

```gdscript
# Append inside tests/test_ship_engine.gd's run(), before `ship_engine.free()`:
	var damaged_engine := ShipEngine.new()
	damaged_engine.max_speed = 200.0
	damaged_engine.acceleration = 100.0
	damaged_engine.max_hp = 20.0
	damaged_engine._ready()
	damaged_engine.apply_damage(10.0)  # 50% health

	if not is_equal_approx(damaged_engine.effective_acceleration(), 50.0):
		failures.append("effective_acceleration: expected 50.0 at half health, got %s" % damaged_engine.effective_acceleration())
	if not is_equal_approx(damaged_engine.effective_max_speed(), 100.0):
		failures.append("effective_max_speed: expected 100.0 at half health, got %s" % damaged_engine.effective_max_speed())

	damaged_engine.apply_damage(1000.0)
	if not is_equal_approx(damaged_engine.effective_acceleration(), 0.0):
		failures.append("effective_acceleration: expected 0.0 once engine is destroyed, got %s" % damaged_engine.effective_acceleration())

	var dead_steer := damaged_engine.steer_toward(Vector2.ZERO, 0.0, Vector2(100, 0), 1.0)
	var dead_vel: Vector2 = dead_steer["velocity"]
	if dead_vel.length() > 0.01:
		failures.append("steer_toward: expected a destroyed engine to produce no new acceleration, velocity length was %s" % dead_vel.length())

	damaged_engine.free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'effective_acceleration'`.

- [ ] **Step 3: Implement**

```gdscript
# scripts/ship/ship_engine.gd
class_name ShipEngine
extends ShipComponent

@export var max_speed: float = 200.0
@export var turn_rate: float = 3.0
@export var acceleration: float = 150.0

var velocity: Vector2 = Vector2.ZERO

func effective_acceleration() -> float:
	return acceleration * health_fraction()

func effective_max_speed() -> float:
	return max_speed * health_fraction()

func steer_toward(current_pos: Vector2, current_rotation: float, target_pos: Vector2, delta: float, slow_radius: float = -1.0) -> Dictionary:
	var to_target := target_pos - current_pos
	var distance := to_target.length()
	var accel := effective_acceleration()
	if distance < 1.0:
		velocity = velocity.move_toward(Vector2.ZERO, accel * delta)
		return {"rotation": current_rotation, "velocity": velocity}
	var desired_angle := to_target.angle()
	var new_rotation := rotate_toward_angle(current_rotation, desired_angle, turn_rate * delta)
	var forward := Vector2.RIGHT.rotated(new_rotation)
	var top_speed := effective_max_speed()
	var effective_slow_radius := slow_radius if slow_radius >= 0.0 else stopping_distance()
	var desired_speed := top_speed
	if effective_slow_radius > 0.0 and distance < effective_slow_radius:
		desired_speed = top_speed * (distance / effective_slow_radius)
	velocity = velocity.move_toward(forward * desired_speed, accel * delta)
	return {"rotation": new_rotation, "velocity": velocity}

func stopping_distance() -> float:
	var accel := effective_acceleration()
	var top_speed := effective_max_speed()
	return (top_speed * top_speed) / (2.0 * accel) if accel > 0.0 else 0.0

static func rotate_toward_angle(current: float, target: float, max_delta: float) -> float:
	var diff := wrapf(target - current, -PI, PI)
	if abs(diff) <= max_delta:
		return target
	return current + sign(diff) * max_delta
```

- [ ] **Step 4: Bump `Engine`'s declared node type in every ship scene**

Same reasoning as Task 2's Step 3b: `ShipEngine` now extends `ShipComponent` (`Node2D`-based), but every scene still declares `[node name="Engine" type="Node" parent="."]`. In each of `scenes/ship/ship.tscn`, `scenes/ship/ship_corvette.tscn`, `scenes/ship/ship_freighter.tscn`, `scenes/ship/ship_capital.tscn`, change:

```
[node name="Engine" type="Node" parent="."]
```

to:

```
[node name="Engine" type="Node2D" parent="."]
```

(Only the `type` attribute changes — every other line on that node stays exactly as-is; hitbox/position tuning is Task 9.)

- [ ] **Step 5: Run test to verify it passes**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 6: Commit**

```bash
git add scripts/ship/ship_engine.gd scenes/ship/ship.tscn scenes/ship/ship_corvette.tscn scenes/ship/ship_freighter.tscn scenes/ship/ship_capital.tscn tests/test_ship_engine.gd
git commit -m "Scale engine thrust with engine health"
```

---

### Task 4: Weapon mount health gates firing

**Files:**
- Modify: `scripts/weapons/weapon_mount.gd`
- Test: `tests/test_weapon_mount.gd` (extend)

**Interfaces:**
- Consumes: `ShipComponent` (Task 1).
- Produces: `WeaponMount.can_fire()` now also requires `not is_destroyed()`.

- [ ] **Step 1: Write the failing test (modify existing file)**

First, fix a latent regression: every `WeaponMount.new()` in this file's existing `run()` and `run_async()` is used without ever calling `_ready()`, so once `can_fire()` also checks `is_destroyed()`, its inherited `current_hp` (default 0.0 until `_ready()` runs) would make every existing mount read as already-destroyed and every existing assertion in this file would start failing. Add a `_ready()` call immediately after each existing `WeaponMount.new()` call (there are two: one in `run()`, one in `run_async()`):

```gdscript
# In run(), right after `var mount := WeaponMount.new()`:
	mount.weapon = weapon
	mount._ready()  # seed current_hp = max_hp now that WeaponMount extends ShipComponent
```

```gdscript
# In run_async(), right after `var mount := WeaponMount.new()`:
	mount.weapon = weapon
	mount._ready()
```

Then append this new block to `run()`, before `mount.free()`:

```gdscript
	var dying_mount := WeaponMount.new()
	dying_mount.weapon = weapon
	dying_mount.max_hp = 15.0
	dying_mount._ready()
	if not dying_mount.can_fire():
		failures.append("can_fire: expected true before any damage")
	dying_mount.apply_damage(15.0)
	if dying_mount.can_fire():
		failures.append("can_fire: expected false once the mount is destroyed")
	if dying_mount.try_fire(close_target):
		failures.append("try_fire: expected false once the mount is destroyed, even with target in range")
	dying_mount.free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `can_fire` still true after destruction (or a crash if `apply_damage`/`is_destroyed` don't exist yet on `WeaponMount`).

- [ ] **Step 3: Implement**

```gdscript
# scripts/weapons/weapon_mount.gd
class_name WeaponMount
extends ShipComponent

const MuzzleFlashScene = preload("res://scenes/vfx/muzzle_flash.tscn")

@export var weapon: Weapon
var cooldown_remaining: float = 0.0

func _physics_process(delta: float) -> void:
	if cooldown_remaining > 0.0:
		cooldown_remaining -= delta

func can_fire() -> bool:
	return weapon != null and cooldown_remaining <= 0.0 and not is_destroyed()

func try_fire(target: Node2D) -> bool:
	if not can_fire() or target == null or not is_instance_valid(target):
		return false
	if global_position.distance_to(target.global_position) > weapon.weapon_range:
		return false
	_spawn_projectile(target)
	cooldown_remaining = 1.0 / weapon.fire_rate
	return true

func _spawn_projectile(target: Node2D) -> void:
	if weapon.projectile_scene == null:
		return
	var projectile: Node2D = weapon.projectile_scene.instantiate()
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	host.add_child(projectile)
	projectile.global_position = global_position
	projectile.setup(target, weapon.damage, weapon.weapon_range)
	var muzzle_flash: Node2D = MuzzleFlashScene.instantiate()
	host.add_child(muzzle_flash)
	muzzle_flash.global_position = global_position
	muzzle_flash.rotation = (target.global_position - global_position).angle()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/weapons/weapon_mount.gd tests/test_weapon_mount.gd
git commit -m "Weapon mounts stop firing once destroyed"
```

---

### Task 5: Component hit resolution and damage routing on `Ship`

**Files:**
- Modify: `scripts/ship/ship.gd`
- Modify: `scripts/weapons/projectile.gd`
- Test: `tests/test_ship.gd` (extend `_check_ship_logic`)
- Test: `tests/test_projectile.gd` (extend)

**Interfaces:**
- Consumes: `ShipComponent.hitbox_radius`/`is_destroyed()` (Task 1), `ship.weapon_mounts`, `ship.engine`.
- Produces: `Ship.hit_radius: float` export, `Ship.get_hit_radius() -> float`, `Ship.resolve_component_hit(impact_pos: Vector2) -> ShipComponent`, `Ship.receive_damage(amount, impact_position = Vector2.INF)`.

- [ ] **Step 1: Write the failing tests**

In `tests/test_ship.gd`, append inside `_check_ship_logic`, right before the `hull.free()` / `shield.free()` cleanup block:

```gdscript
	# Component hit resolution: a mount positioned away from the ship's
	# origin should absorb overflow damage exclusively, leaving hull/shield
	# untouched, when the impact point lands inside its hitbox.
	var hit_ship := Ship.new()
	var hit_hull := Hull.new()
	hit_hull.max_hp = 100.0
	hit_hull._ready()
	var hit_shield := Shield.new()
	hit_shield.max_shield = 0.0
	hit_shield.current_shield = 0.0
	var hit_engine := ShipEngine.new()
	hit_engine.max_hp = 20.0
	hit_engine._ready()
	var hit_mount := WeaponMount.new()
	hit_mount.max_hp = 15.0
	hit_mount._ready()
	hit_mount.hitbox_radius = 8.0
	hit_mount.position = Vector2(20, 0)
	hit_ship.hull = hit_hull
	hit_ship.shield = hit_shield
	hit_ship.engine = hit_engine
	hit_ship.weapon_mounts = [hit_mount]
	hit_ship.add_child(hit_mount)
	hit_ship.add_child(hit_engine)

	hit_ship.receive_damage(10.0, Vector2(20, 2))
	if not is_equal_approx(hit_mount.current_hp, 5.0):
		failures.append("receive_damage: expected the mount's hitbox to absorb the hit, got mount.current_hp=%s" % hit_mount.current_hp)
	if not is_equal_approx(hit_hull.current_hp, 100.0):
		failures.append("receive_damage: expected hull untouched by a component-exclusive hit, got %s" % hit_hull.current_hp)

	hit_ship.receive_damage(10.0, Vector2(-200, -200))
	if not is_equal_approx(hit_hull.current_hp, 90.0):
		failures.append("receive_damage: expected a hit outside every hitbox to fall through to hull, got %s" % hit_hull.current_hp)

	hit_ship.receive_damage(10.0)
	if not is_equal_approx(hit_hull.current_hp, 80.0):
		failures.append("receive_damage: expected the default impact_position to route to hull (ship's own center), got %s" % hit_hull.current_hp)

	hit_ship.free()
```

In `tests/test_projectile.gd`, replace the whole file with:

```gdscript
extends RefCounted

const Projectile = preload("res://scripts/weapons/projectile.gd")

class RecordingTarget:
	extends Node2D
	var received_amount: float = -1.0
	var received_position: Vector2 = Vector2.ZERO
	func receive_damage(amount: float, impact_position: Vector2 = Vector2.ZERO) -> void:
		received_amount = amount
		received_position = impact_position

static func run() -> Array[String]:
	var failures: Array[String] = []

	var projectile := Projectile.new()
	var target := Node2D.new()
	target.global_position = Vector2(0.0, 100.0)
	projectile.global_position = Vector2.ZERO
	projectile.setup(target, 10.0)

	var expected_angle: float = Vector2(0.0, 100.0).angle()
	if not is_equal_approx(projectile.rotation, expected_angle):
		failures.append("setup: expected rotation to face travel_direction (%s), got %s" % [expected_angle, projectile.rotation])

	target.free()
	projectile.free()

	var hit_projectile := Projectile.new()
	var recording_target := RecordingTarget.new()
	recording_target.global_position = Vector2(5.0, 0.0)
	hit_projectile.global_position = Vector2(0.0, 0.0)
	hit_projectile.setup(recording_target, 25.0)
	hit_projectile._hit()

	if not is_equal_approx(recording_target.received_amount, 25.0):
		failures.append("_hit: expected receive_damage called with the projectile's damage, got %s" % recording_target.received_amount)
	if not recording_target.received_position.is_equal_approx(Vector2(0.0, 0.0)):
		failures.append("_hit: expected receive_damage called with the projectile's own global_position as impact_position, got %s" % recording_target.received_position)

	recording_target.free()
	return failures
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `receive_damage` still single-argument, hull takes the mount's damage, and `_hit` doesn't pass a position.

- [ ] **Step 3: Implement `Ship` changes**

In `scripts/ship/ship.gd`, add `hit_radius` export near the top and replace `receive_damage`:

```gdscript
@export var hit_radius: float = 16.0
```
(place it directly below `@export var ship_type: ShipType.Kind = ShipType.Kind.CORVETTE`)

```gdscript
func get_hit_radius() -> float:
	return hit_radius

func receive_damage(amount: float, impact_position: Vector2 = Vector2.INF) -> void:
	var overflow := shield.absorb(amount)
	if overflow <= 0.0:
		return
	var pos := global_position if impact_position == Vector2.INF else impact_position
	var hit_component := resolve_component_hit(pos)
	if hit_component != null:
		hit_component.apply_damage(overflow)
	else:
		hull.apply_damage(overflow)

func resolve_component_hit(impact_pos: Vector2) -> ShipComponent:
	var best: ShipComponent = null
	var best_dist := INF
	var candidates: Array[ShipComponent] = []
	for mount in weapon_mounts:
		candidates.append(mount)
	candidates.append(engine)
	for comp in candidates:
		if comp == null or comp.is_destroyed() or comp.hitbox_radius <= 0.0:
			continue
		var d := comp.global_position.distance_to(impact_pos)
		if d <= comp.hitbox_radius and d < best_dist:
			best = comp
			best_dist = d
	return best
```

`weapon_mounts` is typed `Array[WeaponMount]`; building `candidates` by appending each element (rather than assigning the typed array directly) avoids a `Array[WeaponMount]` → `Array[ShipComponent]` type mismatch, since GDScript's typed arrays aren't covariant on direct assignment.

- [ ] **Step 4: Implement `Projectile` changes**

In `scripts/weapons/projectile.gd`, update `HIT_RADIUS` usage and `_hit`:

```gdscript
func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		queue_free()
		return
	var step := travel_direction * speed * delta
	global_position += step
	_distance_traveled += step.length()
	var effective_hit_radius := target.get_hit_radius() if target.has_method("get_hit_radius") else HIT_RADIUS
	if global_position.distance_to(target.global_position) < effective_hit_radius:
		_hit()
	elif _distance_traveled >= max_travel:
		queue_free()

func _hit() -> void:
	if is_instance_valid(target) and target.has_method("receive_damage"):
		target.receive_damage(damage, global_position)
	queue_free()
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 6: Commit**

```bash
git add scripts/ship/ship.gd scripts/weapons/projectile.gd tests/test_ship.gd tests/test_projectile.gd
git commit -m "Route damage through per-component hitboxes before falling back to hull"
```

---

### Task 6: Shield visual-feedback signals

**Files:**
- Modify: `scripts/ship/shield.gd`
- Test: `tests/test_shield.gd` (extend)

**Interfaces:**
- Produces: `Shield.health_fraction() -> float`, `signal depleted`, `signal restored` (fires once when regen crosses back above 0).

- [ ] **Step 1: Write the failing test (append to existing `run()`, before `shield.free()`)**

```gdscript
	var signaled := Shield.new()
	signaled.max_shield = 20.0
	signaled.current_shield = 20.0
	var depleted_count := 0
	var restored_count := 0
	signaled.depleted.connect(func(): depleted_count += 1)
	signaled.restored.connect(func(): restored_count += 1)

	signaled.absorb(20.0)
	if depleted_count != 1:
		failures.append("depleted: expected exactly 1 emission on exact depletion, got %s" % depleted_count)
	if not is_equal_approx(signaled.health_fraction(), 0.0):
		failures.append("health_fraction: expected 0.0 when depleted, got %s" % signaled.health_fraction())

	signaled.absorb(5.0)
	if depleted_count != 1:
		failures.append("depleted: expected no re-emission while already at 0, got count=%s" % depleted_count)

	signaled._physics_process(1.0)  # regen_rate default 5.0 -> current_shield rises above 0
	if restored_count != 1:
		failures.append("restored: expected exactly 1 emission when regen crosses back above 0, got %s" % restored_count)

	signaled.free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `Invalid access to property or key 'depleted'`.

- [ ] **Step 3: Implement**

```gdscript
# scripts/ship/shield.gd
class_name Shield
extends Node

signal depleted
signal restored

@export var max_shield: float = 50.0
@export var regen_rate: float = 5.0
var current_shield: float

func _ready() -> void:
	current_shield = max_shield

func _physics_process(delta: float) -> void:
	if current_shield < max_shield:
		var was_depleted := current_shield <= 0.0
		current_shield = min(max_shield, current_shield + regen_rate * delta)
		if was_depleted and current_shield > 0.0:
			restored.emit()

func absorb(amount: float) -> float:
	if current_shield <= 0.0:
		return amount
	var remaining := max(0.0, current_shield - amount)
	var overflow := max(0.0, amount - current_shield)
	current_shield = remaining
	if current_shield <= 0.0:
		depleted.emit()
	return overflow

func health_fraction() -> float:
	return current_shield / max_shield if max_shield > 0.0 else 0.0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/shield.gd tests/test_shield.gd
git commit -m "Add Shield depleted/restored signals and health_fraction for visual feedback"
```

---

### Task 7: Per-kind engine/mount base stats and composition fields

**Files:**
- Modify: `scripts/ship/ship_type.gd`
- Test: `tests/test_ship_type.gd` (extend)

**Interfaces:**
- Consumes: nothing new.
- Produces: `ShipType.new_composition(kind)` dicts now also carry `engine_max_hp`, `engine_current_hp`, `weapon_mount_max_hp: Array[float]`, `weapon_mount_current_hp: Array[float]`.

- [ ] **Step 1: Write the failing test (append to existing `run()`, if any, or create one — read the current file first)**

Read `tests/test_ship_type.gd` first to match its existing style, then append:

```gdscript
	var corvette_comp := ShipType.new_composition(ShipType.Kind.CORVETTE)
	if not is_equal_approx(corvette_comp["engine_max_hp"], 25.0):
		failures.append("new_composition: expected corvette engine_max_hp 25.0, got %s" % corvette_comp["engine_max_hp"])
	if corvette_comp["weapon_mount_max_hp"] != [15.0]:
		failures.append("new_composition: expected corvette weapon_mount_max_hp [15.0], got %s" % corvette_comp["weapon_mount_max_hp"])

	var freighter_comp := ShipType.new_composition(ShipType.Kind.FREIGHTER)
	if freighter_comp["weapon_mount_max_hp"] != []:
		failures.append("new_composition: expected freighter weapon_mount_max_hp [] (unarmed), got %s" % freighter_comp["weapon_mount_max_hp"])

	var capital_comp := ShipType.new_composition(ShipType.Kind.CAPITAL)
	if capital_comp["weapon_mount_max_hp"] != [30.0, 30.0, 30.0]:
		failures.append("new_composition: expected capital weapon_mount_max_hp [30.0, 30.0, 30.0], got %s" % capital_comp["weapon_mount_max_hp"])
	if capital_comp["weapon_mount_current_hp"] != capital_comp["weapon_mount_max_hp"]:
		failures.append("new_composition: expected weapon_mount_current_hp to start equal to weapon_mount_max_hp")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `Invalid get index 'engine_max_hp'`.

- [ ] **Step 3: Implement**

```gdscript
# scripts/ship/ship_type.gd
class_name ShipType
extends RefCounted

enum Kind { CORVETTE, FREIGHTER, CAPITAL }

const SCENES := {
	Kind.CORVETTE: "res://scenes/ship/ship_corvette.tscn",
	Kind.FREIGHTER: "res://scenes/ship/ship_freighter.tscn",
	Kind.CAPITAL: "res://scenes/ship/ship_capital.tscn",
}

const BASE_STATS := {
	Kind.CORVETTE: {"max_hp": 60.0, "max_shield": 20.0, "cargo_capacity": 20.0, "engine_hp": 25.0, "weapon_mount_hp": 15.0, "weapon_mount_count": 1},
	Kind.FREIGHTER: {"max_hp": 80.0, "max_shield": 20.0, "cargo_capacity": 60.0, "engine_hp": 35.0, "weapon_mount_hp": 0.0, "weapon_mount_count": 0},
	Kind.CAPITAL: {"max_hp": 220.0, "max_shield": 80.0, "cargo_capacity": 20.0, "engine_hp": 70.0, "weapon_mount_hp": 30.0, "weapon_mount_count": 3},
}

static func scene_for(kind: Kind) -> PackedScene:
	return load(SCENES[kind])

static func kind_of(comp: Dictionary) -> Kind:
	return comp.get("ship_type", Kind.CORVETTE)

static func cargo_capacity_for(kind: Kind) -> float:
	return BASE_STATS[kind]["cargo_capacity"]

static func new_composition(kind: Kind) -> Dictionary:
	var stats: Dictionary = BASE_STATS[kind]
	var mount_hp: Array[float] = []
	for i in int(stats["weapon_mount_count"]):
		mount_hp.append(stats["weapon_mount_hp"])
	return {
		"ship_type": kind,
		"max_hp": stats["max_hp"],
		"current_hp": stats["max_hp"],
		"max_shield": stats["max_shield"],
		"current_shield": stats["max_shield"],
		"engine_max_hp": stats["engine_hp"],
		"engine_current_hp": stats["engine_hp"],
		"weapon_mount_max_hp": mount_hp,
		"weapon_mount_current_hp": mount_hp.duplicate(),
	}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/ship_type.gd tests/test_ship_type.gd
git commit -m "Add per-kind engine/weapon-mount base stats to ship compositions"
```

---

### Task 8: Carry engine/mount damage through combat <-> campaign

**Files:**
- Modify: `scripts/combat/combat_scene.gd`
- Test: `tests/test_combat_scene.gd` (extend the campaign-battle section)

**Interfaces:**
- Consumes: `ShipType.new_composition` fields (Task 7), `Ship.engine`, `Ship.weapon_mounts`.
- Produces: `_apply_fleet_data`/`_collect_survivor_data` round-trip `engine_max_hp`/`engine_current_hp`/`weapon_mount_max_hp`/`weapon_mount_current_hp` when present, and leave scene defaults alone when a composition dict omits them (backward compatible with hand-built test dicts).

- [ ] **Step 1: Write the failing test**

In `tests/test_combat_scene.gd`, change the campaign-battle player fleet composition (around the `player_fleet.ship_compositions = [...]` line) to include engine/mount damage, and add assertions after the `await tree.process_frame` that follows spawning:

```gdscript
	var player_fleet := CampaignFleet.new()
	player_fleet.ship_compositions = [{
		"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0,
		"engine_max_hp": 25.0, "engine_current_hp": 5.0,
		"weapon_mount_max_hp": [15.0], "weapon_mount_current_hp": [3.0],
	}]
```

(this replaces the existing `player_fleet.ship_compositions = [{"max_hp": 100.0, ...}]` line)

Then, right after the existing `if campaign_scene.enemy_ships.size() != 1:` block (which already runs after the first `await tree.process_frame` pair), add:

```gdscript
	if campaign_scene.player_ships.size() == 1:
		var spawned_player: Ship = campaign_scene.player_ships[0]
		if not is_equal_approx(spawned_player.engine.current_hp, 5.0):
			failures.append("campaign battle: expected spawned player engine.current_hp carried over from composition, got %s" % spawned_player.engine.current_hp)
		if spawned_player.weapon_mounts.size() != 1 or not is_equal_approx(spawned_player.weapon_mounts[0].current_hp, 3.0):
			failures.append("campaign battle: expected spawned player mount current_hp carried over from composition")

		spawned_player.engine.apply_damage(1000.0)
		spawned_player.weapon_mounts[0].apply_damage(1000.0)
```

And after the existing `if campaign_state.player_fleet.ship_compositions.size() != 1:` survivor-check block, add:

```gdscript
	else:
		var surviving_comp: Dictionary = campaign_state.player_fleet.ship_compositions[0]
		if surviving_comp.get("engine_current_hp", -1.0) != 0.0:
			failures.append("campaign battle: expected the destroyed engine's 0 hp carried back into the composition, got %s" % surviving_comp.get("engine_current_hp"))
		if surviving_comp.get("weapon_mount_current_hp", [-1.0])[0] != 0.0:
			failures.append("campaign battle: expected the destroyed mount's 0 hp carried back into the composition, got %s" % surviving_comp.get("weapon_mount_current_hp"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — spawned player's `engine.current_hp` is still the scene default (not 5.0).

- [ ] **Step 3: Implement**

```gdscript
# scripts/combat/combat_scene.gd
func _apply_fleet_data(ships: Array[Ship], fleet_data: CampaignFleet) -> void:
	for i in ships.size():
		var comp: Dictionary = fleet_data.ship_compositions[i]
		ships[i].hull.max_hp = comp["max_hp"]
		ships[i].hull.current_hp = comp["current_hp"]
		ships[i].shield.max_shield = comp["max_shield"]
		ships[i].shield.current_shield = comp["current_shield"]
		if comp.has("engine_max_hp"):
			ships[i].engine.max_hp = comp["engine_max_hp"]
			ships[i].engine.current_hp = comp["engine_current_hp"]
		if comp.has("weapon_mount_max_hp"):
			var mount_max: Array = comp["weapon_mount_max_hp"]
			var mount_cur: Array = comp["weapon_mount_current_hp"]
			for j in ships[i].weapon_mounts.size():
				if j < mount_max.size():
					ships[i].weapon_mounts[j].max_hp = mount_max[j]
					ships[i].weapon_mounts[j].current_hp = mount_cur[j]
```

```gdscript
func _collect_survivor_data(ships: Array[Ship]) -> Array[Dictionary]:
	var survivors: Array[Dictionary] = []
	for ship in ships:
		if is_instance_valid(ship) and not ship.hull.is_destroyed():
			var mount_max: Array[float] = []
			var mount_cur: Array[float] = []
			for mount in ship.weapon_mounts:
				mount_max.append(mount.max_hp)
				mount_cur.append(mount.current_hp)
			survivors.append({
				"ship_type": ship.ship_type,
				"max_hp": ship.hull.max_hp,
				"current_hp": ship.hull.current_hp,
				"max_shield": ship.shield.max_shield,
				"current_shield": ship.shield.current_shield,
				"engine_max_hp": ship.engine.max_hp,
				"engine_current_hp": ship.engine.current_hp,
				"weapon_mount_max_hp": mount_max,
				"weapon_mount_current_hp": mount_cur,
			})
	return survivors
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/combat/combat_scene.gd tests/test_combat_scene.gd
git commit -m "Carry engine and weapon mount damage between combat and the campaign layer"
```

---

### Task 9: Scene migration — hitbox positions, hit_radius, ShieldGlow

**Files:**
- Modify: `scenes/ship/ship.tscn`, `scenes/ship/ship_corvette.tscn`, `scenes/ship/ship_freighter.tscn`, `scenes/ship/ship_capital.tscn`
- Test: `tests/test_ship.gd` (`_check_scene_structure`), `tests/test_ship_type_scenes.gd` (extend)

**Interfaces:**
- Consumes: `Hull`/`Engine` already declared `type="Node2D"` in every scene (Tasks 2 and 3).
- Produces: `Engine` positioned at the stern with a tuned `hitbox_radius`, `WeaponMount`(s) moved off dead-center with a tuned `hitbox_radius`, a `Ship.hit_radius` override matching the hull's `CollisionShape2D` radius, and a new `ShieldGlow` `Polygon2D` child. (`ShipVfx`'s wiring to `ShieldGlow` is Task 11 — this task only adds the node.)

- [ ] **Step 1: Write the failing tests**

In `tests/test_ship.gd`, inside `_check_scene_structure`, add after the existing `mount_weapon` checks:

```gdscript
	if not is_equal_approx(ship.hit_radius, 16.0):
		failures.append("ship.tscn: expected hit_radius 16.0, got %s" % ship.hit_radius)
	for child in ship.get_children():
		if child is WeaponMount and child.hitbox_radius <= 0.0:
			failures.append("ship.tscn: expected the WeaponMount to have a positive hitbox_radius")
	var generic_engine := ship.get_node_or_null("Engine")
	if generic_engine != null and generic_engine.hitbox_radius <= 0.0:
		failures.append("ship.tscn: expected the Engine to have a positive hitbox_radius")
```

In `tests/test_ship_type_scenes.gd`, add after the existing capital assertions, before the `for ship in [corvette, freighter, capital]:` cleanup loop:

```gdscript
	if not is_equal_approx(corvette.hit_radius, 12.0):
		failures.append("ship_corvette.tscn: expected hit_radius 12.0, got %s" % corvette.hit_radius)
	if corvette.weapon_mounts.size() == 1 and corvette.weapon_mounts[0].hitbox_radius <= 0.0:
		failures.append("ship_corvette.tscn: expected the WeaponMount to have a positive hitbox_radius")
	if corvette.engine.hitbox_radius <= 0.0:
		failures.append("ship_corvette.tscn: expected the Engine to have a positive hitbox_radius")

	if not is_equal_approx(freighter.hit_radius, 22.0):
		failures.append("ship_freighter.tscn: expected hit_radius 22.0, got %s" % freighter.hit_radius)
	if freighter.engine.hitbox_radius <= 0.0:
		failures.append("ship_freighter.tscn: expected the Engine to have a positive hitbox_radius")

	if not is_equal_approx(capital.hit_radius, 34.0):
		failures.append("ship_capital.tscn: expected hit_radius 34.0, got %s" % capital.hit_radius)
	for mount in capital.weapon_mounts:
		if mount.hitbox_radius <= 0.0:
			failures.append("ship_capital.tscn: expected every capital WeaponMount to have a positive hitbox_radius")
	if capital.engine.hitbox_radius <= 0.0:
		failures.append("ship_capital.tscn: expected the Engine to have a positive hitbox_radius")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `hit_radius` is still the `Ship` default (16.0) on every scene, and `hitbox_radius` is 0.0 everywhere.

- [ ] **Step 3: Edit `scenes/ship/ship.tscn`**

`Hull` and `Engine` are already `type="Node2D"` as of Tasks 2 and 3 — reposition `WeaponMount`, give `Engine` a position/hitbox, and add `ShieldGlow`:

```
[node name="Hull" type="Node2D" parent="."]
script = ExtResource("2")

[node name="Engine" type="Node2D" parent="."]
script = ExtResource("4")
hitbox_radius = 6.0
position = Vector2(-8, 0)

[node name="WeaponMount" type="Node2D" parent="."]
script = ExtResource("5")
weapon = ExtResource("6")
hitbox_radius = 6.0
position = Vector2(10, 0)

[node name="ShieldGlow" type="Polygon2D" parent="."]
polygon = PackedVector2Array(20, 0, 14.1, 14.1, 0, 20, -14.1, 14.1, -20, 0, -14.1, -14.1, 0, -20, 14.1, -14.1)
color = Color(0.4, 0.8, 1, 0.35)
```

Add `hit_radius = 16.0` is unnecessary here since 16.0 is `Ship`'s own default — leave the `[node name="Ship" ...]` block as-is (no override needed on this scene).

- [ ] **Step 4: Edit `scenes/ship/ship_corvette.tscn`**

```
[node name="Ship" type="CharacterBody2D"]
script = ExtResource("1")
ship_type = 0
hit_radius = 12.0

[node name="Hull" type="Node2D" parent="."]
script = ExtResource("2")
max_hp = 60.0

[node name="Engine" type="Node2D" parent="."]
script = ExtResource("4")
max_speed = 280.0
turn_rate = 5.0
acceleration = 220.0
hitbox_radius = 5.0
position = Vector2(-6, 0)

[node name="WeaponMount" type="Node2D" parent="."]
script = ExtResource("5")
weapon = ExtResource("6")
hitbox_radius = 5.0
position = Vector2(8, 0)

[node name="ShieldGlow" type="Polygon2D" parent="."]
polygon = PackedVector2Array(16, 0, 11.3, 11.3, 0, 16, -11.3, 11.3, -16, 0, -11.3, -11.3, 0, -16, 11.3, -11.3)
color = Color(0.4, 0.8, 1, 0.35)
```

(Add the `ShieldGlow` node right after the `Sprite2D` node; leave every other existing node untouched.)

- [ ] **Step 5: Edit `scenes/ship/ship_freighter.tscn`**

```
[node name="Ship" type="CharacterBody2D"]
script = ExtResource("1")
ship_type = 1
hit_radius = 22.0

[node name="Hull" type="Node2D" parent="."]
script = ExtResource("2")
max_hp = 80.0

[node name="Engine" type="Node2D" parent="."]
script = ExtResource("4")
max_speed = 110.0
turn_rate = 1.5
acceleration = 80.0
hitbox_radius = 8.0
position = Vector2(-12, 0)

[node name="ShieldGlow" type="Polygon2D" parent="."]
polygon = PackedVector2Array(28, 0, 19.8, 19.8, 0, 28, -19.8, 19.8, -28, 0, -19.8, -19.8, 0, -28, 19.8, -19.8)
color = Color(0.4, 0.8, 1, 0.35)
```

(No `WeaponMount` — freighter stays unarmed. Add `ShieldGlow` right after `Sprite2D`.)

- [ ] **Step 6: Edit `scenes/ship/ship_capital.tscn`**

```
[node name="Ship" type="CharacterBody2D"]
script = ExtResource("1")
ship_type = 2
hit_radius = 34.0

[node name="Hull" type="Node2D" parent="."]
script = ExtResource("2")
max_hp = 220.0

[node name="Engine" type="Node2D" parent="."]
script = ExtResource("4")
max_speed = 90.0
turn_rate = 1.0
acceleration = 60.0
hitbox_radius = 10.0
position = Vector2(-20, 0)

[node name="WeaponMount" type="Node2D" parent="."]
script = ExtResource("5")
position = Vector2(24, 0)
weapon = ExtResource("6")
hitbox_radius = 9.0

[node name="WeaponMount2" type="Node2D" parent="."]
script = ExtResource("5")
position = Vector2(10, -14)
weapon = ExtResource("6")
hitbox_radius = 9.0

[node name="WeaponMount3" type="Node2D" parent="."]
script = ExtResource("5")
position = Vector2(10, 14)
weapon = ExtResource("6")
hitbox_radius = 9.0

[node name="ShieldGlow" type="Polygon2D" parent="."]
polygon = PackedVector2Array(42, 0, 29.7, 29.7, 0, 42, -29.7, 29.7, -42, 0, -29.7, -29.7, 0, -42, 29.7, -29.7)
color = Color(0.4, 0.8, 1, 0.35)
```

(Add `ShieldGlow` right after `Sprite2D`.)

- [ ] **Step 7: Run tests to verify they pass**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.` If Godot reports unimported-resource warnings for the edited `.tscn` files, first run `godot.windows.opt.tools.64_console.exe --headless --path . --editor --quit` once to let the editor re-cache them, then re-run the test command.

- [ ] **Step 8: Commit**

```bash
git add scenes/ship/ship.tscn scenes/ship/ship_corvette.tscn scenes/ship/ship_freighter.tscn scenes/ship/ship_capital.tscn tests/test_ship.gd tests/test_ship_type_scenes.gd
git commit -m "Give ship scenes distinct engine/weapon-mount hitboxes and a shield glow visual"
```

---

### Task 10: VFX — engine and weapon mount destruction

**Files:**
- Modify: `scripts/ship/ship_vfx.gd`
- Test: `tests/test_ship_vfx.gd` (extend `run_async`)

**Interfaces:**
- Consumes: `ship.engine.destroyed`, `WeaponMount.destroyed` (Task 1/3/4), `ship.weapon_mounts` (populated by `Ship._ready()` one frame after `ShipVfx._ready()` — see existing comment pattern in `tests/test_ship.gd`).
- Produces: `ShipVfx` spawns an explosion at a destroyed engine's or weapon mount's position, and the engine trail stops permanently once the engine is destroyed.

- [ ] **Step 1: Write the failing test**

In `tests/test_ship_vfx.gd`, append a new case to `run_async`, right before `return failures`:

```gdscript
	await _check_engine_and_mount_destruction(tree, failures)

	return failures

static func _check_engine_and_mount_destruction(tree: SceneTree, failures: Array[String]) -> void:
	var ship: Ship = ShipScene.instantiate()
	tree.root.add_child(ship)
	await tree.process_frame
	await tree.process_frame  # let ShipVfx's deferred weapon-mount wiring run

	var vfx: ShipVfx = ship.get_node("VFX")
	var explosion_script: Script = preload("res://scripts/vfx/explosion.gd")

	ship.velocity = Vector2(50, 0)
	vfx._physics_process(0.016)
	var engine_trail: CPUParticles2D = vfx.get_node("EngineTrail")
	if not engine_trail.emitting:
		failures.append("ShipVfx: expected EngineTrail emitting while moving, before engine destruction")

	var explosions_before := tree.root.get_children().filter(func(c): return c.get_script() == explosion_script).size()
	ship.engine.apply_damage(ship.engine.max_hp)
	var explosions_after: Array = tree.root.get_children().filter(func(c): return c.get_script() == explosion_script)
	if explosions_after.size() != explosions_before + 1:
		failures.append("ShipVfx: expected one new explosion when the engine is destroyed, got %d new" % (explosions_after.size() - explosions_before))

	vfx._physics_process(0.016)
	if engine_trail.emitting:
		failures.append("ShipVfx: expected EngineTrail to stop permanently once the engine is destroyed")

	var mount_explosions_before := tree.root.get_children().filter(func(c): return c.get_script() == explosion_script).size()
	ship.weapon_mounts[0].apply_damage(ship.weapon_mounts[0].max_hp)
	var mount_explosions_after: Array = tree.root.get_children().filter(func(c): return c.get_script() == explosion_script)
	if mount_explosions_after.size() != mount_explosions_before + 1:
		failures.append("ShipVfx: expected one new explosion when a weapon mount is destroyed, got %d new" % (mount_explosions_after.size() - mount_explosions_before))

	for e in mount_explosions_after:
		if is_instance_valid(e):
			e.queue_free()
	if is_instance_valid(ship) and not ship.is_queued_for_deletion():
		ship.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — no explosion spawned on engine/mount destruction.

- [ ] **Step 3: Implement**

```gdscript
# scripts/ship/ship_vfx.gd
class_name ShipVfx
extends Node2D

@export var flash_color: Color = Color(1, 0.3, 0.3, 1)
@export var flash_duration: float = 0.12
@export var low_hp_threshold: float = 0.25

const ENGINE_TRAIL_SPEED_THRESHOLD := 5.0
const ExplosionScene = preload("res://scenes/vfx/explosion.tscn")

@onready var _visual: CanvasItem = (
	get_parent().get_node_or_null("Sprite2D") as CanvasItem
	if get_parent().has_node("Sprite2D")
	else get_parent().get_node("Polygon2D") as CanvasItem
)
@onready var _hull: Hull = get_parent().get_node("Hull")
@onready var _engine: ShipEngine = get_parent().get_node("Engine")
@onready var _hit_spark: CPUParticles2D = $HitSpark
@onready var _smoke_trail: CPUParticles2D = $SmokeTrail
@onready var _engine_trail: CPUParticles2D = $EngineTrail
@onready var _body: CharacterBody2D = get_parent()

var _flash_tween: Tween
var _engine_disabled := false

func _ready() -> void:
	_hull.damaged.connect(_on_hull_damaged)
	_hull.destroyed.connect(_on_hull_destroyed)
	_engine.destroyed.connect(_on_engine_destroyed)
	call_deferred("_wire_weapon_mount_signals")

func _wire_weapon_mount_signals() -> void:
	for mount in _body.weapon_mounts:
		mount.destroyed.connect(_on_weapon_mount_destroyed.bind(mount))

func _physics_process(_delta: float) -> void:
	_engine_trail.emitting = not _engine_disabled and _body.velocity.length() > ENGINE_TRAIL_SPEED_THRESHOLD

func _on_hull_damaged(_amount: float, remaining: float) -> void:
	_flash()
	_hit_spark.restart()
	var hp_ratio: float = remaining / _hull.max_hp if _hull.max_hp > 0.0 else 0.0
	_smoke_trail.emitting = should_emit_smoke(hp_ratio, low_hp_threshold)

func _flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_visual.modulate = flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_visual, "modulate", Color.WHITE, flash_duration)

func _on_hull_destroyed() -> void:
	_spawn_explosion_at(get_parent().global_position)

func _on_engine_destroyed() -> void:
	_engine_disabled = true
	_engine_trail.emitting = false
	_spawn_explosion_at(_engine.global_position)

func _on_weapon_mount_destroyed(mount: WeaponMount) -> void:
	_spawn_explosion_at(mount.global_position)

func _spawn_explosion_at(pos: Vector2) -> void:
	var ship_node := get_parent()
	var explosion: Node2D = ExplosionScene.instantiate()
	ship_node.get_parent().add_child(explosion)
	explosion.global_position = pos

static func should_emit_smoke(hp_ratio: float, threshold: float) -> bool:
	return hp_ratio <= threshold
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/ship_vfx.gd tests/test_ship_vfx.gd
git commit -m "Spawn explosions and silence the trail when engine/weapon mounts are destroyed"
```

---

### Task 11: VFX — shield glow dim and blink

**Files:**
- Modify: `scripts/ship/ship_vfx.gd`
- Test: `tests/test_ship_vfx.gd` (extend)

**Interfaces:**
- Consumes: `Shield.health_fraction()`, `Shield.depleted`, `Shield.restored` (Task 6), the `ShieldGlow` node added in Task 9.
- Produces: `ShieldGlow.modulate.a` tracks shield health every physics frame; flickers to 0 on `depleted` and back up on `restored`.

- [ ] **Step 1: Write the failing test**

Append to `run_async` in `tests/test_ship_vfx.gd`, before the final `return failures`:

```gdscript
	await _check_shield_glow(tree, failures)

	return failures

static func _check_shield_glow(tree: SceneTree, failures: Array[String]) -> void:
	var ship: Ship = ShipScene.instantiate()
	tree.root.add_child(ship)
	await tree.process_frame

	var vfx: ShipVfx = ship.get_node("VFX")
	var glow: Polygon2D = ship.get_node("ShieldGlow")

	ship.shield.current_shield = ship.shield.max_shield
	vfx._physics_process(0.016)
	if not is_equal_approx(glow.modulate.a, ShipVfx.SHIELD_GLOW_BASE_ALPHA):
		failures.append("ShipVfx: expected full glow alpha at full shield, got %s" % glow.modulate.a)

	ship.shield.current_shield = ship.shield.max_shield * 0.5
	vfx._physics_process(0.016)
	if not is_equal_approx(glow.modulate.a, ShipVfx.SHIELD_GLOW_BASE_ALPHA * 0.5):
		failures.append("ShipVfx: expected half glow alpha at half shield, got %s" % glow.modulate.a)

	ship.shield.absorb(ship.shield.current_shield)
	if not is_equal_approx(glow.modulate.a, 1.0):
		failures.append("ShipVfx: expected the glow to flash to full alpha the instant the shield depletes, got %s" % glow.modulate.a)

	ship.shield.current_shield = 0.0
	ship.shield._physics_process(1.0)
	if not is_equal_approx(glow.modulate.a, 0.0):
		failures.append("ShipVfx: expected the glow to flash to 0 alpha the instant the shield is restored, got %s" % glow.modulate.a)

	if is_instance_valid(ship) and not ship.is_queued_for_deletion():
		ship.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `SHIELD_GLOW_BASE_ALPHA` doesn't exist / `ShieldGlow` node not resolved.

- [ ] **Step 3: Implement**

Add to `scripts/ship/ship_vfx.gd` (alongside the other `const`s):

```gdscript
const SHIELD_GLOW_BASE_ALPHA := 0.35
```

Add an `@onready` resolution alongside `_hull`:

```gdscript
@onready var _shield: Shield = get_parent().get_node("Shield")
@onready var _shield_glow: Polygon2D = get_parent().get_node("ShieldGlow")
```

Add to `_ready()`, alongside the other signal connections:

```gdscript
	_shield.depleted.connect(_on_shield_depleted)
	_shield.restored.connect(_on_shield_restored)
```

Add a tween-tracking var next to `_flash_tween`:

```gdscript
var _shield_flicker_tween: Tween
```

Update `_physics_process` to drive the glow outside of an active flicker:

```gdscript
func _physics_process(_delta: float) -> void:
	_engine_trail.emitting = not _engine_disabled and _body.velocity.length() > ENGINE_TRAIL_SPEED_THRESHOLD
	if _shield_flicker_tween == null or not _shield_flicker_tween.is_running():
		_shield_glow.modulate.a = SHIELD_GLOW_BASE_ALPHA * _shield.health_fraction()
```

Add the two handlers:

```gdscript
func _on_shield_depleted() -> void:
	if _shield_flicker_tween:
		_shield_flicker_tween.kill()
	_shield_glow.modulate.a = 1.0
	_shield_flicker_tween = create_tween()
	_shield_flicker_tween.tween_property(_shield_glow, "modulate:a", 0.0, flash_duration)

func _on_shield_restored() -> void:
	if _shield_flicker_tween:
		_shield_flicker_tween.kill()
	_shield_glow.modulate.a = 0.0
	_shield_flicker_tween = create_tween()
	_shield_flicker_tween.tween_property(_shield_glow, "modulate:a", SHIELD_GLOW_BASE_ALPHA * _shield.health_fraction(), flash_duration)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/ship_vfx.gd tests/test_ship_vfx.gd
git commit -m "Dim and flicker the shield glow with shield health"
```

---

### Task 12: Station repair in `CampaignState`, and remove the free auto-repair

**Files:**
- Modify: `scripts/campaign/campaign_state.gd`
- Modify: `scripts/campaign/home_base.gd`
- Test: `tests/test_campaign_state.gd` (extend)
- Test: `tests/test_home_base.gd` (fix the now-invalid assertion)

**Interfaces:**
- Produces: `CampaignState.REPAIR_COST`, `CampaignState.is_damaged(comp) -> bool` (static), `CampaignState.repair_cost_for(comp) -> float` (static), `CampaignState.repair_ship(comp) -> void` (instance method, deducts `credits`).

- [ ] **Step 1: Write the failing tests**

Append to `run()` in `tests/test_campaign_state.gd`, before the final `return failures`:

```gdscript
	var damaged_comp := {
		"max_hp": 100.0, "current_hp": 50.0, "max_shield": 50.0, "current_shield": 50.0,
		"engine_max_hp": 20.0, "engine_current_hp": 20.0,
		"weapon_mount_max_hp": [10.0], "weapon_mount_current_hp": [10.0],
	}
	if not CampaignState.is_damaged(damaged_comp):
		failures.append("is_damaged: expected true when hull is below max")
	if CampaignState.repair_cost_for(damaged_comp) != CampaignState.REPAIR_COST:
		failures.append("repair_cost_for: expected REPAIR_COST for a damaged ship, got %s" % CampaignState.repair_cost_for(damaged_comp))

	var full_comp := {
		"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0,
		"engine_max_hp": 20.0, "engine_current_hp": 20.0,
		"weapon_mount_max_hp": [10.0], "weapon_mount_current_hp": [10.0],
	}
	if CampaignState.is_damaged(full_comp):
		failures.append("is_damaged: expected false for a fully healed ship")
	if CampaignState.repair_cost_for(full_comp) != 0.0:
		failures.append("repair_cost_for: expected 0.0 for a fully healed ship")

	var engine_damaged := {
		"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0,
		"engine_max_hp": 20.0, "engine_current_hp": 5.0,
		"weapon_mount_max_hp": [], "weapon_mount_current_hp": [],
	}
	if not CampaignState.is_damaged(engine_damaged):
		failures.append("is_damaged: expected true when only the engine is damaged")

	var mount_damaged := {
		"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0,
		"engine_max_hp": 20.0, "engine_current_hp": 20.0,
		"weapon_mount_max_hp": [10.0, 10.0], "weapon_mount_current_hp": [10.0, 0.0],
	}
	if not CampaignState.is_damaged(mount_damaged):
		failures.append("is_damaged: expected true when a weapon mount is damaged")

	var legacy_comp := {"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}
	if CampaignState.is_damaged(legacy_comp):
		failures.append("is_damaged: expected false for a legacy composition dict with no engine/mount fields")

	var repair_state := CampaignState.new()
	repair_state.credits = 200.0
	var to_repair := {
		"max_hp": 100.0, "current_hp": 10.0, "max_shield": 50.0, "current_shield": 0.0,
		"engine_max_hp": 20.0, "engine_current_hp": 2.0,
		"weapon_mount_max_hp": [10.0], "weapon_mount_current_hp": [1.0],
	}
	repair_state.repair_ship(to_repair)
	if not is_equal_approx(repair_state.credits, 200.0 - CampaignState.REPAIR_COST):
		failures.append("repair_ship: expected credits reduced by REPAIR_COST, got %s" % repair_state.credits)
	if to_repair["current_hp"] != 100.0 or to_repair["current_shield"] != 50.0 or to_repair["engine_current_hp"] != 20.0 or to_repair["weapon_mount_current_hp"][0] != 10.0:
		failures.append("repair_ship: expected every field restored to max, got %s" % to_repair)
```

In `tests/test_home_base.gd`, replace the free-repair assertion:

```gdscript
	if fleet.ship_compositions[0]["current_hp"] != 100.0 or fleet.ship_compositions[0]["current_shield"] != 50.0:
		failures.append("HomeBase: expected fleet repaired to full on docking, got %s" % fleet.ship_compositions[0])
```

with:

```gdscript
	if fleet.ship_compositions[0]["current_hp"] != 10.0 or fleet.ship_compositions[0]["current_shield"] != 0.0:
		failures.append("HomeBase: expected docking to NOT auto-repair (repair is now a paid station action), got %s" % fleet.ship_compositions[0])
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `is_damaged`/`repair_cost_for`/`repair_ship`/`REPAIR_COST` don't exist yet, and `test_home_base.gd` still sees the fleet auto-repaired.

- [ ] **Step 3: Implement `CampaignState` additions**

Add near the top of `scripts/campaign/campaign_state.gd`, alongside the other `const`s:

```gdscript
const REPAIR_COST := 75.0
```

Add these functions anywhere after `reset()`:

```gdscript
static func is_damaged(comp: Dictionary) -> bool:
	if comp["current_hp"] < comp["max_hp"] or comp["current_shield"] < comp["max_shield"]:
		return true
	var engine_max: float = comp.get("engine_max_hp", 0.0)
	if engine_max > 0.0 and comp.get("engine_current_hp", engine_max) < engine_max:
		return true
	var mount_max: Array = comp.get("weapon_mount_max_hp", [])
	var mount_cur: Array = comp.get("weapon_mount_current_hp", [])
	for i in mount_max.size():
		if i < mount_cur.size() and mount_cur[i] < mount_max[i]:
			return true
	return false

static func repair_cost_for(comp: Dictionary) -> float:
	return REPAIR_COST if is_damaged(comp) else 0.0

func repair_ship(comp: Dictionary) -> void:
	credits -= REPAIR_COST
	comp["current_hp"] = comp["max_hp"]
	comp["current_shield"] = comp["max_shield"]
	if comp.has("engine_max_hp"):
		comp["engine_current_hp"] = comp["engine_max_hp"]
	if comp.has("weapon_mount_max_hp"):
		comp["weapon_mount_current_hp"] = (comp["weapon_mount_max_hp"] as Array).duplicate()
```

- [ ] **Step 4: Remove the free auto-repair**

In `scripts/campaign/home_base.gd`:

```gdscript
# scripts/campaign/home_base.gd
class_name HomeBase
extends Area2D

signal player_docked

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	if area is CampaignFleetIcon and area.behavior_type == CampaignFleetIcon.BehaviorType.PLAYER and area.fleet != null:
		player_docked.emit()
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 6: Commit**

```bash
git add scripts/campaign/campaign_state.gd scripts/campaign/home_base.gd tests/test_campaign_state.gd tests/test_home_base.gd
git commit -m "Add paid per-ship station repair and remove the free auto-repair on docking"
```

---

### Task 13: Repair UI in `TradePanel`

**Files:**
- Modify: `scenes/campaign/trade_panel.tscn`
- Modify: `scripts/campaign/trade_panel.gd`
- Test: `tests/test_trade_panel.gd` (extend)

**Interfaces:**
- Consumes: `CampaignState.repair_cost_for`/`is_damaged`/`repair_ship`/`REPAIR_COST` (Task 12).
- Produces: a repair row per damaged ship with a per-ship "Repair" button, and a "Repair All" button, both wired into the existing `refresh()` cycle.

- [ ] **Step 1: Write the failing test**

Append to `run_async` in `tests/test_trade_panel.gd`, before `campaign_state.reset()` / `panel.queue_free()` at the end:

```gdscript
	fleet.ship_compositions = [
		{
			"max_hp": 100.0, "current_hp": 40.0, "max_shield": 50.0, "current_shield": 50.0,
			"engine_max_hp": 20.0, "engine_current_hp": 20.0,
			"weapon_mount_max_hp": [], "weapon_mount_current_hp": [],
		},
		{
			"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0,
			"engine_max_hp": 20.0, "engine_current_hp": 20.0,
			"weapon_mount_max_hp": [], "weapon_mount_current_hp": [],
		},
	]
	campaign_state.credits = 1000.0
	panel.refresh()

	if panel.repair_container.get_child_count() != 1:
		failures.append("TradePanel: expected exactly 1 repair row for 1 damaged ship, got %d" % panel.repair_container.get_child_count())
	if panel.repair_all_button.disabled:
		failures.append("TradePanel: expected Repair All enabled when credits cover the damaged ship")

	var repair_row: HBoxContainer = panel.repair_container.get_child(0)
	var repair_button: Button = repair_row.get_child(1)
	var credits_before_repair: float = campaign_state.credits
	repair_button.pressed.emit()
	if not is_equal_approx(campaign_state.credits, credits_before_repair - CampaignState.REPAIR_COST):
		failures.append("TradePanel: expected pressing Repair to deduct REPAIR_COST, got credits=%s" % campaign_state.credits)
	if fleet.ship_compositions[0]["current_hp"] != 100.0:
		failures.append("TradePanel: expected pressing Repair to fully heal the ship")
	if panel.repair_container.get_child_count() != 0:
		failures.append("TradePanel: expected 0 repair rows once no ship is damaged")

	fleet.ship_compositions[0]["current_hp"] = 1.0
	fleet.ship_compositions[1]["current_hp"] = 1.0
	campaign_state.credits = 10.0
	panel.refresh()
	if not panel.repair_all_button.disabled:
		failures.append("TradePanel: expected Repair All disabled when credits can't cover every damaged ship")

	campaign_state.credits = 1000.0
	panel.refresh()
	panel.repair_all_button.pressed.emit()
	if fleet.ship_compositions[0]["current_hp"] != 100.0 or fleet.ship_compositions[1]["current_hp"] != 100.0:
		failures.append("TradePanel: expected Repair All to heal every damaged ship")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `Invalid get index 'repair_container'`.

- [ ] **Step 3: Edit `scenes/campaign/trade_panel.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/campaign/trade_panel.gd" id="1"]

[node name="TradePanel" type="Control"]
offset_left = 200.0
offset_top = 100.0
offset_right = 700.0
offset_bottom = 460.0
mouse_filter = 2
script = ExtResource("1")

[node name="Background" type="Panel" parent="."]
offset_right = 500.0
offset_bottom = 420.0
mouse_filter = 2

[node name="CreditsLabel" type="Label" parent="."]
offset_left = 14.0
offset_top = 14.0
offset_right = 314.0
offset_bottom = 44.0

[node name="RowsContainer" type="VBoxContainer" parent="."]
offset_left = 14.0
offset_top = 54.0
offset_right = 486.0
offset_bottom = 220.0

[node name="RepairContainer" type="VBoxContainer" parent="."]
offset_left = 14.0
offset_top = 226.0
offset_right = 486.0
offset_bottom = 340.0

[node name="RepairAllButton" type="Button" parent="."]
offset_left = 14.0
offset_top = 346.0
offset_right = 164.0
offset_bottom = 376.0
text = "Repair All"

[node name="CloseButton" type="Button" parent="."]
offset_left = 14.0
offset_top = 382.0
offset_right = 114.0
offset_bottom = 412.0
text = "Close"
```

- [ ] **Step 4: Implement `trade_panel.gd` changes**

```gdscript
# scripts/campaign/trade_panel.gd
class_name TradePanel
extends Control

var _docked_base_economy: BaseEconomy
var _player_fleet: CampaignFleet
var _rows: Dictionary = {}

@onready var rows_container: VBoxContainer = $RowsContainer
@onready var repair_container: VBoxContainer = $RepairContainer
@onready var repair_all_button: Button = $RepairAllButton
@onready var credits_label: Label = $CreditsLabel
@onready var close_button: Button = $CloseButton

func _ready() -> void:
	close_button.pressed.connect(close)
	repair_all_button.pressed.connect(_on_repair_all_pressed)
	visible = false
	_build_rows()

func open_for(base_economy: BaseEconomy, fleet: CampaignFleet) -> void:
	_docked_base_economy = base_economy
	_player_fleet = fleet
	visible = true
	refresh()

func close() -> void:
	visible = false
	_docked_base_economy = null
	_player_fleet = null

func refresh() -> void:
	if _docked_base_economy == null or _player_fleet == null:
		return
	credits_label.text = "Credits: %d" % CampaignState.credits
	for commodity in _rows.keys():
		var row: Dictionary = _rows[commodity]
		var stock: float = _docked_base_economy.stock.get(commodity, 0.0)
		var buy_price := _docked_base_economy.price_for(commodity)
		var sell_price := _docked_base_economy.sell_price_for(commodity)
		var held: float = _player_fleet.cargo.get(commodity, 0.0)
		row["label"].text = "%s  stock:%.0f  buy:%.0f  sell:%.0f  held:%.0f" % [Commodity.NAMES[commodity], stock, buy_price, sell_price, held]
		row["buy_button"].disabled = CampaignState.credits < buy_price or stock < 1.0 or _player_fleet.cargo_total() + 1.0 > _player_fleet.cargo_capacity()
		row["sell_button"].disabled = held < 1.0
	_refresh_repair_section()

func _refresh_repair_section() -> void:
	for child in repair_container.get_children():
		child.queue_free()
	var total_cost := 0.0
	for i in _player_fleet.ship_compositions.size():
		var comp: Dictionary = _player_fleet.ship_compositions[i]
		var cost := CampaignState.repair_cost_for(comp)
		if cost <= 0.0:
			continue
		total_cost += cost
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "Ship %d  repair cost: %d" % [i + 1, cost]
		var button := Button.new()
		button.text = "Repair"
		button.disabled = CampaignState.credits < cost
		button.pressed.connect(_on_repair_pressed.bind(i))
		row.add_child(label)
		row.add_child(button)
		repair_container.add_child(row)
	repair_all_button.disabled = total_cost <= 0.0 or CampaignState.credits < total_cost

func _on_repair_pressed(index: int) -> void:
	CampaignState.repair_ship(_player_fleet.ship_compositions[index])
	refresh()

func _on_repair_all_pressed() -> void:
	for comp in _player_fleet.ship_compositions:
		if CampaignState.repair_cost_for(comp) > 0.0 and CampaignState.credits >= CampaignState.REPAIR_COST:
			CampaignState.repair_ship(comp)
	refresh()

func _build_rows() -> void:
	if not _rows.is_empty():
		return
	for commodity in Commodity.Type.values():
		var row_box := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = load(Commodity.ICON_TEXTURES[commodity])
		icon.custom_minimum_size = Vector2(18, 18)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		var label := Label.new()
		var buy_button := Button.new()
		buy_button.text = "Buy"
		buy_button.pressed.connect(_on_buy_pressed.bind(commodity))
		var sell_button := Button.new()
		sell_button.text = "Sell"
		sell_button.pressed.connect(_on_sell_pressed.bind(commodity))
		row_box.add_child(icon)
		row_box.add_child(label)
		row_box.add_child(buy_button)
		row_box.add_child(sell_button)
		rows_container.add_child(row_box)
		_rows[commodity] = {"icon": icon, "label": label, "buy_button": buy_button, "sell_button": sell_button}

func _on_buy_pressed(commodity: int) -> void:
	CampaignState.buy(_docked_base_economy, commodity, _player_fleet)
	refresh()

func _on_sell_pressed(commodity: int) -> void:
	CampaignState.sell(_docked_base_economy, commodity, _player_fleet)
	refresh()
```

- [ ] **Step 5: Run test to verify it passes**

Run: `godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 6: Commit**

```bash
git add scenes/campaign/trade_panel.tscn scripts/campaign/trade_panel.gd tests/test_trade_panel.gd
git commit -m "Add per-ship and Repair All station repair UI to the trade panel"
```

---

## Manual verification (not covered by the headless suite)

After Task 13, launch the game (`godot.windows.opt.tools.64.exe --path .`) and confirm:
- A corvette's weapon mount visibly explodes and stops firing when focused fire lands near its nose; the ship keeps fighting on hull/shield alone.
- A capital ship losing its engine drifts to a stop and no longer accelerates, but can still rotate.
- The shield glow dims smoothly as shield damage accumulates and blinks fully out the instant it depletes (and back in once it regenerates).
- Docking at the home base no longer auto-heals; opening the trade panel shows per-ship repair rows and a working "Repair All".
