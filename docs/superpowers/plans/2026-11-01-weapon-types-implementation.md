# Weapon Types Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing `Weapon`/`WeaponMount`/`Hull`/`Shield` architecture with the damage model (shield/hull multipliers, pierce, component damage, fire arcs, rarity) from the design spec, and populate it with the 14 Kinetic/Missile/Beam/Point-Defense weapon variants. Drone is out of scope (separate subsystem, separate future plan).

**Architecture:** Additive fields on the `Weapon` resource plus a new `ComponentPool` node class for engine/weapons subsystem HP. `Ship.receive_weapon_damage(weapon)` becomes the new damage-resolution entry point (shield_mult → absorb → hull_mult, pierce bypass, optional component damage); the old `receive_damage(float)` stays untouched for any caller that doesn't have a `Weapon` reference. `WeaponMount` gains a fire-arc check and multi-submissile spawning. New weapon variants are plain `.tres` resource files reusing the existing `projectile.tscn`.

**Tech Stack:** Godot 4.7, GDScript. Tests use this repo's existing custom runner convention (static `run() -> Array[String]` / `run_async(tree) -> Array[String]`, registered in `tests/run_tests.gd`), not GUT.

## Global Constraints

- Spec reference: `docs/superpowers/specs/2026-11-01-weapon-types-design.md`.
- Every new `Weapon` field must default to a value that preserves current behavior for existing content (`resources/weapons/kinetic_cannon.tres`) and existing tests — no field may be required.
- No ammo/magazine system (cooldown-only, per spec).
- No component-specific targeting (random-weighted pick between the two pools, per spec).
- No Drone work in this plan.
- Follow existing code style: tabs for indentation, `class_name` + `extends` header, static pure-logic helpers where the codebase already does this (e.g. `Ship.nearest_in_range`).

---

### Task 1: Extend the Weapon resource with the new damage-model fields

**Files:**
- Modify: `scripts/weapons/weapon.gd`
- Test: `tests/test_weapon.gd` (create)
- Modify: `tests/run_tests.gd` (register new test)

**Interfaces:**
- Produces: `Weapon` gains `shield_mult: float`, `hull_mult: float`, `pierce_pct: float`, `component_damage: float`, `mount_type: Weapon.MountType` (enum `FIXED`/`TURRET`), `fire_arc_degrees: float`, `rarity: Weapon.Rarity` (enum `COMMON`/`UNCOMMON`/`RARE`/`EPIC`), `submissile_count: int`, `projectile_speed: float`. All later tasks reference these exact names.

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

const Weapon = preload("res://scripts/weapons/weapon.gd")

static func run() -> Array[String]:
	var failures: Array[String] = []
	var weapon := Weapon.new()

	if not is_equal_approx(weapon.shield_mult, 1.0):
		failures.append("default shield_mult: expected 1.0, got %s" % weapon.shield_mult)
	if not is_equal_approx(weapon.hull_mult, 1.0):
		failures.append("default hull_mult: expected 1.0, got %s" % weapon.hull_mult)
	if not is_equal_approx(weapon.pierce_pct, 0.0):
		failures.append("default pierce_pct: expected 0.0, got %s" % weapon.pierce_pct)
	if not is_equal_approx(weapon.component_damage, 0.0):
		failures.append("default component_damage: expected 0.0, got %s" % weapon.component_damage)
	if weapon.mount_type != Weapon.MountType.TURRET:
		failures.append("default mount_type: expected TURRET, got %s" % weapon.mount_type)
	if not is_equal_approx(weapon.fire_arc_degrees, 360.0):
		failures.append("default fire_arc_degrees: expected 360.0, got %s" % weapon.fire_arc_degrees)
	if weapon.rarity != Weapon.Rarity.COMMON:
		failures.append("default rarity: expected COMMON, got %s" % weapon.rarity)
	if weapon.submissile_count != 1:
		failures.append("default submissile_count: expected 1, got %s" % weapon.submissile_count)
	if not is_equal_approx(weapon.projectile_speed, 0.0):
		failures.append("default projectile_speed: expected 0.0, got %s" % weapon.projectile_speed)

	weapon.free()
	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/run_tests.gd` (will fail to compile/run because `tests/test_weapon.gd` doesn't exist yet and isn't registered — confirm by first registering it in `tests/run_tests.gd`'s `test_scripts` array, inserted right after the `test_hull.gd` / `test_shield.gd` entries, then running).
Expected: FAIL — "Invalid get index 'shield_mult'" or similar, since the fields don't exist on `Weapon` yet.

- [ ] **Step 3: Write minimal implementation**

Replace the full contents of `scripts/weapons/weapon.gd` with:

```gdscript
class_name Weapon
extends Resource

enum MountType { FIXED, TURRET }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC }

@export var weapon_name: String = "Kinetic Cannon"
@export var damage: float = 10.0
@export var fire_rate: float = 1.0
@export var weapon_range: float = 300.0
@export var projectile_scene: PackedScene

@export var shield_mult: float = 1.0
@export var hull_mult: float = 1.0
@export var pierce_pct: float = 0.0
@export var component_damage: float = 0.0
@export var mount_type: MountType = MountType.TURRET
@export var fire_arc_degrees: float = 360.0
@export var rarity: Rarity = Rarity.COMMON
@export var submissile_count: int = 1
@export var projectile_speed: float = 0.0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script tests/run_tests.gd`
Expected: PASS — no `FAIL [res://tests/test_weapon.gd]` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/weapons/weapon.gd tests/test_weapon.gd tests/run_tests.gd
git commit -m "Add damage-model fields to Weapon resource"
```

---

### Task 2: Create ComponentPool

**Files:**
- Create: `scripts/ship/component_pool.gd`
- Test: `tests/test_component_pool.gd` (create)
- Modify: `tests/run_tests.gd` (register new test)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `class_name ComponentPool extends Node` with `@export var max_hp: float`, `@export var disable_duration: float`, `var current_hp: float`, signals `disabled`, `restored`, methods `apply_damage(amount: float) -> void`, `is_disabled() -> bool`. Task 3 depends on exactly these names.

- [ ] **Step 1: Write the failing test**

```gdscript
extends RefCounted

const ComponentPool = preload("res://scripts/ship/component_pool.gd")

class CallbackTracker:
	var disabled_fired := false
	var restored_fired := false
	func on_disabled() -> void:
		disabled_fired = true
	func on_restored() -> void:
		restored_fired = true

static func run() -> Array[String]:
	var failures: Array[String] = []
	var pool := ComponentPool.new()
	pool.max_hp = 30.0
	pool.disable_duration = 5.0
	pool.current_hp = 30.0

	var tracker := CallbackTracker.new()
	pool.disabled.connect(tracker.on_disabled)
	pool.restored.connect(tracker.on_restored)

	pool.apply_damage(10.0)
	if not is_equal_approx(pool.current_hp, 20.0):
		failures.append("apply_damage: expected 20.0 remaining, got %s" % pool.current_hp)
	if pool.is_disabled():
		failures.append("apply_damage: expected not disabled yet")

	pool.apply_damage(1000.0)
	if not is_equal_approx(pool.current_hp, 0.0):
		failures.append("apply_damage: expected 0.0 after overkill, got %s" % pool.current_hp)
	if not pool.is_disabled():
		failures.append("apply_damage: expected is_disabled() true at 0 hp")
	if not tracker.disabled_fired:
		failures.append("apply_damage: expected disabled signal to fire at 0 hp")

	# Damage while disabled is a no-op.
	pool.apply_damage(5.0)
	if not is_equal_approx(pool.current_hp, 0.0):
		failures.append("apply_damage: expected no-op while disabled, got current_hp=%s" % pool.current_hp)

	# Ticking past disable_duration restores the pool.
	pool._physics_process(5.0)
	if pool.is_disabled():
		failures.append("_physics_process: expected is_disabled() false after disable_duration elapses")
	if not is_equal_approx(pool.current_hp, 30.0):
		failures.append("_physics_process: expected current_hp restored to max_hp, got %s" % pool.current_hp)
	if not tracker.restored_fired:
		failures.append("_physics_process: expected restored signal to fire")

	pool.free()
	return failures
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/run_tests.gd` (after adding `preload("res://tests/test_component_pool.gd")` to `test_scripts` in `tests/run_tests.gd`, placed after the `test_weapon.gd` entry from Task 1).
Expected: FAIL — script `scripts/ship/component_pool.gd` doesn't exist.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/ship/component_pool.gd`:

```gdscript
class_name ComponentPool
extends Node

signal disabled
signal restored

@export var max_hp: float = 30.0
@export var disable_duration: float = 5.0
var current_hp: float
var disable_timer: float = 0.0

func _ready() -> void:
	current_hp = max_hp

func _physics_process(delta: float) -> void:
	if disable_timer > 0.0:
		disable_timer = max(0.0, disable_timer - delta)
		if disable_timer <= 0.0:
			current_hp = max_hp
			restored.emit()

func apply_damage(amount: float) -> void:
	if is_disabled():
		return
	current_hp = max(0.0, current_hp - amount)
	if current_hp <= 0.0:
		disable_timer = disable_duration
		disabled.emit()

func is_disabled() -> bool:
	return disable_timer > 0.0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script tests/run_tests.gd`
Expected: PASS — no `FAIL [res://tests/test_component_pool.gd]` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/component_pool.gd tests/test_component_pool.gd tests/run_tests.gd
git commit -m "Add ComponentPool for engine/weapons subsystem disables"
```

---

### Task 3: Wire ComponentPool into Ship and add receive_weapon_damage

**Files:**
- Modify: `scripts/ship/ship.gd`
- Test: `tests/test_ship.gd` (modify — extend `_check_ship_logic`, add a new static check function)

**Interfaces:**
- Consumes: `Weapon` fields from Task 1 (`shield_mult`, `hull_mult`, `pierce_pct`, `component_damage`), `ComponentPool` from Task 2 (`apply_damage`, `is_disabled`).
- Produces: `Ship.engine_component: ComponentPool`, `Ship.weapons_component: ComponentPool` (created in `_ready()`), `Ship.receive_weapon_damage(weapon: Weapon) -> void`, `static Ship.pick_component(components: Array[ComponentPool], roll: float) -> ComponentPool`. Task 5 (Projectile) calls `receive_weapon_damage`.

- [ ] **Step 1: Write the failing test**

Add this new static function to `tests/test_ship.gd`, and call it from `run()`:

```gdscript
static func _check_receive_weapon_damage(failures: Array[String]) -> void:
	# pick_component: deterministic selection by roll, independent of Ship instance.
	var pool_a := ComponentPool.new()
	var pool_b := ComponentPool.new()
	var components: Array[ComponentPool] = [pool_a, pool_b]
	if Ship.pick_component(components, 0.0) != pool_a:
		failures.append("pick_component: expected roll 0.0 to select the first component")
	if Ship.pick_component(components, 0.99) != pool_b:
		failures.append("pick_component: expected roll 0.99 to select the second component")

	# receive_weapon_damage: shield_mult/hull_mult/pierce_pct resolution.
	var ship := Ship.new()
	var hull := Hull.new()
	hull.max_hp = 100.0
	hull.current_hp = 100.0
	var shield := Shield.new()
	shield.max_shield = 20.0
	shield.current_shield = 20.0
	ship.hull = hull
	ship.shield = shield
	ship.engine_component = ComponentPool.new()
	ship.weapons_component = ComponentPool.new()

	# shield_mult 1.4, hull_mult 0.75, no pierce: damage 10 -> effective shield hit 14,
	# fully absorbed (shield has 20), no hull damage.
	var pulse_laser := Weapon.new()
	pulse_laser.damage = 10.0
	pulse_laser.shield_mult = 1.4
	pulse_laser.hull_mult = 0.75
	ship.receive_weapon_damage(pulse_laser)
	if not is_equal_approx(ship.shield.current_shield, 6.0):
		failures.append("receive_weapon_damage: expected shield 20 - 14 = 6.0, got %s" % ship.shield.current_shield)
	if not is_equal_approx(ship.hull.current_hp, 100.0):
		failures.append("receive_weapon_damage: expected hull untouched, got %s" % ship.hull.current_hp)

	# Second hit: effective shield hit 14, only 6 shield left -> overflow_effective 8,
	# raw_unabsorbed = 8 / 1.4, hull_damage = raw_unabsorbed * 0.75.
	ship.receive_weapon_damage(pulse_laser)
	var expected_hull_damage: float = (8.0 / 1.4) * 0.75
	if not is_equal_approx(ship.shield.current_shield, 0.0):
		failures.append("receive_weapon_damage: expected shield depleted to 0.0, got %s" % ship.shield.current_shield)
	if not is_equal_approx(ship.hull.current_hp, 100.0 - expected_hull_damage):
		failures.append("receive_weapon_damage: expected hull %s, got %s" % [100.0 - expected_hull_damage, ship.hull.current_hp])

	# pierce_pct: a railgun with pierce_pct 0.25 against a full shield should still
	# land 25% of its damage * hull_mult directly on hull.
	var railgun_ship := Ship.new()
	var r_hull := Hull.new()
	r_hull.max_hp = 100.0
	r_hull.current_hp = 100.0
	var r_shield := Shield.new()
	r_shield.max_shield = 1000.0
	r_shield.current_shield = 1000.0
	railgun_ship.hull = r_hull
	railgun_ship.shield = r_shield
	railgun_ship.engine_component = ComponentPool.new()
	railgun_ship.weapons_component = ComponentPool.new()
	var railgun := Weapon.new()
	railgun.damage = 40.0
	railgun.shield_mult = 0.5
	railgun.hull_mult = 1.0
	railgun.pierce_pct = 0.25
	railgun_ship.receive_weapon_damage(railgun)
	if not is_equal_approx(r_hull.current_hp, 90.0):
		failures.append("receive_weapon_damage: expected pierce to deal 10.0 hull damage (40*0.25*1.0), got hull=%s" % r_hull.current_hp)

	# component_damage: a nonzero value must reach one of the two component pools.
	var emp_ship := Ship.new()
	var e_hull := Hull.new()
	e_hull.max_hp = 100.0
	e_hull.current_hp = 100.0
	var e_shield := Shield.new()
	e_shield.max_shield = 50.0
	e_shield.current_shield = 50.0
	emp_ship.hull = e_hull
	emp_ship.shield = e_shield
	emp_ship.engine_component = ComponentPool.new()
	emp_ship.engine_component.max_hp = 30.0
	emp_ship.engine_component.current_hp = 30.0
	emp_ship.weapons_component = ComponentPool.new()
	emp_ship.weapons_component.max_hp = 30.0
	emp_ship.weapons_component.current_hp = 30.0
	var emp_missile := Weapon.new()
	emp_missile.damage = 6.0
	emp_missile.component_damage = 15.0
	emp_ship.receive_weapon_damage(emp_missile)
	var total_component_damage: float = (30.0 - emp_ship.engine_component.current_hp) + (30.0 - emp_ship.weapons_component.current_hp)
	if not is_equal_approx(total_component_damage, 15.0):
		failures.append("receive_weapon_damage: expected 15.0 component_damage applied to exactly one pool, got total=%s" % total_component_damage)

	hull.free()
	shield.free()
	ship.engine_component.free()
	ship.weapons_component.free()
	ship.free()
	pool_a.free()
	pool_b.free()
	r_hull.free()
	r_shield.free()
	railgun_ship.engine_component.free()
	railgun_ship.weapons_component.free()
	railgun_ship.free()
	e_hull.free()
	e_shield.free()
	emp_ship.engine_component.free()
	emp_ship.weapons_component.free()
	emp_ship.free()
```

Add `_check_receive_weapon_damage(failures)` to the body of `run()` in `tests/test_ship.gd`, alongside the existing calls.

Also add, near the top of `tests/test_ship.gd` (it already preloads `ShipScene`), nothing further is needed — `Ship`, `Hull`, `Shield`, `Weapon` are already global class names used elsewhere in this file; add one line:

```gdscript
const ComponentPool = preload("res://scripts/ship/component_pool.gd")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/run_tests.gd`
Expected: FAIL — "Invalid call. Nonexistent function 'receive_weapon_damage'" (and `pick_component`, and `engine_component`/`weapons_component` assignment errors).

- [ ] **Step 3: Write minimal implementation**

In `scripts/ship/ship.gd`, add after the existing `@onready` lines:

```gdscript
var engine_component: ComponentPool
var weapons_component: ComponentPool
```

In `_ready()`, add before the `for child in get_children():` loop:

```gdscript
	engine_component = ComponentPool.new()
	add_child(engine_component)
	weapons_component = ComponentPool.new()
	add_child(weapons_component)
```

Add these two new functions (near `receive_damage`):

```gdscript
func receive_weapon_damage(weapon: Weapon) -> void:
	var pierce_damage: float = weapon.damage * weapon.pierce_pct
	var absorbable_damage: float = weapon.damage - pierce_damage
	var effective_shield_hit: float = absorbable_damage * weapon.shield_mult
	var overflow_effective := shield.absorb(effective_shield_hit)
	var raw_unabsorbed: float = overflow_effective / weapon.shield_mult if weapon.shield_mult > 0.0 else overflow_effective
	var hull_damage: float = (raw_unabsorbed + pierce_damage) * weapon.hull_mult
	hull.apply_damage(hull_damage)
	if weapon.component_damage > 0.0:
		var components: Array[ComponentPool] = [engine_component, weapons_component]
		Ship.pick_component(components, randf()).apply_damage(weapon.component_damage)

static func pick_component(components: Array[ComponentPool], roll: float) -> ComponentPool:
	var index := int(roll * components.size())
	index = clamp(index, 0, components.size() - 1)
	return components[index]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script tests/run_tests.gd`
Expected: PASS — no `FAIL [res://tests/test_ship.gd]` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/ship.gd tests/test_ship.gd
git commit -m "Add Ship.receive_weapon_damage with shield/hull/pierce/component resolution"
```

---

### Task 4: WeaponMount fire-arc gating

**Files:**
- Modify: `scripts/weapons/weapon_mount.gd`
- Test: `tests/test_weapon_mount.gd` (modify — extend `run()`)

**Interfaces:**
- Consumes: `Weapon.fire_arc_degrees` from Task 1.
- Produces: `WeaponMount._within_arc(target: Node2D) -> bool` (private helper, but tests may call it directly per this codebase's convention of testing underscore-prefixed methods).

- [ ] **Step 1: Write the failing test**

Append to `run()` in `tests/test_weapon_mount.gd`, just before `far_target.free()`:

```gdscript
	# Fire-arc gating: a narrow-arc (e.g. Fixed) weapon mounted facing +X (rotation 0)
	# should refuse to fire at a target far off to the side, and accept one dead ahead.
	var narrow_weapon := Weapon.new()
	narrow_weapon.weapon_name = "Railgun"
	narrow_weapon.damage = 35.0
	narrow_weapon.fire_rate = 1.0
	narrow_weapon.weapon_range = 500.0
	narrow_weapon.fire_arc_degrees = 10.0

	var narrow_mount := WeaponMount.new()
	narrow_mount.weapon = narrow_weapon
	narrow_mount.global_position = Vector2.ZERO
	narrow_mount.rotation = 0.0

	var ahead_target := Node2D.new()
	ahead_target.global_position = Vector2(200.0, 0.0)
	if not narrow_mount._within_arc(ahead_target):
		failures.append("_within_arc: expected target dead ahead to be within a 10-degree arc")

	var side_target := Node2D.new()
	side_target.global_position = Vector2(0.0, 200.0)
	if narrow_mount._within_arc(side_target):
		failures.append("_within_arc: expected target 90 degrees off-axis to be outside a 10-degree arc")

	# Default 360-degree arc (e.g. the existing Kinetic Cannon) must accept any angle.
	if not mount._within_arc(side_target):
		failures.append("_within_arc: expected default 360-degree arc to accept any target angle")

	ahead_target.free()
	side_target.free()
	narrow_mount.free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/run_tests.gd`
Expected: FAIL — "Invalid call. Nonexistent function '_within_arc'".

- [ ] **Step 3: Write minimal implementation**

In `scripts/weapons/weapon_mount.gd`, add this function and call it from `try_fire`:

```gdscript
func _within_arc(target: Node2D) -> bool:
	if weapon.fire_arc_degrees >= 360.0:
		return true
	var to_target_angle := (target.global_position - global_position).angle()
	var diff := wrapf(to_target_angle - global_rotation, -PI, PI)
	return abs(diff) <= deg_to_rad(weapon.fire_arc_degrees) * 0.5
```

Update `try_fire` to add the arc check alongside the existing range check:

```gdscript
func try_fire(target: Node2D) -> bool:
	if not can_fire() or target == null or not is_instance_valid(target):
		return false
	if global_position.distance_to(target.global_position) > weapon.weapon_range:
		return false
	if not _within_arc(target):
		return false
	_spawn_projectile(target)
	cooldown_remaining = 1.0 / weapon.fire_rate
	return true
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script tests/run_tests.gd`
Expected: PASS — no `FAIL [res://tests/test_weapon_mount.gd]` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/weapons/weapon_mount.gd tests/test_weapon_mount.gd
git commit -m "Add fire-arc gating to WeaponMount"
```

---

### Task 5: Projectile carries a Weapon reference and routes hits through receive_weapon_damage

**Files:**
- Modify: `scripts/weapons/projectile.gd`
- Test: `tests/test_projectile.gd` (modify — add a new check)

**Interfaces:**
- Consumes: `Ship.receive_weapon_damage(weapon: Weapon)` from Task 3.
- Produces: `Projectile.setup(p_target, p_damage, p_weapon_range = 0.0, p_weapon: Weapon = null)` (4th param, optional, backward compatible with all existing 2-3 arg call sites), `Projectile.weapon: Weapon`. Task 6 depends on this 4-arg `setup` signature.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_projectile.gd`'s `run()`, before `target.free()`:

```gdscript
	# weapon-aware hit routing: when a Weapon is attached, _hit() should call
	# receive_weapon_damage(weapon) on the target instead of the plain receive_damage(float).
	var tracker_target := TrackerTarget.new()
	var weapon := Weapon.new()
	weapon.damage = 12.0
	var weapon_projectile := Projectile.new()
	weapon_projectile.global_position = Vector2.ZERO
	weapon_projectile.setup(tracker_target, weapon.damage, 0.0, weapon)
	weapon_projectile._hit()
	if not tracker_target.received_weapon:
		failures.append("_hit: expected receive_weapon_damage(weapon) to be called when a weapon is attached")
	if tracker_target.received_plain:
		failures.append("_hit: expected plain receive_damage NOT to be called when a weapon is attached")

	# Backward compatibility: no weapon attached still calls plain receive_damage(float).
	var plain_tracker := TrackerTarget.new()
	var plain_projectile := Projectile.new()
	plain_projectile.global_position = Vector2.ZERO
	plain_projectile.setup(plain_tracker, 7.0)
	plain_projectile._hit()
	if not plain_tracker.received_plain:
		failures.append("_hit: expected plain receive_damage(float) to be called when no weapon is attached")
	if not is_equal_approx(plain_tracker.last_plain_amount, 7.0):
		failures.append("_hit: expected plain receive_damage to be called with 7.0, got %s" % plain_tracker.last_plain_amount)

	tracker_target.free()
	plain_tracker.free()
```

Add this helper class near the top of `tests/test_projectile.gd`, after the `const Projectile = preload(...)` line:

```gdscript
class TrackerTarget extends Node2D:
	var received_weapon := false
	var received_plain := false
	var last_plain_amount := 0.0
	func receive_weapon_damage(_weapon) -> void:
		received_weapon = true
	func receive_damage(amount: float) -> void:
		received_plain = true
		last_plain_amount = amount
```

Also add, after the existing `const Projectile = preload(...)` line:

```gdscript
const Weapon = preload("res://scripts/weapons/weapon.gd")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/run_tests.gd`
Expected: FAIL — `setup()` doesn't accept a 4th argument yet, so this errors at the `weapon_projectile.setup(...)` call.

- [ ] **Step 3: Write minimal implementation**

In `scripts/weapons/projectile.gd`, add a `weapon` field and update `setup` and `_hit`:

```gdscript
var weapon: Weapon

func setup(p_target: Node2D, p_damage: float, p_weapon_range: float = 0.0, p_weapon: Weapon = null) -> void:
	target = p_target
	damage = p_damage
	weapon = p_weapon
	if is_instance_valid(target):
		travel_direction = (target.global_position - global_position).normalized()
	rotation = travel_direction.angle()
	if p_weapon_range > 0.0:
		max_travel = p_weapon_range * 1.5

func _hit() -> void:
	if is_instance_valid(target):
		if weapon != null and target.has_method("receive_weapon_damage"):
			target.receive_weapon_damage(weapon)
		elif target.has_method("receive_damage"):
			target.receive_damage(damage)
	queue_free()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script tests/run_tests.gd`
Expected: PASS — no `FAIL [res://tests/test_projectile.gd]` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/weapons/projectile.gd tests/test_projectile.gd
git commit -m "Route projectile hits through Ship.receive_weapon_damage when a Weapon is attached"
```

---

### Task 6: WeaponMount submissile volleys and per-weapon projectile speed

**Files:**
- Modify: `scripts/weapons/weapon_mount.gd`
- Test: `tests/test_weapon_mount.gd` (modify — extend `run_async`)

**Interfaces:**
- Consumes: `Weapon.submissile_count`, `Weapon.projectile_speed` from Task 1; the 4-arg `Projectile.setup(..., p_weapon)` from Task 5.
- Produces: `_spawn_projectile` now spawns `weapon.submissile_count` projectiles per shot (still exactly one muzzle flash) and applies `weapon.projectile_speed` to each when nonzero.

- [ ] **Step 1: Write the failing test**

Append to `run_async(tree: SceneTree)` in `tests/test_weapon_mount.gd`, replacing the final `for c in tree.root.get_children():` cleanup block with this (adds a second scenario before the same cleanup runs):

```gdscript
	# Submissile volley: a weapon with submissile_count 4 should spawn 4 projectiles
	# but still exactly one muzzle flash, and projectile_speed should be applied.
	var swarm_weapon := Weapon.new()
	swarm_weapon.weapon_name = "Swarm Missile"
	swarm_weapon.damage = 5.0
	swarm_weapon.fire_rate = 1.0
	swarm_weapon.weapon_range = 300.0
	swarm_weapon.submissile_count = 4
	swarm_weapon.projectile_speed = 80.0
	swarm_weapon.projectile_scene = preload("res://scenes/weapons/projectile.tscn")

	var swarm_mount := WeaponMount.new()
	swarm_mount.weapon = swarm_weapon
	tree.root.add_child(swarm_mount)
	swarm_mount.global_position = Vector2.ZERO

	var projectiles_before: Array = tree.root.get_children().filter(func(c): return c is Projectile)
	var flashes_before: Array = tree.root.get_children().filter(func(c): return c is CPUParticles2D)

	var swarm_fired := swarm_mount.try_fire(target)
	if not swarm_fired:
		failures.append("try_fire: expected true for swarm volley with an in-range target")

	var projectiles_after: Array = tree.root.get_children().filter(func(c): return c is Projectile)
	if projectiles_after.size() != projectiles_before.size() + 4:
		failures.append("_spawn_projectile: expected 4 new projectiles for submissile_count 4, got %d new" % (projectiles_after.size() - projectiles_before.size()))
	for p in projectiles_after:
		if p is Projectile and not projectiles_before.has(p):
			if not is_equal_approx(p.speed, 80.0):
				failures.append("_spawn_projectile: expected submissile speed 80.0, got %s" % p.speed)

	var flashes_after: Array = tree.root.get_children().filter(func(c): return c is CPUParticles2D)
	if flashes_after.size() != flashes_before.size() + 1:
		failures.append("_spawn_projectile: expected exactly 1 new muzzle flash for a 4-submissile volley, got %d new" % (flashes_after.size() - flashes_before.size()))

	for c in tree.root.get_children():
		if (c == swarm_mount or (c is Projectile and not projectiles_before.has(c)) or (c is CPUParticles2D and not flashes_before.has(c))) and is_instance_valid(c):
			c.queue_free()

	for c in tree.root.get_children():
		if (c == target or c == mount or c is CPUParticles2D or c is Projectile) and is_instance_valid(c):
			c.queue_free()
```

(The final loop is the original cleanup block, kept as-is, now running after the new swarm-specific cleanup.)

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/run_tests.gd`
Expected: FAIL — only 1 new `Projectile` spawned instead of 4, and/or `p.speed` mismatch (since `_spawn_projectile` doesn't yet honor `submissile_count`/`projectile_speed`).

- [ ] **Step 3: Write minimal implementation**

Replace `_spawn_projectile` in `scripts/weapons/weapon_mount.gd`:

```gdscript
func _spawn_projectile(target: Node2D) -> void:
	if weapon.projectile_scene == null:
		return
	var host: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	for i in range(weapon.submissile_count):
		var projectile: Node2D = weapon.projectile_scene.instantiate()
		host.add_child(projectile)
		projectile.global_position = global_position
		if weapon.projectile_speed > 0.0:
			projectile.speed = weapon.projectile_speed
		projectile.setup(target, weapon.damage, weapon.weapon_range, weapon)
	var muzzle_flash: Node2D = MuzzleFlashScene.instantiate()
	host.add_child(muzzle_flash)
	muzzle_flash.global_position = global_position
	muzzle_flash.rotation = (target.global_position - global_position).angle()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script tests/run_tests.gd`
Expected: PASS — no `FAIL [res://tests/test_weapon_mount.gd]` lines.

- [ ] **Step 5: Commit**

```bash
git add scripts/weapons/weapon_mount.gd tests/test_weapon_mount.gd
git commit -m "Support submissile volleys and per-weapon projectile speed"
```

---

### Task 7: Create the 14 weapon resource files

**Files:**
- Modify: `resources/weapons/kinetic_cannon.tres` (add new fields only; leave `damage`/`fire_rate`/`weapon_range` untouched)
- Create: `resources/weapons/mass_driver.tres`, `resources/weapons/flak_cannon.tres`, `resources/weapons/railgun.tres`, `resources/weapons/seeker_missile.tres`, `resources/weapons/swarm_missile.tres`, `resources/weapons/torpedo.tres`, `resources/weapons/emp_missile.tres`, `resources/weapons/pulse_laser.tres`, `resources/weapons/heavy_beam.tres`, `resources/weapons/disruptor_beam.tres`, `resources/weapons/lance_graser.tres`, `resources/weapons/pd_flak_turret.tres`, `resources/weapons/pd_laser_turret.tres`
- Test: `tests/test_weapon_resources.gd` (create)
- Modify: `tests/run_tests.gd` (register new test)

**Interfaces:**
- Consumes: all `Weapon` fields from Task 1.
- Produces: nothing further downstream — this is the leaf task.

- [ ] **Step 1: Write the failing test**

Create `tests/test_weapon_resources.gd`:

```gdscript
extends RefCounted

const Weapon = preload("res://scripts/weapons/weapon.gd")

static func _check(failures: Array[String], path: String, expected: Dictionary) -> void:
	var weapon: Weapon = load(path)
	if weapon == null:
		failures.append("%s: failed to load" % path)
		return
	for key in expected:
		var actual = weapon.get(key)
		var exp = expected[key]
		if typeof(exp) == TYPE_FLOAT:
			if not is_equal_approx(actual, exp):
				failures.append("%s: expected %s=%s, got %s" % [path, key, exp, actual])
		elif actual != exp:
			failures.append("%s: expected %s=%s, got %s" % [path, key, exp, actual])

static func run() -> Array[String]:
	var failures: Array[String] = []

	_check(failures, "res://resources/weapons/kinetic_cannon.tres", {
		"damage": 10.0, "fire_rate": 2.0, "weapon_range": 300.0,
		"shield_mult": 0.7, "hull_mult": 1.1,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 100.0,
		"rarity": Weapon.Rarity.COMMON,
	})
	_check(failures, "res://resources/weapons/mass_driver.tres", {
		"damage": 14.0, "fire_rate": 0.8, "weapon_range": 400.0,
		"shield_mult": 1.0, "hull_mult": 1.0,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 120.0,
		"rarity": Weapon.Rarity.COMMON,
	})
	_check(failures, "res://resources/weapons/flak_cannon.tres", {
		"damage": 4.0, "fire_rate": 4.0, "weapon_range": 200.0,
		"shield_mult": 0.6, "hull_mult": 0.6,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 140.0,
		"rarity": Weapon.Rarity.UNCOMMON,
	})
	_check(failures, "res://resources/weapons/railgun.tres", {
		"damage": 35.0, "fire_rate": 0.25, "weapon_range": 500.0,
		"shield_mult": 0.5, "hull_mult": 1.3, "pierce_pct": 0.25,
		"mount_type": Weapon.MountType.FIXED, "fire_arc_degrees": 10.0,
		"rarity": Weapon.Rarity.RARE,
	})
	_check(failures, "res://resources/weapons/seeker_missile.tres", {
		"damage": 18.0, "fire_rate": 0.5, "weapon_range": 350.0,
		"shield_mult": 1.1, "hull_mult": 0.9,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 360.0,
		"rarity": Weapon.Rarity.COMMON,
	})
	_check(failures, "res://resources/weapons/swarm_missile.tres", {
		"damage": 5.0, "fire_rate": 0.33, "weapon_range": 300.0,
		"shield_mult": 1.2, "hull_mult": 0.7, "submissile_count": 4,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 360.0,
		"rarity": Weapon.Rarity.UNCOMMON,
	})
	_check(failures, "res://resources/weapons/torpedo.tres", {
		"damage": 60.0, "fire_rate": 0.2, "weapon_range": 450.0,
		"shield_mult": 1.0, "hull_mult": 1.2, "projectile_speed": 150.0,
		"mount_type": Weapon.MountType.FIXED, "fire_arc_degrees": 10.0,
		"rarity": Weapon.Rarity.RARE,
	})
	_check(failures, "res://resources/weapons/emp_missile.tres", {
		"damage": 6.0, "fire_rate": 0.4, "weapon_range": 250.0,
		"shield_mult": 0.8, "hull_mult": 0.5, "component_damage": 15.0,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 360.0,
		"rarity": Weapon.Rarity.RARE,
	})
	_check(failures, "res://resources/weapons/pulse_laser.tres", {
		"damage": 9.0, "fire_rate": 1.2, "weapon_range": 280.0,
		"shield_mult": 1.4, "hull_mult": 0.75,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 110.0,
		"rarity": Weapon.Rarity.COMMON,
	})
	_check(failures, "res://resources/weapons/heavy_beam.tres", {
		"damage": 16.0, "fire_rate": 1.0, "weapon_range": 220.0,
		"shield_mult": 1.3, "hull_mult": 0.85,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 90.0,
		"rarity": Weapon.Rarity.UNCOMMON,
	})
	_check(failures, "res://resources/weapons/disruptor_beam.tres", {
		"damage": 5.0, "fire_rate": 1.0, "weapon_range": 260.0,
		"shield_mult": 1.0, "hull_mult": 0.4, "component_damage": 10.0,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 100.0,
		"rarity": Weapon.Rarity.RARE,
	})
	_check(failures, "res://resources/weapons/lance_graser.tres", {
		"damage": 30.0, "fire_rate": 0.4, "weapon_range": 450.0,
		"shield_mult": 0.6, "hull_mult": 1.3, "pierce_pct": 0.2,
		"mount_type": Weapon.MountType.FIXED, "fire_arc_degrees": 10.0,
		"rarity": Weapon.Rarity.EPIC,
	})
	_check(failures, "res://resources/weapons/pd_flak_turret.tres", {
		"damage": 3.0, "fire_rate": 6.0, "weapon_range": 120.0,
		"shield_mult": 0.3, "hull_mult": 0.3,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 360.0,
		"rarity": Weapon.Rarity.COMMON,
	})
	_check(failures, "res://resources/weapons/pd_laser_turret.tres", {
		"damage": 6.0, "fire_rate": 3.0, "weapon_range": 150.0,
		"shield_mult": 0.3, "hull_mult": 0.3,
		"mount_type": Weapon.MountType.TURRET, "fire_arc_degrees": 360.0,
		"rarity": Weapon.Rarity.UNCOMMON,
	})

	return failures
```

Register it in `tests/run_tests.gd`'s `test_scripts` array (after the `test_weapon.gd` entry).

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script tests/run_tests.gd`
Expected: FAIL — most `.tres` paths don't exist yet (`load()` returns null) and `kinetic_cannon.tres` is missing the new fields (defaults wrongly reported as e.g. `shield_mult=1.0` instead of `0.7`).

- [ ] **Step 3: Write minimal implementation**

Update `resources/weapons/kinetic_cannon.tres` (add 4 lines under `[resource]`, keep everything else identical):

```
[gd_resource type="Resource" script_class="Weapon" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/weapons/weapon.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/weapons/projectile.tscn" id="2"]

[resource]
script = ExtResource("1")
weapon_name = "Kinetic Cannon"
damage = 10.0
fire_rate = 2.0
weapon_range = 300.0
projectile_scene = ExtResource("2")
shield_mult = 0.7
hull_mult = 1.1
mount_type = 1
fire_arc_degrees = 100.0
rarity = 0
```

Create each new resource file following the same template (`mount_type`: `0` = FIXED, `1` = TURRET; `rarity`: `0` = COMMON, `1` = UNCOMMON, `2` = RARE, `3` = EPIC). Example, `resources/weapons/railgun.tres`:

```
[gd_resource type="Resource" script_class="Weapon" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/weapons/weapon.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/weapons/projectile.tscn" id="2"]

[resource]
script = ExtResource("1")
weapon_name = "Railgun"
damage = 35.0
fire_rate = 0.25
weapon_range = 500.0
projectile_scene = ExtResource("2")
shield_mult = 0.5
hull_mult = 1.3
pierce_pct = 0.25
mount_type = 0
fire_arc_degrees = 10.0
rarity = 2
```

Repeat for the other 12 files using the matching values from the table in the Step 1 test above (`mass_driver`, `flak_cannon`, `seeker_missile`, `swarm_missile`, `torpedo`, `emp_missile`, `pulse_laser`, `heavy_beam`, `disruptor_beam`, `lance_graser`, `pd_flak_turret`, `pd_laser_turret`), each with `weapon_name` set to its own display name (e.g. "Mass Driver", "Flak Cannon", "Seeker Missile", "Swarm Missile", "Torpedo", "EMP Missile", "Pulse Laser", "Heavy Beam", "Disruptor Beam", "Lance/Graser", "PD Flak Turret", "PD Laser Turret") and only the non-default fields present in its `_check(...)` block written out (any field not listed in that block keeps `Weapon`'s own default, so it does not need a line in the `.tres` file).

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script tests/run_tests.gd`
Expected: PASS — no `FAIL [res://tests/test_weapon_resources.gd]` lines, and `All tests passed.` printed at the end (full suite green).

- [ ] **Step 5: Commit**

```bash
git add resources/weapons/*.tres tests/test_weapon_resources.gd tests/run_tests.gd
git commit -m "Add Kinetic/Missile/Beam/PD weapon resource variants"
```
