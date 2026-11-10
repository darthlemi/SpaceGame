# Map editor: visual station & scenery placement - design

## Intent
The map editor (`docs\superpowers\specs\2026-11-05-map-editor-design.md`) edits station position only
as numeric x/y fields. The starfield wiring round (`2026-11-08-starfield-wiring-design.md`) wired a
single hash-picked backdrop into the campaign system view and explicitly deferred "planet/asteroid
placement library" and "per-system recipe data stored in data/galaxy.json" to a later round. This is
that round: a visual System tab lets the user drag stations onto their real positions by eye, pick a
system's background by eye instead of by hash, and hand-place (or randomize) planets and asteroids,
with the same data the editor shows being what the campaign game renders.

## Goals
- A "System" tab (third tab, alongside Map and Presets) with two sub-tabs: Stations and Scenery.
- Stations sub-tab: canvas shows every station in the selected system as its real sprite at its real
  position; dragging moves it, kept in sync with the existing numeric pos fields in the station
  inspector (both edit the same field; neither is removed).
- Scenery sub-tab: pick the system's background (category + seed, overriding today's pure hash), and
  place/drag planets and asteroids, each on a layer (Deep Background / Mid Distance / Foreground) that
  controls draw order relative to stations (Foreground draws in front; the other two draw behind).
- Randomize button: replaces the system's background and scenery with a fresh random pick (1-2
  planets, 1-4 asteroids, no same-type overlap).
- Asset browser: pick a folder under `assets/sprites/backgrounds/` (today: planets, asteroids; future
  folders need no editor code change), see real thumbnail previews, click to select, place.
- The campaign game renders the same background + scenery the editor shows (no camera panning added;
  draw order only, matching the system view's current fixed, non-scrolling viewport).

## Non-goals
- No camera panning / real parallax motion in the campaign system view (combat's parallax is untouched
  and unrelated; campaign's view stays static, as decided in the starfield wiring round).
- No nebula-tint layers (still out of scope per the starfield wiring round).
- No free-form "extra" bucket on scenery items - the shape is fixed and small; new fields are a
  one-line schema change, same philosophy as everywhere else in this editor.
- No change to combat's existing `CombatScenery` recipes or rendering.

## Decisions (made with the user)
- **Scenery coordinate space is 3200x3200**, matching the combat arena, independent of the station
  `pos` field's existing 0..1200 space - future-proofed for when/if campaign ever gets a moving camera.
  The Scenery canvas draws a dashed outline of the current 1152x648 visible viewport inside that space
  so it's clear what actually shows up in today's game versus what's placed for later.
- **Layers are draw order only**, named after the real asset folders (Deep Background / Mid Distance /
  Foreground). No motion/parallax is added to the campaign view in this round.
- **Randomize replaces**, it does not add to, the system's current background and scenery.
- **Same-type overlap is avoided** by Randomize only; manual dragging is free (no enforcement),
  exactly like station dragging today.
- **Asset browser lives inline** in the Scenery sub-tab's side panel (thumbnail grid in the same
  panel), not a separate popup window.
- **Stations and Scenery are separate sub-tabs**, not one shared canvas.

## Data model
New optional per-system fields in `data/galaxy.json`:
```json
"background": {"category": "medium", "seed": 3},
"scenery": [
  {"type": "planet", "texture": "planet_gas_purple.png", "pos": [160.0, 90.0], "scale": 3.5, "layer": "mid_distance"},
  {"type": "asteroid", "texture": "v1_round_a.png", "pos": [860.0, 520.0], "scale": 1.3, "layer": "foreground"}
]
```
- Both keys optional. Absent `background` keeps today's exact behavior: `StarfieldAssignment.pick`
  derives category/seed from `hash(system_id)`. Absent or empty `scenery` shows just the background,
  like today.
- `background.category` is one of `StarfieldAssignment.CATEGORIES`; `seed` is `1..SEED_COUNT`.
- `scenery[].type` is the singular form of the folder name under `assets/sprites/backgrounds/`
  (`"planet"` for `planets/`, `"asteroid"` for `asteroids/`, matching `CombatScenery.BodyType` naming;
  a future folder follows the same singular-of-plural rule with no code change). `texture` is a
  filename in that folder. `pos` is `[x, y]` in the 3200x3200 scenery space. `scale` is a float.
  `layer` is `"deep_background"` / `"mid_distance"` / `"foreground"`.
- `GalaxyDocument.SYSTEM_KEYS` gains `"background"`, `"scenery"`; new key-order contexts added for a
  background dict (`category`, `seed`) and a scenery item (`type`, `texture`, `pos`, `scale`, `layer`).
  Output stays deterministic and round-trips byte-for-byte like every other field.

## Editor UI
- **System tab**: a system selector (shares selection with the Map tab) drives both sub-tabs.
- **Stations sub-tab**: `StationCanvas` (modeled on `MapCanvas`) draws every station in the selected
  system as its real sprite via `StationData.texture_path()`, scaled the same way
  `CampaignStation.setup()` does (72px max dimension). Click selects (syncs with the existing station
  list/inspector); drag moves it through the same `set_station_field(id, "pos", ...)` path the numeric
  spinboxes already use, so both stay live-in-sync.
- **Scenery sub-tab**: `SceneryCanvas` at 3200x3200 scale shows the system's background tile (preview
  of the real `StarfieldAssignment` texture), a dashed outline of the 1152x648 visible viewport, and
  every placed planet/asteroid as its real sprite, draggable; click selects.
- Side panel: Background (category + seed dropdowns, defaulting to whatever the hash currently picks
  if unset, plus a preview swatch); Folder dropdown (scanned from `assets/sprites/backgrounds/*`,
  generalizing `EditorFields`'s existing directory-scan pattern used for station `art`); Layer dropdown;
  a thumbnail preview grid of the chosen folder's files (real textures, not placeholders) with a
  "+ Place" button dropping the selected one at canvas center; Randomize button; selected item's Scale
  spinbox and Delete button.

## Randomize algorithm
New pure-logic module `scripts/editor/scenery_randomizer.gd` (static functions, seeded
`RandomNumberGenerator` so it's unit-testable), mirroring `CombatScenery`'s style but generative:
1. Pick background: random category from `StarfieldAssignment.CATEGORIES`, random seed `1..SEED_COUNT`.
2. Pick counts: planets `randi_range(1, 2)`, asteroids `randi_range(1, 4)`.
3. Per item: random texture from its folder, random position in the 3200x3200 space, random layer,
   scale within `CombatScenery`-derived bands (~3.0-4.0 planets, ~1.0-2.0 asteroids).
4. Same-type overlap avoidance: approximate radius = `scale * a fixed base radius per type`; retry a
   few times on collision with an already-placed same-type item, then accept anyway rather than
   looping forever.
5. Replaces `doc["background"]` and `doc["scenery"]` for the selected system wholesale; marks the model
   dirty like any other edit.

## Runtime wiring
- `StarfieldAssignment.pick()` / `base_texture_path()` gain an optional explicit `{category, seed}`
  override parameter: if the system doc carries a `background` entry, callers pass it through;
  otherwise behavior is identical to today's pure hash. Additive, no existing caller breaks.
- `SystemLayer` gains `add_scenery(item: Dictionary)`: instances a plain `Sprite2D` at the item's
  `pos`/`scale` from its resolved texture path, added to the tree ordered by `layer` relative to
  stations (deep_background/mid_distance children added before stations, foreground children added
  after) - child order only, no `ParallaxBackground`, no motion.
- `campaign_scene.gd`'s `_build_layers()` reads `system.scenery` (if present) after adding that
  system's stations and calls `add_scenery` for each; and threads the system's `background` (if
  present) into the existing `StarfieldAssignment` call in `show_system()`.

## Validation
- No new Save blockers. A bad scenery `texture` name fails the same way a bad station `art` name does
  today: caught by the asset-existence test, not by `GalaxyValidator`.

## Verification
- `GalaxyDocument` round-trip tests: `background`/`scenery` present and absent, unknown systems/stations
  unaffected.
- `StarfieldAssignment` override test: explicit `{category, seed}` wins over the hash; omitted falls
  back to the hash exactly as today.
- `SceneryRandomizer` tests: counts land in range; same-type pairs don't overlap (bounded retries);
  determinism under a seeded RNG.
- `StationCanvas` / `SceneryCanvas` tests: press/drag/select handlers driven through public methods,
  same pattern as the existing `MapCanvas` tests in `test_map_editor.gd`.
- Asset-existence test extended to cover every `scenery[].texture` the same way it covers station `art`.
- Screenshot of the Scenery sub-tab with a real system loaded, and of a campaign system view showing
  placed scenery in-game.
- Full test suite clean except the known long-run-sim flake; 0 `SCRIPT ERROR`.

## Left to the builder
- Exact base radius constants per type for the overlap check (tune by eye against `CombatScenery`'s
  existing radius values).
- Exact scale bands and position-retry count for `SceneryRandomizer`.
- Whether `StationCanvas` and `SceneryCanvas` share a common base class with `MapCanvas` (same drag/
  select plumbing) or just follow its pattern independently - builder's call, favor whichever keeps
  each file smallest and clearest.
