#!/usr/bin/env python3
"""The cars rolling over in a crash at speed (since 2026-11-12: the sprites
only, not in the game yet).

tools/cars3d.py (ROLL=True, in Blender) renders each car rolled about its
long axis - right, clockwise as seen from behind - 30, 90, 150, 210, 270 and
330 degrees (ROLL_FIRST, ROLL_STEP: none upright, that is the straight view)
into assets/cars/<car>_roll<k>.png, in a frame ROLL_LINES high round the
other views' middle. This brings them to the car's pens as tools/mkcars.py
brings its views (squeezed across, flat colours, lone cells dropped), each
row's run widened to whole pairs of bytes from any byte, in the colours at
its ends (bytes_run), the six of a car in one box. Rolling left is these
backwards (rolled left 30 degrees = rolled right 330).

Writes tools/rollart.py (ROLL_ART[car] = six frames of rows, ROLL_TOP[car] =
the box's first line against the other views' frame - mkcar.CELLS - and
ROLL_BOX[car] its width and height) and build/roll-sheet.png: each car
upright, then its six frames, on the asphalt and on the grass. Prints each
frame's size and what its code would take as the car's views are drawn
(mkbush.car_code).
"""

import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cpcgfx import PEN, m0_byte, pen_rgb  # noqa: E402
import mkcar  # noqa: E402
import mkcars  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FRAMES = 6
ROLL_LINES = 64                     # cars3d.py's (the frame's height, lines)
DEG = [30 + 60 * k for k in range(FRAMES)]


def bytes_run(r):
    """The row's run widened to whole pairs of bytes - from any byte, not
    from the car's pair grid (mkcar.pairs: up to 3 pixels either side) -
    so a pixel at most either side, and two more on one: its outer side
    from the middle, if that is not past the other; and what it is widened
    by (and any gap) the colour next to it, not the asphalt's grey (up in
    the air the grass can be under it)."""
    xs = [i for i, c in enumerate(r) if c != "."]
    if not xs:
        return r
    a, b = xs[0] // 2 * 2, (xs[-1] + 2) // 2 * 2
    if (b - a) // 2 % 2:
        if mkcar.MID - a < b - mkcar.MID:
            a -= 2
        else:
            b += 2
    row = list(r)
    for i in range(xs[0] - 1, a - 1, -1):
        row[i] = row[i + 1]
    for i in range(xs[-1] + 1, b):
        row[i] = row[i - 1]
    for i in range(a + 1, b):
        if row[i] == ".":
            row[i] = row[i - 1]
    return "".join(row)


def roll_frames(name):
    """A car's six frames in one box, its middle the other views' (as wide
    either side; a multiple of 4 pixels): (arts, the box's first line in the
    roll frame)."""
    renders = [mkcars.flat_pens(name, os.path.join(mkcars.SRC, "%s_roll%d.png" % (name, k)),
                                (mkcar.CELLS[0], ROLL_LINES)) for k in range(FRAMES)]
    rows = [[bytes_run(r) for r in v] for v in renders]
    used = [i for v in rows for i, r in enumerate(v) if r.strip(".")]
    top, bottom = min(used), max(used)
    xs = [i for v in rows for r in v for i, c in enumerate(r) if c != "."]
    half = max(mkcar.MID - min(xs), max(xs) + 1 - mkcar.MID)
    half += half % 2
    arts = [[r[mkcar.MID - half:mkcar.MID + half] for r in v[top:bottom + 1]] for v in rows]
    for a in arts:
        for r in a:
            assert "." not in r.strip("."), (name, r)
            if r.strip("."):
                assert (len(r) - len(r.lstrip("."))) % 2 == 0 and len(r.strip(".")) % 4 == 0
    return arts, top


def runs(rows):
    """mkbush.car_code's spans: (first byte, bytes) a line."""
    out = []
    for row in rows:
        if not row.strip("."):
            out.append((0, []))
            continue
        a = min(i for i, c in enumerate(row) if c != ".")
        b = max(i for i, c in enumerate(row) if c != ".") + 1
        pens = [PEN[mkcars.LETTERS[c]] for c in row[a:b]]
        out.append((a // 2, [m0_byte(pens[i], pens[i + 1]) for i in range(0, len(pens), 2)]))
    return out


def sheet(cars, path, s=4):
    """Per car: upright (its straight view), then the six frames - on the
    asphalt, and again on the grass (in the air its run's grey ends show)."""
    w = max(len(a[0][0]) for a, t in cars.values()) + 4
    h = max(len(a[0]) for a, t in cars.values()) + 4
    cols = 1 + FRAMES
    im = Image.new("RGB", (cols * w * 2 * s + 8, len(cars) * (2 * h * s + 16) + 8), (30, 30, 30))
    dr = ImageDraw.Draw(im)
    y0 = 4
    for name, (arts, top) in cars.items():
        up = mkcars.car_views(name)[0]["flat"]["straight"]
        dr.text((4, y0), "%s: %d x %d pixels a frame" % (name, len(arts[0][0]), len(arts[0])),
                fill=(255, 255, 255))
        y0 += 12
        for g, ground in enumerate(("GREY", "GRASS_A")):
            yy = y0 + g * h * s
            dr.rectangle([4, yy, cols * w * 2 * s + 3, yy + h * s - 1], fill=pen_rgb(PEN[ground]))
            for c, art in enumerate([up] + arts):
                x0 = 4 + c * w * 2 * s + (w - len(art[0])) * s
                oy = yy + (h - len(art)) * s // 2
                for y, row in enumerate(art):
                    for x, ch in enumerate(row):
                        if ch != ".":
                            dr.rectangle([x0 + 2 * x * s, oy + y * s,
                                          x0 + 2 * x * s + 2 * s - 1, oy + y * s + s - 1],
                                         fill=pen_rgb(PEN[mkcars.LETTERS[ch]]))
        y0 += 2 * h * s + 4
    im.save(path)


def main():
    import mkbush
    cars = {}
    lines = ['"""Generated by tools/mkroll.py from assets/cars/*_roll*.png - do not edit.',
             "",
             "The cars rolling over (right; left is these mirrored): ROLL_ART[car] =",
             "six frames, %s degrees, rows of mode 0 pixels, letters as" % "/".join(map(str, DEG)),
             "tools/mkcars.py LETTERS, '.' none; ROLL_TOP[car] = the box's first line",
             "against the other views' frame (tools/mkcar.py CELLS: its middle the same).",
             '"""', "", "ROLL_ART = {"]
    tops = {}
    for name in mkcars.CARS:
        arts, top = roll_frames(name)
        cars[name] = (arts, top)
        tops[name] = top - (ROLL_LINES - mkcar.CELLS[1]) // 2
        sizes = []
        for k, a in enumerate(arts):
            code, us = mkbush.car_code(runs(a), 200, 30)
            sizes.append((sum(mkbush.SIZE[mkbush.kind(t)] for t, st in code), us))
        print("%s: %d x %d pixels; code %s bytes, %s us; all six %d bytes" % (
            name, len(arts[0][0]), len(arts[0]), "/".join(str(b) for b, u in sizes),
            "/".join("%d" % u for b, u in sizes), sum(b for b, u in sizes)))
        lines.append('    "%s": [' % name)
        for k, a in enumerate(arts):
            lines.append("        [   # %d degrees" % DEG[k])
            lines += ['            "%s",' % r for r in a]
            lines.append("        ],")
        lines.append("    ],")
    lines += ["}", "", "ROLL_TOP = %r" % tops,
              "ROLL_BOX = %r" % {n: (len(a[0][0]), len(a[0])) for n, (a, t) in cars.items()}, ""]
    open(os.path.join(ROOT, "tools", "rollart.py"), "w").write("\n".join(lines))
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    sheet(cars, os.path.join(ROOT, "build", "roll-sheet.png"))


if __name__ == "__main__":
    main()
