"""Procedural kitbash capital ship, rendered top-down with Cycles.

A broad, low, faceted saucer whose front is split by an opening, with the bridge prow
sitting in it between two mandibles. Same gunmetal plate skin, neon accents and mounts
sidecar as the corvette (shared code is imported from kitbash_corvette.py).
The approved design (2026-11-03) is --hull slot (the default), seed 1 (the default).

Run headless in Blender 5.2; see art\\README.md for the command.

Nose points +X (right) to match Ship.gd's rotation convention.
"""
import argparse
import logging
import math
import os
import random
import sys
import time

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kitbash_corvette as kb  # noqa: E402  (needs the sys.path entry above)

LOG = logging.getLogger("kitbash")
MOUNT_RADIUS = 0.5  # capital weapon attach plate, Blender units

# Silhouette recipes. rx/ry: saucer half-length/half-width. notch: half-width of the front
# opening. notch_x: where the opening bottoms out on the body. prow: how far the bridge
# prow reaches into the opening past notch_x. "slot" is approved; the others are the
# rejected alternatives, kept for comparison.
HULLS = {
    "bay": {"rx": 6.4, "ry": 5.9, "notch": 1.7, "notch_x": 1.3, "prow": 2.2},
    "oval": {"rx": 6.8, "ry": 5.2, "notch": 1.3, "notch_x": 1.8, "prow": 2.4},
    "slot": {"rx": 6.4, "ry": 5.9, "notch": 0.95, "notch_x": 2.4, "prow": 1.3},
}


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    p.add_argument("--hull", choices=sorted(HULLS), default="slot")
    p.add_argument("--seed", type=int, default=1, help="1 = approved capital design")
    p.add_argument("--res", type=int, default=768, help="render width in px")
    p.add_argument("--samples", type=int, default=64)
    p.add_argument("--preview", action="store_true", help="add space backdrop + engine flames")
    p.add_argument("--verbose", action="store_true")
    return p.parse_args(argv)


# Faceted saucer outline, (x / rx, half_width / ry) from stern to bow: flat stern, chamfered
# shoulders, then a straight taper to the mandible tips. Straight runs read as angled plate
# edges instead of a balloon curve.
OUTLINE = [(-1.0, 0.42), (-0.74, 0.86), (-0.3, 1.0), (0.25, 0.92), (1.0, 0.12)]


def lerp_table(table, x):
    """Piecewise-linear lookup in a sorted [(x, value)] table, clamped at the ends."""
    if x <= table[0][0]:
        return table[0][1]
    for (xa, va), (xb, vb) in zip(table, table[1:]):
        if x <= xb:
            return va + (vb - va) * (x - xa) / (xb - xa)
    return table[-1][1]


def rim(x, rx, ry):
    """Saucer outline half-width at x (0 past the bow)."""
    if x > rx:
        return 0.0
    return ry * lerp_table(OUTLINE, x / rx)


def stations(x0, x1, rx, step=0.5):
    """Evenly spaced X samples plus the outline corners, so the PCHIP loft runs straight
    along each facet and only rounds off right at the corners."""
    xs = {x0, x1}
    xs.update(f * rx for f, _ in OUTLINE if x0 < f * rx < x1)
    n = max(1, int((x1 - x0) / step))
    xs.update(x0 + (x1 - x0) * i / n for i in range(n + 1))
    return sorted(xs)


def build_capital(kit, rng, mats, spec, preview):
    m = mats
    tones = (m["hull"], m["hull"], m["hull2"], m["hull3"])
    rx, ry, notch, nx, prow = (spec[k] for k in ("rx", "ry", "notch", "notch_x", "prow"))

    # Body: low, ridged saucer (p < 2 gives a crown ridge instead of a dome) following the
    # outline until the mandibles take over the outer edge, then narrowing to the bridge prow.
    body_h = [(-rx, 0.4), (-rx * 0.6, 0.6), (nx - 0.6, 0.55), (nx, 0.45), (nx + prow, 0.16)]
    body_st = [(x, rim(x, rx, ry), lerp_table(body_h, x), 0.0)
               for x in stations(-rx, -0.4, rx)]
    body_st.append((nx - 0.6, notch + 0.9, lerp_table(body_h, nx - 0.6), 0.0))
    # Straight-sided prow wedge: evenly spaced stations keep the PCHIP flanks flat.
    for i in range(5):
        f = i / 4.0
        x = nx + prow * f
        body_st.append((x, notch * 0.85 + (0.05 - notch * 0.85) * f, lerp_table(body_h, x),
                        0.0))
    body = kb.Loft(body_st, p=1.5, q=1.5)

    # Mandibles: outer edge on the outline, inner edge on the opening, rising out of the
    # body's shoulder and tapering to points where outline and opening meet.
    lo, hi = 0.0, rx
    for _ in range(40):  # bisect for the tip: where the outline narrows to the opening
        mid = (lo + hi) / 2.0
        lo, hi = (mid, hi) if rim(mid, rx, ry) > notch else (lo, mid)
    tip = lo - 0.05
    mand_h = [(-3.2, 0.15), (-1.8, 0.35), (0.0, 0.5), (nx, 0.5), (tip - 0.6, 0.26), (tip, 0.12)]
    mands = []
    for s in (1, -1):
        st = []
        for x in stations(-3.2, tip, rx, step=0.6):
            out_y = rim(x, rx, ry) - 0.02
            in_y = notch if x >= nx - 0.6 else notch + 0.6 * (nx - 0.6 - x) / (nx + 2.6)
            st.append((x, max(0.03, (out_y - in_y) / 2.0), lerp_table(mand_h, x),
                       s * (out_y + in_y) / 2.0))
        mands.append(kb.Loft(st, p=1.6, q=1.3, z0=0.1))

    # Dorsal deck: a low flat-topped plate stack on the crown ridge (p = 4 flattens the top,
    # q > 1 keeps chined edges), ending in the bridge.
    bridge_x = nx + prow * 0.25
    dorsal = kb.Loft([(-rx * 0.8, 0.15, 0.08, 0.0), (-rx * 0.6, 0.75, 0.18, 0.0),
                      (bridge_x - 1.2, 0.7, 0.18, 0.0), (bridge_x - 0.2, 0.4, 0.14, 0.0),
                      (bridge_x + 0.15, 0.05, 0.05, 0.0)], p=4.0, q=1.2, z0=0.47)

    kit.loft_body(body, m["hull3"], step=0.1, tcount=40)
    kit.loft_body(dorsal, m["hull3"])
    for md in mands:
        kit.loft_body(md, m["hull3"])

    def skin(loft, x0, x1, t0, t1, mirror, **kw):
        w = loft.params((x0 + x1) / 2.0)[0]
        gx, gt = 0.014, 0.014 / max(w, 0.1)
        cells = kb.organic_partition(rng, x0, x1, t0, t1, (t1 - t0) * w * 1.2, **kw)
        for quad in cells:
            q = kb.shrink_quad(quad, gx, gt)
            mat = rng.choice(tones)
            thick = rng.uniform(0.025, 0.08) if rng.random() > 0.15 else 0.12
            kit.loft_quad(loft, q, 0.002, thick, mat)
            if mirror is not None:
                kit.loft_quad(mirror, [(x, -t) for x, t in q], 0.002, thick, mat)
        return len(cells)

    big = {"strip": (0.7, 1.3)}
    plates = 0
    # The saucer is wide, so its skin goes on in bands across T to keep plates chunky.
    for t0, t1 in ((0.0, 0.3), (0.3, 0.62), (0.62, 0.99)):
        plates += skin(body, -rx + 0.05, nx, t0, t1, body, **big)
    plates += skin(body, nx, nx + prow - 0.1, 0.0, 0.99, body)
    plates += skin(dorsal, -rx * 0.8, bridge_x, 0.0, 0.99, dorsal, strip=(0.9, 1.4))
    for t0, t1 in ((-0.99, -0.1), (-0.1, 0.99)):
        plates += skin(mands[0], -3.2, tip - 0.05, t0, t1, mands[1], **big)

    def top_z(loft, x, y):
        w, _, yc = loft.params(x)
        return loft.point(x, (y - yc) / max(w, 1e-3)).z + 0.06

    def surface_z(x, y):
        """Highest skin over (x, y) across every hull loft, clear of the thickest plates."""
        z = 0.0
        for lf in (body, dorsal) + tuple(mands):
            w, _, yc = lf.params(x)
            if lf.x0 <= x <= lf.x1 and abs(y - yc) < w:
                z = max(z, top_z(lf, x, y))
        return z + 0.08

    # Neon: a trim line around each mandible's inner edge and along the body shoulders.
    for s, md in zip((1, -1), mands):
        t = -0.55 * s
        kit.loft_patch(md, 0.2, tip - 1.0, t - 0.012, t + 0.012, 0.13, 0.025, m["cyan"],
                       bevel=0.0)
    for t in (0.42, -0.42):
        kit.loft_patch(body, -rx * 0.7, -0.6, t - 0.01, t + 0.01, 0.13, 0.025, m["cyan"],
                       bevel=0.0)

    # Bridge on the prow, looking out through the opening.
    bz = top_z(body, bridge_x, 0.0)
    kit.box(bridge_x - 0.2, 0.0, bz - 0.2, 1.3, 1.1, 0.4, m["hull"], bevel=0.06)
    kit.box(bridge_x + 0.1, 0.0, bz + 0.1, 0.7, 0.75, 0.22, m["hull2"], bevel=0.05)
    kit.box(bridge_x + 0.47, 0.0, bz + 0.17, 0.05, 0.6, 0.1, m["yellow"], bevel=0.0)
    for s in (1, -1):  # nav lights on the mandible tips
        p = mands[0 if s > 0 else 1].point(tip - 0.35, 0.0)
        kit.box(p.x, p.y, p.z, 0.14, 0.1, 0.05, m["red"], bevel=0.0)

    # Engine block across the rounded stern.
    for k in (-2, -1, 0, 1, 2):  # spread across the flat stern
        y = k * 0.19 * ry
        x = -rx + 0.25
        kit.cyl(x - 0.75, y, 0.3, 0.85, 0.42, m["bright"], r2=0.5)
        kit.cyl(x - 0.77, y, 0.3, 0.03, 0.32, m["engine"], bevel=0.0)
        if preview:
            kit.cyl(x - 3.6, y, 0.3, 2.85, 0.0, m["flame"], r2=0.3, bevel=0.0)

    # Six weapon attach points: mandibles (fore), broadside (mid), aft quarters.
    mounts = []
    for side, s, md in (("port", 1, mands[0]), ("starboard", -1, mands[1])):
        for name, x, y in (("fore", nx + 0.3, md.params(nx + 0.3)[2]),
                           ("mid", -1.4, s * rim(-1.4, rx, ry) * 0.72),
                           ("aft", -3.6, s * rim(-3.6, rx, ry) * 0.55)):
            mounts.append(("%s_%s" % (side, name), x, y, surface_z(x, y)))
    for _, tx, ty, tz in mounts:
        kit.cyl(tx, ty, tz - 0.08, 0.16, MOUNT_RADIUS, m["dark"], axis="Z", bevel=0.025)

    # Sparse hardware clusters on the saucer crown, mirrored.
    for tx in rng.sample([-4.8, -4.2, -2.6, -2.2, 0.0], 3):
        kind = rng.random()
        for s in (1, -1):
            ty = s * 1.6
            tz = top_z(body, tx, ty)
            if kind < 0.5:
                kit.box(tx, ty, tz - 0.04, 0.55, 0.42, 0.08, m["dark"])
                for i in range(5):
                    kit.box(tx - 0.2 + i * 0.1, ty, tz + 0.04, 0.04, 0.34, 0.03, m["bright"],
                            bevel=0.0)
            else:
                for i in (-1, 1):
                    kit.cyl(tx + i * 0.16, ty, tz - 0.04, 0.2, 0.14, m["dark"], axis="Z")
    return plates, mounts, rx, ry


def main():
    args = parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="[kitbash] %(message)s")
    spec = HULLS[args.hull]
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
    plates, mounts, rx, ry = build_capital(kit, random.Random(args.seed), mats, spec,
                                           args.preview)

    # Frame the saucer: square-ish image, stern engines (and flames in preview) included.
    margin = 1.0
    span_x = 2.0 * rx + (3.5 if args.preview else 1.4) + margin
    span_y = 2.0 * ry + margin
    scene.render.resolution_y = int(args.res * span_y / span_x)
    scene.camera.data.ortho_scale = span_x
    scene.camera.location = (-(3.5 if args.preview else 1.4) / 2.0, 0.0, 30.0)
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
    LOG.debug("built %d objects (%d plates) in %.2fs", kit.count, plates, t1 - t0)
    scene.render.filepath = args.out
    bpy.ops.render.render(write_still=True)
    LOG.info("wrote %s (render %.1fs)", args.out, time.perf_counter() - t1)
    kb.write_mounts(scene, mounts, args.out, os.path.splitext(args.out)[0] + ".mounts.json",
                    args.seed, ship="capital", radius=MOUNT_RADIUS)


if __name__ == "__main__":
    main()
