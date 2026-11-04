"""Procedural kitbash freighter, rendered top-down with Cycles.

A long cargo bay: shipping containers racked in columns either side of a plated keel, a
command module at the bow and a wider engineering block at the stern, framed by a neon
trim line. Same plate skin, lighting and mounts sidecar as the corvette (shared code is
imported from kitbash_corvette.py).
The approved design (2026-11-03) is --cargo muted, seed 1 (both the defaults).

Run headless in Blender 5.2; see art\\README.md for the command.

Nose points +X (right) to match Ship.gd's rotation convention.
"""
import argparse
import logging
import os
import random
import sys
import time

import bmesh
import bpy
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kitbash_corvette as kb  # noqa: E402  (needs the sys.path entry above)

LOG = logging.getLogger("kitbash")
MOUNT_RADIUS = 0.3  # light turret attach plate, Blender units

# Container paint. "muted": weathered shipping colours; "mono": gunmetal shades only.
CARGO_PALETTES = {
    "mono": ("#4a4e54", "#565a60", "#3f4247", "#60646a"),
    "muted": ("#6e3a2e", "#2f5a60", "#7d6431", "#3c4866", "#55595e", "#5e3040"),
}

BAY_X0, BAY_X1 = -4.2, 4.3  # cargo bay extent along the keel
BAY_HALF = 1.95             # cargo bay half-width
COLUMNS = 4                 # container columns per side
CONTAINER_LEN = 1.55        # a 40ft box; 20ft boxes are half this, in pairs
RIB_PITCH = 0.11            # roof corrugation period; finer than this aliases away
RIB_DEPTH = 0.012


def facet_loft(corners, step=0.2):
    """Loft through straight-edged corners [(x, half_width, height)]: dense evenly spaced
    stations keep the PCHIP sides flat between corners (faceted, not rounded)."""
    st = []
    for (xa, wa, ha), (xb, wb, hb) in zip(corners, corners[1:]):
        n = max(1, int((xb - xa) / step))
        st += [(xa + (xb - xa) * i / n, wa + (wb - wa) * i / n, ha + (hb - ha) * i / n, 0.0)
               for i in range(n)]
    xb, wb, hb = corners[-1]
    st.append((xb, wb, hb, 0.0))
    return kb.Loft(st, p=1.6, q=1.4)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    p.add_argument("--cargo", choices=sorted(CARGO_PALETTES), default="muted")
    p.add_argument("--seed", type=int, default=1, help="1 = approved freighter design")
    p.add_argument("--res", type=int, default=768, help="render width in px")
    p.add_argument("--samples", type=int, default=64)
    p.add_argument("--preview", action="store_true", help="add space backdrop + engine flames")
    p.add_argument("--verbose", action="store_true")
    return p.parse_args(argv)


def _cube(bm, cx, cy, z0, sx, sy, sz, mat_index):
    """Add an axis-aligned box to an existing bmesh, tagged with a material slot."""
    verts = bmesh.ops.create_cube(bm, size=1.0)["verts"]
    bmesh.ops.transform(bm, verts=verts, matrix=Matrix.Translation((cx, cy, z0 + sz / 2.0))
                        @ Matrix.Diagonal((sx, sy, sz, 1.0)))
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mat_index


def container(kit, cx, cy, z0, length, width, height, paint, dark):
    """Shipping container as seen from above: ribbed roof (flat-shaded triangle wave, so
    the ribs read as light/dark bands), raised top rails and end frames in the paint, and
    dark corner castings. One mesh per container keeps the object count down."""
    bm = bmesh.new()
    top = z0 + height
    rail, frame = 0.028, 0.045
    _cube(bm, cx, cy, z0, length, width, height, 0)
    for s in (1, -1):  # top side rails along the long edges, and the two end frames
        _cube(bm, cx, cy + s * (width - rail) / 2.0, top, length, rail, 0.02, 0)
        _cube(bm, cx + s * (length - frame) / 2.0, cy, top, frame, width, 0.025, 0)
        for t in (1, -1):  # corner castings
            _cube(bm, cx + s * (length / 2.0 - 0.03), cy + t * (width / 2.0 - 0.03), top,
                  0.06, 0.06, 0.035, 1)
    x0, x1 = cx - length / 2.0 + frame, cx + length / 2.0 - frame
    y0, y1 = cy - width / 2.0 + rail, cy + width / 2.0 - rail
    n = max(2, int((x1 - x0) / RIB_PITCH) * 2)
    row = []
    for i in range(n + 1):
        x = x0 + (x1 - x0) * i / n
        z = top + 0.004 + (RIB_DEPTH if i % 2 else 0.0)
        row.append((bm.verts.new((x, y0, z)), bm.verts.new((x, y1, z))))
    for (a0, a1), (b0, b1) in zip(row, row[1:]):
        bm.faces.new((a0, b0, b1, a1))
    ob = kit.link(bm, paint)
    ob.data.materials.append(dark)
    return ob


def build_freighter(kit, rng, mats, cargo, preview):
    m = mats
    tones = (m["hull"], m["hull"], m["hull2"], m["hull3"])

    # Bow command module and stern engineering block: low faceted blocks (straight runs,
    # chamfered corners, ridged crown) - not domes. The stern is wider than the bay.
    bow = facet_loft([(BAY_X1 - 0.3, 1.8, 0.4), (BAY_X1 + 1.1, 2.05, 0.55),
                      (BAY_X1 + 1.8, 1.55, 0.5), (BAY_X1 + 2.3, 0.65, 0.3)])
    stern = facet_loft([(BAY_X0 - 2.3, 1.7, 0.4), (BAY_X0 - 1.95, 2.4, 0.6),
                        (BAY_X0 - 0.8, 2.4, 0.6), (BAY_X0 - 0.2, 1.9, 0.5),
                        (BAY_X0 + 0.3, 1.8, 0.4)])
    keel = kb.Loft([(BAY_X0 - 0.2, 0.42, 0.5, 0.0), (BAY_X1 + 0.2, 0.42, 0.5, 0.0)],
                   p=4.0, q=1.2)
    for lf in (bow, stern, keel):
        kit.loft_body(lf, m["hull3"])

    def skin(loft, x0, x1, t0, t1, mirror, **kw):
        w = loft.params((x0 + x1) / 2.0)[0]
        gx, gt = 0.012, 0.012 / max(w, 0.1)
        cells = kb.organic_partition(rng, x0, x1, t0, t1, (t1 - t0) * w * 1.2, **kw)
        for quad in cells:
            q = kb.shrink_quad(quad, gx, gt)
            mat = rng.choice(tones)
            thick = rng.uniform(0.02, 0.07) if rng.random() > 0.15 else 0.1
            kit.loft_quad(loft, q, 0.002, thick, mat)
            if mirror is not None:
                kit.loft_quad(mirror, [(x, -t) for x, t in q], 0.002, thick, mat)
        return len(cells)

    plates = 0
    for t0, t1 in ((0.0, 0.45), (0.45, 0.99)):
        plates += skin(bow, BAY_X1 - 0.3, BAY_X1 + 2.25, t0, t1, bow, strip=(0.5, 0.9))
        plates += skin(stern, BAY_X0 - 2.3, BAY_X0 + 0.3, t0, t1, stern, strip=(0.5, 0.9))
    plates += skin(keel, BAY_X0 - 0.2, BAY_X1 + 0.2, 0.0, 0.99, keel, strip=(0.8, 1.3))

    # Cargo bay floor and the outer gantry rails the containers lock into.
    kit.box((BAY_X0 + BAY_X1) / 2.0, 0.0, 0.0, BAY_X1 - BAY_X0, BAY_HALF * 2.0, 0.08,
            m["dark"])
    for s in (1, -1):
        kit.box((BAY_X0 + BAY_X1) / 2.0, s * (BAY_HALF + 0.06), 0.0, BAY_X1 - BAY_X0 + 0.2,
                0.14, 0.55, m["hull"])

    # Containers: columns either side of the keel, rows split by cross-beams. Slots hold
    # one 40ft box or a pair of 20ft boxes; a few are left empty so the racks don't read as
    # a solid grid.
    col_w = (BAY_HALF - 0.45) / COLUMNS
    rows = int((BAY_X1 - BAY_X0) / (CONTAINER_LEN + 0.12))
    row_pitch = (BAY_X1 - BAY_X0) / rows
    paints = [kb.metal_mat("cargo%d" % i, c, metal=0.35, rough=0.55, grime=0.75)
              for i, c in enumerate(CARGO_PALETTES[cargo])]
    # Own stream for paint: choice() draws a palette-size-dependent amount of randomness,
    # which would otherwise make the layout differ between --cargo palettes.
    paint_rng = random.Random(rng.random())
    containers = 0
    for r in range(rows):
        cx = BAY_X0 + row_pitch * (r + 0.5)
        if r:
            kit.box(BAY_X0 + row_pitch * r, 0.0, 0.08, 0.1, BAY_HALF * 2.0, 0.08, m["hull2"])
        for s in (1, -1):
            for c in range(COLUMNS):
                if rng.random() < 0.08:
                    continue
                cy = s * (0.45 + col_w * (c + 0.5))
                h = 0.38 if rng.random() > 0.3 else 0.3
                length, width = row_pitch - 0.12, col_w - 0.05
                if rng.random() < 0.35:
                    half = (length - 0.05) / 2.0
                    for k in (-1, 1):
                        container(kit, cx + k * (half + 0.05) / 2.0, cy, 0.08, half, width, h,
                                  paint_rng.choice(paints), m["dark"])
                    containers += 2
                else:
                    container(kit, cx, cy, 0.08, length, width, h, paint_rng.choice(paints),
                              m["dark"])
                    containers += 1

    # Neon trim framing the bay: along both rails and across the bow and stern bulkheads.
    for s in (1, -1):
        kit.box((BAY_X0 + BAY_X1) / 2.0, s * (BAY_HALF + 0.06), 0.56, BAY_X1 - BAY_X0, 0.03,
                0.02, m["cyan"], bevel=0.0)
    for x in (BAY_X0 - 0.05, BAY_X1 + 0.05):
        kit.box(x, 0.0, 0.56, 0.03, BAY_HALF * 2.1, 0.02, m["cyan"], bevel=0.0)

    def top_z(loft, x, y=0.0):
        w, _, yc = loft.params(x)
        return loft.point(x, (y - yc) / max(w, 1e-3)).z + 0.12

    # Bridge with lit windows on the bow module.
    bx = BAY_X1 + 1.2
    bz = top_z(bow, bx)
    kit.box(bx, 0.0, bz - 0.12, 0.8, 1.1, 0.25, m["hull"], bevel=0.05)
    kit.box(bx + 0.42, 0.0, bz + 0.02, 0.04, 0.8, 0.08, m["yellow"], bevel=0.0)
    for s in (1, -1):  # nav lights on the stern block's outer corners
        p = stern.point(BAY_X0 - 1.3, 0.93 * s)
        kit.box(p.x, p.y, p.z, 0.14, 0.1, 0.05, m["red"], bevel=0.0)

    # Engines across the stern.
    for y in (-1.35, -0.45, 0.45, 1.35):
        x = BAY_X0 - 2.3
        kit.cyl(x - 0.55, y, 0.3, 0.7, 0.3, m["bright"], r2=0.36)
        kit.cyl(x - 0.57, y, 0.3, 0.03, 0.24, m["engine"], bevel=0.0)
        if preview:
            kit.cyl(x - 3.0, y, 0.3, 2.45, 0.0, m["flame"], r2=0.22, bevel=0.0)

    # Light turret attach points: on the bow module and the stern block, on the centreline.
    mounts = [("dorsal_fore", BAY_X1 + 0.35, 0.0, top_z(bow, BAY_X1 + 0.35)),
              ("dorsal_aft", BAY_X0 - 1.2, 0.0, top_z(stern, BAY_X0 - 1.2))]
    for _, tx, ty, tz in mounts:
        kit.cyl(tx, ty, tz - 0.08, 0.14, MOUNT_RADIUS, m["dark"], axis="Z", bevel=0.02)

    # Sparse hardware cluster on the stern block, mirrored.
    for s in (1, -1):
        tx, ty = BAY_X0 - 1.0, s * 1.5
        tz = top_z(stern, tx, ty) - 0.1
        for i in range(4):
            kit.box(tx - 0.15 + i * 0.1, ty, tz, 0.04, 0.3, 0.04, m["bright"], bevel=0.0)
    return plates, containers, mounts


def main():
    args = parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="[kitbash] %(message)s")
    t0 = time.perf_counter()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = kb.setup_scene(args)
    mats = {
        "hull": kb.metal_mat("hull", "#62666b"),
        "hull2": kb.metal_mat("hull2", "#5c6065"),
        "hull3": kb.metal_mat("hull3", "#565a5f"),
        "dark": kb.metal_mat("dark", "#34353a", rough=0.5),
        "bright": kb.metal_mat("bright", "#b8bcc4", metal=0.9, rough=0.22, grime=0.9),
        "cyan": kb.emit_mat("cyan", "#3ff2ff", 6.0),
        "red": kb.emit_mat("red", "#ff3b3b", 14.0),
        "yellow": kb.emit_mat("yellow", "#ffd23a", 10.0),
        "engine": kb.emit_mat("engine", "#9ff8ff", 25.0),
        "flame": kb.flame_mat("flame", "#ff9a3c", 14.0),
    }
    kit = kb.Kit()
    plates, containers, mounts = build_freighter(kit, random.Random(args.seed), mats,
                                                 args.cargo, args.preview)

    # Frame the long hull: bow tip to engine nozzles (plus flames in preview).
    aft = 3.0 if args.preview else 0.7
    x_lo, x_hi = BAY_X0 - 2.3 - aft, BAY_X1 + 2.3
    span_x = x_hi - x_lo + 0.8
    span_y = 2.0 * 2.4 + 0.8
    scene.render.resolution_y = int(args.res * span_y / span_x)
    scene.camera.data.ortho_scale = span_x
    scene.camera.location = ((x_lo + x_hi) / 2.0, 0.0, 30.0)
    if args.preview:
        bd = bpy.data.objects.new("backdrop", bpy.data.meshes.new("backdrop"))
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30.0)
        bmesh.ops.translate(bm, vec=(0.0, 0.0, -3.0), verts=bm.verts)
        bm.to_mesh(bd.data)
        bm.free()
        bd.data.materials.append(kb.backdrop_mat())
        scene.collection.objects.link(bd)
    t1 = time.perf_counter()
    LOG.debug("built %d objects (%d plates, %d containers) in %.2fs", kit.count, plates,
              containers, t1 - t0)
    scene.render.filepath = args.out
    bpy.ops.render.render(write_still=True)
    LOG.info("wrote %s (render %.1fs)", args.out, time.perf_counter() - t1)
    kb.write_mounts(scene, mounts, args.out, os.path.splitext(args.out)[0] + ".mounts.json",
                    args.seed, ship="freighter", radius=MOUNT_RADIUS)


if __name__ == "__main__":
    main()
