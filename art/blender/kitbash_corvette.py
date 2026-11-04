"""Procedural kitbash corvette, rendered top-down with Cycles.

Chined, lofted hull skinned with plates in a gunmetal scheme, with neon accent lights.
Seed 2 is the approved corvette design (2026-11-03); other seeds reshuffle the plating
and hardware.

Run headless in Blender 5.2; see art\\README.md for the command. Without --preview the PNG
has a transparent background; --preview adds a space backdrop and engine flames (preview
only; in-game those are VFX).

Nose points +X (right) to match Ship.gd's rotation convention.
"""
import argparse
import json
import logging
import math
import os
import random
import sys
import time

import bmesh
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Vector

LOG = logging.getLogger("kitbash")
MOUNT_RADIUS = 0.34  # weapon attach plate, Blender units


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    p.add_argument("--seed", type=int, default=2, help="2 = approved corvette design")
    p.add_argument("--res", type=int, default=768, help="render width in px")
    p.add_argument("--samples", type=int, default=64)
    p.add_argument("--preview", action="store_true", help="add space backdrop + engine flames")
    p.add_argument("--verbose", action="store_true")
    return p.parse_args(argv)


def hex_lin(h):
    """sRGB hex -> linear RGB tuple (node colors are linear)."""
    out = []
    for i in (1, 3, 5):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


# ---------------------------------------------------------------- materials

def _new_mat(name):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True  # deprecated/always-on in 5.x, required in older builds
    except AttributeError:
        pass
    return m


def _rgba_sockets(node, outputs=False):
    return [s for s in (node.outputs if outputs else node.inputs) if s.type == "RGBA"]


def metal_mat(name, hexcol, metal=0.65, rough=0.4, grime=0.8):
    """Painted metal: fine low-contrast grime, roughness variation, AO in crevices."""
    m = _new_mat(name)
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    rgb = hex_lin(hexcol)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    fine = nt.nodes.new("ShaderNodeTexNoise")
    fine.inputs["Scale"].default_value = 45.0
    fine.inputs["Detail"].default_value = 6.0
    nt.links.new(tc.outputs["Object"], fine.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    e0, e1 = ramp.color_ramp.elements
    e0.position, e1.position = 0.35, 0.65
    e0.color = (rgb[0] * grime, rgb[1] * grime, rgb[2] * grime, 1.0)
    e1.color = (*rgb, 1.0)
    nt.links.new(fine.outputs["Fac"], ramp.inputs["Fac"])
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.3
    ao_ramp = nt.nodes.new("ShaderNodeValToRGB")
    a0, a1 = ao_ramp.color_ramp.elements
    a0.color, a1.color = (0.1, 0.1, 0.1, 1.0), (1.0, 1.0, 1.0, 1.0)
    nt.links.new(ao.outputs["AO"], ao_ramp.inputs["Fac"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    ins = _rgba_sockets(mix)
    nt.links.new(ramp.outputs["Color"], ins[0])
    nt.links.new(ao_ramp.outputs["Color"], ins[1])
    nt.links.new(_rgba_sockets(mix, outputs=True)[0], bsdf.inputs["Base Color"])
    # Large-scale roughness variation reads as wear without adding grain.
    broad = nt.nodes.new("ShaderNodeTexNoise")
    broad.inputs["Scale"].default_value = 4.0
    nt.links.new(tc.outputs["Object"], broad.inputs["Vector"])
    rr = nt.nodes.new("ShaderNodeMapRange")
    rr.inputs["To Min"].default_value = rough - 0.12
    rr.inputs["To Max"].default_value = rough + 0.15
    nt.links.new(broad.outputs["Fac"], rr.inputs["Value"])
    nt.links.new(rr.outputs["Result"], bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = metal
    return m


def emit_mat(name, hexcol, strength):
    m = _new_mat(name)
    nt = m.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*hex_lin(hexcol), 1.0)
    em.inputs["Strength"].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


def flame_mat(name, hexcol, strength):
    """Emission fading to transparent toward the cone tip (Generated X = 0)."""
    m = _new_mat(name)
    nt = m.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = 2.2
    nt.links.new(sep.outputs["X"], pw.inputs[0])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*hex_lin(hexcol), 1.0)
    em.inputs["Strength"].default_value = strength
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(pw.outputs["Value"], mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    return m


def backdrop_mat():
    m = _new_mat("backdrop")
    nt = m.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.12
    noise.inputs["Detail"].default_value = 6.0
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.45, (*hex_lin("#030308"), 1.0)
    els[1].position, els[1].color = 0.75, (*hex_lin("#3a1040"), 1.0)
    mid = els.new(0.6)
    mid.color = (*hex_lin("#0c0a1e"), 1.0)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    neb = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(ramp.outputs["Color"], neb.inputs["Color"])
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 3.0
    nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
    sramp = nt.nodes.new("ShaderNodeValToRGB")
    s0, s1 = sramp.color_ramp.elements
    s0.position, s0.color = 0.0, (1.0, 1.0, 1.0, 1.0)
    s1.position, s1.color = 0.025, (0.0, 0.0, 0.0, 1.0)
    nt.links.new(vor.outputs["Distance"], sramp.inputs["Fac"])
    star = nt.nodes.new("ShaderNodeEmission")
    star.inputs["Strength"].default_value = 3.0
    nt.links.new(sramp.outputs["Color"], star.inputs["Color"])
    add = nt.nodes.new("ShaderNodeAddShader")
    nt.links.new(neb.outputs[0], add.inputs[0])
    nt.links.new(star.outputs[0], add.inputs[1])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(add.outputs[0], out.inputs["Surface"])
    return m


# ---------------------------------------------------------------- geometry

class Loft:
    """Hull section swept along X. Profile z = h * (1 - |t|^p)^q: p=2 gives a rounded crown;
    q > 1 thins the sides into an SR-71-style knife-edge chine, q < 1 makes a blunt hump."""

    def __init__(self, stations, p=2.0, q=1.0, z0=0.0):
        self.st = sorted(stations)  # (x, half_width, height, y_centre)
        self.p, self.q = p, q
        self.z0 = z0
        self.x0, self.x1 = self.st[0][0], self.st[-1][0]
        self.slopes = [self._pchip_slopes(i) for i in (1, 2, 3)]

    def _pchip_slopes(self, i):
        """Fritsch-Carlson monotone slopes: smooth through stations without overshoot or the
        flat spots a cosine blend leaves at each station (which made the nose edge ripple)."""
        xs = [s[0] for s in self.st]
        ys = [s[i] for s in self.st]
        d = [(ys[k + 1] - ys[k]) / (xs[k + 1] - xs[k]) for k in range(len(xs) - 1)]
        m = [d[0]] + [0.0] * (len(xs) - 2) + [d[-1]]
        for k in range(1, len(xs) - 1):
            if d[k - 1] * d[k] > 0.0:
                w1 = 2.0 * (xs[k + 1] - xs[k]) + (xs[k] - xs[k - 1])
                w2 = (xs[k + 1] - xs[k]) + 2.0 * (xs[k] - xs[k - 1])
                m[k] = (w1 + w2) / (w1 / d[k - 1] + w2 / d[k])
        return m

    def params(self, x):
        x = min(max(x, self.x0), self.x1)
        for k, (a, b) in enumerate(zip(self.st, self.st[1:])):
            if a[0] <= x <= b[0]:
                hgt = b[0] - a[0]
                s = (x - a[0]) / hgt if hgt > 0.0 else 0.0
                h00, h10 = 2 * s ** 3 - 3 * s ** 2 + 1, s ** 3 - 2 * s ** 2 + s
                h01, h11 = -2 * s ** 3 + 3 * s ** 2, s ** 3 - s ** 2
                return tuple(h00 * a[i] + h10 * hgt * self.slopes[i - 1][k] + h01 * b[i]
                             + h11 * hgt * self.slopes[i - 1][k + 1] for i in (1, 2, 3))
        return self.st[-1][1:]

    def point(self, x, t):
        w, h, yc = self.params(x)
        a = min(abs(t), 1.0)
        z = h * max(0.0, 1.0 - a ** self.p) ** self.q
        return Vector((x, yc + t * w, self.z0 + z))

    def normal(self, x, t):
        t = min(max(t, -0.995), 0.995)
        e = 1e-3
        dx = self.point(x + e, t) - self.point(x - e, t)
        dt = self.point(x, t + e) - self.point(x, t - e)
        nrm = dx.cross(dt)
        return nrm.normalized() if nrm.length > 1e-9 else Vector((0.0, 0.0, 1.0))


def tsamples(t0, t1, count):
    """Samples biased toward |t| = 1 where the profile curves fastest."""
    out = []
    for i in range(count + 1):
        s = t0 + (t1 - t0) * i / count
        out.append(math.copysign(math.sin(abs(s) * math.pi / 2.0), s))
    return out


class Kit:
    def __init__(self):
        self.count = 0

    def link(self, bm, mat, bevel=0.0, smooth_angle=None):
        self.count += 1
        me = bpy.data.meshes.new("part%d" % self.count)
        bm.to_mesh(me)
        bm.free()
        if smooth_angle is not None:
            try:
                me.set_sharp_from_angle(angle=math.radians(smooth_angle))  # 4.1+
            except AttributeError:
                for poly in me.polygons:
                    poly.use_smooth = True
        ob = bpy.data.objects.new(me.name, me)
        bpy.context.collection.objects.link(ob)
        me.materials.append(mat)
        if bevel > 0.0:
            mod = ob.modifiers.new("bevel", "BEVEL")
            mod.width = bevel
            mod.segments = 2
            mod.limit_method = "ANGLE"
            mod.harden_normals = False
        return ob

    def loft_body(self, loft, mat, step=0.08, tcount=28):
        """Solid surface of a loft with end caps (underside left open; camera is above)."""
        bm = bmesh.new()
        nx = max(2, int((loft.x1 - loft.x0) / step))
        ts = tsamples(-1.0, 1.0, tcount)
        rows = []
        for i in range(nx + 1):
            x = loft.x0 + (loft.x1 - loft.x0) * i / nx
            rows.append([bm.verts.new(loft.point(x, t)) for t in ts])
        for i in range(nx):
            for j in range(len(ts) - 1):
                bm.faces.new((rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1]))
        for row in (rows[0], rows[-1]):
            try:
                bm.faces.new(row)
            except ValueError:
                pass  # degenerate tip cap
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return self.link(bm, mat, smooth_angle=40.0)

    def loft_quad(self, loft, corners, off, thick, mat, bevel=0.01):
        """Plate over an arbitrary param-space quad [(x,t) at x0t0, x1t0, x1t1, x0t1]."""
        (ax, at), (bx, bt), (cx, ct), (dx, dt) = corners
        w = loft.params((ax + cx) / 2.0)[0]
        nx = max(2, int(max(abs(bx - ax), abs(cx - dx)) / 0.08))
        nt = max(2, int(max(abs(dt - at), abs(ct - bt)) * w / 0.05))
        bm = bmesh.new()
        top, bot = [], []
        for i in range(nx + 1):
            u = i / nx
            lx, lt = ax + (bx - ax) * u, at + (bt - at) * u   # t0 edge
            hx, ht = dx + (cx - dx) * u, dt + (ct - dt) * u   # t1 edge
            rt, rb = [], []
            for j in range(nt + 1):
                v = j / nt
                x, t = lx + (hx - lx) * v, lt + (ht - lt) * v
                p, n = loft.point(x, t), loft.normal(x, t)
                # Thin plates to nothing at the chine so the edge silhouette stays clean.
                edge = max(0.05, 1.0 - min(abs(t), 1.0) ** 6)
                rt.append(bm.verts.new(p + n * (off + thick) * edge))
                rb.append(bm.verts.new(p + n * off * edge))
            top.append(rt)
            bot.append(rb)
        for i in range(nx):
            for j in range(nt):
                bm.faces.new((top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1]))
                bm.faces.new((bot[i][j + 1], bot[i + 1][j + 1], bot[i + 1][j], bot[i][j]))
        for i in range(nx):
            bm.faces.new((bot[i][0], bot[i + 1][0], top[i + 1][0], top[i][0]))
            bm.faces.new((top[i][nt], top[i + 1][nt], bot[i + 1][nt], bot[i][nt]))
        for j in range(nt):
            bm.faces.new((top[0][j], top[0][j + 1], bot[0][j + 1], bot[0][j]))
            bm.faces.new((bot[nx][j], bot[nx][j + 1], top[nx][j + 1], top[nx][j]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return self.link(bm, mat, bevel=bevel, smooth_angle=40.0)

    def loft_patch(self, loft, x0, x1, t0, t1, off, thick, mat, bevel=0.008, t_end=None):
        """A plate that follows the loft surface between (x0..x1, t0..t1). t_end, if given,
        is the (t0, t1) span at x1, so the plate tapers into an angled end."""
        bm = bmesh.new()
        e0, e1 = t_end if t_end is not None else (t0, t1)
        w = loft.params((x0 + x1) / 2.0)[0]
        nx = max(2, int((x1 - x0) / 0.08))
        nt = max(2, int(max(abs(t1 - t0), abs(e1 - e0)) * w / 0.05))
        top, bot = [], []
        for i in range(nx + 1):
            f = i / nx
            x = x0 + (x1 - x0) * f
            a, b = t0 + (e0 - t0) * f, t1 + (e1 - t1) * f
            rt, rb = [], []
            for j in range(nt + 1):
                t = a + (b - a) * j / nt
                p, n = loft.point(x, t), loft.normal(x, t)
                rt.append(bm.verts.new(p + n * (off + thick)))
                rb.append(bm.verts.new(p + n * off))
            top.append(rt)
            bot.append(rb)
        for i in range(nx):
            for j in range(nt):
                bm.faces.new((top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1]))
                bm.faces.new((bot[i][j + 1], bot[i + 1][j + 1], bot[i + 1][j], bot[i][j]))
        for i in range(nx):
            bm.faces.new((bot[i][0], bot[i + 1][0], top[i + 1][0], top[i][0]))
            bm.faces.new((top[i][nt], top[i + 1][nt], bot[i + 1][nt], bot[i][nt]))
        for j in range(nt):
            bm.faces.new((top[0][j], top[0][j + 1], bot[0][j + 1], bot[0][j]))
            bm.faces.new((bot[nx][j], bot[nx][j + 1], top[nx][j + 1], top[nx][j]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return self.link(bm, mat, bevel=bevel, smooth_angle=40.0)

    def box(self, cx, cy, z0, sx, sy, sz, mat, rot=0.0, bevel=None):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        mtx = (Matrix.Translation((cx, cy, z0 + sz / 2.0)) @ Matrix.Rotation(rot, 4, "Z")
               @ Matrix.Diagonal((sx, sy, sz, 1.0)))
        bmesh.ops.transform(bm, matrix=mtx, verts=bm.verts)
        if bevel is None:
            bevel = min(0.025, 0.25 * min(sx, sy, sz))
        return self.link(bm, mat, bevel)

    def cyl(self, x, y, z, length, r, mat, axis="X", r2=None, segs=32, bevel=0.01):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r,
                              radius2=r if r2 is None else r2, depth=length)
        if axis == "X":
            mtx = (Matrix.Translation((x + length / 2.0, y, z))
                   @ Matrix.Rotation(math.radians(90.0), 4, "Y"))
        else:
            mtx = Matrix.Translation((x, y, z + length / 2.0))
        bmesh.ops.transform(bm, matrix=mtx, verts=bm.verts)
        return self.link(bm, mat, bevel, smooth_angle=40.0)


def organic_partition(rng, x0, x1, t0, t1, world_w, strip=(0.55, 1.05), slant=0.4,
                      tslant=0.1):
    """Cover a param rect completely with quads: strips along X with slanted cuts, each strip
    split across T at its own slanted lines, so seams never line up into a grid. world_w is
    the region's real width; splits across T follow it so plates stay chunky (~1:1 to 2:1)."""
    tm = (t0 + t1) / 2.0
    cuts = [(x0, 0.0)]
    x = x0
    while True:
        x += rng.uniform(*strip)
        if x >= x1 - 0.5:
            break
        cuts.append((x, rng.uniform(-slant, slant)))
    cuts.append((x1, 0.0))

    def corner(xc, sx, tc, st, xm):
        # Intersect x = xc + sx*(t - tm) with t = tc + st*(x - xm); slopes are small.
        t = tc
        for _ in range(4):
            xx = xc + sx * (t - tm)
            t = tc + st * (xx - xm)
        return (xx, t)

    cells = []
    span = t1 - t0
    for (xa, sa), (xb, sb) in zip(cuts, cuts[1:]):
        xm = (xa + xb) / 2.0
        n = max(1, min(3, int(round(world_w / ((xb - xa) * rng.uniform(0.9, 1.5))))))
        step = span / n
        tcs = [t0 + step * (k + rng.uniform(-0.15, 0.15)) for k in range(1, n)]
        lines = [(t0, 0.0)] + [(tc, rng.uniform(-tslant, tslant)) for tc in tcs] + [(t1, 0.0)]
        for (ta, pa), (tb, pb) in zip(lines, lines[1:]):
            cells.append([corner(xa, sa, ta, pa, xm), corner(xb, sb, ta, pa, xm),
                          corner(xb, sb, tb, pb, xm), corner(xa, sa, tb, pb, xm)])
    return cells


def shrink_quad(quad, gx, gt):
    """Pull each corner toward the centroid to open a hairline seam."""
    cx = sum(c[0] for c in quad) / 4.0
    ct = sum(c[1] for c in quad) / 4.0
    return [(x + math.copysign(gx, cx - x), t + math.copysign(gt, ct - t)) for x, t in quad]


# ---------------------------------------------------------------- ship

def build_corvette(kit, rng, mats, preview):
    m = mats
    tones = (m["hull"], m["hull"], m["hull2"], m["hull3"])  # one paint scheme, slight per-plate drift

    # Chined main hull: rounded crown thinning to knife edges, wide enough that the chine
    # shows ahead of and behind the sponsons.
    spine = Loft([(-4.6, 1.0, 0.85, 0.0), (-3.6, 1.2, 1.0, 0.0), (1.4, 1.2, 1.05, 0.0),
                  (3.4, 0.9, 0.85, 0.0), (5.0, 0.34, 0.45, 0.0), (5.6, 0.02, 0.22, 0.0)],
                 p=2.0, q=1.4)
    dorsal = Loft([(-3.5, 0.28, 0.25, 0.0), (-3.1, 0.42, 0.42, 0.0), (1.4, 0.42, 0.42, 0.0),
                   (2.4, 0.22, 0.3, 0.0), (2.7, 0.05, 0.1, 0.0)], p=2.0, q=0.6, z0=0.8)
    spon = [Loft([(-4.25, 0.4, 0.5, 1.45 * s), (-3.9, 0.75, 0.66, 1.5 * s),
                  (-0.3, 0.7, 0.62, 1.45 * s), (0.7, 0.34, 0.42, 1.25 * s),
                  (1.15, 0.04, 0.2, 1.1 * s)], p=2.0, q=1.2, z0=0.12) for s in (1, -1)]
    # Continuous hull underneath; armour is layered on top rather than tiled with gaps.
    kit.loft_body(spine, m["hull3"])
    kit.loft_body(dorsal, m["hull3"])
    for sp in spon:
        kit.loft_body(sp, m["hull3"])

    def armour(loft, x0, x1, t0, t1, mirror, count, layer):
        """Scatter overlapping plates of mixed size; some taper into angled ends. Layer 1
        sits above layer 0 so overlaps stack instead of intersecting."""
        off = 0.004 if layer == 0 else 0.075
        for _ in range(count):
            length = rng.uniform(0.9, 2.4) if layer == 0 else rng.uniform(0.5, 1.2)
            span = rng.uniform(0.3, 0.65) if layer == 0 else rng.uniform(0.18, 0.35)
            px0 = rng.uniform(x0, max(x0, x1 - length))
            px1 = min(x1, px0 + length)
            pt0 = rng.uniform(t0, max(t0, t1 - span))
            pt1 = min(t1, pt0 + span)
            t_end = None
            if rng.random() < 0.45:  # angled end: one edge pulls in toward the other
                cut = (pt1 - pt0) * rng.uniform(0.3, 0.7)
                t_end = (pt0 + cut, pt1) if rng.random() < 0.5 else (pt0, pt1 - cut)
            mat = rng.choice(tones)
            thick = rng.uniform(0.025, 0.045)
            kit.loft_patch(loft, px0, px1, pt0, pt1, off, thick, mat, bevel=0.01, t_end=t_end)
            if mirror is not None:
                me = None if t_end is None else (-t_end[1], -t_end[0])
                kit.loft_patch(mirror, px0, px1, -pt1, -pt0, off, thick, mat, bevel=0.01,
                               t_end=me)
        return count

    def skin(loft, x0, x1, t0, t1, mirror, **kw):
        """The plates ARE the hull surface: full coverage, hairline seams, stepped heights."""
        w = loft.params((x0 + x1) / 2.0)[0]
        gx, gt = 0.012, 0.012 / max(w, 0.1)
        # Arc length across the curved section is longer than the flat width.
        cells = organic_partition(rng, x0, x1, t0, t1, (t1 - t0) * w * 1.2, **kw)
        for quad in cells:
            q = shrink_quad(quad, gx, gt)
            mat = rng.choice(tones)
            thick = rng.uniform(0.02, 0.07) if rng.random() > 0.15 else 0.1
            kit.loft_quad(loft, q, 0.002, thick, mat)
            if mirror is not None:
                kit.loft_quad(mirror, [(x, -t) for x, t in q], 0.002, thick, mat)
        return len(cells)

    plates = 0
    plates += skin(spine, -4.6, 2.4, 0.36, 0.99, spine)          # hull shoulders + chines
    plates += skin(spine, 2.4, 5.45, 0.0, 0.99, spine)           # nose
    plates += skin(spine, -4.6, -3.4, 0.0, 0.36, spine, strip=(1.2, 1.2))  # tail crown
    plates += skin(dorsal, -3.5, 2.65, 0.0, 0.99, dorsal, strip=(0.8, 1.3))
    plates += skin(spon[0], -4.25, 1.1, -0.99, 0.99, spon[1])
    # A few stacked kitbash pieces on top of the skin, kept to the shoulders and sponsons.
    plates += armour(spine, -4.0, 2.0, 0.55, 0.95, spine, 3, 1)
    plates += armour(spon[0], -3.8, 0.4, -0.8, 0.8, spon[1], 3, 1)

    # Neon trim running along the spine shoulder, following the curve.
    for t in (0.5, -0.5):
        kit.loft_patch(spine, -3.6, 1.4, t - 0.012, t + 0.012, 0.1, 0.025, m["cyan"], bevel=0.0)
    kit.loft_patch(spine, 3.2, 4.6, 0.2, 0.23, 0.1, 0.02, m["cyan"], bevel=0.0)
    kit.loft_patch(spine, 3.2, 4.6, -0.23, -0.2, 0.1, 0.02, m["cyan"], bevel=0.0)

    def top_z(loft, x, t=0.0):
        return loft.point(x, t).z + 0.05

    # Nav lights on the sponson's outer edge (the side boosters and their fins are gone).
    for side, sp in zip((1, -1), spon):
        p = sp.point(-3.5, 0.8 * side)
        kit.box(p.x, p.y, p.z - 0.02, 0.12, 0.08, 0.05, m["red"], bevel=0.0)

    # Bridge with lit windows near the front of the dorsal.
    bz = top_z(spine, 2.55)
    kit.box(2.55, 0.0, bz - 0.12, 0.7, 0.55, 0.3, m["hull"], bevel=0.05)
    kit.box(2.92, 0.0, bz + 0.0, 0.04, 0.4, 0.1, m["yellow"], bevel=0.0)

    for y in (0.0, 0.55, -0.55):
        kit.cyl(-5.25, y, 0.5, 0.7, 0.3, m["bright"], r2=0.34)
        kit.cyl(-5.27, y, 0.5, 0.03, 0.22, m["engine"], bevel=0.0)

    # Weapon attach points: bare mount plates only. Weapons are attached in game, at the
    # positions written to the mounts sidecar. +Y is port (left of the nose).
    mounts = [("dorsal", 1.0, 0.0, top_z(dorsal, 1.0))]
    for side, sp in zip(("port", "starboard"), spon):
        for name, tx in (("fore", -0.8), ("aft", -2.8)):
            mounts.append(("%s_%s" % (side, name), tx, sp.params(tx)[2], top_z(sp, tx)))
    for _, tx, ty, tz in mounts:
        kit.cyl(tx, ty, tz - 0.06, 0.14, MOUNT_RADIUS, m["dark"], axis="Z", bevel=0.02)

    # A few hardware modules on the flat crown of the sponsons, mirrored.
    for tx in rng.sample([-3.8, -3.4, -1.9, -1.5, 0.2], 3):
        kind = rng.random()
        for sp in spon:
            ty, tz = sp.params(tx)[2], top_z(sp, tx)
            if kind < 0.5:
                kit.box(tx, ty, tz - 0.03, 0.42, 0.32, 0.06, m["dark"])
                for i in range(4):
                    kit.box(tx - 0.15 + i * 0.1, ty, tz + 0.03, 0.04, 0.26, 0.03, m["bright"],
                            bevel=0.0)
            else:
                for i in (-1, 1):
                    kit.cyl(tx + i * 0.13, ty, tz - 0.03, 0.16, 0.11, m["dark"], axis="Z")

    if preview:
        for y in (0.0, 0.55, -0.55):
            kit.cyl(-7.6, y, 0.5, 2.35, 0.0, m["flame"], r2=0.22, bevel=0.0)
    return plates, mounts


def write_mounts(scene, mounts, image_path, json_path, seed, ship="corvette",
                 radius=MOUNT_RADIUS):
    """Write mount positions in Godot Sprite2D-local pixels: origin at the image centre,
    +x toward the nose, +y down. Multiply by the Sprite2D's scale to get node positions."""
    cam = scene.camera
    w, h = scene.render.resolution_x, scene.render.resolution_y

    def to_px(co):
        ndc = world_to_camera_view(scene, cam, co)  # (0,0) = bottom-left of frame
        return Vector((ndc.x * w - w / 2.0, (1.0 - ndc.y) * h - h / 2.0))

    out = []
    for name, x, y, z in mounts:
        centre = to_px(Vector((x, y, z)))
        edge = to_px(Vector((x + radius, y, z)))
        out.append({"id": name, "x": round(centre.x, 1), "y": round(centre.y, 1),
                    "radius": round((edge - centre).length, 1), "facing_deg": 0.0})
    data = {
        "ship": ship,
        "seed": seed,
        "image": os.path.basename(image_path),
        "width": w,
        "height": h,
        "coords": "pixels from image centre; +x = nose, +y = down (Godot Sprite2D local)",
        "mounts": out,
    }
    with open(json_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    LOG.info("wrote %s (%d mounts)", json_path, len(out))


# ---------------------------------------------------------------- scene

def setup_scene(args):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 4
    scene.render.film_transparent = not args.preview
    scene.render.resolution_x = args.res
    scene.render.resolution_y = int(args.res * 0.72)
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"

    # Sky-to-ground gradient so the metal has something to reflect; flat black made it dull.
    world = bpy.data.worlds.new("world")
    scene.world = world
    try:
        world.use_nodes = True
    except AttributeError:
        pass
    nt = world.node_tree
    bg = nt.nodes["Background"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    r0, r1 = ramp.color_ramp.elements
    r0.position, r0.color = 0.0, (*hex_lin("#0a0c14"), 1.0)
    r1.position, r1.color = 1.0, (*hex_lin("#80858f"), 1.0)
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.6

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 14.0 if args.preview else 11.6
    cam = bpy.data.objects.new("cam", cam_data)
    cam.location = (-0.9 if args.preview else 0.0, 0.0, 30.0)
    scene.collection.objects.link(cam)
    scene.camera = cam

    for name, rot, energy, col in (
            ("key", (-52.0, -35.0, 0.0), 6.0, "#fff2e0"),
            ("fill", (30.0, 35.0, 0.0), 0.8, "#6080ff"),
            ("rim", (0.0, 60.0, 0.0), 1.5, "#ff7040")):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = energy
        ld.color = hex_lin(col)
        ld.angle = math.radians(3.0)
        lo = bpy.data.objects.new(name, ld)
        lo.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(lo)
    return scene


def main():
    args = parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="[kitbash] %(message)s")
    t0 = time.perf_counter()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = setup_scene(args)
    mats = {
        "hull": metal_mat("hull", "#62666b"),
        "hull2": metal_mat("hull2", "#5c6065"),
        "hull3": metal_mat("hull3", "#565a5f"),
        "dark": metal_mat("dark", "#34353a", rough=0.5),
        "bright": metal_mat("bright", "#b8bcc4", metal=0.9, rough=0.22, grime=0.9),
        "cyan": emit_mat("cyan", "#3ff2ff", 6.0),
        "red": emit_mat("red", "#ff3b3b", 14.0),
        "yellow": emit_mat("yellow", "#ffd23a", 10.0),
        "engine": emit_mat("engine", "#9ff8ff", 25.0),
        "flame": flame_mat("flame", "#ff9a3c", 14.0),
    }
    kit = Kit()
    plates, mounts = build_corvette(kit, random.Random(args.seed), mats, args.preview)
    if args.preview:
        bd = bpy.data.objects.new("backdrop", bpy.data.meshes.new("backdrop"))
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30.0)
        bmesh.ops.translate(bm, vec=(0.0, 0.0, -3.0), verts=bm.verts)
        bm.to_mesh(bd.data)
        bm.free()
        bd.data.materials.append(backdrop_mat())
        scene.collection.objects.link(bd)
    t1 = time.perf_counter()
    LOG.debug("built %d objects (%d plates) in %.2fs", kit.count, plates, t1 - t0)
    scene.render.filepath = args.out
    bpy.ops.render.render(write_still=True)
    LOG.info("wrote %s (render %.1fs)", args.out, time.perf_counter() - t1)
    write_mounts(scene, mounts, args.out, os.path.splitext(args.out)[0] + ".mounts.json",
                 args.seed)


if __name__ == "__main__":  # importable by the other hull scripts
    main()
