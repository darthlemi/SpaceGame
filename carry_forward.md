# Carry-Forward - SpaceGame 2026-11-04 (star systems and jumping: spec + plan approved, not built)

Trimmed 2026-11-04. Finished, committed work was removed; it lives in git history
(`git log -p -- carry_forward.md`). Only the current thread, open items and durable rules remain.

## Completed this session
- Brainstormed sub-project 1 of "bigger world". The map is now a fixed galaxy of FTL-style
  systems, each the size of today's map, linked by jumps (no camera). This replaces the earlier
  pan/zoom camera idea.
- Spec approved: `docs\superpowers\specs\2026-11-04-star-systems-jumping-design.md` (`0ecf9d1`).
- Plan written: `docs\superpowers\plans\2026-11-04-star-systems-jumping.md` (`9da2d17`).
  - 5 tasks: galaxy model; station-based state; system layers in the scene; player jumping and
    jump map; AI jumping and the perf check.
  - The draft layout has 26 systems, 37 stations and 40 links. The table is in Task 1 and the
    user may adjust it.

## Next steps
1. **Waiting on the user:** review the plan and pick an execution method. Recommended:
   subagent-driven with batched reviews (one after Task 2, one after Tasks 3-4, a final review on
   the most capable model), started in a **fresh session** with only the spec and plan.
2. **Perf gate (plan Task 5):** if `tests\perf_galaxy.gd` misses the bar (8 ms average, 33 ms
   max, at 1x and 5x), stop and report. Don't build off-screen simulation unasked.
3. **Later sub-projects, in agreed order:**
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

## Star systems: calls the user should check while reading the plan
- **Caught mid-warp:** the user never answered this. As written, hostile contact during the
  countdown forces the engage prompt, and no new warp can start while a hostile is touching you.
- **Distress signal:** about 3x the base fuel price, delivered instantly. With no money and no
  fuel, you're stuck (the user's rule).
- **Every base is dockable and tradeable, pirate bases included** (the user's rule).
- **Bases:** every base uses the station renders with a faction-coloured ring. The old
  `assets\sprites\bases\` art becomes unused but is kept.

## Open ideas
- **Neutral vs pirate station services:** what makes them different to visit (black-market
  parts, bounties, smuggling, ...). User wants to revisit; v1 gives every base the same services.
- **Off-screen simulation:** v1 simulates every system in full. May need abstract off-screen
  simulation if the frame-time check fails or the galaxy grows.

## Repo state
- **Unpushed:** `main` is 23 commits ahead of origin (`03e243d` onward). Push only when asked.
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
  under hauler traffic.
- **Trader route reset after combat:** plan Task 3 absorbs this. Routes move to
  `CampaignFleet.dest_station_id`.

### Art
- **Ship mount counts:** the user is updating the art (capital 3 plates, freighter 0, corvette 1).
  Re-render with the `art\README.md` `--res` values (corvette 75, capital 122x111 at 80%,
  freighter 107), then re-place the mounts.
- **Stations into the game:** plan Tasks 1 and 3 (`CampaignStation`, art chosen per station in
  `GalaxyData`).
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
