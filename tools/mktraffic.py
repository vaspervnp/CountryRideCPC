#!/usr/bin/env python3
"""The traffic's sprites, from renders of their 3D models (tools/traffic3d.py,
in Blender: assets/traffic/s<size>_<top>_<bottom>_<pass>.png).

A traffic car is two pieces - a top (closed or open) on a bottom (sport,
saloon or GT) - and any top goes on any bottom: their models share the body
above the rear face, and the line between the pieces is the same for all.
Each piece's paint is black (K): the game gives each car its colours, one
for its top and one for its bottom - a pen, or two in a checkerboard - so a
few sprites make dozens of cars. Black is used for nothing else (the
darkest of the rest is navy).

The engine draws a sprite with PUSHes, two bytes - four pixels - at a time,
and gives the paint from registers: a byte (two pixels) is all paint or none.
So, from the renders:

- each cell (a mode 0 pixel) is paint where most of what covers it is (the
  paint pass), else the mean colour of the rest, over the asphalt's grey,
  brought to the pens without black (tools/dither.py) - what would be
  black, navy;
- a byte half paint is all paint or none, as the two cells' paint adds up;
- lone cells are dropped, each line's run widened to whole pairs of bytes
  over the asphalt's grey.

Writes tools/trafficart.py and build/traffic-sheet.png: each size's pieces,
and cars made of them in a few colours.
"""

import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cpcgfx import PEN, pen_rgb  # noqa: E402
import dither  # noqa: E402
import mkcar  # noqa: E402
import mkcars  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "assets", "traffic")
SIZES = 8                                   # tools/traffic3d.py SCALES
NEAR = 3                                    # the nearest, in two pieces
TOPS = ["closed", "open"]
BOTTOMS = ["sport", "saloon", "gt"]
FAR_BOTTOM = "saloon"                       # the further ones' only bottom
CELLS, CELL_PX = mkcar.CELLS, mkcar.CELL_PX

# the pens for what is not paint: the cars' own, but black
LETTERS = {c: p for c, p in mkcars.LETTERS.items() if c != "K"}
PALETTE = {c: pen_rgb(PEN[p]) for c, p in LETTERS.items()}
# the pairs that may mix: neighbours on the reds', the blues' and the greys'
# ramps
PAIRS = ["DR", "RO", "OY", "YW", "RW", "NB", "BS", "SH", "HW", "SP", "PW", "GW", "GP",
         "NG"]
PAINT = "K"


def load(size, top, bottom):
    """A render's cells: (alpha, paint, top, linear rgb sum of what is not
    paint), each summed over the cell's pixels."""
    ims = {p: Image.open(os.path.join(SRC, "s%d_%s_%s_%s.png" % (size, top, bottom, p)))
           .convert("RGBA") for p in ("car", "paint", "top")}
    w, h = ims["car"].size
    assert (w, h) == (CELLS[0] * CELL_PX[0], CELLS[1] * CELL_PX[1])
    car, paint, tp = (list(ims[p].get_flattened_data()) for p in ("car", "paint", "top"))
    out = [[[0.0, 0.0, 0.0, [0.0, 0.0, 0.0]] for _ in range(CELLS[0])] for _ in range(CELLS[1])]
    for i in range(w * h):
        y, x = divmod(i, w)
        c = out[y // CELL_PX[1]][x // CELL_PX[0]]
        a = car[i][3] / 255.0
        if not a:
            continue
        pa = paint[i][0] / 255.0 * paint[i][3] / 255.0
        c[0] += a
        c[1] += min(pa, a)
        c[2] += tp[i][0] / 255.0 * tp[i][3] / 255.0
        rest = a - min(pa, a)
        for k in range(3):
            c[3][k] += dither.LIN[car[i][k]] * rest
    return out


def art(size, top, bottom):
    """Rows of letters ('.' clear, K paint) and the rows the top covers."""
    n = CELL_PX[0] * CELL_PX[1]
    ul = [dither._lin(float(v)) for v in dither.ASPHALT]
    cells = load(size, top, bottom)
    colours, paint, toprows = [], [], set()
    for y, row in enumerate(cells):
        cr, pr = [], []
        for x, (a, pa, tc, s) in enumerate(row):
            if tc / n >= 0.3:
                toprows.add(y)
            if a / n < 0.5:
                cr.append(None)
                pr.append(0.0)
                continue
            rest = n - pa                       # what is not paint, the grey too
            cr.append(tuple(dither._srgb((s[k] + ul[k] * (n - a)) / rest) for k in range(3))
                      if rest > 0.5 else dither.ASPHALT)
            pr.append(pa / n)
        colours.append(cr)
        paint.append(pr)
    graded = dither.grade(colours)
    rows = [list(r) for r in dither.pattern(graded, PALETTE, PAIRS, mixed_only="G")]
    # what would be black - tyres, plastic, shadow - navy (dark grey is
    # nearer dark red, and black is the paint's)
    for y, row in enumerate(graded):
        for x, c in enumerate(row):
            if c is not None and max(c) < 64 and max(c) - min(c) < 40:
                rows[y][x] = "N"
    # paint, a byte (two cells from the middle column on) at a time
    for y in range(len(rows)):
        for x in range(0, CELLS[0], 2):
            if rows[y][x] == "." and rows[y][x + 1] == ".":
                continue
            if paint[y][x] + paint[y][x + 1] >= 1.0:
                rows[y][x] = rows[y][x + 1] = PAINT
    rows = mkcar.lone(["".join(r) for r in rows])
    return rows, toprows


def runs(rows):
    """Each line's run widened to a whole number of pairs of bytes (four
    pixels), from its first byte, over the asphalt's grey."""
    out = []
    for r in rows:
        xs = [i for i, c in enumerate(r) if c != "."]
        if not xs:
            out.append(r)
            continue
        a = xs[0] // 2 * 2
        b = a + (xs[-1] + 1 - a + 3) // 4 * 4
        if b > len(r):
            a, b = a - (b - len(r)), len(r)
        out.append(r[:a] + r[a:b].replace(".", "G") + r[b:])
    return out


def size_art(size):
    """{"split": the top's lines, "tops": {kind: rows}, "bottoms": {...},
    "whole": drawn as one piece}, all cut to one box. The further sizes have
    the one bottom, FAR_BOTTOM: each top on it is a sprite of its own, the
    line between them where its paint's colour changes."""
    bottoms_of = BOTTOMS if size < NEAR else [FAR_BOTTOM]
    tops, bottoms, split = {}, {}, 0
    full = {}
    for t in TOPS:
        full[t, bottoms_of[0]] = art(size, t, bottoms_of[0])
    for b in bottoms_of[1:]:
        full[TOPS[0], b] = art(size, TOPS[0], b)
    split = 1 + max(max(tr) for rows, tr in full.values() if tr)
    for t in TOPS:
        tops[t] = runs(full[t, bottoms_of[0]][0][:split])
    for b in bottoms_of:
        bottoms[b] = runs(full[TOPS[0], b][0][split:])
    every = list(tops.values()) + list(bottoms.values())
    used = [i for v in tops.values() for i, r in enumerate(v) if r.strip(".")]
    first = min(used)
    last = max(i for v in bottoms.values() for i, r in enumerate(v) if r.strip("."))
    xs = [i for v in every for r in v for i, c in enumerate(r) if c != "."]
    half = max(mkcar.MID - min(xs), max(xs) + 1 - mkcar.MID)
    half += half % 2
    cut = slice(mkcar.MID - half, mkcar.MID + half)
    return dict(split=split - first, whole=size >= NEAR,
                tops={t: [r[cut] for r in v[first:]] for t, v in tops.items()},
                bottoms={b: [r[cut] for r in v[:last + 1]] for b, v in bottoms.items()})


# Colours a car's paint can take: a pen, or two in a checkerboard (a byte -
# two pixels - one way round on even lines, the other on odd ones)
COLOURS = [("RED",), ("ORANGE",), ("YELLOW",), ("WHITE",), ("BLUE",), ("SKY",),
           ("PASTEL",), ("GRASS_A",), ("BUSH",), ("MAUVE",), ("CAR_DARK",), ("BLACK",),
           ("NAVY",), ("RED", "ORANGE"), ("ORANGE", "YELLOW"), ("YELLOW", "WHITE"),
           ("BLUE", "SKY"), ("SKY", "WHITE"), ("RED", "CAR_DARK"), ("MAUVE", "PASTEL"),
           ("GRASS_A", "GRASS_B"), ("HAZE", "WHITE")]


def painted(rows, colour, line0=0):
    """The rows as pens, the paint in `colour`."""
    out = []
    for y, r in enumerate(rows):
        line = []
        for x, c in enumerate(r):
            if c == ".":
                line.append(None)
            elif c == PAINT:
                pens = colour * 2 if len(colour) == 1 else colour
                line.append(PEN[pens[(x + y + line0) % 2]])
            else:
                line.append(PEN[LETTERS[c]])
        out.append(line)
    return out


def sheet(sizes, path, sx=4, sy=4):
    """Per size: the pieces (paint black), then cars of them in colours."""
    cw = max(len(s["tops"][TOPS[0]][0]) for s in sizes) + 6
    cols = 6
    blocks = []
    for s in sizes:
        h = len(s["tops"][TOPS[0]]) + len(next(iter(s["bottoms"].values()))) + 4
        blocks.append((s, h))
    height = sum(14 + h * sy * (1 + (2 * len(TOPS) * len(s["bottoms"]) + cols - 1) // cols)
                 for s, h in blocks)
    im = Image.new("RGB", (cols * cw * 2 * sx, height + 10), pen_rgb(PEN["GREY"]))
    dr = ImageDraw.Draw(im)

    def blit(pens, x0, y0):
        for y, line in enumerate(pens):
            for x, p in enumerate(line):
                if p is not None:
                    xx = x0 + x * 2 * sx
                    dr.rectangle([xx, y0 + y * sy, xx + 2 * sx - 1, y0 + (y + 1) * sy - 1],
                                 fill=pen_rgb(p))
    y0, k = 4, 0
    for si, (s, h) in enumerate(blocks):
        combos = [(t, b) for t in TOPS for b in s["bottoms"]]
        n = len(s["tops"][TOPS[0]])
        dr.text((4, y0), "size %d: %d x %d pixels, the top %d lines%s" % (
            si, len(s["tops"][TOPS[0]][0]), n + len(next(iter(s["bottoms"].values()))),
            s["split"], ", one piece" if s["whole"] else ""), fill=(255, 255, 255))
        y0 += 14
        for i, t in enumerate(TOPS):
            blit(painted(s["tops"][t], ("BLACK",)), 8 + i * cw * 2 * sx, y0)
        for i, b in enumerate(s["bottoms"]):
            blit(painted(s["bottoms"][b], ("BLACK",)), 8 + (2 + i) * cw * 2 * sx, y0 + n * sy)
        y0 += h * sy
        for j, (t, b) in enumerate(combos * 2):
            top_c = COLOURS[(7 * k) % len(COLOURS)]
            bot_c = top_c if j < len(combos) else COLOURS[(7 * k + 5) % len(COLOURS)]
            k += 1
            x0 = 8 + (j % cols) * cw * 2 * sx
            yy = y0 + (j // cols) * h * sy
            blit(painted(s["tops"][t], top_c), x0, yy)
            blit(painted(s["bottoms"][b], bot_c, n), x0, yy + n * sy)
        y0 += ((2 * len(combos) + cols - 1) // cols) * h * sy
    im.save(path)


def main():
    sizes = [size_art(s) for s in range(SIZES)]
    lines = ['"""Generated by tools/mktraffic.py from assets/traffic/*.png - do not edit.',
             "",
             "The traffic's sprites: TRAFFIC_ART[size] = {split, whole, tops, bottoms} -",
             "split: the lines of the top piece; tops[closed|open] and",
             "bottoms[sport|saloon|gt] (the further sizes, whole: saloon only, each",
             "top drawn on it as one sprite): rows of mode 0 pixels, letters as",
             "tools/mktraffic.py LETTERS, '.' none, K the car's paint.", '"""', "",
             "TRAFFIC_ART = ["]
    for si, s in enumerate(sizes):
        lines.append("    dict(split=%d, whole=%s, tops={" % (s["split"], s["whole"]))
        for t in TOPS:
            lines.append('        "%s": [' % t)
            lines += ['            "%s",' % r for r in s["tops"][t]]
            lines.append("        ],")
        lines.append("    }, bottoms={")
        for b in s["bottoms"]:
            lines.append('        "%s": [' % b)
            lines += ['            "%s",' % r for r in s["bottoms"][b]]
            lines.append("        ],")
        lines.append("    }),")
        print("size %d: %d x %d pixels, the top %d lines%s" % (
            si, len(s["tops"][TOPS[0]][0]),
            len(s["tops"][TOPS[0]]) + len(next(iter(s["bottoms"].values()))), s["split"],
            ", one piece" if s["whole"] else ""))
    lines += ["]", ""]
    open(os.path.join(ROOT, "tools", "trafficart.py"), "w").write("\n".join(lines))
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    sheet(sizes, os.path.join(ROOT, "build", "traffic-sheet.png"))


if __name__ == "__main__":
    main()
