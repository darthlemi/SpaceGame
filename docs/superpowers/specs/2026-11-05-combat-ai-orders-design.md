# Combat AI and Orders - Design

Date: 2026-11-05. Status: approved by the user 2026-11-05.
Research behind it (not in the repo):
`C:\Users\c_dirks\AppData\Local\Temp\claude\7f8633d840d3c804\51be9291-a679-44ab-a75f-35b440181b48\scratchpad\combat_ai_research.md`.

## Intent

Ships should fight like the ship they are, using the weapons they actually carry. Today
every ship hunts the nearest enemy, parks at one standoff range, stacks on top of allies
and drifts away at 25% hull. The player also lacks two basic orders: hold position and
flee the battle.

Success: a fight where corvettes with railguns make strafing runs, turret capitals hold
the line at range, a ship that outranges its target kites it, allies spread around a
target instead of stacking, and the player can pin ships in place or pull a ship out of
the battle at a real cost.

## Goals

1. **Automatic behaviour from hull and weapons** (no player setting): engagement range,
   positioning, target choice and when to flee.
2. **Hold Position** order for the player.
3. **Flee** order: the ship leaves the battle after a spool-up that damage resets. AI ships
   use the same flee.
4. **Order bar** in combat plus hotkeys.

## Non-goals

- **Weapon range rebalance** (guns reach about half as far relative to the doubled
  sprites). Parked by the user; stays on the carry-forward backlog.
- **Stance dial** (Cautious / Steady / Aggressive). The user chose automatic behaviour
  "for now".
- **PD shooting down missiles.** Projectiles aren't targetable today; that needs new
  targeting infrastructure (already a deferred backlog item).
- **Drone behaviour.** `DroneBay` is not wired into any combat scene today.
- **Campaign-level changes** (pirate crew-based retreat, economy, trade), except the
  re-engage delay below.
- Guard / leash and escort orders.

## Anti-goals (a failure even if it technically works)

- **Free escapes.** Flee must not be a zero-cost way to save a dying ship, or a way to
  dip in and out of a fight.
- **Opaque behaviour.** If the player can't tell why a ship is doing something, it's
  wrong. Flee state must be visible on every ship (own and enemy).
- **Jitter.** Ships flipping between states every frame (kite / close / kite, flee /
  fight / flee).
- **Perf regression.** The campaign perf bar is 8 ms avg / 33 ms max; combat must stay
  smooth with 10-ship fleets per side (future fleet size 4-10).

## Constraints

- Godot 4, GDScript, existing structure: `Ship` (`scripts\ship\ship.gd`) runs orders and
  movement, `AIController` (`scripts\controllers\ai_controller.gd`) drives enemy ships
  only, `FleetCommander` (`scripts\controllers\fleet_commander.gd`) handles player input.
  Player ships have no `AIController`; with no order they run `Order.HOLD`, which today
  means "idle: engage the nearest enemy, loiter when none".
- Ship-level behaviour (range, positioning, targeting, separation) lives on `Ship`, so it
  improves both sides. AI-only decisions (when to flee) live in `AIController`.
- Arena is 2304 x 1296 with walls (`Bounds`). Weapon ranges are 120-500.
- Battle end today: a side with no armed active ship loses; surviving losers roll
  `BattleResolution.escape_chance`; results go to `CampaignState.resolve_engagement`.
- Tests: pytest is not used here; the project has its own GDScript test runner
  (`tests\run_tests.gd`). Follow the carry-forward rules (no `SCRIPT ERROR`, known
  long-run-sim flake only).

## Decided by the user

### Flee
- A fleeing ship **leaves the battle entirely**.
- The cost is **time under fire**: the ship charges a jump spool-up, and **damage resets
  the spool to zero**.
- The player's flee order always wins over any automatic behaviour.

### Behaviour
- Behaviour comes **automatically from hull and weapons**. No stance dial for now.

### Orders UI
- **Hotkeys plus a small order bar** (option A of the mockups):
  - bottom centre of the combat screen;
  - buttons: `Hold [H]`, `Flee [F]`, `Formation: <active> ^`;
  - the Formation button opens a small pop-up listing Free 1 / Line 2 / Wedge 3 / Box 4 /
    Circle 5 with the active one highlighted; picking one closes the pop-up;
  - the 1-5 hotkeys keep working without opening the pop-up;
  - speed controls stay where they are (top right).

### Re-engage delay (campaign)
- After any battle in which both fleets still exist, those two fleets can't engage each
  other again for a short delay, "to mimic getting all your loot etc after a battle".
- This also stops "flee, repair, re-engage, repeat" from being instant.
- Claude's calls inside it: about 10 s of campaign time (tunable); it applies only to that
  pair of fleets, not to the fleets in general; it blocks both the player's engage prompt
  and NPC interception (pirate and patrol behaviours) between the pair; the player can
  still be engaged by any other fleet.

## Decided by Claude (accepted by the user without changes; easy to revisit)

### Flee details
- **No map-edge requirement.** The jump fires anywhere once the spool completes. While
  spooling, the ship flies at full speed away from the nearby enemies (away from their
  centroid, steering off walls), so running for the edge is the natural move.
- **What resets the spool:** any damage that gets past shields (hull or component hits).
  Hits fully absorbed by shields do not reset it, so shields buy the escape and
  shield-stripping weapons are the counter. Pierce damage (railgun 25%, lance 20%) counts:
  it reaches the hull even through full shields, which makes those guns the anti-flee
  weapon (Claude's call, from the builder check).
- **Spool time:** about 6 s for a corvette or freighter, about 8 s for a capital
  (tunable constants).
- **Fire while fleeing:** mounts that bear may fire; the ship never turns to aim. In
  practice that is missiles and PD, since the other turrets have forward 90-140 degree
  arcs and the ship is pointed away.
- **Visibility:** an orange spool bar under every fleeing ship, own and enemy, filling as
  it charges and dropping to empty on a reset. A short flash when the ship jumps out.
- **Battle accounting:** a ship that jumps out counts as escaped. It never rolls the
  end-of-battle escape chance and can't be captured. Its hull, crew and component state at
  the moment of the jump is what returns to the campaign.
- **Battle end:** a fled ship is no longer on the field, so the existing rule applies: a
  side with no armed active ship left loses, and any ships it left behind (for example an
  unarmed freighter) roll the existing escape chance.
- **Cancelling:** a new move or attack order cancels the flee and drops the spool.
- **Result label:** when the player's side ends the battle by fleeing (no armed ship left
  on the field because they jumped out, not because they died), show "Withdrew" instead of
  "Defeat". Campaign accounting is unchanged (it is still a loss).

### Hold Position (StarCraft II rules)
- The ship stops and stays at its anchor point.
- It turns freely to bring weapons to bear and fires at anything in range.
- It never chases, even when shot from outside its range.
- A new move, attack or flee order cancels it.
- This is a new order type. The existing `Order.HOLD` (idle auto-engage) keeps its
  behaviour; the builder may rename it for clarity.

### Automatic behaviour
- **PD excluded from range choice.** PD weapons (`pd_flak_turret`, `pd_laser_turret`) do
  not count in the standoff / dps-share calculation. PD still fires at any ship in its
  range (it has nothing else to shoot until missiles are targetable).
- **Range to hull edge.** Standoff and in-range checks measure to the target's hull edge
  (centre distance minus hit radius), not its centre.
- **Attack runs for fixed-forward ships.** A ship whose main damage comes from narrow-arc
  fixed weapons (railgun, torpedo, lance: 10-degree arcs) makes runs: turn onto the
  target, close to range, fire as it bears, pass or break off, loop round, repeat. Ships
  whose main damage is turreted park at standoff as today (fixed point on the
  target-to-ship line, nose on target).
- **Weapons pick the tactic, agility gates it** (Claude's call, from the builder check):
  - narrow-arc main damage + agile hull (corvette) -> attack runs;
  - narrow-arc main damage + slow hull (capital) -> park nose-on at standoff (runs at
    turn rate 1.0 would waste most of the fight turning);
  - turreted main damage -> park at standoff, kiting when the kite rule applies;
  - the hull also sets the flee threshold (below).
- **Kiting.** If a ship's standoff range exceeds the target's longest non-PD range, it
  holds just outside the target's range and backs off when the target closes. Only
  worth it when the ship isn't slower than the target; a slower ship just fights at its
  normal standoff.
- **Spread out.** Allies attacking the same target take distinct approach angles around
  it, plus light separation steering between nearby friendly hulls.
- **Target scoring** replaces nearest-enemy. Factors:
  - distance (to hull edge);
  - time to turn onto the target (matters most for fixed-forward ships);
  - weapon vs shield match (shield_mult-heavy loadouts prefer shields up; hull_mult /
    pierce-heavy loadouts prefer shields down);
  - low remaining hull, weighted by the threat the target still poses;
  - a reluctance to switch away from the current target.
  Explicit player attack orders always override the score.
- **Hull roles** (how the rule above plays out with typical loadouts):
  - corvette: skirmisher - kites or makes runs; AI flees early;
  - capital: line ship - parks at range; AI flees last;
  - freighter: unarmed - AI flees once an enemy is within weapon reach (see below).
- **AI flee threshold by hull** (tunable), measured against each ship's hull **at battle
  start**, so a ship that arrives damaged doesn't flee at spawn: a corvette flees after
  losing about 65% of the hull it came in with, a capital about 85%. Freighters flee once
  an enemy is within weapon reach of them (about 500 px), not from spawn. A freighter that
  gets away keeps its cargo: that is the price of not catching it. (Claude's call after
  the builder check; the user didn't object.) Hysteresis is not needed once flee is committed: an AI ship that
  starts fleeing keeps fleeing until it jumps out or dies.
- **Player ships never flee on their own.** Only the player's order makes them flee.

## Left to the builder

- Exact constants: spool times, flee thresholds, separation radius, kite margin, score
  weights, the dps share that marks a ship as "fixed-forward".
- How PD is marked (recommended: a role field on `Weapon` rather than matching names).
- How attack runs are shaped (break-off distance, loop radius), as long as narrow-arc
  ships get repeated firing passes instead of parking.
- The order bar's exact styling within the existing holo theme (`assets\ui\theme.tres`);
  disabled when nothing is selected; its background must be `MOUSE_FILTER_STOP` so clicks
  don't fall through to world input.
- Whether Hold / Flee buttons show a toggled state for the current selection.
- Hotkeys H and F; check for conflicts with existing input actions first.
- Splitting `ship.gd` (279 lines) if the new behaviour would bloat it.

## Testing

- Unit tests for the pure parts: range choice without PD, hull-edge range, fixed-forward
  detection, target scoring, kite decision, spool reset rules, flee threshold by hull.
- Scene tests: a flee that completes removes the ship and reports it escaped; a hit past
  shields resets the spool, a shield-absorbed hit doesn't; Hold Position doesn't move or
  chase; battle end when the last armed ship flees.
- A manual playtest pass by the user on feel (runs, kiting, spacing, flee cost).
