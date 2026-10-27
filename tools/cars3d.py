"""Three more sports cars as 3D models, for their sprites' views
(tools/mkcars.py): a wide red one with a grille across its tail (after a
Ferrari Testarossa), a low yellow wedge with a louvred engine cover (after
a Lotus Esprit) and a white saloon with a wing on its boot, flared arches
and racing stripes (after a BMW M3 of the eighties). No badges. Their
bodies are curved, as the player's: car3d.py's lofts, arches and fenders.

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
panel, box, wheel = c3.panel, c3.box, c3.wheel
Shape, loft, strip, stations = c3.Shape, c3.loft, c3.strip, c3.stations


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


def mirrored(car, name, mat, c0, c1, n0, n1, depth=0, clip=None):
    """A panel on the rear face over columns c0..c1 and its mirror image."""
    panel(name, mat, col(c0), col(c1), zl(n0), zl(n1), car, depth, clip)
    panel(name, mat, -col(c1), -col(c0), zl(n0), zl(n1), car, depth, clip)


def on(sh):
    """A line just under a body's top: what its cabin and sails stand on."""
    return lambda y: sh.top(y) - 0.03


def spans(length):
    """A flank's stretches clear of the wheel arches, as (y0, y1)."""
    r0 = c3.REAR_AXLE - c3.REAR_R - c3.ARCH_GAP
    r1 = c3.REAR_AXLE + c3.REAR_R + c3.ARCH_GAP
    f0 = c3.FRONT_AXLE - c3.FRONT_R - c3.ARCH_GAP
    f1 = c3.FRONT_AXLE + c3.FRONT_R + c3.ARCH_GAP
    return [(0.1, r0 - 0.01), (r1 + 0.01, f0 - 0.01), (f1 + 0.01, length - 0.15)]


def body_and_arches(car, sh, length, mat, well, notch=0.6):
    """A body: `sh` lofted from the rear face to the nose, the wheel
    arches cut into it."""
    cut, edges = c3.arches([(c3.REAR_AXLE, c3.REAR_R), (c3.FRONT_AXLE, c3.FRONT_R)])
    return loft("body", [mat, well], sh, stations(0.0, length, 0.04, edges), car,
                cut=cut, notch=notch, well=1)


def sills(car, sh, mat):
    """Black sills along the flanks behind and between the arches."""
    for sx in (-1, 1):
        for y0, y1 in spans(0)[:2]:
            strip("sill", mat, sh, stations(y0, y1, 0.05), Z0 + c3.NOTCH_MIN, zl(1), car, side=sx)


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
    lights glowing through at its ends; broad hips over the rear wheels; a
    long flat engine cover between two sails; strakes along the flanks into
    the side intakes."""
    body = c3.toon("BODY", [(0.0, "CAR_DARK"), (0.35, "RED"), (0.97, "ORANGE")])
    k, d, w = c3.flat("BLACK"), c3.flat("CAR_DARK"), c3.flat("WHITE")
    r = c3.flat("RED")
    n, gl = c3.flat("NAVY"), c3.glass()
    car = bpy.data.objects.new("Car", None)
    bpy.context.collection.objects.link(car)

    top = 8                                         # the rear face's lines
    sh = Shape([(0, 0.91), (0.06, 0.96), (0.2, 0.99), (0.45, 1.0), (1.6, 1.0), (2.6, 0.96),
                (3.5, 0.955), (4.05, 0.93), (4.3, 0.83), (4.42, 0.66), (4.45, 0.55)],
               Z0,
               [(0, zl(top - 0.6)), (0.1, zl(top - 0.1)), (0.25, zl(top + 0.05)), (1.8, zl(top + 0.1)),
                (3.25, zl(top - 0.4)), (3.9, zl(6.2)), (4.3, zl(4.6)), (4.45, zl(3.4))],
               [(0, 5.5), (0.6, 5.0), (3.5, 4.2), (4.45, 2.6)])
    body_and_arches(car, sh, 4.45, body, k)
    tail = sh.outline(0.0, 0.02)
    c3.fenders("fender", body, k, [
        (c3.REAR_AXLE, c3.REAR_R, 0.84, 0.18, (zl(top), zl(9.4), zl(top)), (0.3, 0.3)),
        (c3.FRONT_AXLE, c3.FRONT_R, 0.856, 0.16, (zl(top - 0.4), zl(8.6), zl(3.6)),
         (0.3, 0.12))], car)
    # the cabin, set forward: a small upright rear window, glass all round
    # under a flat roof
    cabin = Shape([(1.75, 0.55), (2.4, 0.66), (3.3, 0.72)], on(sh),
                  [(1.75, zl(top + 0.4)), (2.0, zl(top + 5.4)), (2.35, zl(top + 6)),
                   (2.7, zl(top + 5.7)), (3.3, zl(top - 0.1))], 3.0)
    loft("cabin", [gl, body], cabin, stations(1.75, 3.3, 0.03), car,
         slot=lambda y, x, z, u: 1 if 2.0 < y < 2.75 and abs(u - 0.5) < 0.2 else 0)
    # the sails: from the roof's back corners down to the tail
    sail = Shape([(0.2, 0.15), (2.0, 0.08)], on(sh),
                 [(0.2, zl(top + 0.5)), (1.1, zl(top + 1.6)), (2.0, zl(top + 5.2))], 4.0,
                 [(0.2, 0.82), (2.0, 0.52)])
    for sx in (-1, 1):
        loft("sail", [body], sail, stations(0.2, 2.0, 0.05), car, side=sx)
    # the engine cover between them: black louvres at its back
    for y in (0.35, 0.6, 0.85):
        z = sh.top(y)
        box("louvre", k, -0.55, 0.55, y, y + 0.1, z - 0.02, z + 0.015, car)
    # the tail: the grille - slats over the lights at the ends, a dark glow
    # between - over a black band, the plate; cut to its rounded outline
    panel("grille", k, col(1.5), -col(1.5), zl(0), zl(top - 1), car, 0, tail)
    for row in (2, 4, 6):
        panel("glow", d, col(9), -col(9), zl(row - 1), zl(row), car, 1, tail)
        mirrored(car, "light", r, 2.5, 9, row - 1, row, 1, tail)
    panel("frame", k, col(13), -col(13), zl(0), zl(2), car, 2)
    panel("plate", w, col(14), -col(14), zl(0), zl(2), car, 3)
    # under the body: black, and two pairs of exhausts
    panel("diffuser", k, col(5), -col(5), LZ, Z0, car)
    box("under", k, col(5), -col(5), 0.0, 4.1, LZ, Z0, car)
    for sx in (-1, 1):
        for cc in (9.5, 12):
            exhaust(car, w, sx * -col(cc), 2 * LZ)
    # strakes along the flanks into the side intakes
    sills(car, sh, k)
    for sx in (-1, 1):
        for row in (1.5, 3, 4.5, 6):
            strip("strake", k, sh, stations(1.45, 3.15, 0.05), zl(row), zl(row + 0.6), car, side=sx)
    wheels(car, 1.02, 0.36, k, n, c3.flat("GREY"), front_in=0.02)
    return car


def lotus():
    """A wedge, its edges rounded: low at the nose, its tail upright with a
    lip on top; over the engine a cover of black louvres sloping up to the
    roof between two sails; the lights on a black panel; the fenders
    swelling over the front wheels."""
    body = c3.toon("BODY", [(0.0, "ORANGE"), (0.35, "YELLOW")])
    k, w = c3.flat("BLACK"), c3.flat("WHITE")
    r, o = c3.flat("RED"), c3.flat("ORANGE")
    n, gl = c3.flat("NAVY"), c3.glass()
    lv = stripes("LOUVRES", "BLACK", "NAVY", 2 * LZ, 0.5)
    car = bpy.data.objects.new("Car", None)
    bpy.context.collection.objects.link(car)

    top = 8.2
    sh = Shape([(0, 0.86), (0.06, 0.91), (0.2, 0.94), (0.45, 0.95), (1.8, 0.95), (2.6, 0.93),
                (3.5, 0.93), (3.9, 0.9), (4.1, 0.8), (4.2, 0.62)],
               Z0,
               [(0, zl(top - 0.6)), (0.07, zl(top + 0.4)), (0.2, zl(top + 0.1)), (0.5, zl(top - 0.1)),
                (1.7, zl(top - 0.8)), (3.3, zl(5.6)), (3.9, zl(4.8)), (4.1, zl(3.9)), (4.2, zl(2.8))],
               [(0, 5.5), (0.6, 5.0), (3.0, 4.0), (4.2, 2.6)])
    body_and_arches(car, sh, 4.2, body, k)
    tail = sh.outline(0.0, 0.02)
    c3.fenders("fender", body, k, [
        (c3.REAR_AXLE, c3.REAR_R, 0.81, 0.17, (zl(top - 0.2), zl(9.4), zl(top - 0.6)), (0.3, 0.3)),
        (c3.FRONT_AXLE, c3.FRONT_R, 0.842, 0.15, (zl(6.0), zl(8.3), zl(3.6)), (0.3, 0.05))],
        car)
    # over the engine the louvres between the sails, up to the cabin: glass
    # sides, a flat roof, the windscreen raked far forward
    def slot(y, x, z, u):
        if y < 1.75:
            return 1 if abs(u - 0.5) < 0.2 else 2
        return 2 if 1.8 < y < 2.55 and abs(u - 0.5) < 0.2 else 0
    gh = Shape([(0.25, 0.62), (1.7, 0.68), (2.5, 0.72), (3.4, 0.8)], on(sh),
               [(0.25, zl(top + 0.5)), (1.7, zl(top + 4.3)), (2.1, zl(top + 4.8)),
                (2.5, zl(top + 4.6)), (3.4, zl(5.8))], 3.0)
    loft("cabin", [gl, lv, body], gh, stations(0.25, 3.4, 0.03), car, slot=slot)
    # the tail: a black panel with the lights, a black bumper, the plate
    panel("panel", k, col(2), -col(2), zl(2), zl(5), car, 0, tail)
    for row, mat in ((5, r), (4, r), (3, o)):
        mirrored(car, "light", mat, 2.5, 9, row - 1, row, 1, tail)
    panel("bumper", k, col(2), -col(2), zl(0), zl(1), car, 0, tail)
    panel("frame", k, col(13), -col(13), zl(0), zl(3), car, 2)
    panel("plate", w, col(14), -col(14), zl(0.5), zl(2.5), car, 3)
    panel("diffuser", k, col(6), -col(6), LZ, Z0, car)
    box("under", k, col(6), -col(6), 0.0, 3.9, LZ, Z0, car)
    exhaust(car, w, -col(11), 2 * LZ)
    exhaust(car, w, col(11), 2 * LZ)
    sills(car, sh, k)
    for sx in (-1, 1):
        strip("intake", k, sh, stations(1.5, 2.3, 0.05), zl(3), zl(5.5), car, side=sx)
    wheels(car, 0.97, 0.32, k, n, c3.flat("GREY"), front_in=0.0)
    return car


def bmw():
    """A saloon, square but its corners rounded: an upright boot with a wing
    on it, wide lights, flared arches over the wheels, a tall cabin with
    broad rear pillars; stripes in light blue, dark blue and red along it."""
    body = c3.toon("BODY", [(0.0, "PASTEL"), (0.35, "WHITE")])
    k, w = c3.flat("BLACK"), c3.flat("WHITE")
    r, o = c3.flat("RED"), c3.flat("ORANGE")
    n, s, gl = c3.flat("NAVY"), c3.flat("SKY"), c3.glass()
    car = bpy.data.objects.new("Car", None)
    bpy.context.collection.objects.link(car)

    hw = 0.85
    top = 10                                        # the boot lid's line
    sh = Shape([(0, 0.8), (0.06, 0.835), (0.18, hw), (4.15, hw), (4.28, 0.82), (4.36, 0.74),
                (4.4, 0.6)],
               Z0,
               [(0, zl(top - 0.5)), (0.12, zl(top)), (3.2, zl(top)), (3.4, zl(top - 0.4)),
                (4.2, zl(top - 1.8)), (4.4, zl(top - 3.6))],
               [(0, 6.0), (4.0, 6.0), (4.4, 4.0)])
    body_and_arches(car, sh, 4.4, body, k)
    tail = sh.outline(0.0, 0.02)
    c3.fenders("fender", body, k, [
        (c3.REAR_AXLE, c3.REAR_R, 0.8, 0.17, (zl(8.5), zl(9.4), zl(8.5)), (0.3, 0.3)),
        (c3.FRONT_AXLE, c3.FRONT_R, 0.83, 0.15, (zl(8.5), zl(8.6), zl(7.0)), (0.3, 0.12))],
        car, p=5.0)
    # the cabin: a sloping rear window between broad pillars, a tall roof
    def slot(y, x, z, u):
        f = abs(u - 0.5)
        if y < 1.55:                                # the rear window, the
            return 0 if f < 0.17 else 1             # pillars
        if y < 2.62:                                # the roof, the side
            return 1 if f < 0.24 else 0             # windows
        return 1 if f > 0.45 else 0                 # the windscreen
    cabin = Shape([(0.95, 0.76), (2.0, 0.74), (3.2, 0.78)], on(sh),
                  [(0.95, zl(top + 0.2)), (1.45, zl(top + 7.6)), (1.6, zl(top + 8.2)),
                   (2.5, zl(top + 8.2)), (2.65, zl(top + 7.8)), (3.2, zl(top))], 4.5)
    loft("cabin", [gl, body], cabin, stations(0.95, 3.2, 0.03), car, slot=slot)
    # the wing on the boot lid's back edge
    box("wing", body, -0.74, 0.74, 0.02, 0.32, zl(top + 1), zl(top + 2), car)
    panel("wing_k", k, -0.74, 0.74, zl(top + 1), zl(top + 1.5), car)
    for sx in (-1, 1):
        box("stand", k, sx * 0.55 - 0.03, sx * 0.55 + 0.03, 0.1, 0.25, zl(top - 0.3), zl(top + 1), car)
    # the rear face: the lights either side of a black panel with the plate,
    # stripes across under them, a black bumper
    for row, mat in ((8, r), (7, r), (6, o), (5, r)):
        mirrored(car, "light", mat, 3.7, 11, row - 1, row, 1, tail)
    mirrored(car, "reverse", w, 10, 11, 4, 5, 2, tail)
    panel("panel", k, col(11), -col(11), zl(4), zl(8), car)
    panel("frame", k, col(13), -col(13), zl(4), zl(7), car, 2)
    panel("plate", w, col(14), -col(14), zl(4.5), zl(6.5), car, 3)
    for row, mat in ((4, s), (3, n), (2, r)):
        panel("stripe", mat, -hw, hw, zl(row - 1), zl(row), car, 1, tail)
    panel("bumper", k, -hw, hw, zl(0), zl(1), car, 1, tail)
    panel("diffuser", k, col(7), -col(7), LZ, Z0, car)
    box("under", k, col(7), -col(7), 0.0, 4.1, LZ, Z0, car)
    exhaust(car, w, col(9), 2 * LZ)
    # along each flank, between the arches: the stripes and the bumper
    for sx in (-1, 1):
        for y0, y1 in spans(4.4):
            ys = stations(y0, y1, 0.05)
            for row, mat in ((4, s), (3, n), (2, r)):
                strip("stripe", mat, sh, ys, zl(row - 1), zl(row), car, side=sx)
            strip("bumper", k, sh, ys, Z0 + c3.NOTCH_MIN, zl(1), car, side=sx)
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
        "rim": "paint", "fender": "paint", "cabin": "glass", "wing_k": "plastic", "pylon": "plastic",
        "stand": "plastic", "grille": "plastic", "frame": "plastic", "diffuser": "plastic",
        "under": "plastic", "sill": "plastic", "strake": "plastic", "louvre": "plastic",
        "panel": "plastic", "bumper": "plastic", "intake": "plastic", "band": "plastic",
        "middle": "dark", "glow": "dark", "amber": "amber", "lamp": "clear",
        "reverse": "clear", "plate": "plate", "exhaust": "chrome"}
BY_PEN = {"light": dict(RED="red", ORANGE="amber"),
          "stripe": dict(SKY="sky", NAVY="navy", RED="red_paint"),
          "wing_r": dict(RED="red_paint"), "wing_o": dict(ORANGE="orange_paint")}


# a part's further materials (a cabin's roof, an arch's walls), by the pen
# they had
SLOT = {"BODY": "paint", "GLASS": "glass", "BLACK": "plastic", "LOUVRES": "plastic"}


def photoreal(paint):
    """Every part of the car built given its real material."""
    P = photo_materials(paint)
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        part = ob.name.split(".")[0]
        olds = [m.name.split(".")[0] for m in ob.data.materials]
        old = olds[0] if olds else ""
        if part.startswith("tyre"):
            mat = P["rim"] if part.endswith("_hub") else P["rubber"]
            for i in range(len(ob.data.materials)):
                ob.data.materials[i] = mat
            continue
        for i in range(1, len(olds)):
            ob.data.materials[i] = P[SLOT[olds[i]]]
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
            bev.limit_method = "ANGLE"          # (a loft's own edges are not)


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
