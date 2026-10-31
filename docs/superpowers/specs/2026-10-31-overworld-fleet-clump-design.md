# Overworld Fleet Clump — Design

## Problem

In the overworld (campaign map), a fleet is rendered as a single yellow
triangle icon (`CampaignFleetIcon`) regardless of how many ships it
contains. The player can't tell at a glance how many ships are in their
fleet (or an enemy/trader fleet) without entering combat.

## Scope

Count/shape only. The game currently has a single generic ship type —
there is no ship-class field anywhere in `CampaignFleet` or the combat
spawner, and no corvette/capital/freighter visuals exist in code (only in
old planning docs). Introducing real ship classes is a separate, larger
feature and is **out of scope** here — tracked in `carry_forward.md`.

This feature applies to **all fleets** in the overworld (player, trader,
pirate, faction), not just the player's.

## Design

### Visual

`CampaignFleetIcon`'s single static triangle `Polygon2D` is **replaced
entirely** by a loose, randomly-scattered clump of small dots — one dot
per entry in `fleet.ship_compositions`. No formation logic, no sorting by
role — dots get a random offset within a small radius around the icon's
origin, rolled once and cached so they don't jitter.

- `CLUMP_RADIUS := 18.0` — max distance a dot's offset can be from origin.
- `SHIP_DOT_RADIUS := 3.0` — radius of each dot's circle polygon.
- `DOT_COLOR := Color(0.9, 0.9, 0.3, 1)` — same yellow as today's triangle,
  so visibility/contrast is unchanged.

The `Area2D` root and its `CollisionShape2D` (radius 24, used for
click/interaction detection and AI proximity checks) are unchanged —
only the visual children change. Fleet movement, AI behavior
(`PatrolBehavior`/`TraderBehavior`/`PirateBehavior`), and all existing
signals are untouched.

### Data

No changes to `CampaignFleet` (`scripts/campaign/campaign_fleet.gd`).
This is purely a rendering layer reading `fleet.ship_compositions.size()`.
A fleet with 0 ships renders 0 dots, consistent with existing
destroyed-fleet cleanup elsewhere (`CampaignScene._on_skirmish_resolved`
already frees the icon).

### Implementation

`scenes/campaign/campaign_fleet_icon.tscn`:
- Remove the static `Polygon2D` triangle node.
- Keep `Area2D` root + `CollisionShape2D` (unchanged).

`scripts/campaign/campaign_fleet_icon.gd`:
- New state: `_ship_dots: Array[Polygon2D]`, `_ship_dot_offsets: Array[Vector2]`.
- New method `_sync_ship_dots()`:
  - Target count = `fleet.ship_compositions.size()`.
  - If `_ship_dots.size() < target`: for each missing index, roll a new
    random offset (angle `randf_range(0, TAU)`, distance
    `randf_range(0, CLUMP_RADIUS)`), cache it in `_ship_dot_offsets`,
    create a small circle `Polygon2D` at that offset, add as child,
    append to `_ship_dots`.
  - If `_ship_dots.size() > target`: free and remove trailing dots (do
    **not** touch `_ship_dot_offsets` for surviving indices, so remaining
    dots keep their positions).
- Call `_sync_ship_dots()` once from `setup()`.
- Also call it from `_physics_process()` (cheap size comparison) so a
  composition-size change mid-session (no scene reload) reflects
  immediately. In practice, today's only paths that shrink
  `ship_compositions` happen via a full scene reload after combat
  (`change_scene_to_file`), so this is a safety net for correctness, not
  something currently exercised by gameplay — `apply_fractional_damage`
  (auto-resolved skirmishes) scales hp/shield down but does not remove
  array entries.

### Testing

Update `tests/test_campaign_fleet_icon.gd`:
- After `setup()` with N-entry `ship_compositions`, assert the icon has
  N dot children, each within `CLUMP_RADIUS` of the origin.
- Shrink `fleet.ship_compositions` by removing entries, tick
  `_physics_process`, assert dot count drops to match and surviving
  dots' positions are unchanged.

## Out of scope / follow-up

- Ship classes (corvette/capital/freighter) with distinct size/shape per
  class, both in combat and in this clump — needs a ship-class field on
  `CampaignFleet.ship_compositions` entries and corresponding combat
  scene changes. Noted in `carry_forward.md`.
