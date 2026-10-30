# Ship Damage/Death Visual Feedback — Design Spec

## Vision Recap

Follows the multi-ship combat milestone (see
`2026-08-26-multi-ship-combat-design.md`), which gave ships hull/shield/
hit logic but no visual feedback: a ship takes damage, nears death, and
explodes with no on-screen cue beyond the HP numbers and its eventual
disappearance. This milestone adds that feedback so combat reads clearly
without needing a health bar.

## Goals for This Milestone

- Every hit flashes the ship and throws a small spark burst.
- A ship below a low-HP threshold continuously trails smoke/sparks until
  it dies or is healed back above the threshold.
- A ship's death plays a one-shot explosion at its last position, which
  outlives the ship itself.
- All effects use flat-colored placeholder particles (no textures), with
  particle colors/amounts as `@export` tunables so real textures/sprites
  can be swapped in later without touching the triggering logic.

## Out of Scope

- Camera/screen shake (explicitly dropped per discussion — flash + spark
  is enough punch for now).
- Persistent damage decals, hull scorch marks, or sprite-based damage
  states (no sprites exist yet).
- Sourcing real particle textures/art (placeholder flat-color particles
  only this milestone).
- A health bar or other HUD element.
- Any change to `Hull`'s or `Ship`'s damage/combat logic — this is purely
  a new listener on existing signals.

## Architecture

`Hull` already emits `damaged(amount, remaining)` and `destroyed` and
needs no changes. All new behavior lives in one new node, `ShipVfx`
(script `scripts/ship/ship_vfx.gd`), added as a sibling of `Hull`/
`Shield`/`Engine` inside `ship.tscn` — the same one-node-per-concern
pattern those already follow. `ShipVfx` resolves its sibling `Hull` and
`Polygon2D` via direct node paths (not through `Ship`'s own `@onready`
vars, which resolve later in sibling-ready order) and connects to
`Hull`'s signals itself. `ship.gd` and `hull.gd` are untouched.

Low-HP smoke toggling is the one piece of non-trivial logic here, so it's
isolated as a pure static function (`ShipVfx.should_emit_smoke`) the same
way `Ship.should_disengage` was isolated in the prior milestone — pure
logic gets a unit test, particle/tween playback gets a playtest.

Explosion survives the ship's `queue_free()` by being instantiated under
the ship's *parent*, not the ship, at the ship's `global_position`.

## Components

- **`ShipVfx`** (new, `Node2D`, child of `Ship`): on `ready`, resolves
  `$"../Polygon2D"` and `$"../Hull"`, connects to `Hull.damaged` and
  `Hull.destroyed`.
  - On `damaged(amount, remaining)`: tweens the `Polygon2D`'s `modulate`
    to `flash_color` and back over `flash_duration`; calls `restart()` on
    the `HitSpark` child; sets `SmokeTrail.emitting =
    ShipVfx.should_emit_smoke(remaining / hull.max_hp, low_hp_threshold)`.
  - On `destroyed`: instantiates `scenes/vfx/explosion.tscn` as a child of
    `get_parent()` (the ship's parent, e.g. `CombatScene`), positioned at
    `get_parent().to_local(global_position)` — ahead of `ship.gd`'s own
    `_on_hull_destroyed` → `queue_free()`, which still fires normally
    since both listeners run before the deferred free takes effect.
  - `@export` tunables: `flash_color: Color`, `flash_duration: float`,
    `low_hp_threshold: float = 0.25`.
- **`HitSpark`** (new, `CPUParticles2D`, child of `ShipVfx`): one-shot,
  `emitting = false` by default, restarted per hit. `@export`-tunable via
  the node's own particle properties (amount, spread, initial velocity,
  lifetime, color) directly in the scene file — no script needed beyond
  the restart call from `ShipVfx`.
- **`SmokeTrail`** (new, `CPUParticles2D`, child of `ShipVfx`):
  continuous, `emitting = false` by default, toggled by `ShipVfx`. Same
  inspector-tunable particle properties, no script.
- **`scenes/vfx/explosion.tscn`** + **`scripts/vfx/explosion.gd`** (new):
  a one-shot `CPUParticles2D` root. Script connects `finished → queue_free`
  and is otherwise empty — `emitting`/`one_shot` are set in the scene file.

## Data Flow

1. A hit lands → `Hull.apply_damage()` emits `damaged(amount, remaining)`.
2. `ShipVfx` flashes the hull polygon, restarts `HitSpark`, and
   recalculates whether `SmokeTrail` should be emitting based on the new
   HP ratio.
3. HP reaches 0 → `Hull.apply_damage()` emits `destroyed`.
4. `ShipVfx` spawns an `explosion.tscn` instance under the ship's parent
   at the ship's last position; it plays out and frees itself
   independently of the ship.
5. `ship.gd`'s existing `_on_hull_destroyed` still calls `queue_free()` on
   the ship itself, unchanged.

## Testing

- `tests/test_ship_vfx.gd` (new, registered in `tests/run_tests.gd`):
  unit tests `ShipVfx.should_emit_smoke(hp_ratio, threshold)` — below
  threshold → true, above → false, at threshold → true (inclusive).
- Flash timing, particle appearance, and explosion playback are
  playtest-verified in the editor (per Global Constraints below) — no
  headless test renders particles or tweens.

## Global Constraints

- Godot 4.7.x, no external addons, `CPUParticles2D` only (matches "no
  textures yet" — `GPUParticles2D` needs a material/texture to look like
  anything beyond a flat square, `CPUParticles2D` is the simpler choice
  for the same placeholder look).
- All new particle/flash constants are `@export`, per the existing
  tuning convention — no hardcoded magic numbers.
- `ShipVfx` only ever reads from `Hull`/`Ship`; it never mutates combat
  state (HP, orders, etc.) — one-directional, consistent with the rest of
  the codebase's component separation.
