// Commodity icons for Trade/Loot panel rows. Detailed style (shadow +
// highlight + glow), locked per user feedback: Food shows actual
// bottle/can goods contained in the crate (not wheat sprouting above
// it), Fuel's main color is orange (not blue), Luxury Goods is a
// faceted diamond silhouette.
//
// Per-commodity accent: Ore=o, Food=c, Fuel=o, Hull Parts=y, Weapons=e,
// Luxury Goods=p.
//
// See docs/superpowers/specs/2026-11-02-ui-art-design.md.

pal({
  k: "#060607",
  h: "#5a584f",
  H: "#38362f",
  c: "#4dff8a",
  C: "#167a3f",
  e: "#ff3b3b",
  E: "#8a1414",
  b: "#3f9fff",
  B: "#1a4e8a",
  y: "#d1a52c",
  o: "#c05a1f",
  p: "#b23d6e",
})

sprite("ore", { w: 16, h: 16, outline: "k" },
  poly([3, 10, 2, 6, 6, 2, 11, 3, 14, 7, 12, 12, 7, 14], "h"),
  poly([3, 10, 6, 2, 11, 3, 10, 6, 6, 8], "H"),
  poly([6, 5, 9, 4, 11, 7, 8, 10, 5, 8], "o"),
  line(7, 6, 9, 5, "y", 1),
  glow("o", { r: 1, strength: 0.3, bands: 2 }))

// Crate of goods: a bottle and a can sitting inside the crate's open top,
// not poking out above it.
sprite("food", { w: 16, h: 16, outline: "k" },
  rect(2, 7, 12, 7, "h"),
  rect(2, 11, 12, 3, "H"),
  rect(5, 4, 3, 6, "h"), rect(5, 3, 3, 1, "c"),
  circ(11, 7, 2, "h"), circ(11, 7, 2, "H"),
  line(2, 7, 2, 2, "h", 1), line(14, 7, 14, 2, "h", 1),
  glow("c", { r: 1, strength: 0.25, bands: 2 }))

// Canister, orange as the main color (not blue).
sprite("fuel", { w: 16, h: 16, outline: "k" },
  rect(4, 5, 8, 9, "o"),
  rect(4, 10, 8, 4, "E"),
  rect(6, 2, 4, 3, "h"),
  rect(4, 8, 8, 2, "H"),
  line(5, 5, 5, 7, "y", 1),
  glow("o", { r: 1, strength: 0.4, bands: 2 }))

sprite("hull_parts", { w: 16, h: 16, outline: "k" },
  rect(2, 4, 12, 8, "h"),
  rect(2, 4, 12, 3, "H"),
  circ(5, 7, 1, "y"), circ(11, 7, 1, "y"), circ(5, 9, 1, "y"), circ(11, 9, 1, "y"),
  line(2, 4, 14, 12, "H", 1))

// Placeholder — multiple weapon-type icons queued for a future pass.
sprite("weapons", { w: 16, h: 16, outline: "k" },
  poly([1, 9, 1, 7, 9, 7, 9, 5, 14, 5, 14, 9, 9, 9, 9, 11, 4, 11, 4, 9], "h"),
  poly([1, 9, 9, 9, 9, 11, 4, 11, 4, 9], "H"),
  circ(13, 7, 1, "e"),
  glow("e", { r: 1, strength: 0.4, bands: 2 }))

// Classic faceted brilliant-cut diamond silhouette.
sprite("luxury_goods", { w: 16, h: 16, outline: "k" },
  poly([5, 3, 11, 3, 15, 7, 8, 15, 1, 7], "p"),
  line(5, 3, 1, 7, "k", 1), line(11, 3, 15, 7, "k", 1),
  line(1, 7, 15, 7, "k", 1),
  line(5, 3, 8, 15, "k", 1), line(11, 3, 8, 15, "k", 1),
  line(6, 3, 9, 6, "y", 1),
  glow("p", { r: 1, strength: 0.35, bands: 2 }))
