# Campaign Long-Run Simulation Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an automated Godot test that runs the real campaign simulation forward for several *simulated* minutes (fast, in-process, no real-time waiting) and reports fleet drift distance and whether the pirate fleet ever targets a non-player fleet.

**Architecture:** A new `RefCounted` test script, `tests/test_campaign_long_run_sim.gd`, following the existing `run_async(tree: SceneTree) -> Array[String]` pattern used by other scene-level tests. It resets `CampaignState`, instantiates the real `campaign_scene.tscn` (letting its normal bootstrap spawn player/trader/pirate fleets), then advances time by calling each `CampaignFleetIcon`'s `_physics_process(delta)` directly in a loop with a fixed `delta = 1/60`, bypassing the engine's real frame pacing entirely. It does this for two durations (5 simulated minutes, then 20), tracking each fleet's max distance from its spawn point (report-only, printed) and whether the pirate ever targeted a non-player fleet it came within detection range of (a hard assertion — expected to fail today, documenting a known gap).

**Tech Stack:** GDScript, Godot 4.7 (`godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`).

## Global Constraints

- Test must run in well under 1 second of wall-clock time regardless of simulated duration — verified explicitly in Task 2's manual check. If it's slow, a stray `await tree.physics_frame` has crept back into the loop.
- Durations: `[300.0, 1200.0]` seconds (5 min, 20 min simulated), fixed step `1.0 / 60.0`.
- Each duration runs against a fresh `CampaignState.reset()` + fresh `campaign_scene.tscn` instance — no state bleeds from one duration's run into the next.
- The pirate-engagement assertion is expected to fail on the real codebase today (pirates only ever target the player) — this is documenting a known gap, not a bug in the test. Do not "fix" the assertion to pass; that is a separate, later spec.
- Reading `CampaignFleetIcon._move_target` directly from the test (an underscore-prefixed field) is intentional and approved for this file only — don't treat it as a precedent to copy into other tests.

---

## File Structure

- **Create:** `tests/test_campaign_long_run_sim.gd` — the harness itself.
- **Modify:** `tests/run_tests.gd` — register the new test via `load()` (matching the other campaign-scene tests, since `campaign_scene.gd` bare-references the `CampaignState` autoload).

## Reference: key existing APIs this plan depends on

- `scripts/campaign/campaign_state.gd`: `CampaignState.reset()` — clears `player_fleet`, `enemy_fleets`, `factions`, etc.
- `scripts/campaign/campaign_scene.gd`: `var player_icon: CampaignFleetIcon`, `var enemy_icons: Array[CampaignFleetIcon]`, both populated by `_ready() -> _bootstrap_default_campaign()`.
- `scripts/campaign/campaign_fleet_icon.gd`:
  - `enum BehaviorType { PLAYER, PATROL, TRADER, PIRATE }`
  - `@export var detection_range: float = 200.0`
  - `var _move_target: Vector2`
  - `func route_away_point() -> Vector2` — returns the icon's spawn point.
  - `func _physics_process(delta: float) -> void` — safe to call directly; takes `delta` as a plain parameter.
- `tests/test_campaign_scene.gd` — the existing reference pattern for `campaign_state.reset()` + instantiate + `await tree.process_frame` + read `scene.player_icon` / `scene.enemy_icons`.

---

### Task 1: Harness skeleton — single duration, distance tracking only

**Files:**
- Create: `tests/test_campaign_long_run_sim.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces: `test_campaign_long_run_sim.run_async(tree: SceneTree) -> Array[String]`, matching the signature every other `load()`-based test in `run_tests.gd` already uses.

- [ ] **Step 1: Write `tests/test_campaign_long_run_sim.gd` with one fixed duration and distance-from-spawn tracking (no pirate check yet)**

```gdscript
extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")

const STEP_DELTA := 1.0 / 60.0

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")

	var duration := 300.0  # 5 simulated minutes
	campaign_state.reset()

	var scene: Node2D = CampaignSceneScene.instantiate()
	tree.root.add_child(scene)
	await tree.process_frame

	var icons: Array[CampaignFleetIcon] = [scene.player_icon]
	icons.append_array(scene.enemy_icons)

	var spawn_positions: Dictionary = {}
	var max_distance: Dictionary = {}
	for icon in icons:
		spawn_positions[icon] = icon.global_position
		max_distance[icon] = 0.0

	var step_count := int(duration / STEP_DELTA)
	for step in step_count:
		for icon in icons:
			icon._physics_process(STEP_DELTA)
		for icon in icons:
			var d: float = icon.global_position.distance_to(spawn_positions[icon])
			if d > max_distance[icon]:
				max_distance[icon] = d

	for icon in icons:
		var label: String = "player" if icon == scene.player_icon else "enemy[%d] (%s)" % [scene.enemy_icons.find(icon), CampaignFleetIcon.BehaviorType.keys()[icon.behavior_type]]
		print("[sim %0.0fs] %s max distance from spawn: %.1f" % [duration, label, max_distance[icon]])

	scene.queue_free()
	await tree.process_frame

	return failures
```

- [ ] **Step 2: Register it in `tests/run_tests.gd`**

Add after the `campaign_scene_trading_test` block (around line 104) and before the `campaign_fleet_icon_test` block, matching the existing `load()`-based comment convention:

```gdscript
	# Loaded (not preloaded) for the same reason as campaign_scene_test above:
	# campaign_scene.gd bare-references the CampaignState autoload.
	var campaign_long_run_sim_test = load("res://tests/test_campaign_long_run_sim.gd")
	var campaign_long_run_sim_failures: Array[String] = await campaign_long_run_sim_test.run_async(self)
	for f in campaign_long_run_sim_failures:
		print("FAIL [%s]: %s" % [campaign_long_run_sim_test.resource_path, f])
	total_failures += campaign_long_run_sim_failures.size()
```

- [ ] **Step 3: Run the full suite and verify it passes with the new output present**

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`

Expected: `All tests passed.` (zero failures — this task adds no assertions yet), and somewhere in the output two lines like:
```
[sim 300s] player max distance from spawn: 0.0
[sim 300s] enemy[0] (PIRATE) max distance from spawn: 143.2
[sim 300s] enemy[1] (TRADER) max distance from spawn: 812.5
```
(Exact numbers don't matter yet — just confirm the lines appear, the run finishes quickly, and no errors/crashes occur. The player's distance will be `0.0` since `BehaviorType.PLAYER` has no movement logic (`_process_pirate`/`_process_trader` aren't called for it) — that's correct, not a bug.)

- [ ] **Step 4: Commit**

```bash
git add tests/test_campaign_long_run_sim.gd tests/run_tests.gd
git commit -m "Add campaign long-run sim test skeleton (5-minute distance tracking)"
```

---

### Task 2: Add the 20-minute duration via a duration loop

**Files:**
- Modify: `tests/test_campaign_long_run_sim.gd`

**Interfaces:**
- Consumes: Task 1's `run_async` body — restructured to loop over durations instead of a single hardcoded value.
- Produces: same `run_async(tree: SceneTree) -> Array[String]` signature, unchanged.

- [ ] **Step 1: Replace the single `duration := 300.0` setup with a loop over both durations**

Rewrite `run_async` to wrap the existing body (from `campaign_state.reset()` through `await tree.process_frame` after `queue_free()`) in a `for duration in SIM_DURATIONS_SECONDS:` loop, and hoist `STEP_DELTA` alongside a new constant:

```gdscript
extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")

const SIM_DURATIONS_SECONDS: Array[float] = [300.0, 1200.0]  # 5 min, 20 min
const STEP_DELTA := 1.0 / 60.0

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")

	for duration in SIM_DURATIONS_SECONDS:
		campaign_state.reset()

		var scene: Node2D = CampaignSceneScene.instantiate()
		tree.root.add_child(scene)
		await tree.process_frame

		var icons: Array[CampaignFleetIcon] = [scene.player_icon]
		icons.append_array(scene.enemy_icons)

		var spawn_positions: Dictionary = {}
		var max_distance: Dictionary = {}
		for icon in icons:
			spawn_positions[icon] = icon.global_position
			max_distance[icon] = 0.0

		var step_count := int(duration / STEP_DELTA)
		for step in step_count:
			for icon in icons:
				icon._physics_process(STEP_DELTA)
			for icon in icons:
				var d: float = icon.global_position.distance_to(spawn_positions[icon])
				if d > max_distance[icon]:
					max_distance[icon] = d

		for icon in icons:
			var label: String = "player" if icon == scene.player_icon else "enemy[%d] (%s)" % [scene.enemy_icons.find(icon), CampaignFleetIcon.BehaviorType.keys()[icon.behavior_type]]
			print("[sim %0.0fs] %s max distance from spawn: %.1f" % [duration, label, max_distance[icon]])

		scene.queue_free()
		await tree.process_frame

	return failures
```

- [ ] **Step 2: Run the full suite and verify both durations report, and timing stays fast**

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`

Time the run (e.g. wrap with PowerShell `Measure-Command`). Expected: `All tests passed.`, distance lines printed once for `[sim 300s]` and once for `[sim 1200s]` per icon (6 lines total for 3 icons), and the whole `run_tests.gd` invocation still completes in a few seconds total (dominated by the rest of the suite, not this test) — not tens of seconds. If it's noticeably slower than Task 1's run, stop and check for an accidental `await tree.physics_frame` in the step loop before continuing.

- [ ] **Step 3: Commit**

```bash
git add tests/test_campaign_long_run_sim.gd
git commit -m "Run campaign long-run sim at both 5 and 20 simulated minutes"
```

---

### Task 3: Pirate engagement tracking and assertion

**Files:**
- Modify: `tests/test_campaign_long_run_sim.gd`

**Interfaces:**
- Consumes: Task 2's per-duration loop body — adds pirate/other identification and per-step opportunity/engagement tracking inside the same loop, using the already-built `icons` list and `scene.enemy_icons`.
- Produces: same `run_async` signature; `failures` now may be non-empty by design.

- [ ] **Step 1: Add pirate/other identification and opportunity+engagement tracking inside the duration loop**

Insert pirate/other setup right after the `max_distance` dictionary is built, and the opportunity/engagement check inside the step loop (right after the existing distance-tracking inner loop), and the failure check right after the existing distance-printing loop. Full updated `run_async`:

```gdscript
extends RefCounted

const CampaignSceneScene = preload("res://scenes/campaign/campaign_scene.tscn")

const SIM_DURATIONS_SECONDS: Array[float] = [300.0, 1200.0]  # 5 min, 20 min
const STEP_DELTA := 1.0 / 60.0
const ENGAGEMENT_EPSILON := 1.0

static func run_async(tree: SceneTree) -> Array[String]:
	var failures: Array[String] = []
	var campaign_state = tree.root.get_node("/root/CampaignState")

	for duration in SIM_DURATIONS_SECONDS:
		campaign_state.reset()

		var scene: Node2D = CampaignSceneScene.instantiate()
		tree.root.add_child(scene)
		await tree.process_frame

		var icons: Array[CampaignFleetIcon] = [scene.player_icon]
		icons.append_array(scene.enemy_icons)

		var spawn_positions: Dictionary = {}
		var max_distance: Dictionary = {}
		for icon in icons:
			spawn_positions[icon] = icon.global_position
			max_distance[icon] = 0.0

		var pirate_icon: CampaignFleetIcon = null
		for icon in scene.enemy_icons:
			if icon.behavior_type == CampaignFleetIcon.BehaviorType.PIRATE:
				pirate_icon = icon
				break

		var others: Array[CampaignFleetIcon] = []
		if pirate_icon != null:
			for icon in scene.enemy_icons:
				if icon != pirate_icon:
					others.append(icon)

		var opportunity_seen: Dictionary = {}
		var engaged: Dictionary = {}
		for other in others:
			opportunity_seen[other] = false
			engaged[other] = false

		var step_count := int(duration / STEP_DELTA)
		for step in step_count:
			for icon in icons:
				icon._physics_process(STEP_DELTA)
			for icon in icons:
				var d: float = icon.global_position.distance_to(spawn_positions[icon])
				if d > max_distance[icon]:
					max_distance[icon] = d
			if pirate_icon != null:
				for other in others:
					var pirate_distance: float = pirate_icon.global_position.distance_to(other.global_position)
					if pirate_distance <= pirate_icon.detection_range:
						opportunity_seen[other] = true
					if pirate_icon._move_target.distance_to(other.global_position) <= ENGAGEMENT_EPSILON:
						engaged[other] = true

		for icon in icons:
			var label: String = "player" if icon == scene.player_icon else "enemy[%d] (%s)" % [scene.enemy_icons.find(icon), CampaignFleetIcon.BehaviorType.keys()[icon.behavior_type]]
			print("[sim %0.0fs] %s max distance from spawn: %.1f" % [duration, label, max_distance[icon]])

		for other in others:
			if opportunity_seen[other] and not engaged[other]:
				var other_label: String = "enemy[%d] (%s)" % [scene.enemy_icons.find(other), CampaignFleetIcon.BehaviorType.keys()[other.behavior_type]]
				failures.append("[sim %0.0fs] pirate never targeted %s despite coming within detection range" % [duration, other_label])

		scene.queue_free()
		await tree.process_frame

	return failures
```

- [ ] **Step 2: Run the full suite and verify the expected (known) failure appears**

Run: `godot.windows.opt.tools.64.exe --headless --path . --script res://tests/run_tests.gd`

Expected: output includes two `FAIL [res://tests/test_campaign_long_run_sim.gd]: [sim 300s] pirate never targeted enemy[...] (TRADER) despite coming within detection range` / `[sim 1200s] ...` lines, the run finishes with `N test failure(s).` where N is exactly the pre-existing failure count (0, from `git status` at plan time) plus 2, and no other test in the suite regresses. This is the expected, documented state — do not attempt to make this pass; that's the pirate-hunting fix, a separate later spec.

If instead `opportunity_seen` never becomes true for either duration (i.e. no failure and no `engaged` either — check by temporarily adding a debug print of `opportunity_seen`/`engaged` if the output is ambiguous), the pirate and trader never came within `detection_range` of each other during the run — note the actual bootstrap spawn distance between the pirate (`Vector2(1000, 200)`) and trader (`Vector2(200, 550)`) in `campaign_scene.gd` is well outside the default `detection_range = 200.0`, and both wander/patrol near their own spawn points, so this is a real possible outcome, not just a hypothetical. If it happens, report it as-is (print whatever the data shows) rather than forcing a failure — the point of this task is to find out, not to engineer a particular result.

- [ ] **Step 3: Commit**

```bash
git add tests/test_campaign_long_run_sim.gd
git commit -m "Add pirate non-player-targeting assertion to campaign long-run sim"
```

---

## Self-Review Notes

- **Spec coverage:** manual delta-stepping (not real-time) — Task 1 Step 1. Both durations — Task 2. Distance report-only, no assertion — Tasks 1–3 (print only). Pirate engagement hard assertion, expected-red — Task 3. Suite registration via `load()` — Task 1 Step 2. All spec sections have a corresponding task.
- **Placeholder scan:** no TBD/TODO; Task 3 Step 2 intentionally describes a possible real outcome (no opportunity ever occurring) rather than a placeholder — it's a real contingency with a concrete instruction (report what's found), not unfinished work.
- **Type consistency:** `run_async(tree: SceneTree) -> Array[String]` identical across all three tasks; `CampaignFleetIcon`, `BehaviorType`, `detection_range`, `_move_target`, `route_away_point()` names used consistently with `scripts/campaign/campaign_fleet_icon.gd` and matched against the Task 2→3 diff (no renames introduced).
