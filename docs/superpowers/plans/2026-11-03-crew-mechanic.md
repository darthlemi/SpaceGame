# Crew Mechanic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make crew a real resource. Ships lose crew to damage, can't deploy or
get disabled when under-crewed, and are hired, paid, balanced, scuttled,
jettisoned and respawned through new UI.

**Architecture:** Crew is an int `"crew"` key on each `ship_compositions` dict.
All crew math (thresholds, transfers, balancing, hiring/desertion
distribution) lives in one pure static helper, `CrewRules`, so UI, combat and
NPC code share it. Combat tracks crew live on `Ship` and reports it back
through `combat_scene._collect_survivor_data`. New panels follow the existing
`Layout` VBox and ScrollContainer convention.

**Tech Stack:** Godot 4 / GDScript, custom headless test runner (`tests/run_tests.gd`).

**Spec:** `docs/superpowers/specs/2026-11-03-crew-mechanic-design.md`

## Global Constraints

- Every crew read goes through `CrewRules.crew_of(comp)`. A missing `"crew"`
  key means fully crewed. Missing `"deploy"` means true and missing
  `"flagship"` means false. The bootstrap dicts in
  `campaign_scene._bootstrap_default_campaign` lack these keys, and that must
  keep working.
- Thresholds round UP to whole crew, with float noise guarded (`0.3 * 40` is
  `12.000000000000002` in IEEE). The expected values are corvette deploy 4 /
  disable 2, freighter 2 / 1 and capital 12 / 4.
- Constants (tuning placeholders, exact values):
  - `CrewRules.DEPLOY_MIN_CREW_FRACTION = 0.3`
  - `CrewRules.DISABLE_CREW_FRACTION = 0.1`
  - `CrewRules.NPC_CREW_FLOOR = 1`
  - `CrewRules.CAPTURED_CREW_FRACTION = 0.2`
  - `BaseEconomy.CREW_POOL_CAP_FRACTION = 0.05`
  - `BaseEconomy.CREW_POOL_REGEN_RATE = 0.005`
  - `CampaignState.CREW_HIRE_COST = 40.0`
  - `CampaignState.WAGE_PER_CREW = 0.1`
  - `CampaignState.DESERTION_RATE = 0.2`
  - `CampaignState.PIRATE_CREW_REGEN = 1`
  - `CampaignState.RESPAWN_CREDIT_PENALTY = 0.25`
  - `ShipType.SHIP_PRICE = {CORVETTE: 400.0, FREIGHTER: 500.0, CAPITAL: 2000.0}`
- `CampaignState.credits` never goes negative.
- New `class_name`s need a warm pass before `--script` runs:
  `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --editor --quit --path .`
  Then revert the CRLF-only `.import`/`project.godot` churn it causes. Delete
  each listed file, then `git checkout -- <files>`; the list comes from
  `git status --porcelain`.
- Assigning a literal to a typed array through the untyped autoload ref
  (`campaign_state.x = [...]`) is a silent SCRIPT ERROR. Use `.assign()`.
- Panels: `Layout` VBoxContainer, variable lists in a ScrollContainer,
  checked with `tests/ui_layout_check.gd`. Fresh panels need
  `await tree.process_frame` before layout checks.
- New scene-based or autoload-touching tests are `run_async` files,
  registered in `tests/run_tests.gd` with `load()` (not `preload()`) after
  the existing campaign tests. Do NOT register anything before
  `test_ai_controller_targeting.gd` (documented frame-timing fragility).
- Full suite command. The non-console exe drops stdout, so it's redirected
  to a log:
  `Start-Process -FilePath "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" -ArgumentList "--headless","--path",".","--script","res://tests/run_tests.gd" -RedirectStandardOutput "$env:TEMP\sg_tests.log" -Wait -NoNewWindow`
  then read `$env:TEMP\sg_tests.log`. Baseline: only the known
  `test_campaign_long_run_sim.gd` pirate-targeting flake (5-6 failures). Any
  other FAIL line is a regression.
- Commit after each task on the current branch, ending messages with the
  `Co-Authored-By` trailer.

## Review Focus

1. A bootstrap composition with no `crew`/`deploy`/`flagship` keys must be
   treated as fully crewed, deployable and flagship-assignable. Test in
   Task 1.
2. When both sides' last active ships are disabled or destroyed in the same
   check, the player loses and the battle never stalls. Test in Task 3.
3. Desertion with 0 credits and only the flagship crewed must never take the
   flagship below its floor, and credits stay >= 0. Test in Task 5.
4. Scuttling when remaining cargo would exceed capacity is refused until
   enough is jettisoned. Test in Task 7.
5. Respawning with fewer credits than any ship price still offers the free
   corvette, and credits never go negative after the penalty. Test in Task 8.

---

### Task 1: CrewRules and the crew data model

**Files:**
- Create: `scripts/campaign/crew_rules.gd`
- Modify: `scripts/ship/ship_type.gd` (`new_composition`, add `SHIP_PRICE`)
- Modify: `scripts/campaign/campaign_fleet.gd` (`crew_total`, `travel_speed`, flagship helpers)
- Modify: `scripts/campaign/campaign_scene.gd` (`_bootstrap_default_campaign`: call `player.ensure_flagship()`)
- Test: `tests/test_crew_rules.gd` (new, sync `run()`, register in the sync list), `tests/test_campaign_fleet.gd`

**Interfaces:**
- Produces (`class_name CrewRules extends RefCounted`, all `static`):
  - `complement(comp: Dictionary) -> int` returns `ShipType.crew_for(ShipType.kind_of(comp))`
  - `crew_of(comp: Dictionary) -> int` returns the complement when the key is missing
  - `set_crew(comp: Dictionary, value: int) -> void` clamps to 0..complement
  - `crew_fraction(comp: Dictionary) -> float`
  - `deploy_min_for(complement: int) -> int` and `disable_threshold_for(complement: int) -> int`
  - `wants_deploy(comp) -> bool` and `is_flagship(comp) -> bool`
  - `deploy_indices(comps: Array[Dictionary]) -> Array[int]`: ships with
    `wants_deploy` and crew >= the deploy minimum. If that's empty: the
    highest-crew ship that `wants_deploy`. If none wants to deploy: the
    flagship, else the highest-crew ship. Returns empty only for an empty
    fleet.
  - `free_berths(comps: Array[Dictionary]) -> int`
  - `add_crew(comps: Array[Dictionary], amount: int) -> int`: one at a time
    to the lowest `crew_fraction` ship with a free berth. Returns the number
    added.
  - `remove_crew(comps: Array[Dictionary], amount: int, protect_index: int, protect_floor: int) -> int`:
    one at a time from the lowest-fraction non-protected ship with crew > 0,
    then the protected ship down to `protect_floor`. Returns the number
    removed.
  - `set_ship_crew(comps: Array[Dictionary], index: int, target: int) -> void`:
    zero-sum. Raising takes from the highest-fraction other ship first,
    lowering gives to the lowest-fraction other ship with room first. The
    target clamps to what is achievable.
  - `balance(comps: Array[Dictionary]) -> void`: equal fraction as near as
    integers allow. Leftover crew go to the flagship, then by class size
    (capital > corvette > freighter), then by index.
- Produces (`CampaignFleet`): `crew_total() -> int` (actual crew),
  `crew_capacity() -> int`, `has_uncrewed_ship() -> bool`,
  `flagship_index() -> int` (-1 if none), `set_flagship(index: int) -> void`
  (clears the others), `ensure_flagship() -> void` (if none, flags the
  largest class; ties go to the lowest index).
- Produces: `ShipType.new_composition()` includes `"crew": crew_for(kind)`.
  `ShipType.SHIP_PRICE` per the constraints.

- [ ] **Step 1: Write failing tests** in `tests/test_crew_rules.gd`:
  - `deploy_min_for`: 12->4, 6->2, 40->12. `disable_threshold_for`: 12->2, 6->1, 40->4.
  - `crew_of({"ship_type": CAPITAL})` == 40 (missing key). `set_crew(comp, 99)` gives 40, and `-3` gives 0.
  - `deploy_indices`:
    - [corvette 12, corvette 2] -> [0]
    - [corvette 2 deploy, capital 5 deploy] -> [1] (none meets the min, so the highest-crew wanted ship)
    - all `deploy:false` with flagship at index 1 -> [1]
    - [] -> []
  - `add_crew([corvette 6, freighter 6], 10)` returns 6 and gives corvette 12 / freighter 6.
  - `remove_crew([capital 20 flagship, corvette 6], 30, 0, 12)` returns 14 and leaves corvette 0 / capital 12.
  - `set_ship_crew([corvette 4, capital 40, freighter 6], 0, 12)` leaves corvette 12 and the total unchanged at 50.
  - `balance([capital 40, corvette 0, freighter 0])`: every ship within one crew of 40/58 of its complement, total 40.
  - A bootstrap-style dict with no crew keys passes `wants_deploy` and isn't
    a flagship. Then `CampaignFleet.ensure_flagship()` on [corvette, capital,
    freighter] bootstrap dicts flags index 1. (Review Focus 1.)
- [ ] **Step 2:** Add `test_campaign_fleet.gd` cases:
  - `crew_total()` == 18 for [corvette crew 12, freighter crew 6 missing-key].
  - `crew_capacity()` == 18.
  - `travel_speed()` == `speed * EMPTY_FUEL_SPEED_FACTOR` when fuel > 0 and one ship has crew 0.
  - The same value (not squared) when fuel is 0 and a ship is uncrewed.
  Update the existing `crew_total` case if its expectation changes.
- [ ] **Step 3:** Warm pass, run the suite, confirm the new cases FAIL (missing class/functions).
- [ ] **Step 4:** Implement the interfaces above. Guard the rounding with
  `ceili(fraction * complement - 0.0001)`.
- [ ] **Step 5:** Run the suite. New cases pass and only the baseline flake remains.
- [ ] **Step 6:** Commit `Add CrewRules and per-ship crew data`.

### Task 2: Live crew, crew loss and the disabled state on Ship

**Files:**
- Modify: `scripts/ship/ship.gd`
- Test: `tests/test_ship_crew.gd` (new `run_async`, registered with `load()` after `test_campaign_state` async)

**Interfaces:**
- Consumes: `CrewRules.disable_threshold_for(complement)`.
- Produces (`Ship`):
  - `signal disabled`
  - `var crew: float = 0.0`
  - `var crew_complement: int = 0`. 0 means crew isn't tracked: never
    disabled. This covers drones, non-campaign battles and `AddFriend` ships.
  - `func setup_crew(crew_count: int, complement: int, floor_count: int) -> void`.
    It must be called after hull hp is applied, because it snapshots
    `hull.current_hp`.
  - `func is_disabled() -> bool`
  - `const DISABLED_DRIFT_DECEL := 20.0`

- [ ] **Step 1: Write failing tests** (instantiate
  `scenes/ship/ship_corvette.tscn`, add it to the tree, await a frame, then
  `setup_crew(12, 12, 0)`):
  - After `hull.apply_damage(hull.current_hp * 0.5)`: `crew` is about 6.0.
  - Then damaging the hull to 10% of its original hp: `is_disabled()` is true
    and `disabled` was emitted exactly once (count with a lambda), even after
    further damage.
  - A disabled ship's `_physics_process` fires no weapon. Put an enemy ship
    in its `enemy_group` 50px directly ahead (+X, inside every fire arc).
    Control: the same setup without disabling must show a cooldown > 0, so
    the test can't pass vacuously. Await two physics frames, then assert
    every mount's `cooldown_remaining == 0.0`. `WeaponMount.try_fire` sets
    the cooldown, so a fired weapon would show one.
  - With `setup_crew(12, 12, 1)`: heavy damage leaves `crew >= 1`.
  - With `crew_complement == 0` (no setup): heavy damage never disables.
- [ ] **Step 2:** Run, confirm FAIL.
- [ ] **Step 3:** Implement:
  - Connect `hull.damaged` in `_ready`. On damage:
    `crew = max(crew_floor, crew * remaining / _last_hull_hp)` when
    `_last_hull_hp > 0`, then store `remaining`.
  - Emit `disabled` once when the crew drops below the threshold.
  - In `_physics_process`, when disabled: `velocity.move_toward(Vector2.ZERO, DISABLED_DRIFT_DECEL * delta)`,
    then `move_and_slide()` and return before orders and weapons.
- [ ] **Step 4:** Run the suite. Pass, baseline flake only.
- [ ] **Step 5:** Commit `Track crew on ships in combat and disable under-crewed ships`.

### Task 3: Deployment, battle end and crew results in CombatScene

**Files:**
- Modify: `scripts/combat/combat_scene.gd`
- Modify: `scripts/campaign/campaign_state.gd` (`resolve_engagement`, `pending_captured_crew`, `reset`)
- Test: `tests/test_combat_scene.gd`, `tests/test_campaign_state.gd`

**Interfaces:**
- Consumes: `CrewRules.deploy_indices`, `CrewRules.crew_of`,
  `CrewRules.complement`, `CrewRules.balance`, `CrewRules.NPC_CREW_FLOOR`,
  `CrewRules.CAPTURED_CREW_FRACTION`, `Ship.setup_crew`, `Ship.disabled`,
  `Ship.is_disabled`, `CampaignFleet.ensure_flagship`.
- Produces:
  - `CampaignState.resolve_engagement(player_survivors: Array[Dictionary], enemy_survivors: Array[Dictionary], player_won: bool = false, captured_crew: int = 0) -> void`.
    The enemy is defeated when `player_won or is_destroyed()`. On defeat:
    erase it, apply reputation loss, and set `pending_loot_fleet` when
    `cargo_total() > 0 or captured_crew > 0`. Otherwise `CrewRules.balance`
    the enemy comps. Always call `player_fleet.ensure_flagship()` when it
    has ships.
  - `CampaignState.pending_captured_crew: int = 0` (cleared by `reset`).
  - Survivor dicts gain `"crew"` (`roundi(ship.crew)`), plus `"deploy"` and
    `"flagship"` copied from the original comp.

- [ ] **Step 1: Write failing tests** in `test_combat_scene.gd`'s
  campaign-driven section:
  - **Deployment.** Player fleet: [corvette crew 12, corvette crew 2 with
    `deploy:true`, freighter crew 6 with `deploy:false`]. Expect 1 player
    ship spawned. Win the battle (destroy every enemy hull). The player
    fleet then has 3 comps: the fought ship with its crew, and the two
    held-back comps unchanged.
  - **Disabled ending.** Disable every enemy ship by heavy damage short of
    destruction (set `hull.current_hp` low via `apply_damage` so crew falls
    under the threshold). Result text is "Victory". The enemy fleet is
    removed from `enemy_fleets`. `pending_captured_crew == floori(0.2 * <crew on the disabled enemies>)`.
  - **Mutual knockout (Review Focus 2).** Disable all player ships and all
    enemy ships before any check fires (connect after setting state, or call
    the end check once). The result is "Defeat".
  - **Defeat with held-back ships.** All deployed player ships are destroyed
    and one is held back. After `_report_to_campaign`, the player fleet
    holds exactly the held-back comp, and the scene goes to the campaign,
    not game over.
  - **Enemy floor.** An enemy ship spawned from data has `crew_floor == 1`
    and the player ship has 0.
- [ ] **Step 2:** `test_campaign_state.gd`:
  - `resolve_engagement(player, [enemy comp with hp], true, 3)`: the enemy is
    removed, `pending_loot_fleet == enemy` and `pending_captured_crew == 3`.
  - The legacy 2-arg call still works (existing assertions unchanged).
- [ ] **Step 3:** Run, confirm FAIL.
- [ ] **Step 4:** Implement:
  - Store `_player_spawned_indices` and `_enemy_spawned_indices` from
    `CrewRules.deploy_indices`. Spawn only those.
  - `_apply_fleet_data` maps ship i to comp `indices[i]` and calls
    `setup_crew(crew_of, complement, floor)`, with the floor at 0 for the
    player and `NPC_CREW_FLOOR` for the enemy.
  - Replace the end check with `_check_battle_end()`, called from both the
    `hull.destroyed` and `disabled` handlers. A ship counts as active when it
    is valid, not queued for deletion and not disabled. The player is checked
    first: 0 active players means Defeat, else 0 active enemies means
    Victory.
  - `_report_to_campaign`:
    - Player: survivors are the surviving spawned ships (disabled ones are
      kept only if the player won) plus the un-spawned comps
      (`duplicate(true)`).
    - Enemy on a player win: `[]`. Captured crew is
      `floori(CAPTURED_CREW_FRACTION * (crew on disabled enemy ships + crew of held-back enemy comps))`.
    - Enemy on a player loss: surviving spawned ships, disabled included,
      plus the held-back comps.
    - Debug `AddFriend`/`AddEnemy` ships beyond the index list keep today's
      empty-orig behavior.
- [ ] **Step 5:** Run the suite. Pass, baseline flake only.
- [ ] **Step 6:** Commit `Deploy by crew, end battles on disabled fleets, report crew back`.

### Task 4: Captured crew in LootPanel

**Files:**
- Modify: `scripts/campaign/loot_panel.gd`, `scripts/campaign/campaign_scene.gd` (pending loot block in `_ready`)
- Test: `tests/test_loot_panel.gd`

**Interfaces:**
- Consumes: `CampaignState.pending_captured_crew`, `CrewRules.add_crew`, `CrewRules.free_berths`.
- Produces: `LootPanel.open_for(defeated_fleet: CampaignFleet, player_fleet: CampaignFleet, captured_crew: int = 0) -> void`;
  `LootPanel.crew_take_button: Button` (null when `captured_crew == 0`).

- [ ] **Step 1: Write failing tests:**
  - `open_for(fleet_no_cargo, player_with_3_free_berths, 5)` shows a crew
    row. Pressing take adds 3 crew to the player and leaves 2 available.
    The button is disabled at 0 free berths.
  - With `captured_crew = 0`, no crew row appears (existing cargo cases
    unchanged).
- [ ] **Step 2:** Run, confirm FAIL.
- [ ] **Step 3:** Implement the crew row: label `Crew  available:%d`, with a
  "Take" button that takes `min(available, free_berths)` via `add_crew`.
  In `campaign_scene._ready`, pass `CampaignState.pending_captured_crew`,
  then reset it to 0.
- [ ] **Step 4:** Run the suite. Pass.
- [ ] **Step 5:** Commit `Offer captured crew in the loot panel`.

### Task 5: Base hire pools, hiring, wages and desertion

**Files:**
- Modify: `scripts/campaign/base_economy.gd`, `scripts/campaign/campaign_state.gd`, `scripts/campaign/campaign_scene.gd` (bootstrap pools)
- Test: `tests/test_base_economy.gd`, `tests/test_campaign_state.gd`

**Interfaces:**
- Produces:
  - `BaseEconomy.crew_pool: float = 0.0`, plus `CREW_POOL_CAP_FRACTION` and
    `CREW_POOL_REGEN_RATE`. In `tick()`, after `_tick_population`:
    `crew_pool = min(population * CAP, crew_pool + population * REGEN)`.
    Also `crew_pool_cap() -> float`.
  - `CampaignState.flagship_floor(fleet: CampaignFleet) -> int`: the
    flagship's `deploy_min_for(complement)`, or 0 when there's no flagship.
  - `CampaignState.wage_bill(fleet: CampaignFleet) -> float`:
    `WAGE_PER_CREW * (crew_total - min(flagship crew, flagship_floor))`.
  - `CampaignState.pay_wages() -> void`, called first in each
    `tick_economy` iteration. When the bill can't be paid:
    - `paid = floori(credits / WAGE_PER_CREW)` and
      `credits -= paid * WAGE_PER_CREW` (credits never go negative).
    - `deserters = clampi(maxi(1, roundi(unpaid * DESERTION_RATE)), 0, unpaid)`.
    - Remove the deserters via `CrewRules.remove_crew(comps, deserters, flagship_index, flagship_floor)`.
  - `CampaignState.hire_crew(economy: BaseEconomy, fleet: CampaignFleet, count: int) -> bool`:
    fails when `count < 1`, `count > floori(crew_pool)`, `count > free_berths`
    or `credits < count * CREW_HIRE_COST`. On success, deduct the credits and
    the pool, then `add_crew`.
  - Bootstrap: every economy's `crew_pool = crew_pool_cap()` after
    population is seeded (my call: hiring is possible from the start).

- [ ] **Step 1: Write failing tests:**
  - BaseEconomy with population 1000 and pool 0: one `tick()` gives a pool of 5.0. Many ticks cap it at 50.0.
  - `hire_crew`:
    - Succeeds for 3 with pool 10, 3 free berths and 500 credits. Credits fall by 120 and the pool by 3.
    - Fails for 4 (berths), for 11 (pool) and when credits are 100 for 3.
  - `wage_bill` on [capital 40 flagship, corvette 12] is `0.1 * (52 - 12)` = 4.0.
  - `pay_wages` with credits 1.0 and that fleet:
    - credits end at 0.0 (10 paid).
    - deserters = `roundi(30 * 0.2)` = 6, taken from the corvette first.
  - **Review Focus 3.** Credits 0, fleet [capital 12 flagship, corvette 0]:
    `pay_wages` 20 times leaves capital crew at 12 and credits at 0.
- [ ] **Step 2:** Run, confirm FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the suite. Check that the existing economy and
  long-run sim results are unchanged apart from the baseline flake.
- [ ] **Step 5:** Commit `Add base crew pools, hiring, wages and desertion`.

### Task 6: Fleet Management panel and status bar

**Files:**
- Create: `scenes/campaign/fleet_management_panel.tscn`, `scripts/campaign/fleet_management_panel.gd`
- Modify: `scenes/ui/fleet_status_bar.tscn`, `scripts/ui/fleet_status_bar.gd`, `scenes/campaign/campaign_scene.tscn`, `scripts/campaign/campaign_scene.gd`
- Test: `tests/test_fleet_management_panel.gd` (new `run_async`, `load()`), `tests/test_campaign_scene_trading.gd` (status bar label/layout)

**Interfaces:**
- Consumes: `CrewRules.*`, `CampaignState.hire_crew`, `wage_bill`,
  `CREW_HIRE_COST`, `CampaignFleet.set_flagship`.
- Produces (`class_name FleetManagementPanel extends Control`):
  - Geometry: the dock sub-panel slot, x 652-1152 and y 140-640, the same
    as RepairPanel.
  - `open_for(fleet: CampaignFleet, docked_economy: BaseEconomy) -> void`,
    where `docked_economy` is null when not docked. Also `close()` and
    `refresh()`.
  - Nodes: `header_label: Label`, `rows_container: VBoxContainer` (inside
    `RowsScroll`), `balance_button`, `close_button`, `hire_row: Control`
    (hidden when not docked), `hire_count: SpinBox`, `hire_button`.
  - Per row (in order, exposed via a `rows: Array[Dictionary]` with keys
    `flagship_button`, `label`, `slider`, `count_label`, `deploy_check`):
    - Flagship button. It's disabled on the current flagship.
    - Label `"%s %d"` (class name, 1-based index).
    - `HSlider` with range 0..complement and step 1.
    - Count label `"%d/%d"` plus `"(min %d)"`.
    - `CheckBox`. When under the minimum its text is "Too few"; otherwise it
      reads "Deploy" and toggles `comp["deploy"]`.
  - Header text: `"Crew %d / %d   Wages %.1f cr/tick   Credits %d"`.
  - `FleetStatusBar`: `fleet_button: Button` (text "Fleet"). The crew label
    becomes `"Crew: %d/%d (-%.1f cr/tick)"`.
  - `campaign_scene`:
    - The Fleet button opens the panel, closing the dock sub-panels first.
      It passes `_economy_for_base(_docked_base)` when docked and pauses the
      tree.
    - Close unpauses only when not docked.
    - `_unhandled_input` ignores map clicks while the panel is visible.

- [ ] **Step 1: Write failing tests:**
  - `open_for` with [corvette 6, capital 40 flagship, freighter 6] and no
    economy:
    - 3 rows, and `hire_row` hidden.
    - Setting row 0's slider to 12 leaves corvette 12 and the total 52.
  - Balance makes every ship's fraction within one crew of equal.
  - With corvette crew 2, row 0's deploy check is disabled with text "Too
    few". Toggling the freighter's check sets `comp["deploy"] == false`.
  - Pressing row 2's flagship button: `flagship_index() == 2`, and row 2's
    button becomes disabled.
  - Docked with a pool-10 economy and 500 credits, with the corvette at 6:
    `hire_row` is visible. Hire with count 3 succeeds and the header updates.
  - `ui_layout_check` passes on the open panel at the docked state.
  - Status bar: the crew label matches `"Crew: %d/%d (-%.1f cr/tick)"`.
    `fleet_button` exists and the bar passes the existing layout check.
- [ ] **Step 2:** Run, confirm FAIL.
- [ ] **Step 3:** Implement.
  - Guard slider feedback: setting values inside `refresh()` must not
    re-enter `set_ship_crew`. Use a `_refreshing` flag or
    `set_value_no_signal`.
- [ ] **Step 4:** Warm pass (new class_name), then run the suite. Pass.
- [ ] **Step 5:** Commit `Add Fleet Management panel with crew sliders, balance, flagship, deploy and hiring`.

### Task 7: Scuttle and Jettison

**Files:**
- Create: `scenes/campaign/jettison_panel.tscn`, `scripts/campaign/jettison_panel.gd`
- Modify: `scripts/campaign/campaign_state.gd`, `scripts/campaign/fleet_management_panel.gd` / `.tscn`
- Test: `tests/test_campaign_state.gd`, `tests/test_jettison_panel.gd` (new `run_async`, `load()`), `tests/test_fleet_management_panel.gd`

**Interfaces:**
- Produces (`CampaignState`):
  - `scuttle_check(fleet: CampaignFleet, index: int) -> Dictionary` with
    keys `allowed: bool`, `crew_lost: int`, `cargo_overflow: float` and
    `reason: String`.
    - `allowed` is false for the flagship (reason "Flagship") and for the
      last ship (reason "Last ship").
    - `crew_lost = max(0, ship crew - free berths on the other ships)`.
    - `cargo_overflow = max(0, cargo_total - capacity_without_ship)`.
  - `scuttle_ship(fleet: CampaignFleet, index: int) -> bool`. It refuses
    when not allowed or when `cargo_overflow > 0`. Otherwise it moves the
    crew via `add_crew` to the others, removes the comp and calls
    `ensure_flagship()`.
  - `jettison(fleet: CampaignFleet, cargo_amounts: Dictionary, part_indices: Array[int], crew_by_ship: Dictionary) -> void`.
    - Amounts are clamped to what's held.
    - Parts are removed by descending index.
    - Flagship crew can't go below `flagship_floor`.
- Produces (`class_name JettisonPanel extends Control`, a child overlay of
  FleetManagementPanel with the same rect):
  - `signal finished(confirmed: bool)`
  - `open_for(fleet: CampaignFleet, required_cargo: float) -> void`
  - Rows, each with a slider over 0..held: one per held commodity, one
    `CheckBox` per part and one per ship for crew.
  - `confirm_button` is disabled while selected cargo + parts <
    `required_cargo`. `cancel_button`.
- Produces (FleetManagementPanel): a per-row `scuttle_button` and a
  panel-level `jettison_button`. Scuttle shows an inline confirm with
  `"Scuttle %s? Lost: %d crew, %.1f cargo"`.
  - If `cargo_overflow > 0`, confirming opens JettisonPanel with
    `required_cargo = cargo_overflow`.
  - When it finishes confirmed, scuttle runs. When cancelled, nothing
    changes.

- [ ] **Step 1: Write failing tests:**
  - Fleet [capital 40 flagship, freighter 6], cargo 70 (capacity 80, 20
    without the freighter):
    - `scuttle_check(1)` gives `cargo_overflow == 50` and `crew_lost == 6`
      (the capital is full).
    - `scuttle_ship(1)` returns false (Review Focus 4).
    - After `jettison(fleet, {ORE: 50}, [], {})`, `scuttle_ship(1)` returns
      true, the fleet has 1 ship and the crew total is 40.
  - `scuttle_check(0)` is not allowed, with reason "Flagship".
  - `jettison` crew of `{0: 40}` on a capital flagship leaves 12.
  - JettisonPanel: with `required_cargo` 5, confirm stays disabled until
    sliders total >= 5. Then confirming applies `jettison` and emits
    `finished(true)`.
  - FleetManagementPanel: on the overflow fleet, pressing the freighter's
    scuttle and then confirm makes the JettisonPanel visible.
- [ ] **Step 2:** Run, confirm FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Warm pass, then run the suite. Pass.
- [ ] **Step 5:** Commit `Add scuttle and jettison`.

### Task 8: Respawn instead of game over

**Files:**
- Create: `scenes/campaign/respawn_panel.tscn`, `scripts/campaign/respawn_panel.gd`
- Modify: `scripts/campaign/campaign_state.gd`, `scripts/combat/combat_scene.gd` (`_report_to_campaign`), `scripts/campaign/campaign_scene.gd`, `scenes/campaign/campaign_scene.tscn`
- Test: `tests/test_campaign_state.gd`, `tests/test_respawn_panel.gd` (new `run_async`, `load()`), `tests/test_combat_scene.gd`

**Interfaces:**
- Produces (`CampaignState`):
  - `pending_respawn: bool = false` (cleared by `reset`)
  - `begin_respawn() -> void`:
    - `credits = max(0.0, credits * (1.0 - RESPAWN_CREDIT_PENALTY))`
    - clears `cargo` and `part_inventory`, sets `ship_compositions = []`
    - sets `pending_respawn = true`
    - Reputation and fines are untouched.
  - `complete_respawn(kind: ShipType.Kind, buy: bool) -> bool`:
    - `buy` false forces a CORVETTE at no cost.
    - `buy` true fails when `credits < SHIP_PRICE[kind]`.
    - The new comp gets crew = its deploy minimum and `flagship: true`.
    - Clears `pending_respawn`.
- `combat_scene._report_to_campaign`: when the player fleet is empty after
  resolve, call `begin_respawn()` and go to the campaign scene. The
  `game_over.tscn` path is no longer reached from combat; the scene and its
  test stay.
- `campaign_scene._ready`: when `pending_respawn`, set
  `player_fleet.position = HOME_BASE_POSITION` before spawning the icon.
  Then open the RespawnPanel and pause. On finish, unpause.
- Produces (`class_name RespawnPanel extends Control`, overview slot x
  316-636, y 140-640):
  - `signal finished`
  - `open_for() -> void`
  - `free_button: Button`
  - `buy_buttons: Dictionary` (Kind -> Button, text `"Buy %s (%d cr)"`,
    disabled when unaffordable)

- [ ] **Step 1: Write failing tests:**
  - With credits 400, faction fine 150 and reputation 30, `begin_respawn()`
    leaves credits 300, cargo `{}`, parts `[]`, 0 ships, and fine and
    reputation unchanged.
  - `complete_respawn(CAPITAL, true)` at 300 credits returns false.
    `complete_respawn(CORVETTE, false)` returns true: 1 corvette, crew 4,
    flagship, credits still 300.
  - **Review Focus 5.** Credits 10: `begin_respawn()` gives 7.5. Every buy
    button is disabled and `free_button` is enabled. Pressing it emits
    `finished`.
  - Combat: a defeat with every player ship destroyed and none held back
    sets `pending_respawn` and does not change to `game_over.tscn`. Assert
    on `CampaignState` after `_report_to_campaign`.
- [ ] **Step 2:** Run, confirm FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Warm pass, then run the suite. Pass.
- [ ] **Step 5:** Commit `Respawn at home base instead of game over`.

### Task 9: NPC crew rules

**Files:**
- Modify: `scripts/campaign/campaign_state.gd` (`_resolve_skirmish`, `tick_economy`)
- Test: `tests/test_campaign_state.gd`

**Interfaces:**
- Consumes: `CrewRules.add_crew`, `CrewRules.balance`, `CrewRules.NPC_CREW_FLOOR`, `BaseEconomy.crew_pool`.
- Produces: `CampaignState._refill_npc_crew() -> void`, called in each
  `tick_economy` iteration after the faction economies tick.
  - Dominion and Freehold fleets: `add_crew` up to `floori(faction.economy.crew_pool)`,
    deducting what was added from the pool.
  - Pirate fleets: `add_crew(comps, PIRATE_CREW_REGEN)` each.
  - Then `balance` each refilled fleet.
- `_resolve_skirmish`: winner comps get
  `crew = max(NPC_CREW_FLOOR, roundi(crew * (1 - winner_damage_fraction)))`,
  then `balance`.

- [ ] **Step 1: Write failing tests:**
  - Skirmish winner [corvette 12] with damage fraction 0.5 ends at crew 6.
    A fraction of 1.0 ends at crew 1 (the floor).
  - Dominion fleet [corvette 2], faction pool 5.0: `_refill_npc_crew()` puts
    crew at 7 and the pool at 0.0.
  - Pirate fleet [corvette 2]: after `_refill_npc_crew()` its crew is 3.
- [ ] **Step 2:** Run, confirm FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the suite. Pass, baseline flake only, and the long-run
  sim is no worse than baseline.
- [ ] **Step 5:** Commit `Apply crew rules to NPC skirmishes, refill and pirate regen`.
