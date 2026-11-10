"""The four cars as 3D models, for their sprites' views (tools/mkcars.py),
each built to the drawings and the figures of the car it is after: a
Ferrari Testarossa twice - the BERLINETTA, and the ROSSO GT with a lip on
its tail and bigger rims - a Lotus Esprit S2/S3 (the WEDGE TURBO, yellow)
and a BMW M3 Touring (the TOURING, white). No badges. Their bodies are
curved: car3d.py's lofts, arches and fenders. A model's axles and length
are its own (axles, new_car); the views turn it about its rear axle.

Run inside Blender 4.2 or later (exec() through an MCP), with TOOLS set to
this directory and OUT_DIR to where the renders go: it takes car3d.py's
pens, shapes, camera and light - the same frame and scale for all, the
rear face laid out on the frame's grid - and renders each car seen from
behind, on the level, going uphill (its nose up PITCH degrees) and
downhill, each straight and turning left by car3d.YAW degrees, to
OUT_DIR/<car>_<flat|up|down>_<0|left>.png. Turning right is the left view
mirrored. CARS (default all four) picks which, TURNS (default both) the
straight ("0") or the turning ("left") views, YAW (default car3d's) the
turn; PHOTO (default) renders them photorealistic. SPIN renders the crash's
view instead (spin_render).
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
YAW = globals().get("YAW", c3.YAW)         # degrees, turning (car3d's)
TURNS = globals().get("TURNS", ("0", "left"))   # the views rendered: "left"
                                                # alone for the turning ones

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


def new_car(length):
    """The empty a model's parts hang from, its length (rear face to nose)
    noted on it."""
    car = bpy.data.objects.new("Car", None)
    bpy.context.collection.objects.link(car)
    car["length"] = length
    return car


def axles(rear, front, rear_r=0.34, front_r=0.31):
    """The car's axles, metres from its rear face, and its tyres' radii -
    car3d's, for its arches and the helpers here: set first by a model.
    The views turn it about its rear axle (place)."""
    c3.REAR_AXLE, c3.FRONT_AXLE, c3.REAR_R, c3.FRONT_R = rear, front, rear_r, front_r


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


def wheels(car, tyre_out, tyre_w, k, n, hub, front_in=0.04, hub_r=0.55):
    for sx in (-1, 1):
        wheel("tyre_r", k, n, sx * (tyre_out - tyre_w / 2), c3.REAR_AXLE, c3.REAR_R, tyre_w,
              car, hub, hub_r)
        wheel("tyre_f", k, n, sx * (tyre_out - front_in - tyre_w * 0.4), c3.FRONT_AXLE,
              c3.FRONT_R, tyre_w * 0.8, car, hub, hub_r)


def exhaust(car, mat, x, z, r=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=r or CX, depth=0.12,
                                        location=(x, -0.05, z), rotation=(math.pi / 2, 0, 0))
    ob = bpy.context.object
    ob.name = "exhaust"
    ob.data.materials.append(mat)
    ob.parent = car


def testarossa(restomod=False):
    """After a Ferrari Testarossa's drawings (getoutlines.com, CC BY 4.0;
    its height to the real 1.13 m): wide and flat, the widest at the hips
    before the rear wheels; the tail a grille of black slats right across,
    the lights glowing through at its ends, the plate under it, two pairs
    of exhausts; a flat engine cover, louvred, between two sails sloping
    up to the roof; a small cabin set forward, its rear window upright;
    strakes along the flanks into the side intakes. restomod (the ROSSO
    GT): a lip on the tail, bigger rims."""
    axles(0.84, 3.39, 0.33, 0.315)
    length = 4.485
    body = c3.toon("BODY", [(0.0, "CAR_DARK"), (0.35, "RED"), (0.97, "ORANGE")])
    k, d, w = c3.flat("BLACK"), c3.flat("CAR_DARK"), c3.flat("WHITE")
    r, o = c3.flat("RED"), c3.flat("ORANGE")
    n, gl = c3.flat("NAVY"), c3.glass()
    car = new_car(length)

    top = 9                                         # the grille's top line
    sh = Shape([(0, 0.89), (0.05, 0.925), (0.15, 0.945), (0.5, 0.975), (0.8, 0.968),
                (1.2, 0.995), (1.45, 0.99), (2.0, 0.952), (2.6, 0.918), (3.3, 0.912),
                (3.7, 0.89), (4.0, 0.857), (4.2, 0.81), (4.35, 0.75), (4.44, 0.62),
                (length, 0.45)],
               Z0,
               [(0, zl(top + 0.2)), (0.08, zl(top + 0.5)), (0.4, zl(top + 0.6)),
                (1.3, zl(top + 0.7)), (2.2, zl(top + 0.4)), (2.9, zl(top + 0.4)),
                (3.15, zl(top + 0.5)), (3.4, zl(top + 0.2)), (3.6, zl(8.6)), (3.9, zl(7.6)),
                (4.1, zl(6.9)), (4.3, zl(5.8)), (4.42, zl(5.0)), (length, zl(3.8))],
               [(0, 6.0), (1.5, 7.0), (2.5, 5.0), (3.5, 4.0), (length, 2.6)])
    body_and_arches(car, sh, length, body, k)
    tail = sh.outline(0.0, 0.02)
    # the cabin: an upright rear window, a flat roof, the windscreen raked
    # down to the cowl; glass all round under the roof
    def slot(y, x, z, u):
        f = abs(u - 0.5)
        if y < 1.3:                                 # the rear window, its
            return 0 if f < 0.3 else 1              # frame
        if y < 2.3:                                 # the roof, the side
            return 1 if f < 0.22 else 0             # windows
        return 1 if f > 0.44 else 0                 # the windscreen
    cabin = Shape([(1.16, 0.58), (1.5, 0.70), (2.5, 0.73), (3.15, 0.76)], on(sh),
                  [(1.16, zl(top + 0.9)), (1.22, zl(13.7)), (1.35, zl(14.4)), (2.0, zl(14.7)),
                   (2.2, zl(14.45)), (2.4, zl(13.8)), (2.7, zl(12.2)), (3.0, zl(10.3)),
                   (3.15, zl(top + 0.6))], 3.5)
    loft("cabin", [gl, body], cabin, stations(1.16, 3.15, 0.03), car, slot=slot)
    # the sails: from the roof's back corners down to the tail
    sail = Shape([(0.1, 0.06), (1.2, 0.07)], on(sh),
                 [(0.1, zl(top + 0.3)), (0.4, zl(9.9)), (0.8, zl(11.0)), (1.1, zl(12.3)),
                  (1.2, zl(13.5))], 4.0, [(0.1, 0.62), (1.2, 0.56)])
    for sx in (-1, 1):
        loft("sail", [body], sail, stations(0.1, 1.2, 0.05), car, side=sx)
    # the engine cover between them: black louvres
    for i in range(7):
        y = 0.3 + 0.14 * i
        z = sh.top(y)
        box("louvre", k, -0.5, 0.5, y, y + 0.07, z - 0.02, z + 0.012, car)
    # the tail: the grille - black slats, the lights through them at the
    # ends, the indicators outermost, a dark glow between - the plate in a
    # black frame under it, then the body down to two pairs of exhausts
    # either side of a black valance
    panel("grille", k, -0.93, 0.93, zl(4), zl(top), car, 0, tail)
    for row in (5, 7):
        panel("glow", d, -0.52, 0.52, zl(row), zl(row + 1), car, 1, tail)
        for sx in (-1, 1):
            panel("light", r, sx * 0.52, sx * 0.78, zl(row), zl(row + 1), car, 1, tail)
            panel("amber", o, sx * 0.78, sx * 0.92, zl(row), zl(row + 1), car, 1, tail)
    panel("frame", k, col(12), -col(12), zl(2), zl(4), car, 1)
    panel("plate", w, col(13.5), -col(13.5), zl(2), zl(4), car, 2)
    panel("valance", k, -0.33, 0.33, zl(0), zl(1.5), car, 1)
    for sx in (-1, 1):
        for x in (0.38, 0.47):
            exhaust(car, w, sx * x, zl(1), 0.035)
    if restomod:                                    # a lip on the tail
        sl = sh.top(0.0)
        box("lip", body, -0.86, 0.86, 0.0, 0.14, sl - 0.02, sl + 0.06, car)
    # under the body: black
    panel("diffuser", k, -0.75, 0.75, LZ, Z0, car)
    box("under", k, -0.75, 0.75, 0.0, 4.1, LZ, Z0, car)
    # strakes along the flanks into the side intakes
    for sx in (-1, 1):
        for row in (0.6, 1.8, 3.0, 4.2, 5.4):
            strip("strake", k, sh, stations(1.5, 2.95, 0.05), zl(row), zl(row + 0.6), car, side=sx)
    sills(car, sh, k)
    wheels(car, 0.98, 0.30, k, n, c3.flat("GREY"), front_in=0.10, hub_r=0.7 if restomod else 0.6)
    return car


def ferrari():
    """The BERLINETTA: as it left Maranello."""
    return testarossa()


def player():
    """The ROSSO GT: a Testarossa made new (its picture: an image made by
    an AI, "Drago Rosso") - from behind as the old one."""
    return testarossa(restomod=True)


def lotus():
    """After a Lotus Esprit S2/S3's drawings (the-blueprints.com; its
    width from getoutlines.com's Turbo HC, CC BY 4.0): a wedge with crisp
    edges, low at the nose, nearly as wide at the tail as at the doors; a
    cabin of flat glass, its rear window upright between two sails sloping
    down to the tail; a black louvred engine cover between them; the tail
    upright, a band of lights across it - amber outermost - with the plate
    between them, a black bumper under it, wrapping round along the
    flanks."""
    axles(0.75, 3.17, 0.31, 0.30)
    length = 4.19
    body = c3.toon("BODY", [(0.0, "ORANGE"), (0.35, "YELLOW")])
    k, w = c3.flat("BLACK"), c3.flat("WHITE")
    r, o = c3.flat("RED"), c3.flat("ORANGE")
    n, gl = c3.flat("NAVY"), c3.glass()
    lv = stripes("LOUVRES", "BLACK", "NAVY", 2 * LZ, 0.5)
    car = new_car(length)

    top = 9.1                                       # the tail's lip
    sh = Shape([(0, 0.86), (0.05, 0.895), (0.2, 0.905), (1.0, 0.92), (2.0, 0.93),
                (3.0, 0.92), (3.9, 0.89), (4.1, 0.86), (length, 0.78)],
               Z0,
               [(0, zl(top - 0.6)), (0.06, zl(top)), (0.5, zl(top)), (1.3, zl(top + 0.1)),
                (2.95, zl(9.4)), (3.2, zl(8.3)), (3.5, zl(6.7)), (3.8, zl(5.1)), (4.0, zl(4.0)),
                (length, zl(3.0))],
               [(0, 6.0), (2.9, 5.5), (length, 4.0)])
    body_and_arches(car, sh, length, body, k)
    tail = sh.outline(0.0, 0.02)
    # the cabin: the rear window upright, a flat roof, the windscreen raked
    # far forward; glass all round under the roof
    def slot(y, x, z, u):
        f = abs(u - 0.5)
        if y < 1.32:                                # the rear window
            return 0 if f < 0.34 else 1
        if y < 2.15:                                # the roof, the side
            return 1 if f < 0.2 else 0              # windows
        return 1 if f > 0.45 else 0                 # the windscreen
    cabin = Shape([(1.22, 0.72), (1.5, 0.79), (2.5, 0.80), (2.97, 0.82)], on(sh),
                  [(1.22, zl(10.6)), (1.28, zl(13.5)), (1.38, zl(14.2)), (2.1, zl(14.2)),
                   (2.2, zl(13.6)), (2.4, zl(12.2)), (2.6, zl(11.1)), (2.8, zl(10.1)),
                   (2.97, zl(9.6))], 3.7)
    loft("cabin", [gl, body], cabin, stations(1.22, 2.97, 0.03), car, slot=slot)
    # the sails, from the roof's back corners down to the tail, and the
    # louvred engine cover between them
    sail = Shape([(0.08, 0.10), (1.3, 0.09)], on(sh),
                 [(0.08, zl(top)), (0.4, zl(9.9)), (0.6, zl(10.9)), (0.9, zl(12.2)),
                  (1.1, zl(13.2)), (1.3, zl(13.8))], 4.0, [(0.08, 0.7), (1.3, 0.64)])
    for sx in (-1, 1):
        loft("sail", [body], sail, stations(0.08, 1.3, 0.05), car, side=sx)
    deck = Shape(0.62, on(sh), [(0.15, zl(top + 0.3)), (1.24, zl(10.8))], 8.0)
    loft("louvres", [lv], deck, stations(0.15, 1.24, 0.05), car)
    # the tail: a black band of lights, the plate between; the bumper under
    # it; below, the body round a black valance, the exhaust on the right
    panel("panel", k, -0.79, 0.79, zl(5), zl(8), car, 0, tail)
    for sx in (-1, 1):
        panel("light", r, sx * 0.31, sx * 0.64, zl(5), zl(8), car, 1, tail)
        panel("amber", o, sx * 0.64, sx * 0.78, zl(5), zl(8), car, 1, tail)
    panel("plate", w, -0.25, 0.25, zl(6), zl(8), car, 1)
    panel("bumper", k, -0.9, 0.9, zl(2), zl(4), car, 0, tail)
    panel("valance", k, -0.55, 0.55, zl(0.5), zl(1.5), car, 0, tail)
    exhaust(car, w, 0.5, zl(1), 0.035)
    exhaust(car, w, 0.58, zl(1), 0.035)
    panel("diffuser", k, -0.7, 0.7, LZ, Z0, car)
    box("under", k, -0.7, 0.7, 0.0, 3.9, LZ, Z0, car)
    # along the flanks the bumper's black band, and the sills
    for sx in (-1, 1):
        for y0, y1 in spans(length):
            strip("bumper", k, sh, stations(y0, y1, 0.05), zl(2), zl(4), car, side=sx)
    sills(car, sh, k)
    wheels(car, 0.93, 0.27, k, n, c3.flat("GREY"), front_in=0.03)
    return car


def bmw():
    """After a BMW M3 Touring (G81): its makers' figures (4.79 m long, the
    axles 2.86 m apart, 1.44 m high), the side in BMW's picture, the rear
    in photographs (Wikimedia Commons, CC BY-SA) - all of it 0.93 times
    (as tall as fits the frame). An estate: a long roof down to a raked
    tailgate, a spoiler over the rear window, broad pillars either side of
    it; the lights in an L at each corner, the plate between them in the
    tailgate; wide hips over the rear wheels; under the bumper a black
    diffuser, two pairs of exhausts."""
    axles(1.03, 3.69, 0.316, 0.314)
    length = 4.458
    body = c3.toon("BODY", [(0.0, "PASTEL"), (0.35, "WHITE")])
    k, w = c3.flat("BLACK"), c3.flat("WHITE")
    r = c3.flat("RED")
    n, gl = c3.flat("NAVY"), c3.glass()
    car = new_car(length)

    top = 11                                        # the tailgate's foot
    sh = Shape([(0, 0.78), (0.06, 0.82), (0.2, 0.84), (0.75, 0.88), (1.3, 0.885),
                (1.7, 0.86), (2.8, 0.855), (3.5, 0.87), (3.9, 0.86), (4.2, 0.82), (4.38, 0.76),
                (length, 0.66)],
               Z0,
               [(0, zl(top + 0.2)), (0.08, zl(top + 0.4)), (0.5, zl(top + 0.4)),
                (2.0, zl(top + 0.2)), (3.2, zl(top + 0.1)), (3.6, zl(10.6)), (4.0, zl(9.8)),
                (4.3, zl(8.8)), (4.42, zl(7.2)), (length, zl(5.5))],
               [(0, 8.0), (1.5, 8.0), (3.0, 6.0), (length, 3.5)])
    body_and_arches(car, sh, length, body, k)
    tail = sh.outline(0.0, 0.02)
    # the cabin: the rear window raked between broad pillars, a long roof,
    # the windscreen; glass all round under the roof
    def slot(y, x, z, u):
        f = abs(u - 0.5)
        if y < 0.55:                                # the rear window, the
            return 0 if f < 0.3 else 1              # pillars
        if y < 2.42:                                # the roof, the side
            return 1 if f < 0.25 else 0             # windows
        return 1 if f > 0.45 else 0                 # the windscreen
    cabin = Shape([(0.22, 0.68), (0.6, 0.73), (2.4, 0.76), (3.25, 0.78)], on(sh),
                  [(0.22, zl(top + 0.6)), (0.3, zl(13.0)), (0.42, zl(15.3)), (0.55, zl(16.8)),
                   (0.8, zl(17.6)), (1.3, zl(18.0)), (2.0, zl(18.0)), (2.35, zl(17.7)),
                   (2.6, zl(16.3)), (2.9, zl(14.0)), (3.1, zl(12.4)), (3.25, zl(top + 0.4))], 3.3)
    loft("cabin", [gl, body], cabin, stations(0.22, 3.25, 0.03), car, slot=slot)
    # the spoiler over the rear window
    box("wing_k", k, -0.6, 0.6, 0.4, 0.62, zl(16.9), zl(17.5), car)
    # the rear face: an L of lights at each corner, the plate under the
    # tailgate in a black recess, the bumper, a black diffuser under it
    # with two pairs of exhausts, the reflectors at the bumper's corners
    for sx in (-1, 1):
        panel("light", r, sx * 0.42, sx * 0.8, zl(9), zl(10), car, 1, tail)
        panel("light", r, sx * 0.62, sx * 0.8, zl(8), zl(9), car, 1, tail)
        panel("light", r, sx * 0.7, sx * 0.77, zl(2), zl(4), car, 1, tail)
    panel("frame", k, -0.3, 0.3, zl(4), zl(8), car, 1)
    panel("plate", w, -0.24, 0.24, zl(5), zl(7), car, 2)
    panel("diffuser", k, -0.68, 0.68, zl(0), zl(2), car, 1, tail)
    for sx in (-1, 1):                              # (its ends up the bumper)
        panel("diffuser", k, sx * 0.6, sx * 0.68, zl(2), zl(4), car, 1, tail)
    for sx in (-1, 1):
        for x in (0.4, 0.5):
            exhaust(car, w, sx * x, zl(1), 0.045)
    panel("diffuser", k, -0.68, 0.68, LZ, Z0, car)
    box("under", k, -0.68, 0.68, 0.0, 4.1, LZ, Z0, car)
    sills(car, sh, k)
    wheels(car, 0.9, 0.27, k, n, c3.flat("GREY"), front_in=0.04, hub_r=0.72)
    return car


MODELS = dict(player=player, ferrari=ferrari, lotus=lotus, bmw=bmw)

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
        red=principled("lens_red", (0.6, 0.0, 0.0), 0.08, emit=(1.0, 0.02, 0.0), strength=1.5),
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
        "valance": "plastic", "middle": "dark", "glow": "dark", "amber": "amber", "lamp": "clear",
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
    p = Vector((0, c3.REAR_AXLE, 0))
    car.rotation_euler = e
    car.location = p - e.to_matrix() @ p


def render():
    paths = []
    os.makedirs(OUT_DIR, exist_ok=True)
    for name in CARS:
        clear()
        car = MODELS[name]()
        # squashed after it is pitched, as the slope under it would be: the
        # car as low as the game's cars are, the slope as gentle
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
                if yname not in TURNS:
                    continue
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
            car = MODELS[name]()
            root = bpy.data.objects.new("Squash", None)
            bpy.context.collection.objects.link(root)
            root.scale = (1, 1, SIDE_SQUASH)
            car.parent = root
            # the frame's bottom on the ground, less 2 lines; the car's
            # middle (rear face to nose) in the middle
            h = SIDE_CELLS[1] / 2.0 / (2 * SIDE_PX)          # metres, half
            side_camera(car["length"] / 2, h - 2 / (2 * SIDE_PX))
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


# ---------------------------------------------------------------------------
# The crash's view: the car on the level spun SPIN_YAW degrees (nose left)
# about its middle, so its tail swings out - the same camera, scale and
# light as the other views, in a frame SPIN_CELLS wide (the others' frame in
# its middle: the tail goes past their right edge), to
# OUT_DIR/<car>_spin.png. Spun right is this mirrored.
# ---------------------------------------------------------------------------
SPIN_YAW = 30.0
SPIN_CELLS = 80


def spin_render():
    paths = []
    os.makedirs(OUT_DIR, exist_ok=True)
    sc = bpy.context.scene
    for name in CARS:
        clear()
        car = MODELS[name]()
        root = bpy.data.objects.new("Squash", None)
        bpy.context.collection.objects.link(root)
        root.scale = (1, 1, c3.SQUASH)
        car.parent = root
        cam = c3.camera()
        # the frame wider, the scale and the lines as they were
        resx = sc.render.resolution_x
        shift = cam.data.shift_y * resx
        sc.render.resolution_x = SPIN_CELLS * c3.CELL_PX[0]
        cam.data.lens *= resx / sc.render.resolution_x
        cam.data.shift_y = shift / sc.render.resolution_x
        if PHOTO:
            photoreal(PAINT[name])
            photo_setup((math.radians(45), 0, 0))
        else:
            c3.setup()
        e = Euler((0, 0, math.radians(SPIN_YAW)), "XYZ")
        p = Vector((0, car["length"] / 2, 0))     # its middle
        car.rotation_euler = e
        car.location = p - e.to_matrix() @ p
        path = os.path.join(OUT_DIR, "%s_spin.png" % name)
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        paths.append(path)
    return paths


if globals().get("RUN", False):
    result = dict(paths=render())
if globals().get("SPIN", False):
    result = dict(paths=spin_render())
if globals().get("SIDE", False):
    result = dict(paths=side_render())
