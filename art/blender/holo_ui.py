"""Cobalt holo-glass UI chrome: the five 9-slice textures that assets\\ui\\theme.tres uses.

Flat emissive quads under an orthographic camera at 1 Blender unit = 1 output px, so every
line lands on whole pixels. Glow is built from geometry (1 px falloff strips of emission
mixed with transparency), not the compositor Glare node, which drops glow on a transparent
film. Standard view transform + emission strength 1 make an output px equal its hex.

Run headless in Blender 5.2; see art\\README.md for the command.

9-slice contract (keep in sync with theme.tres texture_margin_*): everything that is not a
straight run lives inside the margins, and the tiled button centre is a whole number of
6 px dash periods, so tiling never smears or seams.
"""
import argparse
import logging
import os
import sys
import time

import bmesh
import bpy

LOG = logging.getLogger("holo_ui")

ACCENT = "#3f9fff"
DIM_ACCENT = "#1a4e8a"
GLASS = "#050c18"

BUTTON_SIZE = 24          # px; texture_margin 6 leaves a 12 px tiled centre
BUTTON_OUTLINE_INSET = 3
BUTTON_FILL_ALPHA = 0.35
PRESSED_FILL_ALPHA = 0.4
BUTTON_OUTER_GLOW = (0.6, 0.4, 0.2)  # alpha per px, moving outward from the outline
BUTTON_INNER_GLOW = (0.45, 0.2)      # inward; 2 px so the glow ends at the 6 px margin
DASH = 3                             # disabled outline: 3 px on, 3 px off (6 px period)
DASH_ALPHA = 0.6
BUTTON_STATES = ("normal", "hover", "pressed", "disabled")

PANEL_SIZE = 66           # px; texture_margin 15 leaves a 36 px tiled centre
PANEL_BORDER_INSET = 4
PANEL_BORDER_ALPHA = 0.35
PANEL_OUTER_GLOW = (0.2, 0.12, 0.06)
PANEL_INNER_GLOW = (0.25, 0.17, 0.1, 0.05)
BRACKET_INSET = 3         # 2 px thick L-brackets over the border's outer edge
BRACKET_THICK = 2
BRACKET_LEN = 12          # ends at px 14, inside the 15 px margin

# Draw order, bottom to top; the camera looks down -Z.
Z_FILL, Z_GLOW, Z_LINE, Z_BRACKET = range(4)


def hex_lin(h):
    """sRGB hex -> linear RGB tuple (node colors are linear)."""
    out = []
    for i in (1, 3, 5):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


class Canvas:
    """Collects axis-aligned px rects in image space (origin top-left, y down) and builds
    one mesh per (colour, alpha, layer), so a texture is a handful of objects."""

    def __init__(self, width: int, height: int):
        self.width = width
        self.height = height
        self.rects = {}

    def rect(self, x: int, y: int, w: int, h: int, hexcol: str, alpha: float, z: int):
        if w > 0 and h > 0:
            self.rects.setdefault((hexcol, alpha, z), []).append((x, y, w, h))

    def ring(self, inset: int, hexcol: str, alpha: float, z: int):
        """1 px rectangle outline `inset` px in from the texture edge, corners drawn once."""
        span_w = self.width - 2 * inset
        span_h = self.height - 2 * inset
        if span_w <= 0 or span_h <= 0:
            return
        self.rect(inset, inset, span_w, 1, hexcol, alpha, z)
        self.rect(inset, self.height - inset - 1, span_w, 1, hexcol, alpha, z)
        self.rect(inset, inset + 1, 1, span_h - 2, hexcol, alpha, z)
        self.rect(self.width - inset - 1, inset + 1, 1, span_h - 2, hexcol, alpha, z)

    def glow(self, inset: int, hexcol: str, outer, inner, z: int):
        """Falloff rings either side of the outline at `inset`."""
        for k, a in enumerate(outer, start=1):
            self.ring(inset - k, hexcol, a, z)
        for k, a in enumerate(inner, start=1):
            self.ring(inset + k, hexcol, a, z)

    def flush(self):
        mats = {}
        for (hexcol, alpha, z), rects in self.rects.items():
            key = (hexcol, alpha)
            if key not in mats:
                mats[key] = glass_mat(hexcol, alpha)
            bm = bmesh.new()
            for x, y, w, h in rects:
                y0 = self.height - y - h  # image y-down -> Blender y-up
                vs = [bm.verts.new((px, py, float(z)))
                      for px, py in ((x, y0), (x + w, y0), (x + w, y0 + h), (x, y0 + h))]
                bm.faces.new(vs)
            mesh = bpy.data.meshes.new("holo")
            bm.to_mesh(mesh)
            bm.free()
            mesh.materials.append(mats[key])
            obj = bpy.data.objects.new("holo", mesh)
            bpy.context.scene.collection.objects.link(obj)
        LOG.debug("canvas: %d rects in %d objects, %d materials",
                  sum(len(r) for r in self.rects.values()), len(self.rects), len(mats))


def glass_mat(hexcol, alpha):
    """Emission at strength 1 mixed with transparency at `alpha` (partial-alpha px)."""
    m = bpy.data.materials.new("holo_%s_%.2f" % (hexcol.lstrip("#"), alpha))
    try:
        m.use_nodes = True
    except AttributeError:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*hex_lin(hexcol), 1.0)
    em.inputs["Strength"].default_value = 1.0
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.inputs["Fac"].default_value = alpha
    nt.links.new(tr.outputs["BSDF"], mix.inputs[1])
    nt.links.new(em.outputs["Emission"], mix.inputs[2])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return m


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out-dir", required=True)
    p.add_argument("--pressed-color", default="#eaf6ff", help="pressed fill + outline hex")
    p.add_argument("--panel-alpha", type=float, default=0.8, help="panel glass opacity")
    p.add_argument("--samples", type=int, default=16)
    p.add_argument("--verbose", action="store_true")
    args = p.parse_args(argv)
    if len(args.pressed_color) != 7 or not args.pressed_color.startswith("#"):
        p.error("--pressed-color must be #rrggbb, got %r" % args.pressed_color)
    if not 0.0 <= args.panel_alpha <= 1.0:
        p.error("--panel-alpha must be in [0, 1], got %s" % args.panel_alpha)
    return args


def setup_scene(width: int, height: int, samples: int):
    """Empty scene, transparent Cycles film, ortho camera framing [0,w] x [0,h] 1:1."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = False
    scene.cycles.filter_width = 0.01  # minimum: px-aligned edges stay hard
    scene.cycles.transparent_max_bounces = 16  # stacked fill/glow/line layers
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"  # AgX shifts the palette hex
    scene.view_settings.look = "None"
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = float(max(width, height))
    cam = bpy.data.objects.new("cam", cam_data)
    cam.location = (width / 2.0, height / 2.0, 10.0)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return scene


def build_panel(alpha: float):
    """Navy glass, a faint cobalt border + glow, bright corner brackets."""
    c = Canvas(PANEL_SIZE, PANEL_SIZE)
    b = PANEL_BORDER_INSET
    inner = PANEL_SIZE - 2 * (b + 1)
    c.rect(b + 1, b + 1, inner, inner, GLASS, alpha, Z_FILL)
    c.glow(b, ACCENT, PANEL_OUTER_GLOW, PANEL_INNER_GLOW, Z_GLOW)
    c.ring(b, ACCENT, PANEL_BORDER_ALPHA, Z_LINE)
    far = PANEL_SIZE - BRACKET_INSET
    for x0, y0, sx, sy in ((BRACKET_INSET, BRACKET_INSET, 1, 1), (far, BRACKET_INSET, -1, 1),
                           (BRACKET_INSET, far, 1, -1), (far, far, -1, -1)):
        xa = x0 if sx > 0 else x0 - BRACKET_LEN
        ya = y0 if sy > 0 else y0 - BRACKET_THICK
        c.rect(xa, ya, BRACKET_LEN, BRACKET_THICK, ACCENT, 1.0, Z_BRACKET)
        xb = x0 if sx > 0 else x0 - BRACKET_THICK
        yb = (y0 + BRACKET_THICK) if sy > 0 else (y0 - BRACKET_LEN)
        c.rect(xb, yb, BRACKET_THICK, BRACKET_LEN - BRACKET_THICK, ACCENT, 1.0, Z_BRACKET)
    c.flush()


def build_button(state: str, pressed_hex: str):
    """One button state; see BUTTON_STATES."""
    if state not in BUTTON_STATES:
        raise ValueError("unknown button state %r" % state)
    c = Canvas(BUTTON_SIZE, BUTTON_SIZE)
    o = BUTTON_OUTLINE_INSET
    span = BUTTON_SIZE - 2 * o
    if state == "pressed":
        c.rect(o, o, span, span, pressed_hex, PRESSED_FILL_ALPHA, Z_FILL)
    else:
        c.rect(o, o, span, span, GLASS, BUTTON_FILL_ALPHA, Z_FILL)

    if state == "normal":
        c.ring(o, DIM_ACCENT, 1.0, Z_LINE)
    elif state in ("hover", "pressed"):
        col = ACCENT if state == "hover" else pressed_hex
        c.glow(o, col, BUTTON_OUTER_GLOW, BUTTON_INNER_GLOW, Z_GLOW)
        c.ring(o, col, 1.0, Z_LINE)
    else:
        # Absolute-position phase keeps the dashes continuous across the 9-slice joins.
        far = BUTTON_SIZE - o - 1
        for p in range(o, BUTTON_SIZE - o):
            if (p // DASH) % 2 == 0:
                c.rect(p, o, 1, 1, DIM_ACCENT, DASH_ALPHA, Z_LINE)
                c.rect(p, far, 1, 1, DIM_ACCENT, DASH_ALPHA, Z_LINE)
                if o < p < far:
                    c.rect(o, p, 1, 1, DIM_ACCENT, DASH_ALPHA, Z_LINE)
                    c.rect(far, p, 1, 1, DIM_ACCENT, DASH_ALPHA, Z_LINE)
    c.flush()


def render(out_path: str):
    scene = bpy.context.scene
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)


def main():
    args = parse_args()
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="[holo_ui] %(message)s")
    os.makedirs(args.out_dir, exist_ok=True)
    jobs = [("panel_frame", PANEL_SIZE, lambda: build_panel(args.panel_alpha))]
    jobs += [("button_" + s, BUTTON_SIZE, lambda s=s: build_button(s, args.pressed_color))
             for s in BUTTON_STATES]
    t_all = time.perf_counter()
    for name, size, build in jobs:
        t0 = time.perf_counter()
        setup_scene(size, size, args.samples)
        build()
        out = os.path.join(args.out_dir, name + ".png")
        render(out)
        LOG.debug("%s: %dx%d in %.2fs", name, size, size, time.perf_counter() - t0)
        LOG.info("wrote %s", out)
    LOG.debug("total %.2fs for %d textures", time.perf_counter() - t_all, len(jobs))


if __name__ == "__main__":
    main()
