import bpy, bmesh, math, random, os
from mathutils import Vector, noise as mnoise

SEED = 7
random.seed(SEED)
mnoise.seed_set(SEED)

OUT_DIR = os.path.dirname(bpy.data.filepath) or r"C:\Users\corbi\AppData\Local\Temp\claude\C--Users-corbi-Desktop-SpaceGame\e6e81089-25d1-44c7-a796-a1b6c927da15\scratchpad\asteroid"
RENDER_PATH = os.path.join(OUT_DIR, "renders", "preview.png")

# ---------- clean scene ----------
bpy.ops.wm.read_factory_settings(use_empty=True)

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

# ---------- base irregular sphere ----------
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=6, radius=1.0, location=(0, 0, 0))
obj = bpy.context.object
obj.name = "Asteroid"
mesh = obj.data

# elongate / lump the base silhouette with low-freq noise + a squash
for v in mesh.vertices:
    d = v.co.normalized()
    p = d * 1.6
    lowfreq = frac_noise(p, octaves=3, lac=2.1, gain=0.55)  # big lumps
    midfreq = frac_noise(p * 3.3 + Vector((9.2, 1.7, 5.4)), octaves=3, lac=2.3, gain=0.5)
    disp = 1.0 + lowfreq * 0.11 + midfreq * 0.025
    v.co = d * disp

# slight non-uniform scale to kill sphere-ness
obj.scale = (1.0, 0.88, 0.8)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

mesh.update()

# ---------- crater definitions ----------
# two dominant "ray burst" craters (reference image), plus scattered small/medium craters
BIG_CRATERS = [
    dict(center=Vector((0.25, -0.75, 0.35)).normalized(), R=0.46, depth=0.27,
         rim=0.0, rays=46, ray_len=0.0, sharp=2.0, jitter=0.22),
    dict(center=Vector((-0.45, -0.68, -0.25)).normalized(), R=0.32, depth=0.21,
         rim=0.0, rays=38, ray_len=0.0, sharp=1.8, jitter=0.25),
]

SMALL_CRATERS = []
for i in range(26):
    c = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))).normalized()
    R = random.uniform(0.045, 0.13)
    SMALL_CRATERS.append(dict(center=c, R=R, depth=R * random.uniform(0.3, 0.55),
                               rim=R * 0.2, rays=0))

ALL_CRATERS = BIG_CRATERS + SMALL_CRATERS

def tangent_basis(n):
    up = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))
    u = up.cross(n).normalized()
    w = n.cross(u).normalized()
    return u, w

for c in ALL_CRATERS:
    u, w = tangent_basis(c["center"])
    c["u"] = u
    c["w"] = w

def triangle_wave(x):
    # 0..1 period 1, triangle shape
    x = x - math.floor(x)
    return 1.0 - abs(2.0 * x - 1.0)

crater_depth_attr = {}  # vidx -> shading value for material (0=undisturbed,1=deep crater floor)

for vi, v in enumerate(mesh.vertices):
    dirn = v.co.normalized()
    base_len = v.co.length
    total_disp = 0.0
    shade_val = 0.0
    for c in ALL_CRATERS:
        center = c["center"]
        d = (dirn - center).length  # chordal distance, good proxy for angular distance on unit-ish sphere
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

        # uniform circular bowl -- jaggedness never perturbs the wall itself
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
            if c["rays"] > 0:
                # subtle radiating striping, concentrated near the rim, fading fast toward the floor
                cand_stripe = (mask - 0.5) * 0.22 * (r_norm * r_norm)
                if abs(cand_stripe) > abs(shade_val):
                    shade_val = cand_stripe

        # thin crenellated tooth right at the rim only -- small, uniform height, not carved into the wall
        rim_band = math.exp(-((r_norm - 1.0) ** 2) / 0.006)
        if c["rays"] > 0:
            tooth = max(0.0, mask - 0.15) * rim_band
            total_disp += c["rim"] * tooth
            if rim_band > 0.25:
                cand2 = (mask * 0.55 - (1.0 - mask) * 0.18) * rim_band
                if abs(cand2) > abs(shade_val):
                    shade_val = cand2
        else:
            total_disp += c["rim"] * rim_band * 0.6
    # fine surface grain everywhere
    grain = frac_noise(dirn * 14.0 + Vector((3.1, 7.7, 2.2)), octaves=3, lac=2.2, gain=0.5) * 0.006
    total_disp += grain

    v.co = dirn * (base_len + total_disp)
    crater_depth_attr[vi] = max(-1.0, min(shade_val, 1.0))

mesh.update()

# ---------- vertex color attribute for crater shading ----------
if "CraterShade" not in mesh.color_attributes:
    mesh.color_attributes.new(name="CraterShade", type='FLOAT_COLOR', domain='POINT')
cattr = mesh.color_attributes["CraterShade"]
for vi, v in enumerate(mesh.vertices):
    val = crater_depth_attr.get(vi, 0.0)  # -1 (dark bowl floor) .. 0 (neutral) .. 1 (bright ray ridge)
    stored = val * 0.5 + 0.5
    cattr.data[vi].color = (stored, stored, stored, 1.0)

bpy.ops.object.shade_smooth()

# recompute normals
bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(mesh)
bm.free()

# ---------- material ----------
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

# large-scale patch noise to break up color into regions (blue-gray / rust / pale)
patchnoise = nodes.new("ShaderNodeTexNoise")
patchnoise.location = (-500, 150)
patchnoise.inputs["Scale"].default_value = 2.2
patchnoise.inputs["Detail"].default_value = 4.0
patchnoise.inputs["Roughness"].default_value = 0.6
links.new(mapping.outputs["Vector"], patchnoise.inputs["Vector"])

patchramp = nodes.new("ShaderNodeValToRGB")
patchramp.location = (-300, 150)
patchramp.color_ramp.elements[0].position = 0.42
patchramp.color_ramp.elements[0].color = (0.065, 0.075, 0.115, 1)  # deep blue-slate
patchramp.color_ramp.elements[1].position = 0.76
patchramp.color_ramp.elements[1].color = (0.27, 0.26, 0.245, 1)   # pale gray
links.new(patchnoise.outputs["Fac"], patchramp.inputs["Fac"])

# rust/ochre patch mask
rustnoise = nodes.new("ShaderNodeTexNoise")
rustnoise.location = (-500, -150)
rustnoise.inputs["Scale"].default_value = 1.6
rustnoise.inputs["Detail"].default_value = 3.0
links.new(mapping.outputs["Vector"], rustnoise.inputs["Vector"])

rustramp = nodes.new("ShaderNodeValToRGB")
rustramp.location = (-300, -150)
rustramp.color_ramp.elements[0].position = 0.55
rustramp.color_ramp.elements[0].color = (0, 0, 0, 1)
rustramp.color_ramp.elements[1].position = 0.68
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

# fine speckle variation
specknoise = nodes.new("ShaderNodeTexNoise")
specknoise.location = (-500, -500)
specknoise.inputs["Scale"].default_value = 22.0
specknoise.inputs["Detail"].default_value = 6.0
links.new(mapping.outputs["Vector"], specknoise.inputs["Vector"])

speckmix = nodes.new("ShaderNodeMixRGB")
speckmix.location = (120, 0)
speckmix.blend_type = 'MULTIPLY'
speckmix.inputs["Fac"].default_value = 0.12
links.new(mixrust.outputs["Color"], speckmix.inputs["Color1"])
links.new(specknoise.outputs["Fac"], speckmix.inputs["Color2"])

# crater shading attribute: 0=dark bowl floor, 0.5=neutral, 1=bright ray ridge
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

# bump for micro roughness
bumpnoise = nodes.new("ShaderNodeTexNoise")
bumpnoise.location = (-500, -950)
bumpnoise.inputs["Scale"].default_value = 30.0
bumpnoise.inputs["Detail"].default_value = 8.0
links.new(mapping.outputs["Vector"], bumpnoise.inputs["Vector"])

bump = nodes.new("ShaderNodeBump")
bump.location = (300, -400)
bump.inputs["Strength"].default_value = 0.08
links.new(bumpnoise.outputs["Fac"], bump.inputs["Height"])
links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

obj.data.materials.append(mat)

# ---------- world ----------
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

# ---------- lighting ----------
def add_area(name, loc, energy, size, rot, color=(1, 1, 1)):
    bpy.ops.object.light_add(type='AREA', location=loc)
    l = bpy.context.object
    l.name = name
    l.data.energy = energy
    l.data.size = size
    l.data.color = color
    l.rotation_euler = rot
    return l

# key light - warm, from upper right matching reference top lighting
add_area("Key", (3.2, -2.6, 2.6), 950, 3.0, (math.radians(55), 0, math.radians(55)))
# fill - cool, dim, opposite side
add_area("Fill", (-3.0, 2.0, -1.0), 55, 3.5, (math.radians(-60), 0, math.radians(-130)), color=(0.6, 0.7, 1.0))
# rim light - behind, to carve the silhouette edge
add_area("Rim", (-1.5, -3.5, -2.0), 260, 1.8, (math.radians(-100), 0, math.radians(20)), color=(0.8, 0.85, 1.0))
# soft ambient so crater interiors aren't crushed to pure black
add_area("Ambient", (0, 0, 4.5), 40, 6.0, (0, 0, 0), color=(0.75, 0.8, 0.9))

# ---------- camera (frame full bounding box) ----------
bbox = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
center = sum(bbox, Vector((0, 0, 0))) / 8
radius = max((c - center).length for c in bbox)

cam_dir = Vector((0, -1, 0.1)).normalized()
lens_mm = 60
sensor_w = 36.0
sensor_h = 45.0  # matches the portrait render aspect so vertical fit is correct
fov = 2 * math.atan((sensor_h / 2) / lens_mm)
dist = (radius * 1.06) / math.sin(fov / 2)
cam_loc = center + cam_dir * dist

bpy.ops.object.camera_add(location=cam_loc)
cam = bpy.context.object
cam.name = "Camera"
cam.data.lens = lens_mm
cam.data.sensor_fit = 'VERTICAL'
cam.data.sensor_height = sensor_h
bpy.context.scene.camera = cam

direction = center - cam.location
rot_quat = direction.to_track_quat('-Z', 'Y')
cam.rotation_euler = rot_quat.to_euler()

# ---------- render settings ----------
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
try:
    scene.cycles.device = 'GPU'
except Exception:
    pass
scene.cycles.samples = 400
scene.cycles.use_denoising = True
scene.render.resolution_x = 1500
scene.render.resolution_y = 1875
scene.render.film_transparent = False
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'

scene.render.filepath = RENDER_PATH
bpy.ops.render.render(write_still=True)

blend_path = os.path.join(OUT_DIR, "asteroid.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend_path)

print("DONE:", RENDER_PATH)
