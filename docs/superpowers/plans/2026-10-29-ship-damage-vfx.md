# Ship Damage/Death Visual Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give ships visible feedback when they take damage (flash + spark), near death (continuous smoke trail), and die (one-shot explosion), using the existing `Hull.damaged`/`Hull.destroyed` signals with no changes to combat logic.

**Architecture:** A new `ShipVfx` node (`scripts/ship/ship_vfx.gd`), added as a sibling of `Hull`/`Shield`/`Engine` in `ship.tscn`, listens to its sibling `Hull`'s signals and drives a `Polygon2D` modulate flash plus two `CPUParticles2D` children (`HitSpark`, `SmokeTrail`). A separate `scenes/vfx/explosion.tscn` plays the death explosion and frees itself, spawned under the ship's parent (not the ship) so it survives `queue_free()`.

**Tech Stack:** Godot 4.7.x (GDScript), `CPUParticles2D` (no textures — flat-colored placeholder particles), headless unit tests via `godot --headless --script res://tests/run_tests.gd`, particle/tween feel verified by editor playtest.

## Global Constraints

- Godot version: 4.7.x, no external addons.
- `CPUParticles2D` only — no `GPUParticles2D` — since there are no particle textures yet and `CPUParticles2D` renders a flat shape by default.
- Every new flash/particle tunable is an `@export` field (or a plain Inspector property on the particle node itself), per the project's existing tuning convention — no hardcoded magic numbers in scripts.
- `ShipVfx` only ever reads from `Hull`/`Ship` — it never mutates combat state (HP, orders, etc.).
- No camera/screen shake, health bar, sprite-based damage states, or particle texture sourcing this milestone (spec: Out of Scope).

---

### Task 1: `ShipVfx` — pure low-HP smoke rule

**Files:**
- Create: `scripts/ship/ship_vfx.gd`
- Create: `tests/test_ship_vfx.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `class_name ShipVfx` (extends `Node2D`), static `ShipVfx.should_emit_smoke(hp_ratio: float, threshold: float) -> bool`. Reused by `ShipVfx`'s own instance method in Task 2.

- [ ] **Step 1: Write the minimal `ShipVfx` script**

`scripts/ship/ship_vfx.gd`:
```gdscript
class_name ShipVfx
extends Node2D

static func should_emit_smoke(hp_ratio: float, threshold: float) -> bool:
	return hp_ratio <= threshold
```

- [ ] **Step 2: Write the failing test**

`tests/test_ship_vfx.gd`:
```gdscript
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_should_emit_smoke(failures)
	return failures

static func _check_should_emit_smoke(failures: Array[String]) -> void:
	if ShipVfx.should_emit_smoke(0.5, 0.25):
		failures.append("should_emit_smoke: expected false when hp_ratio is above threshold")
	if not ShipVfx.should_emit_smoke(0.25, 0.25):
		failures.append("should_emit_smoke: expected true when hp_ratio equals threshold (inclusive)")
	if not ShipVfx.should_emit_smoke(0.1, 0.25):
		failures.append("should_emit_smoke: expected true when hp_ratio is below threshold")
```

- [ ] **Step 3: Register the test and run the suite**

In `tests/run_tests.gd`, add `preload("res://tests/test_ship_vfx.gd"),` to the `test_scripts` array.

Run: `godot --headless --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 4: Commit**

```bash
git add scripts/ship/ship_vfx.gd tests/test_ship_vfx.gd tests/run_tests.gd
git commit -m "Add ShipVfx low-HP smoke threshold rule"
```

---

### Task 2: `ShipVfx` — hit flash, hit spark, smoke toggle

**Files:**
- Modify: `scripts/ship/ship_vfx.gd`
- Modify: `scenes/ship/ship.tscn`
- Modify: `tests/test_ship_vfx.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `Hull.damaged(amount: float, remaining: float)` (unchanged), `Hull.max_hp` (unchanged), `ShipVfx.should_emit_smoke` (Task 1).
- Produces: `ShipVfx.flash_color: Color`, `ShipVfx.flash_duration: float`, `ShipVfx.low_hp_threshold: float` (all `@export`). `ship.tscn` gains a `VFX` node (type `ShipVfx`) with `HitSpark` and `SmokeTrail` `CPUParticles2D` children — later tasks and the live game rely on these exact node names.

- [ ] **Step 1: Add the `VFX` node tree to `ship.tscn`**

Replace `scenes/ship/ship.tscn` in full:

```
[gd_scene load_steps=9 format=3]

[ext_resource type="Script" path="res://scripts/ship/ship.gd" id="1"]
[ext_resource type="Script" path="res://scripts/ship/hull.gd" id="2"]
[ext_resource type="Script" path="res://scripts/ship/shield.gd" id="3"]
[ext_resource type="Script" path="res://scripts/ship/ship_engine.gd" id="4"]
[ext_resource type="Script" path="res://scripts/weapons/weapon_mount.gd" id="5"]
[ext_resource type="Resource" path="res://resources/weapons/kinetic_cannon.tres" id="6"]
[ext_resource type="Script" path="res://scripts/ship/ship_vfx.gd" id="7"]

[sub_resource type="CircleShape2D" id="1"]
radius = 16.0

[node name="Ship" type="CharacterBody2D"]
script = ExtResource("1")

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("1")

[node name="Polygon2D" type="Polygon2D" parent="."]
polygon = PackedVector2Array(20, 0, -12, -10, -12, 10)
color = Color(0.4, 0.8, 1, 1)

[node name="Hull" type="Node" parent="."]
script = ExtResource("2")

[node name="Shield" type="Node" parent="."]
script = ExtResource("3")

[node name="Engine" type="Node" parent="."]
script = ExtResource("4")

[node name="WeaponMount" type="Node2D" parent="."]
script = ExtResource("5")
weapon = ExtResource("6")

[node name="VFX" type="Node2D" parent="."]
script = ExtResource("7")

[node name="HitSpark" type="CPUParticles2D" parent="VFX"]
emitting = false
amount = 12
lifetime = 0.3
one_shot = true
explosiveness = 1.0
direction = Vector2(1, 0)
spread = 180.0
gravity = Vector2(0, 0)
initial_velocity_min = 40.0
initial_velocity_max = 90.0
scale_amount_min = 2.0
scale_amount_max = 4.0
color = Color(1, 0.9, 0.4, 1)

[node name="SmokeTrail" type="CPUParticles2D" parent="VFX"]
emitting = false
amount = 16
lifetime = 0.6
direction = Vector2(-1, 0)
spread = 25.0
gravity = Vector2(0, 0)
initial_velocity_min = 15.0
initial_velocity_max = 30.0
scale_amount_min = 3.0
scale_amount_max = 5.0
color = Color(0.3, 0.3, 0.3, 0.8)
```

- [ ] **Step 2: Wire flash/spark/smoke behavior in `ShipVfx`**

Replace `scripts/ship/ship_vfx.gd` in full:

```gdscript
class_name ShipVfx
extends Node2D

@export var flash_color: Color = Color(1, 0.3, 0.3, 1)
@export var flash_duration: float = 0.12
@export var low_hp_threshold: float = 0.25

@onready var _polygon: Polygon2D = get_parent().get_node("Polygon2D")
@onready var _hull: Hull = get_parent().get_node("Hull")
@onready var _hit_spark: CPUParticles2D = $HitSpark
@onready var _smoke_trail: CPUParticles2D = $SmokeTrail

var _flash_tween: Tween

func _ready() -> void:
	_hull.damaged.connect(_on_hull_damaged)
	_hull.destroyed.connect(_on_hull_destroyed)

func _on_hull_damaged(_amount: float, remaining: float) -> void:
	_flash()
	_hit_spark.restart()
	var hp_ratio: float = remaining / _hull.max_hp if _hull.max_hp > 0.0 else 0.0
	_smoke_trail.emitting = ShipVfx.should_emit_smoke(hp_ratio, low_hp_threshold)

func _flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_polygon.modulate = flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_polygon, "modulate", Color.WHITE, flash_duration)

func _on_hull_destroyed() -> void:
	pass

static func should_emit_smoke(hp_ratio: float, threshold: float) -> bool:
	return hp_ratio <= threshold
```

(`_on_hull_destroyed` stays a no-op until Task 3 adds the explosion.)

- [ ] **Step 3: Write the flash/spark/smoke integration test**

`ShipVfx` resolves its sibling nodes via `get_parent()`/`$`, which only works once it's a real child of a real `Ship` inside a live `SceneTree` — same timing constraint as `tests/test_ship.gd`'s `run_async` (see that file's header comment). Replace `tests/test_ship_vfx.gd` in full:

```gdscript
extends RefCounted

const ShipScene = preload("res://scenes/ship/ship.tscn")

static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_should_emit_smoke(failures)
	return failures

static func _check_should_emit_smoke(failures: Array[String]) -> void:
	if ShipVfx.should_emit_smoke(0.5, 0.25):
		failures.append("should_emit_smoke: expected false when hp_ratio is above threshold")
	if not ShipVfx.should_emit_smoke(0.25, 0.25):
		failures.append("should_emit_smoke: expected true when hp_ratio equals threshold (inclusive)")
	if not ShipVfx.should_emit_smoke(0.1, 0.25):
		failures.append("should_emit_smoke: expected true when hp_ratio is below threshold")

# Integration test: needs a live SceneTree for ShipVfx._ready()'s get_parent()/$ node
# resolution to actually run -- see tests/test_ship.gd's run_async note.
static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var ship: Ship = ShipScene.instantiate()
	tree.root.add_child(ship)
	await tree.process_frame

	var vfx: ShipVfx = ship.get_node("VFX")
	var polygon: Polygon2D = ship.get_node("Polygon2D")
	var smoke: CPUParticles2D = vfx.get_node("SmokeTrail")

	ship.hull.apply_damage(10.0)

	if not polygon.modulate.is_equal_approx(vfx.flash_color):
		failures.append("ShipVfx: expected polygon.modulate to flash immediately on damage, got %s" % polygon.modulate)
	if smoke.emitting:
		failures.append("ShipVfx: expected SmokeTrail not emitting while hp_ratio is above low_hp_threshold")

	ship.hull.apply_damage(ship.hull.max_hp * 0.8)
	if not smoke.emitting:
		failures.append("ShipVfx: expected SmokeTrail emitting once hp_ratio drops at/below low_hp_threshold")

	if is_instance_valid(ship) and not ship.is_queued_for_deletion():
		ship.queue_free()

	return failures
```

- [ ] **Step 4: Register the async test in the runner**

In `tests/run_tests.gd`, add a block mirroring the existing `test_ship.gd` async registration (place it after that one):

```gdscript
	var ship_vfx_test = preload("res://tests/test_ship_vfx.gd")
	var ship_vfx_failures: Array[String] = await ship_vfx_test.run_async(self)
	for f in ship_vfx_failures:
		print("FAIL [%s]: %s" % [ship_vfx_test.resource_path, f])
	total_failures += ship_vfx_failures.size()
```

- [ ] **Step 5: Run the tests**

Run: `godot --headless --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 6: Commit**

```bash
git add scripts/ship/ship_vfx.gd scenes/ship/ship.tscn tests/test_ship_vfx.gd tests/run_tests.gd
git commit -m "Add ShipVfx hit flash, hit spark, and low-HP smoke trail"
```

---

### Task 3: Death explosion

**Files:**
- Create: `scripts/vfx/explosion.gd`
- Create: `scenes/vfx/explosion.tscn`
- Modify: `scripts/ship/ship_vfx.gd`
- Modify: `tests/test_ship_vfx.gd`

**Interfaces:**
- Consumes: `Hull.destroyed` (unchanged), `Ship.global_position` (unchanged).
- Produces: `scenes/vfx/explosion.tscn` — a self-freeing one-shot `CPUParticles2D`. No later task consumes this.

- [ ] **Step 1: Write the self-freeing explosion script**

`scripts/vfx/explosion.gd`:
```gdscript
extends CPUParticles2D

func _ready() -> void:
	finished.connect(queue_free)
```

- [ ] **Step 2: Write the explosion scene**

`scenes/vfx/explosion.tscn`:
```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/vfx/explosion.gd" id="1"]

[node name="Explosion" type="CPUParticles2D"]
script = ExtResource("1")
emitting = true
amount = 40
lifetime = 0.6
one_shot = true
explosiveness = 1.0
direction = Vector2(0, 0)
spread = 180.0
gravity = Vector2(0, 0)
initial_velocity_min = 60.0
initial_velocity_max = 160.0
scale_amount_min = 3.0
scale_amount_max = 6.0
color = Color(1, 0.6, 0.2, 1)
```

- [ ] **Step 3: Spawn the explosion on `Hull.destroyed`**

In `scripts/ship/ship_vfx.gd`, add near the top (after the `@export` lines):

```gdscript
const ExplosionScene = preload("res://scenes/vfx/explosion.tscn")
```

Replace the `_on_hull_destroyed` no-op:

```gdscript
func _on_hull_destroyed() -> void:
	var ship_node := get_parent()
	var explosion: Node2D = ExplosionScene.instantiate()
	ship_node.get_parent().add_child(explosion)
	explosion.global_position = ship_node.global_position
```

(This runs before `ship.gd`'s own `Hull.destroyed` → `queue_free()` handler takes effect — `queue_free()` is deferred, so the ship and its `global_position` are still valid for every signal listener this frame, regardless of listener order.)

- [ ] **Step 4: Write the explosion-spawn test**

In `tests/test_ship_vfx.gd`, add this check and call it at the end of `run_async`, right before the existing cleanup block:

```gdscript
static func _check_explosion_on_destroyed(tree: SceneTree, failures: Array[String]) -> void:
	var ship: Ship = ShipScene.instantiate()
	tree.root.add_child(ship)
	await tree.process_frame

	var last_position: Vector2 = ship.global_position
	var explosion_script: Script = preload("res://scripts/vfx/explosion.gd")
	var explosions_before := tree.root.get_children().filter(func(c): return c.get_script() == explosion_script).size()

	ship.hull.apply_damage(ship.hull.max_hp)

	var explosions_after: Array = tree.root.get_children().filter(func(c): return c.get_script() == explosion_script)
	if explosions_after.size() != explosions_before + 1:
		failures.append("ShipVfx: expected exactly one new explosion added to the ship's parent on hull.destroyed, got %d new" % (explosions_after.size() - explosions_before))
	elif not explosions_after[explosions_after.size() - 1].global_position.is_equal_approx(last_position):
		failures.append("ShipVfx: expected explosion spawned at the ship's last position %s, got %s" % [last_position, explosions_after[explosions_after.size() - 1].global_position])

	for e in explosions_after:
		if is_instance_valid(e):
			e.queue_free()
```

Update `run_async` to call it:

```gdscript
static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var ship: Ship = ShipScene.instantiate()
	tree.root.add_child(ship)
	await tree.process_frame

	var vfx: ShipVfx = ship.get_node("VFX")
	var polygon: Polygon2D = ship.get_node("Polygon2D")
	var smoke: CPUParticles2D = vfx.get_node("SmokeTrail")

	ship.hull.apply_damage(10.0)

	if not polygon.modulate.is_equal_approx(vfx.flash_color):
		failures.append("ShipVfx: expected polygon.modulate to flash immediately on damage, got %s" % polygon.modulate)
	if smoke.emitting:
		failures.append("ShipVfx: expected SmokeTrail not emitting while hp_ratio is above low_hp_threshold")

	ship.hull.apply_damage(ship.hull.max_hp * 0.8)
	if not smoke.emitting:
		failures.append("ShipVfx: expected SmokeTrail emitting once hp_ratio drops at/below low_hp_threshold")

	if is_instance_valid(ship) and not ship.is_queued_for_deletion():
		ship.queue_free()

	await _check_explosion_on_destroyed(tree, failures)

	return failures
```

- [ ] **Step 5: Run the tests**

Run: `godot --headless --script res://tests/run_tests.gd`
Expected: `All tests passed.`

- [ ] **Step 6: Commit**

```bash
git add scripts/vfx/explosion.gd scenes/vfx/explosion.tscn scripts/ship/ship_vfx.gd tests/test_ship_vfx.gd
git commit -m "Add one-shot death explosion for destroyed ships"
```

---

### Task 4: Playtest

**Files:** none (verification only).

- [ ] **Step 1: Playtest the full feedback loop**

Run the project (F5) and start a fleet battle. Verify:
- Every hit on a ship flashes it red and throws a brief spark burst at its position.
- A ship whose HP drops to ~25% or below starts trailing continuous smoke, and the smoke stops if it somehow gets back above that threshold (e.g. via the debug console's `GodMode`, or simply by it not taking further hits and dying before you can check — either way, confirm the smoke only appears once a ship is genuinely low).
- A destroyed ship plays a one-shot explosion burst at the spot it died, and the explosion finishes and disappears on its own (doesn't linger forever).
- None of this blocks or slows down combat — flashes/sparks/smoke/explosions are purely visual and don't desync from the existing hit/death logic.

If any of these don't hold, fix the relevant script from the earlier tasks before proceeding.

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "Confirm ship damage/death VFX playtest"
```
