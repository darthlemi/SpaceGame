// Ship sprites. Copy of palette.px.js's pal() block (pxl has no cross-file
// import). nose points +X (right), matching Ship.gd's rotation convention
// (rotation 0 = facing right, Vector2.RIGHT.rotated(rotation)).
//
// See docs/superpowers/specs/2026-10-31-pxl-art-pipeline-design.md for the
// pipeline, and carry_forward.md for the brainstorming history (style
// comparison, reference images) behind these specific designs.

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

sprite("corvette", { w: 42, h: 34, outline: "k" },
  // main dart hull, nose right
  poly([40, 17, 28, 10, 12, 11, 4, 14, 4, 20, 12, 23, 28, 24], "h"),
  poly([40, 17, 32, 13, 30, 17, 32, 21], "H"),
  // big sweeping delta wings — root near the nose, trailing edge near
  // the tail, tips swept far out past the hull silhouette
  poly([26, 11, 1, 1, 12, 13], "H"),
  poly([26, 23, 1, 33, 12, 21], "H"),
  line(12, 13, 26, 11, "C"), line(12, 21, 26, 23, "C"),
  circ(3, 2, 1, "e"), circ(3, 32, 1, "e"),
  // canopy — isometric block, elongated lengthwise along the hull
  isobox(0, 0, 0, 4, 1, 2, "c", { size: 4, at: [26, 11], top: "c", left: "H", right: "h" }),
  // nose light
  circ(39, 17, 1, "e"),
  // twin engine nacelles
  circ(5, 13, 2, "e"), circ(5, 13, 1, "E"),
  circ(5, 21, 2, "e"), circ(5, 21, 1, "E"),
  // hull pinstripe
  line(12, 11, 28, 11, "C"), line(12, 23, 28, 23, "C"),
  glow("c", { r: 2, strength: 0.4, bands: 3 }),
  glow("e", { r: 3, strength: 0.5, bands: 3 }))

sprite("freighter", { w: 64, h: 40, outline: "k" },
  // central spine
  rect(10, 14, 42, 12, "h"),
  rect(10, 14, 42, 2, "H"),
  rect(10, 24, 42, 2, "H"),
  // nose / command module
  poly([62, 20, 52, 14, 52, 26], "h"),
  rect(53, 17, 6, 6, "c"),
  circ(60, 20, 1, "e"),
  // top cargo pod — isometric block, elongated lengthwise, bolted on
  isobox(0, 0, 0, 6, 1, 2, "h", { size: 3, at: [18, 11], top: "h", left: "H", right: "H" }),
  // bottom cargo pod (different size/offset, kept asymmetric)
  isobox(0, 0, 0, 4, 1, 2, "h", { size: 3, at: [23, 27], top: "h", left: "H", right: "H" }),
  // engine block at tail
  rect(2, 10, 10, 20, "H"),
  rect(2, 10, 10, 2, "h"),
  circ(4, 16, 2, "e"), circ(4, 16, 1, "E"),
  circ(4, 24, 2, "e"), circ(4, 24, 1, "E"),
  // radiator fins
  rect(9, 7, 2, 5, "k"), rect(9, 28, 2, 5, "k"),
  glow("c", { r: 2, strength: 0.35, bands: 3 }),
  glow("e", { r: 3, strength: 0.45, bands: 3 }))

// Modular truss freighter skins, from the "Mule Class Freighter" reference:
// a slim spine with a cockpit module up front, and a swappable mid-section.
// Not wired into any scene yet — held for a future ship-customization
// feature (player picks a cargo-vs-fuel-hauler skin). See carry_forward.md.

function trussBase() {
  return [
    rect(4, 19, 88, 6, "h"),
    vline(16, 17, 2, "H"), vline(16, 25, 2, "H"),
    vline(76, 17, 2, "H"), vline(76, 25, 2, "H"),
    rect(84, 16, 12, 14, "H"),
    rect(86, 18, 8, 6, "c"),
    line(90, 16, 90, 10, "k", 1),
    circ(90, 9, 1, "e"),
    circ(4, 22, 2, "e"), circ(4, 22, 1, "E"),
  ]
}

sprite("freighter_fuel", { w: 100, h: 44, outline: "k" },
  ...trussBase(),
  // 2x2 cluster of round fuel tanks, clipped onto the spine
  ellipse(40, 12, 9, 6, "H"), ellipse(60, 12, 9, 6, "H"),
  ellipse(40, 32, 9, 6, "H"), ellipse(60, 32, 9, 6, "H"),
  // orange accent band around each tank
  rect(39, 6, 2, 12, "e"), rect(59, 6, 2, 12, "e"),
  rect(39, 26, 2, 12, "e"), rect(59, 26, 2, 12, "e"),
  glow("c", { r: 2, strength: 0.35, bands: 3 }),
  glow("e", { r: 1, strength: 0.3, bands: 3 }))

sprite("freighter_cargo", { w: 100, h: 44, outline: "k" },
  ...trussBase(),
  // 2x2 cluster of square cargo containers, clipped onto the spine
  rect(31, 6, 18, 12, "H"), rect(51, 6, 18, 12, "H"),
  rect(31, 26, 18, 12, "H"), rect(51, 26, 18, 12, "H"),
  // hazard-marking accent on each container
  rect(37, 9, 6, 6, "e"), rect(57, 9, 6, 6, "e"),
  rect(37, 29, 6, 6, "e"), rect(57, 29, 6, 6, "e"),
  glow("c", { r: 2, strength: 0.35, bands: 3 }),
  glow("e", { r: 1, strength: 0.3, bands: 3 }))

// Capital ship — Star Wars contour (Nebula-class dagger hull + Venator-class
// inspired twin bridge towers, translated to top-down). Bow is a plain
// taper (a forked version was tried and rejected — read as a fish mouth).
sprite("capital", { w: 128, h: 64, outline: "k" },
  // long dagger hull, pointed bow right, flat stern left
  poly([124, 32, 95, 18, 40, 14, 15, 20, 6, 26, 6, 38, 15, 44, 40, 50, 95, 46], "h"),
  // surface panel greebling — short ticks, not full-height lines, so
  // they read as plating rather than cutting false notches in the hull
  vline(30, 16, 4, "H"), vline(50, 14, 4, "H"), vline(70, 16, 4, "H"), vline(85, 18, 4, "H"),
  vline(30, 44, 4, "H"), vline(50, 46, 4, "H"), vline(70, 44, 4, "H"), vline(85, 42, 4, "H"),
  // bold single centerline stripe, the signature marking
  line(10, 32, 118, 32, "e", 2),
  // twin isometric towers mounted on the deck, symmetric above/below
  // the spine, aft third — elongated lengthwise, not square
  isobox(0, 0, 0, 4, 1, 2, "c", { size: 5, at: [28, 19], top: "c", left: "H", right: "h" }),
  isobox(0, 0, 0, 4, 1, 2, "c", { size: 5, at: [28, 45], top: "c", left: "H", right: "h" }),
  // engine block at stern, three thrusters
  rect(2, 20, 8, 24, "H"),
  circ(4, 25, 1, "e"), circ(4, 32, 1, "e"), circ(4, 39, 1, "e"),
  glow("c", { r: 2, strength: 0.35, bands: 3 }),
  glow("e", { r: 2, strength: 0.4, bands: 3 }))
