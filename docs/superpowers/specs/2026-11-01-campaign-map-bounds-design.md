# Campaign Map Bounds — Design Spec

## Purpose

The long-run simulation harness (`tests/test_campaign_long_run_sim.gd`,
previous spec) confirmed what playtesting suspected: nothing stops a
fleet icon from wandering, fleeing, or chasing indefinitely far from
where it started. There is no map-size constant anywhere in the
codebase. This spec adds one, and clamps fleet movement to it.

There is no `Camera2D` anywhere in the campaign scene and no window-size
override in `project.godot` — the overworld view is a fixed, non-scrolling
1152x648 viewport. This spec deliberately does **not** add a camera or
scrolling. The map bounds introduced here (4000x2400) are larger than
that visible viewport, so until a future camera/scrolling spec lands,
fleets (including the player, via mouse-click targeting) can move into
space that is logically in-bounds but not actually visible on screen.
That is an acknowledged, accepted rough edge for this spec, not a bug to
work around here.

## Out of scope

- Camera / scrolling — separate future spec.
- Picking a *visually* correct map size that matches a camera's eventual
  view — 4000x2400 is a logical simulation bound, not a viewport size.
- Any change to *why* fleets move where they do (patrol wander radius,
  trader flee distance, pirate intercept logic) — this spec only adds a
  ceiling on top of existing target-picking logic, it doesn't change what
  targets get picked in-bounds.

## The bound

Two new constants in `scripts/campaign/campaign_fleet_icon.gd`, alongside
the other top-of-file constants (after `const CLUMP_RADIUS := 18.0` and
friends, `campaign_fleet_icon.gd:10-25`):

```gdscript
const MAP_MIN := Vector2(0, 0)
const MAP_MAX := Vector2(4000, 2400)
```

`HOME_BASE_POSITION` (`campaign_scene.gd:8`, `Vector2(600, 400)`) and every
current bootstrap spawn point sit well inside this rectangle with room for
existing wander/flee radii (up to 300px) on top — no existing test fixture
or bootstrap position needs to change.

## The clamp

One clamp, one call site: `campaign_fleet_icon.gd`'s `_physics_process`
(`:74-98`) runs a `match behavior_type:` block (`:80-88`) that is the only
place `_move_target` gets set for `PATROL`/`TRADER`/`PIRATE` (`PLAYER`'s
target is set externally, by `campaign_scene.gd:275`'s
`player_icon.set_move_target(get_global_mouse_position())` on click).
Immediately after that `match` block and before the existing
`move_toward` call (`:89-90`), add:

```gdscript
_move_target = _move_target.clamp(MAP_MIN, MAP_MAX)
```

This is a single choke point, not three (one per behavior): every
behavior type's freshly-computed target gets clamped the same way, and so
does the player's mouse-click target, satisfying "apply uniformly"
without duplicating the clamp call inside `_process_trader()` and
`_process_pirate()` separately. `Vector2.clamp(min, max)` is a built-in
Godot 4 method — no helper function needed.

**Effect on movement feel:** a fleet aiming at a clamped (in-bounds)
target just arrives there and stops, the same as arriving at any other
target today (`move_toward` naturally stops once `global_position`
reaches `_move_target`) — no jitter, no bounce, no separate "hit the
wall" state.

## Testing

- `tests/test_campaign_fleet_icon.gd`: new case — construct a fleet icon,
  drive it into a scenario whose natural (unclamped) target would fall
  outside `[MAP_MIN, MAP_MAX]` (e.g. a trader fleeing a player positioned
  such that `TraderBehavior.flee_target` lands past `MAP_MAX.x`, or a
  patrol wandering near a spawn point placed near the edge with
  `wander_radius` pushing past it), tick `_physics_process`, and assert
  the resulting `_move_target` (and/or `global_position` after enough
  ticks) stays within `[MAP_MIN, MAP_MAX]`.
- `tests/test_campaign_long_run_sim.gd`: per that spec's own stated
  intent ("once the map-bounds fix lands with a real `MAP_*` constant,
  this becomes a real assertion"), the existing report-only
  distance-from-spawn tracking is joined by a real hard assertion: at
  every sampled step, every icon's `global_position.x`/`.y` must fall
  within `[CampaignFleetIcon.MAP_MIN, CampaignFleetIcon.MAP_MAX]`. A
  violation appends a failure naming the icon, the step, and the
  out-of-bounds position. This assertion is expected to **pass**
  immediately once the clamp lands (unlike the pirate-engagement
  assertion in that same file, which stays red until a separate future
  fix) — if it doesn't pass, that's a real bug in the clamp, not a
  documented gap.
- No existing test needs its fixtures changed — `MAP_MIN`/`MAP_MAX` are
  far outside the range any current test or bootstrap scenario operates
  in, by construction (see "The bound" above).
