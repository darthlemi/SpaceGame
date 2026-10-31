# Carry Forward — 2026-10-31 session

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
