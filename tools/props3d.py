"""The roadside trees as 3D models, for their sprites (tools/mkprops.py): a
tall thin palm, a short thick palm, a dead tree. (The signs are drawn as
pixels: mkprops.py.)

Run inside Blender 4.2 or later as tools/cars3d.py is (exec() through an
MCP), with TOOLS set to this directory and OUT_DIR to where the renders go
(assets/props). Each prop is rendered seen square from the road, lit from
the left and above as the bushes are, photorealistic, at each of the
heights in lines its sprites have (HEIGHTS): a frame of cells - each a mode
0 pixel, CELL_PX render pixels, twice as wide as a line is high - its
height that many cells, its width the prop's, to OUT_DIR/<prop>_<h>.png.
PROPS picks which props (default all).
"""

import importlib.util
import math
import os
import random

import bpy
from mathutils import Vector

TOOLS = globals().get("TOOLS", os.path.dirname(os.path.abspath(globals().get("__file__", "."))))
OUT_DIR = globals().get("OUT_DIR", bpy.app.tempdir)
SAMPLES = globals().get("SAMPLES", 32)
CELL_PX = (16, 8)               # render pixels a cell (a mode 0 pixel)

# Each prop's sprite heights in lines (tools/cpcgfx.py: prop_heights; and
# tools/mkprops.py reads them from the renders' names).
_spec = importlib.util.spec_from_file_location("cpcgfx", os.path.join(TOOLS, "cpcgfx.py"))
G = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(G)
HEIGHTS = {k: G.prop_heights(k) for k in ("palm", "stump", "dead")}
PROPS = globals().get("PROPS", tuple(HEIGHTS))


def clear():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    for coll in (bpy.data.materials, bpy.data.meshes, bpy.data.curves,
                 bpy.data.lights, bpy.data.cameras):
        for x in list(coll):
            coll.remove(x)


def principled(name, base, rough=0.7, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = tuple(base) + (1,)
    b.inputs["Roughness"].default_value = rough
    if emit is not None:
        b.inputs["Emission Color"].default_value = tuple(emit) + (1,)
        b.inputs["Emission Strength"].default_value = strength
    return m


def ringed(name, a, b, period):
    """Bark in rings up the trunk: a and b by turns, period metres."""
    m = principled(name, a)
    nt = m.node_tree
    tc = nt.nodes.new("ShaderNodeTexCoord")
    xyz = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], xyz.inputs[0])
    math_n = nt.nodes.new("ShaderNodeMath")
    math_n.operation = "MULTIPLY"
    math_n.inputs[1].default_value = 1.0 / period
    nt.links.new(xyz.outputs["Z"], math_n.inputs[0])
    frac = nt.nodes.new("ShaderNodeMath")
    frac.operation = "FRACT"
    nt.links.new(math_n.outputs[0], frac.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, tuple(b) + (1,)
    els[1].position, els[1].color = 0.3, tuple(a) + (1,)
    ramp.color_ramp.interpolation = "CONSTANT"
    nt.links.new(frac.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], nt.nodes.get("Principled BSDF").inputs["Base Color"])
    return m


def link(ob):
    bpy.context.collection.objects.link(ob)
    return ob


def mesh(name, verts, faces, mat):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    return link(bpy.data.objects.new(name, me))


def tube(name, path, radii, mat, sides=10):
    """A tube along the points `path`, its radius radii[i] at each."""
    verts, faces = [], []
    n = len(path)
    for i, (p, r) in enumerate(zip(path, radii)):
        p = Vector(p)
        d = (Vector(path[min(i + 1, n - 1)]) - Vector(path[max(i - 1, 0)])).normalized()
        u = d.orthogonal().normalized()
        v = d.cross(u)
        for k in range(sides):
            a = 2 * math.pi * k / sides
            verts.append(p + r * (math.cos(a) * u + math.sin(a) * v))
    for i in range(n - 1):
        for k in range(sides):
            a, b = i * sides + k, i * sides + (k + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    faces.append(tuple(range(sides - 1, -1, -1)))
    faces.append(tuple((n - 1) * sides + k for k in range(sides)))
    return mesh(name, verts, faces, mat)


def frond(name, base, yaw, length, rise, droop, width, mat, leaflets=True):
    """A palm frond from `base`: out along `yaw` (radians, 0 = +X), up by
    rise and down by droop over its length, a ribbon `width` wide in the
    middle, its leaflets a V folded along the rib."""
    n = 14
    verts, faces = [], []
    d = Vector((math.cos(yaw), math.sin(yaw), 0))
    side = Vector((-d.y, d.x, 0))
    for i in range(n + 1):
        t = i / n
        p = Vector(base) + d * (length * t) + Vector((0, 0, rise * math.sin(math.pi * t * 0.7) - droop * t * t))
        w = width * math.sin(math.pi * min(1.0, t * 1.15)) * (1 if t < 0.95 else 0.3)
        fold = Vector((0, 0, -0.25 * w))
        verts += [p + side * w + fold, p, p - side * w + fold]
    for i in range(n):
        a = 3 * i
        faces += [(a, a + 1, a + 4, a + 3), (a + 1, a + 2, a + 5, a + 4)]
    return mesh(name, verts, faces, mat)


def palm():
    """A tall thin palm, 8 m, leaning a little, ringed; ten long fronds."""
    bark = ringed("bark", (0.3, 0.17, 0.08), (0.08, 0.04, 0.02), 0.32)
    leaf = principled("leaf", (0.08, 0.32, 0.05), 0.6)
    nut = principled("nut", (0.3, 0.18, 0.06))
    path, radii = [], []
    for i in range(25):
        t = i / 24
        path.append((0.9 * t * t, 0, 8.0 * t))
        radii.append(0.26 - 0.09 * t)
    tube("trunk", path, radii, bark)
    top = Vector(path[-1])
    for k in range(10):
        yaw = 2 * math.pi * k / 10 + 0.3
        frond("frond%d" % k, top, yaw, 4.6, 1.1, 3.2, 0.6, leaf)
    for k in range(3):
        a = 2 * math.pi * k / 3
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.17, location=top + Vector((0.2 * math.cos(a), 0.2 * math.sin(a) - 0.2, -0.25)))
        bpy.context.object.data.materials.append(nut)


def stump():
    """A short thick palm, 4.5 m: a fat scaly trunk, fourteen fronds."""
    bark = ringed("bark", (0.28, 0.16, 0.07), (0.07, 0.04, 0.02), 0.22)
    leaf = principled("leaf", (0.1, 0.36, 0.06), 0.6)
    path, radii = [], []
    for i in range(13):
        t = i / 12
        path.append((0, 0, 3.6 * t))
        radii.append(0.55 - 0.12 * t + 0.08 * math.sin(math.pi * t))
    tube("trunk", path, radii, bark, sides=14)
    top = Vector(path[-1])
    for k in range(14):
        yaw = 2 * math.pi * k / 14
        up = k % 2
        frond("frond%d" % k, top, yaw, 3.4 if up else 3.9, 1.7 if up else 1.0,
              1.3 if up else 2.6, 0.6, leaf)


def dead():
    """A dead tree, 6 m: a crooked trunk, three limbs spreading from it,
    each forking once or twice, no leaves."""
    wood = principled("wood", (0.36, 0.33, 0.3), 0.9)
    rnd = random.Random(11)
    n = [0]

    def limb(p, d, length, r, depth):
        mid = p + d * (length * 0.5) + Vector((rnd.uniform(-0.15, 0.15), 0, 0))
        q = p + d * length
        n[0] += 1
        tube("b%d" % n[0], [p, mid, q], [r, r * 0.85, r * 0.65], wood, 8)
        if depth == 0:
            return
        for a in (rnd.uniform(0.35, 0.7), -rnd.uniform(0.35, 0.7))[:2 if depth > 1 or rnd.random() < 0.7 else 1]:
            nd = Vector((d.x * math.cos(a) - d.z * math.sin(a), rnd.uniform(-0.3, 0.3),
                         d.x * math.sin(a) + d.z * math.cos(a))).normalized()
            limb(q, nd, length * rnd.uniform(0.55, 0.75), r * 0.62, depth - 1)

    base = Vector((0, 0, 0))
    top = Vector((0.25, 0, 2.4))
    tube("trunk", [base, Vector((-0.1, 0, 1.2)), top], [0.36, 0.3, 0.26], wood, 10)
    for ang, length in ((-0.95, 2.2), (0.15, 2.4), (0.85, 2.0)):
        d = Vector((math.sin(ang), 0, math.cos(ang)))
        limb(top, d, length, 0.2, 2)


def camera_and_light(height, width):
    """An orthographic camera square on to the prop (looking along +Y),
    framing `width` x `height` metres from the ground up; a sun from the
    left and above, as the bushes' (scene.BUSH_LIGHT), and a sky."""
    sc = bpy.context.scene
    cam = link(bpy.data.objects.new("cam", bpy.data.cameras.new("cam")))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(width, height)
    cam.data.sensor_fit = "AUTO"
    cam.location = (0, -30, height / 2)
    cam.rotation_euler = (math.pi / 2, 0, 0)
    sc.camera = cam
    sun = link(bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")))
    sun.data.energy = 4.0
    sun.data.angle = math.radians(3)
    sun.rotation_euler = (math.radians(55), math.radians(-40), 0)
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = False
    sc.render.film_transparent = True
    sc.render.filter_size = 1.0
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("sky")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.35, 0.45, 0.7, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.7


MODELS = dict(palm=palm, stump=stump, dead=dead)


def bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    bpy.context.view_layer.update()
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def render():
    paths = []
    os.makedirs(OUT_DIR, exist_ok=True)
    for name in PROPS:
        clear()
        MODELS[name]()
        lo, hi = bounds()
        height = hi.z
        cx = 0.0                                    # (the trunk's foot in the
        half = max(hi.x, -lo.x) * 1.04              # frame's middle)
        for h in HEIGHTS[name]:
            per_line = height / h                       # metres a line
            cells = 2 * int(math.ceil(half / (2 * per_line))) + 1
            width = cells * 2 * per_line                # (a cell: two lines wide)
            clear_cams()
            camera_and_light(h * per_line, width)
            cam = bpy.context.scene.camera
            cam.location.x = cx
            sc = bpy.context.scene
            sc.render.resolution_x = cells * CELL_PX[0]
            sc.render.resolution_y = h * CELL_PX[1]
            sc.render.resolution_percentage = 100
            p = os.path.join(OUT_DIR, "%s_%d.png" % (name, h))
            sc.render.filepath = p
            bpy.ops.render.render(write_still=True)
            paths.append(p)
    return paths


def clear_cams():
    for ob in list(bpy.data.objects):
        if ob.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(ob)


if globals().get("RUN"):
    result_paths = render()
