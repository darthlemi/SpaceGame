# Weapon Loadout Randomization Design

## Goal

18 weapon variants exist (`resources/weapons/*.tres`, from the 2026-11-01
weapon-types and drone-weapons specs) but every combat-capable ship scene
still hardcodes a single `WeaponMount.weapon = kinetic_cannon.tres` on
every mount. This closes that gap: ships spawn with a varied, randomized
loadout drawn from the existing weapon pool, with no shop/inventory system
and no faction-specific pools (neither exists, neither is needed here).

## Scope

- **In scope**: `ship_corvette.tscn` (1 mount), `ship_capital.tscn` (3
  mounts).
- **Out of scope, untouched**:
  - `ship_freighter.tscn` — 0 weapon mounts, nothing to assign.
  - `scenes/ship/ship.tscn` — the generic scene many unit tests instantiate
    expecting a fixed, known weapon (`kinetic_cannon.tres`). Left exactly
    as-is so no existing test needs updating for weapon identity.
  - Rarity-weighted picks, any shop/purchase/loot system, per-faction
    weapon pools — all explicitly deferred by the 2026-11-01 weapon-types
    spec's "Out of scope" section and still don't exist.

## Mechanism

**`ShipType.WEAPON_POOL`** (new `const Array[String]` in
`scripts/ship/ship_type.gd`): resource paths to the 14 ship-mountable
weapons — all Kinetic/Missile/Beam/PD variants. The 3 drone-specific
weapons (`drone_attack_gun.tres`, `drone_bomber_payload.tres`,
`drone_interceptor_gun.tres`) are excluded — they're wired directly into
drone scenes already and aren't meant for a corvette/capital mount.

**`Ship.randomize_loadout`** (new `@export var randomize_loadout: bool =
false`): default false everywhere, so every scene not explicitly opted in
(`ship.tscn`, `ship_freighter.tscn`, drone scenes) keeps its current fixed
or absent weapon. Only `ship_corvette.tscn` and `ship_capital.tscn` set
this `true`.

**Assignment, in `Ship._ready()`**: if `randomize_loadout`, shuffle a copy
of `ShipType.WEAPON_POOL` and assign one distinct path per
`WeaponMount` in `weapon_mounts`, in order (`load()` each path, set
`mount.weapon`). Picking without replacement means a single ship instance
never repeats a weapon across its own mounts — irrelevant for the
corvette's 1 mount, meaningful for the capital's 3 (satisfies "3 different
weapons" per mount). This runs identically regardless of who owns the
ship — player, Dominion, Freehold, pirate — since it's driven by the scene
itself, not spawner/faction code. Two corvettes on screen at once can
carry different guns; the same corvette re-spawning rolls fresh each time.

No mount-size/compatibility restriction exists in the weapon data model
(confirmed in the 2026-11-01 spec's own Out-of-scope section), so every
pool entry is valid for every mount — no filtering logic needed beyond
excluding the 3 drone-only weapons.

## Testing

`tests/test_ship_type_scenes.gd` already only asserts mount *count* and
hitbox radii, not weapon identity — needs no changes.

New test (new file or appended to an existing ship-scene test):
1. After instantiating `ship_corvette.tscn` and calling `_ready()`
   (already happens on `add_child`/instantiation per existing test
   patterns), its single mount's `weapon` is non-null.
2. Instantiating `ship_capital.tscn` gives all 3 mounts non-null,
   pairwise-distinct `weapon` resources.
3. Instantiating `scenes/ship/ship.tscn` still yields
   `kinetic_cannon.tres` on its mount, unchanged — regression guard for
   the many tests assuming that.
4. Run the pool pick a handful of times (e.g. 10 fresh corvette instances)
   and assert at least two different weapons appear across the runs — a
   loose statistical check that randomization is actually happening, not
   just structurally wired but always picking index 0.

## Out of scope (explicitly, carried forward)

Same three items the 2026-11-01 carry-forward note already flagged as not
needed for this change: rarity-driven spawn/loot tables, a shop/purchase
system, and PD/Interceptor's deferred missile-vs-drone targeting bonus
(unrelated to loadouts, a separate targeting-infrastructure feature).
