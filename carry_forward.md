# Carry-Forward - SpaceGame 2026-11-09 (backgrounds: starfield wired and tuned, combat scenery built, for playtest)

Trimmed 2026-11-04, 2026-11-07 and 2026-11-09. Finished, committed work was removed; it lives in git
history (`git log -p -- carry_forward.md`). Only the current thread, open items and durable rules remain.

## Combat commands, idle start, pacing (built 2026-11-06/07, for playtest)
Spec: `docs\superpowers\specs\2026-11-06-combat-commands-pacing-design.md`. Plan: `docs\superpowers\plans\2026-11-06-combat-commands-pacing.md`
(4 tasks, all complete, final whole-branch review clean). Commits `0c69a12`..`d8be4b2`. Built via
`superpowers:subagent-driven-development`; the ledger at
`.superpowers\sdd\2026-11-06-combat-commands-pacing\progress.md` has the full task-by-task record
(bugs found, fix rounds, review verdicts) if more detail than below is ever needed.

- **Idle start:** ships spawn on `HOLD_POSITION` (no auto-hunt at battle start) at
  strength-sorted formation anchors (`CombatScene.strength_of`/`center_out_anchors` — strongest
  ship lands centre). **Only player ships are idle** — enemy AI still attacks from frame one
  (`ai_controller.gd` reissues `attack_target` every tick). That's a spec non-goal, not a bug, but
  it's the first thing anyone will see in a playtest and contradicts the spec's "every ship"
  wording at a glance.
- **Five orders:** Move, Hold, Attack, Protect, Flee. Protect screens toward the nearest in-reach
  threat (standoff scaled to both hulls' radii), falls back to attacking if its protectee dies.
  Attack/Protect auto-retarget when their target is lost mid-battle.
- **Input scheme** (revised live by the user across three rounds of feedback — the spec's "Input
  scheme" section is the authoritative text, not the plan's original pseudocode): left-click only
  selects/deselects; right-click is a smart default (attack an enemy under the cursor, else move)
  unless Move/Attack/Protect is armed (OrderBar button or M/A/P hotkey), in which case right-click
  resolves that command instead. Arming now toggles off on a second press of the same
  button/hotkey, and the OrderBar buttons show which command (if any) is currently armed.
- **Weapon focus and dodge:** ships fire only their best 1-2 weapons by dps
  (`Ship.primary_mounts`, keyed on mount identity so two mounts sharing one `load()`-cached
  Weapon resource don't both count toward the cap); PD always fires independently. Ships jink
  imperfectly (`_update_dodge`/`_dodge_vector`) when a projectile targeting them is in range.
- **Pacing:** all three hulls fly slower/heavier (`ShipEngine` values in the `.tscn` files). The
  five buyable refit engines (`resources\engines\*.tres`) were rescaled by the same ratios so a
  refitted ship doesn't undo the pacing change.
- Perf: `perf_combat.gd` at 10v10/15v15/20v20, well inside the 8ms avg/33ms max bar (max seen
  5.82ms).
- **Open, for the user's playtest pass:**
  - The spec asked for a run/kite probe (not just perf) after the speed retune — not done. The
    existing "untested run cases" note further below (hull speed vs. break/reset distance) is
    more likely to matter now that every hull is slower.
  - Does Protect read as "shooting things near the ally"? Does the slower pacing fix the fly-by
    complaint or just make everything slower? Does weapon focus look like a ship "committing"
    rather than going quiet?
  - Parked minors (non-blocking): `primary_weapons` (the old Weapon-identity ranker) is now dead
    code, superseded by `primary_mounts`; `strength_of` ignores current HP and randomized
    loadouts (acceptable per the spec's "placeholder balance metric" framing); `_update_dodge`
    doesn't check whether the incoming projectile is still approaching (can jink from one that's
    already passed); right-click mid-drag doesn't clear the drag state; refitting a corvette with
    a Dominion heavy/titan engine already drops its turn rate below `RUN_MIN_TURN_RATE` (flips it
    from RUN to PARK tactic) — pre-existing, not introduced by this plan.

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
  moved systems, link changes); the tests stale from those edits were fixed in commit `0cfd1d5`.
  `test_galaxy_data.gd` exempts `ironhold` from the pirate-needs-agriculture rule (TODO in the test):
  Ironhold is now a pirate station with a population slot and no pirate farm in range. User chose to
  leave the TODO in place for now (2026-11-06) rather than add agriculture or relax the rule.

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
3. **Open question for the user:** neutral haulers (`TRADER`) are still never pirate prey, even
   though neutral patrols now hunt and skirmish pirates (`_factions_hostile`, fixed 2026-11-05) —
   is that the intended split?
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

## Systems and Stations menu (built 2026-11-07, commits `7906ffd`..`dbdebef`, for playtest)
Spec: `docs\superpowers\specs\2026-11-07-systems-stations-menu-design.md`. Plan:
`docs\superpowers\plans\2026-11-07-systems-stations-menu.md`. Built via
`superpowers:subagent-driven-development` (3 tasks, all complete, final whole-branch review required
one fix round — commit `dbdebef`). Mockup (reference, final v24): `docs\superpowers\mockups\station-menu-final-v24.html`.
- `CampaignState` gained `game_day()` and `station_snapshots: Dictionary` (population, wealth,
  reputation, produces/consumes market rows), snapshotted per-station in `record_visit()` — same
  moment the jump-map's per-system snapshot already fires.
- `SystemsStationsPanel` (`scenes\ui\systems_stations_panel.tscn` / `scripts\ui\systems_stations_panel.gd`):
  left tree of visited systems (expand/collapse, faction-coloured station dots), right detail panel
  (header, population/wealth/reputation tiles, sortable PRODUCES/CONSUMES tables). Opens from a new
  "Systems" button on the HUD (`fleet_status_bar.tscn`), modal-exclusive with Fleet/Jump
  Map/engage/respawn exactly like the existing panels.
- The final review caught (and a fix round resolved) a real bug: the new campaign-scene test never
  freed its instantiated scene, which kept running `_physics_process` against a nulled `CampaignState`
  for the rest of the suite (27 `SCRIPT ERROR` lines) — and surfaced the same missing-`await`-after-
  `queue_free` bug, pre-existing on `main`, in three other campaign-scene tests
  (`test_campaign_scene_trading.gd`, `test_campaign_scene_fleet_panel.gd`, `test_campaign_scene.gd`).
  All four fixed the same way. Suite is now 0 `SCRIPT ERROR`, only the known long-run-sim flake.
- **Restyled toward the mockup 2026-11-07 (`96ebb97`):** tiles now span the row, the "MARKET (AS LAST
  SEEN)" header and green/red colour bars on the PRODUCES/CONSUMES group labels were added, the badge
  got its bordered box, and the station-list dots were fixed (were stretching into full-row bars).
- **Still open, for the user's playtest pass (remaining mockup-fidelity gaps):**
  - the PRODUCES/CONSUMES tables are still fixed-width (`COLUMN_WIDTHS` 160/100/100/100 px) inside the
    wider detail pane rather than filling it;
  - a selected-station row is still just white font colour; the mockup wants a gradient + left border;
  - no thousands separators on population; the tree still uses Godot's default right-hand scrollbar
    instead of the spec's left-edge one.
  - 5-widget HUD layout: `fleet_status_bar.tscn`'s button separation was tightened 16->8 to fit the new
    Systems button without colliding with SpeedControls; layout tests pass (no overlap/spill) but the
    visual tightness itself wasn't eyeballed.
- Parked minors (non-blocking): `_build_station_row` doesn't clear a font-color override on the
  non-selected path (harmless, tree rebuilds fully each time); the system-sort comparator re-resolves
  `galaxy.system(id)` per comparison instead of once; no automated test for the Jump Map vs Systems
  panel mutual exclusion (the guard is a one-line mirror of the tested Fleet case); re-pressing the
  Systems button while already open silently resets tree/selection state (same shape as the
  pre-existing Fleet button).

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
- **Unpushed:** `main` is 20 commits ahead of origin (`b280a50` onward). Push only when asked.
- **Two sessions on one tree:** on 2026-11-05 the combat and map editor sessions committed to `main`
  together; something wiped `.superpowers\sdd\` mid-run. When running parallel sessions, agents
  must never `git clean` / `stash` / `checkout .`, must redirect test output to unique files, and
  must stage only their own hunks.
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
- **Background art (brainstormed 2026-11-06):** starfield is now built and wired into both
  scenes (see below); nebula tint and the planet/asteroid placement library are still
  unbuilt. Scope agreed with the user: 30 campaign (system) backgrounds + 30 combat
  backgrounds, start small. Approach agreed: shared tileable
  starfield + subtle nebula-tint layers (soft localized color blobs, never a flat full-screen
  wash — the user was explicit about this), composited with a small library of standalone
  planet/moon/asteroid renders placed once per background at a fixed spot/scale (not baked as
  60 unique giant images). Combat arena is 3200x3200 with a pannable/zoomable camera
  (`CombatCamera`); campaign has no camera (fixed 1152x648 view) — this is why tiling/parallax
  was chosen over one big bespoke image per background.
  - **Starfield: built 2026-11-08, approved, and wired into both scenes 2026-11-08.** Design
    spec `docs\superpowers\specs\2026-11-08-starfield-wiring-design.md`. Decided this round:
    density category + seed are picked by a deterministic hash of the system id
    (`scripts\background\starfield_assignment.gd`, `StarfieldAssignment.pick`/
    `base_texture_path`) — no stored data, and combat reuses the same id as the system it's
    fought at (`CampaignState.player_fleet.system_id`), so a battle's background matches that
    system's map view. Assets copied from `art\blender\Starfield\` into
    `assets\sprites\backgrounds\starfield\` (lower-cased category folders +
    `depth_layers\`); the Blender output dir stays the source of truth. Campaign
    (`campaign_scene.tscn`/`.gd`): a `Background` `TextureRect` (`STRETCH_TILE`), first child,
    updated in `show_system()`. Combat (`combat_scene.tscn`/`.gd`, new
    `scenes\combat\combat_starfield.tscn` + `combat_starfield.gd`): a `ParallaxBackground`
    with 4 `ParallaxLayer`s (Base ~1.0, Deep ~0.9, Mid ~0.75, Foreground ~0.5 `motion_scale`,
    tuning values not rigorously tuned yet), first child, `setup()` called from `_ready()`.
    **Found and fixed a real tiling bug along the way:** a single un-tiled `Sprite2D` per
    layer only covers one 1024x1024 tile, leaving the rest of the 3200x3200 arena as bare
    grey canvas once the camera pans/zooms off it (caught via an in-engine screenshot, not by
    the test suite). Fixed by giving each layer's `Sprite2D` `region_enabled` +
    `region_rect` sized to the full arena (3200x3200) + `texture_repeat = 2` (GPU-tiles the
    1024px texture within that region), plus `motion_mirroring` matching the same 3200x3200
    so panning wraps seamlessly beyond it. `StarfieldAssignment` has a unit test
    (`tests\test_starfield_assignment.gd`); the full suite is a clean run (only the known
    `test_campaign_long_run_sim.gd` pirate-targeting flake) after also guarding against
    `CampaignState.player_fleet == null` (a real standalone-skirmish test fixture has no
    player fleet set at all).
  - **Nebula-tint layers and the planet/asteroid placement library are still separate,
    unbuilt pieces — out of scope for the starfield-wiring round above.** The recipe/
    assignment format for those (once their art is locked) is still undecided.
  - Generator (kept for reference, regenerate from here if the starfield art itself needs to
    change): `art\blender\starfield_generator.py`, run via `blender --background --python
    art\blender\starfield_generator.py`; pure `bpy`+numpy pixel authoring, no Cycles render —
    stars are stamped as Gaussian-falloff dots with a per-star reach that wraps toroidally at
    the tile edges, so every tile is seamlessly self-tileable. All generation knobs (seed,
    count, size range, brightness, color weights, cluster count/size, glow, background tint,
    resolution) are config dicts at the top of the script.
  - **Planets/moons: style approved.** Smooth Cycles spheres (not low-poly faceted, which would
    match the ship/station kit but read badly for round bodies), `shade_smooth` + ~128
    segments/64 rings, layered noise (coarse band noise x fine detail, bump-mapped), plus a
    thin Fresnel-driven emission shell for a soft atmosphere rim glow. Samples rendered:
    purple gas giant, red ringed gas giant, earthlike, icy moon — all approved as a good
    starting point. **Open feedback (2026-11-07, not yet acted on):** reads too much like
    polished marble; wants a soft hazy atmosphere instead of the current tight Fresnel rim.
  - **Asteroids: low-poly rejected, high-poly iteration in progress (2026-11-07).** Low-poly
    faceted rocks came out dark/muddy/flat; replaced with smooth-shaded high-poly geometry.
    Craters went through two more rounds against a reference photo (asteroid 16 Psyche): a
    shader-bump version was rejected as too shallow/speckly, then real carved-geometry
    craters (parabolic dished floor + raised rim, two size passes per rock) with the rim
    height then turned down after it read too raised. Material also moved from a warm tan to
    a cooler grey with a rust mineral-streak layer (still too pastel, needs retuning). Full
    detail, open issues and the live script (`art\blender\experiments\bg_preview.py`, not
    wired into the pipeline) are in
    `docs\superpowers\specs\2026-11-07-backgrounds-design.md` — read that before continuing
    this thread.
  - **Cluster render approved as-is (2026-11-07):** `asteroids_v3_seed1` (the 3-rock
    hero+escort cluster) is locked in, keep it unchanged. **Singles still need work:** the 4
    `rock_single_seed*` renders (bigger, elongated foreground rocks) were reviewed and
    rejected; the user will give a specific new prompt/direction for those before the next
    iteration. Latest preview artifact:
    https://claude.ai/code/artifact/5267b3c1-2c85-4804-aa85-edff863e2c44
  - Not yet decided: the "recipe" data format tying a background id to its tile/nebula/feature
    choices, how campaign system backgrounds (one per `StarSystem`) get assigned their
    background, and whether combat backgrounds are picked per-system or from a shared pool.
    No design spec locked yet. **Resolved for combat only, see below; campaign/system-view
    planet/asteroid placement is still unbuilt.**
  - **Combat scenery: built and wired 2026-11-09.** `scripts\background\combat_scenery.gd`
    (`class_name CombatScenery`) answers the recipe-format question above, for combat only: 5
    hand-authored `RECIPES`, each an `Array` of placement `Dictionary`s (`{type, texture,
    position, scale, radius}`), picked via `pick(id)` using the same
    `abs(hash(id)) % N` pattern as `StarfieldAssignment.pick`. Hand-placed rather than
    procedural — only 5 backdrops, so curating by eye beat a collision solver. `combat_starfield
    .tscn`/`.gd` replaced the one-off test `Planet`/`Foreground` layer with an empty `Scenery`
    `ParallaxLayer` (`motion_scale` 0.98, topmost); `setup()` instantiates one `Sprite2D` per
    placement from `CombatScenery.pick(system_id)` into it. The approved asteroid renders
    (24 `_small` variants + the `asteroids_v3_seed1` cluster) and planet/moon samples
    (earthlike, gas_red, gas_red_ring, moon_icy, gas_purple) are now safely copied into
    `assets\sprites\backgrounds\{asteroids,planets}\` — no longer only sitting in old session
    scratchpads. `tests\test_combat_scenery.gd` enforces determinism plus a geometric
    overlap invariant: same-type pairs (planet-planet, asteroid-asteroid) must never have
    `distance < radius_a + radius_b`; planet-asteroid pairs are exempt (asteroids are allowed
    to sit close to a planet). Every body is also checked against a hardcoded ship-box rect so
    scenery never reads as part of the fight. All 5 recipes screenshot-verified visually
    (non-headless `--script` via a `SubViewport` sized to the full 3200x3200 arena — the
    window itself gets clamped to the monitor's usable height, so render into a `SubViewport`
    instead of relying on `get_viewport()` on the main window for anything taller than screen
    resolution).
  - **Separate asteroid iteration thread (2026-11-07/08, approved "good for now"):** a different
    script, `art\blender\experiments\asteroid_variants.py` (ray-crater geometry, distinct from
    `bg_preview.py`'s `add_craters`; `asteroid_build.py` is its earlier single-preview
    predecessor, `asteroid.blend` the saved scene) — now committed in the repo, no longer only in
    a session temp scratchpad.
    - Material (`make_material`) retuned to the midpoint between `build.py`'s original softer
      noise/bump and a later, sharper pass: patch/rust noise scale and ramp widths, speckle
      mix, and bump strength all roughly halved back from the sharp version.
    - Found and fixed a real bug in `build_rock`'s crater carving: overlapping craters summed
      their bowl/rim displacement with no cap, so several bowls stacking could push a vertex
      past the body's center (flipping that patch inside-out into a detached "fin" silhouette)
      and several rim bulges stacking could do the same outward. Fixed with
      `total_disp = max(-base_len*0.55, min(total_disp, base_len*0.12))`. Separately, the ray
      crater's alternating-wedge shading (`cand_stripe`/`cand2`) read as a ring of "teeth"
      around the crater mouth even heavily turned down, so it was removed outright — crater
      floor/rim shading is now purely radial. Also tightened `facing_dir`'s bias and shrank the
      big craters' angular radius (0.46/0.32 -> 0.38/0.27) so a wide crater can't reach the
      grazing silhouette limb and project a crescent past the body outline.
    - `ALL_VARIANTS` now generates **4 seeds per shape type** (6 types: round, elongated, round
      cluster, elongated cluster, very elongated, many-companions = 24 renders), sized
      0.70/0.92/1.18/1.45 (small -> large); crater depth/rim and small-crater count scale with
      body size, small-crater centers use minimum-separation rejection against each other.
    - Approved by the user as-is. Latest contact sheet (all 24):
      https://claude.ai/code/artifact/5a018553-2ac6-4f14-b24a-df60f00f10f7
    - Render settings then gained `film_transparent = True` + RGBA output (the first batch was
      opaque black-background PNGs); all 24 re-rendered with alpha, confirmed with
      `GetPixel` (corner alpha 0, body alpha 255). Alpha contact sheet (checker backdrop):
      https://claude.ai/code/artifact/f71500bb-2bce-4801-bdd8-7e3de7f820ec
    - The native 1600x2000 renders run ~1.3-1.6 MB each. A `_small` set (512px wide, `.NET`
      `HighQualityBicubic` downsample of the full-res renders, not a re-render) was added
      alongside the originals — 171-192 KB each, all under the 200 KB target. Originals
      untouched. Both sets currently live only in the render output dir
      (`...\renders\variants\` and its `small\` subfolder) under the OS temp scratchpad above,
      not copied into the repo yet.
    - Open: not wired into any pipeline yet; still needs the "recipe"/placement decisions above;
      the companion small-rock material/crater recipe wasn't separately re-examined for the same
      overlap bug (only the main body was) — check it if companions ever look fin-y; the 24
      full-size + 24 `_small` renders themselves still need to be copied from the temp scratchpad
      into the repo (e.g. `art\blender\experiments\renders\`) before they're safe from loss.
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

Godot engine/editor and GDScript-specific rules moved to `godot_notes.md` (running tests, known
flakes, freed-object/typed-array gotchas, etc.) to keep this file smaller.

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
