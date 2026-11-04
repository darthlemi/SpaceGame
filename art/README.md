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
- `art/blender/*.py` — Blender kitbash ship generators (see below).
- `assets/sprites/<category>/*.png` — committed build output.

## Blender kitbash ships

Ship sprites are moving from pxl to procedural 3D kitbash renders: a lofted,
chined hull skinned with gunmetal plates plus neon accent lights, rendered
top-down by Cycles. Each script is a standalone Blender Python file; nothing
is installed into the repo. It needs Blender 5.2.

`art/blender/kitbash_corvette.py` — corvette. Seed 2 (the default) is the
approved design. Other seeds reshuffle the plating and hardware.

From the project root:

```powershell
cd art\blender
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python kitbash_corvette.py -- --out "$PWD\corvette.png"
```

`art/blender/kitbash_capital.py` — capital ship: a low, faceted saucer with an opening at
the bow where the bridge prow sits between two mandibles. It imports the shared hull,
plating and material code from `kitbash_corvette.py`, so keep both files together.
`--hull slot` with seed 1 (both the defaults) is the approved design. `--hull bay` and
`--hull oval` are the rejected alternatives. It has 6 mounts: `port_fore`, `port_mid`,
`port_aft`, `starboard_fore`, `starboard_mid` and `starboard_aft`.

```powershell
cd art\blender
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python kitbash_capital.py -- --out "$PWD\capital.png"
```

`art/blender/kitbash_freighter.py` — freighter: a long cargo bay of shipping containers
(ribbed roofs, end frames, corner castings, mixed 40ft and 20ft boxes) either side of a
keel, with a faceted command module at the bow and a wider engine block at the stern. It
also imports `kitbash_corvette.py`. `--cargo muted` with seed 1 (both the defaults) is the
approved design, and `--cargo mono` paints the containers gunmetal. It has 2 light-turret
mounts: `dorsal_fore` and `dorsal_aft`.

```powershell
cd art\blender
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python kitbash_freighter.py -- --out "$PWD\freighter.png"
```

Flags (after `--`, the same for every script unless noted):

- `--out` — the output PNG path (required).
- `--preview` — adds a space backdrop and engine flames for review renders.
  Leave it off for in-game sprites, which come out with a transparent background.
- `--res` — render width in px (default 768).
- `--samples` — Cycles samples (default 64).
- `--seed` — corvette default 2, capital and freighter default 1.
- `--cargo` — freighter only: `muted` (default) or `mono`.
- `--hull` — capital only: `slot` (default), `bay` or `oval`.
- `--verbose` — prints build timing and part counts.

Weapons are not rendered, because the game attaches them. Each mount shows as a bare grey
plate, and the script writes `<out>.mounts.json` next to the PNG
(`corvette.png` gives `corvette.mounts.json`). Each mount has these fields:

- `id` — the mount name. The corvette uses `dorsal`, `port_fore`, `port_aft`,
  `starboard_fore` and `starboard_aft`; the capital and freighter use
  the names listed above.
- `x`, `y` — the position in Godot `Sprite2D`-local pixels, measured from the image centre,
  with +x toward the nose and +y down. Multiply by the `Sprite2D` scale to get a
  `WeaponMount` node's `position`.
- `radius` — the plate radius in px.
- `facing_deg` — 0 means the mount faces the nose.

The JSON matches the image it was rendered with: `--res` and `--preview` change the framing,
so a mounts file only applies to its own PNG.

Use `&`, not `start`: in PowerShell `start` is `Start-Process`, which rejects
Blender's `-b` flag.

### In-game sprites

`assets/sprites/ships/{corvette,capital,freighter}.png` are rendered at exactly their
in-game size, so each scene's `Sprite2D` scale is 1 (there is no camera zoom; 1 world px
is 1 screen px). They come out at about 70, 122 and 101 px long. Render them with no
`--preview` and these `--res` values, and leave the mounts JSON out of `assets`:

```powershell
cd art\blender; New-Item -ItemType Directory -Force "$env:TEMP\ships" | Out-Null
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python kitbash_corvette.py -- --out "$env:TEMP\ships\corvette.png" --res 75
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python kitbash_capital.py -- --out "$env:TEMP\ships\capital.png" --res 143
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python kitbash_freighter.py -- --out "$env:TEMP\ships\freighter.png" --res 107
```

Then copy the PNGs into `assets\sprites\ships\`. The scene `WeaponMount` and `Engine`
positions were taken from that render's `.mounts.json` at these sizes. If the art or
`--res` changes, re-check them in `scenes\ship\ship_*.tscn`.

## Blender holo UI

The theme's button and panel textures (`assets\sprites\ui\button_{normal,hover,pressed,disabled}.png`
and `panel_frame.png`) are cobalt holo glass rendered by `art\blender\holo_ui.py`. It
draws flat emissive quads under a 1 unit = 1 px orthographic camera, with glow built from
falloff strips rather than the compositor. `art\src\ui_chrome.px.js` is retired: it no
longer produces the shipped UI PNGs. The commodity icons are still pxl.

```powershell
cd art\blender; New-Item -ItemType Directory -Force "$env:TEMP\holo_ui" | Out-Null
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python holo_ui.py -- --out-dir "$env:TEMP\holo_ui"
```

Then copy the five PNGs into `assets\sprites\ui\`.

| Flag | Default | Meaning |
|---|---|---|
| `--out-dir` | (required) | Where the five PNGs are written |
| `--panel-alpha` | `0.8` | Panel glass opacity; raise it if text is hard to read over the map |
| `--pressed-color` | `#eaf6ff` | Pressed fill, outline and glow colour |
| `--samples` | `16` | Cycles samples |
| `--verbose` | off | Per-texture timing and object counts |

The 9-slice margins in `assets\ui\theme.tres` must match the script: `texture_margin` 6
for the 24x24 buttons and 15 for the 66x66 panel. Everything that isn't a straight run
(corners, brackets, glow) stays inside those margins, and the tiled centre is a whole
number of pattern periods (6 px dashes, 6 px scanlines), so tiling never seams.
