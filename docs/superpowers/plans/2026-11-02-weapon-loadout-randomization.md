# Weapon Loadout Randomization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ship_corvette.tscn` and `ship_capital.tscn` spawn with a randomized weapon loadout drawn from the 14 existing ship-mountable weapon resources, instead of every mount hardcoding `kinetic_cannon.tres`.

**Architecture:** A new `ShipType.WEAPON_POOL` constant lists the 14 eligible resource paths. A new `Ship.randomize_loadout` export flag (default `false`) gates a new `_assign_random_loadout()` call in `Ship._ready()`, which shuffles a copy of the pool and assigns one distinct weapon per `WeaponMount`, in order. Only `ship_corvette.tscn` and `ship_capital.tscn` set the flag `true`; `ship.tscn` and `ship_freighter.tscn` are untouched.

**Tech Stack:** Godot 4 / GDScript. Headless test runner: `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`

## Global Constraints

- No mount-size/compatibility restriction exists in the weapon data model — every pool entry is valid for every mount (per the 2026-11-01 weapon-types spec's own Out-of-scope section). No filtering logic beyond excluding the 3 drone-only weapons.
- `scenes/ship/ship.tscn` (generic scene, used by many existing tests expecting a fixed, known `kinetic_cannon.tres`) and `ship_freighter.tscn` (0 mounts) must not change behavior.
- `tests/test_ship_type_scenes.gd` already only asserts mount count/hitbox radii, not weapon identity — do not need to modify it, but do not break its assertions either.
- Out of scope: rarity-weighted picks, any shop/purchase/inventory system, faction-specific pools, PD/Interceptor missile-vs-drone targeting.
- Run the full suite after every task via the headless command above. Only acceptable pre-existing failures: `test_campaign_long_run_sim.gd`'s flaky pirate-targeting cases. Any other failure is a regression — fix before moving on.
- New/changed `.tscn`/texture files need one `--headless --editor --quit` warm pass before `--headless --script` test runs can see class/resource changes (per-checkout cache gotcha noted in `carry_forward.md`) — not expected to be needed here since no new scenes/textures are added, but run it first if a test run reports a resource it can't find.

---

### Task 1: `ShipType.WEAPON_POOL` constant

**Files:**
- Modify: `scripts/ship/ship_type.gd`
- Test: `tests/test_ship_type.gd`

**Interfaces:**
- Produces: `ShipType.WEAPON_POOL: Array[String]` — a flat array of 14 `res://resources/weapons/*.tres` paths, excluding `drone_attack_gun.tres`, `drone_bomber_payload.tres`, `drone_interceptor_gun.tres`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_ship_type.gd`, inside `run()`, just before `return failures`:

```gdscript
	if ShipType.WEAPON_POOL.size() != 14:
		failures.append("WEAPON_POOL: expected 14 entries, got %d" % ShipType.WEAPON_POOL.size())
	var seen_paths := {}
	for path in ShipType.WEAPON_POOL:
		if seen_paths.has(path):
			failures.append("WEAPON_POOL: duplicate entry %s" % path)
		seen_paths[path] = true
		if not ResourceLoader.exists(path):
			failures.append("WEAPON_POOL: path does not exist: %s" % path)
		if path.contains("drone_"):
			failures.append("WEAPON_POOL: drone-only weapon should not appear in the ship pool: %s" % path)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `Invalid get index 'WEAPON_POOL'` or similar, since the constant doesn't exist yet.

- [ ] **Step 3: Write minimal implementation**

In `scripts/ship/ship_type.gd`, add alongside the existing `SCENES`/`BASE_STATS` consts:

```gdscript
const WEAPON_POOL: Array[String] = [
	"res://resources/weapons/kinetic_cannon.tres",
	"res://resources/weapons/mass_driver.tres",
	"res://resources/weapons/flak_cannon.tres",
	"res://resources/weapons/railgun.tres",
	"res://resources/weapons/seeker_missile.tres",
	"res://resources/weapons/swarm_missile.tres",
	"res://resources/weapons/torpedo.tres",
	"res://resources/weapons/emp_missile.tres",
	"res://resources/weapons/pulse_laser.tres",
	"res://resources/weapons/heavy_beam.tres",
	"res://resources/weapons/disruptor_beam.tres",
	"res://resources/weapons/lance_graser.tres",
	"res://resources/weapons/pd_flak_turret.tres",
	"res://resources/weapons/pd_laser_turret.tres",
]
```

- [ ] **Step 4: Run test to verify it passes**

Run the same headless command as Step 2.
Expected: `All tests passed` (or at least no `WEAPON_POOL` failures).

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/ship_type.gd tests/test_ship_type.gd
git commit -m "Add ShipType.WEAPON_POOL for ship weapon loadout randomization"
```

---

### Task 2: `Ship.randomize_loadout` + `_assign_random_loadout()`

**Files:**
- Modify: `scripts/ship/ship.gd`
- Test: `tests/test_ship.gd` (uses the existing async `run_async(tree)` pattern already present in that file)

**Interfaces:**
- Consumes: `ShipType.WEAPON_POOL` (Task 1).
- Produces: `Ship.randomize_loadout: bool` (export, default `false`); `Ship._assign_random_loadout() -> void` (private, called from `_ready()` only when the flag is true).

- [ ] **Step 1: Write the failing test**

Open `tests/test_ship.gd` and find its `run_async(tree)` function (it already instantiates `ship.tscn` and awaits a frame — follow that exact pattern). Add a new block before the function's final `return failures`:

```gdscript
	var randomized_ship: Ship = preload("res://scenes/ship/ship.tscn").instantiate()
	randomized_ship.randomize_loadout = true
	tree.root.add_child(randomized_ship)
	await tree.process_frame

	if randomized_ship.weapon_mounts.size() != 1:
		failures.append("randomize_loadout: expected ship.tscn to still have exactly 1 WeaponMount, got %d" % randomized_ship.weapon_mounts.size())
	elif randomized_ship.weapon_mounts[0].weapon == null:
		failures.append("randomize_loadout: expected the mount's weapon to be non-null after randomization")
	elif not ShipType.WEAPON_POOL.has(randomized_ship.weapon_mounts[0].weapon.resource_path):
		failures.append("randomize_loadout: expected the assigned weapon's resource_path to be a member of WEAPON_POOL, got %s" % randomized_ship.weapon_mounts[0].weapon.resource_path)

	if is_instance_valid(randomized_ship) and not randomized_ship.is_queued_for_deletion():
		randomized_ship.queue_free()
```

(If `tests/test_ship.gd` has no existing `run_async`, read the file first — `test_ship_type_scenes.gd` shown in this plan's research is the reference pattern: instantiate, `add_child`, `await tree.process_frame`, assert, `queue_free`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — `Invalid assignment of property or key 'randomize_loadout'` (export doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

In `scripts/ship/ship.gd`, add the export near the other `@export` lines:

```gdscript
@export var randomize_loadout: bool = false
```

Change `_ready()` from:

```gdscript
func _ready() -> void:
	for child in get_children():
		if child is WeaponMount:
			weapon_mounts.append(child)
	hull.destroyed.connect(_on_hull_destroyed)
	execute_order(Order.hold())
```

to:

```gdscript
func _ready() -> void:
	for child in get_children():
		if child is WeaponMount:
			weapon_mounts.append(child)
	hull.destroyed.connect(_on_hull_destroyed)
	execute_order(Order.hold())
	if randomize_loadout:
		_assign_random_loadout()

func _assign_random_loadout() -> void:
	var pool: Array = ShipType.WEAPON_POOL.duplicate()
	pool.shuffle()
	for i in weapon_mounts.size():
		weapon_mounts[i].weapon = load(pool[i % pool.size()])
```

- [ ] **Step 4: Run test to verify it passes**

Run the same headless command as Step 2.
Expected: `All tests passed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ship/ship.gd tests/test_ship.gd
git commit -m "Add Ship.randomize_loadout flag and random weapon assignment"
```

---

### Task 3: Wire `ship_corvette.tscn` and `ship_capital.tscn`, add end-to-end test

**Files:**
- Modify: `scenes/ship/ship_corvette.tscn`
- Modify: `scenes/ship/ship_capital.tscn`
- Create: `tests/test_weapon_loadout.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `Ship.randomize_loadout` and `ShipType.WEAPON_POOL` (Tasks 1-2).
- Produces: nothing consumed by later tasks — this is the final integration task.

- [ ] **Step 1: Write the failing test**

Create `tests/test_weapon_loadout.gd`:

```gdscript
extends RefCounted

const CorvetteScene = preload("res://scenes/ship/ship_corvette.tscn")
const CapitalScene = preload("res://scenes/ship/ship_capital.tscn")
const GenericShipScene = preload("res://scenes/ship/ship.tscn")

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []

	# Capital: 3 mounts, all non-null, pairwise distinct.
	var capital: Ship = CapitalScene.instantiate()
	tree.root.add_child(capital)
	await tree.process_frame

	if capital.weapon_mounts.size() != 3:
		failures.append("ship_capital.tscn: expected 3 WeaponMounts, got %d" % capital.weapon_mounts.size())
	else:
		var resource_paths: Array[String] = []
		for mount in capital.weapon_mounts:
			if mount.weapon == null:
				failures.append("ship_capital.tscn: expected every mount's weapon to be non-null")
			else:
				resource_paths.append(mount.weapon.resource_path)
		var unique_paths := {}
		for path in resource_paths:
			unique_paths[path] = true
		if unique_paths.size() != resource_paths.size():
			failures.append("ship_capital.tscn: expected 3 distinct weapons across its mounts, got %s" % resource_paths)

	if is_instance_valid(capital) and not capital.is_queued_for_deletion():
		capital.queue_free()

	# Corvette: 1 mount, non-null, pool member.
	var corvette: Ship = CorvetteScene.instantiate()
	tree.root.add_child(corvette)
	await tree.process_frame

	if corvette.weapon_mounts.size() != 1:
		failures.append("ship_corvette.tscn: expected 1 WeaponMount, got %d" % corvette.weapon_mounts.size())
	elif corvette.weapon_mounts[0].weapon == null:
		failures.append("ship_corvette.tscn: expected the mount's weapon to be non-null")
	elif not ShipType.WEAPON_POOL.has(corvette.weapon_mounts[0].weapon.resource_path):
		failures.append("ship_corvette.tscn: expected the assigned weapon to be a WEAPON_POOL member, got %s" % corvette.weapon_mounts[0].weapon.resource_path)

	if is_instance_valid(corvette) and not corvette.is_queued_for_deletion():
		corvette.queue_free()

	# Variety check: spawn 10 corvettes, expect at least 2 distinct weapons across them.
	var seen_across_spawns := {}
	for i in range(10):
		var c: Ship = CorvetteScene.instantiate()
		tree.root.add_child(c)
		await tree.process_frame
		if c.weapon_mounts.size() == 1 and c.weapon_mounts[0].weapon != null:
			seen_across_spawns[c.weapon_mounts[0].weapon.resource_path] = true
		c.queue_free()
	if seen_across_spawns.size() < 2:
		failures.append("ship_corvette.tscn: expected at least 2 distinct weapons across 10 spawns, got %s" % seen_across_spawns.keys())

	# Regression guard: the generic ship.tscn (randomize_loadout defaults false)
	# must keep its fixed kinetic_cannon.tres.
	var generic: Ship = GenericShipScene.instantiate()
	tree.root.add_child(generic)
	await tree.process_frame

	if generic.weapon_mounts.size() != 1:
		failures.append("ship.tscn: expected 1 WeaponMount, got %d" % generic.weapon_mounts.size())
	elif generic.weapon_mounts[0].weapon == null or generic.weapon_mounts[0].weapon.resource_path != "res://resources/weapons/kinetic_cannon.tres":
		failures.append("ship.tscn: expected the fixed kinetic_cannon.tres to be unaffected, got %s" % (generic.weapon_mounts[0].weapon.resource_path if generic.weapon_mounts[0].weapon else "null"))

	if is_instance_valid(generic) and not generic.is_queued_for_deletion():
		generic.queue_free()

	return failures
```

Register it in `tests/run_tests.gd` — add immediately after the existing `ship_type_scenes_test` block (around the `var ship_type_scenes_test = preload(...)` lines found during planning):

```gdscript
	var weapon_loadout_test = preload("res://tests/test_weapon_loadout.gd")
	var weapon_loadout_failures: Array[String] = await weapon_loadout_test.run_async(self)
	for f in weapon_loadout_failures:
		print("FAIL [%s]: %s" % [weapon_loadout_test.resource_path, f])
	total_failures += weapon_loadout_failures.size()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
Expected: FAIL — capital's 3 mounts and corvette's 1 mount all still report `kinetic_cannon.tres` (not yet randomized), so the "distinct weapons" and "variety across spawns" assertions fail.

- [ ] **Step 3: Wire the scenes**

In `scenes/ship/ship_corvette.tscn`:
- Remove the line `weapon = ExtResource("6")` from the `[node name="WeaponMount" ...]` block.
- Remove the now-unused `[ext_resource type="Resource" path="res://resources/weapons/kinetic_cannon.tres" id="6"]` line.
- Add `randomize_loadout = true` to the `[node name="Ship" type="CharacterBody2D"]` block (alongside its existing `ship_type = 0` / `hit_radius = 12.0` lines).

In `scenes/ship/ship_capital.tscn`:
- Remove `weapon = ExtResource("6")` from all three `WeaponMount`/`WeaponMount2`/`WeaponMount3` node blocks.
- Remove the now-unused `kinetic_cannon.tres` ext_resource line (confirm via `grep -n "ExtResource(\"6\")" scenes/ship/ship_capital.tscn` that no other node still references it before deleting the ext_resource declaration).
- Add `randomize_loadout = true` to the `[node name="Ship" ...]` block.

- [ ] **Step 4: Run test to verify it passes**

Run the same headless command as Step 2.
Expected: `All tests passed`. If the capital or corvette scene fails to load (a dangling `ExtResource("6")` reference left on some node), re-check the `grep` from Step 3 and restore the ext_resource line if it's still needed anywhere.

- [ ] **Step 5: Run the full suite once more to confirm no regressions**

Run the same headless command.
Expected: `All tests passed` except the pre-existing, known-flaky `test_campaign_long_run_sim.gd` pirate-targeting failures (unrelated to this change). Any other failure is a regression — investigate before committing.

- [ ] **Step 6: Commit**

```bash
git add scenes/ship/ship_corvette.tscn scenes/ship/ship_capital.tscn tests/test_weapon_loadout.gd tests/run_tests.gd
git commit -m "Randomize ship_corvette/ship_capital weapon loadouts from the weapon pool"
```

---

## Done

After Task 3, every corvette and capital spawn (player, Dominion, Freehold, pirate alike) rolls a random loadout from the 14-weapon pool; the capital's 3 mounts never repeat a weapon on the same ship. `ship.tscn` and `ship_freighter.tscn` behavior is unchanged, verified by the regression-guard assertions in `test_weapon_loadout.gd`.
