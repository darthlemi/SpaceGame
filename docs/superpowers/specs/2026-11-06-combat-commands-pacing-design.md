# Combat Commands, Idle Start and Pacing — Design Spec

Covers the 2026-11-06 combat request list from `carry_forward.md` (numbering is
the user's; there is no item 3):
1. idle formation start (no auto-move/auto-attack at battle start);
2. fleet commands (Move / Hold / Attack / Protect / Flee) with a redesigned
   click scheme;
4. AI weapon focus, imperfect dodging, and slower/heavier ship movement.

Two calls made with the user before writing this spec:
- **Order-target-loss:** when an Attack or Protect order's target dies, the
  ship auto-retargets the nearest/best enemy and keeps acting on the same
  command, rather than reverting to idle.
- **Command naming:** the existing Hold Position order and its `H` hotkey
  keep the name "Hold" (not renamed "Halt") in the new five-command set.

## Goals

- At battle start, every ship (player and enemy) spawns anchored and
  passive: it does not seek a target or move, but still fires at anything
  that drifts into its own weapon range (today's defensive autofire is
  already order-independent — see `Ship._process_weapons` /
  `Ship.pick_autofire_target` — so this is unchanged).
- Spawn formation sorts ships by strength: the strongest ship on the
  centre-most spawn anchor, the next two on the anchors flanking it, and so
  on outward; weakest/support ships land in the rear rows that
  `CombatScene.formation_points` already generates for fleets bigger than
  the anchor count.
- Five player commands — Move, Hold, Attack, Protect, Flee — issued by
  right-click, with left-click doing selection only.
- A new Protect order: selected ships hold a standoff distance from the
  protectee and fire on threats near it.
- Ships favour their 1-2 best weapons against the current target instead of
  firing every mount that can bear, and gain a small imperfect jink against
  incoming fire.
- Corvette (and capital/freighter) movement is slowed down — speed,
  acceleration and turn rate — so flights read as flying, not darting.

## Non-goals

- Command-button iconography and square-button art: a separate, later task
  (per the user's 2.5). This spec only places plain-text/placeholder
  buttons.
- No changes to `CombatTactics.tactic_for`'s RUN/PARK split or the
  run-break geometry itself. Slowing ships down changes the *numbers* that
  feed that geometry (closing speed, break distance), not the algorithm;
  retuning those constants if runs start looking wrong is implementation
  work, not a design change.
- No new ship classes, hulls, or weapons.
- No pathing/obstacle avoidance beyond the existing steer-to/hold-station
  primitives in `ShipEngine`.
- Enemy `AIController` ship behaviour (target picking, flee thresholds) is
  unchanged except where it inherits shared code (weapon focus, dodging,
  movement tuning) — it already overrides its ship's order every physics
  tick, so the new idle spawn order never shows on enemy ships in practice.

## 1. Idle formation start

### Spawn order

`Ship._ready()` currently calls `execute_order(Order.hold())`, which (via
`_process_hold`) immediately hunts the best-scored enemy anywhere on the
field and moves to engage it — the "auto attack and move" the user wants
gone. Change the default to `execute_order(Order.hold_position())`.
`_process_hold_position` already does exactly what's wanted: it anchors at
`global_position` (captured at `_ready`, i.e. the spawn point), never
moves, and only turns to face + autofire at an enemy already inside
`attack_range()`. No change needed to that function.

This is a one-line default-order change; `Order.hold()`'s hunting behaviour
stays as-is for its other callers (what a ship falls back to once it has
chased down and lost its last `MOVE_TO`/retreat destination — unaffected by
this spec).

### Strength-sorted formation

`CombatScene.formation_points(anchors, count, facing)` places the first
`min(count, anchors.size())` ships on the anchors in the order given, then
overflow ships in rows behind. Today the anchor order is just
`player_spawn_points`'s declared order, and ships map onto it in fleet-data
order — no strength sorting.

Add:
- `FleetCommander.strength_of(comp: Dictionary) -> float` (or an equivalent
  pure helper near `ShipType`): `ShipType.BASE_STATS[kind]["max_hp"]` plus
  the fleet composition's total weapon DPS (`CombatTactics.weapon_dps`
  summed over its loadout). A placeholder balance metric — the hull/DPS mix
  is a tuning knob, not a design blocker.
- `CombatScene.center_out_anchors(anchors: Array[Vector2]) -> Array[Vector2]`:
  reorders a spawn-point list by distance from the group's lateral centre,
  alternating sides (centre-most first, then next-closest right, then
  next-closest left, ...), so mapping a strength-descending ship list onto
  it puts the strongest ship in the middle and the next-strongest flanking
  it.
- `_spawn_fleet_from_data`/`_spawn_fleet` sort the incoming ship list by
  `strength_of` (descending) before calling `formation_points`, and pass
  `center_out_anchors(points)` instead of `points` directly. Overflow ships
  (already weakest, since the list is strength-sorted) land in the rear
  rows unchanged.

## 2. Fleet commands

### Order model

`Order.Type` gains `PROTECT` alongside the existing `MOVE_TO`,
`ATTACK_TARGET`, `HOLD`, `RETREAT`, `HOLD_POSITION`, `FLEE`. New
constructor `Order.protect(ship: Node2D) -> Order` mirrors
`attack_target()`, storing the protectee in `target_ship`.

The five user-facing commands map onto existing/new order machinery:

| Command | Hotkey | `Order.Type` used |
|---|---|---|
| Move | M | `MOVE_TO` (exists) |
| Hold | H | `HOLD_POSITION` (exists, keeps its name/hotkey) |
| Attack | A | `ATTACK_TARGET` (exists) |
| Protect | P | `PROTECT` (new) |
| Flee | F | `FLEE` (exists) |

### Input scheme

Per the user's 2.2: left-click selects only (box-select and single-select,
unchanged from today); right-click issues the **armed command** and clears
selection. This replaces `FleetCommander`'s current split, where left-click
on empty space issues a move/attack order and right-click only clears
selection (`_on_left_release` / `_on_right_press`).

- `OrderBar` gains an "armed command" concept: five square buttons (Move,
  Hold, Attack, Protect, Flee), mutually exclusive like the existing
  formation popup's `ButtonGroup`, each togglable by its hotkey. Hold and
  Flee keep emitting their existing immediate-fire signals too (they don't
  need a target, so clicking the button can fire them directly at the
  current selection, same as today) — Move/Attack/Protect need a
  right-click in the arena to supply a position or target, so arming them
  just sets the pending command; nothing happens until the right-click.
- `FleetCommander._on_right_press()` becomes: if a command is armed and
  there's a live selection, resolve the click point into that command's
  order (position for Move; `ship_at_point` on the opposing group for
  Attack; `ship_at_point` on the player's own group, excluding the
  selection, for Protect) and issue it to every selected ship, then clear
  the selection as before. If no command is armed, right-click keeps
  today's clear-only behaviour (so old muscle memory/tests for "right
  click deselects" still hold when nothing is armed).
- `_on_left_release` drops its `_issue_order` branch entirely — a plain
  click on empty space (not a drag, no ship under the cursor) does nothing,
  since ordering now only happens via right-click.

### Protect behaviour

New `Ship._process_protect(delta, candidates)`, parallel to
`_process_hold_position`: holds a standoff distance from
`current_order.target_ship` (reuse `ENGAGE_HULL_GAP`-style spacing, not a
fixed number — tune during implementation) on the side toward the nearest
threat, screening the protectee from it, and autofires at whichever enemy is closest to the
protectee and in range, preferring PD weapons against incoming
missiles/drones when the protectee itself is the thing being shot at (PD
mounts already fire independently via `WeaponMount`'s own targeting, so
this is mostly about choosing to engage the threat nearest the protectee
rather than the nearest threat to self).

If the protectee is destroyed or jumps out, the order doesn't revert to
`hold()`: per the user's call, the ship switches to `ATTACK_TARGET` against
the nearest live enemy (same auto-retarget path as below).

### Auto-retarget on target loss

Today, `_process_order_movement`'s `ATTACK_TARGET` branch calls
`execute_order(Order.hold())` the instant `current_order.target_ship` stops
being a live target — which both drops the order type and re-enables
`hold()`'s whole-field hunting/movement. Per the user's call, change this:
on loss, re-run `CombatTactics.pick_target` over current enemy candidates
and, if one is found, re-issue `Order.attack_target(new_target)` (same
order type, new target) instead of falling back to `hold()`. Only fall back
to `Order.hold_position()` (anchored, not `hold()`) if no live enemy
remains at all — `hold()`'s battlefield-wide hunt is for NPCs, not a
player ship whose explicit order just ran out of target.

## 4. Weapon focus, dodging, pacing

### Weapon focus

`Ship._process_weapons` currently fires every mount whose `can_fire()` is
true at whatever `pick_mount_target` resolves — effectively "fire
everything that bears." Add `Ship.primary_weapons(weapons: Array[Weapon])
-> Array[Weapon]`: among `CombatTactics.range_weapons(weapons)` (non-PD),
keep only the top `PRIMARY_WEAPON_COUNT` (new const, default 2) ranked by
`CombatTactics.weapon_dps`. `_process_weapons` only sends `primary` as a
mount's target when the mount's weapon is in that set (or is point-defense,
which keeps firing independently at its own targets as today — PD is
defense, not the offensive focus this item is about). A mount whose weapon
isn't in the primary set and isn't PD holds fire rather than opportunistically
engaging a secondary target, so the ship visibly commits to its best
weapons instead of lighting up every hardpoint.

### Imperfect dodge

New small lateral jink layered onto `_park_at`'s `station` point (and
`_process_hold_position`'s anchor-facing, where relevant): when an enemy
projectile is within some radius and heading roughly at the ship (dot
product of its `travel_direction * speed` — `Projectile` has no `velocity`
field, just a fixed `travel_direction` set once at launch plus `speed` —
with the vector to the ship past a threshold), offset the station point
sideways by a
capped random distance, decaying over a short window so the ship drifts
back to its proper standoff once clear. "Imperfect" means this is a soft
bias on top of existing station-keeping, not a guaranteed dodge — it should
read as a ship juking, not teleporting or always avoiding damage. Exact
detection radius/cap/decay are tuning constants, not fixed here.

### Pacing

Reduce `max_speed`/`acceleration`/`turn_rate` in `scenes/ship/ship_*.tscn`,
most notably the corvette (today 280 / 220 / 5.0 — clearly the "too fast,
turns too sharp" ship the user called out). Freighter and capital are
already much slower and may need smaller or no adjustment. Exact target
numbers are an implementation/playtest tuning task, not fixed by this spec
— but per the user's own flag, changing these ripples into
`CombatTactics`'s run-break geometry (`RUN_BREAK_LEAD_TIME`,
`RUN_BREAK_FRACTION`, `KITE_MARGIN` are all expressed in the same speed/
distance units) and the existing kite-vs-corvette open item in
`carry_forward.md`. The implementation plan should re-run
`tests/perf_combat.gd` and a run/kite probe (same shape as the existing
ones in `carry_forward.md`'s "Combat AI and orders" section) after
retuning, not just trust the numbers on paper.

No new mechanic is needed for the "fly-by hits" complaint itself
(`CombatTactics.Tactic.RUN` already makes narrow-arc ships break off and
come back around) — the complaint is a symptom of speeds being too high for
the break/reset geometry to read as a deliberate pass rather than a drive-by.
Slowing ships down is expected to fix it; if a playtest afterward still
shows flat fly-bys, that's new information for a follow-up, not something
to pre-solve here.

## Testing

- `FleetCommander.strength_of` / `center_out_anchors`: table-driven, fixed
  compositions and anchor layouts → expected ordering.
- `Ship._ready()` default order is `HOLD_POSITION`; a freshly spawned ship
  with an enemy out of range does not move over several physics frames.
- Order-bar arm/fire: each of the five buttons toggles exclusively; Hold/
  Flee fire immediately on click with a selection; Move/Attack/Protect only
  fire on a subsequent right-click; right-click with nothing armed still
  only clears selection.
- `Order.protect()` / `_process_protect`: a protected ship under simulated
  fire draws its guardian toward the threat side, within the standoff band.
- Auto-retarget: an `ATTACK_TARGET` order whose target is freed mid-battle
  re-targets instead of calling `hold()` (assert the resulting
  `current_order.type` stays `ATTACK_TARGET`, or becomes `HOLD_POSITION`
  only when candidates is empty).
- `Ship.primary_weapons`: table-driven across loadouts with >2 non-PD
  weapons, confirming the top-DPS subset and that PD weapons are excluded
  from (and unaffected by) the cap.
- `tests/perf_combat.gd` re-run after the pacing changes (existing gate,
  `DangerTier.SECURITY_MAX_SHIPS` perf budget) to catch any regression from
  slower ships taking longer to resolve fights.

## Open questions for the implementation plan

- Exact slowed `max_speed`/`acceleration`/`turn_rate` values per hull, and
  the dodge jink's radius/cap/decay constants, are tuning guesses to settle
  during implementation/playtest.
- `PRIMARY_WEAPON_COUNT` default of 2 matches the user's "pick 1-2
  weapons" — whether it's ever 1 (e.g. for single-weapon corvettes it's
  moot) is just the natural `min(2, available)` behaviour of "top N."
- Protect's standoff distance and which weapons count as "protecting" (PD
  only, or any weapon that can hit the threat) are implementation-time
  calls; the design intent is "shoot things attacking the protectee,"
  not a hard rule.
- Whether `Order.hold()`'s whole-field hunt (used when a `MOVE_TO`/
  `RETREAT` order completes with no explicit follow-up) should also be
  replaced by the quieter `HOLD_POSITION` fallback is left to the user to
  confirm once this is in front of them — item 1 only asked about battle
  *start*, not what a ship does after it finishes a Move order.
