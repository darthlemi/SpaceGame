// UI chrome: panel background + button states, shared across every UI
// panel (Trade, Loot, Speed Controls, Game Over). Locked style: double
// border panel (C) and chamfered-bracket buttons (C), both with red
// accent (swapped from the sample gallery's blue per user feedback).
//
// See docs/superpowers/specs/2026-11-02-ui-art-design.md.

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

// Panel background — double border, red accent corner ticks. Stretched
// via a Godot StyleBoxTexture 9-patch (margins = the 6px outer frame).
sprite("panel_frame", { w: 160, h: 100, outline: "k" },
  rect(0, 0, 160, 100, "H"),
  rect(6, 6, 148, 88, "h"),
  box(6, 6, 148, 88, "H"),
  line(6, 6, 16, 6, "e"), line(6, 6, 6, 16, "e"),
  line(154, 6, 144, 6, "e"), line(154, 6, 154, 16, "e"),
  line(6, 94, 16, 94, "e"), line(6, 94, 6, 84, "e"),
  line(154, 94, 144, 94, "e"), line(154, 94, 154, 84, "e"))

// Button — chamfered bracket, 4 states. Used for Close, Buy/Sell, the
// 1x/3x/5x speed toggles, and Pause.
sprite("button_normal", { w: 56, h: 22 },
  poly([6, 0, 50, 0, 56, 6, 56, 16, 50, 22, 6, 22, 0, 16, 0, 6], "h"),
  poly([7, 1, 49, 1, 55, 6, 55, 16, 49, 21, 7, 21, 1, 16, 1, 6], "H"),
  poly([8, 2, 48, 2, 53, 6, 53, 15, 48, 20, 8, 20, 3, 15, 3, 6], "h"))
sprite("button_hover", { w: 56, h: 22 },
  poly([6, 0, 50, 0, 56, 6, 56, 16, 50, 22, 6, 22, 0, 16, 0, 6], "e"),
  poly([7, 1, 49, 1, 55, 6, 55, 16, 49, 21, 7, 21, 1, 16, 1, 6], "H"),
  poly([8, 2, 48, 2, 53, 6, 53, 15, 48, 20, 8, 20, 3, 15, 3, 6], "h"))
sprite("button_pressed", { w: 56, h: 22 },
  poly([6, 0, 50, 0, 56, 6, 56, 16, 50, 22, 6, 22, 0, 16, 0, 6], "e"),
  poly([7, 1, 49, 1, 55, 6, 55, 16, 49, 21, 7, 21, 1, 16, 1, 6], "h"),
  poly([8, 2, 48, 2, 53, 6, 53, 15, 48, 20, 8, 20, 3, 15, 3, 6], "H"))
sprite("button_disabled", { w: 56, h: 22 },
  poly([6, 0, 50, 0, 56, 6, 56, 16, 50, 22, 6, 22, 0, 16, 0, 6], "H"),
  poly([7, 1, 49, 1, 55, 6, 55, 16, 49, 21, 7, 21, 1, 16, 1, 6], "k"),
  poly([8, 2, 48, 2, 53, 6, 53, 15, 48, 20, 8, 20, 3, 15, 3, 6], "H"))
