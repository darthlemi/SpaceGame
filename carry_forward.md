# Carry-Forward - SpaceGame 2026-11-04 (bigger fleets / bigger world: brainstorm) - mid-brainstorm, no spec yet

Trimmed 2026-11-04. Finished, committed work was removed; it lives in git history
(`git log -p -- carry_forward.md`). Only the current thread, open items and durable rules remain.

## Current thread: bigger fleets, bigger world

### Findings in the current code
- `FleetAllocationPolicy`: `MAX_FLEETS = 4` per faction, `MAX_SHIPS_PER_FLEET = 3`. Ships are
  added one at a time, free, only on `GROW_COMBAT` (pirate threat) or `GROW_TRADE` (wealthy).
- New trade fleets start as one freighter (`CampaignState._grow_fleet`).
- Pirates never add ships, only crew (`PIRATE_CREW_REGEN`). No pirate base or economy.
- Factions have no credits: just a `BaseEconomy` stockpile and crew pool.
- The player has no hard ship cap. The 3 cap only applies in `_settle_player_defeat` captures.
- The campaign has no camera: a fixed 1152x648 view, fleets clamped to 4000x2400
  (`campaign_fleet_icon.gd` `MAP_MIN`/`MAP_MAX`). Bases are hand-placed in `campaign_scene.gd`.
- Combat has 3 spawn points per side (`combat_scene.gd` `player_spawn_points` /
  `enemy_spawn_points`). Extra ships reuse them (`points[k % size]` in `_spawn_fleet_from_data`).
- Overworld clump: `CLUMP_RADIUS` 36 caps ship spread regardless of fleet size, so 10-ship fleets
  will overlap on the map.

### Decisions (user's words, agreed in playbacks)
- **Fleet size:** 4-10 ships for every faction's fleets (pirates, patrols, convoys).
- **No hard cap:** a fleet's size is limited by what it can support in credits, crew and fuel.
  Same rule for the player and the AI.
- **AI cheats via discount:** AI pays for ships, crew and fuel like the player, but everything
  costs less. My proposal (not explicitly confirmed): a credit treasury per faction, fed by its
  economy and trade; one tunable discount (say 50%); crew from the base crew pool; fuel from the
  base stockpile. Losses must be rebuilt by saving up, so fleets visibly shrink and regrow.
- **Pirates become a full faction** with a base and economy. My guess, unconfirmed: they earn
  mainly by raiding, and stay hostile to the power factions.
- **Convoys:** freighters always travel with warship escorts. Bigger escorts on dangerous routes.
  My guesses, unconfirmed: danger comes from enemy strength near the route; a convoy that can't
  afford its escort waits in port.
- **Map:** each faction owns several bases across its own territory, plus neutral stations in
  between. The play area grows to fit, which needs a pan/zoom campaign camera. The 16-station
  art pool (`assets\sprites\stations\`) gets used here.

### Next steps
1. **Open question to the user:** agree the order of the three sub-projects. My recommendation:
   1. bigger map: campaign camera, multiple bases per faction, neutral stations, pirate base;
   2. AI economy and fleets: treasuries, discounted costs, 4-10 ship fleets that grow and
      shrink, escorted convoys;
   3. big battles: formation spawning for 10 ships per side, plus clump scaling on the map.
   The alternative is bigger fights on the current map first.
2. Continue brainstorming sub-project 1. Still to cover: hand-placed vs generated layout, base
   count, what neutral stations offer, camera controls. Write
   `docs\superpowers\specs\2026-11-04-<topic>-design.md`, run the builder check, then the plan.
3. Confirm the guesses marked above when brainstorming sub-project 2.

## Open ideas
- **Neutral vs pirate station services:** what makes them different to visit (black-market
  parts, bounties, smuggling, ...). User wants to revisit; v1 gives every base the same services.
- **Off-screen simulation:** v1 simulates every system in full. May need abstract off-screen
  simulation if the frame-time check fails or the galaxy grows.

## Repo state
- **Unpushed:** `main` is 19 commits ahead of origin (`03e243d` onward). Push only when asked.
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
- **Trader route reset after combat (parked, unverified since 2026-10-31):** returning from
  combat may reset in-flight traders' `_route_state`, causing a wasted round trip. The real fix
  is persisting the route state on `CampaignFleet`.

### Art
- **Ship mount counts:** the user is updating the art (capital 3 plates, freighter 0, corvette 1).
  Re-render with the `art\README.md` `--res` values (corvette 75, capital 122x111 at 80%,
  freighter 107), then re-place the mounts.
- **Stations into the game:** nothing uses the 16-station pool yet. Now part of sub-project 1.
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
- **Known flake:** `test_campaign_long_run_sim.gd`, 5-6 pirate-targeting failures. A clean suite
  is that flake only, with no `SCRIPT ERROR`. Always grep for `SCRIPT ERROR`: one inside an async
  test aborts it without a FAIL line.
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
