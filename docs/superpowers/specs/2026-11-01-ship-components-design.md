# Ship Components, Component Damage, and Station Repair

## Goal

Ships currently take damage as two flat pools: `Shield` (absorbs first,
regenerates) then `Hull` (kills the ship at 0). Engines and weapon mounts
are functionally invincible — they never degrade or fail. This spec adds
per-component health to engines and weapon mounts, location-based damage
(components have their own hitboxes distinct from the hull), visual
feedback for all of it, and a flat-fee repair action at stations so
component/hull/shield damage has a persistent cost across the campaign.

## Non-goals

- No new weapon types, no changes to `Weapon` resource balance.
- No real Godot physics collision (`Area2D` monitoring/signals) — hit
  detection stays geometric/manual, matching the existing testable style
  (see `Projectile._hit()`'s distance check).
- No per-component repair pricing — repair cost is a single flat fee
  per damaged ship (see Station Repair below).
- No partial/degraded weapon fire rate — a weapon mount works at full
  effectiveness until destroyed, then stops entirely (binary, not a
  dial, unlike the engine).

## Discovered conflict: existing free auto-repair

`scripts/campaign/home_base.gd`'s `_on_area_entered` already calls
`area.fleet.repair_to_full()` the moment the player's fleet icon enters
the home base — the same trigger that opens `TradePanel`. Left in place,
the player's hull/shield would always already be full by the time the
paid repair UI appears, making the fee pointless. Resolved: **remove**
the `area.fleet.repair_to_full()` call from `HomeBase._on_area_entered`
entirely (the `player_docked` signal emit stays). All repair, at any
station, now goes through the new paid per-ship flow.
`CampaignFleet.repair_to_full()` itself is left in place as a utility
(still covered by its own existing test) — only its one call site goes
away.

## Component base class

Introduce `ShipComponent` (`extends Node`), the common shape that
`Hull`, `Shield`'s HP-bearing behavior, `ShipEngine`, and `WeaponMount`
all need:

```
class_name ShipComponent
extends Node

signal destroyed
signal damaged(amount: float, remaining: float)

@export var max_hp: float = 10.0
var current_hp: float

func _ready() -> void:
    current_hp = max_hp

func apply_damage(amount: float) -> void:
    if current_hp <= 0.0:
        return
    current_hp = max(0.0, current_hp - amount)
    damaged.emit(amount, current_hp)
    if current_hp <= 0.0:
        destroyed.emit()

func is_destroyed() -> bool:
    return current_hp <= 0.0

func health_fraction() -> float:
    return current_hp / max_hp if max_hp > 0.0 else 0.0
```

- `Hull` becomes a thin subclass that adds only `invulnerable` and
  overrides `apply_damage` to respect it. Existing `Hull` call sites
  (`hull.max_hp`, `hull.current_hp`, `hull.apply_damage()`,
  `hull.destroyed`, `hull.is_destroyed()`) are unchanged.
- `ShipEngine` becomes `extends ShipComponent` (and changes base type
  from `Node` to `Node2D`, since it now needs a hitbox position — see
  below). Its existing `max_speed`/`turn_rate`/`acceleration` exports
  and `steer_toward`/`stopping_distance` stay as-is.
- `WeaponMount` becomes `extends ShipComponent` (already `Node2D`, so no
  base-type change). Its existing `weapon`/`cooldown_remaining` exports
  and `can_fire`/`try_fire` stay as-is, but `can_fire()` additionally
  requires `not is_destroyed()`.
- `Shield` is intentionally **not** migrated to `ShipComponent` — it has
  no `destroyed`/hitbox concept (shields regenerate, don't "die" in the
  hull-damage sense) and keeps its current standalone shape, just with
  one addition: a `depleted`/`restored` signal pair for the new visuals
  (see Shield visuals below).

## Hitboxes and hit resolution

Hit detection today is a distance check against the target's center
(`Projectile._physics_process` / `_hit()`), not real physics collision.
Component hitboxes extend that same geometric style rather than
introducing `Area2D` monitoring:

- `ShipComponent` gains `@export var hitbox_radius: float = 0.0`.
  `0.0` means "no distinct hitbox" (not independently targetable) —
  this is `Hull`'s default, since the hull is the catch-all target, not
  a located component.
- `Ship` gains:
  ```
  func resolve_component_hit(impact_pos: Vector2) -> ShipComponent:
      var best: ShipComponent = null
      var best_dist := INF
      for comp in _hitbox_components():  # engine + live weapon_mounts
          if comp.is_destroyed() or comp.hitbox_radius <= 0.0:
              continue
          var d := comp.global_position.distance_to(impact_pos)
          if d <= comp.hitbox_radius and d < best_dist:
              best = comp
              best_dist = d
      return best
  ```
- `Projectile._hit()` passes its own `global_position` as the impact
  point: `target.receive_damage(damage, global_position)`.
- Per-ship-type scene work: today every `WeaponMount` sits at the ship's
  local origin (dead center), which would make its hitbox indistinguishable
  from a hull hit. Each ship scene (`ship_corvette.tscn`,
  `ship_freighter.tscn`, `ship_capital.tscn`, generic `ship.tscn`) needs
  its `WeaponMount` node(s) repositioned to a sensible mount point on the
  sprite (e.g. corvette: nose; capital: turret positions along the hull)
  and the new `Engine` node positioned at the rear, each with a tuned
  `hitbox_radius`.

## Damage routing

`Ship.receive_damage` gains an optional impact position, defaulting to
the ship's own center so all existing call sites (and `tests/test_ship.gd`)
keep working unchanged:

```
func receive_damage(amount: float, impact_position: Vector2 = Vector2.INF) -> void:
    var overflow := shield.absorb(amount)
    if overflow <= 0.0:
        return
    var pos := global_position if impact_position == Vector2.INF else impact_position
    var hit_component := resolve_component_hit(pos)
    if hit_component != null:
        hit_component.apply_damage(overflow)
    else:
        hull.apply_damage(overflow)
```

Shield absorption is unconditional and whole-ship, same as today — only
the overflow's destination changes based on where the shot landed. A
component hit takes the *full* overflow; it never spills into the hull
(confirmed: component hits are exclusive, not an extra defense layer).

## Engine behavior: thrust loss

`ShipEngine.steer_toward`/`stopping_distance` currently use
`acceleration`/`max_speed` directly. Add:

```
func effective_acceleration() -> float:
    return acceleration * health_fraction()

func effective_max_speed() -> float:
    return max_speed * health_fraction()
```

`steer_toward` and `stopping_distance` switch to these. At `current_hp`
0 (`destroyed` fires), `health_fraction()` is 0, so thrust and max speed
both go to 0 — the ship drifts on whatever velocity it already had, no
new acceleration, until the hull is eventually destroyed too (or the
ship is towed/repaired). No change to `turn_rate` — a dead-in-the-water
ship can still rotate in place (maneuvering thrusters assumed separate
from main thrust).

## Weapon mount behavior: silent death

On `WeaponMount.destroyed`: `can_fire()` is already false via the
`ShipComponent` base's `is_destroyed()` check — no further mount-side
change needed. `ShipVfx` (see below) handles the explosion visual. No
hull damage occurs — this is a contained, local explosion per your
answer ("weapons explode on death not doing damage to hull").

## Visual feedback (`ShipVfx`)

`ShipVfx` already listens to `hull.damaged`/`hull.destroyed` for flash/
smoke/explosion. Extend it:

- **Engine destroyed:** small explosion (`ExplosionScene`, scaled down)
  at `engine.global_position`; `_engine_trail.emitting` is forced `false`
  permanently (a `_engine_disabled` flag short-circuits the existing
  speed-threshold check in `_physics_process`).
- **Weapon mount destroyed:** for each mount, connect `destroyed` to a
  handler that spawns a small explosion at that mount's
  `global_position`. (`ShipVfx` iterates `get_parent().weapon_mounts`
  after `Ship._ready()` has populated it — needs the same one-frame-later
  caveat already documented in `tests/test_ship.gd`.)
- **Shield glow:** new `ShieldGlow` visual (a simple translucent
  `Sprite2D`/circle child, no shader) whose `modulate.a` is set each
  physics frame from `shield.health_fraction()` (dimmer as shield
  depletes). On `Shield.depleted`, a quick flicker-tween to `alpha 0`
  ("blinks out"); on `Shield.restored` (new signal, fires when
  `current_shield` rises above 0 from 0 during regen), a flicker back in.

## Persistence across campaign

`ShipType.new_composition`, `combat_scene._apply_fleet_data`, and
`combat_scene._collect_survivor_data` already carry `max_hp`/`current_hp`/
`max_shield`/`current_shield` between combat and the campaign layer.
Extend the composition dict with:

```
"engine_max_hp": ..., "engine_current_hp": ...,
"weapon_mount_max_hp": [...], "weapon_mount_current_hp": [...],
```

(arrays indexed in scene child order, matching how `weapon_mounts` is
already populated by `Ship._ready()`'s discovery loop). `ShipType.BASE_STATS`
gains per-kind `engine_hp` and `weapon_mount_hp` base values (corvette
squishiest, capital tankiest, mirroring the existing `max_hp`/`max_shield`
spread). `_apply_fleet_data`/`_collect_survivor_data` copy these fields
the same way they copy hull/shield fields today.

## Station repair

`CampaignState` gains:

```
const REPAIR_COST := 75.0

static func is_damaged(comp: Dictionary) -> bool:
    if comp["current_hp"] < comp["max_hp"] \
            or comp["current_shield"] < comp["max_shield"] \
            or comp["engine_current_hp"] < comp["engine_max_hp"]:
        return true
    var mount_hp: Array = comp["weapon_mount_current_hp"]
    var mount_max: Array = comp["weapon_mount_max_hp"]
    for i in mount_hp.size():
        if mount_hp[i] < mount_max[i]:
            return true
    return false

static func repair_cost_for(comp: Dictionary) -> float:
    return REPAIR_COST if is_damaged(comp) else 0.0

func repair_ship(comp: Dictionary) -> void:
    comp["current_hp"] = comp["max_hp"]
    comp["current_shield"] = comp["max_shield"]
    comp["engine_current_hp"] = comp["engine_max_hp"]
    comp["weapon_mount_current_hp"] = comp["weapon_mount_max_hp"].duplicate()
    credits -= REPAIR_COST
```

`TradePanel` gains a repair section, visible only when docked at a base
(repair is a station service, same gate as trading):

- One row per ship in `_player_fleet.ship_compositions`: ship label, a
  per-ship cost readout, and a "Repair" button — disabled if the ship
  isn't damaged or `credits < REPAIR_COST`.
- A "Repair All" button below the rows — disabled if
  `sum(repair_cost_for(comp) for comp in compositions) > credits`, or if
  no ship is damaged. Repairs every damaged ship in one call.
- `refresh()` re-renders the repair section the same way it already
  re-renders commodity rows (recompute damaged state + button `disabled`
  state from current `CampaignState.credits` and the fleet's compositions).

## Testing

- `tests/test_hull.gd`-style unit tests for the new `ShipComponent` base
  (apply_damage clamps at 0, emits `damaged`/`destroyed` once, `is_destroyed`).
- Extend `tests/test_ship.gd`'s `_check_ship_logic` with: a component-hit
  case (`receive_damage` with an `impact_position` inside a mount's
  hitbox_radius only damages that mount, hull/shield untouched) and a
  hull-hit case (`impact_position` outside all hitboxes still routes
  overflow to hull, matching current behavior).
- `tests/test_ship_engine.gd`: `effective_acceleration()`/
  `effective_max_speed()` scale linearly with `current_hp`, and read 0
  at `current_hp == 0`.
- New `tests/test_weapon_mount.gd`: `can_fire()` false once destroyed,
  even with cooldown elapsed and a target in range.
- `CampaignState.repair_cost_for`/`is_damaged`/`repair_ship`: unit-tested
  directly against hand-built composition dicts (same style as existing
  `CampaignState` tests), no scene tree needed.
- Visual/VFX behavior (explosion placement, shield glow alpha, engine
  trail cutoff) is manual-playtest-only, consistent with how `ship_vfx.gd`'s
  existing flash/smoke/trail behavior is already marked unverified-by-
  automated-test in `tests/test_ship.gd`'s header comment.
