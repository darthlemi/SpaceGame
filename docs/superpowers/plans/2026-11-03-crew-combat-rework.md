# Crew Combat Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace disabled ships and stalemates with crew efficiency,
post-battle escape rolls and ship capture. Rework the loot window around
captured ships and crew. Make every credit value a whole number.

**Architecture:**
- Crew efficiency is computed in `CrewRules` and pushed by `Ship` into its
  engine, shield and weapon mounts as multipliers.
- Battle end, escape and capture are decided in combat_scene, helped by a
  new pure static `BattleResolution`, and handed to the campaign as a new
  `LootOffer` value object.
- Credits become `int` across `CampaignState`, the price helpers and the UI.

**Tech Stack:** Godot 4 / GDScript, headless test runner `tests/run_tests.gd`.

**Spec:** `docs/superpowers/specs/2026-11-03-crew-combat-rework-design.md`
(amends `docs/superpowers/specs/2026-11-03-crew-mechanic-design.md`).

**Execution note (user):** build directly on `main`, commit per task, and
review only the large tasks (marked **[review]**) plus one final
whole-branch review.

## Global Constraints

- Every crew read goes through `CrewRules.crew_of(comp)`. Missing keys:
  crew means full, deploy means true, flagship means false.
- Constants (exact values; all are tuning placeholders):
  - `CrewRules.MIN_CREW_EFFICIENCY = 0.5`
  - `BattleResolution.ESCAPE_SPEED_WEIGHT = 1.0`
  - `BattleResolution.ESCAPE_MIN = 0.1`
  - `BattleResolution.ESCAPE_MAX = 0.9`
  - `CampaignState.WAGE_PER_10_CREW = 1`
  - `CampaignState.DESERTION_RATE = 0.2` (unchanged)
  - `CampaignState.FINE_PER_KILL = 150`
  - `CampaignState.REPAIR_COST = 75`
  - `CampaignState.CREW_HIRE_COST = 40`
  - `CampaignState.RESPAWN_CREDIT_PENALTY = 0.25`; the amount kept is
    `floori(credits * 0.75)`
  - `ShipType.SHIP_PRICE` values become ints: 400 / 500 / 2000.
- `CampaignState.credits` is an `int` and never goes negative. No credit
  value is formatted as a float anywhere in the UI.
- Removed by this plan:
  - `Ship.disabled`, `Ship.is_disabled`, `DISABLED_DRIFT_DECEL`
  - `CrewRules.DISABLE_CREW_FRACTION`, `disable_threshold_for`,
    `CAPTURED_CREW_FRACTION`
  - `CampaignState.pending_loot_fleet`, `pending_captured_crew`
  - combat_scene's `_stalemate` and every "Stalemate" path
- Tests asserting removed behavior are replaced by tests of the new
  behavior, never just deleted.
- Escape rolls never call global `randf()`. They use a
  `RandomNumberGenerator` that tests can inject.
- Panels: `Layout` VBox, ScrollContainer rows, `tests/ui_layout_check.gd`.
  A fresh panel needs `await tree.process_frame` before layout checks.
- New `class_name`s need a warm pass before `--script` runs:
  `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --editor --quit --path .`
  Revert any `.import` churn by deleting each listed file, then
  `git checkout -- <files>`; take the list from `git status --porcelain`.
  About 19 `.import` files are already modified and are not ours: never
  stage them, and stage by explicit path.
- Typed-array literal through the untyped autoload: use `.assign()`.
- New `run_async` tests are registered with `load()` at the END of
  `tests/run_tests.gd`.
- Full suite. The non-console exe drops stdout, so redirect it:
  `Start-Process -FilePath "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" -ArgumentList "--headless","--path",".","--script","res://tests/run_tests.gd" -RedirectStandardOutput "$env:TEMP\sg_tests.log" -Wait -NoNewWindow`
  - Baseline: only the known `test_campaign_long_run_sim.gd` flake (5-6
    FAILs).
  - No `SCRIPT ERROR` lines. A run that hits a parse error can hang; kill
    only a process you started.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  Do not push.

## Review Focus

1. A fleet with only unarmed ships on both sides can never enter a battle:
   Engage is blocked. Test in Task 4.
2. A battle always ends. Destroying the last weapon mount on a side
   (mid-battle) ends it as that side's loss. Test in Task 4.
3. Escape rolls are reproducible with a seeded RNG, and the pursuer-speed-0
   case gives 100% escape. Test in Task 4.
4. Wage, price and penalty values are ints at every API boundary, and
   credits stay >= 0 when they can't be paid. Test in Task 1.
5. Bootstrap or hand-written comps (missing keys) work through efficiency,
   speed and armed checks. Test in Tasks 2 and 4.

---

### Task 1: Whole-number credits **[review]**

**Files:** `scripts/campaign/campaign_state.gd`,
`scripts/campaign/base_economy.gd`, `scripts/ship/part_rarity.gd`,
`scripts/ship/ship_type.gd` (`SHIP_PRICE`), every UI script that shows or
compares credits (`fleet_status_bar.gd`, `trade_panel.gd`,
`refit_panel.gd`, `repair_panel.gd`, `base_overview_panel.gd`,
`fleet_management_panel.gd`, `respawn_panel.gd`), and the matching tests.

**Interfaces:**
- `CampaignState.credits: int = 500`.
- `BaseEconomy.price_for(c) -> int`: `maxi(1, roundi(float_price))`.
- `BaseEconomy.sell_price_for(c) -> int`:
  `clampi(floori(buy * SELL_SPREAD), 1, maxi(1, buy - 1))`.
- `PartRarity.price_for(tier) -> int` and `sell_price_for(tier) -> int`:
  rounded, sell clamped the same way.
- `CampaignState.repair_cost_for(comp) -> int`, `wage_bill(fleet) -> int`.
  `PowerFaction.fine` / `fine_reputation`: `fine` becomes int.
- Wages: `wage_bill = floori(payable / 10) * WAGE_PER_10_CREW`.
  - Unpaid groups: `unpaid_groups = groups - floori(credits / WAGE_PER_10_CREW)`.
  - Deserters: `clampi(maxi(1, roundi(unpaid_groups * 10 * DESERTION_RATE)), 0, payable)`.
  - Credits: `credits -= paid_groups * WAGE_PER_10_CREW`.
  - Remove the old `WAGE_PER_CREW` constant and its float epsilon.
- Respawn: `credits = floori(credits * (1.0 - RESPAWN_CREDIT_PENALTY))`.

- [ ] **Step 1: Failing tests.** Update or add in `tests/test_base_economy.gd`,
  `tests/test_campaign_state.gd` and `tests/test_part_rarity.gd`:
  - `typeof(price_for(x)) == TYPE_INT`.
  - For every commodity at every band: `sell_price_for <= price_for - 1`
    when `price_for >= 2`, and sell `>= 1`.
  - `wage_bill([capital 40 flagship, corvette 12]) == 4`: payable 40 gives 4
    groups.
  - `pay_wages` with credits 1 and that fleet: credits 0, deserters
    `roundi(30 * 0.2) = 6`.
  - Respawn from 401 credits gives 300.
  - `typeof(campaign_state.credits) == TYPE_INT` after buy, sell, hire,
    repair, fine and respawn.
  - Status bar wage text has no decimal point: `"(-4 cr/tick)"`.
- [ ] **Step 2:** Run the suite and confirm the new assertions FAIL.
- [ ] **Step 3:** Implement. Search `scripts/` for every `credits` use,
  every `%.1f`/`%.2f` near a credit value, and float credit constants.
  Convert all of them.
- [ ] **Step 4:** Run the suite: baseline only.
- [ ] **Step 5:** Commit `Make credits, prices and wages whole numbers`.

### Task 2: Crew efficiency replaces the disabled state

**Files:** `scripts/campaign/crew_rules.gd`, `scripts/ship/ship.gd`,
`scripts/ship/ship_engine.gd`, `scripts/ship/shield.gd`,
`scripts/weapons/weapon_mount.gd`, `scripts/ship/ship_type.gd`,
`tests/test_ship_crew.gd`, `tests/test_crew_rules.gd`,
`tests/test_ship_type.gd`.

**Interfaces:**
- `CrewRules.MIN_CREW_EFFICIENCY := 0.5`.
- `CrewRules.efficiency_for(crew: float, complement_crew: int) -> float`:
  `lerp(MIN, 1.0, clamp(crew / complement, 0, 1))`, or 1.0 when
  complement <= 0.
- `CrewRules.is_armed(comp) -> bool`: true when `weapon_mount_count > 0`
  and some mount is not destroyed. A missing `weapon_mount_current_hp` key
  counts as armed.
- `ShipType.BASE_STATS[kind]["max_speed"]` and `["turn_rate"]` match each
  ship scene's `Engine` node values. `ShipType.base_speed_for(kind) -> float`.
- `CrewRules.comp_top_speed(comp) -> float`: the engine item's `max_speed`
  if `engine_item` is set, else `ShipType.base_speed_for(kind)`, times
  `efficiency_for(crew_of, complement)`, times the engine hp fraction
  (`engine_current_hp / engine_max_hp`, 1.0 when the keys are missing).
- `ShipEngine.crew_multiplier: float = 1.0`, applied in
  `effective_max_speed()` and to `turn_rate` in steering.
- `Shield.crew_multiplier: float = 1.0`, multiplied with the existing
  `regen_multiplier`. The EW drone's per-frame reset must not clear it.
- `WeaponMount.fire_rate_multiplier: float = 1.0`; cooldown is
  `1.0 / (weapon.fire_rate * fire_rate_multiplier)`.
- `Ship.crew_efficiency() -> float`. Ship pushes the efficiency into all
  three multipliers in `setup_crew` and on every crew change.
- Removed: `Ship.disabled`, `is_disabled`, `_disabled`,
  `DISABLED_DRIFT_DECEL`, the disabled branch in `_physics_process`,
  `CrewRules.DISABLE_CREW_FRACTION` and `disable_threshold_for`.
- Note: combat_scene still references the disabled state. In this task,
  replace those references with "always active" so it compiles. Task 4
  rewrites the battle end.

- [ ] **Step 1: Failing tests:**
  - `efficiency_for(12, 12) == 1.0`, `(6, 12) == 0.75`, `(0, 12) == 0.5`,
    and `(5, 0) == 1.0`.
  - Ship test: `setup_crew(6, 12, 0)` makes `engine.crew_multiplier`,
    `shield.crew_multiplier` and every mount's `fire_rate_multiplier`
    0.75. After a hull hit halves crew to 3, they are 0.625.
  - A corvette with kinetic_cannon at efficiency 0.5 has a cooldown after
    firing of `1 / (fire_rate * 0.5)`.
  - EW debuff stacking: with crew efficiency 0.5 and
    `shield.regen_multiplier` reset to 1.0 by Shield's own physics step,
    `shield.crew_multiplier` is still 0.5 after a physics frame. The crew
    part must survive the per-frame drone reset. The per-frame regen
    amount is `regen_rate * regen_multiplier * crew_multiplier * delta`.
  - `base_speed_for(kind)` equals the instantiated scene's
    `engine.max_speed` for all 3 kinds.
  - `is_armed`: freighter false; corvette true; corvette with all mount hp
    0 false; a bare bootstrap corvette dict true.
  - `comp_top_speed` of a half-crew bare corvette is `base * 0.75`.
  - Heavy damage never "disables". Replace the old disabled tests with:
    "a ship at crew 1 still fires (cooldown > 0 after a shot)".
- [ ] **Step 2:** Run and confirm FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run the suite: baseline only. Fix any test that relied on
  disabled behavior by asserting the new behavior.
- [ ] **Step 5:** Commit `Scale ship performance by crew instead of disabling ships`.

### Task 3: LootOffer and the loot window rework **[review]**

**Files:** create `scripts/campaign/loot_offer.gd`. Modify
`scripts/campaign/loot_panel.gd` and `scenes/campaign/loot_panel.tscn`,
`scripts/campaign/campaign_scene.gd` (loot open block),
`scripts/campaign/campaign_state.gd` (new `pending_loot`),
`tests/test_loot_panel.gd`, `tests/test_combat_scene.gd` (loot
assertions).

**Interfaces:**
- `class_name LootOffer extends RefCounted` with:
  - `var cargo: Dictionary = {}` (commodity to float)
  - `var parts: Array[String] = []`
  - `var ships: Array[Dictionary] = []` (captured comps, each with its
    current crew)
  - `func is_empty() -> bool`
  - `func crew_pool() -> int` (sum of `crew_of` over ships)
- `CampaignState.pending_loot: LootOffer = null` (cleared by `reset`).
- In this task, `resolve_engagement` builds a LootOffer from the defeated
  fleet's cargo and parts when it sets loot today, with no ships.
  `pending_loot_fleet` and `pending_captured_crew` are removed, and the
  `captured_crew` param is removed. Task 4 changes how the offer is built.
- `LootPanel.open_for(offer: LootOffer, player_fleet: CampaignFleet) -> void`.
- Cargo rows stay as today, taking from `offer.cargo`. Part rows each get
  a Take button, subject to cargo capacity.
- One row per ship in `offer.ships`: class, hull %, `crew/complement`, and
  a `keep_check: CheckBox`, exposed in `ship_rows: Array[Dictionary]`.
- `crew_slider: HSlider` from 0 to
  `min(offer.crew_pool(), free_berths(player) + sum complement(kept))`,
  with a label showing the count and `"+%d cr/tick"` of added wages.
  Ticking or unticking Keep recomputes the max. Ticking sets the value to
  the new max.
- `take_button` ("Take"): appends each kept comp with crew set to 0 and
  `flagship` false, then `CrewRules.add_crew(player comps, slider value)`,
  then `player.ensure_flagship()`, then closes.
- `close_button` text is "Leave": closes without taking ships or crew.
  Cargo already taken stays taken.
- `campaign_scene._ready` opens the panel when
  `pending_loot != null and not pending_loot.is_empty()`, then sets
  `pending_loot = null`.

- [ ] **Step 1: Failing tests** in `test_loot_panel.gd`, built from
  hand-made LootOffers. Player [corvette 12/12]; offer ships
  [corvette crew 5, freighter crew 3]:
  - The slider max starts at 0 (no free berths).
  - Ticking the corvette sets the max to 8 (`min(pool 8, 0 + 12)`) and
    the value to 8.
  - Also ticking the freighter keeps the max at 8 (pool-limited).
  - Unticking both sets the max to 0.
  - Take with the corvette kept and the slider at 5: the player has 2
    ships, the new corvette has 5 crew, and the total is 17.
  - Leave: the player is unchanged.
  - The cargo row takes from `offer.cargo`. A part row's Take adds to
    `part_inventory`.
  - `ui_layout_check` passes with 2 ship rows.
- [ ] **Step 2:** Run and confirm FAIL.
- [ ] **Step 3:** Implement. Update `test_combat_scene.gd` and
  `test_campaign_state.gd` where they read `pending_loot_fleet` or
  `pending_captured_crew` to use `pending_loot`.
- [ ] **Step 4:** Warm pass (new class_name), then run the suite: baseline
  only.
- [ ] **Step 5:** Commit `Rework loot window around captured ships and crew`.

### Task 4: Battle end, escape rolls and capture **[review]**

**Files:** create `scripts/combat/battle_resolution.gd`. Modify
`scripts/combat/combat_scene.gd`, `scripts/campaign/campaign_state.gd`
(`resolve_engagement`), `scripts/campaign/crew_rules.gd`
(`deploy_indices`), `scripts/campaign/campaign_scene.gd` (Engage
blocking), `tests/test_combat_scene.gd`, `tests/test_campaign_state.gd`,
`tests/test_crew_rules.gd`; create `tests/test_battle_resolution.gd`
(sync).

**Interfaces:**
- `class_name BattleResolution extends RefCounted`, all static:
  - `escape_chance(escaper_speed: float, pursuer_speed: float) -> float`:
    `clamp(0.5 + WEIGHT * (escaper / pursuer - 1.0), MIN, MAX)`, or 1.0
    when `pursuer_speed <= 0`.
  - `roll_escapes(escaper_speeds: Array[float], pursuer_speed: float, rng: RandomNumberGenerator) -> Array[bool]`:
    true means escaped, decided by `rng.randf() < chance`.
  - `split_cargo(fleet: CampaignFleet, captured_indices: Array[int]) -> Dictionary`:
    returns `{"loot_cargo": Dictionary, "loot_parts": Array[String], "kept_cargo": Dictionary, "kept_parts": Array[String]}`.
    - Share = captured cargo capacity / total capacity, applied to each
      commodity.
    - Parts: `floori(share * count)` go to loot, taken from the front.
    - All cargo goes to loot when every ship is captured.
- `CrewRules.deploy_indices`: when no ship meets the normal rule, the
  fallback order is (1) the highest-crew armed ship with the deploy flag,
  (2) the highest-crew armed ship regardless of the flag, (3) the existing
  fallback.
- combat_scene:
  - `var escape_rng: RandomNumberGenerator`; randomize it in `_ready`
    unless a test already set it.
  - Battle-end check after setup and on every hull or mount `destroyed`:
    "has active armed ship" means valid, not queued, and some mount
    neither destroyed nor with a null weapon.
  - Player checked first: no armed player ship means Defeat; else no armed
    enemy ship means Victory. No stalemate.
  - On result, the losing side's escape candidates are its surviving
    deployed ships (speed `engine.effective_max_speed()`) plus its
    held-back comps (speed `CrewRules.comp_top_speed`).
  - Pursuer speed: max `engine.effective_max_speed()` over the winner's
    surviving deployed ships.
  - Roll with `escape_rng`. Escaped ships keep their survivor comps; caught
    ones become captured comps.
- `CampaignState.resolve_engagement(player_survivors: Array[Dictionary], enemy_survivors: Array[Dictionary], player_won: bool = false, captured: Array[Dictionary] = []) -> void`:
  - **Player won:**
    - The enemy fleet is set to `enemy_survivors`, its escapers.
    - Cargo comes from `split_cargo`: the loot share goes into
      `pending_loot` with `captured` as `offer.ships`; the kept share stays
      on the enemy fleet.
    - The enemy fleet is erased if it has no ships left.
    - Reputation loss and fine are applied once if any enemy ship was
      destroyed or captured.
  - **Player lost:**
    - `player_survivors` (the escapers) become the player fleet.
    - `captured` player comps (flagship cleared) are appended to the enemy
      fleet, extras beyond `FleetAllocationPolicy.MAX_SHIPS_PER_FLEET`
      dropped, then `CrewRules.balance`.
    - `player.ensure_flagship()`.
    - No loot when the player fleet is empty (existing rule).
  - The legacy 2-arg call keeps working.
- campaign_scene: Engage is disabled, with label text "Neither fleet can
  fight", when neither the player's `deploy_indices` comps nor the enemy's
  contain `CrewRules.is_armed`.

- [ ] **Step 1: Failing tests.**
  - `test_battle_resolution.gd`:
    - `escape_chance(100, 100) == 0.5`, `(200, 100) == 0.9` (clamped),
      `(25, 100) == 0.1`, `(50, 0) == 1.0`.
    - `roll_escapes` with a seeded rng (seed 1234) is identical across two
      runs.
    - `split_cargo` on [capital (cap 20), freighter (cap 60)] with ORE 80
      and 3 parts, capturing index 1: loot ORE 60 and 2 parts; kept ORE
      20 and 1 part.
  - `test_crew_rules.gd`: [freighter 1 deploy, corvette 3 deploy:false]
    makes `deploy_indices` [1]. Neither meets the minimum (freighter 2,
    corvette 4), so the fallback picks the armed corvette despite its flag.
  - `test_combat_scene.gd` (replace the stalemate, disabled-ending and
    captured-crew sections):
    - Freighter vs armed corvette is an immediate Defeat, then escape
      rolls. With `escape_rng` seeded so the roll fails, the freighter is
      captured into the enemy fleet and the player respawns.
    - Win with an enemy held-back corvette and an rng seeded to escape: the
      enemy fleet stays in `enemy_fleets` with 1 ship.
      `pending_loot.ships` is empty.
    - Win with an rng seeded to capture: `pending_loot.ships` has the
      corvette with its crew, and the enemy is erased.
    - Destroying every enemy weapon mount mid-battle (hulls intact) gives
      Victory.
  - `test_campaign_state.gd`:
    - Player-lost path: captured player comps join the enemy fleet up to
      `MAX_SHIPS_PER_FLEET`, and the enemy flagship flag is cleared.
    - Reputation loss is applied once on a partial-escape win.
  - Campaign scene: with both fleets unarmed, the engage button is
    disabled and the label reads "Neither fleet can fight".
- [ ] **Step 2:** Run and confirm FAIL.
- [ ] **Step 3:** Implement. Remove the stalemate, the 20% captured crew and
  `CAPTURED_CREW_FRACTION`.
- [ ] **Step 4:** Warm pass, then run the suite: baseline only.
- [ ] **Step 5:** Commit `Replace stalemate with escape rolls and ship capture`.
