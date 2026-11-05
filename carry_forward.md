# Carry-Forward - SpaceGame 2026-11-05 (star systems and jumping: built; 3 user decisions open)

Trimmed 2026-11-04. Finished, committed work was removed; it lives in git history
(`git log -p -- carry_forward.md`). Only the current thread, open items and durable rules remain.

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
- Rulings made during execution (19, each with its cost if wrong) are in the SDD ledger
  `.superpowers\sdd\2026-11-04-star-systems-jumping\progress.md`. Delete that folder once the
  decisions below are made.

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

## Star systems: calls built as "my call", for the user to playtest
- **Caught mid-warp:** never answered. Hostile contact during the countdown forces the engage
  prompt, and no new warp can start while a hostile is touching you. Only fleets with pirate
  behaviour catch you; traders never do.
- **Distress signal:** 3x the base fuel price, delivered instantly; hidden whenever a connected
  jump is affordable.
- **Pirate citadels** (Ashfall, Deadreach) switched from `population` to `agriculture` so they
  don't starve. The user may re-tune `galaxy_data.gd`, which now also takes an optional `tier`
  key per system.
- **NPC tuning:** fuel for 4 jumps, raids and hunts end after 75 s away (`RAID_DWELL`,
  `HUNT_DWELL`), a 90 s rest at home (`HOME_REST`), a station FUEL reserve of 5 ticks of its own
  burn.
- **Neutral traders** trade only with neutral stations (the spec's rule).
- `assets\sprites\bases\` is unused but kept.

## Open ideas
- **Neutral vs pirate station services:** what makes them different to visit (black-market
  parts, bounties, smuggling, ...). User wants to revisit; v1 gives every base the same services.
- **Off-screen simulation:** not needed at 26 systems; perf has a ~30x margin. Revisit if the
  galaxy grows a lot.

## Repo state
- **Unpushed:** `main` is 32 commits ahead of origin (`03e243d` onward). Push only when asked.
- **Untracked root files:** `images.jpg` (the kitbash reference), `images.jpg.import`,
  `MEMORY.md`, `token-efficient-execution.md`. The user said to leave them alone.
- Never commit the `.import` churn or the CRLF-only noise in `project.godot` and
  `tests\test_campaign_scene_fleet_panel.gd`.

## Open backlog (deduplicated from older entries)

### Playtest and tune (waiting on the user)
- **Combat ranges:** sprites doubled but weapon ranges didn't, so guns reach about half as far
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
- **Combat AI:**
  - ships attacking the same target from similar bearings stack (no ally separation);
  - the standoff ignores the enemy's range (no kiting of outranged targets);
  - there is no hold-position stance;
  - PD weapons count toward the dps share, so PD-heavy loadouts close to PD range.
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
- **Known flake:** `test_campaign_long_run_sim.gd`, 3-4 pirate-targeting failures (3, 3 and 4 in
  three runs after the 2026-11-04 final fix round; the count varies run to run). Any other FAIL in
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
