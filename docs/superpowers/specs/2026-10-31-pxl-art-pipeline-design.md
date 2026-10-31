# pxl Art Pipeline — Design Spec

## Purpose

SpaceGame currently has zero art — ships, bullets, map icons, and UI are all
flat-colored `Polygon2D`/`ColorRect` placeholders. This spec establishes the
pipeline and palette for replacing those placeholders with real sprites,
generated with [pxl](https://github.com/uilianks/pxl) (MIT), a small
JavaScript DSL that renders pixel art to PNG and was evaluated against
`vex` (vector art) side by side before being chosen for its retro, chunky,
grid-snapped look.

## Out of scope

Producing the actual ship/VFX/UI/background assets. This spec only sets up
*where things live and how they're built*. Each asset category (ships,
projectiles/VFX, campaign map icons, UI panel icons, background/starfield)
is big enough to need its own design pass and gets its own future spec.

## Tool

`pxl` stays external to this repo — cloned separately from
`github.com/uilianks/pxl`, the same way you'd install any other authoring
tool (an image editor, a DAW). SpaceGame's repo does not vendor it or add
its Node/TypeScript tooling as a project dependency; this keeps the game
repo exactly as it is today (pure Godot/GDScript) with no extra build
tooling required to open and run the project.

Building art requires Node ≥ 22.18 and a local clone of `pxl`, then:

```
node <path-to-pxl-clone>/bin/pxl.js build art/src/<file>.px.js
```

Output goes to that file's `out/` directory; finished PNGs get copied (or
the build pointed to output directly) into `assets/sprites/<category>/`.

## Palette

Locked after comparing military/neon/arcade mood boards and iterating
toward a "noir cyberpunk" direction (dark, high-contrast neon accents on a
near-black base — grey gunmetal hull, not pure black, so it reads against
a starfield). Defined once, copy-pasted at the top of every `.px.js` file
in `art/src/` (pxl has no cross-file import; each file is standalone):

```js
pal({
  k: "#060607",   // outline, near-black
  h: "#5a584f",   // hull, dirty grey
  H: "#38362f",   // hull shadow
  c: "#4dff8a",   // neon green accent
  C: "#167a3f",   // neon green, dim
  e: "#ff3b3b",   // neon red accent
  E: "#8a1414",   // neon red, dim
  b: "#3f9fff",   // neon blue accent
  B: "#1a4e8a",   // neon blue, dim
  y: "#d1a52c",   // darker yellow (secondary accent)
  o: "#c05a1f",   // darker orange (secondary accent)
  p: "#b23d6e",   // darker pink (secondary accent)
})
```

Green/red/blue are the primary accent trio (e.g. candidates for
cockpit glow, engine glow, faction identity — exact assignment is a
future spec's call). Yellow/orange/pink are secondary, for variety where
three accents aren't enough (e.g. distinguishing a third+ faction, or
pickup/loot highlighting).

## File layout

```
art/
  README.md           — how to clone pxl, build command, output convention
  src/
    palette.px.js      — the palette above, source of truth to copy from
    ships.px.js         — future spec
    vfx.px.js            — future spec
    ui.px.js               — future spec
    campaign.px.js           — future spec
    backgrounds.px.js         — future spec
assets/
  sprites/
    ships/*.png        — committed output, referenced by Godot scenes
    vfx/*.png
    ui/*.png
    campaign/*.png
    backgrounds/*.png
```

Generated PNGs are committed to git (Godot loads them directly; nothing
in the game build process runs `pxl`). `.px.js` sources are also
committed, as the editable "art code" — source of truth for regenerating
or tweaking a sprite later.

## Testing

None — this spec adds no game logic, only a directory convention and a
documented build command.
