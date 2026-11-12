"""The traffic's cars as 3D models, for their sprites (tools/mktraffic.py).

Every traffic car is two pieces, seen from behind: a top - the cabin, closed
(a coupe's roof) or open (a convertible's windscreen, seats and driver) -
and a bottom - the body, three kinds of tail: a sports car's round lamps, a
saloon's wide clusters, a GT's light bar. They share one body above its rear
face (the deck, the line they meet on), so any top goes on any bottom. Their
paint is the colour the game gives each car, each piece its own: rendered,
it is marked, and the sprites have it black.

Run inside Blender 4.2 or later as tools/cars3d.py is (exec() through an
MCP), with TOOLS set to this directory and OUT_DIR to where the renders go
(assets/traffic). For each scale in SCALES (the car's size against the
player's) it renders the combinations that hold every top and every bottom
- each top on the first bottom, each bottom under the first top; for the
sizes past the NEAR nearest, each top on FAR_BOTTOM, whole - in three
passes: the car (photorealistic, its paint grey), its paint (white on
black) and its top (white on black), to OUT_DIR/s<i>_<top>_<bottom>_<pass>.png.
SIZES picks which scales (default all). With YAW (degrees) each car is
turned that much, nose left, about its rear face's middle (the rear
face staying where it is: not the rear axle, as the player's car turns) -
seen from a camera off
to its right, its left flank in view, as a near car right of the middle of
the screen is (since 2026-11-12) - to OUT_DIR/s<i>_<top>_<bottom>_<pass>_yaw.png;
COMBOS ([(top, bottom)]) then picks which of the near sizes' pieces.
"""

import importlib.util
import math
import os

import bpy

TOOLS = globals().get("TOOLS", os.path.dirname(os.path.abspath(globals().get("__file__", "."))))
_spec = importlib.util.spec_from_file_location("cars3d", os.path.join(TOOLS, "cars3d.py"))
cs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cs)
c3 = cs.c3

OUT_DIR = globals().get("OUT_DIR", bpy.app.tempdir)
SCALES = [1.1, 0.92, 0.75,                  # the nearest, in two pieces, against
          0.62, 0.5, 0.39, 0.29, 0.2]       # the player's car; then whole ones
NEAR = 3                                    # (the two pieces' sizes)
SIZES = globals().get("SIZES", range(len(SCALES)))
SAMPLES = globals().get("SAMPLES", 32)
TOPS = ["closed", "open"]
BOTTOMS = ["sport", "saloon", "gt"]
FAR_BOTTOM = "saloon"                       # the further sizes' (one piece)
YAW = globals().get("YAW", 0.0)             # degrees, nose left (0: straight)
COMBOS = globals().get("COMBOS", None)      # the near pieces rendered (None: all)

col, zl, LZ, CX, Z0 = c3.col, c3.zl, c3.LZ, c3.CX, c3.Z0
Shape, loft, strip, stations, panel, box = c3.Shape, c3.loft, c3.strip, c3.stations, c3.panel, c3.box

HW = 0.95                                   # the body's half width
DECK = 9                                    # the rear face's lines: the deck on it
TYRE_OUT, TYRE_W = 0.97, 0.3


def face(name, mat, poly, parent, depth=0, clip=None):
    """A flat face on the rear face, any outline ((x, z) going round)."""
    y = -0.004 - 0.001 * depth
    if clip:
        poly = c3.clipped(poly, clip)
        if len(poly) < 3:
            return None
    me = bpy.data.meshes.new(name)
    me.from_pydata([(x, y, z) for x, z in poly], [], [tuple(range(len(poly)))])
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.parent = parent
    return ob


def disc(name, mat, x, z, r, parent, depth=0, clip=None, n=20):
    """A round lamp on the rear face (r in metres across; heights are lines
    of LZ before the squash, so it is drawn an ellipse that the squash makes
    round)."""
    k = 1 / c3.SQUASH
    return face(name, mat, [(x + r * math.cos(2 * math.pi * i / n),
                             z + k * r * math.sin(2 * math.pi * i / n)) for i in range(n)],
                parent, depth, clip)


def body(car, mats):
    """The body every bottom shares above its rear face: one loft, the wheel
    arches, fenders, sills; returns its shape and the rear face's outline."""
    paint, k = mats["paint"], mats["plastic"]
    sh = Shape([(0, 0.86), (0.06, 0.91), (0.2, 0.94), (0.45, HW), (1.6, HW), (2.4, 0.92),
                (3.4, 0.93), (3.95, 0.9), (4.2, 0.8), (4.3, 0.62)],
               Z0,
               [(0, zl(DECK - 0.6)), (0.12, zl(DECK - 0.05)), (0.3, zl(DECK)), (1.2, zl(DECK + 0.1)),
                (3.0, zl(DECK - 0.3)), (3.8, zl(DECK - 1.6)), (4.2, zl(DECK - 3.4)), (4.3, zl(DECK - 4.4))],
               [(0, 5.0), (0.6, 4.6), (3.5, 4.0), (4.3, 2.6)])
    cs.body_and_arches(car, sh, 4.3, paint, k)
    rx, fx = TYRE_OUT - TYRE_W / 2, TYRE_OUT - TYRE_W * 0.4
    c3.fenders("fender", paint, k, [
        (c3.REAR_AXLE, c3.REAR_R, rx, TYRE_W / 2 + 0.01, (zl(DECK), zl(9.3), zl(DECK)), (0.3, 0.3)),
        (c3.FRONT_AXLE, c3.FRONT_R, fx, TYRE_W * 0.4 + 0.02, (zl(DECK - 0.5), zl(8.5), zl(DECK - 3.4)),
         (0.3, 0.1))], car)
    cs.sills(car, sh, k)
    box("under", k, col(6), -col(6), 0.0, 4.0, LZ, Z0, car)
    cs.wheels(car, TYRE_OUT, TYRE_W, k, mats["tread"], mats["hub"], front_in=0.0)
    return sh, sh.outline(0.0, 0.02)


def top_closed(car, sh, mats):
    """A coupe's cabin: a sloping rear window between broad pillars, a
    rounded roof."""
    def slot(y, x, z, u):
        f = abs(u - 0.5)
        if y < 1.55:
            return 0 if f < 0.18 else 1             # the rear window, the pillars
        if y < 2.5:
            return 1 if f < 0.25 else 0             # the roof, the side windows
        return 1 if f > 0.45 else 0                 # the windscreen
    cabin = Shape([(1.05, 0.7), (2.0, 0.7), (3.0, 0.78)], cs.on(sh),
                  [(1.05, zl(DECK + 0.3)), (1.45, zl(DECK + 7.6)), (1.7, zl(DECK + 8.4)),
                   (2.3, zl(DECK + 8.4)), (2.55, zl(DECK + 7.8)), (3.05, zl(DECK - 0.1))], 3.0)
    loft("cabin", [mats["glass"], mats["paint"]], cabin, stations(1.05, 3.05, 0.03), car, slot=slot)


def top_open(car, sh, mats):
    """A convertible's: the windscreen, raked, in a painted frame; two seats
    with headrests, a driver - and behind them the deck, painted."""
    screen = Shape([(2.55, 0.74), (2.9, 0.8)], cs.on(sh),
                   [(2.55, zl(DECK + 5.0)), (2.75, zl(DECK + 2.4)), (2.9, zl(DECK - 0.2))], 6.0)
    loft("cabin", [mats["glass"], mats["paint"]], screen, stations(2.55, 2.9, 0.02), car,
         slot=lambda y, x, z, u: 1 if abs(u - 0.5) > 0.44 else 0)
    for sx in (-1, 1):
        rest = Shape(0.2, cs.on(sh), [(1.62, zl(DECK + 0.5)), (1.68, zl(DECK + 4.2)),
                                      (1.82, zl(DECK + 4.4)), (1.9, zl(DECK + 0.5))], 3.0,
                     sx * 0.42)
        loft("seat", [mats["seat"]], rest, stations(1.62, 1.9, 0.02), car)
    # the driver, on the left: a head over the headrest's top
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.16,
                                         location=(-0.42, 1.98, zl(DECK + 5.6)))
    h = bpy.context.object
    h.name = "hair"
    h.scale = (1.0, 1.0, 1 / c3.SQUASH)
    h.data.materials.append(mats["hair"])
    h.parent = car
    # the deck's opening: dark, between the seats and the windscreen
    box("cockpit", mats["seat"], -0.7, 0.7, 1.5, 2.6, sh.top(2.0) - 0.06, sh.top(2.0) + 0.005, car)


def bottom_sport(car, sh, tail, mats):
    """Two round lamps a side, a black diffuser, twin exhausts, the plate
    low in the middle."""
    for sx in (-1, 1):
        for x, c in ((0.66, "red"), (0.4, "red")):
            disc("light", mats[c], sx * x, zl(5.4), 0.12, car, 1, tail)
            disc("lens", mats["dark"], sx * x, zl(5.4), 0.05, car, 2, tail)
    panel("plate", mats["plate"], col(14), -col(14), zl(1.4), zl(3.4), car, 2)
    panel("diffuser", mats["plastic"], col(4), -col(4), zl(0), zl(1.1), car, 1, tail)
    for sx in (-1, 1):
        cs.exhaust(car, mats["chrome"], sx * 0.28, Z0 + 1.0 * LZ, 0.035)
        cs.exhaust(car, mats["chrome"], sx * 0.38, Z0 + 1.0 * LZ, 0.035)


def bottom_saloon(car, sh, tail, mats):
    """Wide clusters - red over amber, a white lamp inside - the plate
    between them, a dark bumper right across."""
    for sx in (-1, 1):
        face("light", mats["red"], [(sx * 0.28, zl(5.3)), (sx * 0.88, zl(5.3)), (sx * 0.88, zl(7.6)),
                                    (sx * 0.28, zl(7.6))], car, 1, tail)
        face("amber", mats["amber"], [(sx * 0.5, zl(4.3)), (sx * 0.86, zl(4.3)), (sx * 0.86, zl(5.3)),
                                      (sx * 0.5, zl(5.3))], car, 1, tail)
        face("reverse", mats["clear"], [(sx * 0.28, zl(4.3)), (sx * 0.5, zl(4.3)), (sx * 0.5, zl(5.3)),
                                        (sx * 0.28, zl(5.3))], car, 1, tail)
    panel("plate", mats["plate"], col(14), -col(14), zl(4.4), zl(6.6), car, 2)
    panel("bumper", mats["plastic"], -1, 1, zl(0), zl(2.2), car, 1, tail)
    cs.exhaust(car, mats["chrome"], 0.55, Z0 + 0.6 * LZ, 0.035)


def bottom_gt(car, sh, tail, mats):
    """A red light bar right across, the plate under it on a dark panel,
    four exhausts under a painted valance."""
    face("light", mats["red"], [(-0.9, zl(5.6)), (0.9, zl(5.6)), (0.9, zl(7.0)), (-0.9, zl(7.0))],
         car, 1, tail)
    face("glow", mats["dark"], [(-0.25, zl(5.6)), (0.25, zl(5.6)), (0.25, zl(7.0)), (-0.25, zl(7.0))],
         car, 2, tail)
    panel("panel", mats["plastic"], col(10), -col(10), zl(2.4), zl(5.0), car, 1, tail)
    panel("plate", mats["plate"], col(14), -col(14), zl(2.6), zl(4.8), car, 2)
    for sx in (-1, 1):
        for x in (0.5, 0.64):
            cs.exhaust(car, mats["chrome"], sx * x, Z0 + 0.8 * LZ, 0.032)


TOP = dict(closed=top_closed, open=top_open)
BOTTOM = dict(sport=bottom_sport, saloon=bottom_saloon, gt=bottom_gt)
TOP_PARTS = {"cabin", "seat", "hair", "cockpit"}


def materials():
    """The real materials (cars3d.photo_materials), by role; paint grey."""
    P = cs.photo_materials((0.25, 0.25, 0.25))
    P["seat"] = cs.principled("seat", (0.03, 0.03, 0.05), 0.6)
    P["hair"] = cs.principled("hair", (0.7, 0.45, 0.08), 0.5)        # blond
    P["tread"] = P["rubber"]
    P["hub"] = P["rim"]
    return P


def build(top, bottom):
    cs.clear()
    mats = materials()
    car = bpy.data.objects.new("Car", None)
    bpy.context.collection.objects.link(car)
    sh, tail = body(car, mats)
    TOP[top](car, sh, mats)
    BOTTOM[bottom](car, sh, tail, mats)
    # the paint's bevel, as cars3d.photoreal gives it
    for ob in bpy.data.objects:
        if ob.type == "MESH" and ob.data.materials and ob.data.materials[0] == mats["paint"]:
            bev = ob.modifiers.new("bevel", "BEVEL")
            bev.width = 0.03
            bev.segments = 2
            bev.limit_method = "ANGLE"
    return car, mats


def flat_pass(white):
    """Every surface emitting black, but those white(object, material) says:
    white - a mask."""
    em = {}
    for v in (0, 1):
        m = bpy.data.materials.new("mask%d" % v)
        m.use_nodes = True
        nt = m.node_tree
        nt.nodes.clear()
        e = nt.nodes.new("ShaderNodeEmission")
        e.inputs[0].default_value = (v, v, v, 1)
        o = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(e.outputs[0], o.inputs[0])
        em[v] = m
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        for i, m in enumerate(ob.data.materials):
            ob.data.materials[i] = em[1 if white(ob, m) else 0]


def render():
    paths = []
    os.makedirs(OUT_DIR, exist_ok=True)
    near = [(TOPS[0], BOTTOMS[0])] + [(t, BOTTOMS[0]) for t in TOPS[1:]] \
        + [(TOPS[0], b) for b in BOTTOMS[1:]]
    if COMBOS:
        near = [c for c in near if c in COMBOS]
    for si in SIZES:
        for top, bottom in near if si < NEAR else [(t, FAR_BOTTOM) for t in TOPS]:
            for pas in ("car", "paint", "top"):
                car, mats = build(top, bottom)
                root = bpy.data.objects.new("Squash", None)
                bpy.context.collection.objects.link(root)
                root.scale = (SCALES[si], SCALES[si], c3.SQUASH * SCALES[si])
                car.parent = root
                if YAW:
                    car.rotation_euler = (0, 0, math.radians(YAW))
                c3.camera()
                cs.photo_setup((math.radians(45), 0, 0))
                sc = bpy.context.scene
                sc.cycles.samples = SAMPLES
                if pas == "paint":
                    paint = mats["paint"]
                    flat_pass(lambda ob, m: m == paint)
                elif pas == "top":
                    flat_pass(lambda ob, m: ob.name.split(".")[0] in TOP_PARTS)
                if pas != "car":
                    sc.world = bpy.data.worlds.new("Black")
                    sc.world.use_nodes = True
                    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
                    for ob in list(bpy.data.objects):
                        if ob.type == "LIGHT":
                            bpy.data.objects.remove(ob)
                p = os.path.join(OUT_DIR, "s%d_%s_%s_%s%s.png" % (si, top, bottom, pas,
                                                                  "_yaw" if YAW else ""))
                sc.render.filepath = p
                bpy.ops.render.render(write_still=True)
                paths.append(p)
    return paths


if globals().get("RUN", False):
    result = dict(paths=render())
