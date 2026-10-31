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
