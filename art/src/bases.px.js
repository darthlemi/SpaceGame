// Base sprites (player HomeBase, Dominion/Freehold FactionBase). Copy of
// palette.px.js's pal() block (pxl has no cross-file import). Top-down
// overworld view — these are map icons, not foreshortened/isometric.
//
// See docs/superpowers/specs/2026-11-01-base-art-design.md for the design,
// and docs/superpowers/specs/2026-10-31-pxl-art-pipeline-design.md for the
// pipeline.

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

// Dominion FactionBase — full ring/torus with central hub. Industrial +
// population economy: the most "complete" looking station, authoritative.
// Accent mix: red (e/E) + orange (o).
sprite("dominion_base", { w: 72, h: 72, outline: "k" },
  // outer ring band (annulus: fill then erase the center)
  circ(35, 35, 33, "h"),
  circ(35, 35, 23, "_"),
  ring(35, 35, 33, "H"),
  ring(35, 35, 23, "H"),
  // central hub
  circ(35, 35, 9, "h"),
  ring(35, 35, 9, "e"),
  circ(35, 35, 5, "H"),
  // spokes connecting hub to ring, at the 4 cardinal points
  rect(33, 10, 4, 16, "H"), rect(33, 44, 4, 16, "H"),
  rect(10, 33, 16, 4, "H"), rect(44, 33, 16, 4, "H"),
  line(33, 10, 33, 26, "o", 1), line(37, 46, 37, 62, "o", 1),
  line(10, 33, 26, 33, "o", 1), line(46, 37, 62, 37, "o", 1),
  // docking arms — struts jutting diagonally past the outer ring, capped
  // with a small pad and light, at NE and SW
  line(58, 12, 68, 2, "h", 4), circ(68, 2, 3, "h"), ring(68, 2, 3, "H"), circ(68, 2, 1, "e"),
  line(12, 58, 2, 68, "h", 4), circ(2, 68, 3, "h"), ring(2, 68, 3, "H"), circ(2, 68, 1, "e"),
  // panel greebling — short radial ticks across the ring band
  line(35, 2, 35, 9, "H"), line(35, 61, 35, 68, "H"),
  line(2, 35, 9, 35, "H"), line(61, 35, 68, 35, "H"),
  line(20, 6, 24, 12, "H"), line(46, 58, 50, 64, "H"),
  line(6, 50, 12, 46, "H"), line(58, 24, 64, 20, "H"),
  line(50, 6, 46, 12, "H"), line(20, 64, 24, 58, "H"),
  line(64, 50, 58, 46, "H"), line(6, 20, 12, 24, "H"),
  // lit windows around the ring
  circ(35, 2, 1, "o"), circ(35, 68, 1, "o"),
  circ(2, 35, 1, "o"), circ(68, 35, 1, "o"),
  circ(11, 11, 1, "e"), circ(59, 11, 1, "e"),
  circ(11, 59, 1, "e"), circ(59, 59, 1, "e"),
  glow("e", { r: 2, strength: 0.4, bands: 3 }),
  glow("o", { r: 2, strength: 0.3, bands: 3 }))

// Freehold FactionBase — asymmetric mining-rig cluster, no full ring.
// Mining + agriculture economy: scrappy, bolted-together, utilitarian.
// Accent mix: green (c/C) + yellow (y).
sprite("freehold_base", { w: 80, h: 64, outline: "k" },
  // central hub module, off-center hexagon hull
  poly([10, 32, 18, 20, 34, 20, 42, 32, 34, 44, 18, 44], "h"),
  line(18, 20, 18, 44, "H"), line(34, 20, 34, 44, "H"),
  // mining drill arm, thick segmented spike jutting right from the hub
  poly([42, 24, 56, 28, 56, 36, 42, 40], "h"),
  line(48, 25, 48, 39, "H"), line(56, 28, 56, 36, "H"),
  poly([56, 28, 68, 32, 56, 36], "h"),
  circ(67, 32, 1, "y"),
  // ore silo cluster, upper right, each bolted on via its own visible strut
  line(34, 22, 50, 13, "H", 3),
  line(50, 13, 64, 16, "H", 3),
  ellipse(50, 11, 6, 5, "h"), ring(50, 11, 6, "H"),
  ellipse(65, 17, 5, 4, "h"), ring(65, 17, 5, "H"),
  line(50, 11, 42, 5, "H", 3),
  ellipse(42, 4, 4, 3, "h"), ring(42, 4, 4, "H"),
  rect(45, 8, 10, 2, "y"), rect(61, 15, 8, 2, "y"),
  // radiator fins, lower left, asymmetric angles
  line(16, 40, 4, 52, "H", 4), line(22, 43, 12, 58, "H", 4),
  // antenna stalk + dish
  line(25, 20, 25, 8, "h", 1), circ(25, 6, 2, "h"), ring(25, 6, 2, "H"),
  // hub windows and running lights, offset asymmetrically to avoid a
  // face-like look
  circ(18, 26, 1, "c"), circ(29, 32, 1, "c"), circ(20, 39, 1, "c"),
  circ(44, 30, 1, "y"),
  glow("c", { r: 2, strength: 0.35, bands: 3 }),
  glow("y", { r: 1, strength: 0.3, bands: 3 }))

// Player HomeBase — compact hub-and-spoke trade station. Trade hub +
// refinery economy: modest in scale/complexity next to the two faction
// bases, tidy rather than scrappy or imposing. Accent: blue (b/B).
sprite("home_base", { w: 48, h: 48, outline: "k" },
  // central core
  circ(24, 24, 10, "h"),
  ring(24, 24, 10, "H"),
  circ(24, 24, 5, "H"),
  ring(24, 24, 5, "b"),
  // four short docking spokes
  rect(22, 6, 4, 10, "h"), rect(22, 32, 4, 10, "h"),
  rect(6, 22, 10, 4, "h"), rect(32, 22, 10, 4, "h"),
  line(24, 8, 24, 16, "H"), line(24, 32, 24, 40, "H"),
  line(8, 24, 16, 24, "H"), line(32, 24, 40, 24, "H"),
  // docking pads at each spoke tip, with a lit window
  rect(19, 3, 10, 4, "h"), box(19, 3, 10, 4, "H"), circ(24, 4, 1, "b"),
  rect(19, 41, 10, 4, "h"), circ(24, 44, 1, "b"),
  rect(3, 19, 4, 10, "h"), circ(4, 24, 1, "b"),
  rect(41, 19, 4, 10, "h"), circ(44, 24, 1, "b"),
  // core windows
  circ(19, 20, 1, "b"), circ(29, 20, 1, "b"), circ(24, 29, 1, "b"),
  glow("b", { r: 2, strength: 0.4, bands: 3 }))
