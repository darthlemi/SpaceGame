---
name: ship-art-direction
description: SpaceGame ship art taste learned from the corvette kitbash iterations - what the user rejected and approved
metadata:
  node_type: memory
  type: feedback
  originSessionId: 744ddd2f-406b-4996-ad8a-f6fab6673c25
  modified: 2026-11-04T03:43:42.017Z
---

Ship art moved from pxl pixel art to Blender kitbash renders (`art\blender\kitbash_corvette.py`, seed 2 approved 2026-11-03). Reference the user loved: a dense top-down kitbash ship with a bronze, painted/rendered look. Overall mood: neon on dark space (Blade Runner meets FTL meets Cyberpunk 2077).

Rejected along the way, in order:
- scattered tiny boxes and dots all over the hull;
- brick-like tiled seams and a wood-grain texture;
- flat slab hulls with vertical sides;
- a mix of orange/bronze and grey plates;
- plates laid on top of a smooth hull;
- long narrow plates;
- a rippled nose edge;
- outer side booster nacelles.

**Why:** the user wants a cohesive, sleek, built-from-plates look, not a noisy greeble look.

**How to apply:** for new ships or styles:
- one base hull color (gunmetal) with only small colored/neon accents;
- the plates ARE the hull skin, with angled non-grid seams and chunky ~1:1-2:1 proportions;
- small details only in a few tight clusters;
- rounded crown thinning to SR-71-style chines, taller than the SR-71 in side profile;
- smooth, monotone tapers.

Show seeds side by side in the visual companion for the user to pick.

Capital ship (`art\blender\kitbash_capital.py`, `--hull slot` seed 1, approved 2026-11-03): a smooth elliptical saucer was rejected as "balloon like", and a domed middle as "bulbous". What was approved: a low, flat profile; a faceted outline (straight runs with chamfered corners, not ellipses); a ridged crown; a straight-sided prow wedge. For big hulls, prefer flat and angular over round and tall.
