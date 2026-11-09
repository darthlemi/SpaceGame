"""Procedural starfield tileset generator, run inside Blender's Python (bpy + numpy).

Usage:
    blender --background --python starfield_generator.py

Generates 25 base density tiles (Sparse/Light/Medium/Dense/Clustered x5),
3 transparent parallax depth layers, and a set of preview composites, under
art/blender/Starfield/.
"""

import os
import random
import shutil
import math

import bpy
import numpy as np

# ---------------------------------------------------------------------------
# Global config
# ---------------------------------------------------------------------------

RES = 1024  # tile resolution: see note in final report (crisp AA stars, cheap VRAM, 4x4 grid ~= 4096 ~ the requested 4000x4000 conceptual background)

OUT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Starfield")

BG_COLOR = np.array([2.0, 4.0, 11.0]) / 255.0  # near-black, subtle navy tint

# (weight, rgb0_1, name)
BASE_PALETTE = [
    (0.40, (1.00, 1.00, 1.00), "white"),
    (0.25, (0.85, 0.92, 1.00), "cool_white"),
    (0.10, (0.75, 0.85, 1.00), "blue_white"),
    (0.12, (1.00, 0.95, 0.80), "pale_yellow"),
    (0.07, (1.00, 0.85, 0.55), "warm_yellow"),
    (0.04, (1.00, 0.65, 0.35), "orange"),
    (0.02, (1.00, 0.45, 0.35), "red"),
]

DEEP_PALETTE = [
    (0.60, (1.00, 1.00, 1.00), "white"),
    (0.35, (0.85, 0.92, 1.00), "cool_white"),
    (0.05, (0.75, 0.85, 1.00), "blue_white"),
]

MID_PALETTE = [
    (0.35, (1.00, 1.00, 1.00), "white"),
    (0.25, (0.85, 0.92, 1.00), "cool_white"),
    (0.08, (0.75, 0.85, 1.00), "blue_white"),
    (0.15, (1.00, 0.95, 0.80), "pale_yellow"),
    (0.10, (1.00, 0.85, 0.55), "warm_yellow"),
    (0.05, (1.00, 0.65, 0.35), "orange"),
    (0.02, (1.00, 0.45, 0.35), "red"),
]

FORE_PALETTE = [
    (0.25, (1.00, 1.00, 1.00), "white"),
    (0.15, (0.85, 0.92, 1.00), "cool_white"),
    (0.05, (0.75, 0.85, 1.00), "blue_white"),
    (0.20, (1.00, 0.95, 0.80), "pale_yellow"),
    (0.18, (1.00, 0.85, 0.55), "warm_yellow"),
    (0.12, (1.00, 0.65, 0.35), "orange"),
    (0.05, (1.00, 0.45, 0.35), "red"),
]

# (weight, (radius_min, radius_max), name, glow_chance)
SIZE_TABLE = [
    (0.70, (0.6, 1.3), "tiny", 0.0),
    (0.20, (1.3, 2.2), "small", 0.0),
    (0.08, (2.2, 3.6), "medium", 0.15),
    (0.02, (3.6, 5.5), "large", 0.6),
]

BRIGHTNESS_BY_SIZE = {
    "tiny": (0.55, 0.85),
    "small": (0.60, 0.90),
    "medium": (0.70, 1.00),
    "large": (0.85, 1.00),
}


def weighted_pick(rng, items):
    total = sum(i[0] for i in items)
    r = rng.random() * total
    upto = 0.0
    for item in items:
        upto += item[0]
        if upto >= r:
            return item
    return items[-1]


def scatter_points(rng, n, w, h, min_dist):
    """Uniform scatter; dart-throws with a minimum spacing when n is small
    enough for rejection sampling to stay cheap, otherwise falls back to
    plain uniform placement (density is high enough that spacing is
    irrelevant to the look)."""
    pts = []
    if min_dist <= 0 or n > 300:
        for _ in range(n):
            pts.append((rng.uniform(0, w), rng.uniform(0, h)))
        return pts

    max_tries = 30
    min_dist2 = min_dist * min_dist
    for _ in range(n):
        placed = False
        for _try in range(max_tries):
            x, y = rng.uniform(0, w), rng.uniform(0, h)
            ok = True
            for (px, py) in pts:
                dx = min(abs(x - px), w - abs(x - px))
                dy = min(abs(y - py), h - abs(y - py))
                if dx * dx + dy * dy < min_dist2:
                    ok = False
                    break
            if ok:
                pts.append((x, y))
                placed = True
                break
        if not placed:
            pts.append((rng.uniform(0, w), rng.uniform(0, h)))
    return pts


def cluster_points(rng, n, cx, cy, sigma_x, sigma_y, angle, w, h):
    pts = []
    ca, sa = math.cos(angle), math.sin(angle)
    for _ in range(n):
        gx = rng.gauss(0, sigma_x)
        gy = rng.gauss(0, sigma_y)
        x = cx + gx * ca - gy * sa
        y = cy + gx * sa + gy * ca
        pts.append((x % w, y % h))
    return pts


def make_star(rng, x, y, palette, size_table=SIZE_TABLE, brightness_scale=1.0, glow_scale=1.0):
    weight, (rmin, rmax), size_name, glow_chance = weighted_pick(rng, size_table)
    radius = rng.uniform(rmin, rmax)
    _, color, _ = weighted_pick(rng, palette)
    blo, bhi = BRIGHTNESS_BY_SIZE[size_name]
    alpha_peak = min(1.0, rng.uniform(blo, bhi) * brightness_scale)
    glow = rng.random() < glow_chance * glow_scale
    glow_radius = radius * 2.6 if glow else 0.0
    glow_peak = rng.uniform(0.10, 0.22) if glow else 0.0
    return dict(x=x, y=y, radius=radius, color=color, alpha=alpha_peak,
                glow=glow, glow_radius=glow_radius, glow_peak=glow_peak)


def stamp_star(canvas_rgb, canvas_a, star, w, h):
    radius = star["radius"]
    reach = max(radius, star["glow_radius"]) * 2.4
    color = np.array(star["color"])

    offsets = []
    for ox in (-1, 0, 1):
        for oy in (-1, 0, 1):
            cx = star["x"] + ox * w
            cy = star["y"] + oy * h
            if cx + reach < 0 or cx - reach > w or cy + reach < 0 or cy - reach > h:
                continue
            offsets.append((cx, cy))

    for cx, cy in offsets:
        x0 = int(max(0, math.floor(cx - reach)))
        x1 = int(min(w, math.ceil(cx + reach)))
        y0 = int(max(0, math.floor(cy - reach)))
        y1 = int(min(h, math.ceil(cy + reach)))
        if x1 <= x0 or y1 <= y0:
            continue

        xs = np.arange(x0, x1) + 0.5
        ys = np.arange(y0, y1) + 0.5
        X, Y = np.meshgrid(xs, ys)
        dist2 = (X - cx) ** 2 + (Y - cy) ** 2

        core = star["alpha"] * np.exp(-dist2 / (2.0 * (radius * 0.6) ** 2))

        patch_rgb = canvas_rgb[y0:y1, x0:x1]
        patch_a = canvas_a[y0:y1, x0:x1]
        patch_rgb += core[..., None] * color

        if star["glow"]:
            glow_a = star["glow_peak"] * np.exp(-dist2 / (2.0 * (star["glow_radius"] * 0.5) ** 2))
            patch_rgb += glow_a[..., None] * color
            patch_a += np.clip(core + glow_a * 0.5, 0, 1)
        else:
            patch_a += core

        np.clip(patch_a, 0, 1, out=patch_a)


def render_tile(stars, w, h):
    canvas_rgb = np.zeros((h, w, 3), dtype=np.float64)
    canvas_a = np.zeros((h, w), dtype=np.float64)
    for star in stars:
        stamp_star(canvas_rgb, canvas_a, star, w, h)
    return canvas_rgb, canvas_a


def finalize_opaque(canvas_rgb, canvas_a):
    rgb = np.clip(BG_COLOR[None, None, :] + canvas_rgb, 0, 1)
    a = np.ones(canvas_rgb.shape[:2], dtype=np.float64)
    return rgb, a


def finalize_transparent(canvas_rgb, canvas_a):
    a = np.clip(canvas_a, 0, 1)
    eps = 1e-4
    rgb = np.clip(canvas_rgb / np.maximum(a[..., None], eps), 0, 1)
    rgb = np.where(a[..., None] > eps, rgb, 0.0)
    return rgb, a


_save_counter = [0]


def save_png(rgb, a, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    h, w = rgb.shape[:2]
    arr = np.empty((h, w, 4), dtype=np.float32)
    arr[..., :3] = rgb
    arr[..., 3] = a
    arr = np.flipud(arr)  # bpy image rows are bottom-to-top

    _save_counter[0] += 1
    name = f"starfield_export_{_save_counter[0]}"
    img = bpy.data.images.new(name, width=w, height=h, alpha=True)
    img.pixels.foreach_set(arr.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def to_u8(rgb, a):
    out = np.empty((*rgb.shape[:2], 4), dtype=np.uint8)
    out[..., :3] = np.clip(rgb * 255, 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(a * 255, 0, 255).astype(np.uint8)
    return out


def from_u8(arr):
    f = arr.astype(np.float64) / 255.0
    return f[..., :3], f[..., 3]


def downsample(u8, factor):
    h, w = u8.shape[:2]
    h2, w2 = h // factor, w // factor
    trimmed = u8[: h2 * factor, : w2 * factor].astype(np.float64)
    reshaped = trimmed.reshape(h2, factor, w2, factor, u8.shape[2])
    return reshaped.mean(axis=(1, 3)).astype(np.uint8)


# ---------------------------------------------------------------------------
# Category definitions for the 25 base tiles
# ---------------------------------------------------------------------------

CATEGORIES = [
    dict(name="Sparse", seed_base=1000, count_range=(15, 35), min_dist=30,
         cluster_fraction=0.0, cluster_count_range=(0, 0)),
    dict(name="Light", seed_base=2000, count_range=(45, 95), min_dist=18,
         cluster_fraction=0.0, cluster_count_range=(0, 0)),
    dict(name="Medium", seed_base=3000, count_range=(150, 260), min_dist=8,
         cluster_fraction=0.15, cluster_count_range=(1, 2)),
    dict(name="Dense", seed_base=4000, count_range=(450, 700), min_dist=0,
         cluster_fraction=0.0, cluster_count_range=(0, 0)),
    dict(name="Clustered", seed_base=5000, count_range=(120, 260), min_dist=14,
         cluster_fraction=0.7, cluster_count_range=(2, 5)),
]


def generate_category_tile(cfg, variation_index):
    seed = cfg["seed_base"] + variation_index
    rng = random.Random(seed)

    total = rng.randint(*cfg["count_range"])
    n_cluster = int(total * cfg["cluster_fraction"])
    n_scatter = total - n_cluster

    stars = []

    scatter_pts = scatter_points(rng, n_scatter, RES, RES, cfg["min_dist"])
    for (x, y) in scatter_pts:
        stars.append(make_star(rng, x, y, BASE_PALETTE))

    if n_cluster > 0:
        n_clusters = rng.randint(*cfg["cluster_count_range"])
        remaining = n_cluster
        for ci in range(n_clusters):
            take = remaining if ci == n_clusters - 1 else remaining // (n_clusters - ci)
            remaining -= take
            cx, cy = rng.uniform(0, RES), rng.uniform(0, RES)
            sigma_x = rng.uniform(RES * 0.02, RES * 0.07)
            sigma_y = sigma_x * rng.uniform(0.5, 1.0)
            angle = rng.uniform(0, math.pi)
            pts = cluster_points(rng, take, cx, cy, sigma_x, sigma_y, angle, RES, RES)
            for (x, y) in pts:
                stars.append(make_star(rng, x, y, BASE_PALETTE, brightness_scale=1.05))

    canvas_rgb, canvas_a = render_tile(stars, RES, RES)
    rgb, a = finalize_opaque(canvas_rgb, canvas_a)
    return rgb, a, seed, total


# ---------------------------------------------------------------------------
# Depth layer definitions
# ---------------------------------------------------------------------------

DEPTH_LAYERS = [
    dict(name="Deep_Background", seed=9001, count=800, min_dist=0,
         palette=DEEP_PALETTE,
         size_table=[(0.85, (0.4, 0.75), "tiny", 0.0), (0.15, (0.75, 0.95), "small", 0.0)],
         brightness_scale=0.45, glow_scale=0.0),
    dict(name="Mid_Distance", seed=9002, count=250, min_dist=6,
         palette=MID_PALETTE,
         size_table=[(0.55, (0.9, 1.6), "tiny", 0.0), (0.35, (1.6, 2.4), "small", 0.0),
                     (0.10, (2.4, 3.2), "medium", 0.20)],
         brightness_scale=0.75, glow_scale=0.6),
    dict(name="Foreground", seed=9003, count=60, min_dist=25,
         palette=FORE_PALETTE,
         size_table=[(0.40, (2.0, 3.0), "small", 0.0), (0.40, (3.0, 4.2), "medium", 0.25),
                     (0.20, (4.2, 5.5), "large", 0.7)],
         brightness_scale=0.95, glow_scale=1.0),
]


def generate_depth_layer(cfg):
    rng = random.Random(cfg["seed"])
    pts = scatter_points(rng, cfg["count"], RES, RES, cfg["min_dist"])
    stars = []
    for (x, y) in pts:
        stars.append(make_star(rng, x, y, cfg["palette"], size_table=cfg["size_table"],
                                brightness_scale=cfg["brightness_scale"], glow_scale=cfg["glow_scale"]))
    canvas_rgb, canvas_a = render_tile(stars, RES, RES)
    rgb, a = finalize_transparent(canvas_rgb, canvas_a)
    return rgb, a


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=== Starfield generator: starting ===")
    base_tiles_u8 = {}  # name -> uint8 RGBA array, for previews

    for cfg in CATEGORIES:
        for i in range(1, 6):
            rgb, a, seed, total = generate_category_tile(cfg, i)
            fname = f"{cfg['name'].lower()}_{i:02d}.png"
            path = os.path.join(OUT_ROOT, cfg["name"], fname)
            save_png(rgb, a, path)
            base_tiles_u8[f"{cfg['name']}_{i}"] = to_u8(rgb, a)
            print(f"  [{cfg['name']}] {fname} seed={seed} stars={total}")

    depth_u8 = {}
    for cfg in DEPTH_LAYERS:
        rgb, a = generate_depth_layer(cfg)
        path = os.path.join(OUT_ROOT, "Depth_Layers", cfg["name"], f"{cfg['name'].lower()}.png")
        save_png(rgb, a, path)
        depth_u8[cfg["name"]] = to_u8(rgb, a)
        print(f"  [Depth_Layers] {cfg['name']} seed={cfg['seed']} stars={cfg['count']}")

    # ---- Previews ---------------------------------------------------
    previews_dir = os.path.join(OUT_ROOT, "Previews")

    # 1) Contact sheet: 5 categories x 5 variations, downsampled thumbnails
    thumb_factor = 8
    thumb = RES // thumb_factor
    pad = 8
    rows, cols = 5, 5
    sheet_w = cols * thumb + (cols + 1) * pad
    sheet_h = rows * thumb + (rows + 1) * pad
    sheet = np.full((sheet_h, sheet_w, 4), (40, 42, 48, 255), dtype=np.uint8)

    for r, cfg in enumerate(CATEGORIES):
        for c in range(5):
            key = f"{cfg['name']}_{c + 1}"
            thumb_img = downsample(base_tiles_u8[key], thumb_factor)
            y0 = pad + r * (thumb + pad)
            x0 = pad + c * (thumb + pad)
            sheet[y0:y0 + thumb, x0:x0 + thumb] = thumb_img

    rgb, a = from_u8(sheet)
    save_png(rgb, a, os.path.join(previews_dir, "contact_sheet_all_textures.png"))
    print("  [Previews] contact_sheet_all_textures.png")

    # 2) Representative single-category previews (half-res)
    rep_factor = 2
    for cfg in CATEGORIES:
        key = f"{cfg['name']}_1"
        rep = downsample(base_tiles_u8[key], rep_factor)
        rgb, a = from_u8(rep)
        save_png(rgb, a, os.path.join(previews_dir, f"representative_{cfg['name'].lower()}.png"))
    print("  [Previews] representative_*.png (5)")

    # 3) Individual depth-layer previews (composited over BG for visibility)
    bg_u8 = np.array([*(BG_COLOR * 255), 255], dtype=np.uint8)
    for name, u8 in depth_u8.items():
        rgbf, af = from_u8(u8)
        comp = np.clip(BG_COLOR[None, None, :] + rgbf * af[..., None], 0, 1)
        save_png(comp, np.ones(comp.shape[:2]), os.path.join(previews_dir, f"layer_preview_{name.lower()}.png"))
    print("  [Previews] layer_preview_*.png (3)")

    # 4) Combined three-layer preview
    combined_rgb = np.zeros((RES, RES, 3), dtype=np.float64)
    for name, u8 in depth_u8.items():
        rgbf, af = from_u8(u8)
        combined_rgb += rgbf * af[..., None]
    combined = np.clip(BG_COLOR[None, None, :] + combined_rgb, 0, 1)
    save_png(combined, np.ones((RES, RES)), os.path.join(previews_dir, "layers_combined_preview.png"))
    print("  [Previews] layers_combined_preview.png")

    # 5) Large composite: 4x4 grid of base tiles (~4096x4096, downsampled to 2048)
    #    demonstrates placement at scale; one repeated tile proves seamless wrap-tiling.
    pick_keys = ["Dense_1", "Dense_2", "Dense_3", "Dense_4",
                 "Dense_5", "Dense_1", "Dense_2", "Dense_3",
                 "Dense_4", "Dense_5", "Dense_1", "Dense_2",
                 "Dense_3", "Dense_4", "Dense_5", "Dense_1"]
    grid = np.zeros((RES * 4, RES * 4, 4), dtype=np.uint8)
    for idx, key in enumerate(pick_keys):
        r, c = divmod(idx, 4)
        grid[r * RES:(r + 1) * RES, c * RES:(c + 1) * RES] = base_tiles_u8[key]
    grid_small = downsample(grid, 2)
    rgb, a = from_u8(grid_small)
    save_png(rgb, a, os.path.join(previews_dir, "composite_large_4000x4000.png"))
    print("  [Previews] composite_large_4000x4000.png")

    # 6) Seamless wrap-tiling proof: single tile repeated 3x3 at full res, downsampled
    seam_key = "Clustered_1"
    seam_grid = np.zeros((RES * 3, RES * 3, 4), dtype=np.uint8)
    for r in range(3):
        for c in range(3):
            seam_grid[r * RES:(r + 1) * RES, c * RES:(c + 1) * RES] = base_tiles_u8[seam_key]
    seam_small = downsample(seam_grid, 3)
    rgb, a = from_u8(seam_small)
    save_png(rgb, a, os.path.join(previews_dir, "seamless_tiling_proof.png"))
    print("  [Previews] seamless_tiling_proof.png")

    # Copy this script into Scripts/ as the delivered generation script
    scripts_dir = os.path.join(OUT_ROOT, "Scripts")
    os.makedirs(scripts_dir, exist_ok=True)
    shutil.copy(os.path.abspath(__file__), os.path.join(scripts_dir, "starfield_generator.py"))

    print("=== Starfield generator: done ===")


if __name__ == "__main__":
    main()
