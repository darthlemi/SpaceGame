# Multi-Ship Combat — Design Spec

## Vision Recap

Follows directly from the combat-core-prototype milestone (see
`2026-08-25-combat-core-prototype-design.md`). That milestone proved a
single Order interface driven by RTS clicks, direct pilot, or AI could
control one ship. This milestone scales it to fleets: the player selects
one or many ships (click or box-drag) and issues them move/attack orders
via right-click, optionally in formation, while every ship (player or AI)
autonomously auto-fires at nearby threats and chases/disengages on its
own between orders.

## Goals for This Milestone

- Select a single ship or a group via click-drag box-select.
- Right-click issues move or attack orders to the whole selection at
  once, in one of five formations (or no formation).
- Ships never pass through each other (reuse existing physics
  collision, no new steering system).
- Any ship — player or AI — auto-fires at nearby enemies when it has no
  more specific order, and will briefly chase-then-disengage a locked
  target while idling.
- N-vs-M fleet sizes, resolved to Victory/Defeat when one whole fleet is
  destroyed.
- Direct-pilot mode is dropped for this milestone (RTS-only control).

## Out of Scope

- Direct piloting (may return in a later milestone).
- Coordinated/focus-fire AI (each AI ship targets independently).
- New weapon types, damage multipliers, campaign map, factions, rifts
  (unchanged from the prior spec's Out of Scope list).
- A dedicated tuning UI/editor — new behavior constants are `@export`
  fields, tunable via the existing Godot Inspector; a custom editor is
  future work this only sets up for.

## Architecture

Ships keep resolving "who's my enemy" the same way they already resolve
"who's commanding me" (Task 1-9's `Order` abstraction): by not knowing in
advance. Each `Ship` gets `@export var enemy_group: StringName`. Both
auto-fire targeting and `AIController` resolve "nearest living enemy" via
`get_tree().get_nodes_in_group(enemy_group)` at decision time instead of
holding a fixed opponent reference. Groups update for free as ships are
freed, so no manual roster bookkeeping is needed anywhere.

`Order` is unchanged (`MOVE_TO`, `ATTACK_TARGET`, `HOLD`, `RETREAT`).
Chase-then-disengage is a reflex `Ship` runs on its own during `HOLD`,
not a new order type — it's not something a commander expresses intent
for, like autofire itself.

## Components

- **`Ship`** (modified): adds `enemy_group: StringName`. `_process_weapons()`:
  if `current_order.type == ATTACK_TARGET`, fire only at that target
  (unchanged). Otherwise, auto-fire at the nearest living `enemy_group`
  member within any mount's range. On `MOVE_TO` arrival (within a small
  radius), auto-transitions to `Order.hold()` and records the arrival
  point as `_hold_center`.
- **`Ship` HOLD sub-state machine** (new, internal — not exposed via
  `Order`):
  - *Loitering* (default): every `loiter_interval` seconds, drift to a
    new random point within `loiter_radius` of `_hold_center`.
  - *Chasing*: a living `enemy_group` member within `aggro_range` gets
    locked; ship closes to weapon range and fires. Re-checked every
    tick.
  - *Disengage*: triggered by target death, target leaving
    `aggro_range`, or the ship's distance from `_hold_center` exceeding
    `leash_distance`. Clears the lock, steers back to `_hold_center`,
    resumes loitering once close.
  - New `@export` fields on `Ship`: `aggro_range` (default =
    `attack_range()`), `leash_distance`, `loiter_radius`,
    `loiter_interval`.
- **`AIController`** (modified): `setup(ship, enemy_group: StringName)`
  replaces the fixed-enemy signature. Each tick resolves the nearest
  living `enemy_group` member for its range/hp-ratio checks. The pure
  `next_state()` function (already unit-tested) is unchanged.
- **`Formation`** (new, pure logic, `scripts/combat/formation.gd`):
  `class_name Formation`, static
  `compute_slots(type: Type, count: int, anchor: Vector2, facing: Vector2, spacing: float, slop: float) -> Array[Vector2]`.
  `enum Type { NONE, LINE, WEDGE, BOX, CIRCLE }`. `NONE` is handled by
  the caller, not by this function (see below).
- **`FleetCommander`** (new, replaces `RTSCommander` + `DirectPilot` +
  `ControlToggle` for this milestone — those assumed exactly one player
  ship and direct piloting, both dropped here):
  `@export var formation_spacing: float`, `@export var formation_slop: float`.
  `selected_ships: Array[Ship]`, `active_formation: Formation.Type`.
- **`CombatScene`** (modified): spawns configurable player/enemy fleets
  from arrays of spawn points (not two fixed nodes), tags each ship into
  `"player_fleet"`/`"enemy_fleet"` groups, sets `enemy_group` on every
  ship accordingly, gives every enemy ship its own `AIController`, and
  resolves Victory/Defeat by whole-group destruction.

## Data Flow

1. **Selection:** mouse-down starts tracking; mouse-up with near-zero
   drag = single-click select (replaces selection); mouse-up past a
   drag threshold = box-select everything with a center inside the
   rectangle (replaces selection). Selected ships get a visual
   indicator (ring overlay).
2. **Formation choice:** keys `1`-`5` set `active_formation` for the
   *next* order (`1=NONE, 2=LINE, 3=WEDGE, 4=BOX, 5=CIRCLE`).
3. **Right-click on a living enemy ship:** every selected ship gets
   `Order.attack_target(enemy)` individually — no formation math
   involved, each ship navigates independently as it already does.
4. **Right-click on empty space:**
   - `NONE`: each ship's destination = click point + (that ship's
     position minus the selection's centroid at click time). Preserves
     relative shape without a rigid slot grid.
   - `LINE/WEDGE/BOX/CIRCLE`: `Formation.compute_slots(...)` returns
     slot offsets from the click point, facing from centroid toward the
     click point, jittered per-slot by `formation_slop`. Ships are
     greedily assigned to the nearest unfilled slot (minimizes crossed
     paths). Each ship gets an individual `Order.move_to(slot_position)`.
5. Ships steer toward their individual `Order` targets exactly as in
   the 1v1 milestone. Physical spacing comes from existing
   `CharacterBody2D` + `CircleShape2D` collision via `move_and_slide()`
   — formation slots are a target, not a hard constraint, and no new
   avoidance/steering system is introduced.
6. Any ship without an `ATTACK_TARGET` order auto-fires at the nearest
   in-range `enemy_group` member; a `HOLD`ing ship may temporarily chase
   one within its leash before disengaging back to loitering.
7. `CombatScene` watches `hull.destroyed` across both groups; the first
   group to empty ends the battle (Victory/Defeat).

## Error Handling / Edge Cases

- Right-click with nothing selected: no-op.
- A selected ship is destroyed before its order lands: irrelevant, it's
  simply gone; slot assignment only ever runs against `selected_ships`
  at click time.
- Chase target destroyed or already out of range: existing
  target-validity checks (already present in `Ship`/`AIController` from
  the 1v1 milestone) cover disengage the same tick.
- Two ships targeting the same nearest enemy (both player and AI side):
  allowed and expected, not coordinated — matches the 1v1 milestone's
  "not an error condition" stance on range/arc misses.

## Testing

Pure logic gets headless GDScript unit tests, extending
`tests/run_tests.gd`:
- `Formation.compute_slots` — slot counts, spacing, and facing for each
  type (deterministic; slop can be tested at `0` for exact expected
  positions).
- Auto-fire target selection rule (explicit `ATTACK_TARGET` takes
  priority over nearest-in-range).
- `AIController.next_state` — unchanged, already covered.

Selection/box-drag input, formation visuals, chase/disengage feel, and
overall fleet-battle feel remain playtest-verified in the editor, same
testing philosophy as the combat-core-prototype spec.
