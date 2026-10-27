#!/usr/bin/env python3
"""The cars' sprites, from photorealistic renders of their 3D models.

tools/cars3d.py (run in Blender) renders each car - the player's first -
seen from behind, on the level, uphill and downhill, each straight and
turning left, into assets/cars/<car>_<flat|up|down>_<0|left>.png. This
brings each to the pens (tools/dither.py: each cell's mean colour over the
asphalt's grey, graded, a checkerboard where two neighbouring pens mix
nearer), drops lone cells, blackens each row's ends, widens each row's run
to whole pairs over the asphalt's grey (tools/mkcar.py), in one box for
all of a car's views, and adds the views turning right: the left ones
mirrored. Nine sprites a car, in tools/carsart.py. Also draws them all into
build/cars-sheet.png.
"""

import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cpcgfx import PEN, pen_rgb  # noqa: E402
import dither  # noqa: E402
import mkcar  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "assets", "cars")
CARS = ["player", "ferrari", "lotus", "bmw"]
# the pens a car may take: all but the greens and the mauve
LETTERS = dict(mkcar.LETTERS, P="PASTEL", B="BLUE", H="HAZE")
PALETTE = {c: pen_rgb(PEN[p]) for c, p in LETTERS.items()}
# the pairs that may mix: neighbours on the reds', the blues' and the greys'
# ramps
PAIRS = ["KD", "DR", "RO", "OY", "YW", "RW", "KN", "NB", "BS", "SH", "HW", "SP",
         "PW", "KG", "GW", "GP", "NG"]
PITCHES = ["flat", "up", "down"]
TURNS = ["left", "straight", "right"]


def outline(rows):
    """A row's ends black - the car's edge against the asphalt."""
    out = []
    for r in rows:
        r = list(r)
        xs = [i for i, c in enumerate(r) if c != "."]
        for i in xs[:1] + xs[-1:]:
            r[i] = "K"
        out.append("".join(r))
    return out


def car_views(name):
    """{pitch: {turn: art}} for one car, all in one box."""
    renders = []
    for p in PITCHES:
        for v in ("0", "left"):
            path = os.path.join(SRC, "%s_%s_%s.png" % (name, p, v))
            cells = dither.grade(dither.cell_colours(path, mkcar.CELLS))
            renders.append(outline(mkcar.lone(dither.pattern(cells, PALETTE, PAIRS,
                                                             mixed_only="G"))))
    drawn, arts, (top, bottom) = min(mkcar.fit(renders, ph) for ph in (0, 2))
    out = {}
    for i, p in enumerate(PITCHES):
        straight, left = arts[2 * i], arts[2 * i + 1]
        out[p] = dict(left=left, straight=straight, right=[r[::-1] for r in left])
    for p in PITCHES:
        for t in TURNS:
            for r in out[p][t]:
                assert "." not in r.strip("."), (name, p, t, r)
    return out, drawn, top


def sheet(cars, path, sx=3, sy=3):
    """Every view on the asphalt, mode 0 pixels twice as wide as lines: a
    column of the cars' blocks (rows: flat, up, down; columns: left,
    straight, right)."""
    blocks = [(n, cars[n]) for n in CARS if n in cars]
    cw = max(len(a[0]) for _, b in blocks for p in b.values() for a in p.values())
    ch = max(len(a) for _, b in blocks for p in b.values() for a in p.values())
    gap = 6
    cell_w, cell_h = (cw + gap) * 2 * sx, (ch + gap) * sy
    label = 14
    width = 3 * cell_w + 2 * gap * sx
    height = sum(label + len(b) * cell_h for _, b in blocks) + gap * sy
    im = Image.new("RGB", (width, height), pen_rgb(PEN["GREY"]))
    dr = ImageDraw.Draw(im)
    y0 = gap * sy // 2
    for name, b in blocks:
        dr.text((gap * sx, y0), name, fill=(255, 255, 255))
        y0 += label
        for p in PITCHES:
            for j, t in enumerate(TURNS):
                art = b[p][t]
                x0 = gap * sx + j * cell_w + (cw - len(art[0])) * sx
                yy = y0 + (ch - len(art)) * sy
                for ry, r in enumerate(art):
                    for rx, c in enumerate(r):
                        if c == ".":
                            continue
                        x = x0 + rx * 2 * sx
                        dr.rectangle([x, yy + ry * sy, x + 2 * sx - 1, yy + (ry + 1) * sy - 1],
                                     fill=pen_rgb(PEN[LETTERS[c]]))
            dr.text((gap * sx + 3 * cell_w - 40, y0 + 2), p, fill=(255, 255, 255))
            y0 += cell_h
    im.save(path)


VIEWS = [(p, t) for p in PITCHES for t in ("straight", "left", "right")]   # car_view


def game_art(cars, tops):
    """The views the race draws, in car_view's order (on the level, uphill,
    downhill; each straight, turning left, turning right), every car's over
    the same lines of the renders (the ground on the same line), the lines
    none of them uses left out."""
    rows = {}
    for name in CARS:
        a = cars[name]
        used = [i for i in range(len(a["flat"]["straight"]))
                if any(a[p][t][i].strip(".") for p, t in VIEWS)]
        flat = [i for i in range(len(a["flat"]["straight"]))
                if any(a["flat"][t][i].strip(".") for t in TURNS)]
        rows[name] = (tops[name] + used[0], tops[name] + used[-1], tops[name] + flat[-1])
    r0, r1 = min(r[0] for r in rows.values()), max(r[1] for r in rows.values())
    assert len({r[2] for r in rows.values()}) == 1, rows   # (the wheels on the ground)
    ground = rows[CARS[0]][2] - r0
    out = ["", "# The race's views, car_view 0-8 (flat, up, down x straight, left, right),",
           "# every car's over the renders' lines %d-%d: GAME_ART[car][car_view]; the" % (r0, r1),
           "# wheels on the level stand on line GAME_GROUND of them.",
           "GAME_GROUND = %d" % ground, "GAME_ART = {"]
    for name in CARS:
        a, w = cars[name], len(cars[name]["flat"]["straight"][0])
        out.append('    "%s": [' % name)
        for p, t in VIEWS:
            art = ["." * w if not tops[name] <= r < tops[name] + len(a[p][t])
                   else a[p][t][r - tops[name]] for r in range(r0, r1 + 1)]
            out.append("        [   # %s, %s" % (p, t))
            out += ['            "%s",' % r for r in art]
            out.append("        ],")
        out.append("    ],")
    out += ["}", ""]
    return out


def main():
    cars = {}
    lines = ['"""Generated by tools/mkcars.py from assets/cars/*.png - do not edit.',
             "",
             "The cars seen from behind: CARS_ART[car][pitch][turn], pitch flat, up or",
             "down, turn left, straight or right - rows of mode 0 pixels, letters as",
             "tools/mkcars.py LETTERS, '.' none.", '"""', "", "CARS_ART = {"]
    only = sys.argv[1:]
    tops = {}
    for name in CARS:
        if only and name not in only:
            continue
        cars[name], drawn, tops[name] = car_views(name)
        a = cars[name]["flat"]["straight"]
        print("%s: %d x %d pixels, %d drawn in its six rendered views"
              % (name, len(a[0]), len(a), drawn))
        lines.append('    "%s": {' % name)
        for p in PITCHES:
            lines.append('        "%s": {' % p)
            for t in TURNS:
                lines.append('            "%s": [' % t)
                lines += ['                "%s",' % r for r in cars[name][p][t]]
                lines.append("            ],")
            lines.append("        },")
        lines.append("    },")
    lines.append("}")
    lines.append("")
    if not only:
        lines += game_art(cars, tops)
    open(os.path.join(ROOT, "tools", "carsart.py"), "w").write("\n".join(lines))
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    sheet(cars, os.path.join(ROOT, "build", "cars-sheet.png"))


if __name__ == "__main__":
    main()
