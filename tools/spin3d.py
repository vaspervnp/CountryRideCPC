"""The four cars turning, for the select screen (tools/mkspin.py): each car's
model (cars3d.py, photoreal) every 15 degrees, turned about its middle, seen
square from its side by an orthographic camera EL degrees above, K mode 0
pixels a metre, heights times 0.8 (as the screen's side views), the sun with
the camera, in a frame of 80 x 40 cells, to OUT_DIR/<car>_<angle>.png.

Run it in a Blender of its own - cars3d.py's clear() removes every object
and material of the file it runs in:

    blender -b --factory-startup --python tools/spin3d.py -- OUT_DIR 14 5
    python3 tools/mkspin.py renders OUT_DIR
"""
import math
import os
import sys

import bpy
from mathutils import Euler, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
OUT, K, EL = argv[0], float(argv[1]), float(argv[2])
NAMES = argv[3:] or ["player", "ferrari", "lotus", "bmw"]
TOOLS = os.path.dirname(os.path.abspath(__file__))
FRAME = (80, 40)                 # cells (mode 0 pixels), each 16 x 8 render pixels
CELL = (16, 8)
SQUASH = 0.8                     # as the select screen's side views
STEP = 15

ns = dict(TOOLS=TOOLS, __file__=os.path.join(TOOLS, "cars3d.py"), PHOTO=True, SAMPLES=48)
exec(compile(open(os.path.join(TOOLS, "cars3d.py")).read(), "cars3d.py", "exec"), ns)

os.makedirs(OUT, exist_ok=True)
sc = bpy.context.scene
for name in NAMES:
    ns["clear"]()
    car = ns["MODELS"][name]()
    root = bpy.data.objects.new("Squash", None)
    sc.collection.objects.link(root)
    root.scale = (1, 1, SQUASH)
    car.parent = root
    ns["photoreal"](ns["PAINT"][name])
    ns["photo_setup"]((0, math.radians(35), math.radians(15)))   # from the camera's side, above
    cam_data = bpy.data.cameras.new("Spin")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("Spin", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    el = math.radians(EL)
    zc = 0.5 * SQUASH                                   # aimed at the car's middle height
    cam.location = (30 * math.cos(el), 0, zc + 30 * math.sin(el))
    cam.rotation_euler = (math.pi / 2 - el, 0, math.pi / 2)   # looking along -X, down EL
    sc.render.resolution_x = FRAME[0] * CELL[0]
    sc.render.resolution_y = FRAME[1] * CELL[1]
    sc.render.resolution_percentage = 100
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.ortho_scale = FRAME[0] / K
    p = Vector((0, car["length"] / 2, 0))               # turned about its middle
    for a in range(0, 360, STEP):
        e = Euler((0, 0, math.radians(a)), "XYZ")
        car.rotation_euler = e
        car.location = -(e.to_matrix() @ p)
        sc.render.filepath = os.path.join(OUT, "%s_%03d.png" % (name, a))
        bpy.ops.render.render(write_still=True)
    print("done", name, flush=True)
print("all done", flush=True)
