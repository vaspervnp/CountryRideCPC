"""The player's car as a 3D model, for its sprites' views (tools/mkcar.py).

Run inside Blender 4.2 or later (Scripting tab, or exec() through an MCP),
with OUT_DIR set to where the renders go: it empties the scene, builds the
car in the game's colours and renders it seen from behind, straight and
turning left (yawed, its nose to the left) by YAW degrees, to
OUT_DIR/car_0.png and OUT_DIR/car_left.png. Turning right is the left view
mirrored.

The model is a low, wide sports car with a wing and fat tyres, pointing
along +Y, its rear face at y = 0. The body is shaded in three steps (dark
red, red, orange) by a light from above and behind; everything else is a
flat colour, so every rendered pixel is one of the game's pens (but at the
edges).

The camera is the game's: level - the horizon is mid-screen - so verticals
stay vertical, a lens shift bringing the car into the frame - and a little
above the car. A cell of the
frame is a mode 0 pixel, twice as wide as a line is high; the frame's
middle column is the screen's. The car turns about its rear axle: its nose
goes into the turn, its rear stays about where it is. The tyres stand out
past the body, with hubs that show when it turns.
"""

import math
import os

import bpy
import bmesh

# The game's pens (tools/cpcgfx.py PENS), sRGB
PAL = dict(BLACK=(0, 0, 0), NAVY=(0, 0, 128), WHITE=(255, 255, 255),
           GREY=(128, 128, 128), RED=(255, 0, 0), ORANGE=(255, 128, 0),
           YELLOW=(255, 255, 0), SKY=(0, 128, 255), CAR_DARK=(128, 0, 0))

OUT_DIR = globals().get("OUT_DIR", bpy.app.tempdir)
YAW = globals().get("YAW", 10.0)          # degrees, turning left
ELEV = globals().get("ELEV", 3.0)         # degrees: the camera above the rear's foot
DIST = globals().get("DIST", 12.0)         # metres behind the rear face
PIVOT = globals().get("PIVOT", 0.95)       # the yaw turns about (0, PIVOT): the
                                           # rear axle
WING = globals().get("WING", 13)           # the wing's bottom line, over the window
TYRE_OUT = globals().get("TYRE_OUT", 1.04)  # the rear tyres' outer faces (the body
TYRE_W = globals().get("TYRE_W", 0.34)      # is 2 m wide) and width, metres
HUBS = globals().get("HUBS", True)          # grey hubs on the tyres' outer faces
STRAKES = globals().get("STRAKES", True)    # black strakes along the flanks
SQUASH = 0.46                              # heights x this: the game's car is low
CELLS = (64, 40)                           # the frame, in cells
CELL_PX = (16, 8)                          # render pixels a cell (square pixels)
CAR_CELLS = 36                             # cells over the car's 2 m at yaw 0
REAR_AXLE = 0.95
FRONT_AXLE = 3.65


def lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgba(pen):
    return [lin(v) for v in PAL[pen]] + [1]


def material(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes.clear()
    return m, m.node_tree


def emit(nt, colour_socket):
    em = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(colour_socket, em.inputs[0])
    nt.links.new(em.outputs[0], out.inputs[0])


def flat(pen):
    m, nt = material(pen)
    rgb = nt.nodes.new("ShaderNodeRGB")
    rgb.outputs[0].default_value = rgba(pen)
    emit(nt, rgb.outputs[0])
    return m


def toon(name, steps):
    """The diffuse light in steps: [(from, pen), ...]."""
    m, nt = material(name)
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    dif.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    bw = nt.nodes.new("ShaderNodeRGBToBW")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    els = ramp.color_ramp.elements
    while len(els) < len(steps):
        els.new(0.5)
    for el, (pos, pen) in zip(els, steps):
        el.position = pos
        el.color = rgba(pen)
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs[0], bw.inputs[0])
    nt.links.new(bw.outputs[0], ramp.inputs[0])
    emit(nt, ramp.outputs[0])
    return m


def glass():
    """Navy with slanting stripes of sky: the rear window's reflections."""
    m, nt = material("GLASS")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    xyz = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], xyz.inputs[0])
    slant = nt.nodes.new("ShaderNodeMath")
    slant.operation = "MULTIPLY_ADD"        # z * -0.92 + x: a column a line
    slant.inputs[1].default_value = -0.92
    nt.links.new(xyz.outputs["Z"], slant.inputs[0])
    nt.links.new(xyz.outputs["X"], slant.inputs[2])
    freq = nt.nodes.new("ShaderNodeMath")
    freq.operation = "MULTIPLY"             # a stripe every 8 columns
    freq.inputs[1].default_value = 2.25
    nt.links.new(slant.outputs[0], freq.inputs[0])
    frac = nt.nodes.new("ShaderNodeMath")
    frac.operation = "FRACT"
    nt.links.new(freq.outputs[0], frac.inputs[0])
    lt = nt.nodes.new("ShaderNodeMath")
    lt.operation = "LESS_THAN"
    lt.inputs[1].default_value = 0.28
    nt.links.new(frac.outputs[0], lt.inputs[0])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs["A"].default_value = rgba("NAVY")
    mix.inputs["B"].default_value = rgba("SKY")
    nt.links.new(lt.outputs[0], mix.inputs["Factor"])
    emit(nt, mix.outputs["Result"])
    return m


def solid(name, mat, bottom, top, parent):
    """A solid from a ring of bottom corners to a ring of top ones, (x, y,
    z) each, going round the same way."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    n = len(bottom)
    vb = [bm.verts.new(p) for p in bottom]
    vt = [bm.verts.new(p) for p in top]
    bm.faces.new(list(reversed(vb)))
    bm.faces.new(vt)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([vb[i], vb[j], vt[j], vt[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.parent = parent
    return ob


def prism(name, mat, plan, z0, z1, parent, plan_top=None):
    """A solid standing on `plan` ((x, y) going round) from z0 to z1;
    its top `plan_top` if it narrows."""
    return solid(name, mat, [(x, y, z0) for x, y in plan],
                 [(x, y, z1) for x, y in (plan_top or plan)], parent)


def box(name, mat, x0, x1, y0, y1, z0, z1, parent):
    return prism(name, mat, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], z0, z1, parent)


def panel(name, mat, x0, x1, z0, z1, parent, depth=0):
    """A flat panel on the rear face, facing back; `depth` more in front of
    what is under it."""
    y = -0.004 - 0.001 * depth
    me = bpy.data.meshes.new(name)
    me.from_pydata([(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)], [], [(0, 1, 2, 3)])
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.parent = parent
    return ob


def wheel(name, tyre, tread, x, y, r, w, parent, hub=None):
    """A tyre, its tread one colour and its sides another - with a hub on
    its outer side (away from x = 0) if `hub` is a material."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=r, depth=w,
                                        location=(x, y, r), rotation=(0, math.pi / 2, 0))
    ob = bpy.context.object
    ob.name = name
    ob.data.materials.append(tyre)
    ob.data.materials.append(tread)
    for p in ob.data.polygons:          # the round face: the tread
        p.material_index = 1 if len(p.vertices) == 4 else 0
    ob.parent = parent
    if hub is not None:
        side = 1 if x > 0 else -1
        bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.55 * r, depth=0.01,
                                            location=(x + side * (w / 2 + 0.006), y, r),
                                            rotation=(0, math.pi / 2, 0))
        h = bpy.context.object
        h.name = name + "_hub"
        h.data.materials.append(hub)
        h.parent = parent
    return ob


# The rear face is laid out on the frame's grid, as a sprite would be: CX
# metres a column (36 across the car), LZ metres a line (before SQUASH),
# the body's foot Z0 four lines up.
CX = 2.0 / CAR_CELLS
LZ = CELL_PX[1] / (CAR_CELLS * CELL_PX[0] / 2.0) / SQUASH
Z0 = 4 * LZ


def col(c):
    """Where column c (0..36, from the car's left) starts, in metres."""
    return -1.0 + c * CX


def zl(n):
    """Where line n of the rear face (0: the body's foot) starts."""
    return Z0 + n * LZ


def build():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)

    body = toon("BODY", [(0.0, "CAR_DARK"), (0.35, "RED"), (0.97, "ORANGE")])
    k, d, w = flat("BLACK"), flat("CAR_DARK"), flat("WHITE")
    r, o, y = flat("RED"), flat("ORANGE"), flat("YELLOW")
    n, gl = flat("NAVY"), glass()

    car = bpy.data.objects.new("Car", None)
    bpy.context.collection.objects.link(car)

    def mirrored(name, mat, c0, c1, n0, n1, depth=0):
        """A panel over columns c0..c1 and its mirror image."""
        panel(name, mat, col(c0), col(c1), zl(n0), zl(n1), car, depth)
        panel(name, mat, -col(c1), -col(c0), zl(n0), zl(n1), car, depth)

    # the body, nine lines high behind (a tenth, the deck, over the engine):
    # its rear corners cut off (they face
    # away from the light: dark red down the sides), the nose lower
    xr = -col(2)
    rear = [(-xr, 0.0), (xr, 0.0), (1.0, 0.18), (1.0, 3.1), (-1.0, 3.1), (-1.0, 0.18)]
    prism("body", body, rear, Z0, zl(9), car)
    solid("nose", body,
          [(-1.0, 3.1, Z0), (1.0, 3.1, Z0), (0.95, 4.45, Z0), (-0.95, 4.45, Z0)],
          [(-1.0, 3.1, zl(9)), (1.0, 3.1, zl(9)), (0.9, 4.45, zl(5)), (-0.9, 4.45, zl(5))], car)
    # over the engine, the deck; the cabin, glass all round under a
    # body-coloured roof; the buttresses either side of the rear window
    prism("deck", body, [(-xr, 0.0), (xr, 0.0), (1.0, 0.18), (1.0, 1.7), (-1.0, 1.7), (-1.0, 0.18)],
          zl(9), zl(10), car)
    solid("cabin", gl,
          [(-0.5, 1.7, zl(10)), (0.5, 1.7, zl(10)), (0.62, 3.1, zl(9)), (-0.62, 3.1, zl(9))],
          [(-0.4, 2.2, zl(13)), (0.4, 2.2, zl(13)), (0.45, 2.75, zl(13)), (-0.45, 2.75, zl(13))], car)
    box("roof", body, -0.46, 0.46, 2.15, 2.8, zl(12.9), zl(13.4), car)
    for sx in (-1, 1):
        pts = [(0.97, 0.25, zl(10)), (0.5, 0.25, zl(10)), (0.5, 2.25, zl(10)), (0.97, 2.25, zl(10))]
        top = [(0.95, 0.25, zl(10.4)), (0.6, 0.25, zl(10.4)), (0.4, 2.25, zl(13)), (0.62, 2.25, zl(13))]
        solid("buttress", body, [(sx * x, yy, z) for x, yy, z in pts],
              [(sx * x, yy, z) for x, yy, z in top], car)
    # the wing on two pylons, four lines over the roof: black, red, an
    # orange stripe, black
    box("wing", body, col(4), -col(4), 0.0, 0.42, zl(WING), zl(WING + 4), car)
    panel("wing_k", k, col(4), -col(4), zl(WING), zl(WING + 4), car)
    panel("wing_r", r, col(5), -col(5), zl(WING + 1), zl(WING + 2), car, 1)
    panel("wing_o", o, col(5), -col(5), zl(WING + 2), zl(WING + 3), car, 1)
    for sx in (-1, 1):
        box("pylon", k, sx * col(9) - 0.03, sx * col(9) + 0.03, 0.1, 0.3, zl(10), zl(WING), car)
    # the rear face, from the top: the deck's lit edge, a line of red, black
    # slats over two rows of lights (red, red, amber, a yellow lamp, amber;
    # the middle dark), the plate in a black frame on a red line and a dark
    # one
    panel("rim", o, col(2), -col(2), zl(8), zl(9), car)
    panel("grille", k, col(2), -col(2), zl(2), zl(7), car)
    for row in (3, 5):
        panel("middle", d, col(9), -col(9), zl(row), zl(row + 1), car, 1)
        for name, mat, c0, c1 in (("light", r, 3, 5), ("amber", o, 5, 6), ("lamp", y, 6, 7),
                                  ("amber", o, 7, 8)):
            mirrored(name, mat, c0, c1, row, row + 1, 1)
    panel("band", d, col(2), -col(2), zl(0), zl(1), car)
    panel("frame", k, col(13), -col(13), zl(0), zl(2), car, 1)
    panel("plate", w, col(14), -col(14), zl(0), zl(2), car, 2)
    # under the body: the diffuser between the tyres, two exhausts
    panel("diffuser", k, col(6), -col(6), LZ, Z0, car)
    box("under", k, col(6), -col(6), 0.0, 4.3, LZ, Z0, car)
    for sx in (-1, 1):
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=CX, depth=0.12,
                                            location=(sx * (col(9) + CX), -0.05, 2 * LZ),
                                            rotation=(math.pi / 2, 0, 0))
        ex = bpy.context.object
        ex.name = "exhaust"
        ex.data.materials.append(w)
        ex.parent = car
    # fat tyres behind, out to the body's edges or past them; narrower ones
    # in front; hubs that show when the car is seen turning
    hub = flat("GREY") if HUBS else None
    for sx in (-1, 1):
        wheel("tyre_r", k, n, sx * (TYRE_OUT - TYRE_W / 2), REAR_AXLE, 0.34, TYRE_W, car, hub)
        wheel("tyre_f", k, n, sx * (TYRE_OUT - 0.04 - TYRE_W * 0.4), FRONT_AXLE, 0.31,
              TYRE_W * 0.8, car, hub)
    # along each flank: a black sill, and strakes in front of the rear wheel
    for sx in (-1, 1):
        box("sill", k, sx * 1.0 - 0.005, sx * 1.0 + 0.005, 0.18, 4.3, Z0, zl(1), car)
        if STRAKES:
            for row in (3, 5, 7):
                box("strake", k, sx * 1.0 - 0.005, sx * 1.0 + 0.005, 1.4, 3.0,
                    zl(row), zl(row + 1), car)

    car.scale = (1, 1, SQUASH)
    return car


def camera():
    sc = bpy.context.scene
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    hc = DIST * math.tan(math.radians(ELEV))
    cam.location = (0, -DIST, hc)
    cam.rotation_euler = (math.pi / 2, 0, 0)       # level, looking along +Y
    resx, resy = CELLS[0] * CELL_PX[0], CELLS[1] * CELL_PX[1]
    sc.render.resolution_x, sc.render.resolution_y = resx, resy
    sc.render.resolution_percentage = 100
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.sensor_width = 36.0
    px_per_m = CAR_CELLS * CELL_PX[0] / 2.0
    cam_data.lens = px_per_m * DIST * cam_data.sensor_width / resx
    # the car's middle in the middle of the frame - moved so that the rear
    # face's foot is on the edge of a line
    shift = px_per_m * (0.3 * SQUASH - hc)
    foot = resy / 2 + px_per_m * (hc - Z0 * SQUASH) + shift
    shift += round(foot / CELL_PX[1]) * CELL_PX[1] - foot
    cam_data.shift_y = shift / max(resx, resy)
    return cam


def setup():
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.film_transparent = True
    sc.render.filter_size = 0.0
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0
    sc.view_settings.gamma = 1
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    world = sc.world or bpy.data.worlds.new("World")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Strength"].default_value = 0.0
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = math.pi           # a lit face square on: 1
    sun_data.use_shadow = False
    sun = bpy.data.objects.new("Sun", sun_data)
    sc.collection.objects.link(sun)
    # from above and behind: the deck lit most, the rear face less, the
    # flanks not at all
    sun.rotation_euler = (math.radians(28), 0, 0)


def render():
    car = build()
    camera()
    setup()
    os.makedirs(OUT_DIR, exist_ok=True)
    paths = []
    for name, yaw in (("car_0", 0.0), ("car_left", YAW)):
        a = math.radians(yaw)
        car.rotation_euler = (0, 0, a)
        car.location = (PIVOT * math.sin(a), PIVOT * (1 - math.cos(a)), 0)
        p = os.path.join(OUT_DIR, name + ".png")
        bpy.context.scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        paths.append(p)
    return paths


if __name__ == "__main__" or globals().get("RUN", False):
    result = dict(paths=render())
