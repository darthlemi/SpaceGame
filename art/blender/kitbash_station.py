"""Procedural kitbash space stations, rendered top-down with Cycles.

Several archetypes (--type), each reshuffled by --seed, built from low, flat, faceted blocks
skinned with gunmetal plates (same art direction as the ships). --accent picks the neon trim
colour so one archetype can serve any faction. Shared materials and the plate partitioner
come from kitbash_corvette.py, so keep both files together.

Run headless in Blender 5.2; see art\\README.md for the command. Without --preview the PNG
has a transparent background; --preview adds a space backdrop. The image is framed to the
station's footprint, so its aspect follows the station's shape.
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
ACCENTS = {
    "blue": "#3f9fff",
    "cyan": "#3ff2ff",
    "green": "#4bff7a",
    "orange": "#ff8a3a",
    "red": "#ff3b3b",
    "violet": "#a46bff",
    "yellow": "#ffd23a",
}
TAU = 2.0 * math.pi


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    p.add_argument("--type", choices=sorted(BUILDERS), default="ring")
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--accent", choices=sorted(ACCENTS), default="cyan")
    p.add_argument("--res", type=int, default=768, help="longer image side in px")
    p.add_argument("--samples", type=int, default=64)
    p.add_argument("--preview", action="store_true", help="add a space backdrop")
    p.add_argument("--verbose", action="store_true")
    return p.parse_args(argv)


# ---------------------------------------------------------------- 2D helpers

def polar(r, a, c=(0.0, 0.0)):
    return (c[0] + r * math.cos(a), c[1] + r * math.sin(a))


def area2(pts):
    return 0.5 * sum(pts[i - 1][0] * p[1] - p[0] * pts[i - 1][1] for i, p in enumerate(pts))


def ccw(pts):
    return list(pts) if area2(pts) > 0.0 else list(pts)[::-1]


def offset_poly(pts, d):
    """Inset a convex polygon by d: each edge moves inward and neighbours are re-intersected,
    so seams and bevels stay an even width (scaling toward the centroid would not)."""
    pts = ccw(pts)
    lines = []
    for i, (x0, y0) in enumerate(pts):
        x1, y1 = pts[(i + 1) % len(pts)]
        ln = math.hypot(x1 - x0, y1 - y0) or 1e-9
        ux, uy = (x1 - x0) / ln, (y1 - y0) / ln
        lines.append(((x0 - uy * d, y0 + ux * d), (ux, uy)))
    out = []
    for i in range(len(lines)):
        (p, u), (q, v) = lines[i - 1], lines[i]
        den = u[0] * v[1] - u[1] * v[0]
        if abs(den) < 1e-9:
            out.append(q)
            continue
        s = ((q[0] - p[0]) * v[1] - (q[1] - p[1]) * v[0]) / den
        out.append((p[0] + s * u[0], p[1] + s * u[1]))
    return out


def safe_inset(pts, d):
    """offset_poly, backing off when d would collapse or flip a small polygon."""
    base = area2(ccw(pts))
    for _ in range(5):
        out = offset_poly(pts, d)
        if area2(out) > 0.25 * base:
            return out
        d *= 0.5
    return ccw(pts)


def bilerp(q, u, v):
    a, b, c, d = q
    lo = (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u)
    hi = (d[0] + (c[0] - d[0]) * u, d[1] + (c[1] - d[1]) * u)
    return (lo[0] + (hi[0] - lo[0]) * v, lo[1] + (hi[1] - lo[1]) * v)


def beam_quad(p, q, w):
    """Quad of width w along p->q; first edge runs along the beam."""
    ln = math.hypot(q[0] - p[0], q[1] - p[1]) or 1e-9
    nx, ny = -(q[1] - p[1]) / ln * w / 2.0, (q[0] - p[0]) / ln * w / 2.0
    return [(p[0] - nx, p[1] - ny), (q[0] - nx, q[1] - ny), (q[0] + nx, q[1] + ny),
            (p[0] + nx, p[1] + ny)]


def chamfer_rect(c, length, width, ch, ang):
    """Rectangle with 45-degree corner cuts, long axis at ang. Point order is fixed (see
    Station.module), starting at the +X end's lower corner, counter-clockwise."""
    hl, hw = length / 2.0, width / 2.0
    loc = [(hl - ch, -hw), (hl, -hw + ch), (hl, hw - ch), (hl - ch, hw), (-hl + ch, hw),
           (-hl, hw - ch), (-hl, -hw + ch), (-hl + ch, -hw)]
    ca, sa = math.cos(ang), math.sin(ang)
    return [(c[0] + x * ca - y * sa, c[1] + x * sa + y * ca) for x, y in loc]


def ngon(c, r, n, phase=0.0):
    return [polar(r, phase + TAU * i / n, c) for i in range(n)]


# ---------------------------------------------------------------- station kit

class Station:
    """Flat faceted blocks with a plate skin on top. Every block is a frustum (sloped sides),
    so joints between neighbouring blocks read as V-grooves rather than flat butt seams."""

    def __init__(self, kit, rng, mats):
        self.kit, self.rng, self.m = kit, rng, mats
        self.tones = (mats["hull"], mats["hull"], mats["hull2"], mats["hull3"])
        self.plates = 0

    # -- primitives
    def frustum(self, pts, z0, h, inset, mat, bevel=0.01):
        pts = ccw(pts)
        top = safe_inset(pts, inset) if inset > 0.0 else pts
        bm = bmesh.new()
        b = [bm.verts.new((x, y, z0)) for x, y in pts]
        t = [bm.verts.new((x, y, z0 + h)) for x, y in top]
        bm.faces.new(t)
        bm.faces.new(b[::-1])
        for i in range(len(pts)):
            j = (i + 1) % len(pts)
            bm.faces.new((b[i], b[j], t[j], t[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return self.kit.link(bm, mat, bevel)

    def plate(self, pts, z, thick=None):
        rng = self.rng
        if thick is None:
            thick = rng.uniform(0.03, 0.08) if rng.random() > 0.15 else 0.13
        self.plates += 1
        return self.frustum(pts, z, thick, min(0.035, thick * 0.6), rng.choice(self.tones),
                            bevel=0.008)

    def light(self, pts, z, mat=None, thick=0.03):
        return self.frustum(pts, z, thick, 0.0, mat or self.m["accent"], bevel=0.0)

    def light_line(self, p, q, w, z, mat=None):
        return self.light(beam_quad(p, q, w), z, mat)

    def nav(self, p, z, red):
        self.kit.box(p[0], p[1], z, 0.16, 0.16, 0.08, self.m["red" if red else "green"],
                     bevel=0.0)

    # -- plate skins
    def skin_quad(self, quad, z, gap=0.014):
        """Chunky plates over a quad with slanted, non-grid seams (corvette partitioner)."""
        dist = math.dist
        a, b, c, d = quad
        if (dist(a, d) + dist(b, c)) > 1.3 * (dist(a, b) + dist(d, c)):
            a, b, c, d = b, c, d, a  # partition along the longer direction
        q = (a, b, c, d)
        length = (dist(a, b) + dist(d, c)) / 2.0
        width = (dist(a, d) + dist(b, c)) / 2.0
        if length < 0.08 or width < 0.08:
            return
        bands = max(1, int(math.ceil(width / 2.2)))
        wb = width / bands
        strip = (min(0.7, max(0.3, 0.9 * wb)), min(1.3, max(0.5, 1.8 * wb)))
        for k in range(bands):
            cells = kb.organic_partition(self.rng, 0.0, length, k / bands, (k + 1) / bands, wb,
                                         strip=strip, slant=0.35, tslant=0.08 / max(wb, 0.5))
            for cell in cells:
                pts = [bilerp(q, x / length, t) for x, t in cell]
                self.plate(safe_inset(pts, gap), z)

    def skin_ngon(self, pts, z, core=0.55):
        """Ring of quads around a central cap plate, for hubs and pods."""
        pts = ccw(pts)
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        inner = [(cx + (x - cx) * core, cy + (y - cy) * core) for x, y in pts]
        for i in range(len(pts)):
            j = (i + 1) % len(pts)
            self.skin_quad([pts[i], pts[j], inner[j], inner[i]], z)
        self.plate(safe_inset(inner, 0.014), z)

    # -- blocks
    def block(self, pts, z0, h, inset=0.12, skin="auto"):
        """Hull frustum, plated on top. Returns the top z (under the plates)."""
        self.frustum(pts, z0, h, inset, self.m["hull3"], bevel=0.02)
        top = safe_inset(pts, inset)
        if skin == "auto":
            skin = "quad" if len(pts) == 4 else "ngon"
        if skin == "quad":
            self.skin_quad(top, z0 + h)
        elif skin == "ngon":
            self.skin_ngon(top, z0 + h)
        elif skin == "module":
            # Chamfered rect (see chamfer_rect order): plated centre plus one plate per end,
            # so the corner cuts don't leave thin slivers.
            self.skin_quad([top[7], top[0], top[3], top[4]], z0 + h)
            for end in (top[0:4], top[4:8]):
                self.plate(safe_inset(end, 0.014), z0 + h)
        return z0 + h

    def beam(self, p, q, w, z0, h, inset=0.07):
        return self.block(beam_quad(p, q, w), z0, h, inset)

    def module(self, c, length, width, ang, z0, h):
        ch = min(length, width) * 0.22
        return self.block(chamfer_rect(c, length, width, ch, ang), z0, h, 0.12, "module")

    def ring_band(self, r_in, r_out, a0, a1, nf, z0, h, inset=0.16, lit=True, skin=True):
        """Faceted ring (or arc of one): straight facets, sloped sides, plated top, neon strip
        along the inner edge. Returns the top z."""
        full = abs(a1 - a0) >= TAU - 1e-6
        bm = bmesh.new()
        rows = []
        for k in range(nf if full else nf + 1):
            a = a0 + (a1 - a0) * k / nf
            rows.append([bm.verts.new((*polar(r, a), z)) for r, z in
                         ((r_out, z0), (r_out - inset, z0 + h), (r_in + inset, z0 + h),
                          (r_in, z0))])
        for k in range(nf):
            r0, r1 = rows[k], rows[(k + 1) % len(rows)]
            for i in range(4):
                j = (i + 1) % 4
                bm.faces.new((r0[i], r1[i], r1[j], r0[j]))
        if not full:
            bm.faces.new(rows[0])
            bm.faces.new(rows[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        self.kit.link(bm, self.m["hull3"], bevel=0.02)
        top = z0 + h
        lip = 0.09 if lit else 0.0
        for k in range(nf):
            a, b = a0 + (a1 - a0) * k / nf, a0 + (a1 - a0) * (k + 1) / nf
            ri, ro = r_in + inset, r_out - inset
            if lit:
                self.light([polar(ri, a), polar(ri, b), polar(ri + lip, b), polar(ri + lip, a)],
                           top)
            if skin:
                self.skin_quad([polar(ri + lip, a), polar(ri + lip, b), polar(ro, b),
                                polar(ro, a)], top)
        return top

    # -- hardware (kept to a few tight clusters)
    def radiator(self, c, z, ang, length=0.7, width=0.5):
        m = self.m
        self.kit.box(c[0], c[1], z, length, width, 0.12, m["dark"], rot=ang)
        for i in range(5):
            off = -length * 0.36 + i * length * 0.18
            self.kit.box(c[0] + off * math.cos(ang), c[1] + off * math.sin(ang), z + 0.12,
                         0.05, width * 0.8, 0.04, m["bright"], rot=ang, bevel=0.0)

    def tanks(self, c, z, ang, r=0.2):
        for s in (-1, 1):
            p = polar(r * 1.15 * s, ang, c)
            self.kit.cyl(p[0], p[1], z, 0.22, r, self.m["dark"], axis="Z")

    def dish(self, c, z, r=0.35):
        self.kit.cyl(c[0], c[1], z, 0.14, r, self.m["bright"], axis="Z", r2=r * 0.55)
        self.kit.cyl(c[0], c[1], z + 0.14, 0.04, r * 0.15, self.m["accent"], axis="Z",
                     bevel=0.0)

    def hardware(self, kind, c, z, ang):
        if kind == "radiator":
            self.radiator(c, z, ang)
        elif kind == "tanks":
            self.tanks(c, z, ang)
        else:
            self.dish(c, z)

    def beacon(self, z, r=0.2, c=(0.0, 0.0)):
        self.kit.cyl(c[0], c[1], z, 0.08, r, self.m["accent_hot"], axis="Z", bevel=0.0)

    def pier(self, a, r0, r1, z0=0.05, red=True, c=(0.0, 0.0)):
        """Docking arm out from c along angle a, ending in a clamp with a nav light on each
        prong."""
        p, q = polar(r0, a, c), polar(r1, a, c)
        top = self.beam(p, q, 0.42, z0, 0.24)
        side = a + math.pi / 2.0
        # Crossbar ties the prongs to the arm; prongs grow forward out of its ends.
        self.block(beam_quad(polar(-0.42, side, q), polar(0.42, side, q), 0.24), z0, 0.26, 0.04,
                   skin=None)
        for s in (-1, 1):
            base = polar(0.32 * s, side, q)
            self.block(beam_quad(base, polar(0.5, a, base), 0.18), z0, 0.26, 0.04, skin=None)
            self.nav(polar(0.36, a, base), z0 + 0.26, red)
        return top

    def hub(self, r, n, z0=0.0, tiers=2, phase=0.0):
        z = self.block(ngon((0.0, 0.0), r, n, phase), z0, 0.65, 0.18)
        if tiers > 1:
            z = self.block(ngon((0.0, 0.0), r * 0.55, n, phase + math.pi / n), z + 0.12, 0.3,
                           0.1)
        self.beacon(z + 0.14)
        return z


# ---------------------------------------------------------------- archetypes

def build_ring(st, rng):
    """Faceted torus on spokes around a tiered hub, docking piers on the rim."""
    ns = rng.choice((3, 4, 6))
    nf = min(24, ns * rng.choice((2, 3, 4)))
    r_out = rng.uniform(5.3, 6.0)
    r_in = r_out - rng.uniform(1.0, 1.4)
    top = st.ring_band(r_in, r_out, 0.0, TAU, nf, 0.0, 0.5)
    rh = rng.uniform(1.5, 1.9)
    st.hub(rh, rng.choice((6, 8)), tiers=2)
    twin = rng.random() < 0.5
    spoke_phase = math.pi / nf if rng.random() < 0.5 else 0.0
    for k in range(ns):
        a = spoke_phase + TAU * k / ns
        if twin:  # paired spokes with a neon strip run between them
            for s in (-1, 1):
                off = polar(0.28, a + s * math.pi / 2.0)
                st.beam((off[0] + rh * 0.8 * math.cos(a), off[1] + rh * 0.8 * math.sin(a)),
                        (off[0] + (r_in + 0.15) * math.cos(a),
                         off[1] + (r_in + 0.15) * math.sin(a)), 0.32, 0.05, 0.3)
            st.light_line(polar(rh, a), polar(r_in, a), 0.06, 0.1)
        else:
            st.beam(polar(rh * 0.8, a), polar(r_in + 0.15, a), 0.6, 0.05, 0.32)
    if rng.random() < 0.4:  # inner habitat ring threaded on the spokes
        mid = (rh + r_in) / 2.0
        st.ring_band(mid - 0.3, mid + 0.3, 0.0, TAU, nf, 0.0, 0.32, inset=0.1, lit=False)
    npier = ns if rng.random() < 0.6 else 2 * ns
    plen = rng.uniform(0.8, 1.2)
    for k in range(npier):
        st.pier(spoke_phase + math.pi / npier * (1 + 2 * k), r_out - 0.2, r_out + plen,
                red=k % 2 == 0)
    kind = rng.choice(("radiator", "tanks", "dish"))
    for k in range(ns):
        a = spoke_phase + TAU * (k + 0.25) / ns
        st.hardware(kind, polar((r_in + r_out) / 2.0, a), top, a + math.pi / 2.0)


def build_arcs(st, rng):
    """Broken ring: separate arc segments on single spokes, with a glowing halo inside."""
    na = rng.choice((3, 4))
    gap = rng.uniform(0.22, 0.4)
    nf = rng.choice((3, 4))
    r_out = rng.uniform(5.4, 6.0)
    r_in = r_out - rng.uniform(1.0, 1.4)
    phase = rng.uniform(0.0, TAU / na)
    rh = rng.uniform(1.3, 1.7)
    st.hub(rh, na * 2, tiers=2, phase=phase)
    halo = rng.uniform(2.6, 3.2)
    st.ring_band(halo - 0.16, halo + 0.16, 0.0, TAU, na * 6, 0.1, 0.16, inset=0.04, lit=False,
                 skin=False)
    for k in range(na * 6):
        a, b = TAU * k / (na * 6), TAU * (k + 1) / (na * 6)
        st.light([polar(halo - 0.06, a), polar(halo - 0.06, b), polar(halo + 0.06, b),
                  polar(halo + 0.06, a)], 0.26)
    kind = rng.choice(("radiator", "tanks", "dish"))
    for k in range(na):
        ac = phase + TAU * k / na
        a0, a1 = ac - (math.pi / na - gap / 2.0), ac + (math.pi / na - gap / 2.0)
        top = st.ring_band(r_in, r_out, a0, a1, nf, 0.0, 0.5)
        for a, red in ((a0, True), (a1, False)):  # armoured end caps with nav lights
            inward = a + (0.06 if red else -0.06)
            end = [polar(r_in - 0.15, a), polar(r_out + 0.15, a), polar(r_out + 0.15, inward),
                   polar(r_in - 0.15, inward)]
            st.block(end, 0.0, 0.62, 0.06, skin=None)
            st.nav(polar(r_out + 0.05, (a + inward) / 2.0), 0.62, red)
        st.beam(polar(rh * 0.8, ac), polar(r_in + 0.15, ac), 0.55, 0.05, 0.34)
        st.hardware(kind, polar((r_in + r_out) / 2.0, ac + (a1 - ac) * 0.5), top,
                    ac + math.pi / 2.0)


def build_cross(st, rng):
    """Four truss arms carrying modules, with radiator T-bars or docking heads at the ends."""
    rot0 = rng.choice((0.0, math.pi / 4.0))
    rh = rng.uniform(1.6, 2.0)
    st.hub(rh, 8, tiers=2, phase=math.pi / 8.0)
    long_l = rng.uniform(4.8, 5.8)
    plans = []
    for pair in range(2):
        length = long_l if pair == 0 or rng.random() < 0.4 else long_l * rng.uniform(0.6, 0.75)
        mods = []
        x = rh + 0.4
        while x < length - 1.2:
            ml = rng.uniform(1.0, 1.5)
            mods.append((x + ml / 2.0, ml, rng.uniform(0.9, 1.4)))
            x += ml + rng.uniform(0.35, 0.7)
        plans.append((length, mods, rng.choice(("radiator", "dock")), rng.random() < 0.5))
    for k in range(4):
        a = rot0 + k * math.pi / 2.0
        length, mods, end, lit = plans[k % 2]
        st.beam(polar(rh * 0.8, a), polar(length, a), 0.45, 0.03, 0.24)
        if lit:
            st.light_line(polar(rh, a), polar(length - 0.2, a), 0.05, 0.03 + 0.24 + 0.14)
        for xc, ml, mw in mods:
            st.module(polar(xc, a), ml, mw, a, 0.0, 0.45)
        tip = polar(length, a)
        if end == "radiator":
            for s in (-1, 1):  # T-bar of radiator panels across the arm end
                p, q = polar(0.25 * s, a + math.pi / 2.0, tip), polar(1.6 * s, a + math.pi / 2.0,
                                                                     tip)
                st.block(beam_quad(p, q, 0.7), 0.0, 0.18, 0.05, skin=None)
                for i in range(4):
                    f = 0.35 + 0.33 * i
                    c = polar(f * s, a + math.pi / 2.0, tip)
                    st.kit.box(c[0], c[1], 0.18, 0.05, 0.55, 0.03, st.m["bright"], rot=a,
                               bevel=0.0)
                st.nav(polar(1.45 * s, a + math.pi / 2.0, tip), 0.18, k % 2 == 0)
        else:
            z = st.module(tip, 1.1, 1.1, a + math.pi / 4.0, 0.0, 0.5)
            st.dish(tip, z + 0.13, 0.28)
            for s in (-1, 1):  # diagonal piers off the docking head
                st.pier(a + s * 0.8, 0.4, 1.4, red=s > 0, c=tip)


def build_spoke(st, rng):
    """Big hub with radial arms ending in hexagonal pods, optionally tied by a thin ring."""
    n = rng.choice((5, 6, 8))
    rh = rng.uniform(2.0, 2.4)
    st.hub(rh, n * 2 if n < 6 else n, tiers=2)
    long_l = rng.uniform(4.9, 5.5)
    alt = rng.random() < 0.5
    pr = rng.uniform(0.75, 0.95)
    if rng.random() < 0.45:
        tie = long_l * 0.62
        st.ring_band(tie - 0.12, tie + 0.12, 0.0, TAU, n * 3, 0.0, 0.18, inset=0.04, lit=False,
                     skin=False)
    kind = rng.choice(("radiator", "tanks", "dish"))
    for k in range(n):
        a = TAU * k / n
        length = long_l * (0.75 if alt and k % 2 else 1.0)
        st.beam(polar(rh * 0.8, a), polar(length - pr * 0.7, a), 0.38, 0.03, 0.26)
        pz = st.block(ngon(polar(length, a), pr, 6, a), 0.0, 0.5, 0.12)
        st.kit.cyl(*polar(length, a), pz + 0.12, 0.05, pr * 0.3, st.m["accent"], axis="Z",
                   bevel=0.0)
        st.nav(polar(length + pr * 0.6, a), pz + 0.1, k % 2 == 0)
        st.hardware(kind, polar(rh * 0.78, a + math.pi / n), 0.65, a)


def build_truss(st, rng):
    """Asymmetric industrial rig: a long twin-rail truss with habitat, silos and cranes."""
    half = rng.uniform(5.0, 5.8)
    rail = 0.6
    for s in (-1, 1):  # twin rails, tied together by a crossbeam at each end
        st.beam((-half, rail * s), (half, rail * s), 0.34, 0.05, 0.26, inset=0.05)
        st.beam((half * s, -rail - 0.17), (half * s, rail + 0.17), 0.34, 0.05, 0.26, inset=0.05)
    nb = int(2 * half / 1.1)
    for i in range(nb):  # zig-zag bracing between the rails
        x0 = -half + 2 * half * i / nb
        x1 = -half + 2 * half * (i + 1) / nb
        y0, y1 = (rail, -rail) if i % 2 else (-rail, rail)
        st.kit.box((x0 + x1) / 2.0, 0.0, 0.08, math.hypot(x1 - x0, 2 * rail), 0.1, 0.1,
                   st.m["bright"], rot=math.atan2(y1 - y0, x1 - x0), bevel=0.0)
    hab_x = -half + 1.4
    z = st.module((hab_x, 0.0), rng.uniform(2.8, 3.4), rng.uniform(3.6, 4.4), 0.0, 0.0, 0.6)
    st.module((hab_x, 0.0), 1.6, 2.0, math.pi / 2.0, z + 0.1, 0.3)
    st.beacon(z + 0.55, c=(hab_x, 0.0))
    st.pier(0.0, half, half + 1.0, red=True)
    x = hab_x + 2.0
    side = rng.choice((-1, 1))
    while x < half - 0.9:
        kind = rng.choice(("block", "block", "silos", "crane"))
        if kind == "block":
            ml, mw = rng.uniform(1.4, 2.2), rng.uniform(1.4, 2.0)
            # Overlap the rail and sit on a collar, so the sloped edges can't open a gap.
            c = (x + ml / 2.0, side * (rail + mw / 2.0 - 0.08))
            st.block(beam_quad((c[0], side * rail), c, ml * 0.5), 0.05, 0.3, 0.05, skin=None)
            z = st.module(c, ml, mw, 0.0, 0.0, 0.42)
            if rng.random() < 0.5:
                st.radiator(c, z + 0.1, math.pi / 2.0)
            x += ml + 0.3
        elif kind == "silos":
            for i in range(rng.choice((2, 3))):
                # Silo hugs the rail on a short strut, so nothing floats free of the frame.
                cx, cy = x + 0.6, side * (rail + 0.55)
                st.block(beam_quad((cx, side * rail), (cx, cy), 0.26), 0.05, 0.2, 0.04,
                         skin=None)
                st.block(ngon((cx, cy), 0.55, 8, math.pi / 8.0), 0.0, 0.5, 0.1)
                st.kit.cyl(cx, cy, 0.5, 0.18, 0.3, st.m["dark"], axis="Z")
                st.kit.cyl(cx, cy, 0.68, 0.03, 0.09, st.m["accent"], axis="Z", bevel=0.0)
                x += 1.3
            x += 0.3
        else:
            # Crane: a turret block on the rail with a short jib swung outboard.
            ang = side * rng.uniform(0.6, 1.2)
            base = (x + 0.4, side * rail)
            tz = st.module(base, 0.7, 0.7, 0.0, 0.0, 0.4)
            jib = rng.uniform(1.4, 2.0)
            tip = polar(jib, ang, base)
            st.block(beam_quad(base, tip, 0.28), tz - 0.1, 0.14, 0.04, skin=None)
            st.kit.box(tip[0], tip[1], tz - 0.12, 0.45, 0.45, 0.22, st.m["dark"], rot=ang)
            st.nav(tip, tz + 0.1, side > 0)
            x += 0.9 + jib * math.cos(ang)  # keep the jib's swing clear of the next module
        side = -side if rng.random() < 0.7 else side
    for i in range(int(2 * half / 2.2) + 1):  # hazard lights along the rails
        hx = -half + 0.4 + i * 2.2
        st.light_line((hx - 0.2, rail), (hx + 0.2, rail), 0.08, 0.33)


BUILDERS = {
    "arcs": build_arcs,
    "cross": build_cross,
    "ring": build_ring,
    "spoke": build_spoke,
    "truss": build_truss,
}


# ---------------------------------------------------------------- scene

def frame(scene, res, margin=0.8):
    """Ortho framing fitted to every mesh's bounding box; res is the longer side in px."""
    xs, ys = [], []
    for ob in scene.objects:
        if ob.type == "MESH":
            for v in ob.bound_box:
                xs.append(v[0])
                ys.append(v[1])
    cx, cy = (min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0
    w, h = max(xs) - min(xs) + margin, max(ys) - min(ys) + margin
    span = max(w, h)
    scene.render.resolution_x = int(round(res * w / span))
    scene.render.resolution_y = int(round(res * h / span))
    scene.camera.data.ortho_scale = span  # ortho_scale spans the longer image side
    scene.camera.location = (cx, cy, 30.0)
    return span


def main():
    args = parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="[kitbash] %(message)s")
    t0 = time.perf_counter()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = kb.setup_scene(args)
    accent = ACCENTS[args.accent]
    mats = {
        "hull": kb.metal_mat("hull", "#62666b"),
        "hull2": kb.metal_mat("hull2", "#5c6065"),
        "hull3": kb.metal_mat("hull3", "#565a5f"),
        "dark": kb.metal_mat("dark", "#34353a", rough=0.5),
        "bright": kb.metal_mat("bright", "#b8bcc4", metal=0.9, rough=0.22, grime=0.9),
        "accent": kb.emit_mat("accent", accent, 6.0),
        "accent_hot": kb.emit_mat("accent_hot", accent, 14.0),
        "red": kb.emit_mat("red", "#ff3b3b", 14.0),
        "green": kb.emit_mat("green", "#4bff7a", 10.0),
    }
    kit = kb.Kit()
    # Seed on type too, so seed N of one archetype doesn't mirror seed N's choices in another.
    st = Station(kit, random.Random("%s-%d" % (args.type, args.seed)), mats)
    BUILDERS[args.type](st, st.rng)
    span = frame(scene, args.res)
    if args.preview:
        bd = bpy.data.objects.new("backdrop", bpy.data.meshes.new("backdrop"))
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30.0)
        bmesh.ops.translate(bm, vec=(scene.camera.location.x, scene.camera.location.y, -3.0),
                            verts=bm.verts)
        bm.to_mesh(bd.data)
        bm.free()
        bd.data.materials.append(kb.backdrop_mat())
        scene.collection.objects.link(bd)
    t1 = time.perf_counter()
    LOG.debug("%s seed %d: %d objects (%d plates), span %.1f, built in %.2fs", args.type,
              args.seed, kit.count, st.plates, span, t1 - t0)
    scene.render.filepath = args.out
    bpy.ops.render.render(write_still=True)
    LOG.info("wrote %s (render %.1fs)", args.out, time.perf_counter() - t1)


if __name__ == "__main__":
    main()
