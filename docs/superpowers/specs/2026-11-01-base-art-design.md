# Base Art — Design

Date: 2026-11-01

## Context

Follows the ship art session (`2026-10-31`, see `carry_forward.md`): ships moved
from flat `Polygon2D` placeholders to pixel-art sprites built with `pxl`
(`art/src/ships.px.js`), using the locked palette in `art/src/palette.px.js`.
Bases were the next queued art category. Three references were gathered
from the user (ringed/toroidal orbital stations with a central hub and
radial docking arms — see session chat; not checked into the repo, used for
visual direction only).

The game currently has three base instances, each a flat colored square
(`Polygon2D`, 40x40, `Area2D` with `CircleShape2D` radius 30):

- **Player HomeBase** (`scenes/campaign/home_base.tscn`, green) — one
  instance, economy slots `TRADE_HUB + REFINERY`.
- **FactionBase** (`scenes/campaign/faction_base.tscn`, red) — one shared
  scene instantiated twice (Dominion, Freehold), distinguished at runtime
  only by an unused `faction_enum` field (`scripts/campaign/faction_base.gd`)
  — the color is currently hardcoded, not faction-driven.
  - Dominion economy: `INDUSTRIAL + POPULATION`.
  - Freehold economy: `MINING + AGRICULTURE`.

Pirates have no fixed base (roam only) — out of scope.

## Design

### Silhouettes (distinct per base, not just recolors)

All three references share a ring/torus-with-central-hub shape. Rather than
reuse that shape three times with different colors, each base gets its own
silhouette, chosen to match its economic role:

- **Dominion** — full ring/torus with central hub. Closest interpretation
  of the references: authoritative, heavily greebled, the most "complete"
  looking station. Matches `INDUSTRIAL + POPULATION`.
- **Freehold** — asymmetric mining-rig cluster, no full ring. Scrappy,
  bolted-together, utilitarian — reads as industrial-frontier rather than
  polished. Matches `MINING + AGRICULTURE`.
- **Player HomeBase** — compact hub-and-spoke trade station: a small core
  with a few docking arms. Deliberately more modest in scale/complexity
  than the two faction bases, since it's the player's starting point, not
  a power faction's capital. Matches `TRADE_HUB + REFINERY`.

### Palette

Stays within the locked `art/src/palette.px.js` noir palette (dirty-grey
hull, near-black outline) for visual continuity with the ships. Unlike the
ships (one dominant accent each), bases may mix accents more freely:

- Dominion: red + orange (authority/industry)
- Freehold: green + yellow (agriculture/mining)
- Player HomeBase: blue (neutral/trade)

These are starting points, not locked — subject to the same live iteration
against previews that the ship palette went through.

### Build pipeline

Same as ships: new `art/src/bases.px.js` (pxl source, importing
`palette.px.js` the same copy-paste way `ships.px.js` does — pxl has no
cross-file import), built locally with `pxl` (cloned at `../UIilianks/pxl`
relative to the repo), exported PNGs copied into `assets/sprites/bases/`.

### Godot wiring

- `scenes/campaign/home_base.tscn`: swap the `Polygon2D` placeholder for a
  `Sprite2D` referencing the HomeBase texture — same pattern as the ship
  scenes.
- `scenes/campaign/faction_base.tscn` is a **shared** scene for both
  Dominion and Freehold, selected per-instance via `faction_enum`
  (`CampaignFleet.Faction`, set by `CampaignScene._ready()` when
  instantiating each `FactionBase`). Currently that field exists but drives
  nothing visual. `scripts/campaign/faction_base.gd` gains a `_ready()`
  that picks the Dominion or Freehold texture based on `faction_enum` and
  applies it to the scene's `Sprite2D` — the shared-scene architecture
  doesn't change, it just finally uses the field that's already there.
- Collision shapes (`CircleShape2D`, radius 30) are untouched. Sprite scale
  is tuned visually (iterate against the real collision radius in-editor),
  same approach used for the three ship scales.

### Out of scope

- Pirates (no fixed base).
- Any change to `BaseEconomy`, `PowerFaction`, or economy-role logic —
  visual only.
- A fourth, player-specific `FactionBase` variant — the player's base stays
  `HomeBase`, a separate scene, as it already is.

## Testing

Existing `tests/test_faction_base.gd` and any `HomeBase`/`CampaignScene`
tests must keep passing after the `Sprite2D` swap — same gotcha as the ship
session: `Polygon2D`-specific node lookups (if any exist for bases) need
checking before assuming nothing breaks silently.
