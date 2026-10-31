# Ship Types — Design Spec

## Purpose

Today every ship in the game — player, pirate, patrol, Dominion, Freehold,
trader — is the exact same hull with the exact same stats (`ship.tscn`,
100 HP / 50 shield / 1 weapon mount, hardcoded in half a dozen places).
This spec introduces three distinct ship types — **Corvette**, **Freighter**,
**Capital** — so combat has real variety: fast, fragile raiders; slow,
unarmed haulers; and heavy, slow-turning gunships. The goal is emergent
counter-play (speed beats raw tonnage, raw tonnage beats everything that
stays in range, cargo haulers are easy but low-value kills), not a new
rock-paper-scissors system bolted on top.

This is scoped independently of Milestone 5 (ship refit/customization).
Refit is about swapping parts within a hull's slots later; this spec is
about having more than one hull to begin with.

## Out of scope

- Drone carriers or other exotic ship types with sub-unit spawning —
  meaningfully more complex (new entity type, spawning, AI); deferred to
  its own future brainstorm once this base system exists.
- Buying/selling ships, hull-slot refit — Milestone 5, untouched.
- New weapon types or an explicit type-counters-type matrix — the three
  types use the existing single weapon resource (`kinetic_cannon.tres`);
  countering is emergent from speed/turn-rate/HP/shield/mount-count
  differences already supported by the engine.

## Ship Types

A new pure static-data class, `scripts/ship/ship_type.gd`, following the
same pattern as `EconomyRole` / `FleetAllocationPolicy`:

```gdscript
class_name ShipType
enum Kind { CORVETTE, FREIGHTER, CAPITAL }
```

| Type | max_hp | max_shield | cargo_capacity | speed profile | weapon mounts |
|---|---|---|---|---|---|
| Corvette | 60 | 20 | 20 | fast, quick turn | 1 |
| Freighter | 80 | 20 | 60 | slow | 0 (unarmed) |
| Capital | 220 | 80 | 20 | slow, poor turning | 3 |

Responsibilities:

- `SCENES: Dictionary[Kind, String]` — scene path per kind.
- `BASE_STATS: Dictionary[Kind, Dictionary]` — `max_hp`, `max_shield`,
  `cargo_capacity` per kind (the table above).
- `static func scene_for(kind: Kind) -> PackedScene`
- `static func kind_of(comp: Dictionary) -> Kind` — returns
  `comp.get("ship_type", Kind.CORVETTE)`. **Missing key defaults to
  Corvette.** This is deliberate: dozens of existing tests build raw
  `{"max_hp": ..., "max_shield": ...}` composition dicts with no
  `ship_type` key, and Corvette's `cargo_capacity` (20) matches today's
  flat `CARGO_CAPACITY_PER_SHIP`, so none of those existing tests need to
  change.
- `static func cargo_capacity_for(kind: Kind) -> float`
- `static func new_composition(kind: Kind) -> Dictionary` — builds a
  fresh `{"ship_type": kind, "max_hp": ..., "current_hp": ..., "max_shield":
  ..., "current_shield": ...}` at full health, used when a fleet grows a
  new ship.

Why no weighting change to combat strength: `CampaignFleet.total_strength()`
stays `current_hp + current_shield` — unchanged. Type differences already
flow through here because each type's baked-in hp/shield differ (Capital
contributes far more strength per ship than Freighter already, with no new
formula needed).

## Scenes

Three Godot **inherited scenes** off the existing `scenes/ship/ship.tscn`
(diff-only, not full duplicates):

- `scenes/ship/ship_corvette.tscn`
- `scenes/ship/ship_freighter.tscn`
- `scenes/ship/ship_capital.tscn`

Each overrides: `Hull.max_hp`, `Shield.max_shield`, `ShipEngine`
(max_speed/turn_rate/acceleration), the set of `WeaponMount` children
(Freighter has zero — `Ship._process_weapons()` and `attack_range()`
already no-op cleanly on an empty `weapon_mounts` array, so this needs no
code change), a distinct `Polygon2D` shape/color so types are visually
distinguishable at a glance, and the new `ship_type` export (below).

`scripts/ship/ship.gd` gains one field:

```gdscript
@export var ship_type: ShipType.Kind = ShipType.Kind.CORVETTE
```

Each inherited scene overrides this export to its own kind — the scene
itself is the source of truth for "what type am I" at runtime, the same
way it's already the source of truth for hp/shield/speed.

## Data model changes

- `CampaignFleet.ship_compositions` dicts gain an optional `"ship_type"`
  key (an int value of `ShipType.Kind`).
- `CampaignFleet.cargo_capacity()` changes from
  `ship_compositions.size() * CARGO_CAPACITY_PER_SHIP` to summing
  `ShipType.cargo_capacity_for(ShipType.kind_of(comp))` per composition.
  `CARGO_CAPACITY_PER_SHIP` is deleted (dead once nothing reads it).
- `CampaignFleet.total_strength()`, `repair_to_full()`,
  `apply_fractional_damage()`, `is_destroyed()` — unchanged.

## Combat scene changes (`scripts/combat/combat_scene.gd`)

- `_spawn_fleet_from_data()` picks the scene per composition via
  `ShipType.scene_for(ShipType.kind_of(comp))` instead of one hardcoded
  `ShipScene` constant.
- `_apply_fleet_data()` — unchanged (still just copies hp/shield numbers
  onto the already-correct-type node).
- `_collect_survivor_data()` additionally reads the spawned ship's own
  `ship_type` export and writes it into the returned dict, so type
  survives the combat → `CampaignState.resolve_engagement` →
  `CampaignFleet.ship_compositions` round trip.
- `_spawn_fleet()` (the no-`CampaignState.active_enemy_fleet` fallback
  used by direct-run/debug paths) and `_spawn_extra_ship()` (debug
  `AddFriend`/`AddEnemy`) keep spawning Corvettes — there's no
  composition data in those paths to drive type selection, and that
  matches today's behavior.

## Fleet composition changes (`scripts/campaign/campaign_scene.gd`,
`scripts/campaign/campaign_state.gd`)

- **Player's starting fleet** (`_bootstrap_default_campaign`): one of
  each type — Corvette, Capital, Freighter — so all three are visible
  from the first session. (Matches the existing 3 player spawn points.)
- **Bootstrap NPC fleets**: pirate and patrol combat fleets → Corvette;
  Freehold's combat fleet → Corvette; Dominion's combat fleet → Capital
  (so a Capital is on the map immediately without waiting on fleet
  growth); the neutral trader fleet and both factions' TRADER-role
  fleets → Freighter.
- **`FleetAllocationPolicy`-driven growth**
  (`CampaignState._grow_fleet`/`_new_ship_template`): growing a COMBAT
  fleet adds a Corvette (`ShipType.new_composition(Kind.CORVETTE)`);
  growing a TRADER fleet adds a Freighter
  (`ShipType.new_composition(Kind.FREIGHTER)`). Capitals are never
  auto-grown — they stay a hand-placed flavor unit for now, not something
  the allocator can spam. The allocator's own decision logic
  (`FleetAllocationPolicy.decide`) is untouched; only the template dict
  `_new_ship_template` builds changes, and it now takes the target role
  as a parameter to pick the right kind.

## Testing

- New `tests/test_ship_type.gd` for `ShipType`'s static helpers
  (`kind_of` default-to-Corvette behavior, `cargo_capacity_for`,
  `new_composition` shape).
- `tests/test_campaign_fleet.gd` gets new cases for `cargo_capacity()`
  with mixed-type compositions (a Freighter contributing 60 vs a Corvette
  contributing 20), while all its existing untyped-dict cases keep
  passing unmodified.
- `tests/test_combat_scene.gd` gets a case asserting a Freighter-typed
  composition spawns the Freighter scene and comes back with
  `ship_type` intact in survivor data.
- No existing test file needs its fixture dicts rewritten — the
  default-to-Corvette fallback is what makes that true, and is worth
  re-verifying explicitly during implementation (run the full suite
  unchanged before adding any new cases, confirm zero regressions).

## Open balance questions (deliberately deferred to playtesting, not this spec)

Exact numeric tuning (is 3 weapon mounts too strong for a Capital, is a
Freighter's 60 cargo vs 20 HP the right trade) is expected to shift once
this is actually played. The table above is a reasonable starting point,
not a locked balance target.
