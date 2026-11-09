"""Throwaway preview script: a few sample tiles and planet renders for the backgrounds
brainstorm. NOT part of the shipping pipeline -- just to show the user example output before
we lock the real design. Run headless in Blender 5.2.
"""
import argparse
import math
import os
import random
import sys

import bpy
import mathutils

sys.path.insert(0, r"C:\Users\corbi\Desktop\SpaceGame\art\blender")
import kitbash_corvette as kb  # noqa: E402


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--out-dir", required=True)
    return p.parse_args(argv)


# ---------------------------------------------------------------- tileable 2D images

def new_image(name, w, h):
    img = bpy.data.images.new(name, width=w, height=h, alpha=True)
    return img


def save(img, path):
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()


def wrapped_dist(dx, dy, w, h):
    dx = min(abs(dx), w - abs(dx))
    dy = min(abs(dy), h - abs(dy))
    return math.hypot(dx, dy)


def starfield_tile(path, w=256, h=256, seed=1, density=90, nebula_tint=None):
    """Dark base + scattered stars, wrapped so it tiles seamlessly. nebula_tint, if given,
    is (r, g, b, max_alpha) for a few soft wrapped blobs -- subtle, not a flat wash."""
    rng = random.Random(seed)
    px = [0.03, 0.035, 0.05, 1.0] * (w * h)

    blobs = []
    if nebula_tint:
        for _ in range(4):
            blobs.append((rng.uniform(0, w), rng.uniform(0, h), rng.uniform(40, 90)))
        r, g, b, max_a = nebula_tint
        for y in range(h):
            for x in range(w):
                a = 0.0
                for bx, by, rad in blobs:
                    d = wrapped_dist(x - bx, y - by, w, h)
                    a = max(a, max_a * max(0.0, 1.0 - d / rad) ** 2)
                if a > 0.0:
                    i = (y * w + x) * 4
                    px[i] = px[i] * (1 - a) + r * a
                    px[i + 1] = px[i + 1] * (1 - a) + g * a
                    px[i + 2] = px[i + 2] * (1 - a) + b * a

    for _ in range(density):
        x, y = rng.randrange(w), rng.randrange(h)
        size = rng.choices([0, 1, 2], weights=[70, 25, 5])[0]
        bright = rng.uniform(0.5, 1.0)
        warm = rng.random() < 0.2
        col = (bright, bright * (0.85 if warm else 1.0), bright * (1.0 if warm else 0.9))
        for oy in range(-size, size + 1):
            for ox in range(-size, size + 1):
                if ox * ox + oy * oy > size * size + 1:
                    continue
                xx, yy = (x + ox) % w, (y + oy) % h
                falloff = 1.0 if (ox, oy) == (0, 0) else 0.5
                i = (yy * w + xx) * 4
                px[i] = max(px[i], col[0] * falloff)
                px[i + 1] = max(px[i + 1], col[1] * falloff)
                px[i + 2] = max(px[i + 2], col[2] * falloff)

    img = new_image(os.path.basename(path), w, h)
    img.pixels.foreach_set(px)
    save(img, path)


# ---------------------------------------------------------------- planets (Cycles)

def planet_mat(name, base_hex, band_hex, emissive=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.0, 1.0, 2.2)  # stretch into bands
    nt.links.new(coord.outputs["Generated"], mapping.inputs["Vector"])
    tex = nt.nodes.new("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = 5.0
    tex.inputs["Detail"].default_value = 6.0
    tex.inputs["Roughness"].default_value = 0.6
    nt.links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    detail = nt.nodes.new("ShaderNodeTexNoise")
    detail.inputs["Scale"].default_value = 22.0
    detail.inputs["Detail"].default_value = 3.0
    nt.links.new(coord.outputs["Generated"], detail.inputs["Vector"])
    combine = nt.nodes.new("ShaderNodeMixRGB")
    combine.blend_type = "MULTIPLY"
    combine.inputs["Fac"].default_value = 0.35
    nt.links.new(tex.outputs["Fac"], combine.inputs["Color1"])
    nt.links.new(detail.outputs["Fac"], combine.inputs["Color2"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    e0, e1 = ramp.color_ramp.elements
    e0.position, e0.color = 0.3, (*kb.hex_lin(base_hex), 1.0)
    e1.position, e1.color = 0.7, (*kb.hex_lin(band_hex), 1.0)
    nt.links.new(combine.outputs["Color"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.15
    nt.links.new(detail.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.92
    bsdf.inputs["Specular IOR Level"].default_value = 0.08
    if emissive:
        bsdf.inputs["Emission Strength"].default_value = 0.4
        nt.links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def atmo_disc_mat(name, glow_hex, planet_radius, outer_radius, strength, cap=0.7):
    """Flat camera-facing halo disc, NOT a Fresnel-driven shell on the sphere itself.
    Fresnel/view-angle glow on a sphere in ortho view fundamentally can't give a wide soft
    haze: viewing angle is massively foreshortened near the silhouette, so almost the whole
    visible disc maps to near-facing angles and the entire angular range that would produce
    a gradient gets compressed into a sliver of screen pixels right at the rim -- it reads as
    a thin ring no matter how the falloff curve is reshaped. A flat disc lying in the same
    plane as the sphere's silhouette, graded by literal object-space radial distance, has no
    such compression: a 1-unit-wide radius band is a genuinely 1-unit-wide band on screen.
    Glow is 0 at the planet's own radius (so there's no seam at the surface) and fades
    smoothly out to `cap` opacity by `outer_radius`."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.blend_method = "BLEND"
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    trans = nt.nodes.new("ShaderNodeBsdfTransparent")
    emis = nt.nodes.new("ShaderNodeEmission")
    base = kb.hex_lin(glow_hex)
    pale = tuple(min(1.0, c * 0.88 + 0.12) for c in base)
    emis.inputs["Color"].default_value = (*pale, 1.0)
    emis.inputs["Strength"].default_value = strength

    coord = nt.nodes.new("ShaderNodeTexCoord")
    radius = nt.nodes.new("ShaderNodeVectorMath")
    radius.operation = "LENGTH"
    nt.links.new(coord.outputs["Object"], radius.inputs[0])

    # Wobble the radius with low-frequency noise so the glow's outer edge is an irregular,
    # cloud-like boundary instead of a perfect circle.
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2.4
    noise.inputs["Detail"].default_value = 3.5
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    wobble = nt.nodes.new("ShaderNodeMath")
    wobble.operation = "SUBTRACT"
    wobble.inputs[1].default_value = 0.5
    nt.links.new(noise.outputs["Fac"], wobble.inputs[0])
    wobble_scale = nt.nodes.new("ShaderNodeMath")
    wobble_scale.operation = "MULTIPLY"
    wobble_scale.inputs[1].default_value = (outer_radius - planet_radius) * 0.5
    nt.links.new(wobble.outputs["Value"], wobble_scale.inputs[0])
    perturbed_r = nt.nodes.new("ShaderNodeMath")
    perturbed_r.operation = "ADD"
    nt.links.new(radius.outputs["Value"], perturbed_r.inputs[0])
    nt.links.new(wobble_scale.outputs["Value"], perturbed_r.inputs[1])

    maprange = nt.nodes.new("ShaderNodeMapRange")
    maprange.interpolation_type = "SMOOTHSTEP"
    maprange.clamp = True
    maprange.inputs["From Min"].default_value = planet_radius
    maprange.inputs["From Max"].default_value = outer_radius
    maprange.inputs["To Min"].default_value = cap
    maprange.inputs["To Max"].default_value = 0.0
    nt.links.new(perturbed_r.outputs["Value"], maprange.inputs["Value"])

    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(maprange.outputs["Result"], mix.inputs["Fac"])
    nt.links.new(trans.outputs["BSDF"], mix.inputs[1])
    nt.links.new(emis.outputs["Emission"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return mat


def render_planet(path, base_hex, band_hex, res=512, emissive=False, ring=False):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 128
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"

    world = bpy.data.worlds.new("world")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0

    bpy.ops.mesh.primitive_uv_sphere_add(radius=3.0, location=(0, 0, 0), segments=128, ring_count=64)
    sphere = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    sphere.data.materials.append(planet_mat("planet", base_hex, band_hex, emissive))

    # Layered haze: flat camera-facing discs (see atmo_disc_mat) graded by literal radial
    # distance, not Fresnel/view-angle -- avoids the ortho-sphere foreshortening that made
    # every earlier Fresnel-based attempt read as a thin ring. Camera looks straight down -Z
    # from above, so a disc in the default XY plane (normal +Z) faces it directly and its
    # ortho projection is a perfect circle matching the sphere's silhouette exactly.
    outer_radius, strength = 3.9, 0.42
    bpy.ops.mesh.primitive_circle_add(radius=outer_radius, fill_type="NGON",
                                       vertices=96, location=(0, 0, 0.01))
    disc = bpy.context.active_object
    disc.data.materials.append(
        atmo_disc_mat("atmo", band_hex, 3.0, outer_radius, strength, cap=0.55))

    if ring:
        bpy.ops.mesh.primitive_torus_add(location=(0, 0, 0), major_radius=4.6, minor_radius=0.15,
                                          major_segments=64, minor_segments=8)
        tor = bpy.context.active_object
        bpy.ops.object.shade_smooth()
        tor.rotation_euler = (math.radians(70), 0, 0)
        tor.data.materials.append(planet_mat("ring", band_hex, base_hex))

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 8.0
    cam = bpy.data.objects.new("cam", cam_data)
    cam.location = (0, 0, 20)
    scene.collection.objects.link(cam)
    scene.camera = cam

    key = bpy.data.lights.new("key", "SUN")
    key.energy = 3.0
    key.angle = math.radians(20.0)
    key_o = bpy.data.objects.new("key", key)
    key_o.rotation_euler = (math.radians(-50), math.radians(-30), 0)
    scene.collection.objects.link(key_o)

    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def rock_mat(name, base_hex, rng):
    """High-poly weathered rock: smooth-shaded geometry + noise/bump surface detail,
    same recipe as the approved planet material, not the rejected faceted-plate look.
    Pointiness darkens craters and lightens worn ridges for a weathered read."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    coord = nt.nodes.new("ShaderNodeTexCoord")

    # Coarse mottling (mineral patches) x fine weathering grain.
    coarse = nt.nodes.new("ShaderNodeTexNoise")
    coarse.inputs["Scale"].default_value = rng.uniform(1.8, 2.6)
    coarse.inputs["Detail"].default_value = 4.0
    nt.links.new(coord.outputs["Object"], coarse.inputs["Vector"])
    fine = nt.nodes.new("ShaderNodeTexNoise")
    fine.inputs["Scale"].default_value = rng.uniform(22.0, 32.0)
    fine.inputs["Detail"].default_value = 10.0
    fine.inputs["Roughness"].default_value = 0.8
    nt.links.new(coord.outputs["Object"], fine.inputs["Vector"])

    # Sparse rust/mineral patches like the reference's copper streaks.
    rust = nt.nodes.new("ShaderNodeTexNoise")
    rust.inputs["Scale"].default_value = rng.uniform(1.2, 1.8)
    rust.inputs["Detail"].default_value = 3.0
    nt.links.new(coord.outputs["Object"], rust.inputs["Vector"])
    rust_ramp = nt.nodes.new("ShaderNodeValToRGB")
    rust_ramp.color_ramp.interpolation = "EASE"
    ru0, ru1 = rust_ramp.color_ramp.elements
    ru0.position, ru0.color = 0.52, (0.0, 0.0, 0.0, 1.0)
    ru1.position, ru1.color = 0.62, (1.0, 1.0, 1.0, 1.0)
    nt.links.new(rust.outputs["Fac"], rust_ramp.inputs["Fac"])

    # Craters are now real geometry (see add_craters), not a shader trick -- a shader bump
    # can't produce the true self-shadowed bowl interiors the reference needs.
    point = nt.nodes.new("ShaderNodeNewGeometry")

    # Crevice darkening from real ambient occlusion reads crater interiors as genuinely
    # dark, matching the reference's deep shadowed bowls.
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.6
    ao_ramp = nt.nodes.new("ShaderNodeValToRGB")
    ao0, ao1 = ao_ramp.color_ramp.elements
    ao0.position, ao0.color = 0.35, (0.4, 0.4, 0.4, 1.0)
    ao1.position, ao1.color = 0.9, (1.0, 1.0, 1.0, 1.0)
    nt.links.new(ao.outputs["AO"], ao_ramp.inputs["Fac"])

    # Patchy mineral variation: stay close to base_hex, a little darker/lighter either side
    # -- never brighter than a dusty rock should be.
    base = kb.hex_lin(base_hex)
    mottle_ramp = nt.nodes.new("ShaderNodeValToRGB")
    e0, e1 = mottle_ramp.color_ramp.elements
    e0.position, e0.color = (0.4, (base[0] * 0.65, base[1] * 0.65, base[2] * 0.72, 1.0))
    e1.position, e1.color = (0.6, (min(1.0, base[0] * 1.3), min(1.0, base[1] * 1.22),
                                    min(1.0, base[2] * 1.1), 1.0))
    nt.links.new(coarse.outputs["Fac"], mottle_ramp.inputs["Fac"])

    # Pointiness: mild darkening in creases, mild lightening on worn high points.
    wear_ramp = nt.nodes.new("ShaderNodeValToRGB")
    w0, w1 = wear_ramp.color_ramp.elements
    w0.position, w0.color = 0.3, (0.75, 0.75, 0.75, 1.0)
    w1.position, w1.color = 0.7, (1.15, 1.15, 1.15, 1.0)
    nt.links.new(point.outputs["Pointiness"], wear_ramp.inputs["Fac"])

    tint = nt.nodes.new("ShaderNodeMixRGB")
    tint.blend_type = "MULTIPLY"
    tint.inputs["Fac"].default_value = 0.6
    nt.links.new(mottle_ramp.outputs["Color"], tint.inputs["Color1"])
    nt.links.new(wear_ramp.outputs["Color"], tint.inputs["Color2"])

    rust_mix = nt.nodes.new("ShaderNodeMixRGB")
    rust_mix.blend_type = "MIX"
    rust_mix.inputs["Color2"].default_value = (0.42, 0.22, 0.1, 1.0)
    nt.links.new(tint.outputs["Color"], rust_mix.inputs["Color1"])
    rust_fac = nt.nodes.new("ShaderNodeMath")
    rust_fac.operation = "MULTIPLY"
    rust_fac.inputs[1].default_value = 0.35
    nt.links.new(rust_ramp.outputs["Color"], rust_fac.inputs[0])
    nt.links.new(rust_fac.outputs["Value"], rust_mix.inputs["Fac"])

    ao_tint = nt.nodes.new("ShaderNodeMixRGB")
    ao_tint.blend_type = "MULTIPLY"
    ao_tint.inputs["Fac"].default_value = 0.9
    nt.links.new(rust_mix.outputs["Color"], ao_tint.inputs["Color1"])
    nt.links.new(ao_ramp.outputs["Color"], ao_tint.inputs["Color2"])
    nt.links.new(ao_tint.outputs["Color"], bsdf.inputs["Base Color"])

    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.5
    bump.inputs["Distance"].default_value = 0.045
    nt.links.new(fine.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

    bsdf.inputs["Roughness"].default_value = 0.92

    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def add_craters(mesh_data, rng, count, radius_range=(0.3, 0.55), depth_range=(0.14, 0.24)):
    """Carve real bowl-shaped craters into the mesh: a parabolic dished floor out to 60% of
    the crater's angular radius, then a raised rim back out to 100%. Real geometry (not a
    shader bump) so interiors genuinely self-shadow and rims read crisp from any angle."""
    centers = []
    for _ in range(count):
        v = mathutils.Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        if v.length < 1e-6:
            continue
        v.normalize()
        centers.append((v, rng.uniform(*radius_range), rng.uniform(*depth_range)))

    for v in mesh_data.vertices:
        n = v.co.normalized()
        total = 0.0
        for c, ang_r, depth in centers:
            ang = math.acos(max(-1.0, min(1.0, n.dot(c))))
            t = ang / ang_r
            if t <= 0.6:
                tt = t / 0.6
                total += -depth * (1.0 - tt * tt)
            elif t <= 1.0:
                tt = (t - 0.6) / 0.4
                total += depth * 0.12 * math.sin(math.pi * tt)
        v.co *= (1.0 + total)


def render_asteroid_cluster(path, res=320, seed=1):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 96
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("world")
    scene.world = world
    world.use_nodes = True
    # A little ambient fill so self-shadowed creases read as dark, not pure black.
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.12

    rng = random.Random(seed)
    # One big primary rock plus 2-3 small escorts, like the station/ship kit's hero+detail
    # composition rather than a loose scatter.
    specs = [(1.6, (0, 0, 0))]
    for _ in range(rng.randint(2, 3)):
        ang = rng.uniform(0, math.tau)
        dist = rng.uniform(1.6, 2.6)
        specs.append((rng.uniform(0.35, 0.7), (math.cos(ang) * dist, math.sin(ang) * dist, 0)))

    base_hexes = ["#6e7076", "#64666c", "#787a80", "#5e6066"]
    for i, (radius, loc) in enumerate(specs):
        # High-poly smooth base: the irregular silhouette comes from gentle, low-frequency
        # Perlin noise (not periodic sine ridges, and not faceted low-poly geometry).
        bpy.ops.mesh.primitive_ico_sphere_add(radius=radius, subdivisions=5, location=loc)
        rock = bpy.context.active_object
        offset = mathutils.Vector((seed * 11 + i * 7, seed * 13 + i * 5, seed * 17 + i * 3))
        for v in rock.data.vertices:
            n = v.co.normalized()
            d1 = mathutils.noise.noise(n * 1.1 + offset)
            d2 = mathutils.noise.noise(n * 2.4 + offset) * 0.4
            v.co *= (1.0 + 0.13 * (d1 + d2))
        if radius > 1.0:
            add_craters(rock.data, rng, count=rng.randint(1, 2), radius_range=(0.3, 0.5),
                        depth_range=(0.16, 0.24))
            add_craters(rock.data, rng, count=rng.randint(4, 7), radius_range=(0.1, 0.22),
                        depth_range=(0.05, 0.12))
        else:
            add_craters(rock.data, rng, count=rng.randint(2, 4), radius_range=(0.14, 0.3),
                        depth_range=(0.06, 0.14))
        bpy.ops.object.shade_smooth()
        rock.rotation_euler = (rng.uniform(0, math.tau), rng.uniform(0, math.tau),
                                rng.uniform(0, math.tau))
        rock.data.materials.append(rock_mat(f"rock{i}", rng.choice(base_hexes), rng))

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 9.0
    cam = bpy.data.objects.new("cam", cam_data)
    cam.location = (0, 0, 20)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for name, rot, energy, col in (
            ("key", (-52.0, -35.0, 0.0), 6.0, "#fff2e0"),
            ("fill", (30.0, 35.0, 0.0), 1.4, "#6080ff"),
            ("rim", (0.0, 150.0, 0.0), 2.5, "#aab8ff")):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = energy
        ld.color = kb.hex_lin(col)
        lo = bpy.data.objects.new(name, ld)
        lo.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(lo)

    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def render_single_rock(path, res=384, seed=1, elongation=1.0):
    """A single large, rockier body -- for close foreground placement rather than a
    background cluster. Same material recipe; bigger, chunkier, more elongated silhouette,
    and more surface detail since it fills much more of the frame."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 128
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("world")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.12

    rng = random.Random(seed + 900)
    base_hexes = ["#6e7076", "#64666c", "#787a80", "#5e6066"]

    radius = rng.uniform(2.2, 2.7)
    bpy.ops.mesh.primitive_ico_sphere_add(radius=radius, subdivisions=6, location=(0, 0, 0))
    rock = bpy.context.active_object
    offset = mathutils.Vector((seed * 19 + 3, seed * 23 + 7, seed * 29 + 11))
    for v in rock.data.vertices:
        n = v.co.normalized()
        # Low-frequency chunky lobes (bigger body reads lumpy, not perfectly round) plus
        # the same mid-frequency weathering noise as the cluster rocks.
        d0 = mathutils.noise.noise(n * 0.7 + offset) * 0.6
        d1 = mathutils.noise.noise(n * 1.3 + offset)
        d2 = mathutils.noise.noise(n * 2.6 + offset) * 0.35
        v.co *= (1.0 + 0.17 * (d0 + d1 + d2))
    add_craters(rock.data, rng, count=rng.randint(2, 3), radius_range=(0.28, 0.42),
                depth_range=(0.16, 0.22))
    add_craters(rock.data, rng, count=rng.randint(8, 13), radius_range=(0.08, 0.2),
                depth_range=(0.04, 0.1))
    # Stretch into a potato/elongated silhouette rather than a round boulder.
    stretch = mathutils.Matrix.Diagonal((elongation, 1.0 / math.sqrt(elongation), 0.92)).to_4x4()
    rock.data.transform(stretch)
    bpy.ops.object.shade_smooth()
    rock.rotation_euler = (rng.uniform(0, math.tau), rng.uniform(0, math.tau),
                            rng.uniform(0, math.tau))
    rock.data.materials.append(rock_mat("rock_big", rng.choice(base_hexes), rng))

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 7.8
    cam = bpy.data.objects.new("cam", cam_data)
    cam.location = (0, 0, 20)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for name, rot, energy, col in (
            ("key", (-52.0, -35.0, 0.0), 6.0, "#fff2e0"),
            ("fill", (30.0, 35.0, 0.0), 1.4, "#6080ff"),
            ("rim", (0.0, 150.0, 0.0), 2.5, "#aab8ff")):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = energy
        ld.color = kb.hex_lin(col)
        lo = bpy.data.objects.new(name, ld)
        lo.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(lo)

    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    args = parse_args()
    os.makedirs(args.out_dir, exist_ok=True)

    # Hazy-atmosphere re-pass on the 4 approved planet/moon samples (layered shells
    # replacing the single tight Fresnel rim -- see atmo_haze_mat).
    for name, base_hex, band_hex, kwargs in (
            ("planet_gas_purple", "#4a2f6e", "#8a6fc9", {}),
            ("planet_gas_red_ring", "#6e2f1f", "#c96a3f", {"ring": True}),
            ("planet_gas_red", "#6e2f1f", "#c96a3f", {}),
            ("planet_earthlike", "#1f4f7a", "#3f8a52", {}),
            ("moon_icy", "#9fb3c2", "#e8f2f7", {"emissive": False})):
        render_planet(os.path.join(args.out_dir, f"{name}.png"), base_hex, band_hex, **kwargs)

    print("done:", args.out_dir)


main()
