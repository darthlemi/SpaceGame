# Carry-Forward - SpaceGame 2026-11-06 (starting stock spread built, for playtest; combat AI and orders built, for playtest; combat commands/pacing Task 1 done and verified, test suite fixed)

Trimmed 2026-11-04. Finished, committed work was removed; it lives in git history
(`git log -p -- carry_forward.md`). Only the current thread, open items and durable rules remain.

## Combat commands, idle start, pacing (in progress, 2026-11-06)
Spec approved and builder-checked: `docs\superpowers\specs\2026-11-06-combat-commands-pacing-design.md`.
Plan: `docs\superpowers\plans\2026-11-06-combat-commands-pacing.md` (4 tasks). Executing via
`superpowers:subagent-driven-development`, batched reviews per `token-efficient-execution`
(one reviewer after Task 2, one final review after Task 4). Ledger:
`.superpowers\sdd\2026-11-06-combat-commands-pacing\progress.md`.

- **Task 1 done:** `scripts\combat\combat_scene.gd` (`strength_of`, `center_out_anchors`,
  strength-sorted `_spawn_fleet_from_data`), `scripts\ship\ship.gd` (default spawn order
  `Order.hold()` -> `Order.hold_position()`, so ships no longer auto-hunt at battle start),
  `tests\test_combat_scene.gd` updated. Commits `0c69a12`, `c5eae75` (the second is a fix: the
  first commit called `CombatScene.strength_of(...)` as a bare global, but `combat_scene.gd` has
  no `class_name` — there is no global `CombatScene` identifier in this codebase. Fixed to
  unprefixed self-calls inside the script and the file's existing `scene_script = load(...)`
  pattern in tests).
- **Test suite hang: fixed.** The warm pass (`--headless --editor --path . --quit`) cleared the
  global `SCRIPT ERROR` flood — confirmed a stale script class cache, not a code bug. It rewrites
  `.import` files (CRLF-only churn); `git status --porcelain` showed none left afterward in this
  run, but if it recurs, delete each changed `.import` then `git checkout -- <files>` per the
  gotchas section below. **Do this warm pass any time the suite hangs with a flood of
  `SCRIPT ERROR` global-class-resolution failures again** before assuming a code regression.
- That warm pass then exposed two real bugs the suite could never reach before (fixed, committed
  `c1a4357`):
  1. `tests\test_combat_scene.gd:49,936` — two `:=` type-inference parse errors (a method chained
     off a Variant-typed array element, and a method called on a `load()`-returned `GDScript`
     object both statically return `Variant`, so `:=` can't infer). Gave both vars explicit types.
  2. `Ship._process_hold_position`'s retarget condition (`ship.gd`, was
     `_retarget_timer <= 0.0 or (_idle_target != null and not _is_live_target(_idle_target))`)
     only forced a retry when `_idle_target` was non-null-but-dead, unlike `_process_hold`'s
     equivalent (which also retries when the target is null). A HOLD_POSITION ship that finds
     zero candidates on the tick its timer last reset (e.g. before `enemy_group` is assigned by
     scene setup code, which runs after the ship's first physics tick in some spawn paths) got
     stuck target-less for a full `RETARGET_INTERVAL` (0.5s) instead of retrying next tick. Only
     hit reliably now because Task 1 made HOLD_POSITION the default spawn order — this condition
     pre-dates Task 1 but was rarely exercised this way before. Fixed to match `_process_hold`'s
     condition (`_retarget_timer <= 0.0 or not _is_live_target(_idle_target)`).
  Confirmed via direct instrumentation (temporarily reverting the spawn-order default and
  comparing `idle_target()` results) before touching code, not guessed.
- Suite now clean: 0 `SCRIPT ERROR` across 2 confirmed runs; only the known
  `test_campaign_long_run_sim.gd` pirate-targeting flake remains (6-8 lines, varies run to run).
- Do not trust an implementer subagent's self-reported "tests pass" / "DONE" on this plan without
  independently re-running the suite and reading the actual output — the Task 1 implementer twice
  reported success (once after a 5-minute client-side timeout it called "not a failure," once by
  comparing error *counts* across commits) without ever seeing a clean run. That caution held up:
  the suite genuinely couldn't run at all until the warm pass.
- **Task 3 done, input scheme revised live by the user (three rounds of feedback) before it
  landed.** The plan/spec's original scheme (left-click only selects, right-click always issues
  the armed command and clears selection) was rejected during implementation and replaced with:
  left-click only selects/deselects (click own ship = select, anything else = deselect, drag =
  box-select); right-click is the smart default when nothing is armed (attack an enemy under the
  cursor, else move the selection there — `FleetCommander._issue_smart_order`); arming Move,
  Attack, or Protect (OrderBar buttons/M-A-P hotkeys, unchanged from the plan) makes right-click
  resolve that command instead (`_issue_armed_command`) — Move always forces a move even onto an
  enemy (close distance without auto-pursuing), Attack always searches for a nearby enemy even
  off-click, Protect is the only way to target an ally (otherwise indistinguishable from "move
  there"). Issuing an order via right-click never clears the selection — only a left-click on
  empty space does, so the player can re-right-click the same selection repeatedly. Full detail
  and rationale: the spec's "Input scheme" section (rewritten to match) and the plan's Task 3
  deviation note. Implementation: `scripts\controllers\fleet_commander.gd`
  (`set_armed_command`/`_issue_armed_command`/`_issue_smart_order`/rewritten
  `_on_left_release`/`_on_right_press`), signals wired in `combat_scene.gd`, three input actions
  (`order_move`/M, `order_attack`/A, `order_protect`/P) added to `project.godot`. Tests updated in
  `tests\test_fleet_commander.gd` and `tests\test_combat_scene.gd`. One real bug the tests caught:
  `_on_left_release`'s deselect branch assigned a bare `[]`/ternary to the typed
  `Array[Ship] selected_ships`, which GDScript's static typing rejects at runtime
  (`SCRIPT ERROR: Trying to assign an array of type "Array" to a variable of type "Array[Ship]"`)
  — fixed by building the typed array with `.append()` instead of a literal. Suite clean except
  the known flake; commit pending.

## Combat camera and debug menu (built 2026-11-06, for playtest)
- `CombatCamera`: mouse at the screen edge pans (48 px band, ramped, eased); arena is now 3200x3200
  (walls in `combat_scene.tscn` and default spawn points moved to match). `OffscreenBlips` draws blue
  (friendly) / red (enemy) edge triangles for off-screen ships. Commit `085f0c5`.
- F12 debug menu (`scripts\debug\debug_menu.gd`, actions in `debug_actions.gd`, tests in
  `tests	est_debug_actions.gd`): click-only, in combat and in the world. Fuel +-100, credits +-1000,
  crew +-10, repair fleet (both scenes); combat: add friend/enemy, god mode, kill all; world: spawn
  pirate fleet tier 1/3/5, spawn trader, reveal all systems.
- Known limits: fuel ignores cargo capacity; crew changes in combat hit campaign comps only, so they
  do not reach already-deployed ships and are overwritten by the battle result for them. The old
  text console is still there. Not playtested; only the headless suite ran (flake failures only).

## Starting stock spread (built 2026-11-06, commits `0b20473`, `bb7cfae`)
- Problem: every station opened at `Commodity.TARGET_STOCK`, so every price matched and the player had no
  profitable trade at the start.
- `CampaignState._default_start_stock`: a net maker (`net_commodities() > 0`) opens at
  `STARTING_STOCK_PRODUCED` 2.0x target (0.6x price band), a net burner at `STARTING_STOCK_CONSUMED`
  0.15x (1.6x band); neutral goods stay at target. An explicit `stock` entry in `data\galaxy.json` wins.
- Tests: `tests	est_campaign_start_stock.gd` (new). `test_campaign_galaxy_state.gd` no longer expects
  target stock at every station, and its trade-destination check resets stock to target first (its
  scores assume an even start).
- Probe, seeds 7 and 11, 1 h (galaxy was 27 systems / 43 stations by then): ~1.33 jumps/s, flat from
  ~20 min; 0 stranded, 0 traders stuck at home, 0-4 fleets dry at home, no slot loss. Not comparable to
  the 1.15/s of the 26-system probe.
- Open, for the user: **playtest the first-trade margins** (ore buys at ~6 at a mine and sells at ~12
  at an industrial station; not measured for the other goods). Both factors are placeholders. NPC traders
  now arbitrage the same gaps from tick 0.
- `data\galaxy.json` committed in the same change with the user's map editor edits (new system Dyrall,
  moved systems, link changes). The tests stale from those edits were updated by hand and NOT re-run:
  counts (27 / 43 / 76 link entries / 27 layers), deadreach and ashfall tier 4, new-game jump map shows
  northgate not tollgate, round-trip raider starts at thornfield, tier-4 pirate check, the neutral-partner
  check uses farhaven, trade range uses northgate (3 jumps from bastion). **Run the suite first thing.**
  `test_galaxy_data.gd` exempts `ironhold` from the pirate-needs-agriculture rule (TODO in the test):
  Ironhold is now a pirate station with a population slot and no pirate farm in range; decide whether
  to add agriculture there or relax the rule. User chose to leave the TODO in place for now (2026-11-06).
  Test fixes are commit `0cfd1d5`.

## Completed this session
- Built the star systems plan (`docs\superpowers\plans\2026-11-04-star-systems-jumping.md`),
  subagent-driven on `main`, commits `879dfac`..`a7683ed`:
  - galaxy model and layout (`GalaxyData`, 26 systems, 37 stations, 40 links);
  - per-station economies, quotas and respawn in `CampaignState`;
  - one `SystemLayer` per system, `CampaignStation` replaces HomeBase/FactionBase;
  - player jumping, the jump map, discovery and distress (`jump_controller.gd`);
  - AI jumping (`NpcJumpPlanner`), NPC refuel, repair, dwell limits and retiring stranded fleets.
- Verified:
  - suite ~68 s, 0 `SCRIPT ERROR`, only the long-run-sim flake;
  - perf, 62 fleets, non-headless: 1x avg 0.95 / max 3.27 ms, 5x avg 1.04 / max 3.13 ms (bar
    8 / 33);
  - 1 h probe, seeds 7 and 11: jump rate flat from ~20-30 min, no trader idles at home > 25 s,
    worst pirate home empty 46%.
- Probe script for the AI galaxy (not committed):
  `C:\Users\c_dirks\AppData\Local\Temp\claude\7f8633d840d3c804\13cae86e-3352-415c-95d6-de4b935bbd38\scratchpad\probe\probe_galaxy.gd`
  (`-- --dur=3600`). Copy it into `tests\` if it is wanted long term.
- The 19 execution rulings were in `.superpowers\sdd\2026-11-04-star-systems-jumping\`, which was
  wiped on 2026-11-05 (see "Combat AI and orders"). They are lost; git history is the record.

## Combat AI and orders (built 2026-11-05, plan `docs\superpowers\plans\2026-11-05-combat-ai-orders.md`)
- Commits: `68b5701` (hull/loadout movement), `7e5bedc` + `0730356` (target scoring, edge range),
  `c00a2d1` + `e6dc30b` (Flee / Hold Position, AI flee, fled accounting), `aece3d3` (order bar,
  H/F hotkeys, 10 s re-engage delay), `a43b9a3` (final fix: latched attack-run break point).
- Verified: suite = long-run-sim flake only (4-8 lines), 0 `SCRIPT ERROR`; perf 10v10 non-headless
  1x avg 1.74 / max 2.20 ms, 5x avg 1.44 / max 3.06 ms; run probe vs a capital 1 -> 5 shots in 30 s,
  never inside the hull floor, 0 ticks outside the arena near a wall.
- Pure helpers live in `CombatTactics` (`scripts\combat\combat_tactics.gd`); all tuning values are
  named consts there, in `Ship` (`FLEE_SPOOL_TIME`) and `AIController` (`FLEE_LOSS_FRACTION`,
  `UNARMED_FLEE_RANGE`), and `CampaignState.REENGAGE_DELAY`.
- Rulings made during execution (spec over plan where they differed):
  - attack runs latch the break point at INBOUND->BREAK (offset from target, clamped to the arena,
    lead time `RUN_BREAK_LEAD_TIME` 0.8 s); the plan's per-tick point made ships orbit after 1 pass;
  - "Withdrew" only when a fled player ship was still armed (plan said any fled ship);
  - `nearest_in_range` and HOLD autofire measure to the hull edge (also fixes the EW drone aura);
  - armed freighters use the corvette `FLEE_LOSS_FRACTION` (no FREIGHTER key);
  - kite reach = `best_engagement_range` over working non-PD weapons;
  - fled ships are untargetable and take no damage (projectiles, mounts, AI, selection);
  - RUN ships don't count toward allies' spread; debug spawns skip fled ships.
- Open, for the user:
  - **Playtest feel:** runs, kiting, spacing, flee cost. The 10v10 perf battles hadn't ended
    after 26 s (13/20 ships left at 1x); watch battle length.
  - **Kiting vs corvettes:** the kite test compares forward speeds, but `hold_station` backs off at
    0.5x, so a kiter can't hold its gap against another corvette. If confirmed, compare
    `own_speed * REVERSE_SPEED_FACTOR`.
  - **Blocked-fleet feedback:** clicking a fleet during its re-engage delay shows nothing, and
    `_travel_target` keeps following it; no prompt when the block expires.
  - **Untested run cases:** a target in an arena corner can turn a run into a wall slide; a hull
    much faster than today's pushes the break distance past the reset distance.
- Parked minors: kite point has no margin inside own reach; `tactic_for` uses base (not
  crew-scaled) turn rate; only the `_trigger_arrival` re-engage gate is tested (`is_hostile_icon`,
  `_process_pirate` aren't); `campaign_fleet_icon.gd` reads `/root/CampaignState` by path (the
  autoload name broke test preloads); the flee spool bar runs `_process` every frame; no tests for
  Hold Position out of reach or PD-only ships under Hold/Flee.

## Next steps
1. **AI economy rebalance: built 2026-11-05 (`da2bec4`), for the user to playtest.** Replaces the
   old Home Base fuel and Dominion economy items:
   - a starved slot idles and keeps its inputs, no slot is ever lost; a 3x-target stock cap idles
     full-output consumers;
   - trade goods follow stock (short = below the 0.6 band, spare = above target); a maker never
     wants its own product, a burner never ships out its input;
   - `_best_trade_partner` scores `_route_value`: surplus x price pull, x (1 + 2 x emptiness) at
     home, plus deliveries to partners short of what home has spare. Removed the per-jump divisor
     and the cargo cap (they let a same-system Ore quarry beat the fuel run);
   - NPCs never trade or refuel at player-owned stations (`_is_trade_partner`); Home Base sits at
     the 300 cap at 1 h;
   - refinery FUEL 2 -> 3, and three Dominion quarries (Bastion Quarry, Ironhold Quarry, Kestrel
     Mines: mining + refinery, TRADER 1);
   - probes, seeds 7 and 11, 1 h: jump rate flat at ~1.15/s, 0 stranded, 5-7 fleets dry at home
     (was 22 before the refinery bump), no slot loss. Suite: only the pirate-targeting flake
     (7-9 failures this run).
   Open: pirate stations cap at 300 FUEL that nobody can reach (pirates only trade with pirates);
   many core stations still sit at 0 FUEL, since NPC refuels are free (no prices); neutral hubs
   (Aurum Bazaar, Freeport, Haven Exchange, Marrow Depot) make no fuel, so their fleets depend
   on hauls; the 3 and the quarry count are placeholders to tune.
3. **Neutral patrols vs pirates: fixed 2026-11-05.** `_factions_hostile` now makes
   NEUTRAL and PIRATE hostile, so neutral patrols hunt and skirmish pirates. Neutral haulers
   (`TRADER`) are still never pirate prey: open question for the user.
4. **Parked minors from the final review:**
   - `campaign_scene.gd` is at 412 lines, and `_icon_of` duplicates `_icon_for_fleet`;
   - the FUEL reserve is 0 at stations that burn no FUEL, so homes like Thornfield and Farhaven
     can run dry and ground their fleets (retiring only covers fleets away from home);
   - the long-run sim's `KNOWN_SLOT_LOSS` list (13 stations) can't see a listed station drop
     further;
   - `_grow_station_fleet` ignores the station's tier;
   - `REALLOCATE_TO_COMBAT` reactivates uncapped growth if a trader quota goes above 1;
   - the speed buttons can unpause the game behind the jump map and the Fleet panel;
   - pirates retreat on damage only, not low crew;
   - test helpers are duplicated across 4 jump test files.
5. **Later sub-projects, in agreed order:**
   1. more factions (4-5, one hostile, one peacekeeper, a couple neutral);
   2. AI economy and bigger fleets;
   3. the mysterious end-game faction (jump gates, cheaper or longer jumps, better ships);
   4. big battles.
   Decisions already made for the AI economy sub-project, kept from the earlier brainstorm:
   - **Fleet size:** 4-10 ships for every faction's fleets.
   - **No hard cap:** fleet size is limited by credits, crew and fuel, for the player and the AI
     alike.
   - **AI cheats by discount:** AI pays like the player, but everything costs less.
   - **Pirates become a full faction**, with an economy.
   - **Convoys:** freighters always travel with escorts, bigger on dangerous routes.
   Unconfirmed guesses to put to the user then:
   - a treasury per faction, with one discount of about 50%;
   - pirates earn by raiding;
   - convoy danger is measured by enemy strength near the route;
   - a convoy that can't afford an escort waits in port.
   Code facts to remember:
   - `CLUMP_RADIUS` 36 will overlap 10-ship fleets on the map;
   - combat has only 3 spawn points per side.

## Systems and Stations menu (brainstormed 2026-11-05, NOT built, no spec or plan yet)
Idea: remember what the player saw at each station on their last visit, and show it in a menu.
Layout, text and sort behaviour are settled by the user; the mockup is the reference. Next step is
to play the design back for sign-off, write the spec (`docs\superpowers\specs\`, builder check), then
`superpowers:writing-plans`. **Do not build before the spec is approved.**
- **Mockup (final, v24, committed):** `docs\superpowers\mockups\station-menu-final-v24.html`. Open
  it in a browser, or serve it from the visual companion. Preview server: start it with the
  brainstorming `scripts\start-server.sh --project-dir <repo>`; to screenshot, headless Edge works
  (`--headless=new --screenshot`).
- **Layout:** one screen on a 16:9 reference stage (1280x720), scaled to fit the window.
  - Left: scrollable tree, scrollbar on the LEFT edge. Systems with a small `[+]`/`[-]` box, name,
    and "Stations - x" under it; stations under an expanded system with a faction-coloured round dot.
    Names may wrap if too long (fits normally).
  - Right: scrollable detail panel for the selected station:
    - header: station name, "System: <name>", faction badge (hugs its text; the mockup stretches it,
      a CSS bug), "Visited: Day 42 (13 days ago)";
    - three one-line stat boxes spanning the row: Population, Wealth, Reputation;
    - Population is shown as a signed number, green `+` when growing, red `-` when declining
      (stable: unspecified, suggest plain white, no sign);
    - market, two groups PRODUCES and CONSUMES, each its own table with fixed-width columns
      (Commodity 34%, Stock, Buy, Sell 22% each), every header and cell centred;
    - Stock is signed and coloured: green `+n` over target, red `-n` short of it (stock minus
      `Commodity.TARGET_STOCK`; my reading, the user hasn't said whether they want raw units);
    - no status tags (Surplus/Deficit words were dropped), no Role column.
  - Sorting: click a column header to sort that table only (each table independent). First click
    ascending with an up arrow, second click descending with a down arrow; the arrow sits outside the
    header text so it never shifts the centring. No sort on open.
- **Left out on purpose:** Security (no such stat exists in the campaign scripts; user said remove for
  now); faction-owned fine/reputation detail beyond the one number.
- **Data facts (verified in code):** `BaseEconomy` has `stock`, `price_for`, `sell_price_for`,
  `net_commodities()` (per-tick, static per station), `population`, `population_trend`,
  `wealth_level()`; `BaseOverviewPanel` already shows population, wealth, produces, consumes and
  reputation when docked. "Net / visit" was my invention and was dropped.
- **Open questions:** how Day is counted (check for a game-day counter; none confirmed); the snapshot
  is taken on docking and stored in `CampaignState` (save games don't exist yet, flag when saving is
  built); which systems appear (visited only, per the user's "systems you visit"); whether the
  discovered-but-unvisited jump-map systems should show; where the menu opens from; whether sort
  state persists between visits.
- **Mockup alignment caveat:** the browser rescales the mockup, so pixel alignment (toggle boxes, `+`
  centring) is only truly settled in the Godot controls; SVG toggles were the scale-proof fix.

## Star systems: calls built as "my call", for the user to playtest
- **Caught mid-warp:** never answered. Hostile contact during the countdown forces the engage
  prompt, and no new warp can start while a hostile is touching you. Only fleets with pirate
  behaviour catch you; traders never do.
- **Distress signal:** 3x the base fuel price, delivered instantly; hidden whenever a connected
  jump is affordable.
- **Pirate citadels** (Ashfall, Deadreach) switched from `population` to `agriculture` so they
  don't starve. The user may re-tune `data\galaxy.json` (see "Map editor"); a system may carry an
  optional `tier` key.
- **NPC tuning:** fuel for 4 jumps, raids and hunts end after 75 s away (`RAID_DWELL`,
  `HUNT_DWELL`), a 90 s rest at home (`HOME_REST`), a station FUEL reserve of 5 ticks of its own
  burn.
- **Neutral traders** trade only with neutral stations (the spec's rule).
- `assets\sprites\bases\` is unused but kept.

## Map editor (built 2026-11-05, plan `docs\superpowers\plans\2026-11-05-map-editor.md`)
- The galaxy is data now: `data\galaxy.json` (27 systems, 43 stations, 38 links as of 2026-11-06). `GalaxyData.build()`
  reads it and hard-fails on a missing or corrupt file (that path is untested: the assert would abort
  the run). Schema and decisions: `docs\superpowers\specs\2026-11-05-map-editor-design.md`.
- Balancing now happens by editing `data\galaxy.json` (presets, per-slot overrides, stock, quotas) or
  in the editor. The file is canonical: two-space JSON, fixed key order, systems and stations sorted
  by id, so a Save of an unchanged galaxy writes nothing and a one-system move is a one-line diff.
- Launch: `tools\map_editor.bat` (`GODOT_EXE` overrides the Steam path). Move / Link / Add System
  modes, Validate / Load / Save; Save is blocked while the errors list has a `[BLOCK]` item (click it
  to select the system or station). The Presets tab edits the six built-in presets and adds new ones.
- No player access: no game scene references the editor. **When `export_presets.cfg` is created, add
  the exclusion filter `scenes/editor/*, scripts/editor/*, tools/*`.** `data/galaxy.json` must ship.
- Station ids are the lower-cased name with spaces as `_`; renaming a station changes its id. No
  save games exist yet: flag it again when saving is built. No undo (Load re-reads the file).
- Unknown JSON keys survive load and save, but a whole number inside an unknown key comes back as
  `1.0` (Godot parses every JSON number as a float); `version`, `tier` and quota counts stay ints.
- Extending: a new per-system or per-station field is one entry in `EditorFields.SYSTEM_FIELDS` /
  `STATION_FIELDS`, plus the runtime code that reads it in `GalaxyData._make_system` / `_make_station`.
- `tests\test_campaign_scene.gd` failed in 2 of about 12 runs on the trader cargo checks (NPC jump
  cooldowns are unseeded random); not reproduced in 16 more. Treat it as a flake unless it recurs.

## Open ideas
- **Neutral vs pirate station services:** what makes them different to visit (black-market
  parts, bounties, smuggling, ...). User wants to revisit; v1 gives every base the same services.
- **Off-screen simulation:** not needed at 26 systems; perf has a ~30x margin. Revisit if the
  galaxy grows a lot.

## Repo state
- **Unpushed:** `main` is 64 commits ahead of origin (`03e243d` onward). Push only when asked.
- **Two sessions on one tree:** on 2026-11-05 the combat and map editor sessions committed to `main`
  together; something wiped `.superpowers\sdd\` mid-run. When running parallel sessions, agents
  must never `git clean` / `stash` / `checkout .`, must redirect test output to unique files, and
  must stage only their own hunks (`tests\run_tests.gd` still holds an unstaged reorder hunk from
  the map editor session).
- **Untracked root files:** `images.jpg` (the kitbash reference), `images.jpg.import`,
  `MEMORY.md`, `token-efficient-execution.md`, and a screenshot of the menu mockup
  (`Screenshot 2026-11-05 163940.png`). The user said to leave them alone.
- Never commit the `.import` churn or the CRLF-only noise in `project.godot` and
  `tests\test_campaign_scene_fleet_panel.gd`.

## Open backlog (deduplicated from older entries)

### Playtest and tune (waiting on the user)
- **Combat ranges (parked by the user 2026-11-05, keep marked):** sprites doubled but weapon ranges didn't, so guns reach about half as far
  relative to the hulls.
- **Frustum hatch:** is the 20%-opacity red hatch visible on dark space? Tune
  `FRUSTUM_HATCH_COLOR`.
- **Crew rework placeholders:** `WAGE_PER_10_CREW`, `CREW_HIRE_COST`, `SHIP_PRICE`,
  `MIN_CREW_EFFICIENCY`, `BattleResolution.ESCAPE_*` (a freighter or capital has about 10%
  against a corvette), `CREW_POOL_*`, the respawn penalty.
- **Crew quirks to raise:**
  - fewer than 10 billable crew costs no wages;
  - the slider can bypass the flagship floor;
  - the loot panel overlaps the fleet panel slot;
  - escapers keep their crew unbalanced.

### Combat
- **Capital selection ring:** the green 24 px `select_radius` circle hides under the capital
  sprite. The user said it's fine for now. Fix: scale the ring to the hull.
- **Click limitation:** a left click within 24 px of an own ship selects it instead of moving.
- **Combat AI:** built 2026-11-05; open items are under "Combat AI and orders".
- **VFX scale:** `HitSpark`, `SmokeTrail` and `EngineTrail` particles are still the pre-2x size.
- **PD/Interceptor missile-vs-drone bonus:** deferred. Needs new targeting infrastructure.

### Campaign
- **Missions:** the base overview button is a disabled placeholder (`# TODO` in the script).
- **Low-fuel warning:** not built.
- **Population feeding back into prices:** not built.
- **HomeBase has no ORE/FOOD producer** (only `refinery()` for fuel), so its seed stock drains
  under hauler traffic. See also Next steps 1 (fuel drain).

### Art
- **Ship mount counts:** the user is updating the art (capital 3 plates, freighter 0, corvette 1).
  Re-render with the `art\README.md` `--res` values (corvette 75, capital 122x111 at 80%,
  freighter 107), then re-place the mounts.
- **Station sprites:** a fleet parked on a station draws over its sprite (cosmetic).
- **Station follow-ups, when asked:**
  - per-faction accent re-renders;
  - more variety within a type (truss always puts the habitat at -X and the pier at +X);
  - larger renders if stations are shown above ~72 px.
- **Blender shared module:** move `Loft`, `Kit`, the materials, `organic_partition` /
  `shrink_quad`, `setup_scene`, `write_mounts`, the backdrop, the duplicated `skin` closure, the
  `mats` dict and `lerp_table`/`facet_loft` into `kitbash_common.py`. Verify all three ship scripts
  stay pixel-identical at their defaults.
- **Freighter variants** (`freighter_cargo`, `freighter_fuel`): ask whether still wanted.
- **Neon glow:** Godot 2D glow (WorldEnvironment with HDR 2D). Engine flames become a VFX.
- **Background art:** no starfield or nebula yet. Zoomed out, combat is plain grey.
- **Blender pipeline spec:** `docs\superpowers\specs\2026-10-31-pxl-art-pipeline-design.md` is
  superseded for ships and has no replacement.

### UI
- **Theme gaps:** LineEdit (debug console), OptionButton and SpinBox use the Godot defaults.
- **Minor review items:**
  - `_show_speed` in `speed_controls.gd` sets or clears the stylebox override every frame. Only
    touch it on a state change.
  - Disabled-button dashes can show a partial dash when the tiled width isn't a multiple of
    6 px. The README "never seams" wording overstates this.
  - `test_speed_controls.gd` emits `pressed` without flipping `button_pressed` like a real click.
  - Open: should the resume-speed text go white while paused? Currently `#9fd0ff`.

## NPC fleet scale (plan `docs\superpowers\plans6-11-06-npc-fleet-scale.md`)
- Task 1 (combat spawn layout + perf gate): `CombatScene.formation_points` places ships past the
  anchors in rows of 5 behind the line (`SHIP_SPACING` 120); 20 per side fit the 3200 arena.
- Perf, `tests\perf_combat.gd`, non-headless, invulnerable N-v-N corvettes (bar 8 / 33 ms):
  - 10v10: 1x avg 1.92 / max 2.75 ms, 5x avg 1.96 / max 3.16 ms;
  - 15v15: 1x avg 2.74 / max 4.59 ms, 5x avg 2.71 / max 4.83 ms;
  - 20v20: 1x avg 3.74 / max 5.92 ms, 5x avg 3.73 / max 7.86 ms.
- Gate passed at 15 and 20: `DangerTier.SECURITY_MAX_SHIPS := 15` (Task 2).
- `FleetBudget.TIER_BUDGET` retuned to {4, 10, 16, 24, 32} (was {3, 6, 10, 16, 22}) so seed-1 NPC ships
  reach the 3x test over `BASELINE_SHIPS` 170. Growth is capped per variant (`ship_count_range(v).y`;
  variant -1 keeps the global 15); `respawn_delay(variant, tier, budget)` only speeds up for output above
  the tier baseline budget.
- Task 4 (supply and long-run check): `tests\probe_galaxy.gd` is now in the repo (`-- --seed=7 --dur=3600`,
  `--verbose`, `--free-fuel`). With the new fleets, 1 h, seeds 7 / 11: jump rate 1.18 / 1.11 per s, 0 stranded,
  18 / 18 fleets dry at home (baseline 0-4): refinery output could not keep up with ~3.5x the ships' fuel use
  (`--free-fuel` gave 1.74 jumps/s, 0 dry). Fix: `refinery` preset `FUEL` 3.0 -> 6.0 in `data\galaxy.json` (the
  `EconomyRole.refinery()` default stays 3.0). Result: 1.74 / 1.70 jumps/s, 0 stranded, 3 / 2 dry at home
  (peak 6 / 5), no slot loss, 150 / 116 NPC skirmishes per hour (123 / 99 before the fix), NPC ships
  at 1 h 667 / 674 vs 622 / 626 at start (107-108%, the respawn refills faster than fights kill).
- Perf, `tests\perf_galaxy.gd`, non-headless, 145 fleets / 633 ships (bar 8 / 33 ms): 1x frame avg 1.95 /
  max 13.74 ms, 5x frame avg 2.16 / max 10.10 ms. The 1x physics-only max (44.99 ms) is a one-off
  hitch in the 600-frame window, not seen at 5x.
- Open playtest items: feel of pickets vs. security fleets; Flee against 10-15 ship fleets; fleet icons do not
  show ship count; pirate security odds early on.

## Rules and gotchas worth keeping

### Running Godot and tests
- Godot exe:
  `C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`
  (not on PATH; there is no console build).
- Tests: `& <exe> --headless --path . --script res://tests/run_tests.gd`. The non-console exe drops
  stdout unless run via `Start-Process -RedirectStandardOutput ... -Wait`. Redirect to a log file
  and read it; piping a backgrounded run through `grep` can look like a hang.
- New `class_name` files and new PNGs need one `--headless --editor --quit` warm pass before a
  `--script` run sees them. The pass rewrites `.import` files with CRLF-only diffs.
- **Known flake:** `test_campaign_long_run_sim.gd`, pirate-targeting failures; 4-8 lines per run
  since the 2026-11-05 economy rebalance (was 3-4; the count varies run to run). Any other FAIL in
  that file is real: jump-rate decay, a trader idling at home, or a station outside
  `KNOWN_SLOT_LOSS` losing a slot. A clean suite is that flake only, with no `SCRIPT ERROR`.
  Always grep for `SCRIPT ERROR`: one inside an async test aborts it without a FAIL line.
- `test_ai_controller_targeting.gd` is sensitive to test ordering. Put new async checks in their
  own file registered after it.
- A parse error can hang a `--script` run. Write stubs before a red run. Kill only your own
  process, never the editor process with `project.godot` on its command line.
- Panels that touch autoloads need `load()`, not `preload()`, in `run_tests.gd`.
- Screenshots: a non-headless `--script` with
  `root.get_viewport().get_texture().get_image().save_png()`, run via `Start-Process -Wait`. Await
  one `process_frame` before touching autoloads in `_initialize`. Warm passes create
  `images.jpg.import`; delete it afterwards.
- Layout checks on a freshly opened panel need `await tree.process_frame` first. Shared helper:
  `tests\ui_layout_check.gd`.

### GDScript
- A freed object fails ANY Object-typed parameter check (even `Object`). A function that guards
  with `is_instance_valid` must take an untyped parameter.
- Call `is_instance_valid(x)` before `x is T` or any member access on a roster that can hold freed
  nodes. `player_ships` keeps dead entries on purpose (indices align with `_player_spawned_indices`).
- Tests that kill every ship in one frame never see freed ships in deferred work. Free one, await
  two frames, then end the battle.
- Assigning a bare literal to a typed array through an untyped autoload ref is a SCRIPT ERROR. Use
  `.assign()`.
- `_rebuild_rows`-style UI rebuilds: `remove_child` before `queue_free`, or same-frame rebuilds
  stack rows.
- Any HUD panel drawn over the play area needs its background on `MOUSE_FILTER_STOP`, or clicks
  fall through to world input.
- Credits are always `int`.

### Files and git
- This file is tracked as lowercase `carry_forward.md`. Stage it under that name.
- In Git Bash, `sed -i` strips CRLF from `.gd` files. Patch with Python `newline=''` instead.
- Clearing `.import` line-ending churn: `git checkout --` doesn't clear it. Delete each file, then
  `git checkout -- <files>`, taking the list from `git status --porcelain`.
- Re-rendering in Blender changes PNG metadata even when pixels match. Compare pixels (Godot
  `Image.get_data()`) and `git checkout` unchanged files before committing.

### Art pipeline (Blender 5.2)
- Run Blender from PowerShell with `&`, not `start`.
- Follow memories `ship-art-direction` and `station-art-direction`. Show seeds side by side in the
  visual companion and let the user pick.
- Never render weapons into ship art. Mounts are bare plates plus `<out>.mounts.json`, which only
  matches the PNG it was rendered with (`--res` and `--preview` change the framing).
- Ships are in world px at `Sprite2D` scale 1; the camera provides zoom. After an art change,
  re-check `WeaponMount` and `Engine` positions in `scenes\ship\ship_*.tscn` against the JSON.
- New hull blocks use faceted outlines with dense stations. A plain `Loft` with few stations and
  `p >= 2` comes out domed. Detail must read at sprite size: geometry, not bump maps.
- UI renders: `Standard` view transform (AgX shifts the hex), glow from geometry (the Glare node
  drops glow on a transparent film), denoising off, geometry snapped to whole px. Cycles composites
  stacked partial-alpha layers brighter than the sRGB mockups.
- 9-slice textures: patterns tile, so the tiled centre must divide by the pattern period. Only
  straight runs cross into the tiled centre or edges; glows and brackets stay inside
  `texture_margin`.
- There's no PIL. Tile mixed-size renders with Blender's numpy.

### Process
- Build on `main` (memory `build-on-main`); follow `token-efficient-execution` for plans.
- Final whole-change reviews must trace the real bootstrap numbers and geometry. Task-level
  tests built with `ShipType.new_composition()` missed bugs that the hand-written bootstrap dicts
  in `campaign_scene.gd` exposed.
