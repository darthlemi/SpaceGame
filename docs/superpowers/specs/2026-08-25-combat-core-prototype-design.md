# Combat Core Prototype — Design Spec

## Vision

A Starsector-inspired tactical space game built in Godot: real-time ship
combat layered under a persistent campaign map with factions, territory,
and ship customization. The signature hook is a **rift system**: large
battles have a chance to tear open "rifts" — anomalies tied to dormant
precursor tech, awakened by destruction. Rifts are passive and safe unless
approached, and offer a tiered, decaying payoff to players who investigate
them: first a risk/reward hazard (guardians, distorted sensors, valuable
wrecks), then an exploitable resource (a rare currency used for unique
parts/tech/faction favor), and eventually a combat power-up (a chargeable
ability usable in a nearby future battle). Rifts spawn probabilistically,
more likely from larger battles but never guaranteed, and decay in
threat/reward over time if left alone.

This document specs only the **first buildable milestone**: the combat
core. Campaign map, factions, ship customization/refit, and the rift
system itself are explicitly out of scope here and will get their own
specs once combat feels good.

## Goals for This Milestone

Prove that real-time tactical combat feels good in Godot, with:
- A player who can either directly pilot their capital ship or command it
  RTS-style (click to move/target), toggled at will mid-battle.
- A weapons/defense system minimal in content (one or two weapon types,
  simple shield + hull) but architected so new weapon *styles* (beam,
  AoE/pulse, homing rocket) can be added without touching ship or control
  code.
- A single AI-controlled enemy ship as an opponent (1v1 duel).
- Clear win/lose resolution.

## Architecture

Godot 4.x, 2D top-down. Ships are composed from independent components
(Hull, Shield, Engine, WeaponMounts) rather than monolithic scripts, so
future ship variety doesn't require forking ship code.

Weapons are Resources (`.tres` data: damage, fire rate, range, cooldown)
paired with a pluggable firing-behavior script. Adding a new weapon style
means writing one new behavior script and data file — not modifying ships
or existing weapons.

A single `Order` interface (`move_to`, `attack_target`, `hold`, `retreat`)
is issued by three interchangeable sources — player RTS clicks, the
direct-pilot controller, or AI logic — so ships never know or care who is
commanding them. This unification is what lets the 1v1 duel scale to
multi-ship fleets later without rewriting control code, and lets the AI
opponent reuse the exact same execution path as the player.

## Components

- **Ship** (base scene): owns Hull, Shield, Engine, WeaponMounts[];
  exposes `execute_order(order)`.
- **Hull**: current/max HP, emits a `destroyed` signal at 0.
- **Shield**: current/max, regen rate, absorbs damage before hull (flat
  absorption for now — no damage-type multipliers yet; extensible later).
- **Engine**: max speed, turn rate, thrust — used identically whether
  driven by direct input or by pathing toward an Order's target position.
- **WeaponMount**: holds a Weapon resource, handles range/arc checks,
  autofires at the ship's current target when in range.
- **Weapon** (Resource): damage, fire_rate, range, cooldown, and a
  reference to its projectile/behavior scene.
- **RTSCommander** (Controller): translates mouse clicks into Orders
  (move-to, attack-target) on the player ship.
- **DirectPilot** (Controller): raw input → thrust/rotation/fire, bypasses
  Order translation for tight direct control.
- **ControlToggle**: swaps which controller is "live" for the player ship
  at runtime; ship state (position, velocity, current target) persists
  across the swap.
- **AIController**: simple state machine (approach → engage → retreat
  below an HP threshold) issuing the same Orders as the player controllers.

## Data Flow

1. Input (mouse click, or direct key/mouse) reaches the active Controller.
2. Controller produces an `Order`.
3. `Ship.execute_order()` updates movement/target each physics tick.
4. In-range WeaponMounts autofire at the ship's current target.
5. Projectile/beam applies damage to the target's Shield first, overflow
   to Hull.
6. Hull reaching 0 fires a `destroyed` signal.
7. The combat scene detects one side destroyed and shows a win/lose
   result screen stub.

## Error Handling / Edge Cases

- **Target destroyed mid-order**: controller/AI re-evaluates (falls back
  to `hold` or re-targets) rather than holding a stale reference.
- **Control mode switch mid-battle**: velocity/rotation/current target
  carry over untouched; only the source issuing new Orders changes.
- **Firing out of range/arc**: WeaponMount simply withholds fire; not an
  error condition.

## Testing

Combat feel (both control modes, 1v1 duel) is validated primarily through
playtesting — this isn't meaningfully unit-testable. Weapon damage math
and Order-resolution logic (e.g. target-destroyed handling) are pure
logic and worth a small set of GDScript unit tests (via GUT), so future
weapon-type additions don't silently break damage calculation.

## Out of Scope (Future Milestones)

- Campaign/sector map, travel, and encounters
- Factions, reputation, territory control
- Ship customization / refit screen
- Rift spawn, decay, and payoff system
- Multi-ship fleets
- Damage-type multipliers (kinetic/energy/explosive/etc.)
