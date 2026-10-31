# Art pipeline

SpaceGame's sprites are authored as code with
[pxl](https://github.com/uilianks/pxl) (MIT), a pixel-art DSL. See
`docs/superpowers/specs/2026-10-31-pxl-art-pipeline-design.md` for the full
design and the locked base palette.

pxl is not vendored into this repo. To build art:

1. Clone it somewhere: `git clone https://github.com/uilianks/pxl`
2. `npm install` once inside that clone (Node ≥ 22.18)
3. Build a file: `node <path-to-pxl-clone>/bin/pxl.js build art/src/<file>.px.js`
4. Preview output lands in that file's `out/_preview/`; copy finished PNGs
   into `assets/sprites/<category>/` — that's what Godot scenes reference.

## Layout

- `art/src/palette.px.js` — the base palette. Copy its `pal()` block into
  the top of any new `.px.js` file (pxl has no cross-file import).
- `art/src/<category>.px.js` — one file per asset category (ships, vfx,
  ui, campaign, backgrounds), added as each is designed.
- `assets/sprites/<category>/*.png` — committed build output.
