# Campaign Map Bounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a map-size constant and clamp fleet-icon movement targets to it, so no fleet (player, patrol, trader, or pirate) can drift indefinitely far from the playable area.

**Architecture:** Two new constants, `MAP_MIN`/`MAP_MAX`, in `scripts/campaign/campaign_fleet_icon.gd`. A single clamp call in `_physics_process`, placed right after the `match behavior_type:` block that computes each behavior's `_move_target` and right before the existing `move_toward` call — one choke point covers every behavior type and the player's externally-set mouse-click target uniformly. The long-run simulation test (`tests/test_campaign_long_run_sim.gd`) gains a real hard assertion on top of its existing report-only distance tracking, now that a real `MAP_*` constant exists to check against.

**Tech Stack:** GDScript, Godot 4.7 (`godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`).

## Global Constraints

- `MAP_MIN := Vector2(0, 0)`, `MAP_MAX := Vector2(4000, 2400)` — exact values, no others.
- The clamp applies to `_move_target` (the computed destination), not to `global_position` directly — a fleet aiming at a clamped target glides to a stop at the edge, it does not get teleported or bounced.
- One clamp call site only, after the `match` block, not duplicated inside `_process_trader()`/`_process_pirate()`/the patrol branch.
- No existing bootstrap position, test fixture, or default radius needs to change — `MAP_MIN`/`MAP_MAX` are far outside everything currently in use.
- The long-run sim test's new bounds assertion is expected to **pass** immediately (unlike the pirate-engagement assertion in that same file, which is intentionally still red) — if it fails, that's a real bug in the clamp.

---

## File Structure

- **Modify:** `scripts/campaign/campaign_fleet_icon.gd` — add `MAP_MIN`/`MAP_MAX` constants and the clamp line.
- **Modify:** `tests/test_campaign_fleet_icon.gd` — two new unit-test cases for the clamp.
- **Modify:** `tests/test_campaign_long_run_sim.gd` — real bounds assertion added to the existing per-step tracking; header comment updated to stop saying "no map-bounds constant exists yet."

## Reference: key existing APIs this plan depends on

- `scripts/campaign/campaign_fleet_icon.gd:74-98` — `_physics_process(delta: float) -> void`, containing the `match behavior_type:` block (`:80-88`) and the `move_toward` call (`:89-90`).
- `scripts/campaign/campaign_fleet_icon.gd:59-60` — `func set_move_target(target: Vector2) -> void`, how the player's mouse-click target gets set externally (`campaign_scene.gd:275`).
- `scripts/campaign/behaviors/trader_behavior.gd:18-19` — `static func flee_target(position: Vector2, threat_position: Vector2, flee_distance: float) -> Vector2`, returns `position + (position - threat_position).normalized() * flee_distance`.
- Godot 4 built-in `Vector2.clamp(min: Vector2, max: Vector2) -> Vector2` — component-wise clamp, no helper function needed.
- `tests/test_campaign_fleet_icon.gd:1-4` — existing test file header/preloads (`CampaignFleetIconScene`, `CampaignFleet`), and its construction pattern: `CampaignFleet.new()` → set `position`/`speed` → `CampaignFleetIconScene.instantiate()` → set `behavior_type` → `add_child` → `.setup(fleet, Vector2.ZERO)` → optionally override `.global_position` → `await tree.physics_frame` (one or more times) → assert → `.queue_free()`.
- `tests/test_campaign_long_run_sim.gd` (full current content, 93 lines) — the per-duration loop (`:28-91`), the per-step tracking (`:63-76`), the report-printing loop (`:78-80`), and the failure-appending section (`:82-88`).

---

### Task 1: Map-bounds constant, clamp, and unit tests

**Files:**
- Modify: `scripts/campaign/campaign_fleet_icon.gd`
- Modify: `tests/test_campaign_fleet_icon.gd`

**Interfaces:**
- Produces: `CampaignFleetIcon.MAP_MIN: Vector2`, `CampaignFleetIcon.MAP_MAX: Vector2` — public constants Task 2 reads to build its assertion.

- [ ] **Step 1: Add the constants**

In `scripts/campaign/campaign_fleet_icon.gd`, after the existing `const ENGINE_TRAIL_SCALE_MAX := 2.5` line (`:25`):

```gdscript
const ENGINE_TRAIL_SCALE_MAX := 2.5
const MAP_MIN := Vector2(0, 0)
const MAP_MAX := Vector2(4000, 2400)
```

- [ ] **Step 2: Add the clamp call**

In the same file's `_physics_process`, the `match` block currently ends and falls straight into movement:

```gdscript
		BehaviorType.PLAYER:
			pass
	var previous_position := global_position
	global_position = global_position.move_toward(_move_target, fleet.speed * delta)
```

Change it to:

```gdscript
		BehaviorType.PLAYER:
			pass
	_move_target = _move_target.clamp(MAP_MIN, MAP_MAX)
	var previous_position := global_position
	global_position = global_position.move_toward(_move_target, fleet.speed * delta)
```

- [ ] **Step 3: Write two new failing-until-now test cases in `tests/test_campaign_fleet_icon.gd`**

Insert before the final `return failures` line, after the existing heading-rotation test's `heading_icon.queue_free()`:

```gdscript
	# Map bounds: a player's mouse-click target set far beyond MAP_MAX should
	# be clamped, so the icon never ends up outside the map rectangle even
	# when driven toward a point far outside it.
	var bounds_player_fleet := CampaignFleet.new()
	bounds_player_fleet.position = Vector2(3999, 1199)
	bounds_player_fleet.speed = 1000.0
	var bounds_player_icon: Area2D = CampaignFleetIconScene.instantiate()
	bounds_player_icon.behavior_type = bounds_player_icon.BehaviorType.PLAYER
	tree.root.add_child(bounds_player_icon)
	bounds_player_icon.setup(bounds_player_fleet, Vector2.ZERO)
	bounds_player_icon.global_position = Vector2(3999, 1199)
	bounds_player_icon.set_move_target(Vector2(9999, 9999))

	for i in 20:
		await tree.physics_frame
	if bounds_player_icon.global_position.x > CampaignFleetIcon.MAP_MAX.x or bounds_player_icon.global_position.y > CampaignFleetIcon.MAP_MAX.y:
		failures.append("map bounds: expected player target clamped to MAP_MAX, got position %s" % bounds_player_icon.global_position)

	bounds_player_icon.queue_free()

	# Map bounds: a trader fleeing past MAP_MAX.x should also get clamped.
	# flee_target() = position + normalized(position - threat) * flee_distance;
	# with position (3950,1200), threat (3850,1200), default flee_distance 300,
	# the raw (unclamped) target is (4250, 1200) -- past MAP_MAX.x (4000).
	var bounds_threat_fleet := CampaignFleet.new()
	bounds_threat_fleet.position = Vector2(3850, 1200)
	var bounds_threat_icon: Area2D = CampaignFleetIconScene.instantiate()
	bounds_threat_icon.behavior_type = bounds_threat_icon.BehaviorType.PLAYER
	tree.root.add_child(bounds_threat_icon)
	bounds_threat_icon.setup(bounds_threat_fleet, Vector2.ZERO)
	bounds_threat_icon.global_position = Vector2(3850, 1200)

	var bounds_trader_fleet := CampaignFleet.new()
	bounds_trader_fleet.position = Vector2(3950, 1200)
	bounds_trader_fleet.speed = 1000.0
	var bounds_trader_icon: Area2D = CampaignFleetIconScene.instantiate()
	bounds_trader_icon.behavior_type = bounds_trader_icon.BehaviorType.TRADER
	tree.root.add_child(bounds_trader_icon)
	bounds_trader_icon.setup(bounds_trader_fleet, Vector2.ZERO)
	bounds_trader_icon.global_position = Vector2(3950, 1200)
	bounds_trader_icon.player_target = bounds_threat_icon

	for i in 20:
		await tree.physics_frame
	if bounds_trader_icon.global_position.x > CampaignFleetIcon.MAP_MAX.x:
		failures.append("map bounds: expected fleeing trader's target clamped to MAP_MAX.x, got position %s" % bounds_trader_icon.global_position)

	bounds_trader_icon.queue_free()
	bounds_threat_icon.queue_free()

	return failures
```

(This replaces the old final `return failures` line — the new tests go between the last existing test's cleanup and the `return`.)

Note on why 20 frames: at `speed = 1000.0` and `delta ≈ 1/60`, each frame covers ~16.7 units. The clamped target for the player case is `(4000, 2400)` (distance ~1246 from start) and for the trader case is `(4000, 1200)` (distance 50 from start) — 20 frames (~333 units of travel) is enough for the trader case to fully arrive and stop at the clamped target, and enough to clearly demonstrate the player case would have overshot past `MAP_MAX` without the clamp (the unclamped target `(9999,9999)` is far past it). If the clamp is missing or wrong, both assertions fail.

- [ ] **Step 4: Run the test and verify it fails without the implementation, then passes with it**

This step validates the test is actually exercising the clamp, not passing vacuously. If you're implementing Steps 1-2 and 3 together (normal flow), do this as a sanity check by temporarily commenting out the Step 2 clamp line, confirming the two new assertions in Step 3 fail, then restoring the clamp line and confirming they pass. If Steps 1-2 are already in place when you write Step 3, skip the "temporarily remove" sub-step and just run once to confirm both new assertions pass.

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`

Expected (with the clamp in place): the suite's only failures are the pre-existing, intentionally-red pirate-engagement ones from `test_campaign_long_run_sim.gd` (5-6, depending on wander RNG) — no new failures from `test_campaign_fleet_icon.gd`.

- [ ] **Step 5: Commit**

```bash
git add scripts/campaign/campaign_fleet_icon.gd tests/test_campaign_fleet_icon.gd
git commit -m "Clamp fleet icon movement targets to map bounds"
```

---

### Task 2: Real bounds assertion in the long-run simulation test

**Files:**
- Modify: `tests/test_campaign_long_run_sim.gd`

**Interfaces:**
- Consumes: `CampaignFleetIcon.MAP_MIN`, `CampaignFleetIcon.MAP_MAX` from Task 1.
- Produces: same `run_async(tree: SceneTree) -> Array[String]` signature, unchanged.

- [ ] **Step 1: Update the header comment**

Replace:

```gdscript
# Distance-from-spawn output is report-only; no map-bounds constant exists yet
# to assert against. Reading `_move_target` (underscore-prefixed) is a
# deliberate one-file exception to verify internal pirate-targeting behavior,
# not a pattern to copy elsewhere.
```

with:

```gdscript
# Distance-from-spawn output is report-only (informational, no "right"
# answer). Map bounds ARE asserted: every icon's position must stay within
# CampaignFleetIcon.MAP_MIN/MAP_MAX at every sampled step -- unlike the
# pirate-engagement assertion above, this one is expected to pass; a failure
# here is a real bug in the clamp, not a documented gap. Reading `_move_target`
# (underscore-prefixed) is a deliberate one-file exception to verify internal
# pirate-targeting behavior, not a pattern to copy elsewhere.
```

- [ ] **Step 2: Track out-of-bounds violations alongside the existing distance tracking**

Find this block (`:38-42`):

```gdscript
		var spawn_positions: Dictionary = {}
		var max_distance: Dictionary = {}
		for icon in icons:
			spawn_positions[icon] = icon.global_position
			max_distance[icon] = 0.0
```

Change it to:

```gdscript
		var spawn_positions: Dictionary = {}
		var max_distance: Dictionary = {}
		var out_of_bounds: Dictionary = {}
		for icon in icons:
			spawn_positions[icon] = icon.global_position
			max_distance[icon] = 0.0
```

- [ ] **Step 3: Record the first violation per icon inside the step loop**

Find this block (`:63-69`, the per-step distance-tracking loop):

```gdscript
		for step in step_count:
			for icon in icons:
				icon._physics_process(STEP_DELTA)
			for icon in icons:
				var d: float = icon.global_position.distance_to(spawn_positions[icon])
				if d > max_distance[icon]:
					max_distance[icon] = d
```

Change it to:

```gdscript
		for step in step_count:
			for icon in icons:
				icon._physics_process(STEP_DELTA)
			for icon in icons:
				var d: float = icon.global_position.distance_to(spawn_positions[icon])
				if d > max_distance[icon]:
					max_distance[icon] = d
				var pos: Vector2 = icon.global_position
				if not out_of_bounds.has(icon) and (pos.x < CampaignFleetIcon.MAP_MIN.x or pos.x > CampaignFleetIcon.MAP_MAX.x or pos.y < CampaignFleetIcon.MAP_MIN.y or pos.y > CampaignFleetIcon.MAP_MAX.y):
					out_of_bounds[icon] = pos
```

- [ ] **Step 4: Append a failure per violating icon, after the existing distance-printing loop**

Find this block (`:78-80`):

```gdscript
		for icon in icons:
			var label: String = "player" if icon == scene.player_icon else "enemy[%d] (%s)" % [scene.enemy_icons.find(icon), CampaignFleetIcon.BehaviorType.keys()[icon.behavior_type]]
			print("[sim %0.0fs] %s max distance from spawn: %.1f" % [duration, label, max_distance[icon]])
```

Change it to:

```gdscript
		for icon in icons:
			var label: String = "player" if icon == scene.player_icon else "enemy[%d] (%s)" % [scene.enemy_icons.find(icon), CampaignFleetIcon.BehaviorType.keys()[icon.behavior_type]]
			print("[sim %0.0fs] %s max distance from spawn: %.1f" % [duration, label, max_distance[icon]])
			if out_of_bounds.has(icon):
				failures.append("[sim %0.0fs] %s went out of map bounds: %s" % [duration, label, out_of_bounds[icon]])
```

(This reuses the `label` variable already computed in this loop — no duplicate label computation needed, unlike the pirate section below it which computes its own `other_label`.)

- [ ] **Step 5: Run the full suite and verify the bounds assertion passes while the pirate assertion stays red**

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`

Expected: total failure count is unchanged from before this task (5-6, all `"pirate never targeted ..."` messages) — zero `"went out of map bounds"` failures. If any appear, that's a real bug in Task 1's clamp (most likely: the clamp line was placed before a behavior sets `_move_target` instead of after, or `move_toward` is being called before the clamp) — stop and investigate Task 1's implementation rather than adjusting this test's bounds.

- [ ] **Step 6: Commit**

```bash
git add tests/test_campaign_long_run_sim.gd
git commit -m "Assert map bounds hold in the long-run simulation test"
```

---

## Self-Review Notes

- **Spec coverage:** `MAP_MIN`/`MAP_MAX` constants in `campaign_fleet_icon.gd` — Task 1 Step 1. Single clamp choke point after the `match` block — Task 1 Step 2. Unit tests for both behavior-computed and externally-set (player) targets — Task 1 Step 3. Sim-harness real assertion replacing report-only bounds commentary — Task 2. No existing fixture changes needed — confirmed in both tasks' test additions, which use positions near `MAP_MAX` specifically chosen to not collide with any existing bootstrap/test position.
- **Placeholder scan:** no TBD/TODO. Task 1 Step 4's "sanity check" instruction is a real verification step with a concrete pass/fail description, not a vague placeholder.
- **Type consistency:** `CampaignFleetIcon.MAP_MIN`/`MAP_MAX` (`Vector2`) used identically in Task 1 (definition) and Task 2 (consumption); `_move_target.clamp(MAP_MIN, MAP_MAX)` matches the Godot 4 `Vector2.clamp(Vector2, Vector2) -> Vector2` signature referenced in both tasks.
