import bpy, bmesh, math, random, os
from mathutils import Vector, noise as mnoise

OUT_DIR = r"C:\Users\corbi\AppData\Local\Temp\claude\C--Users-corbi-Desktop-SpaceGame\e6e81089-25d1-44c7-a796-a1b6c927da15\scratchpad\asteroid"
RENDER_DIR = os.path.join(OUT_DIR, "renders", "variants")
os.makedirs(RENDER_DIR, exist_ok=True)


def frac_noise(p, octaves=4, lac=2.0, gain=0.5):
    amp = 1.0
    freq = 1.0
    total = 0.0
    norm = 0.0
    for _ in range(octaves):
        total += mnoise.noise(p * freq) * amp
        norm += amp
        amp *= gain
        freq *= lac
    return total / norm


def triangle_wave(x):
    x = x - math.floor(x)
    return 1.0 - abs(2.0 * x - 1.0)


def tangent_basis(n):
    up = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))
    u = up.cross(n).normalized()
    w = n.cross(u).normalized()
    return u, w


def build_rock(name, seed, radius, location, elongate, big_craters, n_small, subdiv=6, lump=1.0):
    random.seed(seed)
    mnoise.seed_set(seed)

    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=(0, 0, 0))
    obj = bpy.context.object
    obj.name = name
    mesh = obj.data

    for v in mesh.vertices:
        d = v.co.normalized()
        p = d * 1.6 + Vector((seed * 3.1, seed * 1.7, seed * 2.3))
        lowfreq = frac_noise(p, octaves=3, lac=2.1, gain=0.55)
        midfreq = frac_noise(p * 3.3 + Vector((9.2, 1.7, 5.4)), octaves=3, lac=2.3, gain=0.5)
        disp = 1.0 + (lowfreq * 0.11 + midfreq * 0.025) * lump
        v.co = d * (radius * disp)

    obj.scale = elongate
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mesh.update()

    for c in big_craters:
        u, w = tangent_basis(c["center"])
        c["u"] = u
        c["w"] = w

    crater_shade = {}
    for vi, v in enumerate(mesh.vertices):
        dirn = v.co.normalized()
        base_len = v.co.length
        total_disp = 0.0
        shade_val = 0.0
        for c in big_craters:
            center = c["center"]
            d = (dirn - center).length
            R = c["R"]

            mask = 0.0
            if c["rays"] > 0:
                local = dirn - center
                lu = local.dot(c["u"])
                lw = local.dot(c["w"])
                theta = math.atan2(lw, lu) / (2 * math.pi)
                tri = triangle_wave(theta * c["rays"])
                jitter = frac_noise(dirn * 8.0 + center * 13.0, octaves=2) * c["jitter"]
                mask = max(0.0, tri + jitter)
                mask = mask ** c["sharp"]

            r_norm = d / R
            if r_norm > 1.05 + (c["ray_len"] if c["rays"] > 0 else 0.0):
                continue

            if r_norm <= 1.0:
                bowl = -c["depth"] * (1.0 - r_norm * r_norm)
                if r_norm < 0.25:
                    bowl = -c["depth"] * 0.97
                total_disp += bowl
                cand = -((1.0 - r_norm) * 0.9 + 0.1)
                if abs(cand) > abs(shade_val):
                    shade_val = cand
                # the ray/tooth mask used to also darken-and-lighten the floor and rim in
                # alternating wedges (cand_stripe / cand2 below); even heavily turned down
                # that reads as a ring of "teeth" around the crater mouth, so the shading is
                # now purely radial (cand above) -- smooth bowl, no ray pattern in the shading.

            rim_band = math.exp(-((r_norm - 1.0) ** 2) / 0.006)
            if c["rays"] > 0:
                tooth = max(0.0, mask - 0.15) * rim_band
                total_disp += c["rim"] * tooth
            else:
                total_disp += c["rim"] * rim_band * 0.35

        grain = frac_noise(dirn * 14.0 + Vector((3.1, 7.7, 2.2)) + Vector((seed, seed, seed)),
                            octaves=3, lac=2.2, gain=0.5) * 0.006
        total_disp += grain

        # Overlapping craters sum their bowls/rims uncapped above. Several bowls stacking can
        # push a vertex past zero (flipping that patch through the body's center); several rim
        # bulges stacking can push it far out past the silhouette -- both read as a thin
        # ribbed "fin" jutting off the body. Clamp both directions.
        total_disp = max(-base_len * 0.55, min(total_disp, base_len * 0.12))
        v.co = dirn * (base_len + total_disp)
        crater_shade[vi] = max(-1.0, min(shade_val, 1.0))

    mesh.update()

    if "CraterShade" not in mesh.color_attributes:
        mesh.color_attributes.new(name="CraterShade", type='FLOAT_COLOR', domain='POINT')
    cattr = mesh.color_attributes["CraterShade"]
    for vi in range(len(mesh.vertices)):
        val = crater_shade.get(vi, 0.0)
        stored = val * 0.5 + 0.5
        cattr.data[vi].color = (stored, stored, stored, 1.0)

    bpy.ops.object.shade_smooth()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    obj.location = location
    return obj


def small_craters_list(n, obj_radius=1.0, seed=0):
    # R is an angular (unit-sphere) size so craters cover the same relative fraction of
    # surface on any object; depth/rim are absolute so they scale with the object's radius.
    rng = random.Random(seed * 991 + 7)
    out = []
    placed = []
    attempts = 0
    while len(out) < n and attempts < n * 20:
        attempts += 1
        c = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized()
        R = rng.uniform(0.045, 0.13)
        # reject centers too close to an already-placed crater -- unrestricted random
        # placement lets several bowls stack on top of each other by chance and that reads
        # as a jagged ridge, especially in silhouette.
        if any((c - pc).length < (R + pR) * 0.85 for pc, pR in placed):
            continue
        placed.append((c, R))
        out.append(dict(center=c, R=R, depth=obj_radius * R * rng.uniform(0.16, 0.3),
                         rim=obj_radius * R * 0.08, rays=0, ray_len=0.0))
    return out


def make_material():
    mat = bpy.data.materials.new("AsteroidRock")
    mat.use_nodes = True
    nt = mat.node_tree
    nodes = nt.nodes
    links = nt.links
    for n in list(nodes):
        nodes.remove(n)

    out = nodes.new("ShaderNodeOutputMaterial")
    out.location = (900, 0)
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (650, 0)
    bsdf.inputs["Roughness"].default_value = 0.92
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    texcoord = nodes.new("ShaderNodeTexCoord")
    texcoord.location = (-900, 0)
    mapping = nodes.new("ShaderNodeMapping")
    mapping.location = (-700, 0)
    links.new(texcoord.outputs["Object"], mapping.inputs["Vector"])

    patchnoise = nodes.new("ShaderNodeTexNoise")
    patchnoise.location = (-500, 150)
    patchnoise.inputs["Scale"].default_value = 3.4
    patchnoise.inputs["Detail"].default_value = 6.0
    patchnoise.inputs["Roughness"].default_value = 0.6
    links.new(mapping.outputs["Vector"], patchnoise.inputs["Vector"])

    patchramp = nodes.new("ShaderNodeValToRGB")
    patchramp.location = (-300, 150)
    patchramp.color_ramp.elements[0].position = 0.455
    patchramp.color_ramp.elements[0].color = (0.065, 0.075, 0.115, 1)
    patchramp.color_ramp.elements[1].position = 0.655
    patchramp.color_ramp.elements[1].color = (0.27, 0.26, 0.245, 1)
    links.new(patchnoise.outputs["Fac"], patchramp.inputs["Fac"])

    rustnoise = nodes.new("ShaderNodeTexNoise")
    rustnoise.location = (-500, -150)
    rustnoise.inputs["Scale"].default_value = 2.6
    rustnoise.inputs["Detail"].default_value = 5.0
    links.new(mapping.outputs["Vector"], rustnoise.inputs["Vector"])

    rustramp = nodes.new("ShaderNodeValToRGB")
    rustramp.location = (-300, -150)
    rustramp.color_ramp.elements[0].position = 0.5675
    rustramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    rustramp.color_ramp.elements[1].position = 0.6475
    rustramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    links.new(rustnoise.outputs["Fac"], rustramp.inputs["Fac"])

    rustcolor = nodes.new("ShaderNodeRGB")
    rustcolor.location = (-300, -320)
    rustcolor.outputs[0].default_value = (0.42, 0.22, 0.08, 1)

    mixrust = nodes.new("ShaderNodeMixRGB")
    mixrust.location = (-80, 0)
    mixrust.blend_type = 'MIX'
    links.new(patchramp.outputs["Color"], mixrust.inputs["Color1"])
    links.new(rustcolor.outputs[0], mixrust.inputs["Color2"])
    links.new(rustramp.outputs["Color"], mixrust.inputs["Fac"])

    specknoise = nodes.new("ShaderNodeTexNoise")
    specknoise.location = (-500, -500)
    specknoise.inputs["Scale"].default_value = 38.5
    specknoise.inputs["Detail"].default_value = 8.0
    links.new(mapping.outputs["Vector"], specknoise.inputs["Vector"])

    speckmix = nodes.new("ShaderNodeMixRGB")
    speckmix.location = (120, 0)
    speckmix.blend_type = 'MULTIPLY'
    speckmix.inputs["Fac"].default_value = 0.21
    links.new(mixrust.outputs["Color"], speckmix.inputs["Color1"])
    links.new(specknoise.outputs["Fac"], speckmix.inputs["Color2"])

    attr = nodes.new("ShaderNodeAttribute")
    attr.location = (-500, -700)
    attr.attribute_name = "CraterShade"

    craterdark = nodes.new("ShaderNodeMixRGB")
    craterdark.location = (320, 0)
    craterdark.blend_type = 'OVERLAY'
    craterdark.inputs["Fac"].default_value = 0.95
    links.new(speckmix.outputs["Color"], craterdark.inputs["Color1"])
    links.new(attr.outputs["Color"], craterdark.inputs["Color2"])
    links.new(craterdark.outputs["Color"], bsdf.inputs["Base Color"])

    bumpnoise = nodes.new("ShaderNodeTexNoise")
    bumpnoise.location = (-500, -950)
    bumpnoise.inputs["Scale"].default_value = 50.0
    bumpnoise.inputs["Detail"].default_value = 9.0
    links.new(mapping.outputs["Vector"], bumpnoise.inputs["Vector"])

    bump = nodes.new("ShaderNodeBump")
    bump.location = (300, -400)
    bump.inputs["Strength"].default_value = 0.14
    links.new(bumpnoise.outputs["Fac"], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def setup_world():
    world = bpy.data.worlds.new("Space")
    bpy.context.scene.world = world
    world.use_nodes = True
    wnt = world.node_tree
    for n in list(wnt.nodes):
        wnt.nodes.remove(n)
    wbg = wnt.nodes.new("ShaderNodeBackground")
    wbg.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1)
    wbg.inputs["Strength"].default_value = 1.0
    wout = wnt.nodes.new("ShaderNodeOutputWorld")
    wnt.links.new(wbg.outputs["Background"], wout.inputs["Surface"])


def add_area(name, loc, energy, size, rot, color=(1, 1, 1)):
    bpy.ops.object.light_add(type='AREA', location=loc)
    l = bpy.context.object
    l.name = name
    l.data.energy = energy
    l.data.size = size
    l.data.color = color
    l.rotation_euler = rot
    return l


def add_lights():
    add_area("Key", (3.2, -2.6, 2.6), 950, 3.0, (math.radians(55), 0, math.radians(55)))
    add_area("Fill", (-3.0, 2.0, -1.0), 55, 3.5, (math.radians(-60), 0, math.radians(-130)), color=(0.6, 0.7, 1.0))
    add_area("Rim", (-1.5, -3.5, -2.0), 260, 1.8, (math.radians(-100), 0, math.radians(20)), color=(0.8, 0.85, 1.0))
    add_area("Ambient", (0, 0, 4.5), 40, 6.0, (0, 0, 0), color=(0.75, 0.8, 0.9))


def frame_camera(objs):
    pts = []
    for obj in objs:
        bbox = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
        pts.extend(bbox)
    center = sum(pts, Vector((0, 0, 0))) / len(pts)
    radius = max((p - center).length for p in pts)

    cam_dir = Vector((0, -1, 0.1)).normalized()
    lens_mm = 60
    sensor_h = 45.0
    fov = 2 * math.atan((sensor_h / 2) / lens_mm)
    dist = (radius * 1.1) / math.sin(fov / 2)
    cam_loc = center + cam_dir * dist

    bpy.ops.object.camera_add(location=cam_loc)
    cam = bpy.context.object
    cam.name = "Camera"
    cam.data.lens = lens_mm
    cam.data.sensor_fit = 'VERTICAL'
    cam.data.sensor_height = sensor_h
    bpy.context.scene.camera = cam
    direction = center - cam.location
    cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()


def big_craters_for(seed, c1, c2, r1=0.46, r2=0.32, d1=0.27, d2=0.21):
    return [
        dict(center=c1, R=r1, depth=d1, rim=0.0, rays=46, ray_len=0.0, sharp=1.3, jitter=0.4),
        dict(center=c2, R=r2, depth=d2, rim=0.0, rays=38, ray_len=0.0, sharp=1.2, jitter=0.45),
    ]


BASE_TYPES = [
    dict(name="v1_round", seed=11, elongate=(1.0, 0.9, 0.85), companions=0),
    dict(name="v2_elongated", seed=12, elongate=(1.7, 0.78, 0.78), companions=0),
    dict(name="v3_round_cluster", seed=13, elongate=(1.0, 0.92, 0.88), companions=3),
    dict(name="v4_elongated_cluster", seed=14, elongate=(1.55, 0.82, 0.8), companions=2),
    dict(name="v5_very_elongated", seed=15, elongate=(2.0, 0.72, 0.7), companions=0),
    dict(name="v6_round_many_companions", seed=16, elongate=(1.0, 0.95, 0.9), companions=4),
]

# 4 seeds per type: distinct crater/noise seeds plus a size spread (some bodies notably
# bigger, some smaller) so the library has real variety once placed at different spots.
SEED_SIZES = [("a", 0, 0.70), ("b", 1, 0.92), ("c", 2, 1.18), ("d", 3, 1.45)]

ALL_VARIANTS = []
for base in BASE_TYPES:
    for suffix, seed_off, size in SEED_SIZES:
        v = dict(base)
        v["name"] = f"{base['name']}_{suffix}"
        v["seed"] = base["seed"] * 10 + seed_off
        v["size"] = size
        ALL_VARIANTS.append(v)

import sys
_only = [a for a in sys.argv[sys.argv.index("--") + 1:]] if "--" in sys.argv else []
if _only:
    VARIANTS = [v for v in ALL_VARIANTS if v["name"] in _only]
else:
    VARIANTS = ALL_VARIANTS

mat = None

for var in VARIANTS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mat = make_material()
    setup_world()
    add_lights()

    seed = var["seed"]
    size = var["size"]
    rng = random.Random(seed * 17 + 3)
    # bias crater centers toward the camera-facing hemisphere (camera looks from -Y) so the
    # signature ray craters are actually visible in every variant
    def facing_dir(rng):
        # kept well clear of y=0 (the grazing silhouette limb, from the camera's -Y view) --
        # a wide crater whose center lands near the limb projects as a long thin crescent
        # jutting past the silhouette, which reads as a stray "fin" rather than a crater.
        v = Vector((rng.uniform(-0.65, 0.65), rng.uniform(-1.0, -0.55), rng.uniform(-0.6, 0.6)))
        return v.normalized()
    c1 = facing_dir(rng)
    c2 = facing_dir(rng)
    # depth/rim on the big ray craters are absolute lengths, not angular fractions, so scale
    # them with body size -- otherwise a bigger body gets shallow-looking craters and a
    # smaller one gets craters that gouge all the way through.
    big = big_craters_for(seed, c1, c2, r1=0.38, r2=0.27, d1=0.27 * size, d2=0.21 * size)
    # more pitting on bigger bodies, less on small ones, for visible variety in the library.
    n_small = max(8, round(22 * size))
    small = small_craters_list(n_small, obj_radius=size, seed=seed)

    main_obj = build_rock("Main", seed, size, (0, 0, 0), var["elongate"], big + small, 0, subdiv=7)
    main_obj.data.materials.append(mat)

    objs = [main_obj]
    n_comp = var["companions"]
    for i in range(n_comp):
        crng = random.Random(seed * 101 + i * 7)
        comp_radius = crng.uniform(0.09, 0.19) * size
        comp_elong = (crng.uniform(0.85, 1.3), crng.uniform(0.8, 1.0), crng.uniform(0.8, 1.0))
        direction = Vector((crng.uniform(-1, 1), crng.uniform(-1, 1), crng.uniform(-1, 1))).normalized()
        dist_from_center = size + comp_radius * crng.uniform(0.45, 0.8)
        loc = direction * dist_from_center
        comp_small = small_craters_list(8, obj_radius=comp_radius, seed=seed * 10 + i)
        comp_obj = build_rock(f"Comp{i}", seed * 10 + i, comp_radius, loc, comp_elong,
                               comp_small, 0, subdiv=4, lump=1.1)
        comp_obj.data.materials.append(mat)
        objs.append(comp_obj)

    frame_camera(objs)

    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    try:
        scene.cycles.device = 'GPU'
    except Exception:
        pass
    scene.cycles.samples = 500
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 2000
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'

    out_path = os.path.join(RENDER_DIR, f"{var['name']}.png")
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    print("DONE:", out_path)

print("ALL VARIANTS COMPLETE")
