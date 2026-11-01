# VFX: Engine Trails + Weapon Fire Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give ships a visible engine trail while moving (combat and overworld) and give weapon fire a muzzle flash + a restyled, directional projectile.

**Architecture:** Four independent, additive VFX changes layered onto existing systems — no new subsystem. Combat ships gain an `EngineTrail` `CPUParticles2D` sibling of the existing `HitSpark`/`SmokeTrail` nodes, toggled by `ShipVfx`. The overworld `CampaignFleetIcon` gains one script-created `EngineTrail` reusing the heading-angle tracking already in that file. `WeaponMount` spawns a new self-freeing `MuzzleFlashScene` alongside each projectile. `projectile.tscn` gets a shaped `Polygon2D` + trailing `CPUParticles2D` instead of a flat `ColorRect`, oriented by a one-time rotation set in `Projectile.setup()`.

**Tech Stack:** Godot 4.7 (GDScript), existing `CPUParticles2D`-based VFX pattern (see `scripts/vfx/explosion.gd`, `scripts/ship/ship_vfx.gd`).

## Global Constraints

- One shared VFX tuning per effect — no per-ship-class (corvette/freighter/capital) variation, matching existing `HitSpark`/`SmokeTrail` precedent.
- No faction-colored VFX — projectiles/trails keep the existing single yellow identity.
- Forward is local +X by convention throughout this codebase (`SmokeTrail`'s existing `direction = Vector2(-1, 0)`, `ShipEngine.steer_toward`'s `Vector2.RIGHT.rotated(...)`) — all new `direction`/`rotation` values in this plan follow that convention.
- Tests verify structural state (node presence, `emitting`, `rotation`, position, counts) — not rendered pixel output, matching how `HitSpark`/`SmokeTrail`/explosion are tested today.
- Run the full suite after every task via:
  `"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
  (Git Bash path; this is the Steam-installed build, confirmed working in the prior overworld-sprites session.)

---

### Task 1: Combat ship engine trail

**Files:**
- Modify: `scripts/ship/ship_vfx.gd`
- Modify: `scenes/ship/ship_corvette.tscn`, `scenes/ship/ship_freighter.tscn`, `scenes/ship/ship_capital.tscn`, `scenes/ship/ship.tscn` (add `EngineTrail` node under each scene's `VFX` node)
- Test: `tests/test_ship_vfx.gd`

**Interfaces:**
- Consumes: `CharacterBody2D.velocity` (built-in, already set every physics frame by `Ship._physics_process`/`ShipEngine.steer_toward`).
- Produces: `ShipVfx.ENGINE_TRAIL_SPEED_THRESHOLD: float` (new constant), and every ship scene now has a child node at `VFX/EngineTrail` (`CPUParticles2D`). No other file in this plan depends on this task's output.

- [ ] **Step 1: Write the failing test**

In `tests/test_ship_vfx.gd`, inside the existing `run_async(tree: SceneTree)` function, insert this block right after the existing `SmokeTrail` assertions (after the `if not smoke.emitting:` check, before `ship.hull.apply_damage(ship.hull.max_hp * 0.8)`) — do not touch the smoke/explosion assertions below it:

```gdscript
	var engine_trail: CPUParticles2D = vfx.get_node("EngineTrail")
	if engine_trail.emitting:
		failures.append("ShipVfx: expected EngineTrail not emitting before any movement")

	# Drive ShipVfx._physics_process directly (same pattern as
	# tests/test_weapon_mount.gd's direct mount._physics_process(0.5) call)
	# rather than ticking the tree and relying on Ship's own AI steering --
	# Order.hold()'s loiter behavior never truly settles to zero velocity,
	# so it can't be used to exercise the "stopped" case.
	ship.velocity = Vector2(50, 0)
	vfx._physics_process(0.016)
	if not engine_trail.emitting:
		failures.append("ShipVfx: expected EngineTrail emitting once ship.velocity exceeds ENGINE_TRAIL_SPEED_THRESHOLD")

	ship.velocity = Vector2.ZERO
	vfx._physics_process(0.016)
	if engine_trail.emitting:
		failures.append("ShipVfx: expected EngineTrail not emitting once ship.velocity drops back to zero")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
Expected: a Godot script error / `FAIL [res://tests/test_ship_vfx.gd]` referencing `Node not found: "EngineTrail"` (the node doesn't exist yet on any ship scene).

- [ ] **Step 3: Add the `EngineTrail` node to each ship scene**

In `scenes/ship/ship_corvette.tscn`, `scenes/ship/ship_freighter.tscn`, `scenes/ship/ship_capital.tscn`, and `scenes/ship/ship.tscn`, add this node as a new child of the existing `VFX` node, placed directly after the `SmokeTrail` node block in each file:

```
[node name="EngineTrail" type="CPUParticles2D" parent="VFX"]
emitting = false
amount = 10
lifetime = 0.4
direction = Vector2(-1, 0)
spread = 10.0
gravity = Vector2(0, 0)
initial_velocity_min = 20.0
initial_velocity_max = 40.0
scale_amount_min = 1.5
scale_amount_max = 2.5
color = Color(0.3, 0.7, 1.0, 0.8)
```

(No `load_steps`/`ext_resource` change needed — `CPUParticles2D` is a built-in type, same as `HitSpark`/`SmokeTrail`.)

- [ ] **Step 4: Wire `ShipVfx` to toggle it off ship speed**

In `scripts/ship/ship_vfx.gd`, add the constant near the top (after the existing `@export var low_hp_threshold` line):

```gdscript
const ENGINE_TRAIL_SPEED_THRESHOLD := 5.0
```

Add two new `@onready` vars alongside the existing ones (after `_smoke_trail`):

```gdscript
@onready var _engine_trail: CPUParticles2D = $EngineTrail
@onready var _body: CharacterBody2D = get_parent()
```

Add a new top-level function (after `_ready()`):

```gdscript
func _physics_process(_delta: float) -> void:
	_engine_trail.emitting = _body.velocity.length() > ENGINE_TRAIL_SPEED_THRESHOLD
```

- [ ] **Step 5: Run test to verify it passes**

Run: `"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 6: Commit**

```bash
git add scripts/ship/ship_vfx.gd scenes/ship/ship_corvette.tscn scenes/ship/ship_freighter.tscn scenes/ship/ship_capital.tscn scenes/ship/ship.tscn tests/test_ship_vfx.gd
git commit -m "Add engine trail VFX to combat ships, toggled by velocity"
```

---

### Task 2: Overworld fleet icon engine trail

**Files:**
- Modify: `scripts/campaign/campaign_fleet_icon.gd`
- Test: `tests/test_campaign_fleet_icon.gd`

**Interfaces:**
- Consumes: `CampaignFleetIcon._heading_angle: float` and the per-frame `movement: Vector2` + `HEADING_EPSILON` already computed in `_physics_process` (from the prior overworld-sprites session; see current file).
- Produces: every `CampaignFleetIcon` now has one `CPUParticles2D` child (findable in tests via `get_children().filter(func(c): return c is CPUParticles2D)`), created in `setup()`.

- [ ] **Step 1: Write the failing test**

In `tests/test_campaign_fleet_icon.gd`, extend the existing "Heading rotation" block (the one that ends with `heading_icon.queue_free()`, added in the prior session) — insert these assertions right before that `heading_icon.queue_free()` line:

```gdscript
	var engine_trail: CPUParticles2D = heading_icon.get_children().filter(func(c): return c is CPUParticles2D)[0]
	if not engine_trail.emitting:
		failures.append("ship dots: expected EngineTrail emitting while fleet is moving")
	if not is_equal_approx(wrapf(engine_trail.rotation, 0, TAU), wrapf(expected_angle, 0, TAU)):
		failures.append("ship dots: expected EngineTrail rotation to match heading (%s), got %s" % [expected_angle, engine_trail.rotation])
```

(`expected_angle` is already defined a few lines above in that block, from the sprite-rotation assertion.)

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
Expected: `FAIL [res://tests/test_campaign_fleet_icon.gd]` — `Invalid access to index 0 ... Array is empty` (no `CPUParticles2D` child exists yet).

- [ ] **Step 3: Add the engine trail to `CampaignFleetIcon`**

In `scripts/campaign/campaign_fleet_icon.gd`, add new constants after the existing `const HEADING_EPSILON := 0.5` line:

```gdscript
const ENGINE_TRAIL_COLOR := Color(0.3, 0.7, 1.0, 0.8)
const ENGINE_TRAIL_AMOUNT := 10
const ENGINE_TRAIL_LIFETIME := 0.4
const ENGINE_TRAIL_SPREAD := 10.0
const ENGINE_TRAIL_VELOCITY_MIN := 20.0
const ENGINE_TRAIL_VELOCITY_MAX := 40.0
const ENGINE_TRAIL_SCALE_MIN := 1.5
const ENGINE_TRAIL_SCALE_MAX := 2.5
```

(These match Task 1's combat-ship values numerically — same visual language — but are expressed as script constants here since this icon builds its visuals entirely at runtime, unlike the scene-authored combat ships.)

Add a new instance var alongside `_heading_angle`:

```gdscript
var _engine_trail: CPUParticles2D
```

Add a new private function (place it near `_sync_ship_dots`):

```gdscript
func _ensure_engine_trail() -> void:
	if _engine_trail != null:
		return
	_engine_trail = CPUParticles2D.new()
	_engine_trail.emitting = false
	_engine_trail.amount = ENGINE_TRAIL_AMOUNT
	_engine_trail.lifetime = ENGINE_TRAIL_LIFETIME
	_engine_trail.direction = Vector2(-1, 0)
	_engine_trail.spread = ENGINE_TRAIL_SPREAD
	_engine_trail.gravity = Vector2.ZERO
	_engine_trail.initial_velocity_min = ENGINE_TRAIL_VELOCITY_MIN
	_engine_trail.initial_velocity_max = ENGINE_TRAIL_VELOCITY_MAX
	_engine_trail.scale_amount_min = ENGINE_TRAIL_SCALE_MIN
	_engine_trail.scale_amount_max = ENGINE_TRAIL_SCALE_MAX
	_engine_trail.color = ENGINE_TRAIL_COLOR
	add_child(_engine_trail)
```

Call it from `setup()`, before the existing `_sync_ship_dots()` call:

```gdscript
func setup(campaign_fleet: CampaignFleet, home_pos: Vector2) -> void:
	fleet = campaign_fleet
	global_position = fleet.position
	_spawn_point = fleet.position
	_move_target = fleet.position
	_home_position = home_pos
	_ensure_engine_trail()
	_sync_ship_dots()
```

Finally, in `_physics_process`, extend the existing heading-tracking block (the `if movement.length() > HEADING_EPSILON:` / `for dot in _ship_dots:` lines) to also drive the trail:

```gdscript
	var movement := global_position - previous_position
	if movement.length() > HEADING_EPSILON:
		_heading_angle = movement.angle()
	for dot in _ship_dots:
		dot.rotation = _heading_angle
	_engine_trail.rotation = _heading_angle
	_engine_trail.emitting = movement.length() > HEADING_EPSILON
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_fleet_icon.gd tests/test_campaign_fleet_icon.gd
git commit -m "Add engine trail VFX to overworld fleet icons"
```

---

### Task 3: Weapon-fire muzzle flash

**Files:**
- Create: `scenes/vfx/muzzle_flash.tscn`
- Modify: `scripts/weapons/weapon_mount.gd`
- Modify: `tests/run_tests.gd` (register a new async test)
- Modify: `tests/test_weapon_mount.gd` (add `run_async`)

**Interfaces:**
- Consumes: `scripts/vfx/explosion.gd` (existing, unmodified — generic "connect `finished` to `queue_free`" script, already used by `scenes/vfx/explosion.tscn`).
- Produces: `MuzzleFlashScene` (preloaded const in `weapon_mount.gd`) — not consumed by any other task in this plan.

- [ ] **Step 1: Write the failing test**

In `tests/test_weapon_mount.gd`, add a new function after the existing `run()`:

```gdscript
static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var weapon := Weapon.new()
	weapon.weapon_name = "Kinetic Cannon"
	weapon.damage = 10.0
	weapon.fire_rate = 2.0
	weapon.weapon_range = 300.0
	weapon.projectile_scene = preload("res://scenes/weapons/projectile.tscn")

	var mount := WeaponMount.new()
	mount.weapon = weapon
	tree.root.add_child(mount)
	mount.global_position = Vector2.ZERO

	var target := Node2D.new()
	target.global_position = Vector2(100.0, 0.0)
	tree.root.add_child(target)

	var particles_before := tree.root.get_children().filter(func(c): return c is CPUParticles2D).size()
	var fired := mount.try_fire(target)
	if not fired:
		failures.append("try_fire: expected true for an in-range target with a real projectile scene")

	var particles_after: Array = tree.root.get_children().filter(func(c): return c is CPUParticles2D)
	if particles_after.size() != particles_before + 1:
		failures.append("_spawn_projectile: expected exactly one new muzzle flash particle node, got %d new" % (particles_after.size() - particles_before))
	elif not particles_after[particles_after.size() - 1].global_position.is_equal_approx(mount.global_position):
		failures.append("_spawn_projectile: expected muzzle flash at mount position %s, got %s" % [mount.global_position, particles_after[particles_after.size() - 1].global_position])

	for c in tree.root.get_children():
		if (c == target or c == mount or c is CPUParticles2D or c is Projectile) and is_instance_valid(c):
			c.queue_free()

	return failures
```

In `tests/run_tests.gd`, add the new async block right after the existing `ship_vfx_test` block (after its `total_failures += ship_vfx_failures.size()` line, before the `ship_type_scenes_test` block):

```gdscript
	var weapon_mount_async_test = preload("res://tests/test_weapon_mount.gd")
	var weapon_mount_async_failures: Array[String] = await weapon_mount_async_test.run_async(self)
	for f in weapon_mount_async_failures:
		print("FAIL [%s]: %s" % [weapon_mount_async_test.resource_path, f])
	total_failures += weapon_mount_async_failures.size()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
Expected: `FAIL [res://tests/test_weapon_mount.gd]: _spawn_projectile: expected exactly one new muzzle flash particle node, got 0 new`

- [ ] **Step 3: Create the muzzle flash scene**

Create `scenes/vfx/muzzle_flash.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/vfx/explosion.gd" id="1"]

[node name="MuzzleFlash" type="CPUParticles2D"]
script = ExtResource("1")
emitting = true
amount = 10
lifetime = 0.15
one_shot = true
explosiveness = 1.0
direction = Vector2(0, 0)
spread = 20.0
gravity = Vector2(0, 0)
initial_velocity_min = 40.0
initial_velocity_max = 80.0
scale_amount_min = 1.5
scale_amount_max = 2.5
color = Color(1, 0.95, 0.6, 1)
```

- [ ] **Step 4: Spawn it from `WeaponMount`**

In `scripts/weapons/weapon_mount.gd`, add a preload near the top (after `class_name WeaponMount` / `extends Node2D`):

```gdscript
const MuzzleFlashScene = preload("res://scenes/vfx/muzzle_flash.tscn")
```

Extend `_spawn_projectile` (append after the existing `projectile.setup(...)` line):

```gdscript
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 6: Commit**

```bash
git add scenes/vfx/muzzle_flash.tscn scripts/weapons/weapon_mount.gd tests/test_weapon_mount.gd tests/run_tests.gd
git commit -m "Add muzzle flash VFX on weapon fire"
```

---

### Task 4: Projectile restyle (shape + trail + rotation)

**Files:**
- Modify: `scenes/weapons/projectile.tscn`
- Modify: `scripts/weapons/projectile.gd`
- Create: `tests/test_projectile.gd`
- Modify: `tests/run_tests.gd` (register the new sync test)

**Interfaces:**
- Consumes: nothing from Tasks 1–3.
- Produces: nothing consumed elsewhere in this plan — this is the last task.

- [ ] **Step 1: Write the failing test**

Create `tests/test_projectile.gd`:

```gdscript
extends RefCounted

const Projectile = preload("res://scripts/weapons/projectile.gd")

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
	return failures
```

In `tests/run_tests.gd`, add `preload("res://tests/test_projectile.gd"),` to the `test_scripts` array (the sync list at the top of `_run_all()`), right after the existing `preload("res://tests/test_weapon_mount.gd"),` line.

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
Expected: `FAIL [res://tests/test_projectile.gd]: setup: expected rotation to face travel_direction (1.5707963267949), got 0.0`

- [ ] **Step 3: Set rotation in `Projectile.setup()`**

In `scripts/weapons/projectile.gd`, modify `setup()`:

```gdscript
func setup(p_target: Node2D, p_damage: float, p_weapon_range: float = 0.0) -> void:
	target = p_target
	damage = p_damage
	if is_instance_valid(target):
		travel_direction = (target.global_position - global_position).normalized()
	rotation = travel_direction.angle()
	if p_weapon_range > 0.0:
		max_travel = p_weapon_range * 1.5
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 5: Restyle the projectile scene**

Replace the `ColorRect` node in `scenes/weapons/projectile.tscn` with a shaped streak and a trailing particle effect. New full file contents:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/weapons/projectile.gd" id="1"]

[sub_resource type="CircleShape2D" id="1"]
radius = 4.0

[node name="Projectile" type="Area2D"]
script = ExtResource("1")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("1")

[node name="Streak" type="Polygon2D" parent="."]
polygon = PackedVector2Array(8, 0, 0, -2, -4, 0, 0, 2)
color = Color(1, 0.8, 0.2, 1)

[node name="Trail" type="CPUParticles2D" parent="."]
emitting = true
amount = 8
lifetime = 0.2
direction = Vector2(-1, 0)
spread = 6.0
gravity = Vector2(0, 0)
initial_velocity_min = 10.0
initial_velocity_max = 20.0
scale_amount_min = 1.0
scale_amount_max = 2.0
color = Color(1, 0.85, 0.4, 0.8)
```

This is a pure visual swap (`ColorRect` → `Polygon2D` + `CPUParticles2D`); no script or test changes are needed for this step since nothing asserts on the old `ColorRect` node (confirmed: `tests/test_weapon_mount.gd`'s existing `run()` only checks `try_fire`/cooldown behavior, never looks up child visual nodes by name).

- [ ] **Step 6: Run full suite once more to confirm nothing regressed**

Run: `"/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 7: Commit**

```bash
git add scenes/weapons/projectile.tscn scripts/weapons/projectile.gd tests/test_projectile.gd tests/run_tests.gd
git commit -m "Restyle projectile with a directional streak and trail"
```

---

## Final check

After all four tasks: run the full suite one more time, then confirm `git status` shows only the files touched across these four tasks (no stray leftovers). No in-game visual verification is required by this plan (no screenshot tooling is wired into any task) — if you want to eyeball the result, launch the game per the "Running the game" notes in `carry_forward.md` and trigger combat/overworld movement manually.
