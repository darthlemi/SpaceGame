# Campaign Long-Run Simulation Test — Design Spec

## Purpose

Playtesting surfaced two suspected issues in the overworld campaign
simulation: fleets (especially fleeing traders and hunting pirates) can
drift arbitrarily far from the visible play area with nothing to stop
them, and the single pirate fleet only ever reacts to the player — it has
no way to notice or chase a trader or patrol fleet. Both are hard to
confirm just by eyeballing a few minutes of live play.

This spec is the first of three planned pieces of work (harness → map
bounds fix → pirate-hunting fix). It adds an automated test that runs the
real campaign simulation forward for several *simulated* minutes — fast,
deterministic, and in-process — and reports what actually happens, so the
next two fixes are grounded in real numbers instead of guesses.

## Out of scope

- Actually fixing the drift or the pirate-targeting gap — separate specs,
  informed by this harness's output.
- A general-purpose "fast-forward the whole game" tool (economy ticks,
  combat, UI). This harness only drives fleet-icon movement; it does not
  need the economy/trade/loot layers to advance.
- Picking a real map-bounds constant — there isn't one yet, so the
  distance data this test produces is reported, not asserted against.

## Approach: manual delta-stepping, not real-time

The existing async tests (`tests/test_campaign_fleet_icon.gd`, etc.) use
`await tree.physics_frame`, which advances one real engine frame per
await. Simulating 20 minutes that way would mean the test run takes
roughly 20 minutes of wall-clock time — a non-starter for a suite that
currently finishes in seconds.

Instead, this test calls each relevant `CampaignFleetIcon`'s
`_physics_process(delta)` directly, in a plain GDScript loop, with a fixed
`delta := 1.0 / 60.0`. This is just a normal method call — nothing about
it is tied to the engine's actual frame pacing — so thousands of
simulated steps execute in well under a second. Only fleet-icon movement
is driven this way; the rest of the campaign scene (economy timers, UI)
is not ticked and is irrelevant to what this test checks.

## Test structure

New file `tests/test_campaign_long_run_sim.gd`, following the
`run_async(tree: SceneTree) -> Array[String]` pattern used by the other
scene-level tests (`extends RefCounted`, static `run_async`).

```gdscript
const SIM_DURATIONS_SECONDS: Array[float] = [300.0, 1200.0]  # 5 min, 20 min
const STEP_DELTA := 1.0 / 60.0
```

For each duration in `SIM_DURATIONS_SECONDS`, the test runs an
independent scenario (fresh `CampaignState.reset()` + fresh
`CampaignSceneScene` instance) so a 20-minute run's drift can't bleed into
the 5-minute run's results:

```gdscript
var campaign_state = tree.root.get_node("/root/CampaignState")
campaign_state.reset()

var scene: Node2D = CampaignSceneScene.instantiate()
tree.root.add_child(scene)
await tree.process_frame   # let _ready()/_bootstrap_default_campaign() run

var icons: Array[CampaignFleetIcon] = [scene.player_icon] + scene.enemy_icons
var step_count := int(duration / STEP_DELTA)
for step in step_count:
    for icon in icons:
        icon._physics_process(STEP_DELTA)
    _record_sample(icon_data, icons, step)

scene.queue_free()
```

`CampaignSceneScene` is loaded via `load()`, not `preload()`, for the same
reason `test_campaign_scene.gd` does: `campaign_scene.gd` bare-references
the `CampaignState` autoload, which isn't registered yet at
`run_tests.gd`'s compile time in `--script` mode.

## What it tracks

Per icon, keyed by a stable label (player / each enemy icon's index),
sampled every step:

- **Distance from spawn** — `icon.global_position.distance_to(spawn)`,
  where `spawn` is `icon.route_away_point()` for everything except the
  player icon (which has no route; use its starting position instead).
  Running max kept per icon.
- **Pirate engagement** — for the one icon with
  `behavior_type == CampaignFleetIcon.BehaviorType.PIRATE`, and for every
  *other* icon in `scene.enemy_icons` (i.e. every non-player, non-pirate
  fleet — today that's just the bootstrap trader, but the loop doesn't
  assume a fixed count): if `pirate.global_position.distance_to(other.global_position)
  <= pirate.detection_range`, mark `opportunity_seen[other] = true` for
  that pair. Separately, check whether `pirate._move_target` is within a
  small epsilon (`1.0`) of `other.global_position` at that same step —
  if so, mark `engaged[other] = true`.

  Reading `_move_target` directly (an underscore-prefixed, conventionally
  private field) is a deliberate exception here, not a precedent for
  other tests: this test exists specifically to verify *internal*
  targeting behavior, not just observable position over time. A
  position-trend heuristic ("did distance decrease over N steps")
  would be noisier and no more honest about what's actually being
  checked.

## Assertions

- **Pirate engagement (hard failure):** for every `other` where
  `opportunity_seen[other]` is true, `engaged[other]` must also be true.
  Violations append to `failures` with the pair and the step count,
  e.g. `"pirate never targeted trader fleet despite N steps in detection range"`.

  This is expected to fail today — pirate behavior
  (`campaign_fleet_icon.gd:_process_pirate`) only ever compares against
  `player_target`, never against other `enemy_icons`. That's the known
  gap this harness exists to document; the test suite stays red until
  the pirate-hunting fix (a later spec) closes it. This is intentional,
  not a bug in the test.

- **Distance from spawn (report-only):** no assertion. For each icon,
  `print("[sim %0.0fs] %s max distance from spawn: %.1f" % [duration, label, max_distance])`.
  Once the map-bounds fix lands with a real `MAP_*` constant, this
  becomes a real assertion in that spec — not here.

## Registration in the suite

Added to `tests/run_tests.gd` near the other `load()`-based
campaign-scene tests (after `campaign_scene_trading_test`, before
`campaign_fleet_icon_test`), following the existing comment convention
explaining the `load()` vs `preload()` choice.

## Testing the test

Run `godot.windows.opt.tools.64.exe --headless --path . --script
res://tests/run_tests.gd` after adding it. Expect:

- Full suite still reports `All tests passed.` for every pre-existing
  test.
- The new test reports **one failure** (pirate engagement gap) plus
  distance-from-spawn data for both the 5-minute and 20-minute runs,
  printed to stdout.
- Total run time for the new test should be sub-second; if it's not,
  something (likely an accidental `await tree.physics_frame` reintroduced
  into the loop) is turning simulated time back into real time.
