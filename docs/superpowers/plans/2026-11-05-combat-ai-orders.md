# Combat AI and Orders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ships fight according to their hull and weapons (PD-free range choice, hull-edge
range, attack runs, kiting, spreading out, scored targets), and the player gets Hold
Position and Flee orders with an order bar, plus a campaign re-engage delay.

**Architecture:** Pure decision helpers go in a new static `CombatTactics` class, so they can
be unit-tested without a scene. `Ship` uses them for movement and firing (both sides).
`AIController` uses them for target choice and the flee decision (enemy side only).
`FleetCommander` and a new `OrderBar` control issue the new orders. `combat_scene.gd`
accounts for fled ships. `CampaignState` owns the re-engage delay.

**Tech Stack:** Godot 4, GDScript, the project's own test runner (`tests\run_tests.gd`).

**Spec:** `docs\superpowers\specs\2026-11-05-combat-ai-orders-design.md` (approved
2026-11-05). Read it before each task. Where it says "about", the value here is the
starting constant; keep it as a named, tunable `const`.

## Global Constraints

- Build on `main`, one commit per task, message ending with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never push.
- Match each file's style: tabs, typed GDScript, `# why` comments only.
- Run tests from the project root with the commands below. A clean run means no `FAIL`
  lines except the known `test_campaign_long_run_sim.gd` pirate-targeting flake (3-4 lines),
  and no `SCRIPT ERROR` in either log.
  ```powershell
  $godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
  Start-Process -FilePath $godot -ArgumentList '--headless','--path','.','--script','res://tests/run_tests.gd' -RedirectStandardOutput test_output.txt -RedirectStandardError test_error.txt -Wait -NoNewWindow
  Select-String -Path test_output.txt,test_error.txt -Pattern 'FAIL|SCRIPT ERROR'
  ```
- After adding a new `class_name` file, run one warm pass first:
  `Start-Process -FilePath $godot -ArgumentList '--headless','--editor','--path','.','--quit' -Wait -NoNewWindow`.
  Then revert the `.import` churn it causes (delete each changed `.import`, then
  `git checkout -- <files>`); never commit `.import` or CRLF-only noise.
- Register new test files in `tests\run_tests.gd`: synchronous `run()` scripts in the
  `test_scripts` array; async `run_async(tree)` scripts as their own block placed **after**
  the `test_ai_controller_targeting` block (it's sensitive to ordering).
- GDScript gotchas: a freed object fails any Object-typed parameter check, so functions that
  guard with `is_instance_valid` take untyped params; check `is_instance_valid(x)` before
  `x is T`; assign literals to typed arrays with `.assign()`.
- Edit `project.godot` with Python using `newline=''` so its line endings stay as they are.
- Plain ASCII in all new text.

## Review Focus

1. **A target freed mid-tick** (killed by an ally) while being scored, engaged or kited.
   Expected: no `SCRIPT ERROR`, the ship picks a new target next tick. (Test in Task 2.)
2. **Killing blow during the last spool tick.** Expected: a destroyed ship never jumps out
   and never counts as escaped. (Test in Task 3.)
3. **Every ship on one side jumps out in the same frame.** Expected: the battle resolves
   once, fled ships are counted once, and none of them roll the escape chance. (Test in
   Task 3.)
4. **A ship with only PD, or with every mount destroyed mid-fight**, under attack run, kite,
   Hold Position or Flee. Expected: no crash. PD-only ships still close to PD range, and
   unarmed ships follow the existing "can't engage" path. (Tests in Tasks 1 and 3.)
5. **Hull-edge range on big hulls** (capital radius 54). `WeaponMount.can_engage` and the
   standoff must agree, so a ship parked at standoff actually fires. Expected: at standoff
   against a capital, the mount can engage. (Test in Task 1.)

---

### Task 1: Ship movement smarts (PD role, hull-edge range, runs, kiting, spreading out)

**Files:**
- Create: `scripts\combat\combat_tactics.gd` (`class_name CombatTactics extends RefCounted`,
  static helpers only)
- Modify: `scripts\weapons\weapon.gd` (new export), `resources\weapons\pd_flak_turret.tres`,
  `resources\weapons\pd_laser_turret.tres`
- Modify: `scripts\weapons\weapon_mount.gd` (`can_engage`, `nearest_engageable`)
- Modify: `scripts\ship\ship.gd` (`engagement_distance`, `best_engagement_range`,
  `_engage`, new `ally_group`)
- Modify: `scripts\combat\combat_scene.gd` (set `ally_group` wherever `enemy_group` is set)
- Test: `tests\test_combat_tactics.gd` (sync), `tests\test_ship_tactics.gd` (async),
  update `tests\test_ship.gd` / `tests\test_weapon_resources.gd` where they assumed PD
  counts toward range or centre-distance range.

**Interfaces:**
- Produces:
  - `Weapon.point_defense: bool` (export, default `false`; `true` in both PD `.tres`).
  - `CombatTactics.range_weapons(weapons: Array[Weapon]) -> Array[Weapon]`: the non-PD
    weapons. If all are PD, it returns the input unchanged.
  - `CombatTactics.edge_distance(from: Vector2, target) -> float`: centre distance minus
    `target.get_hit_radius()` when the target has that method, floored at 0. Untyped
    `target`.
  - `CombatTactics.threat_range(weapons: Array[Weapon]) -> float`: the longest non-PD
    range, 0 if there is none.
  - `enum CombatTactics.Tactic { PARK, RUN }`, and
    `CombatTactics.tactic_for(weapons: Array[Weapon], turn_rate: float) -> Tactic`.
  - `enum CombatTactics.RunPhase { INBOUND, BREAK }`, and
    `CombatTactics.next_run_phase(phase: RunPhase, edge_dist: float, run_range: float, hull_floor: float) -> RunPhase`.
  - `CombatTactics.kite_standoff(own_standoff: float, own_reach: float, enemy_threat: float, own_speed: float, enemy_speed: float) -> float`.
  - `CombatTactics.approach_bearing(base_bearing: float, slot: int, count: int) -> float`.
  - `CombatTactics.separation_push(own_pos: Vector2, ally_positions: Array[Vector2], radius: float) -> Vector2`.
  - `Ship.ally_group: StringName` (export, default `&""`).
  - `Ship.engaging_target() -> Node2D`: the target `_engage` last ran against this tick, or
    null. Allies use it to find who is attacking the same target.

Constants (in `CombatTactics`, tunable):
`NARROW_ARC_DEGREES := 30.0`, `RUN_DPS_SHARE := 0.5`, `RUN_MIN_TURN_RATE := 3.0`,
`RUN_BREAK_FRACTION := 0.35`, `RUN_RESET_FRACTION := 0.9`, `KITE_MARGIN := 40.0`,
`SPREAD_STEP := 0.6` (radians), `SEPARATION_RADIUS_FACTOR := 2.5` (times own hit radius),
`SEPARATION_STRENGTH := 60.0` (px added to the station point at full push).

- [ ] **Step 1: Write the failing sync tests** in `tests\test_combat_tactics.gd`
  (`static func run() -> Array[String]`, same style as `tests\test_ai_controller_state.gd`).
  Build `Weapon.new()` instances in code. Tests:
  - `range_weapons_excludes_pd`: [railgun-like, PD] -> only the railgun;
    `range_weapons_all_pd_keeps_all`: [PD, PD] -> both.
  - `best_engagement_range_ignores_pd`: `Ship.best_engagement_range` over [mass driver 400,
    PD 150 with high dps] returns 400.
  - `edge_distance_subtracts_radius`: a target stub with `get_hit_radius()` 54 at 300 px
    -> 246; a stub without the method -> 300; at 20 px from a 54-radius target -> 0.
  - `tactic_run_for_agile_narrow`: [railgun 10 deg] at turn_rate 5.0 -> `RUN`;
    `tactic_park_for_slow_narrow`: same weapons at 1.0 -> `PARK`;
    `tactic_park_for_turrets`: [kinetic cannon 100 deg] at 5.0 -> `PARK`;
    `tactic_mixed_below_share`: a railgun (dps 8.75) plus a heavy beam (dps 16) at 5.0 ->
    `PARK`.
  - `run_phase_breaks_close`: INBOUND, edge 100, run_range 500, floor 70 -> BREAK
    (100 <= 0.35*500); `run_phase_resets_far`: BREAK, edge 460 -> INBOUND (>= 0.9*500);
    `run_phase_holds_between`: BREAK, edge 300 -> BREAK.
  - `kite_outranged`: own_standoff 200, reach 400, threat 220, speeds 280/90 -> 260;
    `kite_already_outside`: own_standoff 320, same otherwise -> 320;
    `kite_slower_does_not`: own_standoff 200, speeds 90/280 -> 200;
    `kite_outranging_enemy_does_not`: own_standoff 200, threat 450 -> 200;
    `kite_unarmed_target`: own_standoff 200, threat 0 -> 200.
  - `approach_bearing_spreads`: count 3, slots 0/1/2 around bearing 0 -> -0.6 / 0 / 0.6;
    count 1 -> unchanged.
  - `separation_none_when_clear`: an ally beyond the radius -> `Vector2.ZERO`;
    `separation_pushes_away`: an ally 10 px to the right, radius 60 -> x < 0.

- [ ] **Step 2: Register the file and run the tests.** Expected: these FAIL, or a parse
  error. Write `CombatTactics` stubs first so a parse error can't hang the run, then do the
  warm pass.

- [ ] **Step 3: Implement `CombatTactics`, `Weapon.point_defense`, and the two PD `.tres`.**
  - `tactic_for`: `RUN` when the dps share of weapons with `fire_arc_degrees <= NARROW_ARC_DEGREES`
    is >= `RUN_DPS_SHARE` over `range_weapons(weapons)`, and `turn_rate >= RUN_MIN_TURN_RATE`.
  - `next_run_phase`: INBOUND -> BREAK when `edge_dist <= maxf(run_range * RUN_BREAK_FRACTION, hull_floor)`.
    BREAK -> INBOUND when `edge_dist >= run_range * RUN_RESET_FRACTION`.
  - `kite_standoff`: when `enemy_threat > 0`, `kite_at := enemy_threat + KITE_MARGIN`,
    `kite_at < own_reach` and `own_speed >= enemy_speed`, return
    `maxf(own_standoff, kite_at)`. Otherwise return `own_standoff`.
  - `separation_push`: the sum over allies within `radius` of
    `(own - ally).normalized() * (1 - d / radius)`, skipping `d < 0.01`.

- [ ] **Step 4: Run the tests.** Expected: the `test_combat_tactics` checks PASS.

- [ ] **Step 5: Write the failing async ship tests** in `tests\test_ship_tactics.gd`.
  Use real ship scenes (`scenes\ship\ship_corvette.tscn`, `ship_capital.tscn`) and set
  weapons on mounts directly, as `tests\test_ai_controller_targeting.gd` does. Tests:
  - `edge_range_capital_engageable_at_standoff`: a corvette with a kinetic cannon
    (range 300), placed at `engagement_distance(capital)` from the capital's hull edge,
    facing it: `weapon_mounts[0].can_engage(capital)` is true. (Review Focus 5.)
  - `pd_only_ship_closes_to_pd_range`: a corvette with only a PD laser:
    `engagement_distance(target)` is about `150 * ENGAGE_RANGE_FRACTION` (not -1).
    (Review Focus 4.)
  - `run_ship_closes_then_breaks`: a corvette with a railgun attacking a stationary capital
    1000 px away. Over the physics ticks, the edge distance first drops below
    `0.35 * 500`, then rises above it again (it doesn't park).
  - `turret_ship_parks`: a corvette with a kinetic cannon, same setup. After 3 s, its edge
    distance is within 15% of `engagement_distance`.
  - `kiter_holds_outside_enemy_range`: a corvette with a mass driver (400, standoff 320)
    against a stationary corvette with a kinetic cannon (300). The kite point is 340, so
    after 3 s the edge distance is > 330 (without kiting it settles near 320).
  - `allies_spread_on_one_target`: three corvettes with the same `ally_group`, attacking
    one target. After 3 s, every pair is more than `2 * hit_radius` apart.

- [ ] **Step 6: Run them.** Expected: FAIL.

- [ ] **Step 7: Wire into `Ship` and `WeaponMount`.**
  - `WeaponMount.can_engage` and `nearest_engageable`: compare
    `CombatTactics.edge_distance(global_position, target)` against `weapon_range`.
  - `Ship.best_engagement_range`: run the dps-share loop over
    `CombatTactics.range_weapons(weapons)`.
  - `engagement_distance` keeps its contract (< 0 means can't engage) and returns an edge
    distance. `hull_floor` becomes `hit_radius + ENGAGE_HULL_GAP`, because the target's
    radius is already taken off by the edge measure.
  - `_engage` picks its movement by `CombatTactics.tactic_for(working weapons, engine.turn_rate)`:
    - **RUN:** keep a `_run_phase`. INBOUND steers at the target with `engine.steer_toward`.
      BREAK steers to `target_pos + away.rotated(side * PI / 3) * run_range`, where `side`
      is +1 or -1 from the parity of `get_instance_id()`.
    - **PARK:** today's `hold_station`. The standoff is
      `CombatTactics.kite_standoff(...)` when the target `is Ship`, otherwise
      `engagement_distance`. Use the target's `threat_range` over its working mounts, and
      `engine.effective_max_speed()` for both speeds. The bearing is
      `CombatTactics.approach_bearing(base, slot, count)`, where:
      - the attackers are the `ally_group` members whose `engaging_target()` is this target;
      - they are sorted by `get_instance_id()`, and `slot` is this ship's index among them;
      - `base` is the angle from the target to the attackers' centroid.

      Add `separation_push(...) * SEPARATION_STRENGTH` to the station point, over all live
      `ally_group` members.
  - Set `ally_group` in `combat_scene.gd` at the 3 places that set `enemy_group`, and in
    any test helper that spawns paired fleets and needs spreading.

- [ ] **Step 8: Run the full suite.** Expected: clean. Fix the older tests that assumed PD
  counted toward range or measured to the centre, and note each change in the commit
  message.

- [ ] **Step 9: Commit:** "Fight to hull and loadout: PD-free range, hull-edge range,
  attack runs, kiting, spacing".

---

### Task 2: Target scoring

**Files:**
- Modify: `scripts\combat\combat_tactics.gd` (scoring)
- Modify: `scripts\controllers\ai_controller.gd` (use scoring; the flee logic comes in
  Task 3)
- Modify: `scripts\ship\ship.gd` (idle `HOLD` uses scoring; the autofire primary is the
  engaged target)
- Test: add to `tests\test_combat_tactics.gd`, and add `tests\test_target_scoring_async.gd`
  (async)

**Interfaces:**
- Consumes: `CombatTactics.edge_distance`, `range_weapons`, `threat_range` (Task 1).
- Produces:
  - `CombatTactics.loadout_shield_bias(weapons: Array[Weapon]) -> float` in [-1, 1]: the
    dps-weighted mean of `(shield_mult - hull_mult - pierce_pct)`, clamped. Positive means
    the loadout prefers shields that are up.
  - `CombatTactics.narrow_share(weapons: Array[Weapon]) -> float`: the dps share of
    narrow-arc weapons (reuse it inside `tactic_for`).
  - `CombatTactics.score_target(own_pos: Vector2, own_rotation: float, turn_rate: float, shield_bias: float, narrow: float, target, is_current: bool) -> float`:
    higher is better. Untyped `target`; return `-INF` when it is invalid.
  - `CombatTactics.pick_target(ship, candidates: Array, current) -> Node2D`: the best
    scored valid candidate, or null.
  - `Ship.idle_target() -> Node2D`: what idle `HOLD` is currently engaging.

Score terms (constants, tunable):
- `-edge_distance / 100 * DIST_WEIGHT` (`1.0`).
- `-turn_seconds * narrow * TURN_WEIGHT` (`2.0`), where `turn_seconds = abs(angle to target) / turn_rate`.
- `shield_bias * (shield_ratio - 0.5) * 2 * MATCH_WEIGHT` (`1.5`). `shield_ratio` is the
  target's `current_shield / max_shield`, or 0 when max is 0.
- `(1 - hull_ratio) * LOW_HULL_WEIGHT * clampf(target_dps / REFERENCE_DPS, 0.25, 2.0)`, with
  `LOW_HULL_WEIGHT` `3.0`, `REFERENCE_DPS` `20.0`, and `target_dps` the target's non-PD
  working dps.
- `+STICKY_BONUS` (`2.0`) when `is_current`.
- `RETARGET_INTERVAL := 0.5` s: the AI and idle `HOLD` re-pick at most this often. In
  between, they keep the current target while it is valid.

- [ ] **Step 1: Write the failing sync tests** (target stubs: build `Ship` scenes in the
  async file, or plain stub objects exposing `global_position`, `get_hit_radius()`, `hull`
  and `shield` for the sync ones):
  - `score_prefers_closer`: two otherwise equal targets at 200 and 600 px: the nearer one
    scores higher.
  - `score_turn_matters_for_narrow`: two targets at equal distance, one dead ahead and one
    behind. With `narrow` 1.0, ahead wins. With `narrow` 0.0, the scores are equal.
  - `score_shield_match`: with `shield_bias` > 0, the shields-up target wins. With bias < 0,
    the shields-down target wins.
  - `score_low_hull_bonus`: an armed target at 20% hull beats the same at 100% hull.
  - `score_sticky_resists_small_gain`: the current target at 300 px beats a new one at
    250 px.
  - `shield_bias_signs`: [pulse laser] > 0; [railgun] < 0.

- [ ] **Step 2: Run them.** Expected: FAIL.

- [ ] **Step 3: Implement the scoring helpers.**

- [ ] **Step 4: Write the failing async tests** in `tests\test_target_scoring_async.gd`:
  - `ai_uses_score_not_nearest`: the AI ship has a railgun facing a near target behind it
    and a slightly farther one dead ahead. After the first pick, its `ATTACK_TARGET` is the
    one ahead.
  - `target_freed_mid_fight`: the AI is attacking A when A is freed (`queue_free`). Over the
    next 3 physics frames it ends up attacking B. The suite-wide `SCRIPT ERROR` grep
    covers the crash case. (Review Focus 1.)
  - `idle_hold_engages_scored_target`: a ship with the default idle `HOLD` engages the same
    target `pick_target` returns.

- [ ] **Step 5: Wire it in.**
  - `AIController` replaces `Ship.nearest_in_range` with `CombatTactics.pick_target` on a
    `RETARGET_INTERVAL` timer.
  - `Ship._process_hold` does the same and stores the result for `idle_target()`.
  - `Ship.pick_autofire_target` returns `idle_target()` for `HOLD` when it is valid and in
    `attack_range()`; otherwise it falls back to `nearest_in_range` as today.

- [ ] **Step 6: Run the full suite.** Expected: clean. `test_ai_controller_targeting`
  still expects the nearest target in its setup. Keep it passing by keeping that setup
  unambiguous, not by special-casing it.

- [ ] **Step 7: Commit:** "Score combat targets by range, facing, shield match and kill
  value".

---

### Task 3: Flee and Hold Position orders, AI flee, battle accounting

**Files:**
- Modify: `scripts\orders\order.gd` (`HOLD_POSITION`, `FLEE`)
- Modify: `scripts\ship\ship.gd` (order handling, spool, jump-out)
- Create: `scripts\vfx\flee_spool_bar.gd` (Node2D bar, added by `Ship` as a child)
- Modify: `scripts\controllers\ai_controller.gd` (flee decision; remove
  `State` / `next_state` / `retreat_hp_ratio`)
- Modify: `scripts\combat\combat_scene.gd` (battle end, survivors, Withdrew)
- Test: rewrite `tests\test_ai_controller_state.gd` (now flee-rule tests), add
  `tests\test_flee_async.gd`, extend `tests\test_combat_scene.gd`

**Interfaces:**
- Produces:
  - `Order.Type.HOLD_POSITION`, `Order.Type.FLEE`; `Order.hold_position() -> Order`,
    `Order.flee() -> Order`. Keep `Order.Type.RETREAT` and `Order.retreat()` (tests use
    them), but the AI stops issuing them.
  - `Ship.FLEE_SPOOL_TIME := {ShipType.Kind.CORVETTE: 6.0, ShipType.Kind.FREIGHTER: 6.0, ShipType.Kind.CAPITAL: 8.0}`.
  - `Ship.flee_progress() -> float` (0..1), `Ship.has_fled: bool`,
    `signal jumped_out(ship: Ship)`, `Ship.arena_rect: Rect2` (an empty rect means no
    clamping; `combat_scene` sets `Rect2(Vector2.ZERO, combat_camera.arena_size)`).
  - `AIController.FLEE_LOSS_FRACTION := {ShipType.Kind.CORVETTE: 0.65, ShipType.Kind.CAPITAL: 0.85}`,
    `AIController.UNARMED_FLEE_RANGE := 500.0`, and
    `static func should_flee(kind: ShipType.Kind, start_hp: float, current_hp: float, armed: bool, nearest_enemy_edge: float) -> bool`.

Behaviour to implement:
- `execute_order` resets the spool to 0 whenever the new order isn't `FLEE`. An order that
  replaces `FLEE` cancels it.
- **FLEE tick:**
  - `spool += delta`;
  - steer at full speed (`engine.steer_toward`) toward a point 500 px from the ship, in the
    direction away from the centroid of `enemy_group` ships within 800 px (or straight ahead
    when none), clamped inside `arena_rect` shrunk by 2 * `hit_radius`;
  - fire normally (no turning to aim);
  - when `spool >= FLEE_SPOOL_TIME[ship_type]` and the hull isn't destroyed, jump out.
- **Spool reset:** in `receive_damage` and `receive_weapon_damage`, any time damage reaches
  past shields (`overflow > 0`, or `total_raw > 0`, which includes pierce), set the spool
  to 0 while fleeing. The reset happens before any later spool tick.
- **Jump out:**
  - `has_fled = true`;
  - remove from every group;
  - `hide()`, disable collision, set `process_mode = PROCESS_MODE_DISABLED`;
  - spawn a short flash (an expanding, fading circle or a `CPUParticles2D` burst, freed when
    done);
  - emit `jumped_out`.

  Don't `queue_free`: the combat scene reads its state at report time.
- **HOLD_POSITION:**
  - the anchor is the position when the order is issued;
  - each tick, `engine.hold_station(pos, rot, face, anchor, delta)`, where `face` is the
    best `CombatTactics.pick_target` candidate within `attack_range()` (edge distance), or
    the current heading point when there is none;
  - autofire as for idle `HOLD`, but it never moves toward a target.
- **Flee spool bar:**
  - visible only while fleeing;
  - drawn with no rotation (reset `global_rotation = 0` each frame) at `hit_radius + 10`
    below the ship;
  - width `2 * hit_radius`, height 4;
  - orange `Color(1.0, 0.702, 0.278)` outline, with a fill of `flee_progress()`;
  - shown on own and enemy ships alike.
- **AIController:**
  - store `start_hp = ship.hull.current_hp` in `setup`. `_wire_ai` already runs after
    `_apply_fleet_data`, so this is the battle-start hull;
  - each tick, first evaluate `should_flee`, where `armed` is
    `ship.engagement_distance(any) >= 0`;
  - once it returns true, issue `Order.flee()` once and stop issuing orders (committed);
  - otherwise attack the Task 2 pick.
- **`should_flee`:**
  - not armed -> `nearest_enemy_edge <= UNARMED_FLEE_RANGE`;
  - armed -> `current_hp <= start_hp * (1 - FLEE_LOSS_FRACTION[kind])`;
  - `start_hp <= 0` -> false.

  Freighters have no mounts, so they always take the unarmed rule.
- **combat_scene:**
  - connect every ship's `jumped_out` to `_check_battle_end`;
  - `_is_active` also requires `not member.has_fled`;
  - when the player side loses and any player ship `has_fled`, show `"Withdrew"` instead of
    `"Defeat"`;
  - `_collect_survivor_data` gains an output `fled: Array[bool]` parallel to `speeds`;
  - `_roll_escapes` treats `fled[i] == true` as escaped without drawing a roll. Keep the
    rng draw order for the others, so seeded tests stay stable;
  - `fleet_commander.selected_ships`, `ships_in_rect` and `ship_at_point` skip ships with
    `has_fled`.

- [ ] **Step 1: Rewrite `tests\test_ai_controller_state.gd` as `should_flee` tests:**
  - `corvette_flees_after_65pct_of_start`: start 60, current 21 -> true; current 22 -> false;
  - `capital_flees_after_85pct`: start 220, current 33 -> true; current 34 -> false;
  - `damaged_arrival_does_not_flee`: corvette start 20, current 20 -> false;
  - `unarmed_flees_on_contact`: freighter, unarmed, enemy edge 499 -> true; 501 -> false;
  - `zero_start_never_flees`: start 0 -> false.

- [ ] **Step 2: Write the failing async tests** in `tests\test_flee_async.gd`:
  - `flee_completes_and_jumps_out`: a corvette under `Order.flee()` with no enemies has
    `has_fled` true by 6.5 s, is not in its group, and has emitted `jumped_out` once.
  - `hull_hit_resets_spool`: while fleeing at about 3 s, a `receive_weapon_damage` with
    zero shield left -> `flee_progress()` is 0.
  - `shield_absorbed_hit_keeps_spool`: full shield and a low-damage hit with no pierce ->
    the progress is unchanged.
  - `pierce_hit_resets_spool`: full shield, railgun (`pierce_pct` 0.25) -> the progress is 0.
  - `new_order_cancels_flee`: after 3 s of fleeing, `execute_order(Order.move_to(...))` ->
    the progress is 0 and the ship doesn't jump out at 6.5 s.
  - `killed_on_last_tick_never_jumps`: spool set just under the threshold, then the hull is
    destroyed in the same frame -> `jumped_out` is never emitted. (Review Focus 2.)
  - `hold_position_does_not_chase`: a ship under `Order.hold_position()` with an enemy
    600 px away moves less than 10 px in 3 s and turns its nose toward the enemy.
  - `hold_position_fires_in_range`: an enemy inside the weapon range takes damage while the
    ship holds.
  - `unarmed_hold_position_safe`: a ship with every mount destroyed under `HOLD_POSITION`
    and then `FLEE` produces no `SCRIPT ERROR`. (Review Focus 4.)

- [ ] **Step 3: Extend `tests\test_combat_scene.gd`:**
  - `enemy_all_flee_same_frame_is_victory_once`: force-complete the spools of every enemy
    in one frame -> `_show_result` runs once with `"Victory"`, and the reported enemy
    survivors include every fled ship with no rng draw for them. Use a seeded `escape_rng`
    and assert the rng state is unchanged. (Review Focus 3.)
  - `player_flee_shows_withdrew`: the last armed player ship jumps out -> the result label
    reads `"Withdrew"`.
  - `fled_player_ship_returns_with_state`: in a player win where one player ship fled with
    damage, that comp comes back with its damaged `current_hp`.

- [ ] **Step 4: Run them.** Expected: FAIL.

- [ ] **Step 5: Implement** everything under "Behaviour to implement".

- [ ] **Step 6: Run the full suite.** Expected: clean.

- [ ] **Step 7: Commit:** "Add Flee and Hold Position orders; AI flees by hull at battle
  start".

---

### Task 4: Order bar, hotkeys, campaign re-engage delay

**Files:**
- Create: `scenes\ui\order_bar.tscn`, `scripts\ui\order_bar.gd`
  (`class_name OrderBar extends Control`)
- Modify: `scenes\combat\combat_scene.tscn` (add `OrderBar` under `UILayer`),
  `scripts\combat\combat_scene.gd` (wire it)
- Modify: `scripts\controllers\fleet_commander.gd` (new order methods, signals)
- Modify: `project.godot` (input actions)
- Modify: `scripts\campaign\campaign_state.gd`, `scripts\campaign\campaign_scene.gd`,
  `scripts\campaign\jump_controller.gd`, `scripts\campaign\campaign_fleet_icon.gd`
- Test: `tests\test_order_bar.gd` (async, use `tests\ui_layout_check.gd`), extend
  `tests\test_fleet_commander.gd`, `tests\test_campaign_state.gd`, and the campaign scene
  test that covers the engage prompt

**Interfaces:**
- Consumes: `Order.hold_position()`, `Order.flee()`, `Ship.has_fled` (Task 3).
- Produces:
  - `FleetCommander.order_hold() -> void`, `FleetCommander.order_flee() -> void`,
    `FleetCommander.set_formation(type: Formation.Type) -> void`,
    `signal formation_changed(type: Formation.Type)`,
    `signal selection_changed(has_selection: bool)` (emitted whenever `selected_ships`
    changes, including the filter in `_issue_order`).
  - `OrderBar`: `signal hold_pressed`, `signal flee_pressed`,
    `signal formation_picked(type: Formation.Type)`,
    `func set_has_selection(value: bool) -> void`,
    `func show_formation(type: Formation.Type) -> void`.
  - Input actions `order_hold` (physical key H, keycode 72) and `order_flee` (physical key
    F, keycode 70). Use the same event format as the existing `formation_*` entries. Check
    that nothing else is bound to H or F first.
  - `CampaignState.REENGAGE_DELAY := 10.0`,
    `CampaignState.can_engage(fleet: CampaignFleet) -> bool`,
    `CampaignState.tick_reengage(delta: float) -> void`.

Behaviour:
- **Bar layout:** bottom centre: `Hold [H]`, `Flee [F]`, `Formation: <Name> ^`.
  - Names: NONE -> "Free", then Line, Wedge, Box, Circle.
  - The Formation button toggles a pop-up panel above it, with 5 buttons `Free 1` ..
    `Circle 5`. The active one is highlighted (`button_pressed`, in one `ButtonGroup`).
    Picking one emits `formation_picked` and closes the pop-up.
  - Hotkeys 1-5 keep working through `FleetCommander` and update the label via
    `formation_changed`.
  - Hold and Flee are disabled while nothing is selected.
  - The bar and pop-up backgrounds are `MOUSE_FILTER_STOP`.
  - Use the project theme; no per-node colour overrides unless the speed controls already
    do the same.
- **FleetCommander:**
  - `_unhandled_input` handles `order_hold` and `order_flee` by calling the methods;
  - `order_hold` issues `Order.hold_position()` to each valid, unfled selected ship;
    `order_flee` does the same with `Order.flee()`;
  - the existing formation hotkeys route through `set_formation`.
- **Re-engage delay:**
  - `resolve_engagement`: after settling, if the enemy fleet is still in `enemy_fleets` and
    the player fleet isn't destroyed, set `_reengage_block[enemy] = REENGAGE_DELAY`;
  - `tick_reengage` counts each entry down and drops it at 0, and also drops fleets no
    longer in `enemy_fleets`;
  - `campaign_scene._physics_process` calls it next to the other `tick_*` calls (game time,
    paused with the game);
  - `reset()` clears it;
  - gates:
    - `campaign_scene._trigger_arrival` ignores a `CampaignFleetIcon` whose fleet can't be
      engaged (no prompt, no pause);
    - `jump_controller.is_hostile_icon` returns false for a blocked fleet, so it neither
      catches a warp nor blocks jumping;
    - `campaign_fleet_icon._process_pirate` doesn't intercept a blocked player target.

- [ ] **Step 1: Write the failing tests:**
  - `test_fleet_commander`:
    - `order_hold_sets_hold_position`: two selected ships both get `HOLD_POSITION`;
    - `order_flee_skips_fled`: a fled ship in the selection gets no order;
    - `set_formation_emits`: `formation_changed` fires with `WEDGE`;
    - `selection_changed_on_clear`: a right click -> `selection_changed(false)`.
  - `test_order_bar`:
    - `buttons_disabled_without_selection`;
    - `formation_popup_opens_and_closes`: the button opens it, picking Box emits `BOX` and
      hides the pop-up;
    - `label_tracks_formation`: `show_formation(LINE)` -> "Formation: Line ^";
    - `bar_inside_viewport_and_stops_mouse`, using `ui_layout_check.gd`.
  - `test_campaign_state`:
    - `reengage_blocked_after_battle`: after `resolve_engagement` with enemy survivors,
      `can_engage(enemy)` is false;
    - `reengage_expires`: `tick_reengage(10.1)` -> true;
    - `reengage_other_fleet_unaffected`;
    - `reengage_cleared_on_reset`;
    - `destroyed_enemy_not_tracked`.
  - Campaign scene test, `blocked_fleet_no_prompt`: `_trigger_arrival` on a blocked fleet's
    icon leaves `engage_prompt.visible` false and the tree unpaused.

- [ ] **Step 2: Run them.** Expected: FAIL.

- [ ] **Step 3: Implement** the bar, the hotkeys, the `FleetCommander` methods, the scene
  wiring and the re-engage delay as described.

- [ ] **Step 4: Run the full suite.** Expected: clean. Also take one non-headless screenshot
  of the combat scene with the pop-up open, using the screenshot recipe in
  `carry_forward.md`. Save it under the scratchpad, look at it, and delete any
  `images.jpg.import` the warm pass created.

- [ ] **Step 5: Commit:** "Add combat order bar and hotkeys; delay re-engaging a fleet
  after battle".

---

## Final review

After Task 4, one whole-change review on the most capable model, against the spec and this
plan. Per the carry-forward, it must trace real bootstrap numbers: a campaign battle built
from the hand-written bootstrap comps in `campaign_scene.gd`, not only
`ShipType.new_composition()`. Also run one perf check: a 10 v 10 non-headless
combat (debug `AddFriend` / `AddEnemy`), with physics frame time well inside the 8 ms avg /
33 ms max bar. Then a user playtest pass on feel: runs, kiting, spacing and flee cost.
