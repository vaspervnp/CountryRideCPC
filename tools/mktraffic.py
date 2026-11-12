#!/usr/bin/env python3
"""The traffic's sprites, from renders of their 3D models (tools/traffic3d.py,
in Blender: assets/traffic/s<size>_<top>_<bottom>_<pass>.png).

A traffic car is two pieces - a top on a bottom - and any top goes on any
bottom: their models share the body above the rear face, and the line
between the pieces is the same for all. traffic3d.py renders two tops
(closed, open) and three bottoms (sport, saloon, GT); since 2026-11-05 the
game has half of them, for room: the closed top, the sport and the saloon
bottoms (TOPS, BOTTOMS).
Each piece's paint is black (K): the game gives each car its colours, one
for its top and one for its bottom - a pen each - so a few sprites make
dozens of cars. Black is used for nothing else (the
darkest of the rest is navy).

The engine draws a sprite with PUSHes, two bytes - four pixels - at a time,
and gives the paint from registers: a byte (two pixels) is all paint or none.
So, from the renders:

- each cell (a mode 0 pixel) is paint where most of what covers it is (the
  paint pass), else the mean colour of the rest - its own, not over the
  asphalt - brought to the nearest of PENS (tools/dither.py; since
  2026-11-05 flat colours, no checkerboards, as the player's car) - what
  would be black, navy;
- a byte half paint is all paint or none, as the two cells' paint adds up;
  a cell mostly paint in a byte that is not takes the other cell's colour
  (or the byte is paint, the other cell clear);
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
TOPS = ["closed"]                           # (and "open": traffic3d.py)
BOTTOMS = ["sport", "saloon"]               # (and "gt")
FAR_BOTTOM = "saloon"                       # the further ones' only bottom
SIDES = 2                                   # the nearest seen from the side too
                                            # (since 2026-11-12; traffic3d.py YAW)
CELLS, CELL_PX = mkcar.CELLS, mkcar.CELL_PX

# the pens for what is not paint: the cars' own, but black
LETTERS = {c: p for c, p in mkcars.LETTERS.items() if c != "K"}
PALETTE = {c: pen_rgb(PEN[p]) for c, p in LETTERS.items()}
# the pens it is brought to (no blues: the glass's and the chrome's
# reflections of the sky would edge it in pastel)
PENS = "DROYWN"
PAINT = "K"
# each size is squeezed across to mkcar.NARROW of its render's width, but
# these, whose bytes round it badly at 0.8: size 0's up to 32 pixels (89% of
# the 36 it was, its bumper wider than its body), 28 at 0.78; size 3's to 16
# but a line of 20, 20 at 0.82
NARROW_SIZE = {0: 0.78, 3: 0.82}


def load(size, top, bottom, yaw=False):
    """A render's cells: (alpha, paint, top, linear rgb sum of what is not
    paint), each summed over the cell's pixels - its passes squeezed across
    (mkcar.narrow, NARROW_SIZE: since 2026-11-07 the cars are 20% narrower
    than their models). yaw: the render turned YAW degrees (_yaw.png)."""
    k = NARROW_SIZE.get(size, mkcar.NARROW)
    ims = {p: mkcar.narrow(Image.open(os.path.join(SRC, "s%d_%s_%s_%s%s.png"
                                                   % (size, top, bottom, p,
                                                      "_yaw" if yaw else "")))
                           .convert("RGBA"), k) for p in ("car", "paint", "top")}
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


def art(size, top, bottom, yaw=False):
    """Rows of letters ('.' clear, K paint) and the rows the top covers."""
    n = CELL_PX[0] * CELL_PX[1]
    cells = load(size, top, bottom, yaw)
    colours, paint, mostly, toprows = [], [], [], set()
    for y, row in enumerate(cells):
        cr, pr, mr = [], [], []
        for x, (a, pa, tc, s) in enumerate(row):
            if tc / n >= 0.3:
                toprows.add(y)
            if a / n < 0.5:
                cr.append(None)
                pr.append(0.0)
                mr.append(False)
                continue
            rest = a - pa                       # what is not paint, its own
            cr.append(tuple(dither._srgb(s[k] / rest) for k in range(3))
                      if rest > 0.5 else dither.ASPHALT)
            pr.append(pa / n)
            mr.append(2 * pa >= a)
        colours.append(cr)
        paint.append(pr)
        mostly.append(mr)
    graded = dither.grade(colours)
    rows = [list(r) for r in dither.pattern(graded, {c: PALETTE[c] for c in PENS}, [])]
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
                continue
            # a cell mostly paint in a byte that is not: its rim's colour
            # would be a speck - the byte paint if the other cell is clear,
            # else that cell's colour
            for c, o in ((x, x + 1), (x + 1, x)):
                if mostly[y][c] and not mostly[y][o]:
                    rows[y][c] = rows[y][o] = rows[y][o] if rows[y][o] != "." else PAINT
    rows = mkcar.lone(["".join(r) for r in rows])
    return rows, toprows


def runs(rows, right=False):
    """Each line's run widened to a whole number of pairs of bytes (four
    pixels), from its first byte - or back from its last, `right` - over
    the asphalt's grey."""
    out = []
    for r in rows:
        xs = [i for i, c in enumerate(r) if c != "."]
        if not xs:
            out.append(r)
            continue
        a = xs[0] // 2 * 2
        b = a + (xs[-1] + 1 - a + 3) // 4 * 4
        if right:
            b = (xs[-1] + 2) // 2 * 2
            a = b - (b - xs[0] + 3) // 4 * 4
        if b > len(r):
            a, b = a - (b - len(r)), len(r)
        out.append(r[:a] + r[a:b].replace(".", "G") + r[b:])
    return out


def size_art(size):
    """{"split": the top's lines, "tops": {kind: rows}, "bottoms": {...},
    "whole": drawn as one piece}, all cut to one box. The further sizes have
    the one bottom, FAR_BOTTOM: each top on it is a sprite of its own, the
    line between them where its paint's colour changes. The SIDES nearest
    have "sides" too: seen from the right of the middle of the screen and
    from its left (its left flank in view, then its right: the YAW renders
    and them mirrored; their lines widened to pairs towards the flank),
    [{"x0": the box's left from the car's - pixels, a
    whole number of bytes -, "tops", "bottoms"}] - over the same lines as
    the car from behind, the flank wider on its side alone (towards the
    middle of the screen; the rear face where the car's is)."""
    bottoms_of = BOTTOMS if size < NEAR else [FAR_BOTTOM]
    views = (False, True) if size < SIDES else (False,)
    full = {}
    for yaw in views:
        for t in TOPS:
            full[yaw, t, bottoms_of[0]] = art(size, t, bottoms_of[0], yaw)
        for b in bottoms_of[1:]:
            full[yaw, TOPS[0], b] = art(size, TOPS[0], b, yaw)
    split = 1 + max(max(tr) for rows, tr in full.values() if tr)
    pieces = {}
    for yaw in views:
        rows = {k[1:]: v[0] for k, v in full.items() if k[0] == yaw}
        tops = {t: runs(rows[t, bottoms_of[0]][:split], yaw) for t in TOPS}
        bottoms = {b: runs(rows[TOPS[0], b][split:], yaw) for b in bottoms_of}
        pieces[yaw] = tops, bottoms
    used = [i for tops, bottoms in pieces.values() for v in tops.values()
            for i, r in enumerate(v) if r.strip(".")]
    first = min(used)
    last = max(i for tops, bottoms in pieces.values() for v in bottoms.values()
               for i, r in enumerate(v) if r.strip("."))

    def xs(tops, bottoms):
        return [i for v in list(tops.values()) + list(bottoms.values())
                for r in v for i, c in enumerate(r) if c != "."]
    x = xs(*pieces[False])
    half = max(mkcar.MID - min(x), max(x) + 1 - mkcar.MID)
    half += half % 2

    def cut(tops, bottoms, a, b):
        return ({t: [r[a:b] for r in v[first:]] for t, v in tops.items()},
                {k: [r[a:b] for r in v[:last + 1]] for k, v in bottoms.items()})
    tops, bottoms = cut(*pieces[False], mkcar.MID - half, mkcar.MID + half)
    out = dict(split=split - first, whole=size >= NEAR, tops=tops, bottoms=bottoms)
    if True in pieces:
        tops, bottoms = pieces[True]
        x = xs(tops, bottoms)
        a, b = min(x) // 2 * 2, (max(x) + 2) // 2 * 2
        mirror = ({t: [r[::-1] for r in v] for t, v in tops.items()},
                  {k: [r[::-1] for r in v] for k, v in bottoms.items()})
        w = mkcar.CELLS[0]
        out["sides"] = []
        for (t, bt), (lo, hi) in (((tops, bottoms), (a, b)), (mirror, (w - b, w - a))):
            ct, cb = cut(t, bt, lo, hi)
            out["sides"].append(dict(x0=lo - (mkcar.MID - half), tops=ct, bottoms=cb))
    return out


# Colours a car's paint can take: a pen (or two in a checkerboard - a byte,
# two pixels, one way round on even lines, the other on odd ones - which
# the game no longer gives: scene.py TRAFFIC_COLOURS)
COLOURS = [("RED",), ("ORANGE",), ("YELLOW",), ("WHITE",), ("BLUE",), ("SKY",),
           ("PASTEL",), ("GRASS_A",), ("BUSH",), ("MAUVE",), ("CAR_DARK",), ("BLACK",),
           ("HAZE",), ("GRASS_B",)]


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
             "tools/mktraffic.py LETTERS, '.' none, K the car's paint. The SIDES",
             "nearest have sides too: [seen right of the middle (its left flank),",
             "left of it] each dict(x0 - its box's left from the car's, pixels -,",
             "tops, bottoms), over the same lines.", '"""', "",
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
        if "sides" not in s:
            lines.append("    }),")
        else:
            lines.append("    }, sides=[")
        for v in s.get("sides", []):
            lines.append("        dict(x0=%d, tops={" % v["x0"])
            for t in TOPS:
                lines.append('            "%s": [' % t)
                lines += ['                "%s",' % r for r in v["tops"][t]]
                lines.append("            ],")
            lines.append("        }, bottoms={")
            for b in v["bottoms"]:
                lines.append('            "%s": [' % b)
                lines += ['                "%s",' % r for r in v["bottoms"][b]]
                lines.append("            ],")
            lines.append("        }),")
        if "sides" in s:
            lines.append("    ]),")
        print("size %d: %d x %d pixels, the top %d lines%s" % (
            si, len(s["tops"][TOPS[0]][0]),
            len(s["tops"][TOPS[0]]) + len(next(iter(s["bottoms"].values()))), s["split"],
            ", one piece" if s["whole"] else ""))
    lines += ["]", ""]
    open(os.path.join(ROOT, "tools", "trafficart.py"), "w").write("\n".join(lines))
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    sheet(sizes, os.path.join(ROOT, "build", "traffic-sheet.png"))
    side_sheet(sizes, os.path.join(ROOT, "build", "traffic-sides.png"))


def side_sheet(sizes, path, sx=4, sy=4):
    """The sizes with sides: each bottom seen from the left of the middle,
    from behind and from the right, in two colours."""
    near = [s for s in sizes if "sides" in s]
    cw = max(len(v["tops"][TOPS[0]][0]) for s in near for v in s["sides"]) + 6
    h = max(len(s["tops"][TOPS[0]]) + len(next(iter(s["bottoms"].values()))) for s in near) + 4
    rows = [(s, b, c) for s in near for b in BOTTOMS for c in (("RED",), ("WHITE",))]
    im = Image.new("RGB", (3 * cw * 2 * sx + 16, len(rows) * h * sy + 8), pen_rgb(PEN["GREY"]))
    dr = ImageDraw.Draw(im)
    for i, (s, b, c) in enumerate(rows):
        n = len(s["tops"][TOPS[0]])
        views = [s["sides"][1], dict(x0=0, tops=s["tops"], bottoms=s["bottoms"]), s["sides"][0]]
        for j, v in enumerate(views):
            x0 = 8 + j * cw * 2 * sx + (v["x0"] + 6) * 2 * sx
            y0 = 4 + i * h * sy
            for y, line in enumerate(painted(v["tops"][TOPS[0]], c)
                                     + painted(v["bottoms"][b], ("ORANGE",) if c == ("WHITE",)
                                               else c, n)):
                for x, p in enumerate(line):
                    if p is not None:
                        xx = x0 + x * 2 * sx
                        dr.rectangle([xx, y0 + y * sy, xx + 2 * sx - 1, y0 + (y + 1) * sy - 1],
                                     fill=pen_rgb(p))
    im.save(path)


if __name__ == "__main__":
    main()
