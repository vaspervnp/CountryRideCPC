"""Three more sports cars as 3D models, for their sprites' views
(tools/mkcars.py): a wide red one with a grille across its tail (after a
Ferrari Testarossa), a low yellow wedge with a louvred engine cover (after
a Lotus Esprit) and a white saloon with a wing on its boot and racing
stripes (after a BMW M3 of the eighties). No badges.

Run inside Blender 4.2 or later as tools/car3d.py is (exec() through an
MCP), with TOOLS set to this directory and OUT_DIR to where the renders go:
it takes car3d.py's pens, shapes, camera and light - the same frame and
scale as the player's car, the rear face laid out on the frame's grid -
and renders each car seen from behind, on the level, going uphill (its
nose up PITCH degrees) and downhill, each straight and turning left by
car3d.YAW degrees, to OUT_DIR/<car>_<flat|up|down>_<0|left>.png. Turning
right is the left view mirrored. CARS (default all four: the player's too)
picks which; PHOTO (default) renders them photorealistic.
"""

import importlib.util
import math
import os

import bpy
from mathutils import Euler, Matrix, Vector

TOOLS = globals().get("TOOLS", os.path.dirname(os.path.abspath(globals().get("__file__", "."))))
_spec = importlib.util.spec_from_file_location("car3d", os.path.join(TOOLS, "car3d.py"))
c3 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(c3)

OUT_DIR = globals().get("OUT_DIR", bpy.app.tempdir)
CARS = globals().get("CARS", ("player", "ferrari", "lotus", "bmw"))
PHOTO = globals().get("PHOTO", True)       # photorealistic (else car3d's toon)
PITCH = globals().get("PITCH", 8.0)        # degrees, going uphill (nose up),
                                           # before the squash
YAW = c3.YAW
PIVOT = c3.PIVOT                           # the rear axle, on the ground

c3.PAL["PASTEL"] = (128, 128, 255)          # the white car's flanks
col, zl, LZ, CX, Z0 = c3.col, c3.zl, c3.LZ, c3.CX, c3.Z0
panel, box, prism, solid, wheel = c3.panel, c3.box, c3.prism, c3.solid, c3.wheel


def clear():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)


def stripes(name, pen_a, pen_b, period, share):
    """Horizontal stripes by height: pen_a for the first `share` of each
    `period` metres (object space, before the squash), pen_b the rest."""
    m, nt = c3.material(name)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    xyz = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], xyz.inputs[0])
    div = nt.nodes.new("ShaderNodeMath")
    div.operation = "DIVIDE"
    div.inputs[1].default_value = period
    nt.links.new(xyz.outputs["Z"], div.inputs[0])
    frac = nt.nodes.new("ShaderNodeMath")
    frac.operation = "FRACT"
    nt.links.new(div.outputs[0], frac.inputs[0])
    lt = nt.nodes.new("ShaderNodeMath")
    lt.operation = "LESS_THAN"
    lt.inputs[1].default_value = share
    nt.links.new(frac.outputs[0], lt.inputs[0])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = c3.rgba(pen_b)
    mix.inputs["B"].default_value = c3.rgba(pen_a)
    nt.links.new(lt.outputs[0], mix.inputs["Factor"])
    c3.emit(nt, mix.outputs["Result"])
    return m


def mirrored(car, name, mat, c0, c1, n0, n1, depth=0):
    """A panel on the rear face over columns c0..c1 and its mirror image."""
    panel(name, mat, col(c0), col(c1), zl(n0), zl(n1), car, depth)
    panel(name, mat, -col(c1), -col(c0), zl(n0), zl(n1), car, depth)


def both(fn, *a):
    for sx in (-1, 1):
        fn(sx, *a)


def wheels(car, tyre_out, tyre_w, k, n, hub, front_in=0.04):
    for sx in (-1, 1):
        wheel("tyre_r", k, n, sx * (tyre_out - tyre_w / 2), c3.REAR_AXLE, 0.34, tyre_w, car, hub)
        wheel("tyre_f", k, n, sx * (tyre_out - front_in - tyre_w * 0.4), c3.FRONT_AXLE, 0.31,
              tyre_w * 0.8, car, hub)


def exhaust(car, mat, x, z, r=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=r or CX, depth=0.12,
                                        location=(x, -0.05, z), rotation=(math.pi / 2, 0, 0))
    ob = bpy.context.object
    ob.name = "exhaust"
    ob.data.materials.append(mat)
    ob.parent = car


def ferrari():
    """Wide and flat: the tail a grille of black slats right across, the
    lights glowing through at its ends; a long flat engine cover between
    two sails; strakes along the flanks into the side intakes."""
    body = c3.toon("BODY", [(0.0, "CAR_DARK"), (0.35, "RED"), (0.97, "ORANGE")])
    k, d, w = c3.flat("BLACK"), c3.flat("CAR_DARK"), c3.flat("WHITE")
    r, o = c3.flat("RED"), c3.flat("ORANGE")
    n, gl = c3.flat("NAVY"), c3.glass()
    car = bpy.data.objects.new("Car", None)
    bpy.context.collection.objects.link(car)

    xr = -col(1.5)
    top = 8                                         # the rear face's lines
    plan = [(-xr, 0.0), (xr, 0.0), (1.0, 0.15), (1.0, 3.2), (-1.0, 3.2), (-1.0, 0.15)]
    prism("body", body, plan, Z0, zl(top), car)
    solid("nose", body,
          [(-1.0, 3.2, Z0), (1.0, 3.2, Z0), (0.92, 4.45, Z0), (-0.92, 4.45, Z0)],
          [(-1.0, 3.2, zl(top)), (1.0, 3.2, zl(top)), (0.86, 4.45, zl(4)), (-0.86, 4.45, zl(4))], car)
    # the cabin, set forward: a small upright rear window, glass all round
    solid("cabin", gl,
          [(-0.55, 1.75, zl(top)), (0.55, 1.75, zl(top)), (0.68, 3.25, zl(top)), (-0.68, 3.25, zl(top))],
          [(-0.44, 2.0, zl(top + 6)), (0.44, 2.0, zl(top + 6)), (0.47, 2.65, zl(top + 6)),
           (-0.47, 2.65, zl(top + 6))], car)
    box("roof", body, -0.47, 0.47, 1.95, 2.7, zl(top + 5.9), zl(top + 6.4), car)
    # the sails: from the roof's back corners down to the tail
    for sx in (-1, 1):
        pts = [(0.98, 0.2, zl(top)), (0.66, 0.2, zl(top)), (0.55, 2.0, zl(top)), (0.98, 2.0, zl(top))]
        tp = [(0.96, 0.2, zl(top + 0.4)), (0.76, 0.2, zl(top + 0.4)), (0.44, 2.0, zl(top + 6)),
              (0.56, 2.0, zl(top + 6))]
        solid("sail", body, [(sx * x, y, z) for x, y, z in pts],
              [(sx * x, y, z) for x, y, z in tp], car)
    # the engine cover between them: black louvres at its back
    for i, y in enumerate((0.35, 0.6, 0.85)):
        box("louvre", k, -0.55, 0.55, y, y + 0.1, zl(top), zl(top + 0.25), car)
    # the tail: the lit edge, then the grille - slats over the lights at the
    # ends, a dark glow between - over a black band, the plate
    panel("rim", o, col(1.5), -col(1.5), zl(top - 1), zl(top), car)
    panel("grille", k, col(1.5), -col(1.5), zl(0), zl(top - 1), car)
    for row in (2, 4, 6):
        panel("glow", d, col(9), -col(9), zl(row - 1), zl(row), car, 1)
        mirrored(car, "light", r, 2.5, 9, row - 1, row, 1)
    panel("frame", k, col(13), -col(13), zl(0), zl(2), car, 2)
    panel("plate", w, col(14), -col(14), zl(0), zl(2), car, 3)
    # under the body: black, and two pairs of exhausts
    panel("diffuser", k, col(5), -col(5), LZ, Z0, car)
    box("under", k, col(5), -col(5), 0.0, 4.3, LZ, Z0, car)
    for sx in (-1, 1):
        for cc in (9.5, 12):
            exhaust(car, w, sx * -col(cc), 2 * LZ)
    # strakes along the flanks into the side intakes
    for sx in (-1, 1):
        box("sill", k, sx * 1.0 - 0.005, sx * 1.0 + 0.005, 0.15, 4.3, Z0, zl(0.7), car)
        for row in (1.5, 3, 4.5, 6):
            box("strake", k, sx * 1.0 - 0.005, sx * 1.0 + 0.005, 1.5, 3.1,
                zl(row), zl(row + 0.6), car)
    wheels(car, 1.02, 0.36, k, n, c3.flat("GREY"), front_in=0.02)
    return car


def lotus():
    """A wedge: low at the nose, its tail flat and upright with a lip on top;
    over the engine a sloping cover of black louvres between two sails; the
    lights on a black panel."""
    body = c3.toon("BODY", [(0.0, "ORANGE"), (0.35, "YELLOW")])
    k, w = c3.flat("BLACK"), c3.flat("WHITE")
    r, o = c3.flat("RED"), c3.flat("ORANGE")
    n, gl = c3.flat("NAVY"), c3.glass()
    lv = stripes("LOUVRES", "BLACK", "NAVY", 2 * LZ, 0.5)
    car = bpy.data.objects.new("Car", None)
    bpy.context.collection.objects.link(car)

    hw = 0.95                                       # half its width
    xr = -col(2)
    top = 7
    plan = [(-xr, 0.0), (xr, 0.0), (hw, 0.15), (hw, 1.7), (-hw, 1.7), (-hw, 0.15)]
    prism("tail", body, plan, Z0, zl(top), car)
    # the wedge: from the tail's top down to the nose
    solid("wedge", body,
          [(-hw, 1.7, Z0), (hw, 1.7, Z0), (0.88, 4.2, Z0), (-0.88, 4.2, Z0)],
          [(-hw, 1.7, zl(top)), (hw, 1.7, zl(top)), (0.8, 4.2, zl(2.5)), (-0.8, 4.2, zl(2.5))], car)
    # the lip over the tail
    box("lip", body, -xr, xr, -0.04, 0.12, zl(top), zl(top + 0.6), car)
    # the louvred cover, sloping up to the roof, between the sails
    solid("louvres", lv,
          [(-0.62, 0.15, zl(top)), (0.62, 0.15, zl(top)), (0.66, 1.7, zl(top)), (-0.66, 1.7, zl(top))],
          [(-0.55, 0.15, zl(top + 0.2)), (0.55, 0.15, zl(top + 0.2)), (0.5, 1.7, zl(top + 5.5)),
           (-0.5, 1.7, zl(top + 5.5))], car)
    for sx in (-1, 1):
        pts = [(hw - 0.02, 0.15, zl(top)), (0.62, 0.15, zl(top)), (0.62, 1.75, zl(top)),
               (hw - 0.02, 1.75, zl(top))]
        tp = [(hw - 0.04, 0.15, zl(top + 0.3)), (0.66, 0.15, zl(top + 0.3)), (0.5, 1.75, zl(top + 5.6)),
              (0.64, 1.75, zl(top + 5.6))]
        solid("sail", body, [(sx * x, y, z) for x, y, z in pts],
              [(sx * x, y, z) for x, y, z in tp], car)
    # the cabin: glass sides, a flat roof, the windscreen raked far forward
    solid("cabin", gl,
          [(-0.66, 1.7, zl(top)), (0.66, 1.7, zl(top)), (0.78, 3.4, zl(4.3)), (-0.78, 3.4, zl(4.3))],
          [(-0.5, 1.75, zl(top + 5.5)), (0.5, 1.75, zl(top + 5.5)), (0.52, 2.5, zl(top + 5.5)),
           (-0.52, 2.5, zl(top + 5.5))], car)
    box("roof", body, -0.52, 0.52, 1.72, 2.5, zl(top + 5.4), zl(top + 5.9), car)
    # the tail: a black panel with the lights, a black bumper, the plate
    panel("panel", k, col(2), -col(2), zl(2), zl(5), car)
    for row, mat in ((5, r), (4, r), (3, o)):
        mirrored(car, "light", mat, 2.5, 9, row - 1, row, 1)
    panel("bumper", k, col(2), -col(2), zl(0), zl(1), car)
    panel("frame", k, col(13), -col(13), zl(0), zl(3), car, 2)
    panel("plate", w, col(14), -col(14), zl(0.5), zl(2.5), car, 3)
    panel("diffuser", k, col(6), -col(6), LZ, Z0, car)
    box("under", k, col(6), -col(6), 0.0, 4.1, LZ, Z0, car)
    exhaust(car, w, -col(11), 2 * LZ)
    exhaust(car, w, col(11), 2 * LZ)
    for sx in (-1, 1):
        box("sill", k, sx * hw - 0.005, sx * hw + 0.005, 0.15, 4.1, Z0, zl(1), car)
        box("intake", k, sx * hw - 0.005, sx * hw + 0.005, 1.6, 2.4, zl(3), zl(5.5), car)
        # over the front wheel, which stands higher than the bonnet: its
        # arch (behind the tyre, seen above it)
        box("arch", body, sx * 0.6, sx * 0.9, c3.FRONT_AXLE - 0.4, c3.FRONT_AXLE + 0.4,
            zl(2), zl(7), car)
    wheels(car, 0.97, 0.32, k, n, c3.flat("GREY"), front_in=0.0)  # (out past
    return car                                                     # the sill)


def bmw():
    """A boxy saloon: an upright boot with a wing on it, wide lights, flared
    arches over the wheels, a tall cabin; stripes in light blue, dark blue
    and red along it."""
    body = c3.toon("BODY", [(0.0, "PASTEL"), (0.35, "WHITE")])
    k, w, g = c3.flat("BLACK"), c3.flat("WHITE"), c3.flat("GREY")
    r, o = c3.flat("RED"), c3.flat("ORANGE")
    n, s, gl = c3.flat("NAVY"), c3.flat("SKY"), c3.glass()
    car = bpy.data.objects.new("Car", None)
    bpy.context.collection.objects.link(car)

    hw = 0.85
    xr = hw - 0.05
    top = 10                                        # the boot lid's line
    plan = [(-xr, 0.0), (xr, 0.0), (hw, 0.1), (hw, 4.3), (-hw, 4.3), (-hw, 0.1)]
    prism("body", body, plan, Z0, zl(top), car)
    # the cabin: a sloping rear window between broad pillars, a tall roof
    solid("cabin", gl,
          [(-0.74, 0.95, zl(top)), (0.74, 0.95, zl(top)), (0.76, 3.2, zl(top)), (-0.76, 3.2, zl(top))],
          [(-0.6, 1.45, zl(top + 8)), (0.6, 1.45, zl(top + 8)), (0.6, 2.6, zl(top + 8)),
           (-0.6, 2.6, zl(top + 8))], car)
    box("roof", body, -0.61, 0.61, 1.4, 2.65, zl(top + 7.9), zl(top + 8.4), car)
    for sx in (-1, 1):                              # the broad rear pillars
        pts = [(0.78, 0.9, zl(top)), (0.46, 0.9, zl(top)), (0.46, 1.5, zl(top)), (0.78, 1.5, zl(top))]
        tp = [(0.74, 0.9, zl(top + 0.3)), (0.5, 0.9, zl(top + 0.3)), (0.36, 1.5, zl(top + 8)),
              (0.61, 1.5, zl(top + 8))]
        solid("pillar", body, [(sx * x, y, z) for x, y, z in pts],
              [(sx * x, y, z) for x, y, z in tp], car)
    # the wing on the boot lid's back edge
    box("wing", body, -0.74, 0.74, 0.02, 0.32, zl(top + 1), zl(top + 2), car)
    panel("wing_k", k, -0.74, 0.74, zl(top + 1), zl(top + 1.5), car)
    for sx in (-1, 1):
        box("stand", k, sx * 0.55 - 0.03, sx * 0.55 + 0.03, 0.1, 0.25, zl(top), zl(top + 1), car)
    # the rear face: the lights either side of a black panel with the plate,
    # stripes across under them, a black bumper
    for row, mat in ((8, r), (7, r), (6, o), (5, r)):
        mirrored(car, "light", mat, 3.7, 11, row - 1, row, 1)
    mirrored(car, "reverse", w, 10, 11, 4, 5, 2)
    panel("panel", k, col(11), -col(11), zl(4), zl(8), car)
    panel("frame", k, col(13), -col(13), zl(4), zl(7), car, 2)
    panel("plate", w, col(14), -col(14), zl(4.5), zl(6.5), car, 3)
    for row, mat in ((4, s), (3, n), (2, r)):
        panel("stripe", mat, -xr, xr, zl(row - 1), zl(row), car, 1)
    panel("bumper", k, -xr, xr, zl(0), zl(1), car, 1)
    panel("diffuser", k, col(7), -col(7), LZ, Z0, car)
    box("under", k, col(7), -col(7), 0.0, 4.2, LZ, Z0, car)
    exhaust(car, w, col(9), 2 * LZ)
    # along each flank: the stripes, the arches flared out over the wheels
    for sx in (-1, 1):
        for row, mat in ((4, s), (3, n), (2, r)):
            box("stripe", mat, sx * hw - 0.005, sx * hw + 0.005, 0.1, 4.3, zl(row - 1), zl(row), car)
        box("bumper", k, sx * hw - 0.005, sx * hw + 0.005, 0.1, 4.3, zl(0), zl(1), car)
        for y in (c3.REAR_AXLE, c3.FRONT_AXLE):
            box("arch", body, sx * hw - (0.0 if sx > 0 else 0.08), sx * hw + (0.08 if sx > 0 else 0.0),
                y - 0.42, y + 0.42, zl(1), zl(4.5), car)
    wheels(car, 0.95, 0.3, k, n, c3.flat("GREY"), front_in=0.0)   # (out past
                                                                   # the arches)
    return car


def player():
    """The player's car (car3d.py), unsquashed."""
    car = c3.build()
    car.scale = (1, 1, 1)
    return car


MODELS = dict(ferrari=ferrari, lotus=lotus, bmw=bmw)

# ---------------------------------------------------------------------------
# Photorealistic: the same models with real materials - paint under a clear
# coat, glass that mirrors the sky, rubber, alloy rims, chrome, lenses - lit
# by a sun and a sky (Cycles), over a ground that only takes their shadows;
# tools/dither.py then brings each cell's mean colour to the pens.
# ---------------------------------------------------------------------------
PAINT = dict(player=(0.85, 0.004, 0.003), ferrari=(0.8, 0.003, 0.002),
             lotus=(0.95, 0.8, 0.0), bmw=(0.82, 0.82, 0.82))      # linear
SAMPLES = globals().get("SAMPLES", 48)
SHADOW = globals().get("SHADOW", False)    # a ground taking the car's shadow:
                                           # it left stray dark cells either
                                           # side of the car


def principled(name, base, rough=0.4, metal=0.0, coat=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = tuple(base) + (1,)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Coat Weight"].default_value = coat
    b.inputs["Coat Roughness"].default_value = 0.08
    if emit is not None:
        b.inputs["Emission Color"].default_value = tuple(emit) + (1,)
        b.inputs["Emission Strength"].default_value = strength
    return m


def photo_materials(paint):
    P = dict(
        paint=principled("paint", paint, 0.3, coat=0.5),
        plastic=principled("plastic", (0.02, 0.02, 0.022), 0.45),
        rubber=principled("rubber", (0.025, 0.025, 0.025), 0.85),
        rim=principled("rim", (0.7, 0.7, 0.72), 0.25, metal=1.0),
        chrome=principled("chrome", (0.9, 0.9, 0.9), 0.06, metal=1.0),
        glass=principled("glass", (0.008, 0.009, 0.012), 0.02, coat=1.0),
        red=principled("lens_red", (0.6, 0.0, 0.0), 0.08, emit=(1.0, 0.02, 0.0), strength=0.6),
        amber=principled("lens_amber", (0.8, 0.25, 0.0), 0.08, emit=(1.0, 0.3, 0.0), strength=0.5),
        clear=principled("lens_clear", (0.8, 0.8, 0.75), 0.05, coat=1.0),
        dark=principled("lens_dark", (0.12, 0.0, 0.0), 0.08, coat=1.0),
        plate=principled("plate", (0.8, 0.8, 0.78), 0.4),
        sky=principled("stripe_sky", (0.02, 0.25, 0.85), 0.25, coat=1.0),
        navy=principled("stripe_navy", (0.0, 0.02, 0.2), 0.25, coat=1.0),
        red_paint=principled("stripe_red", (0.8, 0.0, 0.0), 0.25, coat=1.0),
        orange_paint=principled("stripe_orange", (0.9, 0.2, 0.0), 0.25, coat=1.0))
    return P


# by the part's name - and, for some, the pen it had
PART = {"body": "paint", "nose": "paint", "deck": "paint", "roof": "paint",
        "buttress": "paint", "wing": "paint", "sail": "paint", "tail": "paint",
        "wedge": "paint", "lip": "paint", "pillar": "paint", "arch": "paint",
        "rim": "paint", "cabin": "glass", "wing_k": "plastic", "pylon": "plastic",
        "stand": "plastic", "grille": "plastic", "frame": "plastic", "diffuser": "plastic",
        "under": "plastic", "sill": "plastic", "strake": "plastic", "louvre": "plastic",
        "panel": "plastic", "bumper": "plastic", "intake": "plastic", "band": "plastic",
        "middle": "dark", "glow": "dark", "amber": "amber", "lamp": "clear",
        "reverse": "clear", "plate": "plate", "exhaust": "chrome"}
BY_PEN = {"light": dict(RED="red", ORANGE="amber"),
          "stripe": dict(SKY="sky", NAVY="navy", RED="red_paint"),
          "wing_r": dict(RED="red_paint"), "wing_o": dict(ORANGE="orange_paint")}


def photoreal(paint):
    """Every part of the car built given its real material."""
    P = photo_materials(paint)
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        part = ob.name.split(".")[0]
        old = ob.data.materials[0].name.split(".")[0] if ob.data.materials else ""
        if part.startswith("tyre"):
            mat = P["rim"] if part.endswith("_hub") else P["rubber"]
            for i in range(len(ob.data.materials)):
                ob.data.materials[i] = mat
            continue
        if part == "louvres":                       # slats over glass
            key = "plastic"
        elif part in BY_PEN:
            key = BY_PEN[part].get(old, "paint")
        else:
            key = PART.get(part)
        assert key, (part, old)
        ob.data.materials[0] = P[key]
        if key == "paint" and ob.name.split(".")[0] != "rim":
            bev = ob.modifiers.new("bevel", "BEVEL")
            bev.width = 0.03
            bev.segments = 2


def photo_setup(sun_rot):
    """Cycles; a sky - blue overhead, hazy at the horizon, the asphalt's grey
    below - a sun at sun_rot (and with SHADOW a ground that only shows
    shadows)."""
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = False                 # (a cell averages 128 pixels)
    sc.render.film_transparent = True
    sc.render.filter_size = 1.0
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0
    sc.view_settings.gamma = 1
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    world = bpy.data.worlds.new("Sky")
    sc.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    xyz = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], xyz.inputs[0])
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = -1
    mr.inputs["From Max"].default_value = 1
    nt.links.new(xyz.outputs["Z"], mr.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = 0.0, (0.2, 0.2, 0.2, 1)
    els[1].position, els[1].color = 1.0, (0.08, 0.2, 0.7, 1)
    for pos, c in ((0.49, (0.22, 0.22, 0.22, 1)), (0.5, (0.75, 0.8, 0.9, 1)),
                   (0.6, (0.35, 0.5, 0.9, 1))):
        e = els.new(pos)
        e.color = c
    nt.links.new(mr.outputs[0], ramp.inputs[0])
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 0.6
    nt.links.new(ramp.outputs[0], bg.inputs[0])
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(bg.outputs[0], out.inputs[0])
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 4.5
    sun_data.angle = math.radians(2)
    sun = bpy.data.objects.new("Sun", sun_data)
    sc.collection.objects.link(sun)
    sun.rotation_euler = sun_rot
    if SHADOW:
        bpy.ops.mesh.primitive_plane_add(size=8)    # (not up to the camera
        ground = bpy.context.object                 # when tilted)
        ground.data.transform(Matrix.Translation((0, 2.2, 0)))
        ground.name = "ground"
        ground.is_shadow_catcher = True


VIEWS = (("flat", 0.0), ("up", PITCH), ("down", -PITCH))


def place(car, pitch, yaw):
    """The car pitched (nose up) and yawed (nose left) about its rear axle
    on the ground."""
    e = Euler((math.radians(pitch), 0, math.radians(yaw)), "XYZ")
    p = Vector((0, PIVOT, 0))
    car.rotation_euler = e
    car.location = p - e.to_matrix() @ p


def render():
    paths = []
    os.makedirs(OUT_DIR, exist_ok=True)
    for name in CARS:
        clear()
        if name == "player":
            car = c3.build()
            car.scale = (1, 1, 1)
        else:
            car = MODELS[name]()
        # squashed after it is pitched, as the slope under it would be: the
        # car as low as the player's, the slope as gentle
        root = bpy.data.objects.new("Squash", None)
        bpy.context.collection.objects.link(root)
        root.scale = (1, 1, c3.SQUASH)
        car.parent = root
        c3.camera()
        if PHOTO:
            photoreal(PAINT[name])
            photo_setup((math.radians(45), 0, 0))   # from behind, above
        else:
            c3.setup()
        ground = bpy.data.objects.get("ground")
        if ground:                                  # the slope under it
            ground.parent = root
        for vname, pitch in VIEWS:
            for yname, yaw in (("0", 0.0), ("left", YAW)):
                place(car, pitch, yaw)
                if ground:
                    place(ground, pitch, 0.0)
                p = os.path.join(OUT_DIR, "%s_%s_%s.png" % (name, vname, yname))
                bpy.context.scene.render.filepath = p
                bpy.ops.render.render(write_still=True)
                paths.append(p)
    return paths


# ---------------------------------------------------------------------------
# Side views, for the screen the player picks a car on: seen square from its
# right, facing right, lit from above and in front of the camera, in a
# frame of SIDE_CELLS mode 0 pixels (each CELL_PX render pixels: twice as
# wide as a line is high), SIDE_PX pixels a metre, heights times SIDE_SQUASH.
# ---------------------------------------------------------------------------
SIDE_CELLS = (88, 40)
SIDE_PX = 15.0                             # mode 0 pixels a metre along the car
SIDE_SQUASH = globals().get("SIDE_SQUASH", 0.8)


def side_glass():
    """The windows' sky stripes slanting along the car (car3d.glass's go
    across it)."""
    m = c3.material("GLASS")[0]
    m.name = "GLASS"
    nt = m.node_tree
    tc = nt.nodes.new("ShaderNodeTexCoord")
    xyz = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], xyz.inputs[0])
    slant = nt.nodes.new("ShaderNodeMath")
    slant.operation = "MULTIPLY_ADD"
    slant.inputs[1].default_value = 0.9
    nt.links.new(xyz.outputs["Z"], slant.inputs[0])
    nt.links.new(xyz.outputs["Y"], slant.inputs[2])
    freq = nt.nodes.new("ShaderNodeMath")
    freq.operation = "MULTIPLY"
    freq.inputs[1].default_value = 2.2
    nt.links.new(slant.outputs[0], freq.inputs[0])
    frac = nt.nodes.new("ShaderNodeMath")
    frac.operation = "FRACT"
    nt.links.new(freq.outputs[0], frac.inputs[0])
    lt = nt.nodes.new("ShaderNodeMath")
    lt.operation = "LESS_THAN"
    lt.inputs[1].default_value = 0.25
    nt.links.new(frac.outputs[0], lt.inputs[0])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = c3.rgba("NAVY")
    mix.inputs["B"].default_value = c3.rgba("SKY")
    nt.links.new(lt.outputs[0], mix.inputs["Factor"])
    c3.emit(nt, mix.outputs["Result"])
    return m


def side_light(steps):
    """The body's light steps for the side: the flank its colour, what faces
    up its light one."""
    m = bpy.data.materials.get("BODY")
    ramp = next(n for n in m.node_tree.nodes if n.type == "VALTORGB")
    for el, pos in zip(ramp.color_ramp.elements, steps):
        el.position = pos


def side_camera(y_mid, z_mid):
    sc = bpy.context.scene
    cam_data = bpy.data.cameras.new("Side")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("Side", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = (12.0, y_mid, z_mid)
    cam.rotation_euler = (math.pi / 2, 0, math.pi / 2)    # looking along -X
    sc.render.resolution_x = SIDE_CELLS[0] * c3.CELL_PX[0]
    sc.render.resolution_y = SIDE_CELLS[1] * c3.CELL_PX[1]
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.ortho_scale = SIDE_CELLS[0] / SIDE_PX
    return cam


def side_render(names=("player", "ferrari", "lotus", "bmw")):
    paths = []
    os.makedirs(OUT_DIR, exist_ok=True)
    glass = c3.glass
    c3.glass = side_glass                   # (car3d.build calls it too)
    try:
        for name in names:
            clear()
            car = player() if name == "player" else MODELS[name]()
            root = bpy.data.objects.new("Squash", None)
            bpy.context.collection.objects.link(root)
            root.scale = (1, 1, SIDE_SQUASH)
            car.parent = root
            # the frame's bottom on the ground, less 2 lines; the car's
            # middle (rear face to nose, 4.45 m) in the middle
            h = SIDE_CELLS[1] / 2.0 / (2 * SIDE_PX)          # metres, half
            side_camera(4.45 / 2, h - 2 / (2 * SIDE_PX))
            rot = (0, math.radians(35), math.radians(15))   # from the camera's
            if PHOTO:                                       # side, above, a
                photoreal(PAINT[name])                      # little in front
                photo_setup(rot)
            else:
                side_light((0.0, 0.3, 0.99))    # (the sails caught it: stripes)
                c3.setup()
                bpy.data.objects["Sun"].rotation_euler = rot
            p = os.path.join(OUT_DIR, "side_%s.png" % name)
            bpy.context.scene.render.filepath = p
            bpy.ops.render.render(write_still=True)
            paths.append(p)
    finally:
        c3.glass = glass
    return paths


if globals().get("RUN", False):
    result = dict(paths=render())
if globals().get("SIDE", False):
    result = dict(paths=side_render())
