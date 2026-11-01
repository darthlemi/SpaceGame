# VFX: Engine Trails + Weapon Fire — Design

## Problem

Ships currently have hit-flash, hit-spark, low-hp smoke, and a death
explosion (`scripts/ship/ship_vfx.gd`), but no feedback for just *moving*
or *firing*. Weapon fire is a flat yellow `ColorRect` square
(`scenes/weapons/projectile.tscn`) with no muzzle flash and no travel
streak. This covers both: a movement trail on every ship (combat and
overworld) and restyled weapon-fire VFX (muzzle flash + projectile look).

## Scope

VFX only — no gameplay/stat changes. Applies uniformly across ship
classes (corvette/freighter/capital) and across all factions, same as
existing `HitSpark`/`SmokeTrail`/explosion VFX (one shared config, no
per-type tuning). UI theme work (hover underglow etc.) is a separate,
later spec.

## Design

### 1. Engine trail — combat ships

New `EngineTrail` `CPUParticles2D`, added as a sibling of `HitSpark` and
`SmokeTrail` under each ship scene's existing `VFX` node
(`ship_corvette.tscn`, `ship_freighter.tscn`, `ship_capital.tscn`, and the
generic `ship.tscn` used by tests). Same creation pattern as the existing
two particle nodes — no new scene file.

- `direction = Vector2(-1, 0)`, `spread` small (~10°) — matches the
  existing +X-is-forward convention (`SmokeTrail` already assumes this).
- Subtle blue-cyan color, lower `amount`/`lifetime`/`scale_amount` than
  `SmokeTrail` so it reads as a thin engine glow, not another damage cue.
- `emitting` starts `false`; driven by script, not always-on.

`ShipVfx` (`scripts/ship/ship_vfx.gd`) gains:
- `@onready var _engine_trail: CPUParticles2D = $EngineTrail`
- `@onready var _body: CharacterBody2D = get_parent()`
- A new `_physics_process(_delta)` that sets
  `_engine_trail.emitting = _body.velocity.length() > ENGINE_TRAIL_SPEED_THRESHOLD`
  (new constant, ~5.0). Binary on/off — no speed-scaled particle rate, to
  match the existing level of fidelity in this file.

### 2. Engine trail — overworld fleet icons

One `EngineTrail` `CPUParticles2D`, added once per `CampaignFleetIcon`
(not per ship-sprite in the clump — a 3-ship clump each trailing
individually would be noise at map zoom). Created once in `setup()` as a
direct child of the icon (sibling of the ship sprites added by
`_sync_ship_dots()`), same self-contained style as the rest of that file
(no new scene — the icon's scene, `campaign_fleet_icon.tscn`, already
builds its visuals entirely from script).

- Same `direction = Vector2(-1, 0)` / color / shape as the combat version
  (reuse the constants, don't fork a second tuning).
- `CampaignFleetIcon._physics_process` already computes `movement` (the
  frame's position delta) and `HEADING_EPSILON` for sprite-heading
  rotation (`docs/superpowers/specs/.../overworld` work, now in
  `campaign_fleet_icon.gd`). Reuse both: each frame, set
  `_engine_trail.rotation = _heading_angle` (same angle the ship sprites
  use) and `_engine_trail.emitting = movement.length() > HEADING_EPSILON`.
  This keeps the trail's one-time local `direction` constant while still
  emitting backward along actual travel direction, exactly like the
  sprite-rotation trick already in this file.
- When `frozen` is true, `_physics_process` returns before reaching this
  logic today — the trail simply stays in whatever state it was last in,
  consistent with movement also freezing.

### 3. Weapon fire — muzzle flash

New scene `scenes/vfx/muzzle_flash.tscn`: a one-shot `CPUParticles2D`,
same self-freeing pattern as `scenes/vfx/explosion.tscn` (`emitting =
true`, `one_shot = true`, script connects `finished -> queue_free`).
Reuses the **existing** `scripts/vfx/explosion.gd` as its script (that
script is already generic — just "connect finished to queue_free" — so a
second scene pointing at it is reuse, not a new near-duplicate file).
Smaller/quicker than the explosion: short lifetime (~0.15s), small
`amount`, tight `spread`, yellow-white color to match the projectile.

`WeaponMount._spawn_projectile` (in `scripts/weapons/weapon_mount.gd`)
gains one line: instantiate `MuzzleFlashScene`, add it to the same `host`
node the projectile uses, position it at `global_position` (the mount's
position, i.e. the firing point) — mirrors exactly how
`ShipVfx._on_hull_destroyed` spawns the explosion scene today.

### 4. Weapon fire — projectile restyle

`scenes/weapons/projectile.tscn`: replace the `ColorRect` child with a
small elongated `Polygon2D` (a thin diamond/streak silhouette pointing
along local +X, e.g. points roughly `(8,0), (0,-2), (-4,0), (0,2)`), kept
in the same yellow-ish color family as today (`Color(1, 0.8, 0.2, 1)`) so
it still reads as "the same projectile," just shaped instead of a flat
square. Add a small trailing `CPUParticles2D` child (`direction =
Vector2(-1, 0)`, short lifetime, low amount) for a travel streak behind
it, continuously emitting from spawn (projectiles are short-lived, so no
need to gate this on movement the way the engine trail is).

`scripts/weapons/projectile.gd`'s `setup()` gains one line:
`rotation = travel_direction.angle()`, set once after `travel_direction`
is computed. `travel_direction` is fixed at spawn and never changes during
flight (confirmed in the current code — no retargeting in
`_physics_process`), so a one-time rotation is correct; the streak shape
and particle trail both inherit it automatically as the node's local +X.

### Testing

- `tests/test_ship_vfx.gd` (`run_async`): assert `EngineTrail.emitting`
  tracks `ship.velocity.length()` crossing the threshold (set `velocity`
  directly and tick a physics frame, same style as the existing
  smoke-trail assertions in this file).
- `tests/test_campaign_fleet_icon.gd`: extend the existing heading-rotation
  case (added in the prior overworld-sprites session) to also assert the
  icon's `EngineTrail.emitting` is true while moving and that its
  `rotation` matches `_heading_angle`.
- `tests/test_weapon_mount.gd`: the existing in-range `try_fire` case uses
  a `null` `weapon.projectile_scene`, so `_spawn_projectile` returns before
  reaching new code — add one new case with a real (test-local) weapon
  resource whose `projectile_scene` is set, run via a live `SceneTree`
  (new `run_async`, following `test_campaign_fleet_icon.gd`'s pattern since
  this file is currently `run`-only / no tree), asserting a
  `MuzzleFlashScene` instance appears as a child of the host at the
  mount's position after `try_fire`.
- No test asserts particle *visual* output (color/shape/count) — consistent
  with how `HitSpark`/`SmokeTrail`/explosion are tested today (structural
  presence and `emitting` state only, not rendered pixels).

## Out of scope / follow-up

- Per-ship-class trail/projectile tuning (e.g. a capital ship's engine
  trail being visibly bigger) — not done here, matches existing
  `HitSpark`/`SmokeTrail` precedent of one shared config.
- Faction-colored projectiles/trails — not done here; stays the existing
  single yellow identity.
- UI theme + hover underglow — separate spec, picked up next.
