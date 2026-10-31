// SpaceGame base palette. Copy this pal() block into the top of any other
// art/src/*.px.js file — pxl has no cross-file import, so this file is the
// source of truth, not something that gets built itself.
//
// See docs/superpowers/specs/2026-10-31-pxl-art-pipeline-design.md

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
