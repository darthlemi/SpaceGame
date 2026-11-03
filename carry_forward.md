# Carry Forward - 2026-11-03 session (fleet status bar + fuel/crew, base overview) - COMMITTED to main

## Completed this session

### Base overview panel - `067e6a7`
- Docking now opens `BaseOverviewPanel` (`scenes\campaign\base_overview_panel.tscn`,
  x 316-636, y 140-640) instead of Trade+Refit together. Shows name,
  population + trend, economy level, produces/consumes, reputation (faction
  bases), outstanding fine. Buttons: Trade Goods, Shipyard (= existing
  RefitPanel, renamed per user), Repair, Missions (disabled placeholder,
  `# TODO` in script), Pay Fine (only while owed), Undock.
- Trade/Refit/Repair share one slot (x 652-1152, y 140-640), one open at a
  time; sub-panel Close returns to the overview; Undock or moving away closes
  all. Map clicks are blocked while the overview is visible.
- User decisions: population is a SIMULATED stat (not derived); fines are
  per kill; Repair gets its own button/panel; button named "Shipyard".
- Population (`BaseEconomy._tick_population`, end of `tick()`): +2%/tick when
  Food >= 10, -5%/tick when Food < 1, steady in between; capped by summed
  `EconomyRole.HOUSING`; over-capacity (slot lost) shrinks to the cap; regrows
  from `POPULATION_FLOOR` 100. Does NOT consume Food itself (POPULATION role
  already does). Bootstrap seeds bases at 75% capacity.
- `BaseEconomy.wealth_level()` (Poor/Middling/Wealthy) now backs
  `CampaignState._economic_health`, so UI and fleet AI agree.
- Fines: `CampaignState.FINE_PER_KILL` 150 + the actual (clamped) rep loss
  recorded on `PowerFaction.fine` / `fine_reputation`. `pay_fine()` restores
  it and emits `faction_reputation_changed`; `campaign_scene` re-derives live
  icon behavior via `_on_fleet_role_changed`.
- `RepairPanel` extracted from `TradePanel` (adds an "All ships are fully
  repaired." label when empty); repair tests moved to `test_repair_panel.gd`.
- Tests: `test_base_overview_panel.gd`, `test_repair_panel.gd` (new), plus
  population/wealth, fines, docking flow. Mutation-checked (disconnecting the
  reputation signal -> caught). Suite: only the long_run_sim flake (6).
- Gotchas hit: assigning a bare literal to a typed array through an untyped
  autoload ref (`campaign_state.factions = [...]`) is a SCRIPT ERROR that
  aborts the test silently with no FAIL lines - use `.assign()`. Layout checks
  on a freshly opened panel need `await tree.process_frame` first. New
  `class_name`s need a `--headless --editor --quit` pass before `--script`.

### Fleet status bar + fuel/crew - `59e9594`, `5636e77`
- Top-of-map `FleetStatusBar` (`scenes\ui\fleet_status_bar.tscn`,
  `scripts\ui\fleet_status_bar.gd`): ships, fuel + burn rate, crew, credits,
  cargo. x 10-930, y 10-49; `PROCESS_MODE_ALWAYS` so it refreshes while docked.
- User decisions: fuel is consumed (not display-only); empty fuel = crawl at
  25% speed (`CampaignFleet.EMPTY_FUEL_SPEED_FACTOR`), not stranded; crew is a
  fixed per-class complement with no gameplay effect yet.
- `ShipType.BASE_STATS` gains `crew` (12/6/40) and `fuel_burn` (1.0/1.5/3.0
  per 1000 map units) for corvette/freighter/capital.
- Fuel lives in `cargo[Commodity.Type.FUEL]`; only the PLAYER icon burns it /
  gets the crawl penalty (NPC fleets carry no fuel). Burn is by distance moved,
  so time scale does not matter. New campaigns start with
  `PLAYER_STARTING_FUEL = 30` (~5450 map units for the 3-ship start fleet).
- Tests added in `test_campaign_fleet.gd`, `test_ship_type.gd`,
  `test_campaign_fleet_icon.gd`, `test_campaign_scene_trading.gd` (bar layout
  / overlap / viewport / label values). Mutation-checked (disabled crawl ->
  2 targeted failures). Suite: only the known long_run_sim flake (6).
- Committed `59e9594` on main (user asked for main directly). Not pushed.

- DONE: `.uid` files for `fleet_status_bar.gd` and `ui_layout_check.gd`
  (the latter was missing since last session) committed as `5636e77`.
  `.import`/`project.godot` churn reverted; tree clean.
- Line-ending churn recipe: `git diff --name-only` lists NOTHING for the
  `.import` files (content matches HEAD) and `git checkout --`/`git add` do not
  clear them. Delete each file, then `git checkout -- <files>`, taking the list
  from `git status --porcelain`.
- `CARRY_FORWARD.md` is tracked in git as lowercase `carry_forward.md`.

## Next steps
1. Push main (5 commits ahead of origin) when ready.
2. Tune by playing - all guesses: fuel (`ShipType.BASE_STATS`,
   `PLAYER_STARTING_FUEL`), population (`EconomyRole.HOUSING`, `BaseEconomy`
   growth/decline/`FOOD_SECURE_STOCK`), `FINE_PER_KILL`.
3. Visual check: Produces/Consumes wrapping in the 320px overview.
4. Missions: design TBD; button is a disabled placeholder.
5. Possible follow-ups (not requested): crew as a real mechanic (hire, wages,
   combat losses); low-fuel warning; fractional fuel remainders (<1) cannot be
   sold via TradePanel; population feeding back into production/prices.

---

# Carry Forward — 2026-11-03 session (ship refit/customization wrap-up) — MERGED to main

- Scoped re-review of fix wave `31b11fb..15877c2` done inline: all 4
  Critical/Important findings ADDRESSED (each with a regression test); 5 of
  6 Minor ADDRESSED.
- **Parked residual (Minor) - FIXED (uncommitted, awaiting in-game check)**:
  TradePanel moved to x 136-636 (16px gap to RefitPanel at 652); both
  panels moved to y 140-640 to clear SpeedControls (now ends y 131).
- **Root cause of the dock-panel overflow** (user screenshot): the UI theme
  (`assets/ui/theme.tres`, 8px button texture margins) makes every Button
  39px tall, but the panels were hand-positioned assuming 30px rows, with
  unbounded lists. Both panels now use a `Layout` VBoxContainer, with the
  variable lists in ScrollContainers (RefitPanel toggles `ShopScroll` and
  `EquipScroll`, not their contents). Regression check
  `_check_panel_layout` in `tests/test_campaign_scene_trading.gd`: widgets
  inside Background, no widget overlaps, no SpeedControls overlap, inside
  the configured viewport (headless window is 64x64).
- SpeedControls had the same 4px row overlaps; now a `Layout` VBox (2px
  separation, 8px inset, background 165x121). Covered by the same check.
- Committed as `cbe7491` on main. LootPanel then got the same treatment
  (`Layout` VBox with `RowsScroll`; geometry unchanged), plus
  `_rebuild_rows` now calls `remove_child` before `queue_free` (a same-frame
  rebuild stacked rows: 13 instead of 6). Committed separately on main.
- Layout check moved to `tests/ui_layout_check.gd` (new shared-helper file,
  no `test_` prefix) so panel tests can preload it. It compares the clipped
  rect for widgets inside a ScrollContainer.
- `test_ai_controller_targeting.gd` failed once (one run of five), then
  passed again - the documented frame-timing fragility, not this change.
- Launching the game rewrites 19 `.import` files + `project.godot` with
  LF/CRLF-only diffs; auto mode blocked `git checkout --` on them, so the
  user reverts them.
- Suite on the branch: only the known `test_campaign_long_run_sim.gd`
  pirate-targeting flake (6 failures on the branch, 5 on the merged tree).
- Merged `feature/ship-refit-customization` into `main` (--no-ff). The 31
  add/add `.gd.uid` conflicts (main's "Initial" commit vs branch `c06a483`
  both added them with different IDs; nothing references `uid://`) were
  resolved with the branch's IDs.
- Removed 4 stray `.art_review*` files from main (mangled `cp` output) and
  added `.art_review*` to `.gitignore`.
- This machine has no `godot..._console.exe`; the non-console exe drops
  stdout unless run via `Start-Process -RedirectStandardOutput ... -Wait`.
  The `--headless --editor --quit` warm pass rewrites `.import` files with
  CRLF-only diffs - revert them.

---

# Carry Forward — 2026-11-02 session (ship refit/customization, Milestone 5)

## Status (superseded by the 2026-11-03 entry above): mid subagent-driven-development, final-review fix wave applied, re-review was interrupted

Picked up Milestone 5 (ship refit/customization) from the full-game roadmap.
Brainstormed (several `AskUserQuestion` rounds: scope vs the separately-queued
faction-ship-styles idea — deferred to its own future milestone; weapons+hull
slots vs weapons+shield/engine swap — landed on the latter with Hull
explicitly **never** swappable; discrete upgrade tiers vs swappable component
items — landed on swappable items; buy-direct-install vs buy-into-inventory-
then-equip-separately — landed on inventory+equip; HomeBase-only vs any-base
shopping — any base; same-catalog-everywhere vs per-faction catalogs — per-
faction, split by theme; sellable parts — yes; **and a late addition**: a
loadout-points budget system (each ship class has a point allowance, each
part's rarity costs points, equipping is blocked over budget) — user's own
idea, built into this milestone rather than deferred) → spec → plan →
subagent-driven-development, all in an isolated worktree.

- **Spec**: `docs/superpowers/specs/2026-11-02-ship-refit-customization-design.md`.
  **Plan**: `docs/superpowers/plans/2026-11-02-ship-refit-customization.md`
  (10 tasks). **Worktree**: `.claude/worktrees/ship-refit-customization`,
  branch `worktree-ship-refit-customization`, entered via the native
  `EnterWorktree` tool (not manual `git worktree add`). **SDD ledger**:
  `.superpowers/sdd/2026-11-02-ship-refit-customization/progress.md` inside
  that worktree — full per-task history lives there (2 of 10 tasks needed
  one fix round each: Task 3's `set_equipped_path` unsafe array write, Task
  4's unrequested `get_catalog()` API + missing `extends RefCounted`; both
  resolved clean).
- **All 10 plan tasks implemented, task-reviewed, and completed** (fresh
  implementer + fresh reviewer per task, per `subagent-driven-development`).
  Final commit of the task sequence: `31b11fb`. Full suite green throughout
  (only the pre-existing, known-flaky `test_campaign_long_run_sim.gd`
  pirate-targeting RNG failures, 5-6 per run, same as every prior session).
- **Final whole-branch review** (dispatched on `opus` per the skill's Model
  Selection) caught real problems the per-task reviews couldn't see (each
  only saw one task's diff in isolation):
  - **Critical**: `RefitPanel._rebuild_slot_rows` derived weapon-mount-slot
    count from `comp.get("weapon_mount_items", []).size()` instead of the
    ship class — and the **real campaign's bootstrap**
    (`campaign_scene.gd`'s `_bootstrap_default_campaign`) builds player
    ship compositions as hand-written dict literals with **no**
    `weapon_mount_items` key at all. Net effect: in the actual shipped
    game, the Equip tab showed **zero weapon slots** on every ship until
    after the player's first battle — the feature's headline action
    (equip a bought weapon) was non-functional on a fresh campaign. Every
    task's own tests used `ShipType.new_composition()`, which always
    populates that key, hiding the bug from all 10 task reviews.
  - **Important**: `_collect_survivor_data` read each weapon mount's
    equipped item back **live** from the `Ship` node
    (`mount.weapon.resource_path`), which captured whatever
    `Ship._assign_random_loadout()` (the existing `randomize_loadout`
    feature from the prior session) rolled for *any* mount, not just ones
    the player explicitly equipped via RefitPanel — silently baking a
    random, possibly budget-maxing weapon into the player's permanent
    composition after one battle.
  - **Important**: that same live-read pattern also crashed
    `_report_to_campaign` if the `AddFriend`/`AddEnemy` debug-console
    commands were used mid-battle (array-length mismatch between
    `ships` and `original_compositions`).
  - **Important**: `CampaignState.equip_part` had no defensive check that
    the item being equipped actually matches the slot type (relied solely
    on `RefitPanel`'s UI-side filter) — flagged as risky given the plan
    explicitly documents downstream code as trusting this function fully.
  - Plus 6 Minor findings (UI panel viewport overflow, missing "repair
    first" prompt text, stale points label on empty fleet, uninformative
    ship-selector labels, one unused test var, one stale plan-doc snippet).
- **One consolidated fix wave dispatched** (per the skill: "ONE fix
  subagent with the complete findings list, not one fixer per finding") —
  all 10 findings (4 Critical/Important + 6 Minor) in a single dispatch,
  on `sonnet`. Implementer reported **DONE**, commit `15877c2` on top of
  `31b11fb`, full suite clean (only the same baseline RNG flake), fix
  report at
  `.superpowers/sdd/2026-11-02-ship-refit-customization/final-review-fix-report.md`.

## Next step — resume exactly here

The **scoped re-review of that fix wave was dispatched on `opus`** (per the
skill's "exactly one scoped re-review of the fix wave, then adjudicate — no
second fix wave") but was **killed mid-run by a user interrupt** (ran low on
session tokens), before it returned any verdict. Nothing from the real
feature work was lost — the fix commit `15877c2` is already committed to
the worktree branch; only the *verification* of that fix is incomplete.

To resume: re-dispatch a fresh scoped re-reviewer (the killed agent's id was
`a0eea56e0744ee0fa` — don't try to resume it, start fresh) over the diff
`31b11fb..15877c2`. The review-package diff file already exists at
`.superpowers/sdd/2026-11-02-ship-refit-customization/review-31b11fb..15877c2.diff`
(no need to regenerate it unless the worktree has changed since). The 10
findings to verify are listed in full above and in that diff file's
accompanying context — re-derive the same scoped-re-review prompt structure
used in this session (verdict each of the 10 findings ADDRESSED/NOT
ADDRESSED/PARTIALLY, check for new breakage in the fix diff, out-of-scope
observations don't block). After that comes back: adjudicate any open
residual findings per the loop's breaker rules (park with a ruling, or stop
if load-bearing — there is no second fix wave), then invoke
`superpowers:finishing-a-development-branch` to decide how this worktree
branch gets integrated (it has never been merged to `master`; `master` is
untouched throughout this entire session).

Current worktree HEAD: `15877c2587339e6c459232852e959000b668103f`. Repo is
clean — nothing uncommitted.

---

# Carry Forward — 2026-11-02 session (weapon loadout randomization)

## Done this session

Picked up the "wire weapon/drone resources into ship loadouts" item queued
at the top of the 2026-11-01 weapon-types+drones entry below. Brainstormed
(two rounds of `AskUserQuestion`: same-vs-per-faction loadouts, capital's
3-mount variety, then a clarifying round on per-instance vs per-type
variety) → spec → plan → implemented directly on `master` (user explicitly
chose this over an isolated worktree when asked). All 3 plan tasks done,
each its own commit.

- **Spec**: `docs/superpowers/specs/2026-11-02-weapon-loadout-randomization-design.md`.
  **Plan**: `docs/superpowers/plans/2026-11-02-weapon-loadout-randomization.md`.
- `ShipType.WEAPON_POOL` (`scripts/ship/ship_type.gd`) — 14 ship-mountable
  weapon resource paths (all Kinetic/Missile/Beam/PD variants from the
  2026-11-01 weapon-types spec), deliberately excluding the 3 drone-only
  weapons.
- `Ship.randomize_loadout: bool` (default `false`) + `_assign_random_loadout()`
  in `scripts/ship/ship.gd` — when true, shuffles a copy of `WEAPON_POOL`
  and assigns one distinct weapon per `WeaponMount` in order, so a ship
  with multiple mounts (capital's 3) never repeats a weapon on itself.
  Only `ship_corvette.tscn` and `ship_capital.tscn` set the flag true
  (`scenes/ship/ship_corvette.tscn`, `scenes/ship/ship_capital.tscn` —
  also stripped their hardcoded `weapon = kinetic_cannon.tres` per mount
  and the now-unused ext_resource line). `ship.tscn` (generic, many
  existing tests assume its fixed `kinetic_cannon.tres`) and
  `ship_freighter.tscn` (0 mounts) are untouched, verified by a regression
  test.
- Applies uniformly regardless of who owns the ship (player, Dominion,
  Freehold, pirate) since it's scene-driven, not faction/spawner-driven —
  matches the user's answer "everyone can use the same weapons, but not
  the exact same weapons per ship."
- **Real regression caught and fixed, not just worked around**: adding a
  new test case inside `test_ship.gd`'s `run_async` (to verify the flag on
  a manually-flagged `ship.tscn` instance) shifted frame-count timing
  enough to consistently break `test_ai_controller_targeting.gd` — a
  pre-existing test with a *documented* "single-frame timing assumption"
  (see the comment already in `tests/run_tests.gd` near the
  `campaign_scene_test` registration, which had previously hit the same
  class of issue from a different test). Confirmed via a throwaway `git
  worktree` checkout of the pre-session commit (`71413eb`) that the
  failure did **not** exist at baseline — so this was a real regression
  introduced this session, not a pre-existing flake. Tried awaiting an
  extra `physics_frame`/a second `process_frame` inside the fragile test
  itself first — neither fixed it. Root-caused it to test *ordering*, not
  test *content*: moved the new check out of `test_ship.gd` entirely into
  its own new file, `tests/test_ship_randomize_loadout.gd`, registered in
  `run_tests.gd` well after `test_ai_controller_targeting.gd` instead of
  immediately before it. Confirmed via the baseline worktree comparison
  before concluding it was safe to move on, then deleted the worktree
  (`git worktree remove`).
- Full suite green after every task; only the pre-existing, known-flaky
  `test_campaign_long_run_sim.gd` pirate-targeting failures (5-6, varies
  with wander RNG — same ones noted in every earlier entry below) remain.
- New headless-run gotcha hit this session, worth remembering: running the
  test command through `| grep ...` in a backgrounded shell call can look
  like a 10+ minute hang (process technically still "alive" per
  `Get-Process`, but not actually making progress) purely from pipe
  buffering — redirecting straight to a log file with `>` instead and
  `Read`-ing it afterward is reliable; piping through `grep` in the same
  backgrounded command is not.

## Next step

Per the 2026-11-01 entry's original next-step list, still queued, not
started: the PD/Interceptor deferred missile-vs-drone targeting bonus
(needs new targeting infrastructure), and the Milestone 5 ship
refit/customization feature (hull slots, swappable parts, buying/selling —
needs its own brainstorm). Rarity-driven loot/shop rules are still
explicitly out of scope everywhere they've come up (no shop system exists
at all yet).

Repo is clean on `master`, nothing uncommitted from this session's own
changes (the same pre-existing untracked clutter — `.gd.uid` cache files,
`.art_review*` stray files, an untracked
`docs/superpowers/plans/2026-11-01-campaign-map-bounds.md` — was present
before this session started and is unrelated to it; left untouched).

---

# Carry Forward — 2026-11-01 session (weapon types + drones)

## Done this session

User asked to design kinetic/missile/beam/point-defense/drone weapon
variants (3-4 each) with shield/hull/component-damage balance, assuming
shields and component damage exist (component damage didn't, yet).
Brainstormed → spec → plan → implemented directly on `master` (user said
"implement in master" each time a spec/plan was ready, skipping worktree
isolation both times). Everything below is committed; nothing left
uncommitted.

- **Spec 1**: `docs/superpowers/specs/2026-11-01-weapon-types-design.md` —
  18 weapon variants (4 kinetic, 4 missile, 4 beam, 2 PD, 4 drone) with
  damage-model fields (`shield_mult`/`hull_mult`/`pierce_pct`/
  `component_damage`/`mount_type`/`fire_arc_degrees`/`rarity`/
  `submissile_count`/`projectile_speed`), balanced against existing ship
  stats (corvette 60hp/20shield, freighter 80/20, capital 220/80).
- **Conflict discovered mid-plan**: a different, already-committed
  (but unexecuted) plan, `docs/superpowers/plans/2026-11-01-ship-components-damage-repair.md`,
  independently designed component damage via real `ShipComponent`
  hitboxes (geometric, position-based) — incompatible with this session's
  first draft (a `ComponentPool` with random-weighted picks). User chose
  to build the hitbox-based plan's **prerequisite tasks (1-5 only, not its
  full 11)** first, then revise the weapon-types plan to route
  `component_damage` through that foundation instead. Tasks 6-11 of that
  other plan (shield-glow signals, campaign persistence, scene VFX,
  station repair) remain **not implemented** — still queued if picked up
  later, see that plan file.
- **Prereq work implemented** (`scripts/ship/ship_component.gd` new base
  class; `Hull`/`ShipEngine`/`WeaponMount` migrated to extend it;
  `Ship.resolve_component_hit`/`receive_damage(amount, impact_position)`;
  `Projectile._hit` now passes `global_position`). Caught and fixed one
  real regression during this: `Hull` no longer redeclaring `max_hp`
  meant it inherited `ShipComponent`'s default of `10.0` instead of the
  old `100.0` — `scenes/ship/ship.tscn`'s generic Hull node (used by
  several unit tests) never set `max_hp` explicitly and silently dropped
  to 10hp until caught via `test_ship_vfx.gd` failing. Fixed by adding
  `max_hp = 100.0` explicitly to that one scene node.
- **Spec 2**: `docs/superpowers/specs/2026-11-01-drone-weapons-design.md`
  — Drone was deliberately scoped out of the first implementation plan
  (needs autonomous-entity behavior, not just weapon data) and designed
  separately once the other 4 types shipped. Reuses the existing
  `Ship`/`AIController`/`Order` architecture almost entirely instead of a
  new entity type — key decisions from that session's Q&A: drones are
  regular `enemy_group` combatants (shootable/AI-targetable like any
  ship) but **not** player-right-click-selectable
  (`Ship.player_targetable`); a `DroneBay` launches drones with a short
  gap between successive launches but a much longer cooldown after a
  slot's drone dies (user: "drones fire .3 gap they should battle
  ready" — no spin-up delay, instantly combat-capable).
- **Drone implementation**: `scripts/drones/drone_bay.gd` (bay-wide
  `_launch_cooldown` gates any launch at `launch_interval`=0.3s,
  independent per-slot `_slot_cooldowns` gate only post-death respawn at
  `respawn_delay`=15s — **note**: the plan's first draft used one
  per-slot cooldown for both purposes and TDD caught it as wrong
  immediately, two cooldowns were needed); `scripts/drones/bomber_drone.gd`
  (`BomberDrone extends Ship`, overrides `attack_range()`→
  `detonate_radius` and `_process_weapons()` to hit-then-self-destruct
  instead of firing a projectile); `scripts/drones/ew_drone.gd`
  (`EwDrone extends Ship`, overrides `_process_weapons()` to set the
  nearest enemy's new `Shield.regen_multiplier` each frame — resets to
  `1.0` every physics frame in `Shield._physics_process` so the debuff
  auto-expires when the drone leaves range/dies, no cleanup code needed).
  Attack/Interceptor drones needed **no new scripts** — plain `Ship`
  scenes with a tiny `Hull`/`WeaponMount`/small `Weapon` resource.
- **Deferred** (documented in both specs' Out-of-scope sections, not
  forgotten): PD's and Interceptor's "bonus vs missiles/drones" — no
  missile-vs-drone entity distinction exists in the targeting system;
  would need its own design pass if ever wanted. No ammo/lifetime limits
  anywhere (drones persist until destroyed).
- All 14 kinetic/missile/beam/PD weapon `.tres` resources created under
  `resources/weapons/` (matching every stat in the spec table, including
  `kinetic_cannon.tres`'s new fields layered onto its pre-existing
  damage/fire_rate/range). All 4 drone scenes + their weapon/payload
  resources under `scenes/drones/`.
- **Mid-session, outside this agent's own tool calls**: a separate
  worktree at `.claude/worktrees/ship-components` (branch
  `worktree-ship-components`) was independently completing Tasks 6-11 of
  `ship-components-damage-repair.md` (the ones this session deferred —
  shield-glow VFX, engine/mount-destruction explosions, station repair UI,
  campaign persistence of component damage) at the same time. Tool
  system-reminders briefly showed literal unresolved conflict markers
  (`<<<<<<< HEAD` / `>>>>>>> worktree-ship-components`) in several shared
  files mid-edit — `grep`ing the actual files on disk at that moment came
  back clean, so that was a stale/in-flight snapshot, not real corruption.
  Shortly after, `git merge worktree-ship-components` (commit `f12ad94`,
  outside any tool call this session made — presumably run directly by
  the user) merged that branch into `master` cleanly via git's `ort`
  strategy, no conflicts. **Tasks 6-11 are therefore now done, not
  queued** — see the corrected Next-step note below. Re-ran the full
  suite after: still green (same pre-existing baseline flake only).
- Full suite green throughout (verified after every single task, ~20
  individual runs) via
  `& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/run_tests.gd`
  — only the pre-existing, known-flaky `test_campaign_long_run_sim.gd`
  pirate-targeting failures remain (unrelated, predate this session, same
  ones noted in earlier carry-forward entries below).
- No Godot console-build executable found this session (the
  `godot.windows.opt.tools.64_console.exe` referenced in a prior
  carry-forward entry below wasn't located) — used the Steam-installed
  non-console `godot.windows.opt.tools.64.exe` for headless test runs
  too, not just for launching the playable game window. Worked fine via
  PowerShell with `--headless`; no console-window gotcha hit.

## Next step

Weapon-types, drone-weapons, **and** the full ship-components-damage-repair
plan (all 11 tasks, the last 6 via the external merge noted above) are now
all fully implemented and merged into `master`. Natural next candidates,
not started:
- PD/Interceptor's deferred missile-vs-drone targeting bonus, if ever
  wanted (needs new targeting infrastructure).
- Wiring the new weapon/drone resources into actual ship loadouts/scenes
  (ship_corvette.tscn etc. still only mount `kinetic_cannon.tres`) and
  into whatever drop/shop system eventually uses the new `rarity` field
  — rarity exists as data only, no spawn/loot rules use it yet (explicitly
  out of scope per the weapon-types spec).
- The `.claude/worktrees/ship-components` worktree directory may still
  exist on disk after its branch was merged — check `git worktree list`
  and `git worktree remove` it if it's just leftover clutter (same
  Windows "device busy" caveat noted in the 2026-10-31 Trade Routes
  entry below may apply).

Repo is clean on `master`, nothing uncommitted from this session.

---

# Carry Forward — 2026-11-01 session (click-to-travel interactions)

## Done this session

Brainstormed (several `AskUserQuestion` rounds: scope, chase-vs-fixed-point
for moving fleet targets, friendly-fleet dialog behavior, what cancels an
in-progress travel) then the user said "implement in master" before a spec
doc was written — implemented directly on `master`, no
`docs/superpowers/specs/...` file for this change. Also fixed two bugs the
user found via manual play-testing after the first pass. Committed as
`80f9a35`.

- **Click-to-travel model** in `scripts/campaign/campaign_scene.gd`: new
  `_travel_target: Area2D`. `_unhandled_input` runs a
  `PhysicsPointQueryParameters2D` point-query (`_find_clickable_target`) at
  the click position — clicking a base or `CampaignFleetIcon` sets it as
  the travel target (free-drag mode off); clicking empty space clears it
  and resumes the old hold-and-drag movement unchanged.
  `_physics_process` re-reads the target's **live** `global_position` every
  frame (chases moving fleets, doesn't just head to a stale click point),
  clearing `_travel_target` if the target is freed mid-chase.
- **Arrival gating**: `_on_player_area_entered` (the existing Area2D
  overlap signal) now only opens the trade panel / engage prompt when
  `area == _travel_target` — flying past a base or fleet incidentally no
  longer pops anything. Arrival at any fleet (hostile or not, per user's
  explicit choice) now also pauses the tree, matching the trade panel's
  pre-existing pause-on-dock behavior (previously only trade paused).
  Logic factored into `_trigger_arrival(area)` so it can be called both
  from the signal and directly (see bug fix below).
- **Bug 1** (user caught in play-testing): a stray click anywhere on the
  map while a dialog was open silently unpaused the game without closing
  the dialog (`_unhandled_input` unconditionally unpaused on any paused
  click). Fixed: `_unhandled_input` now returns immediately if
  `trade_panel.visible or engage_prompt.visible` — unpausing only happens
  via an explicit dialog action now. Added `_on_trade_panel_closed`
  (wired to `trade_panel.close_button.pressed`) to unpause + clear
  `_travel_target` on close, and `_on_disengage_pressed` gained an
  explicit unpause (previously relied on the now-removed click fallback).
- **Bug 2** (user caught in play-testing): disengaging from a fleet
  encountered on top of a base, then clicking that same base while still
  standing on it, did nothing — `area_entered` only fires on a *fresh*
  overlap transition, and the player never left the base's collision area.
  Fixed: when a click's target is already in
  `player_icon.get_overlapping_areas()`, `_unhandled_input` calls
  `_trigger_arrival(target)` directly instead of waiting on a signal that
  will never re-fire.
- Updated `tests/test_campaign_scene.gd` and
  `tests/test_campaign_scene_trading.gd` to simulate real clicks by setting
  `scene._travel_target` before teleporting icons (previously these tests
  just teleported onto targets and relied on bare overlap). Added new
  cases: flyby-without-click doesn't open the trade panel, arrival clears
  `_travel_target`, and the already-overlapping-target bug scenario
  (fleet-on-base → disengage → click base → trade panel opens immediately).
- Full suite passes; only the pre-existing, known-flaky pirate-engagement
  RNG failures in `test_campaign_long_run_sim.gd` remain (unrelated).

## Next step

No specific next step named. This closes out the click-to-travel request
and both follow-up bug reports from this session.

---

# Carry Forward — 2026-11-01 session (campaign map bounds)

## Done this session

Implemented the `docs/superpowers/plans/2026-11-01-campaign-map-bounds.md`
plan directly on `master` (user explicitly asked for it "in main", skipping
the usual worktree isolation). Both tasks completed, verified via the
headless test suite, and committed as two separate commits.

- `scripts/campaign/campaign_fleet_icon.gd`: added `MAP_MIN := Vector2(0, 0)`
  and `MAP_MAX := Vector2(4000, 2400)` constants, plus a single clamp line
  (`_move_target = _move_target.clamp(MAP_MIN, MAP_MAX)`) right after the
  `match behavior_type:` block in `_physics_process`, before the
  `move_toward` call. One choke point covers every behavior (patrol,
  trader, pirate) and the player's externally-set mouse-click target
  uniformly — fleets glide to a stop at the map edge instead of being
  teleported or bounced.
- `tests/test_campaign_fleet_icon.gd`: two new cases — a player target set
  far past `MAP_MAX` gets clamped, and a trader fleeing past `MAP_MAX.x`
  (via `TraderBehavior.flee_target`) also gets clamped.
- `tests/test_campaign_long_run_sim.gd`: the per-step distance-from-spawn
  tracking gained a real `out_of_bounds` hard assertion (checked against
  `CampaignFleetIcon.MAP_MIN`/`MAP_MAX`) instead of being report-only;
  header comment updated accordingly.
- Full suite run: only the pre-existing, intentionally-red pirate-
  engagement failures in `test_campaign_long_run_sim.gd` remain (5-6,
  varies with wander RNG) — zero new failures, zero "went out of map
  bounds" failures.
- Commits: `ab1affa` (clamp + unit tests), `a7c526c` (sim-test assertion).

## Next step

No specific next step named. Map-bounds work is closed out; nothing
queued from this session.

---

# Carry Forward — 2026-11-01 session (overworld ship sprites)

## Done this session

Closed the long-queued "ship classes would feed into the clump's dot
rendering too" follow-up from the 2026-10-31 overworld-fleet-clump session
(see that entry below, and the "Follow-up queued" section further down) —
ship classes (corvette/freighter/capital) already existed by this point, so
this was ready to pick up. Brainstormed (two rounds of `AskUserQuestion`:
sprite size small/dot-sized vs. larger, rotate-to-heading vs. fixed upright,
then missing-`ship_type` fallback) and presented a design, but the user said
"just implement code" before a spec/plan doc was written — so, unlike the
usual house process, there is **no** `docs/superpowers/specs/...` file for
this change. Implemented directly and verified via the test suite only (no
in-game screenshot this session).

- `scripts/campaign/campaign_fleet_icon.gd`: `_sync_ship_dots()` now creates
  `Sprite2D` children instead of flat-color `Polygon2D` dots, one per
  `fleet.ship_compositions` entry, textured via `ShipType.kind_of(comp)` →
  a new `SHIP_ICON_TEXTURES` dict (loads the same
  `assets/sprites/ships/*.png` files used by the real ship scenes directly,
  not by instancing the ship scene). Each sprite is scaled so its longest
  dimension is a new `SHIP_ICON_MAX_DIM := 10.0` px constant — comparable
  footprint to the old dots, but now corvette/freighter/capital read as
  visually distinct silhouettes instead of identical dots. Old
  `SHIP_DOT_RADIUS`/`SHIP_DOT_SIDES`/`DOT_COLOR`/`_circle_polygon()` removed
  as dead code. `CLUMP_RADIUS` (18px) and the cached-per-index random offset
  behavior are unchanged.
- Added heading rotation (user explicitly wanted this over fixed-upright):
  `_physics_process` now captures position-before-move, computes the
  frame's movement delta after the existing `move_toward` call, and if its
  length clears a new `HEADING_EPSILON := 0.5` it updates a cached
  `_heading_angle` (`movement.angle()`) applied to every sprite's
  `rotation` each frame. A stationary fleet holds its last heading rather
  than snapping to 0. Sprites rotate in place — they keep their scattered
  clump offsets, this isn't a formation.
- `ShipType` already has a global `class_name` (used bare elsewhere, e.g.
  `campaign_fleet.gd`) — initially added a redundant
  `const ShipType = preload(...)` in the icon script shadowing that global
  class name; removed it once noticed. Worth remembering for any future
  file that reaches for `ShipType` statics: no preload needed.
- `tests/test_campaign_fleet_icon.gd`'s "ship dots" section updated to
  assert `Sprite2D` (with a non-null `texture`) instead of `Polygon2D`, plus
  a new case: a `PLAYER`-behavior icon given a move target, ticked 10
  physics frames, should have its sprite's `rotation` match the direction
  of travel.
- Full suite passes via the same headless Godot command noted in prior
  sessions (`godot.windows.opt.tools.64_console.exe --headless --path . --script res://tests/run_tests.gd`)
  — "All tests passed" plus the usual pre-existing ObjectDB-leak/resource
  warnings at exit, unrelated to this change.

## Still open (not addressed this session)

The 2026-10-31 fleet-clump session's parked reviewer note still applies,
and now matters more: `CLUMP_RADIUS` is fixed regardless of fleet size, so
a large fleet (~15+ ships) will visually saturate — with real ship
silhouettes instead of plain dots this will look like an overlapping mess
sooner than it did with small dots. Still fine for current fleet sizes;
revisit scaling `CLUMP_RADIUS` with `sqrt(ship_count)` if that changes.

## Next step

No specific next step was named by the user this session. The broader
queued-but-not-started items from prior sessions (ship-customization
feature, projectiles/weapon VFX, UI panel icons, background/starfield, and
whatever the base-art session below left pending) are all still just as
queued as before — this session only closed the one specific clump/ship-
class follow-up.

Repo is **not** committed for this session's changes —
`scripts/campaign/campaign_fleet_icon.gd` and
`tests/test_campaign_fleet_icon.gd` are sitting as working-tree changes;
commit only if/when asked. No spec/plan doc was written this session (see
above) — don't go looking for one under `docs/superpowers/` for this
feature.

---

# Carry Forward — 2026-11-01 session (base art)

## Done this session

Picked up from the ships session's queued "ships next" list — bases were
the user's flagged next category, with a reference image already gathered
(but, as noted below, never saved to disk). Brainstormed → short spec →
iterated sprites with the user → wired into Godot, same flow as the ship
art session (asset-design work, not a formal plan/subagent cycle).
Spec: `docs/superpowers/specs/2026-11-01-base-art-design.md`.

- First: committed the previous session's **ship art** work that had been
  left uncommitted (`b3949bb`) — `ship_vfx.gd`, the three ship `.tscn`
  files, `art/src/ships.px.js`, `assets/sprites/ships/*.png`. Left
  `carry_forward.md`'s own pending edit and the stray `.gd.uid`/
  `.art_review*` clutter alone (not part of that commit's scope).
- Found the bases reference images: the previously-mentioned ringed
  orbital station reference was never saved to the repo. User pointed to
  `C:\Users\corbi\OneDrive\Desktop\trainer\images6/7/8` (two `.jfif`, one
  `.webp`) — all three show toroidal/ring stations with a central hub and
  radial docking-arm clusters. `.jfif` files don't render via the Read
  tool directly; copying to a `.jpg` extension in the scratchpad first
  (jfif is JPEG under a different extension) fixed that.
- **Three distinct base sprites** built with `pxl` into new
  `art/src/bases.px.js`, staying in the locked ship palette
  (`art/src/palette.px.js`) but mixing accents more freely than the
  one-accent-per-ship rule:
  - **Dominion** FactionBase — full ring/torus + central hub + cross
    spokes + diagonal docking struts + paneled greebling. Red+orange
    accent. Closest to the references; reads as authoritative/industrial
    (matches its `INDUSTRIAL + POPULATION` economy).
  - **Freehold** FactionBase — asymmetric mining-rig cluster (hex hub,
    segmented drill-arm wedge, 3 strutted ore silos, radiator fins,
    antenna). Green+yellow accent. Deliberately not ring-shaped — scrappy
    /utilitarian, matches `MINING + AGRICULTURE`.
  - **Player HomeBase** — compact hub-and-spoke, all-blue accent, smaller
    and tidier than both faction bases (modest "player's starting point"
    vs. power-faction capitals). Matches `TRADE_HUB + REFINERY`.
- **Wired into Godot**: `home_base.tscn` swapped its `Polygon2D` for a
  `Sprite2D` + the new texture (scale 1.2, chosen to roughly match the
  existing `CircleShape2D` radius-30 collision footprint, same approach as
  ship scaling). `faction_base.tscn` is a **shared** scene for both
  Dominion and Freehold (one scene, `faction_enum` field distinguishes
  instances) — it already had an unused `faction_enum` export; added
  `_ready()` to `faction_base.gd` that picks the Dominion or Freehold
  texture based on that field. Collision shapes untouched on all three.
- Test suite passes clean after the `--headless --editor --quit` warm pass
  (needed for the new PNGs, same gotcha as every session touching
  textures). `tests/test_faction_base.gd` doesn't exercise `_ready()`
  (instantiates without adding to the tree), so it wasn't a signal either
  way for the new texture-picking logic — confirmed visually instead (see
  below), not just trusted on the test suite.
- **Visually verified in the actual running game**, not just sprite
  previews: launched the real project (see "Running the game" below),
  closed the trade panel that opens on start, and screenshotted the
  overworld — all three bases render distinctly and at reasonable scale
  (Freehold small/scrappy top-left, player HomeBase blue hub-and-spoke
  center, Dominion ring station bottom-right). This is the first session
  to actually confirm art in-engine rather than stopping at `pxl`'s
  preview PNGs.

## Running the game (now solved — previously an open gap)

User supplied the actual exe location, which isn't on PATH and wasn't
previously known to any carry-forward note:
`C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`
(Steam-installed; distinct from the WinGet-installed
`godot.windows.opt.tools.64_console.exe` used for `--headless` test runs —
both exist on this machine, use whichever fits: console/WinGet build for
headless test/import commands, this Steam build for actually launching the
game window.)

To launch and play: `Start-Process <that-exe> -ArgumentList "--path", "<repo-path>"`
(no `--editor` flag) opens the game window directly in play mode, titled
"SpaceGame (DEBUG)". To screenshot it from this environment (no
claude-in-chrome equivalent for native Win32 apps): PowerShell +
`user32.dll` P/Invoke (`GetWindowRect`, `SetForegroundWindow`) to find/focus
the window, then `System.Drawing.Graphics.CopyFromScreen` over that
rect, saved to a PNG and read back with the Read tool. Mouse clicks (e.g.
closing a panel) work the same way via `mouse_event` P/Invoke at absolute
screen coordinates computed from the window rect. Close the process after
with `Stop-Process -Force` — don't leave it running across turns.

## Gotchas hit this session

- **Copied the wrong pxl output directory the first time**: `pxl build`
  writes both `out/_preview/<name>.png` (10x upscaled, for humans looking
  at previews) and `out/sprites/<name>.png` (raw pixel size, what actually
  belongs in `assets/sprites/`). Initially copied from `_preview/` by
  habit from eyeballing previews in-session — caught it by comparing
  dimensions against the already-correct `assets/sprites/ships/corvette.png`
  (44x36, matching its 42x34 sprite + 1px outline) before anything got
  wired into a scene. Always diff dimensions against an existing correct
  asset before trusting a copy, not just against what "looks right" in a
  preview tool.
- `pxl`'s `ring(cx, cy, r, c)` is circle-only (4 args: center, radius,
  color) — passing it `rect`-style args (`ring(x, y, w, h, c)`, 5 args) to
  outline a rectangular docking pad fails loudly at build time (not a
  silent wrong-render). Use `box(x, y, w, h, c)` for a 1px rectangle
  border instead.
- To draw a ring/annulus band (needed for the Dominion torus) with no
  boolean-subtract op available: fill a big `circ()` in the hull color,
  then `circ()` again at a smaller radius in `"_"` (erase-to-transparent)
  to punch the hole. `ring()` then adds a crisp 1px rim on top for
  shading definition.
- No GUI-driving tooling is set up for this native Godot desktop app in
  this environment (no project `run` skill, no screenshot/interaction
  path like the Playwright/Electron patterns cover) — verification this
  session stopped at the test suite + sprite previews, not an actual
  in-game look at the campaign map. Flagged to the user rather than
  claimed as verified. If this keeps coming up, `/run-skill-generator`
  could capture a real path (e.g. Godot's `--headless` + a screenshot
  dump some other way) as a project skill.

## Next step

Per the art-pipeline session's original category list, still queued:
**projectiles/weapon VFX**, **UI panel icons** (trade/loot),
**background/starfield**. Bases are now done. Also still queued (not
started): the **ship-customization feature** (gameplay/UI, not art — picks
a ship skin per hull, e.g. freighter cargo vs. fuel-tanker truss variant;
needs its own brainstorm).

Repo is **not** committed for this session's base-art changes —
`faction_base.tscn`, `faction_base.gd`, `home_base.tscn`,
`art/src/bases.px.js`, `assets/sprites/bases/*.png` are sitting as working
tree changes; commit only if/when asked. The same pre-existing
`.gd.uid`/`.art_review*` clutter from prior sessions is still untouched —
still unclear if the user wants it, still not this session's to decide.

---

# Carry Forward — 2026-10-31 session (overworld fleet clump)

## Done this session

Brainstormed → spec'd → planned → implemented (1 task via
subagent-driven-development) → task-reviewed → final whole-branch
reviewed (clean, no Critical/Important) → merged to `master`.
Spec: `docs/superpowers/specs/2026-10-31-overworld-fleet-clump-design.md`.
Plan: `docs/superpowers/plans/2026-10-31-overworld-fleet-clump.md`.

- **Overworld fleet clump** — `CampaignFleetIcon` no longer shows a single
  static triangle for a whole fleet; it now renders one small dot per
  entry in `fleet.ship_compositions`, scattered randomly within a fixed
  `CLUMP_RADIUS` (18px) around the icon's origin via `_sync_ship_dots()`.
  Dot offsets are cached per-index so surviving ships don't jump position
  when the fleet shrinks. Applies uniformly to all fleets (player, trader,
  pirate, faction) since the logic lives in the shared icon script, not
  per-faction code. Deliberately count/shape only — no ship-class visuals
  (see the "Follow-up queued" entry below, still open).
- Final reviewer flagged (Minor, parked, not fixed): clump radius is fixed
  regardless of fleet size, so very large fleets (~15+ ships) will visually
  saturate into an unreadable blob — fine for now since fleets are small,
  but if that changes, scale `CLUMP_RADIUS` with `sqrt(ship_count)` rather
  than leaving it fixed. Also no test for the 0-ship or
  shrink-then-regrow-in-one-frame edge cases (both correct by inspection).

## Gotchas hit this session

- Same per-checkout Godot `class_name` cache gotcha as prior sessions
  (see 2026-10-31 Trade Routes entry below) — bit the dispatched
  implementer subagent on its first pass in the fresh worktree; it
  initially mis-reported "tests can't run" as if blocked, when it just
  needed the one-time `--headless --editor --quit` warm pass. Worth
  including that warm-pass instruction directly in future implementer
  dispatches for fresh worktrees, not just in the plan's Global
  Constraints (which the implementer may not read closely enough to act
  on before concluding it's stuck).
- `master`'s working tree had substantial unrelated uncommitted
  pre-existing work (economy/speed-control/campaign-scene changes, several
  untracked `.gd`/`.gd.uid` files, an untracked `CLAUDE.md`) plus a
  same-named *untracked* copy of this session's own plan file (written
  directly to disk before the worktree existed, with stale `- [ ]`
  checkboxes) sitting at the same path the branch would create via merge
  — had to delete that stale untracked duplicate first or `git merge`
  would have refused to overwrite it. Left all the *other* unrelated dirty
  files alone, as instructed by the art-pipeline session's note below.

## Next step (this session's thread)

No further action needed on the clump feature itself. The ship-classes
follow-up (below) is the natural next consumer if picked up.

---

# Carry Forward — 2026-10-31 session (art pipeline)

## Done this session

Evaluated `C:\Users\corbi\Desktop\UIilianks\` — five separate MIT-licensed
procedural-art tools by GitHub user `uilianks` (`chirp` audio, `kiln` 3D,
`loom` textures, `pxl` pixel art, `vex` vector art), each packaged as a
Claude Code Skill. Scanned all source for risky patterns (eval, exec,
network exfiltration) — clean, nothing beyond local dev-server previews.

Brainstormed → spec'd → scaffolded an **art pipeline** for SpaceGame, which
currently has zero art (every entity is a flat `Polygon2D`/`ColorRect`
placeholder — confirmed via `scenes/combat/combat_scene.tscn`, no
`assets`/`art` directory existed before this session).

- Compared `vex` (vector) vs `pxl` (pixel art) with sample top-down ship
  sprites — **`pxl` chosen** for the chunky retro pixel-art look.
- Iterated palette live against user feedback (started from a reference
  screenshot — dark isometric pixel-art noir/cyberpunk cafe scene) toward
  a locked 12-color base palette: near-black outline, **dirty grey** hull
  (not pure black — needs to read against a starfield), neon
  green/red/blue as the primary accent trio, darker yellow/orange/pink as
  secondary accents. Full swatch + reasoning in the spec below.
- Decided `pxl` stays **external** (cloned separately, not vendored) —
  SpaceGame repo only gains `.px.js` source + exported PNGs, no new
  Node/TypeScript tooling added to an otherwise pure-Godot repo.
- Spec: `docs/superpowers/specs/2026-10-31-pxl-art-pipeline-design.md`
  (pipeline + palette only — scope deliberately excludes producing the
  actual ship/VFX/UI/background assets; each is big enough to need its
  own future brainstorm).
- Scaffolded `art/README.md` (build instructions) and
  `art/src/palette.px.js` (the locked palette, copy-paste source for every
  future `.px.js` file — pxl has no cross-file import). Verified it builds
  clean with no errors.
- Added `art/src/out/` to `.gitignore` (pxl's local build-artifact dir).

Two commits on `master`: `e625cd2` (spec), `4520f32` (scaffold).

## Gotchas hit this session

- `pxl`'s shape-primitive names differ from `vex`'s: `circ` not `circle`.
  Easy to typo when writing samples in both DSLs back to back.
- When building multiple sample files into the same scratch directory,
  pxl/vex both write previews to `out/_preview/<sprite-name>.png` — reused
  sprite names across files **silently overwrite** each other's preview.
  Give samples distinct names (`corvette_vex` vs `corvette_pxl`) when
  comparing tools side by side in one working directory.
- Ship's existing placeholder (`scenes/ship/ship.tscn` `Polygon2D`) is
  authored nose-pointing **+X** (right), not nose-up — `polygon =
  PackedVector2Array(20, 0, -12, -10, -12, 10)`. Any future ship sprite
  needs either authoring nose-right to match, or a 90° rotation offset
  applied in the scene.

## Pre-existing repo state (not from this session — do not attribute)

`master` had substantial uncommitted work already in progress when this
session started (economy/trade-panel/campaign-scene changes, several new
untracked `.gd`/`.gd.uid` files including `game_speed.gd` and
`speed_controls.gd/.tscn`, plus an untracked `CLAUDE.md`). Left entirely
untouched this session — only `art/`, `.gitignore`, and the new spec were
staged and committed. Whoever picks this up next should `git status` and
figure out whether that in-flight work is still wanted before doing
anything that touches those files.

Also on `master` already (not this session): Ship Types design spec +
plan (`docs/superpowers/specs/2026-10-31-ship-types-design.md`,
`docs/superpowers/plans/2026-10-31-ship-types.md`) — **not yet
implemented**, `scenes/ship/` still has only the single generic
`ship.tscn`. This is the natural next consumer of ship sprites once both
the ship-types feature and an actual `art/src/ships.px.js` spec exist.

## Next step (this session's thread)

Pick one asset category and brainstorm it as its own spec, using the
locked palette in `art/src/palette.px.js`. **Ships** is the obvious first
candidate (ties into the already-spec'd-but-unimplemented Ship Types
work) — but check in with the user rather than assuming, same as this
session did category-by-category (mood → palette → repo integration, one
question at a time, nothing finalized without an explicit lock-in).

Other queued categories from this session's scope discussion: projectiles
/ weapon VFX, campaign map icons (fleet icons, faction/home bases), UI
panel icons (trade/loot), background/starfield.

---

# Carry Forward — 2026-10-31 session (Trade Routes)

## Done this session

Milestone 4b (Trade Routes) brainstormed → spec'd → planned → implemented
(11 tasks via subagent-driven-development) → task-reviewed → final
whole-branch reviewed → fix wave → re-reviewed → merged to `master`.
Spec: `docs/superpowers/specs/2026-10-31-trade-routes-design.md`.
Plan: `docs/superpowers/plans/2026-10-31-trade-routes.md`.

- **Trade Routes** — Dominion and Freehold each got a second fleet
  (`CampaignFleet.role = TRADER`) that autonomously hauls cargo to/from
  HomeBase: loads surplus at its own faction base, carries it to a
  per-faction dock point near HomeBase, dumps it into
  `home_base_economy.stock`, loads deficit commodities, and delivers them
  home. `FleetAllocationPolicy` (new, pure static decider) grows a
  faction's combat or trade fleet count/size based on economic health
  (`BaseEconomy.surplus_streak`) and threat ratio (vs. pirate strength),
  or reallocates a trader to combat under threat+deficit (never stripping
  the last trader). HomeBase gained a `refinery()` role producing ongoing
  Fuel, closing the 4a gap where Dominion's Fuel consumption had no
  source. Defeating a cargo-carrying fleet now opens a `LootPanel` letting
  the player take cargo one unit at a time (`CampaignState.pending_loot_fleet`,
  consumed by `CampaignScene._ready()` — not a transient signal, since
  `CombatScene` has already torn down the old `CampaignScene` by the time
  `resolve_engagement` runs).
- Economy & trading milestone (4a+4b) is now fully done per the roadmap.

## Known issue — parked, not blocking, worth a follow-up

`CampaignFleetIcon.set_route_endpoints` only skips its `_route_state` reset
when the new endpoints match the icon's *current* endpoints
(`route_endpoints_match()`), but `CampaignScene._setup_enemy_icon` always
seeds a fresh icon via `icon.setup(fleet, HOME_BASE_POSITION)` first, so
the comparison is seeded wrong and never matches for power-faction fleets.
Net effect: every time the player returns from `CombatScene` (i.e. after
any fight), in-flight trader fleets get their route state reset and
redeliver whatever they were carrying back to the base they just left — a
wasted round trip, not a resource loss (cargo isn't duplicated or lost,
just redundantly re-routed). Real fix needs `_route_state` persisted on
`CampaignFleet` itself (survives scene teardown), not compared on the
icon. Caught by the final review; intentionally parked rather than looped
again (no data loss, nothing else in the plan depends on it).

Also flagged by the final reviewer as an **out-of-scope observation**, not
fixed: HomeBase has no ORE/FOOD producer (only the new `refinery()` for
Fuel), so with haulers now actually drawing both commodities down every
trip, HomeBase's one-time seed runs dry in roughly 2 minutes of real play.
Not as severe as the pre-4b total collapse (Dominion now keeps resupplying
either way once FOOD/FUEL/ORE all load per trip instead of just ORE), but
worth a real producer (or a Freehold trade loop that also deposits FOOD at
HomeBase — it does, but ORE and FOOD compete for the same limited HomeBase
space over time) before calling this fully balanced.

## Gotchas hit this session (useful if touching this code)

- Everything from the 2026-10-30 carry-forward still applies (Godot not on
  PATH, use the full path; new `class_name` files need one
  `--headless --editor --quit` cache-warm pass before `--headless --script`
  tests can see them — **this applies per-checkout**: a fresh git worktree
  has its own uncached class list even if the main checkout was already
  warmed, and vice versa after a merge into a previously-stale checkout).
- `git worktree remove` can fail with "contains modified or untracked
  files" purely from Godot's auto-generated `.gd.uid` cache files (harmless,
  not real work) — `--force` handles that, but on Windows the directory
  itself can still come back "Device or resource busy" after git has
  already deregistered the worktree (confirmed via `git worktree list`
  and `git worktree prune`) — safe to leave the orphaned directory for
  manual cleanup later; the git-level state is already clean.
- `CampaignFleetIcon.set_route_endpoints` forcing `_route_state = FROM_BASE`
  unconditionally (introduced in this milestone, Task 5) looked harmless
  in isolation but became load-bearing wrong once Task 10 added a second,
  repeated call site (post-combat `_ready()` re-wiring) — a reminder that
  a Minor finding deferred in an early task needs re-checking once later
  tasks add new call sites to the same function, not just inherited as
  settled.
- Two Critical bugs that passed every task-level review only surfaced at
  final whole-branch review: (1) cargo-loading always gave the whole hold
  to the first qualifying commodity in dict-iteration order, so FOOD/FUEL
  never actually got hauled even though `cargo_total() > 0` tests passed;
  (2) both factions' haulers routed to the identical HomeBase pixel while
  permanently at war, guaranteeing a skirmish that destroyed one hauler
  within minutes. Neither was visible to any single task's isolated
  tests — only a full-system trace (real bootstrap numbers, real
  geometry) caught them. Worth deliberately tracing "does this close the
  loop under the actual starting numbers" during any future milestone's
  final review, not just checking each task's own narrow test.

## Follow-up queued (not started)

**Ship classes** (corvette/capital/freighter) — the game currently has
only one generic ship type (`scenes/ship/ship.tscn`); there is no
ship-class field anywhere in `CampaignFleet.ship_compositions` or the
combat spawner, and no corvette/capital/freighter visuals exist in code
(only in old 2026-08-25 planning docs). Raised while brainstorming the
overworld fleet clump feature
(`docs/superpowers/specs/2026-10-31-overworld-fleet-clump-design.md`,
scoped out deliberately — see that spec's "Out of scope" section).
Introducing real classes needs a class field on ship composition data,
distinct combat-scene visuals/scale per class, and would feed into this
clump's dot rendering too.

**Note (superseded by the art-pipeline session above):** Ship Types
(design spec + plan) has since been written —
`docs/superpowers/specs/2026-10-31-ship-types-design.md`,
`docs/superpowers/plans/2026-10-31-ship-types.md` — but not yet
implemented.

## Next step

Per the full-game roadmap (`docs/superpowers/specs/2026-10-29-full-game-roadmap-design.md`),
next up is **Milestone 5: Ship refit/customization** (hull slots,
swappable weapons/parts, buying and selling — depends on the economy
existing to be meaningful, which it now does). Pick it up the same way as
always: `superpowers:brainstorming` → spec → plan →
subagent-driven-development. Consider raising the HomeBase ORE/FOOD
producer gap (above) as part of that brainstorm if it starts to matter for
playtesting, rather than as its own milestone.

Repo is clean on `master`, no uncommitted work. No remote configured
(local-only repo, same as before). One stray non-git-tracked worktree
directory at `.claude/worktrees/trade-routes` may still exist on disk
(git already deregistered it) — safe to delete manually if Windows will
release the lock.

---

# Carry Forward — 2026-10-31 session (ship art, picking up the art-pipeline thread)

## Done this session

Picked up the art-pipeline session's queued "ships next" thread. Heavy
back-and-forth visual iteration directly with the user (screenshots via a
published Artifact gallery, not a formal brainstorm/spec/plan cycle — this
was asset-design work, not a code feature) landing on a finalized set now
wired into the actual game:

- **`art/src/ships.px.js`** (new) — final noir-only sprite defs (the
  4-way style comparison — noir/neon/military/arcade — was exploratory;
  noir is the one that shipped, matching the already-locked
  `palette.px.js`). Built with `pxl` (cloned at `../UIilianks/pxl`
  relative to the repo, per the pipeline spec), output copied into
  `assets/sprites/ships/*.png` (new, now tracked).
- **Corvette** — dart hull with big sweeping delta wings (swept well past
  the hull silhouette, not the small triangle nubs from the first pass)
  and an isometric canopy block.
- **Freighter** — kept the original asymmetric-cargo-pod design as the
  wired sprite. Two more variants exist in the same file but are **not
  wired to any scene**: `freighter_fuel` and `freighter_cargo`, a modular
  "truss" design (slim spine + cockpit module + swappable 2x2 pod
  cluster) from a Pinterest "Mule Class Freighter" reference. User
  explicitly wants multiple ship skins selectable later via an
  unbuilt **ship-customization feature** — these are held for that, not
  dead code.
- **Capital** — replaced the original hexagon-ish hull (read as "a fish,
  not a big bad ultimate ship") with a Star-Wars-contour dagger hull
  (Nebula-class silhouette + bold centerline stripe; a forked-bow
  Venator-style variant was tried and explicitly rejected as "fish
  eating a triangle" — bow is a plain taper). Bridge is twin isometric
  tower blocks, elongated lengthwise (not square cubes — also rejected
  once), symmetric above/below the long axis, standing in for the
  reference's "twin sails either side."
- Several other explored-but-not-committed variants exist only in this
  session's chat/scratchpad (not in the repo): a stepped/forked-bow
  capital redesign, and `destroyer_a`/`destroyer_b` tier-deck studies.
  Not saved anywhere on disk — if ever wanted again, they'd need to be
  rebuilt from scratch (not worth preserving given the user converged on
  the Star-Wars-contour design).
- **Wired into Godot**: `ship_corvette.tscn`, `ship_freighter.tscn`,
  `ship_capital.tscn` each swapped their flat-color `Polygon2D` placeholder
  for a `Sprite2D` + the new texture (scale 0.8 / 0.75 / 0.6 respectively,
  chosen so each sprite's nose offset from origin roughly matches the old
  polygon's nose offset, since collision shapes and `WeaponMount` positions
  on the capital are tuned against that origin and weren't touched).
- **Bug caught by the test suite, fixed**: `scripts/ship/ship_vfx.gd` had
  a hardcoded `get_node("Polygon2D")` for the hit-flash tween. Swapping to
  `Sprite2D` broke it silently until `tests/run_tests.gd` surfaced
  `Node not found: "Polygon2D"` + a null-instance `modulate` assignment
  error (tests still reported "All tests passed" — these were runtime
  script errors during a passing run, not assertion failures, easy to
  miss). Fixed by looking up `Sprite2D` first and falling back to
  `Polygon2D` (the generic `scenes/ship/ship.tscn` used by several unit
  tests still has the old `Polygon2D`, untouched, so the fallback is
  load-bearing, not defensive dead code).

## Gotchas hit this session

- Same Godot import/cache gotcha as always, extended to **textures**: new
  PNGs under `assets/` aren't picked up by `--headless --script` test runs
  until one `--headless --editor --quit` pass reimports them. Ran that
  before the test suite; skipping it would have made the new `Sprite2D`
  nodes reference unimported textures.
- `isobox()` (pxl's 2:1 isometric block primitive) does not stretch along
  screen-horizontal when you grow `w` — its `w` axis renders toward
  **lower-right** on screen, `d` toward **lower-left** (true isometric
  axes, not screen x/y). For a ship pointing screen-right, `w` elongated
  (`d: 1`) is the closest achievable approximation to "along the hull" and
  is what shipped. Also: `isobox`'s pixel footprint for a given
  `{size, at}` is not obvious from the parameters — don't try to compute
  placement analytically, iterate visually (a too-large `size` produced
  huge diagonal shapes completely disconnected from the hull on the first
  truss-freighter pod attempt).
- `pxl`'s op functions (`rect()`, `circ()`, etc.) only do anything when
  passed directly as arguments to `sprite()`/`scene()` — calling them
  inside a helper function and discarding the return value draws nothing.
  Shared geometry (the truss freighter's spine+cockpit, used by both the
  fuel and cargo variant) has to be a function that **returns an array**
  of ops, spread into `sprite()` with `...helperFn()`.

## Next step

Ships are done for now ("seems fine for now" / "continue with this art
style for all ships" — noir locked in). Per the art-pipeline session's
original category list, still queued: **projectiles/weapon VFX**,
**campaign map icons** (fleet icons, faction/home bases), **UI panel
icons** (trade/loot), **background/starfield**. User separately flagged
**bases** as the next likely category and supplied a reference (an AI-
generated ringed orbital station/capital-ship-hybrid image — concentric
rings, greebled hull, lit window grid, docking arms) — check in before
assuming that's next rather than one of the other queued categories.

Also now explicitly queued (not started): a **ship-customization feature**
letting the player pick a ship skin per hull (e.g. freighter: cargo vs.
fuel-tanker truss variant). This is a gameplay/UI feature, not just art —
needs its own brainstorm when picked up, separate from the art pipeline
itself. The unwired `freighter_fuel`/`freighter_cargo` sprites in
`art/src/ships.px.js` are the art half of that, already done.

Repo is **not** committed — `git status` shows the new/modified files
(`art/src/ships.px.js`, `assets/sprites/ships/*.png`, the three ship
`.tscn` files, `scripts/ship/ship_vfx.gd`) sitting as working-tree changes,
same as every other session in this file; commit only if/when the user
asks. Pre-existing untracked clutter at repo root from before this session
(`.art_review${f}_ref.jpg` and two garbled-filename artifacts from a
broken shell command) was left alone — not created this session, unclear
if the user wants them, investigate before touching.
