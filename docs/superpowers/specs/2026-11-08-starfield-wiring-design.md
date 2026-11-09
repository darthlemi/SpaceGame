# Starfield wiring design (2026-11-08)

## Scope

This round covers **starfield plumbing only**: wiring the already-approved starfield
tileset (`art/blender/Starfield/`, built and approved 2026-11-08, see
`carry_forward.md`'s Background art entry) into the campaign system view and the
combat scene. Nebula-tint layers, and placing the planet/moon/asteroid render
library, are explicitly out of scope for this round — asteroids (singles) and
nebula tints aren't finished, and the recipe/assignment format they'll eventually
need is a separate future piece. This round only has to solve assignment for the
starfield itself.

## Asset pipeline

Copy the Godot-needed files out of the Blender output directory into the game's
asset tree, matching the existing ships/stations convention (`art/blender/` =
source, `assets/sprites/` = game-ready):

- `art/blender/Starfield/{Sparse,Light,Medium,Dense,Clustered}/*.png` →
  `assets/sprites/backgrounds/starfield/{sparse,light,medium,dense,clustered}/*.png`
  (lower-cased folder names), keeping the `*_01.png`..`*_05.png` naming.
- `art/blender/Starfield/Depth_Layers/{Deep_Background,Mid_Distance,Foreground}/*.png` →
  `assets/sprites/backgrounds/starfield/depth_layers/{deep_background,mid_distance,foreground}.png`.

`art/blender/Starfield/` remains the source of truth for regeneration; the
`assets/` copies are what scenes reference. Per `godot_notes.md`, new PNGs need
one `--headless --editor --quit` warm pass before a `--script` test run sees them
(this rewrites `.import` files with CRLF-only diffs — expected, not noise).

## Assignment logic

New pure-logic module, `scripts/background/starfield_assignment.gd`
(`class_name StarfieldAssignment`, static functions only — no autoload, no Godot
node dependency, so it's trivially unit-testable):

- `const CATEGORIES := ["sparse", "light", "medium", "dense", "clustered"]`
- `static func pick(id: String) -> Dictionary` → `{"category": String, "seed": int}`.
  Derives the category index from `hash(id) % CATEGORIES.size()` and the seed
  index (1-5) from a second, independent hash (`hash(id + "_seed") % 5 + 1`), so
  the same id always resolves identically with zero stored data and zero manual
  curation.
- `static func base_texture_path(id: String) -> String` — builds
  `res://assets/sprites/backgrounds/starfield/%s/%s_%02d.png % [category, category, seed]`
  from `pick(id)`.

Both combat and campaign call this with the **same id** — the current star
system's id — so a battle fought at a system visually matches that system's map
view. Combat reads it from `CampaignState.player_fleet.system_id` at the point
combat starts (the player is always physically at that system when a fight
triggers).

## Combat wiring

New scene `scenes/combat/combat_starfield.tscn` + script
`scripts/combat/combat_starfield.gd`. A `ParallaxBackground` with 4
`ParallaxLayer` children, each holding one `Sprite2D` with `motion_mirroring` set
to the texture size (1024×1024) for seamless infinite tiling as `CombatCamera`
pans/zooms over the 3200×3200 arena:

| Layer | Texture | `motion_scale` (starting value, tune by eye) |
|---|---|---|
| Base | per-system density tile via `StarfieldAssignment` | ~1.0 (furthest/most static) |
| Deep_Background | fixed depth-layer PNG | ~0.9 |
| Mid_Distance | fixed depth-layer PNG | ~0.75 |
| Foreground | fixed depth-layer PNG | ~0.5 (nearest/fastest parallax) |

The three depth layers are universal dressing — always the same 3 files
regardless of density category. Only the Base layer's texture varies per
system.

`combat_starfield.gd` exposes `func setup(system_id: String) -> void`, setting
the Base layer's `Sprite2D.texture` via `StarfieldAssignment.base_texture_path`.
`combat_scene.gd`'s `_ready()` instances this scene, calls
`setup(CampaignState.player_fleet.system_id)`, and adds it as the **first
child** of the scene tree so it draws behind ships, VFX, and UI.

## Campaign wiring

No new scene. A `TextureRect` named `Background`, added as the **first child**
of `campaign_scene.tscn`, anchored full-rect to the fixed 1152×648 viewport,
`stretch_mode = TextureRect.STRETCH_TILE` (no parallax, no camera — the view
never scrolls, so a single tiled static texture is the simplest fit).

`campaign_scene.gd`'s existing `show_system(system_id: String)` gets one added
line setting `$Background.texture = load(StarfieldAssignment.base_texture_path(system_id))`
whenever the current system changes.

## Testing & verification

- Unit test for `StarfieldAssignment`: calling `pick()` twice with the same id
  returns the same result (determinism); a spread of different ids doesn't all
  land in one category bucket; `base_texture_path()`'s output matches the
  expected `res://assets/...` pattern for a known id.
- No automated test asserts actual pixel tiling or parallax motion. Following
  the existing screenshot pattern in `godot_notes.md`, verify visually with an
  in-engine screenshot of a campaign system view and a combat scene after
  wiring, rather than claiming success from code alone.
- Run the full existing test suite to confirm the new background node /
  texture assignment doesn't regress any scene test that counts children or
  checks scene structure.

## Out of scope (next rounds, once their art is locked)

- Nebula-tint layers (soft localized color blobs, never a flat wash).
- Planet/moon/asteroid placement library and its recipe format.
- Per-system recipe data stored in `data/galaxy.json` (this round uses a pure
  hash, no stored assignment).
