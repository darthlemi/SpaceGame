# Drone Weapon Type Design

## Goal

Implement the Drone weapon type from `docs/superpowers/specs/2026-11-01-weapon-types-design.md`
(Attack, Interceptor, Bomber, EW variants) by reusing the existing
`Ship`/`AIController`/`Order`/`ShipComponent` architecture as much as possible,
rather than building a separate entity type from scratch.

## DroneBay

A new `ShipComponent` subclass, mounted on a ship like a `WeaponMount`:

- `@export var max_drones: int = 3`
- `@export var launch_interval: float = 0.3` — gap between successive launches
  when refilling multiple empty slots.
- `@export var respawn_delay: float = 15.0` — cooldown on a slot after its
  drone dies, before that slot can launch again.
- `@export var drone_scene: PackedScene` — the drone variant this bay launches.

Behavior: tracks one cooldown timer per slot (`max_drones` of them). A slot
with cooldown `<= 0.0` and no live drone currently occupying it launches a new
drone (spawned near the bay's ship, added directly to the combat scene — not
as a child of the ship — and given `Order.attack_target()` toward the ship's
current engagement target) and resets its cooldown to `launch_interval`. When
a drone's `hull.destroyed` fires, its slot's cooldown resets to
`respawn_delay` instead. Drones launched "battle ready": no separate spin-up
state, immediately capable of combat via the normal `AIController` loop.

Drones are independent entities once launched — they are not freed when the
launching ship dies, and keep fighting until destroyed. No lifetime timer or
ammo limit (consistent with the no-ammo-system decision in the base weapon
spec).

## Ship.player_targetable

New `@export var player_targetable: bool = true` on `Ship`. Drone scenes set
this `false`. `FleetCommander.ship_at_point()` (the right-click target
picker) filters on this flag; `enemy_group` membership, autofire targeting,
and `AIController` targeting are unaffected — drones remain fully shootable
and AI-targetable, just not player-click-selectable as an explicit order
target.

## Attack Drone / Interceptor Drone

No new scripts. Each is a small `Ship` scene: tiny `Hull`, no `Shield`
functionality needed (or `max_shield = 0.0`), one `ShipEngine`, one
`WeaponMount` + small `Weapon` resource, `player_targetable = false`. Reuses
the existing `AIController`/`Order` movement-and-combat loop unmodified.

Deferred (consistent with the PD anti-missile bonus already deferred in the
base weapon spec): Interceptor's "×3 vs missiles/drones" bonus is not
implemented — no missile-entity-vs-drone distinction exists yet in the
targeting system. Interceptor is differentiated purely by its base stats
(low HP, low damage, high fire rate).

## Bomber Drone

New `scripts/drones/bomber_drone.gd`, `class_name BomberDrone extends Ship`:

- `@export var detonate_radius: float = 15.0`
- `@export var payload_weapon: Weapon` — damage/shield_mult/hull_mult for the
  detonation hit.
- Overrides `attack_range()` to return `detonate_radius`, so the existing
  `AIController`/`Order.attack_target` movement naturally brings it to
  contact distance and holds there (same code path as a normal ship closing
  to weapon range).
- Overrides `_process_weapons()`: if `current_order.type == ATTACK_TARGET`
  and in range of `current_order.target_ship`, call
  `current_order.target_ship.receive_weapon_damage(payload_weapon)`, then
  self-destruct via `hull.apply_damage(hull.max_hp)` (reuses the existing
  `destroyed` signal → `queue_free()` cleanup path). No projectile spawned.

## EW Drone

New `scripts/drones/ew_drone.gd`, `class_name EwDrone extends Ship`:

- No `WeaponMount`.
- `@export var aura_range: float = 150.0`
- `@export var regen_debuff_mult: float = 0.5`
- Overrides `_process_weapons()` (the hook `Ship._physics_process` already
  calls): find the nearest enemy in `aura_range` (reuse
  `Ship.nearest_in_range`); if found, set
  `target.shield.regen_multiplier = regen_debuff_mult` for that frame.

`Shield` gains `var regen_multiplier: float = 1.0`. `_physics_process`
applies `regen_rate * regen_multiplier` for that frame's regen, then resets
`regen_multiplier = 1.0` at the end of the frame — the debuff must be
continuously reasserted every frame to stay active, so it ends automatically
when the EW drone moves out of range or is destroyed, with no explicit
cleanup/un-debuff code needed.

## Out of scope

- Missile/drone-specific targeting bonuses (Interceptor's ×3, PD's intercept
  bonus from the base spec) — no missile/drone entity distinction exists yet.
- Drone lifetime limits or ammo.
- DroneBay UI/visual feedback for active drone count or cooldowns.
