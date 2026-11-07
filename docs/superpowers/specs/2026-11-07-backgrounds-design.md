# Backgrounds art — iteration notes (2026-11-07)

Not a locked design spec yet — this is a checkpoint of the asteroid-rock iteration so it
survives between sessions. See `carry_forward.md`'s Background art entry for the overall
scope (30 campaign + 30 combat backgrounds, shared tileable starfield/nebula + a standalone
planet/moon/asteroid library) and for what's still undecided (recipe format, background
assignment).

## Script

`art/blender/experiments/bg_preview.py` — throwaway, not wired into the real pipeline or
`art/README.md`. Same conventions as `kitbash_corvette.py` (Cycles, ortho top-down camera,
`hex_lin` for node colors). Run from `art/blender/`:

```powershell
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python experiments\bg_preview.py -- --out-dir "$env:TEMP\bg_preview"
```

`main()` currently renders 4 singular large rocks (`rock_single_seed1-4`) and one cluster
check (`asteroids_v3_seed1`). Planets (`render_planet`) and the starfield tile generator
(`starfield_tile`) are also in the file from the earlier pass but not called from `main()`
right now.

## Planets/moons — approved, unchanged this session

Smooth Cycles spheres, `shade_smooth`, layered noise (coarse band noise x fine detail,
bump-mapped), thin Fresnel emission shell for a rim glow. **Open feedback from this
session, not yet acted on:** the user says they read too much like polished marble and
want a slight hazy atmosphere look instead of the current tight Fresnel rim — next
iteration, not done.

## Asteroids — this session's work

Starting point: low-poly faceted rocks had already been rejected (dark/flat). This session
replaced them with a high-poly smooth-shaded recipe, then iterated on craters against a
reference photo of asteroid 16 Psyche (dense, fairly shallow craters; granular rocky
surface; cool grey-blue stone with rust/copper mineral streaks).

**Geometry** (`add_craters` in the script): real mesh displacement, not a shader bump —
a shader can't produce true self-shadowed bowl interiors. For each crater: pick a random
unit-sphere direction as its center, then for every vertex within its angular radius,
carve a parabolic dished floor out to 60% of that radius and a raised rim back out to
100%. Each rock gets two passes — a few bigger/deeper "major" craters plus many more
small/shallow "minor" ones — layered for a densely pitted look rather than a few isolated
pits. Rim height was originally `depth * 0.3` and the user called it too raised; it's now
`depth * 0.12`. Low-frequency Perlin noise (via `mathutils.noise.noise`, not periodic sine
waves — sine at high subdivision counts read as ribbed/banded, an earlier failed attempt)
still drives the overall irregular silhouette, applied before the craters are carved.

**Material** (`rock_mat`): coarse noise for patchy mineral variation, a separate sparse
rust-colored noise layer mixed in at low opacity for the reference's copper streaks, fine
high-frequency noise driving a bump for granular surface roughness, Pointiness-based
wear shading (mild darken in creases / lighten on worn high points), and a real
`ShaderNodeAmbientOcclusion` pass that darkens crater interiors and other creases — doing
double duty with the real geometry so shadowed pits read as genuinely dark. Base palette
shifted from a warm tan (too generic-brown) to a cooler grey (`#6e7076`-ish family) closer
to the reference's stone-and-metal look.

**Known issue, not yet resolved:** the rust-patch mix (`rust_mix` node, `Color2` =
`(0.42, 0.22, 0.1, 1.0)` at up to 0.35 fac) renders more pastel/candy-pink than the muted
rust streaks in the reference — next pass should darken/desaturate it and probably shrink
the patches.

**Framing:** `render_single_rock`'s camera `ortho_scale` was bumped from 7.0 to 7.8 after
a rock didn't fully fit in frame once the elongation stretch (`elongation` up to 2.1) was
combined with crater-driven bulk. Not rigorously verified against the stretch math — if a
body clips again, increase this further or derive it from the mesh bounding box instead of
a fixed guess.

## Next steps

1. Tone down the rust-patch color/opacity to match the reference better.
2. Revisit planet atmosphere per the hazy-look feedback above.
3. Decide the recipe data format and background-assignment questions noted in
   `carry_forward.md`, then write the real (non-throwaway) design spec and pipeline script.
