"""What the cars' 3D models share (tools/cars3d.py builds them and renders
them all: tools/mkcars.py): the game's pens and camera, the frame's grid,
curved shapes and the parts made of them.

Run inside Blender 4.2 or later through cars3d.py. camera() and setup() are
the game's camera and a flat light for it, seen from behind.

A model points along +Y, its rear face at y = 0, its body curved: lofted
through rounded sections from the tail to the nose (Shape, loft), the wheel
arches cut into it, fenders over the wheels if it has them, a cabin, sails.
Its materials are the game's pens (the body shaded in steps by a light from
above and behind, the rest flat); cars3d.py gives them real ones.

The camera is the game's: level - the horizon is mid-screen - so verticals
stay vertical, a lens shift bringing the car into the frame - and a little
above the car. A cell of the frame is a mode 0 pixel, twice as wide as a
line is high; the frame's middle column is the screen's. A car turns about
its rear axle: its nose goes into the turn, its rear stays about where it
is.
"""

import bisect
import math

import bpy
import bmesh

# The game's pens (tools/cpcgfx.py PENS), sRGB
PAL = dict(BLACK=(0, 0, 0), NAVY=(0, 0, 128), WHITE=(255, 255, 255),
           GREY=(128, 128, 128), RED=(255, 0, 0), ORANGE=(255, 128, 0),
           YELLOW=(255, 255, 0), SKY=(0, 128, 255), CAR_DARK=(128, 0, 0))

YAW = globals().get("YAW", 6.0)           # degrees, turning left (10 till
                                           # 2026-11-10: too much, the user said)
ELEV = globals().get("ELEV", 3.0)         # degrees: the camera above the rear's foot
DIST = globals().get("DIST", 12.0)         # metres behind the rear face
SQUASH = 0.46                              # heights x this: the game's car is low
CELLS = (64, 40)                           # the frame, in cells
CELL_PX = (16, 8)                          # render pixels a cell (square pixels)
CAR_CELLS = 36                             # cells over the car's 2 m at yaw 0
REAR_AXLE = 0.95                           # metres from the rear face: a model's
FRONT_AXLE = 3.65                          # own (cars3d.axles)


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


def panel(name, mat, x0, x1, z0, z1, parent, depth=0, clip=None):
    """A flat panel on the rear face, facing back; `depth` more in front of
    what is under it; cut to the outline `clip` ((x, z) going round,
    convex: the rounded rear face's) if given."""
    y = -0.004 - 0.001 * depth
    poly = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
    if clip:
        poly = clipped(poly, clip)
        if len(poly) < 3:
            return None
    me = bpy.data.meshes.new(name)
    me.from_pydata([(x, y, z) for x, z in poly], [], [tuple(range(len(poly)))])
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.parent = parent
    return ob


def wheel(name, tyre, tread, x, y, r, w, parent, hub=None, hub_r=0.55):
    """A tyre, its tread one colour and its sides another - with a hub on
    its outer side (away from x = 0) if `hub` is a material, hub_r of its
    radius."""
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
        bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=hub_r * r, depth=0.01,
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


# ---------------------------------------------------------------------------
# Curved shapes. A loft runs along the car (y): at each station a section,
# the upper half of a superellipse |x/a|^p + |z/b|^p = 1 (p 2: an ellipse;
# the bigger, the squarer) standing on a base line - its half width, base,
# top and p smooth curves along y through a few keys. Bodies, cabins,
# wheel arches, sails.
# ---------------------------------------------------------------------------
SECTION_N = 40          # a section's segments, foot to foot
NOTCH_MIN = 0.01        # a body's wheel arch notch where there is no arch
SLAB_MIN = 0.07         # the body over an arch at least this thick
REAR_R, FRONT_R = 0.34, 0.31                # the tyres' radii
ARCH_GAP = 0.05                             # an arch's clearance over its tyre


def curve(keys):
    """A smooth function through keys [(t, v), ...], t rising: piecewise
    cubic, monotone between the keys (Fritsch-Carlson: no overshoot), level
    past the ends. A number: that, everywhere; a function: itself."""
    if callable(keys):
        return keys
    if not isinstance(keys, (list, tuple)):
        return lambda t: keys
    ts, vs = [float(k[0]) for k in keys], [float(k[1]) for k in keys]
    n = len(ts)
    if n == 1:
        return lambda t: vs[0]
    h = [ts[i + 1] - ts[i] for i in range(n - 1)]
    d = [(vs[i + 1] - vs[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    for i in range(1, n - 1):
        if d[i - 1] * d[i] > 0:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])

    def end(h0, h1, d0, d1):
        e = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
        if e * d0 <= 0:
            return 0.0
        if d0 * d1 <= 0 and abs(e) > 3 * abs(d0):
            return 3 * d0
        return e
    if n > 2:
        m[0], m[-1] = end(h[0], h[1], d[0], d[1]), end(h[-1], h[-2], d[-1], d[-2])
    else:
        m[0] = m[1] = d[0]

    def f(t):
        if t <= ts[0]:
            return vs[0]
        if t >= ts[-1]:
            return vs[-1]
        i = min(bisect.bisect_right(ts, t) - 1, n - 2)
        u = (t - ts[i]) / h[i]
        return ((1 + 2 * u) * (1 - u) ** 2 * vs[i] + u * (1 - u) ** 2 * h[i] * m[i]
                + u * u * (3 - 2 * u) * vs[i + 1] + u * u * (u - 1) * h[i] * m[i + 1])
    return f


def dome(a, b, p, cut=0.0, n=SECTION_N):
    """A superellipse's upper half, half width a and height b over z = 0,
    without what is below z = cut: n + 1 points from its right foot over
    the top to its left foot, closer together where it bends."""
    fine = []
    for i in range(361):
        th = math.pi * i / 360
        c, s = math.cos(th), math.sin(th)
        fine.append((a * math.copysign(abs(c) ** (2.0 / p), c), b * abs(s) ** (2.0 / p)))
    if cut > 0:
        k0 = next(i for i, (x, z) in enumerate(fine) if z >= cut)
        k1 = max(i for i, (x, z) in enumerate(fine) if z >= cut)

        def cross(i, j):
            (x0, z0), (x1, z1) = fine[i], fine[j]
            return (x0 + (cut - z0) / (z1 - z0) * (x1 - x0), cut)
        fine = [cross(k0 - 1, k0)] + fine[k0:k1 + 1] + [cross(k1 + 1, k1)]
    # spaced by length plus turning: the corners get their share of points
    d, prev = [0.0], None
    for (x0, z0), (x1, z1) in zip(fine, fine[1:]):
        ang = math.atan2(z1 - z0, x1 - x0)
        turn = 0.0 if prev is None else abs(math.remainder(ang - prev, 2 * math.pi))
        prev = ang
        d.append(d[-1] + math.hypot(x1 - x0, z1 - z0) + 0.06 * turn)
    out, k = [], 0
    for i in range(n + 1):
        t = d[-1] * i / n
        while k < len(d) - 2 and d[k + 1] < t:
            k += 1
        seg = d[k + 1] - d[k]
        f = min(1.0, (t - d[k]) / seg) if seg > 0 else 0.0
        (x0, z0), (x1, z1) = fine[k], fine[k + 1]
        out.append((x0 + f * (x1 - x0), z0 + f * (z1 - z0)))
    return out


def clipped(poly, clip):
    """poly cut to the convex polygon clip (both (x, z), going round
    anticlockwise: Sutherland-Hodgman)."""
    def inside(p, a, b):
        return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= 0

    def meet(p, q, a, b):
        dx, dz = q[0] - p[0], q[1] - p[1]
        ex, ez = b[0] - a[0], b[1] - a[1]
        t = (ex * (a[1] - p[1]) - ez * (a[0] - p[0])) / (ex * dz - ez * dx)
        return (p[0] + t * dx, p[1] + t * dz)
    out = list(poly)
    for i in range(len(clip)):
        a, b = clip[i], clip[(i + 1) % len(clip)]
        src, out = out, []
        for j in range(len(src)):
            p, q = src[j - 1], src[j]
            if inside(q, a, b):
                if not inside(p, a, b):
                    out.append(meet(p, q, a, b))
                out.append(q)
            elif inside(p, a, b):
                out.append(meet(p, q, a, b))
        if not out:
            break
    return out


class Shape:
    """A loft's shape: at y a dome of half width a(y) centred on x = xc(y),
    standing on base(y), its top at top(y), exponent p(y) - each a number
    or keys for curve()."""

    def __init__(self, a, base, top, p=4.0, xc=0.0):
        self.a, self.base, self.top, self.p, self.xc = (
            curve(v) for v in (a, base, top, p, xc))

    def half(self, y, z):
        """Its half width at y, at height z."""
        b = self.top(y) - self.base(y)
        u = min(1.0, max(0.0, (z - self.base(y)) / b))
        p = self.p(y)
        return self.a(y) * (1 - u ** p) ** (1 / p)

    def outline(self, y, inset=0.0):
        """Its section at y, `inset` in from the sides and the top, going
        round anticlockwise seen from behind (convex): what a panel on that
        end is cut to."""
        z0 = self.base(y)
        pts = dome(self.a(y) - inset, self.top(y) - z0 - inset, self.p(y))
        return [(self.xc(y) + x, z0 + z) for x, z in pts]


def stations(y0, y1, step=0.04, edges=()):
    """y0..y1 every `step` or so, with the points either side of each of
    `edges` (where a cut starts or ends)."""
    n = max(1, round((y1 - y0) / step))
    ys = {round(y0 + (y1 - y0) * i / n, 5) for i in range(n + 1)}
    for e in edges:
        for d in (-0.002, 0.002):
            if y0 < e + d < y1:
                ys.add(round(e + d, 5))
    return sorted(ys)


def rings_mesh(name, mats, rings, kinds, parent, slot=None, well=0):
    """A solid through rings of (x, y, z) points, each going round the same
    way, closed at both ends. kinds: per segment of a ring, "d" (the dome:
    smooth, in mats[slot(x, y, z, u)] - u the segment's place along the dome,
    0 to 1 - or mats[0]) or "w" (flat, in mats[well])."""
    dome_js = [j for j, k in enumerate(kinds) if k == "d"]
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    vs = [[bm.verts.new(p) for p in r] for r in rings]
    m = len(rings[0])
    for i in range(len(rings) - 1):
        for j in range(m):
            jj = (j + 1) % m
            f = bm.faces.new([vs[i][j], vs[i][jj], vs[i + 1][jj], vs[i + 1][j]])
            if kinds[j] == "d":
                f.smooth = True
                if slot:
                    c = [sum(v.co[k] for v in f.verts) / 4 for k in range(3)]
                    u = (j - dome_js[0] + 0.5) / len(dome_js)
                    f.material_index = slot(*c, u)
            else:
                f.material_index = well
    bm.faces.new(list(reversed(vs[0])))
    bm.faces.new(vs[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    for mat in mats:
        me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.parent = parent
    return ob


def loft(name, mats, shape, ys, parent, cut=None, notch=None, slot=None, well=0, side=1):
    """`shape` lofted through the stations ys: a solid in mats (see
    rings_mesh; here slot(y, x, z, u), x from the shape's middle - u keeps
    to the same points of every section: material edges along the loft
    come out straight). cut(y): the dome cut
    off below that height - all of it, or with notch = x_in only outside
    |x| > x_in: a body's wheel arch, the middle staying down to the base, the
    arch's walls in mats[well]. side -1: mirrored."""
    rings, kinds = [], None
    for y in ys:
        z0, a, p, xc = shape.base(y), shape.a(y), shape.p(y), shape.xc(y)
        b = shape.top(y) - z0
        c = 0.0 if cut is None else cut(y) - z0
        if notch is None:
            ring = dome(a, b, p, min(max(c, 0.0), b - SLAB_MIN))
            kinds = ["d"] * (len(ring) - 1) + ["w"]
        else:
            # the arch's roof no higher than leaves the slab over it
            # SLAB_MIN thick and the dome's foot outside its walls
            xn = min(notch, a - 0.08)                # (a narrow nose)
            c = min(max(c, NOTCH_MIN), b - SLAB_MIN,
                    0.98 * b * (1 - ((xn + 0.03) / a) ** p) ** (1 / p))
            ring = [(xn, 0.0), (xn, c)] + dome(a, b, p, c) + [(-xn, c), (-xn, 0.0)]
            kinds = ["w", "w"] + ["d"] * (len(ring) - 5) + ["w", "w", "w"]
        rings.append([(side * (xc + x), y, z0 + z) for x, z in ring])
    sl = None
    if slot:
        def sl(x, y, z, u):
            return slot(y, side * x - shape.xc(y), z, u)
    return rings_mesh(name, mats, rings, kinds, parent, sl, well)


def strip(name, mat, shape, ys, z0, z1, parent, out=0.006, side=1):
    """A strip on a body's flank (shape's), from height z0 to z1 at each of
    ys, standing `out` proud of it - a sill, a strake, an intake."""
    rings = []
    for y in ys:
        x0, x1 = shape.half(y, z0), shape.half(y, z1)
        rings.append([(side * (x0 + out), y, z0), (side * (x1 + out), y, z1),
                      (side * (x1 - 0.03), y, z1), (side * (x0 - 0.03), y, z0)])
    return rings_mesh(name, [mat], rings, ["w"] * 4, parent)


def arches(axles):
    """cut(y) for wheel arches over axles [(y, tyre radius), ...]: the arch's
    height over the ground (a circle ARCH_GAP clear of the tyre), -1 where
    there is none; and the arches' ends, for stations()."""
    def cut(y):
        h = -1.0
        for ay, r in axles:
            R = r + ARCH_GAP
            if abs(y - ay) < R:
                h = max(h, r + math.sqrt(R * R - (y - ay) ** 2))
        return h
    return cut, [ay + s * (r + ARCH_GAP) for ay, r in axles for s in (-1, 1)]


def fenders(name, mat, under, axles, parent, p=3.0):
    """A rounded fender over each wheel, both sides, swelling out of the
    body over the arch and back into it: axles [(y, tyre radius, the tyre's
    middle x, its half width, (top behind, top over the wheel, top in
    front), (reach behind, reach in front)), ...] - its ends, that far past
    the arch, with their tops on the body's line. Cut by the arch, its
    underside in `under`."""
    cut, _ = arches([a[:2] for a in axles])
    for ay, r, x, half, (lo0, hi, lo1), (re0, re1) in axles:
        R = r + ARCH_GAP
        y0, y1 = ay - R - re0, ay + R + re1
        sh = Shape([(y0, 0.04), (ay - R, half), (ay + R, half), (y1, 0.04)], Z0,
                   [(y0, lo0), (ay, hi), (y1, lo1)], p,
                   [(y0, x - 0.1), (ay - R, x), (ay + R, x), (y1, x - 0.1)])
        ys = stations(y0, y1, 0.03, [ay - R, ay + R])
        for sx in (-1, 1):
            loft(name, [mat, under], sh, ys, parent, cut=cut, well=1, side=sx)


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
