# Ship Types Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three distinct ship hulls — Corvette, Freighter, Capital — with different stats, weapon-mount counts, and visuals, and wire them through the campaign fleet data model and the real-time combat scene so player and NPC fleets alike can be composed of a mix of types.

**Architecture:** A new pure static-data class `ShipType` (enum `Kind` + per-kind stat table + scene-path lookup) is the single source of truth for what a "type" means. Three standalone Godot scenes (not inherited-scene diffs — see Global Constraints) each wire `Ship.gd`'s existing Hull/Shield/Engine/WeaponMount composition to different values. `CampaignFleet`'s composition dicts gain an optional `"ship_type"` key that everything reads through `ShipType.kind_of()`, which defaults missing keys to Corvette — this is what keeps every pre-existing test fixture (untyped dicts) passing unmodified.

**Tech Stack:** Godot 4.7 / GDScript. No new dependencies.

## Global Constraints

- Implementation deviates from the design spec's scene-authoring mechanism in one way: the spec said "Godot inherited scenes (diff-only)"; this plan instead uses three **standalone, complete** `.tscn` files. Reasoning: Godot's inherited-scene text format for *removing* an inherited child node (needed for the Freighter's zero weapon mounts) has no simple, reliably-hand-authorable text representation, while three small complete scene files are trivial to write correctly and verify. The design intent (three distinct types, no new combat logic) is unchanged.
- `ShipType.kind_of(comp: Dictionary)` MUST default to `Kind.CORVETTE` when `"ship_type"` is absent from the dict, and `Kind.CORVETTE`'s `cargo_capacity` MUST be `20.0` (matching today's flat `CARGO_CAPACITY_PER_SHIP`). This is load-bearing: dozens of existing tests construct composition dicts with no `ship_type` key and must keep passing without modification.
- Do not change any hardcoded `max_hp`/`max_shield` numeric literal in an *existing* `CampaignFleet.ship_compositions` dict anywhere in `campaign_scene.gd`'s bootstrap. Only add the new `"ship_type"` key to those dicts. (Reason: `tests/test_campaign_scene.gd` asserts the bootstrap's Dominion and Freehold combat fleets "start with exactly equal strength" — `total_strength()` is `hp + shield` and does not consult `ship_type`, so adding a type tag without changing the numbers is always safe; changing the numbers is not.)
- Godot's global `class_name` cache must be warmed after adding `ship_type.gd` (a new `class_name` file) before any `--headless --script` test run can see it: run
  `"C:\Users\corbi\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --editor --quit`
  once, immediately after Task 1's Step 3 (creating `ship_type.gd`), before running any test.
- Test command for every task's verification step:
  `"C:\Users\corbi\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --headless --script tests/run_tests.gd`

---

### Task 1: `ShipType` static data class

**Files:**
- Create: `scripts/ship/ship_type.gd`
- Create: `tests/test_ship_type.gd`
- Modify: `tests/run_tests.gd` (register the new test)

**Interfaces:**
- Produces: `class_name ShipType`, `enum ShipType.Kind { CORVETTE, FREIGHTER, CAPITAL }`, `static func ShipType.kind_of(comp: Dictionary) -> ShipType.Kind`, `static func ShipType.cargo_capacity_for(kind: ShipType.Kind) -> float`, `static func ShipType.new_composition(kind: ShipType.Kind) -> Dictionary` (keys: `ship_type`, `max_hp`, `current_hp`, `max_shield`, `current_shield`), `static func ShipType.scene_for(kind: ShipType.Kind) -> PackedScene` (paths point at scenes created in Task 3 — not called by this task's test, since those scenes don't exist yet).

- [ ] **Step 1: Write the failing test**

Create `tests/test_ship_type.gd`:

```gdscript
extends RefCounted

static func run() -> Array[String]:
	var failures: Array[String] = []

	if ShipType.kind_of({}) != ShipType.Kind.CORVETTE:
		failures.append("kind_of: expected a dict missing 'ship_type' to default to CORVETTE")
	if ShipType.kind_of({"ship_type": ShipType.Kind.FREIGHTER}) != ShipType.Kind.FREIGHTER:
		failures.append("kind_of: expected an explicit ship_type key to be respected")

	if ShipType.cargo_capacity_for(ShipType.Kind.CORVETTE) != 20.0:
		failures.append("cargo_capacity_for: expected Corvette == 20.0, got %s" % ShipType.cargo_capacity_for(ShipType.Kind.CORVETTE))
	if ShipType.cargo_capacity_for(ShipType.Kind.FREIGHTER) != 60.0:
		failures.append("cargo_capacity_for: expected Freighter == 60.0, got %s" % ShipType.cargo_capacity_for(ShipType.Kind.FREIGHTER))
	if ShipType.cargo_capacity_for(ShipType.Kind.CAPITAL) != 20.0:
		failures.append("cargo_capacity_for: expected Capital == 20.0, got %s" % ShipType.cargo_capacity_for(ShipType.Kind.CAPITAL))

	var comp := ShipType.new_composition(ShipType.Kind.CAPITAL)
	if comp["ship_type"] != ShipType.Kind.CAPITAL:
		failures.append("new_composition: expected ship_type == CAPITAL, got %s" % comp["ship_type"])
	if comp["max_hp"] != 220.0 or comp["current_hp"] != 220.0:
		failures.append("new_composition: expected Capital max_hp/current_hp == 220.0, got %s" % comp)
	if comp["max_shield"] != 80.0 or comp["current_shield"] != 80.0:
		failures.append("new_composition: expected Capital max_shield/current_shield == 80.0, got %s" % comp)

	var corvette_comp := ShipType.new_composition(ShipType.Kind.CORVETTE)
	if corvette_comp["max_hp"] != 60.0 or corvette_comp["max_shield"] != 20.0:
		failures.append("new_composition: expected Corvette max_hp==60.0/max_shield==20.0, got %s" % corvette_comp)

	var freighter_comp := ShipType.new_composition(ShipType.Kind.FREIGHTER)
	if freighter_comp["max_hp"] != 80.0 or freighter_comp["max_shield"] != 20.0:
		failures.append("new_composition: expected Freighter max_hp==80.0/max_shield==20.0, got %s" % freighter_comp)

	return failures
```

Register it in `tests/run_tests.gd`: add `preload("res://tests/test_ship_type.gd"),` to the `test_scripts` array (the synchronous list at the top of `_run_all()`, alongside `test_campaign_fleet.gd`).

- [ ] **Step 2: Run test to verify it fails**

Run the test command from Global Constraints. Expected: fails to compile / `ShipType` not found (the class doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `scripts/ship/ship_type.gd`:

```gdscript
class_name ShipType
extends RefCounted

enum Kind { CORVETTE, FREIGHTER, CAPITAL }

const SCENES := {
	Kind.CORVETTE: "res://scenes/ship/ship_corvette.tscn",
	Kind.FREIGHTER: "res://scenes/ship/ship_freighter.tscn",
	Kind.CAPITAL: "res://scenes/ship/ship_capital.tscn",
}

const BASE_STATS := {
	Kind.CORVETTE: {"max_hp": 60.0, "max_shield": 20.0, "cargo_capacity": 20.0},
	Kind.FREIGHTER: {"max_hp": 80.0, "max_shield": 20.0, "cargo_capacity": 60.0},
	Kind.CAPITAL: {"max_hp": 220.0, "max_shield": 80.0, "cargo_capacity": 20.0},
}

static func scene_for(kind: Kind) -> PackedScene:
	return load(SCENES[kind])

static func kind_of(comp: Dictionary) -> Kind:
	return comp.get("ship_type", Kind.CORVETTE)

static func cargo_capacity_for(kind: Kind) -> float:
	return BASE_STATS[kind]["cargo_capacity"]

static func new_composition(kind: Kind) -> Dictionary:
	var stats: Dictionary = BASE_STATS[kind]
	return {
		"ship_type": kind,
		"max_hp": stats["max_hp"],
		"current_hp": stats["max_hp"],
		"max_shield": stats["max_shield"],
		"current_shield": stats["max_shield"],
	}
```

Then run the Godot editor cache-warm pass from Global Constraints (required once for any new `class_name` file before `--headless --script` tests can resolve it).

- [ ] **Step 4: Run test to verify it passes**

Run the test command from Global Constraints. Expected: `test_ship_type.gd` produces zero failures, and the overall suite still ends "All tests passed." (no regressions from Step 1-3).

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/ship_type.gd tests/test_ship_type.gd tests/run_tests.gd
git commit -m "Add ShipType static data class for Corvette/Freighter/Capital stats"
```

---

### Task 2: `Ship.gd` gains a `ship_type` field

**Files:**
- Modify: `scripts/ship/ship.gd`
- Modify: `tests/test_ship.gd`

**Interfaces:**
- Consumes: `ShipType.Kind` (Task 1).
- Produces: `Ship.ship_type: ShipType.Kind` (exported, default `ShipType.Kind.CORVETTE`) — read by `combat_scene.gd` in Task 5 to tag survivor data, and overridden per-scene in Task 3.

- [ ] **Step 1: Write the failing test**

In `tests/test_ship.gd`, inside `run_async()` (after the existing `weapon_mounts.size()` check, i.e. after line 175's `if ship.weapon_mounts.size() != 1:` block), add:

```gdscript
	if ship.ship_type != ShipType.Kind.CORVETTE:
		failures.append("run_async: expected ship.tscn's default ship_type == CORVETTE, got %s" % ship.ship_type)
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command from Global Constraints. Expected: FAIL — `Ship` has no property named `ship_type`.

- [ ] **Step 3: Write minimal implementation**

In `scripts/ship/ship.gd`, add the new export near the other top-level exports (after the `current_order: Order` var, before `@export var enemy_group`):

```gdscript
@export var ship_type: ShipType.Kind = ShipType.Kind.CORVETTE
```

- [ ] **Step 4: Run test to verify it passes**

Run the test command from Global Constraints. Expected: PASS, full suite "All tests passed."

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/ship.gd tests/test_ship.gd
git commit -m "Add Ship.ship_type field, defaulting to Corvette"
```

---

### Task 3: Corvette, Freighter, and Capital scenes

**Files:**
- Create: `scenes/ship/ship_corvette.tscn`
- Create: `scenes/ship/ship_freighter.tscn`
- Create: `scenes/ship/ship_capital.tscn`
- Create: `tests/test_ship_type_scenes.gd`
- Modify: `tests/run_tests.gd` (register the new async test)

**Interfaces:**
- Consumes: `Ship.ship_type` (Task 2), `ShipType.SCENES` paths (Task 1) — this task is what makes those paths resolve to real files.
- Produces: three loadable `PackedScene`s whose root is a `Ship` with `ship_type` set to the matching `ShipType.Kind` value, consumed by `combat_scene.gd` in Task 5.

Stat/weapon-mount table (from the design spec):

| Scene | ship_type | Hull.max_hp | Shield.max_shield | Engine (max_speed / turn_rate / acceleration) | WeaponMount count |
|---|---|---|---|---|---|
| `ship_corvette.tscn` | `CORVETTE` (0) | 60.0 | 20.0 | 280.0 / 5.0 / 220.0 | 1 |
| `ship_freighter.tscn` | `FREIGHTER` (1) | 80.0 | 20.0 | 110.0 / 1.5 / 80.0 | 0 (no `WeaponMount` node at all — `Ship._process_weapons()` already no-ops on an empty `weapon_mounts` array, and `attack_range()` already returns `0.0` with no mounts, so this needs zero code changes) |
| `ship_capital.tscn` | `CAPITAL` (2) | 220.0 | 80.0 | 90.0 / 1.0 / 60.0 | 3 |

- [ ] **Step 1: Write the failing test**

Create `tests/test_ship_type_scenes.gd`:

```gdscript
extends RefCounted

const CorvetteScene = preload("res://scenes/ship/ship_corvette.tscn")
const FreighterScene = preload("res://scenes/ship/ship_freighter.tscn")
const CapitalScene = preload("res://scenes/ship/ship_capital.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	var corvette: Ship = CorvetteScene.instantiate()
	tree.root.add_child(corvette)
	var freighter: Ship = FreighterScene.instantiate()
	tree.root.add_child(freighter)
	var capital: Ship = CapitalScene.instantiate()
	tree.root.add_child(capital)

	await tree.process_frame

	if corvette.ship_type != ShipType.Kind.CORVETTE:
		failures.append("ship_corvette.tscn: expected ship_type == CORVETTE, got %s" % corvette.ship_type)
	if not is_equal_approx(corvette.hull.max_hp, 60.0):
		failures.append("ship_corvette.tscn: expected hull.max_hp == 60.0, got %s" % corvette.hull.max_hp)
	if not is_equal_approx(corvette.shield.max_shield, 20.0):
		failures.append("ship_corvette.tscn: expected shield.max_shield == 20.0, got %s" % corvette.shield.max_shield)
	if corvette.weapon_mounts.size() != 1:
		failures.append("ship_corvette.tscn: expected exactly 1 WeaponMount, got %d" % corvette.weapon_mounts.size())

	if freighter.ship_type != ShipType.Kind.FREIGHTER:
		failures.append("ship_freighter.tscn: expected ship_type == FREIGHTER, got %s" % freighter.ship_type)
	if not is_equal_approx(freighter.hull.max_hp, 80.0):
		failures.append("ship_freighter.tscn: expected hull.max_hp == 80.0, got %s" % freighter.hull.max_hp)
	if freighter.weapon_mounts.size() != 0:
		failures.append("ship_freighter.tscn: expected 0 WeaponMounts (unarmed), got %d" % freighter.weapon_mounts.size())
	if not is_equal_approx(freighter.attack_range(), 0.0):
		failures.append("ship_freighter.tscn: expected attack_range() == 0.0 for an unarmed hull, got %s" % freighter.attack_range())

	if capital.ship_type != ShipType.Kind.CAPITAL:
		failures.append("ship_capital.tscn: expected ship_type == CAPITAL, got %s" % capital.ship_type)
	if not is_equal_approx(capital.hull.max_hp, 220.0):
		failures.append("ship_capital.tscn: expected hull.max_hp == 220.0, got %s" % capital.hull.max_hp)
	if not is_equal_approx(capital.shield.max_shield, 80.0):
		failures.append("ship_capital.tscn: expected shield.max_shield == 80.0, got %s" % capital.shield.max_shield)
	if capital.weapon_mounts.size() != 3:
		failures.append("ship_capital.tscn: expected exactly 3 WeaponMounts, got %d" % capital.weapon_mounts.size())

	for ship in [corvette, freighter, capital]:
		if is_instance_valid(ship) and not ship.is_queued_for_deletion():
			ship.queue_free()

	return failures
```

Register it in `tests/run_tests.gd`'s async section: add this block right after the `ship_vfx_test` block (before the `combat_scene_test` block, since it doesn't touch the `CampaignState` autoload and has no ordering constraints):

```gdscript
	var ship_type_scenes_test = preload("res://tests/test_ship_type_scenes.gd")
	var ship_type_scenes_failures: Array[String] = await ship_type_scenes_test.run_async(self)
	for f in ship_type_scenes_failures:
		print("FAIL [%s]: %s" % [ship_type_scenes_test.resource_path, f])
	total_failures += ship_type_scenes_failures.size()
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command from Global Constraints. Expected: FAIL — scene files don't exist (`Cannot open file` / load error for `ship_corvette.tscn`).

- [ ] **Step 3: Write minimal implementation**

Create `scenes/ship/ship_corvette.tscn`:

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
radius = 12.0

[node name="Ship" type="CharacterBody2D"]
script = ExtResource("1")
ship_type = 0

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("1")

[node name="Polygon2D" type="Polygon2D" parent="."]
polygon = PackedVector2Array(16, 0, -10, -8, -10, 8)
color = Color(0.4, 0.8, 1, 1)

[node name="Hull" type="Node" parent="."]
script = ExtResource("2")
max_hp = 60.0

[node name="Shield" type="Node" parent="."]
script = ExtResource("3")
max_shield = 20.0

[node name="Engine" type="Node" parent="."]
script = ExtResource("4")
max_speed = 280.0
turn_rate = 5.0
acceleration = 220.0

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

Create `scenes/ship/ship_freighter.tscn`:

```
[gd_scene load_steps=7 format=3]

[ext_resource type="Script" path="res://scripts/ship/ship.gd" id="1"]
[ext_resource type="Script" path="res://scripts/ship/hull.gd" id="2"]
[ext_resource type="Script" path="res://scripts/ship/shield.gd" id="3"]
[ext_resource type="Script" path="res://scripts/ship/ship_engine.gd" id="4"]
[ext_resource type="Script" path="res://scripts/ship/ship_vfx.gd" id="5"]

[sub_resource type="CircleShape2D" id="1"]
radius = 22.0

[node name="Ship" type="CharacterBody2D"]
script = ExtResource("1")
ship_type = 1

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("1")

[node name="Polygon2D" type="Polygon2D" parent="."]
polygon = PackedVector2Array(22, 10, 22, -10, -22, -10, -22, 10)
color = Color(0.75, 0.55, 0.25, 1)

[node name="Hull" type="Node" parent="."]
script = ExtResource("2")
max_hp = 80.0

[node name="Shield" type="Node" parent="."]
script = ExtResource("3")
max_shield = 20.0

[node name="Engine" type="Node" parent="."]
script = ExtResource("4")
max_speed = 110.0
turn_rate = 1.5
acceleration = 80.0

[node name="VFX" type="Node2D" parent="."]
script = ExtResource("5")

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

Create `scenes/ship/ship_capital.tscn`:

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
radius = 34.0

[node name="Ship" type="CharacterBody2D"]
script = ExtResource("1")
ship_type = 2

[node name="CollisionShape2D" type="CollisionShape2D" parent="."]
shape = SubResource("1")

[node name="Polygon2D" type="Polygon2D" parent="."]
polygon = PackedVector2Array(34, 0, 14, -20, -24, -20, -34, 0, -24, 20, 14, 20)
color = Color(0.55, 0.3, 0.3, 1)

[node name="Hull" type="Node" parent="."]
script = ExtResource("2")
max_hp = 220.0

[node name="Shield" type="Node" parent="."]
script = ExtResource("3")
max_shield = 80.0

[node name="Engine" type="Node" parent="."]
script = ExtResource("4")
max_speed = 90.0
turn_rate = 1.0
acceleration = 60.0

[node name="WeaponMount" type="Node2D" parent="."]
script = ExtResource("5")
position = Vector2(24, 0)
weapon = ExtResource("6")

[node name="WeaponMount2" type="Node2D" parent="."]
script = ExtResource("5")
position = Vector2(10, -14)
weapon = ExtResource("6")

[node name="WeaponMount3" type="Node2D" parent="."]
script = ExtResource("5")
position = Vector2(10, 14)
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

- [ ] **Step 4: Run test to verify it passes**

Run the test command from Global Constraints. Expected: `test_ship_type_scenes.gd` zero failures, full suite "All tests passed."

- [ ] **Step 5: Commit**

```bash
git add scenes/ship/ship_corvette.tscn scenes/ship/ship_freighter.tscn scenes/ship/ship_capital.tscn tests/test_ship_type_scenes.gd tests/run_tests.gd
git commit -m "Add Corvette, Freighter, and Capital ship scenes"
```

---

### Task 4: `CampaignFleet.cargo_capacity()` uses `ShipType`

**Files:**
- Modify: `scripts/campaign/campaign_fleet.gd`
- Modify: `tests/test_campaign_fleet.gd`

**Interfaces:**
- Consumes: `ShipType.kind_of`, `ShipType.cargo_capacity_for`, `ShipType.new_composition` (Task 1).
- Produces: `CampaignFleet.cargo_capacity()` unchanged signature, new per-type-aware behavior.

- [ ] **Step 1: Write the failing test**

In `tests/test_campaign_fleet.gd`, add after the existing `cargo_fleet` block (after the `cargo_fleet.cargo_total()` checks, before the `default_role_fleet` block):

```gdscript
	var mixed_cargo_fleet := CampaignFleet.new()
	mixed_cargo_fleet.ship_compositions = [
		ShipType.new_composition(ShipType.Kind.FREIGHTER),
		ShipType.new_composition(ShipType.Kind.CORVETTE),
	]
	if mixed_cargo_fleet.cargo_capacity() != 80.0:
		failures.append("cargo_capacity: expected 80.0 for 1 Freighter (60.0) + 1 Corvette (20.0), got %s" % mixed_cargo_fleet.cargo_capacity())
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command from Global Constraints. Expected: FAIL — `cargo_capacity()` returns `40.0` (current flat `size() * 20.0` regardless of type) instead of `80.0`.

- [ ] **Step 3: Write minimal implementation**

In `scripts/campaign/campaign_fleet.gd`, delete `const CARGO_CAPACITY_PER_SHIP := 20.0` and replace:

```gdscript
func cargo_capacity() -> float:
	return ship_compositions.size() * CARGO_CAPACITY_PER_SHIP
```

with:

```gdscript
func cargo_capacity() -> float:
	var sum := 0.0
	for comp in ship_compositions:
		sum += ShipType.cargo_capacity_for(ShipType.kind_of(comp))
	return sum
```

- [ ] **Step 4: Run test to verify it passes**

Run the test command from Global Constraints. Expected: PASS, full suite "All tests passed." (This also re-confirms the existing untyped-dict `cargo_fleet` test two-ships-at-20.0-each=40.0 case still passes via the CORVETTE default — do not skip checking this in the output.)

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_fleet.gd tests/test_campaign_fleet.gd
git commit -m "CampaignFleet.cargo_capacity() uses per-ship-type capacity"
```

---

### Task 5: `combat_scene.gd` spawns the right scene per ship type

**Files:**
- Modify: `scripts/combat/combat_scene.gd`
- Modify: `tests/test_combat_scene.gd`

**Interfaces:**
- Consumes: `ShipType.scene_for`, `ShipType.kind_of` (Task 1), the three scenes (Task 3), `Ship.ship_type` (Task 2).
- Produces: `_spawn_fleet_from_data()` and `_collect_survivor_data()` behavior — unchanged signatures.

- [ ] **Step 1: Write the failing test**

In `tests/test_combat_scene.gd`, in the "Campaign-driven battle" section, change the enemy fleet's composition from a generic dict to a Freighter-tagged one:

```gdscript
	var enemy_fleet := CampaignFleet.new()
	enemy_fleet.ship_compositions = [{"ship_type": ShipType.Kind.FREIGHTER, "max_hp": 80.0, "current_hp": 80.0, "max_shield": 20.0, "current_shield": 20.0}]
```

(replacing the existing line `enemy_fleet.ship_compositions = [{"max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]`)

Then, immediately after the existing `if campaign_scene.enemy_ships.size() != 1:` check (and before the `for ship in campaign_scene.enemy_ships.duplicate():` damage loop), add:

```gdscript
	if campaign_scene.enemy_ships.size() == 1:
		var spawned_enemy: Ship = campaign_scene.enemy_ships[0]
		if spawned_enemy.ship_type != ShipType.Kind.FREIGHTER:
			failures.append("campaign battle: expected the FREIGHTER-tagged composition to spawn a ship_type FREIGHTER, got %s" % spawned_enemy.ship_type)
		if spawned_enemy.weapon_mounts.size() != 0:
			failures.append("campaign battle: expected the spawned FREIGHTER ship to have 0 weapon mounts, got %d" % spawned_enemy.weapon_mounts.size())
```

And after the existing `if not enemy_fleet.is_destroyed():` / `if campaign_state.active_enemy_fleet != null:` checks (still before `campaign_state.reset()`), add a survivor round-trip check using the player side (which is never damaged in this test, so it survives and reports back):

```gdscript
	if campaign_state.player_fleet.ship_compositions.size() != 1:
		failures.append("campaign battle: expected player_fleet to still have 1 surviving ship composition, got %d" % campaign_state.player_fleet.ship_compositions.size())
	elif campaign_state.player_fleet.ship_compositions[0].get("ship_type") != ShipType.Kind.CORVETTE:
		failures.append("campaign battle: expected the surviving player ship's composition to carry ship_type CORVETTE back from combat, got %s" % campaign_state.player_fleet.ship_compositions[0].get("ship_type"))
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command from Global Constraints. Expected: FAIL on both new checks — `_spawn_fleet_from_data` still always instantiates the base `ship_corvette.tscn`-equivalent fallback for every composition regardless of its `ship_type` (so the enemy ship is a Corvette, not a Freighter, and still has 1 weapon mount), and `_collect_survivor_data` doesn't write a `"ship_type"` key at all (so `.get("ship_type")` returns `null`, not `CORVETTE`).

- [ ] **Step 3: Write minimal implementation**

In `scripts/combat/combat_scene.gd`, change the top-level constant:

```gdscript
const ShipScene = preload("res://scenes/ship/ship_corvette.tscn")
```

(This stays as the fallback scene for the no-composition-data spawn paths — `_spawn_fleet()` and `_spawn_extra_ship()` — which have no `CampaignFleet` data to read a type from.)

Change `_spawn_fleet_from_data()`:

```gdscript
func _spawn_fleet_from_data(fleet_data: CampaignFleet, points: Array[Vector2], own_group: StringName, opposing_group: StringName, facing_rotation: float) -> Array[Ship]:
	var spawned: Array[Ship] = []
	for i in fleet_data.ship_compositions.size():
		var point: Vector2 = points[i % points.size()]
		var comp: Dictionary = fleet_data.ship_compositions[i]
		var ship_scene: PackedScene = ShipType.scene_for(ShipType.kind_of(comp))
		var ship: Ship = ship_scene.instantiate()
		add_child(ship)
		ship.global_position = point
		ship.rotation = facing_rotation
		ship.enemy_group = opposing_group
		ship.add_to_group(own_group)
		spawned.append(ship)
	return spawned
```

Change `_collect_survivor_data()`:

```gdscript
func _collect_survivor_data(ships: Array[Ship]) -> Array[Dictionary]:
	var survivors: Array[Dictionary] = []
	for ship in ships:
		if is_instance_valid(ship) and not ship.hull.is_destroyed():
			survivors.append({
				"ship_type": ship.ship_type,
				"max_hp": ship.hull.max_hp,
				"current_hp": ship.hull.current_hp,
				"max_shield": ship.shield.max_shield,
				"current_shield": ship.shield.current_shield,
			})
	return survivors
```

- [ ] **Step 4: Run test to verify it passes**

Run the test command from Global Constraints. Expected: PASS, full suite "All tests passed."

- [ ] **Step 5: Commit**

```bash
git add scripts/combat/combat_scene.gd tests/test_combat_scene.gd
git commit -m "CombatScene spawns the scene matching each composition's ship_type"
```

---

### Task 6: `FleetAllocationPolicy` growth produces typed ships

**Files:**
- Modify: `scripts/campaign/campaign_state.gd`
- Modify: `tests/test_campaign_state.gd`

**Interfaces:**
- Consumes: `ShipType.Kind`, `ShipType.new_composition` (Task 1).
- Produces: `_grow_fleet()` unchanged signature; `_new_ship_template()` removed.

- [ ] **Step 1: Write the failing test**

In `tests/test_campaign_state.gd`, find the outmatched-combat-fleet growth check (around the `weak_combat_fleet` block):

```gdscript
	var ships_before: int = weak_combat_fleet.ship_compositions.size()
	grow_combat_state.tick_economy(CampaignState.ECONOMY_TICK_INTERVAL)
	if weak_combat_fleet.ship_compositions.size() != ships_before + 1:
		failures.append("tick_economy: expected an outmatched combat fleet to grow a ship, had %d before, %d after" % [ships_before, weak_combat_fleet.ship_compositions.size()])
```

Change the last 3 lines to:

```gdscript
	if weak_combat_fleet.ship_compositions.size() != ships_before + 1:
		failures.append("tick_economy: expected an outmatched combat fleet to grow a ship, had %d before, %d after" % [ships_before, weak_combat_fleet.ship_compositions.size()])
	elif weak_combat_fleet.ship_compositions[ships_before]["ship_type"] != ShipType.Kind.CORVETTE:
		failures.append("tick_economy: expected a grown COMBAT fleet's new ship to be ship_type CORVETTE, got %s" % weak_combat_fleet.ship_compositions[ships_before]["ship_type"])
```

And find the trade-growth spawn check:

```gdscript
	if spawned.is_empty():
		failures.append("tick_economy: expected an economically strong, safe faction to spawn a new trader fleet")
	elif spawned[0].role != CampaignFleet.Role.TRADER:
		failures.append("tick_economy: expected the spawned fleet's role to be TRADER")
```

Change the last 2 lines to:

```gdscript
	if spawned.is_empty():
		failures.append("tick_economy: expected an economically strong, safe faction to spawn a new trader fleet")
	elif spawned[0].role != CampaignFleet.Role.TRADER:
		failures.append("tick_economy: expected the spawned fleet's role to be TRADER")
	elif spawned[0].ship_compositions[0]["ship_type"] != ShipType.Kind.FREIGHTER:
		failures.append("tick_economy: expected the spawned trader fleet's ship to be ship_type FREIGHTER, got %s" % spawned[0].ship_compositions[0]["ship_type"])
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command from Global Constraints. Expected: FAIL on both new `elif` branches — `_new_ship_template()` returns a dict with no `"ship_type"` key, so `["ship_type"]` raises a key-not-found error (or, if GDScript treats this as `null`, it fails the equality check against `ShipType.Kind.CORVETTE` / `FREIGHTER`).

- [ ] **Step 3: Write minimal implementation**

In `scripts/campaign/campaign_state.gd`, change `_grow_fleet()`:

```gdscript
func _grow_fleet(faction: PowerFaction, combat_fleets: Array[CampaignFleet], trader_fleets: Array[CampaignFleet], role: CampaignFleet.Role) -> void:
	var fleets_of_role := combat_fleets if role == CampaignFleet.Role.COMBAT else trader_fleets
	var kind := ShipType.Kind.CORVETTE if role == CampaignFleet.Role.COMBAT else ShipType.Kind.FREIGHTER
	for fleet in fleets_of_role:
		if fleet.ship_compositions.size() < FleetAllocationPolicy.MAX_SHIPS_PER_FLEET:
			fleet.ship_compositions.append(ShipType.new_composition(kind))
			return
	if combat_fleets.size() + trader_fleets.size() >= FleetAllocationPolicy.MAX_FLEETS:
		return
	var new_fleet := CampaignFleet.new()
	new_fleet.faction = faction.faction_enum
	new_fleet.role = role
	new_fleet.position = faction.base_position
	new_fleet.speed = 100.0
	new_fleet.ship_compositions = [ShipType.new_composition(kind)]
	enemy_fleets.append(new_fleet)
	fleet_spawn_requested.emit(new_fleet)
```

and delete the now-unused `_new_ship_template()` function entirely.

- [ ] **Step 4: Run test to verify it passes**

Run the test command from Global Constraints. Expected: PASS, full suite "All tests passed."

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_state.gd tests/test_campaign_state.gd
git commit -m "FleetAllocationPolicy growth produces Corvettes for COMBAT, Freighters for TRADER"
```

---

### Task 7: Tag bootstrap fleets with ship types

**Files:**
- Modify: `scripts/campaign/campaign_scene.gd`
- Modify: `tests/test_campaign_economy_bootstrap.gd`

**Interfaces:**
- Consumes: `ShipType.Kind` (Task 1).
- Produces: no new interfaces — this task only adds data to existing bootstrap fleet compositions.

- [ ] **Step 1: Write the failing test**

In `tests/test_campaign_economy_bootstrap.gd`, after the existing `home_base_economy` check block (after the `if not home_role_types.has(EconomyRole.RoleType.REFINERY):` line and its closing, before the `var dominion: PowerFaction = null` line), add:

```gdscript
	if campaign_state.player_fleet == null:
		failures.append("expected bootstrap to set CampaignState.player_fleet")
	else:
		var player_types: Array = campaign_state.player_fleet.ship_compositions.map(func(c): return ShipType.kind_of(c))
		if not player_types.has(ShipType.Kind.CORVETTE):
			failures.append("expected the player's bootstrap fleet to include a CORVETTE")
		if not player_types.has(ShipType.Kind.FREIGHTER):
			failures.append("expected the player's bootstrap fleet to include a FREIGHTER")
		if not player_types.has(ShipType.Kind.CAPITAL):
			failures.append("expected the player's bootstrap fleet to include a CAPITAL")
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command from Global Constraints. Expected: FAIL — all three `has()` checks fail, since no bootstrap composition dict has a `"ship_type"` key yet (`ShipType.kind_of` defaults all three of the player's ships to `CORVETTE`).

- [ ] **Step 3: Write minimal implementation**

In `scripts/campaign/campaign_scene.gd`'s `_bootstrap_default_campaign()`, add a `"ship_type"` key to each `ship_compositions` dict literal (do not change any existing `max_hp`/`max_shield` numbers — see Global Constraints):

```gdscript
	player.ship_compositions = [
		{"ship_type": ShipType.Kind.CORVETTE, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"ship_type": ShipType.Kind.CAPITAL, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
		{"ship_type": ShipType.Kind.FREIGHTER, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0},
	]
```

```gdscript
	pirate.ship_compositions = [{"ship_type": ShipType.Kind.CORVETTE, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
```

```gdscript
	trader.ship_compositions = [{"ship_type": ShipType.Kind.FREIGHTER, "max_hp": 60.0, "current_hp": 60.0, "max_shield": 20.0, "current_shield": 20.0}]
```

```gdscript
	patrol.ship_compositions = [{"ship_type": ShipType.Kind.CORVETTE, "max_hp": 80.0, "current_hp": 80.0, "max_shield": 30.0, "current_shield": 30.0}]
```

```gdscript
	dominion_fleet.ship_compositions = [{"ship_type": ShipType.Kind.CAPITAL, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
```

```gdscript
	freehold_fleet.ship_compositions = [{"ship_type": ShipType.Kind.CORVETTE, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
```

```gdscript
	dominion_trader_fleet.ship_compositions = [{"ship_type": ShipType.Kind.FREIGHTER, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
```

```gdscript
	freehold_trader_fleet.ship_compositions = [{"ship_type": ShipType.Kind.FREIGHTER, "max_hp": 100.0, "current_hp": 100.0, "max_shield": 50.0, "current_shield": 50.0}]
```

- [ ] **Step 4: Run test to verify it passes**

Run the test command from Global Constraints. Expected: PASS, full suite "All tests passed." In particular, re-verify `tests/test_campaign_scene.gd`'s "dominion_icon and freehold_icon start with exactly equal strength" assumption (around its skirmish section) still holds — it must, since `total_strength()` is unchanged and both fleets' `max_hp`/`max_shield` numbers above are untouched (100.0/50.0, same as before this task).

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_scene.gd tests/test_campaign_economy_bootstrap.gd
git commit -m "Tag bootstrap fleets with ship types (player gets one of each)"
```

---

## Self-Review Notes

- **Spec coverage:** `ShipType` class/table → Task 1. Three scenes → Task 3. `CampaignFleet.cargo_capacity()` → Task 4. `combat_scene.gd` spawn-by-type + survivor round-trip → Task 5. `FleetAllocationPolicy` growth producing typed ships → Task 6. Bootstrap fleet tagging (player one-of-each, NPC fleet assignments) → Task 7. Backward-compat default-to-Corvette → built into Task 1 and exercised by every later task's untouched pre-existing tests. Drone carriers, refit, new weapon types — explicitly out of scope per the spec, not present anywhere in this plan.
- **Placeholder scan:** no TBDs; every step has literal code, not a description of code.
- **Type consistency:** `ShipType.Kind`, `ShipType.kind_of`, `ShipType.cargo_capacity_for`, `ShipType.new_composition`, `ShipType.scene_for` are introduced once in Task 1 and used with those exact names in every later task. `Ship.ship_type` introduced in Task 2 is read with that exact name in Tasks 3 and 5.
