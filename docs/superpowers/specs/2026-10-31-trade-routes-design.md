# Trade Routes — Design Spec

## Purpose

Milestone 4b (follow-up to 4a Core Economy). Gives Dominion and Freehold
autonomous NPC trader fleets that actually haul cargo to/from `HomeBase`,
keeping each faction's economy alive without a fixed sink/source, and lets
each faction grow or shrink its fleets (count and size) based on how well
it's doing economically and militarily. Also closes a gap left over from
4a: nothing currently produces Fuel on an ongoing basis, so Dominion's
industrial role starves no matter what once its one-time seed runs out.
Finally, defeating a cargo-carrying fleet in combat now yields loot.

## Fuel Refinery (closing the 4a gap)

`CampaignState.home_base_economy` gains a second slot: `EconomyRole.refinery()`,
producing a small ongoing trickle of `Commodity.Type.FUEL` (placeholder
rate, tuned like all other economy numbers — expect adjustment after the
integration test is in place). `home_base_economy.slots` becomes
`[trade_hub(), refinery()]`, `max_slots` raised to 2. This gives Dominion's
hauler (below) a renewing Fuel source instead of a finite seed.

## Faction Fleet Roles

`CampaignFleetIcon.BehaviorType` already has `TRADER`; faction fleets can
now use it. A fleet's role for allocation purposes is just its current
`behavior_type`: `COMBAT` means `PATROL` or `PIRATE` (whichever
`_behavior_for_faction` already picks from reputation), `TRADE` means
`TRADER`.

Each `PowerFaction` starts with 2 fleets: 1 `COMBAT`, 1 `TRADER` (bootstrap
change to `_bootstrap_default_campaign`). Counts and per-fleet ship counts
change at runtime per the allocation policy below.

## BaseEconomy Health Signals

`BaseEconomy` gains a `surplus_streak: int` counter alongside the existing
`deficit_streaks: Dictionary`. Each `tick()`, if no slot went into deficit
this tick, `surplus_streak += 1`; if any slot did, `surplus_streak = 0`.
`SURPLUS_STREAK_THRESHOLD := 5` (same scale as the existing
`DEFICIT_STREAK_THRESHOLD`) — reaching it means "economically strong."
"In deficit right now" means any entry in `deficit_streaks` is `> 0`.

`BaseEconomy` also gains `net_commodities() -> Dictionary` (Commodity ->
float), summing `produces` minus `consumes` across all slots. Positive =
surplus (faction can export it), negative = deficit (faction needs it).
Used both by the hauler load/unload logic and by nothing else — it's a
pure derived view over `slots`, not new state.

## Fleet Allocation Policy

New `FleetAllocationPolicy` (static pure functions, `scripts/campaign/behaviors/fleet_allocation_policy.gd`,
same style as `SkirmishResolution`). Evaluated per power faction on every
economy tick (`CampaignState.tick_economy`, after `BaseEconomy.tick()` runs
for that faction).

Inputs per faction:

- `economic_health`: `STRONG` if `surplus_streak >= SURPLUS_STREAK_THRESHOLD`,
  `DEFICIT` if any `deficit_streaks` entry is `> 0`, else `STABLE`.
- `threat_ratio := pirate_strength / max(faction_combat_strength, 1.0)`,
  where `pirate_strength` is `total_strength()` summed over all pirate
  fleets currently in `CampaignState.enemy_fleets`, and
  `faction_combat_strength` is `total_strength()` summed over the
  faction's `COMBAT`-role fleets only.

Decision, in priority order:

1. **`threat_ratio > DANGER_THRESHOLD`** (feels weaker than pirates): the
   faction needs more combat power.
   - If `economic_health != DEFICIT` (can afford it): grow — add a ship to
     an existing `COMBAT` fleet if one exists and is below
     `MAX_SHIPS_PER_FLEET`, else spawn a new single-ship `COMBAT` fleet (if
     below `MAX_FLEETS`).
   - Else (economy already in deficit, can't afford new ships): reallocate
     instead — flip one `TRADER` fleet to `COMBAT`, but never the faction's
     last `TRADER` fleet (keeps at least one hauler running so the economy
     can recover).
2. **`economic_health == STRONG` and `threat_ratio < SAFE_THRESHOLD`**
   (comfortably stronger than pirates): grow — add a ship to an existing
   `TRADER` fleet if below `MAX_SHIPS_PER_FLEET`, else spawn a new
   single-ship `TRADER` fleet (if below `MAX_FLEETS`).
3. Otherwise: no change.

Constants (placeholders, tune during testing): `DANGER_THRESHOLD := 1.2`,
`SAFE_THRESHOLD := 0.6`, `MAX_FLEETS := 4` (per faction), `MAX_SHIPS_PER_FLEET := 3`.

Applying a decision:

- **Spawn new fleet**: create a `CampaignFleet` (single ship, same template
  stats as existing starter ships), append to `CampaignState.enemy_fleets`,
  call `CampaignScene._spawn_icon()` with the new fleet and the resolved
  `BehaviorType`. Requires `CampaignScene` to expose this as a method
  callable from a signal/poll rather than only at `_ready` (small
  refactor — `_spawn_icon` itself is unchanged, just called again later).
- **Add ship to existing fleet**: append a new ship dict (same template) to
  that fleet's `ship_compositions`.
- **Flip fleet role**: change that fleet's `CampaignFleetIcon.behavior_type`
  directly (`COMBAT` <-> `TRADER`); if flipping to `TRADER`, the icon's
  `_route_state` resets to `TO_BASE` next frame's `_process_trader()` call
  naturally handles this since it recomputes from current position.
- **Shrink** (not driven by this policy directly — see Trader Hauling
  below for the only shrink path this milestone: losing a fleet to
  combat/skirmish works exactly as it does today, no new code).

## Trader Hauling

A `TRADER`-role faction fleet's icon reuses `TraderBehavior`'s existing
route state machine, retargeted per-faction:

- `_home_position` = that faction's `FactionBase` position (was the fixed
  `HOME_BASE_POSITION` for the generic trader).
- the "away" point = `HOME_BASE_POSITION` (was the fleet's spawn point).

`CampaignFleetIcon` needs a way to know which position is "home" vs "away"
per fleet rather than the single shared `_home_position` it has today;
simplest fix is passing both target positions into `setup()` explicitly
instead of deriving the away point from spawn position, for `TRADER`-role
icons specifically (`PATROL`/`PIRATE` icons keep using spawn-point-based
wander, unchanged).

New `CampaignState.run_npc_trade(fleet: CampaignFleet, base_economy: BaseEconomy, loading_at_home: bool) -> void`,
called when a `TRADER` icon's route state flips (arrives at either
endpoint) — no currency involved, just stock <-> cargo transfer:

- **At faction base** (`loading_at_home = true`): for each commodity with
  positive `net_commodities()`, move `min(available stock, remaining cargo
  space)` from `base_economy.stock` into `fleet.cargo`.
- **At HomeBase** (`loading_at_home = false`): first dump all of
  `fleet.cargo` into `home_base_economy.stock` (clearing cargo), then for
  each commodity with negative `net_commodities()` on the fleet's *own*
  faction (not HomeBase's), load `min(available home stock, remaining
  cargo space)` into `fleet.cargo`.
- Next arrival back at the faction base dumps that deficit cargo into the
  faction's own `stock` — the actual resupply.

This means NPC hauling reads/writes the exact same `home_base_economy.stock`
the player already trades against in `TradePanel` — prices the player sees
move as a side effect of faction logistics, which is intended, not a bug.

Flee-from-player (`TraderBehavior.should_flee`/`flee_target`) is unchanged.
Pirate interception of a hauler works with zero new code: hostility
(`CampaignState.are_hostile`) is keyed on `CampaignFleet.faction`, not
`behavior_type`, so a `TRADER`-role Dominion fleet is still exactly as
hostile-to-pirates as a `COMBAT`-role one.

## Loot on Raid

When the player defeats an enemy fleet in combat and that fleet's
`cargo_total() > 0`, `CampaignState.resolve_engagement` emits a new
`loot_available(fleet: CampaignFleet)` signal before clearing
`active_enemy_fleet` — fleets with empty cargo (pirates, patrol fleets,
`COMBAT`-role faction fleets) never trigger it.

New `LootPanel` Control (`scenes/campaign/loot_panel.tscn` +
`scripts/campaign/loot_panel.gd`), structurally identical to `TradePanel`:
one row per commodity present in the defeated fleet's cargo, a label
showing the amount, and a "Take" button moving 1 unit at a time from the
defeated fleet's `cargo` into `CampaignState.player_fleet.cargo`. A button
disables itself once the player's cargo is full or that commodity is
exhausted on the defeated fleet. `CampaignScene` listens for
`loot_available`, opens `LootPanel` with the defeated fleet's cargo.
Closing the panel (Close button, same as `TradePanel`) discards whatever
cargo remains untaken — no partial-loot persistence, matching how a
defeated fleet already disappears from the simulation today.

## Data Flow

1. `CampaignScene._bootstrap_default_campaign()`: each `PowerFaction`
   starts with 2 fleets (1 `COMBAT`, 1 `TRADER`); `home_base_economy`
   gains `refinery()`.
2. Every economy tick: each `BaseEconomy.tick()` runs as today, now also
   updating `surplus_streak`. Then, per faction, `FleetAllocationPolicy`
   evaluates and applies at most one growth/reallocation step.
3. Every physics frame, `TRADER`-role icons run the retargeted
   `TraderBehavior` route; arrival at either endpoint calls
   `CampaignState.run_npc_trade()`.
4. Existing hostility/skirmish/player-engagement logic is unchanged — a
   hauler is just a `CampaignFleet` with `behavior_type = TRADER`.
5. On player victory over a cargo-carrying fleet, `resolve_engagement`
   emits `loot_available`; `CampaignScene` opens `LootPanel`.

## Testing

Following the existing pure-function-first pattern:

- `test_base_economy.gd` additions: `net_commodities()` sums
  produces-minus-consumes correctly; `surplus_streak` increments on a
  clean tick and resets to 0 on any deficit.
- `test_fleet_allocation_policy.gd`: danger+deficit reallocates and never
  strips the last trader; danger+healthy grows a combat fleet/ship;
  strong+safe grows a trade fleet/ship; stable case produces no change;
  `MAX_FLEETS`/`MAX_SHIPS_PER_FLEET` caps are respected.
- `test_trader_behavior.gd` additions: route state machine works correctly
  with faction-base-as-home / HomeBase-as-away (same logic, different
  inputs — confirms the retargeting doesn't require new route logic).
- `test_economy_role.gd` addition: `refinery()` produces the expected Fuel
  amount, consumes nothing.
- `test_campaign_state.gd` additions: `run_npc_trade` moves surplus
  base->cargo and deficit home->cargo, both capacity-bounded; dumping
  cargo at HomeBase increases `home_base_economy.stock`.
- A scene-tree integration test driving a `TRADER` icon through one full
  route (faction base -> HomeBase -> faction base), asserting stock moved
  both directions as expected.
- A scene-tree integration test for `LootPanel`: defeat a cargo-carrying
  fleet, confirm the panel opens with correct rows, "Take" respects cargo
  capacity, closing discards the remainder.

## Out of Scope (this milestone)

- Direct Freehold<->Dominion trade routes (everything flows through
  HomeBase only, per design discussion — avoids faction-vs-faction combat
  triggered by crossing hostile territory).
- Per-faction credits/currency (profit stays abstract — commodities moving
  to where they're needed, no currency tracked for factions).
- Fleet shrink driven by the allocation policy itself (shrinking only
  happens via existing combat/skirmish loss paths, unchanged).
- Any UI surfacing faction fleet counts/roles to the player.
- Direct balance tuning pass beyond placeholder constants — expect a
  follow-up pass once this is playable, same as 4a.
