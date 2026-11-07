#!/usr/bin/env python3
"""The cars' sprites, from photorealistic renders of their 3D models.

tools/cars3d.py (run in Blender) renders each car - the player's first -
seen from behind, on the level, uphill and downhill, each straight and
turning left, into assets/cars/<car>_<flat|up|down>_<0|left>.png. This
squeezes each across (mkcar.narrow: since 2026-11-07 the cars are 20%
narrower than their models), brings it to the pens (tools/dither.py: each
cell's mean colour over the asphalt's grey, graded, the nearest pen - no
checkerboards, and no outline: since 2026-11-05 the car is drawn in flat
colours), drops lone cells, widens each row's run to whole pairs over the
asphalt's grey (tools/mkcar.py), in one box for all of a car's views, and
adds the views turning right: the left ones mirrored. Nine sprites a car, in tools/carsart.py. Also draws them all into
build/cars-sheet.png.

The race also shows each car spun in a crash (assets/cars/<car>_spin.png,
cars3d.py spin_render): dust at its rear wheels, a box of its own - wider -
and spun right mirrored. GAME_ART has them as car_view 9 and 10.
"""

import colorsys
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
# the pens each car is brought to: its paint's ramp, black, navy (the
# glass), the lights' and the plate's; no blues - its paint's reflections of
# the sky would edge it in blue - but the white car's shade, pastel
CAR_PENS = dict(player="KDROYWN", ferrari="KDROYWN", lotus="KDROYWN", bmw="KDROYWNP")
# a coloured car's paint hue (degrees): what the renders show of it greyed
# by the sky's reflections - a cell as grey as PAINT_GREY, between black
# and the plate's white - is brought back to it, as bright; and a cell of
# about its hue (PAINT_NEAR) full of it, lest a lit red go orange
PAINT_HUE = dict(player=0, ferrari=0, lotus=55)
PAINT_GREY = 0.4
PAINT_NEAR = 15
PITCHES = ["flat", "up", "down"]
TURNS = ["left", "straight", "right"]


def repaint(cells, hue):
    """The greyed paint (see PAINT_HUE) its own colour again."""
    out = []
    for row in cells:
        r2 = []
        for c in row:
            if c is not None:
                h, s, v = colorsys.rgb_to_hsv(*(x / 255.0 for x in c))
                near = abs((h * 360 - hue + 180) % 360 - 180) <= PAINT_NEAR
                if s < PAINT_GREY and 0.25 < v < 0.97 or near and s >= PAINT_GREY:
                    c = tuple(255.0 * x for x in colorsys.hsv_to_rgb(hue / 360.0, 1.0, v))
            r2.append(c)
        out.append(r2)
    return out


def flat_pens(name, path, cells):
    """A render's cells, each its own colour (not over the asphalt), the
    paint's again where the sky greyed it, brought to the nearest of the
    car's pens, lone ones dropped; the render squeezed across first
    (mkcar.narrow)."""
    im = mkcar.narrow(Image.open(path).convert("RGBA"))
    graded = dither.grade(dither.cell_colours(im, cells, under=None))
    if name in PAINT_HUE:
        graded = repaint(graded, PAINT_HUE[name])
    palette = {c: PALETTE[c] for c in CAR_PENS[name]}
    return mkcar.lone(dither.pattern(graded, palette, []))


# The crash's view, rendered SPIN_CELLS wide with the others' frame in its
# middle, is moved SPIN_SHIFT cells (its tail swings out right of the
# others: this keeps its box nearer theirs); then dust at its rear wheels,
# clouds of (x, y, half width, half height) in the frame's cells: white
# over the car at their hearts, specks of it further out - drawn for the car
# as wide as rendered, squeezed across with it (about the render's middle).
SPIN_CELLS = 80
SPIN_SHIFT = -4
DUST = [(54, 19, 3.5, 6), (58, 14, 3, 5), (49, 23, 4, 3.4), (42, 24.5, 5, 1.8)]
_AXIS = mkcar.MID + SPIN_SHIFT
DUST = [(_AXIS + (x - _AXIS) * mkcar.NARROW, y, rx * mkcar.NARROW, ry) for x, y, rx, ry in DUST]


def dusty(rows):
    out = [list(r) for r in rows]
    for y, r in enumerate(out):
        for x in range(len(r)):
            d = min(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 for cx, cy, rx, ry in DUST)
            if d < 0.35:
                r[x] = "W"
            elif r[x] != ".":
                continue
            elif d < 0.6 or d < 1 and (x + 2 * y) % 4 == 0:
                r[x] = "W"
    return ["".join(r) for r in out]


def spin_view(name, width):
    """The car spun left, dust and all, in its box: rows over the whole
    frame's height, widened to pairs on the grid of the car's other views
    (`width` pixels, around the middle). The box as narrow as it can be."""
    path = os.path.join(SRC, "%s_spin.png" % name)
    art = flat_pens(name, path, (SPIN_CELLS, mkcar.CELLS[1]))
    cut = (SPIN_CELLS - mkcar.CELLS[0]) // 2 - SPIN_SHIFT
    assert not any(c != "." for r in art for c in r[:cut] + r[cut + mkcar.CELLS[0]:]), name
    p = (mkcar.MID - width // 2) % 4
    rows = [mkcar.pairs(r, p) for r in dusty([r[cut:cut + mkcar.CELLS[0]] for r in art])]
    xs = [i for r in rows for i, c in enumerate(r) if c != "."]
    half = max(mkcar.MID - min(xs), max(xs) + 1 - mkcar.MID)
    half += (mkcar.MID - half - p) % 4
    return [r[mkcar.MID - half:mkcar.MID + half] for r in rows]


def car_views(name):
    """{pitch: {turn: art}} for one car, all in one box."""
    renders = []
    for p in PITCHES:
        for v in ("0", "left"):
            path = os.path.join(SRC, "%s_%s_%s.png" % (name, p, v))
            renders.append(flat_pens(name, path, mkcar.CELLS))
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
    downhill; each straight, turning left, turning right; then spun left
    and right), every car's over the same lines of the renders (the ground
    on the same line), the lines none of them uses left out."""
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
    out = ["", "# The race's views, car_view 0-8 (flat, up, down x straight, left, right)",
           "# and 9-10 (spun in a crash, left and right: a wider box, as wide either",
           "# side), every car's over the renders' lines %d-%d: GAME_ART[car][car_view];" % (r0, r1),
           "# the wheels on the level stand on line GAME_GROUND of them.",
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
        spin = spin_view(name, w)
        assert not any(r.strip(".") for r in spin[:r0] + spin[r1 + 1:]), name
        for t, art in (("left", spin[r0:r1 + 1]), ("right", [r[::-1] for r in spin[r0:r1 + 1]])):
            out.append("        [   # spun %s" % t)
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
