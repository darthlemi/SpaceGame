# Ship Refit/Customization — Design Spec

Milestone 5 from `docs/superpowers/specs/2026-10-29-full-game-roadmap-design.md`:
"Hull slots, swappable weapons/parts, buying and selling." This spec covers
weapon/shield/engine swapping and a loadout-points budget. Visual hull skins
and faction-specific hull art/hardpoints are explicitly separate, queued
features (see Out of Scope).

## Goals

- Player can buy Weapon/Shield/Engine parts with credits at any base.
- Parts go into a spare-parts inventory, then get equipped onto a specific
  ship in the player's fleet via a separate Equip screen.
- A per-ship-class loadout-points budget prevents simply stacking the best
  gear on every slot — equipping is a trade-off, not a pure upgrade.
- Equipped parts persist across campaign sessions and actually show up in
  combat (today's `ship_compositions` data doesn't carry weapon choice into
  battle at all — this spec closes that gap).

## Non-goals

- Hull is never swappable. `ShipType.BASE_STATS[kind]["max_hp"]` remains the
  fixed, permanent hull HP for a ship class.
- No faction-specific hull art or hardpoint layouts (queued as its own
  future milestone, not part of this spec).
- No loot-to-parts pipeline. `LootPanel` still only moves bulk commodities;
  defeated fleets don't drop individual parts yet.
- No equip-anywhere: parts can only be bought/sold/equipped while docked at
  a base, same as existing trading.

## Data model

### Shared rarity/pricing

New `scripts/ship/part_rarity.gd` (`class_name PartRarity`, `extends RefCounted`,
static-only):

```gdscript
enum Tier { COMMON, UNCOMMON, RARE, EPIC }
const PRICE_BY_TIER := {COMMON: 100.0, UNCOMMON: 250.0, RARE: 600.0, EPIC: 1500.0}
const POINTS_BY_TIER := {COMMON: 5, UNCOMMON: 10, RARE: 15, EPIC: 20}
const SELL_FRACTION := 0.5
static func price_for(tier: Tier) -> float: ...
static func sell_price_for(tier: Tier) -> float: ...
static func points_for(tier: Tier) -> int: ...
```

These numbers are starting-balance guesses, not locked — expect tuning
during implementation/playtesting.

`Weapon.gd`'s existing local `enum Rarity` is migrated to reference
`PartRarity.Tier` instead of declaring its own copy. Same underlying ints in
the same order (`COMMON=0`..`EPIC=3`), so existing `.tres` weapon resources
keep their rarity values unchanged.

### New swappable-part resource classes

Mirrors `Weapon.gd`'s shape as a `Resource`:

- `scripts/ship/shield_generator.gd` (`class_name ShieldGenerator`) —
  `item_name: String`, `max_shield: float`, `regen_rate: float`,
  `rarity: PartRarity.Tier`.
- `scripts/ship/engine_core.gd` (`class_name EngineCore`) — `item_name: String`,
  `max_speed: float`, `turn_rate: float`, `acceleration: float`,
  `rarity: PartRarity.Tier`.

Weapons reuse the existing `Weapon` resource and `.tres` pool under
`resources/weapons/` — no new weapon class needed. New `.tres` resources are
added under `resources/shields/` and `resources/engines/` for the shield
generator and engine core items (a handful of each, split by faction theme —
see Catalogs below).

### Fleet/ship persistence additions

- `CampaignFleet` (`scripts/campaign/campaign_fleet.gd`) gains
  `@export var part_inventory: Array[String] = []` — resource paths of
  owned-but-unequipped parts. Each entry counts as 1 unit toward
  `cargo_total()` (same pool as commodities — parts share cargo capacity).
- Each `ship_compositions` dict gains three new optional keys, parallel to
  the existing hp-tracking keys:
  - `weapon_mount_items: Array[String]` — one resource path per
    `WeaponMount`, `""` meaning "no override, use whatever the scene/
    `randomize_loadout` assigns".
  - `shield_item: String` — `""` meaning "use `ShipType.BASE_STATS` default".
  - `engine_item: String` — same convention.
- `ShipType.new_composition()` initializes all three to empty/`""`.

## Loadout points budget

New `ShipType.LOADOUT_POINTS` const, one entry per `Kind`:

```gdscript
const LOADOUT_POINTS := {CORVETTE: 20, FREIGHTER: 15, CAPITAL: 40}
```

A ship's **total points in use** = sum of `PartRarity.points_for(rarity)`
across every currently-equipped weapon (one per mount), its shield, and its
engine — a single pooled budget per ship, not split per slot-type. Equipping
an item from inventory is blocked if doing so would push the ship's total
over its class budget. Nothing auto-unequips retroactively; the budget only
gates new equip actions. This is a player-facing UI constraint only — NPC/
enemy ships' existing `randomize_loadout` free-assignment is untouched.

## Catalogs (per-faction shops)

Every base's shop (Dominion, Freehold, HomeBase) is browsable regardless of
which base the player is docked at. Each catalog is a fixed
`Array[String]` of resource paths, structured like today's
`ShipType.WEAPON_POOL`:

- **Dominion** — heavier/industrial theme: kinetic + beam weapons from the
  existing pool, new high-`max_shield`/`regen_rate` shield generators,
  tankier engine cores.
- **Freehold** — scrappier/utility theme: missile + PD weapons, new
  high-`max_speed`/`turn_rate` engine cores, lighter shield generators.
- **HomeBase** — small generic starter mix of both, skewed toward
  `PartRarity.Tier.COMMON`.

## UI: RefitPanel

New scene, `scenes/campaign/refit_panel.tscn` + `scripts/campaign/refit_panel.gd`,
opened alongside the existing trade panel when docked at any base. Mirrors
`TradePanel`'s row-based layout (one `HBoxContainer` row per item, `refresh()`
rebuilds rows, buttons disable based on current state).

**Shop tab:** lists the docked base's catalog. Buy row disabled if
`credits < price` or `fleet.cargo_total() + 1 > fleet.cargo_capacity()`.
Also lists the player's current `part_inventory` with a Sell button
(`credits += PartRarity.sell_price_for(rarity)`, removed from inventory,
returned to that base's stock conceptually — but since parts aren't
stock-tracked per base like commodities, selling just removes it from
inventory and adds credits, no base-side stock bookkeeping needed).

**Equip tab:** a dropdown/list to pick one ship in the player's fleet, then
shows its slots (each weapon mount, shield, engine) with the currently
equipped item and a "points used / budget" readout. Each slot has an
"Equip from inventory" picker filtered to compatible `part_inventory` items
(weapon pool items for mounts, `ShieldGenerator` items for shield, etc.)
that don't exceed the remaining budget. Equipping swaps the old item back
into `part_inventory` (even if it's a default/no-item slot — nothing to
swap back in that case) and updates the ship's composition dict.

The Equip tab is disabled with a prompt to repair first if
`CampaignState.is_damaged(comp)` is true for the selected ship — refit
requires a fully-repaired ship, closing off any ambiguity around
partial-health scaling on swap.

## Combat integration

`combat_scene.gd` currently copies hp/shield/engine-hp/mount-hp numbers from
`ship_compositions` onto spawned `Ship` nodes but never touches *which*
weapon is mounted, nor shield regen/engine performance stats — those come
only from the scene file or `randomize_loadout`. Two functions need
extending:

- `_apply_fleet_data`: after the existing copies, for each weapon mount
  with a non-empty `weapon_mount_items[j]`, `load()` it and assign to
  `weapon_mounts[j].weapon`. If `shield_item`/`engine_item` are non-empty,
  load and apply `max_shield`/`regen_rate` onto `shield`, and
  `max_speed`/`turn_rate`/`acceleration` onto `engine`.
- `_collect_survivor_data`: read back each mount's `weapon.resource_path`
  (empty string if no weapon), and the equipped shield/engine item's
  resource path if one was set, writing them into the returned dict's new
  keys so equipped loadouts survive into the next session unchanged.

## Testing

- Unit tests for `PartRarity` price/points lookups.
- `ShieldGenerator`/`EngineCore` resource loading and field correctness.
- Budget-check as a pure function (`ShipType` or a small static helper) —
  table-driven tests across all three ship classes and tier combinations.
- `RefitPanel` button enable/disable conditions (insufficient credits, full
  cargo, over-budget equip, damaged-ship blocks Equip tab).
- `combat_scene.gd` integration test: a composition with a specific
  equipped weapon/shield/engine item, spawned into combat, has that exact
  item reflected on the live `Ship` node — and the reverse round-trip
  (`_collect_survivor_data` after combat preserves the same equipped paths).

## Open questions for the implementation plan

- Exact `LOADOUT_POINTS` values per class and `PRICE_BY_TIER`/`POINTS_BY_TIER`
  numbers are starting guesses — tune during implementation/playtesting,
  not blocking the plan.
- Exact catalog contents (which of the 14 existing weapons go to which
  faction, how many new shield/engine `.tres` resources per faction) are an
  implementation-time content task, not a design blocker.
