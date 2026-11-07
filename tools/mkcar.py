#!/usr/bin/env python3
"""Renders of a car seen from behind made into sprite art - the shared
part of tools/mkcars.py (the race's cars) and tools/mkselect.py (their side
views).

A render is a frame of CELLS mode 0 pixels, each CELL_PX render pixels, its
middle column the screen's (tools/car3d.py's camera). From rows of letters
(a pen each, '.' none):

- a lone cell is dropped;
- each row's run is widened to whole pairs (4 pixels) and its gaps filled
  with the asphalt's grey (the engine draws a line's run with PUSHes) -
  pairs from the box's left edge, the box the same either side of the
  middle, so turning right - the left view mirrored - fits it too, and as
  wide as the widest view needs: of the two ways the pairs can fall
  (the edge 0 or 2 pixels past a multiple of 4), the one with the fewer
  pixels to draw.

cells() is the flat way, each cell its majority pen (renders in the
game's colours only); tools/dither.py the photorealistic one.
"""

import os
import sys
from collections import Counter

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cpcgfx import PEN, pen_rgb  # noqa: E402

CELLS = (64, 40)
CELL_PX = (16, 8)
MID = CELLS[0] // 2
# the race's cars - the player's and the traffic - are drawn this much of
# their renders' width (narrow(); since 2026-11-07, 20% narrower)
NARROW = 0.8


def narrow(im, k=NARROW):
    """The render squeezed across to k of its width about its middle (the
    screen's), in a frame as wide as it was: each pixel the mean of what
    it covers."""
    w, h = im.size
    nw = int(round(w * k / 2)) * 2
    small = im.convert("RGBa").resize((nw, h), Image.BOX).convert("RGBA")
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(small, ((w - nw) // 2, 0))
    return out

# letter -> pen, as scene.py CAR_PEN
LETTERS = dict(R="RED", O="ORANGE", Y="YELLOW", K="BLACK", G="GREY",
               W="WHITE", N="NAVY", S="SKY", D="CAR_DARK")


def cells(path, letters=LETTERS, frame=CELLS):
    """The render, `frame` cells, as rows of letters ('.' clear), of these
    pens."""
    im = Image.open(path).convert("RGBA")
    assert im.size == (frame[0] * CELL_PX[0], frame[1] * CELL_PX[1]), im.size
    px = im.load()
    rgb = {c: pen_rgb(PEN[p]) for c, p in letters.items()}   # (grey: the hubs)
    near = {}
    rows = []
    for cy in range(frame[1]):
        row = ""
        for cx in range(frame[0]):
            n = Counter()
            for y in range(cy * CELL_PX[1], (cy + 1) * CELL_PX[1]):
                for x in range(cx * CELL_PX[0], (cx + 1) * CELL_PX[0]):
                    r, g, b, a = px[x, y]
                    if a < 128:
                        n["."] += 1
                        continue
                    if (r, g, b) not in near:
                        near[r, g, b] = min(rgb, key=lambda c: sum(
                            (u - v) ** 2 for u, v in zip((r, g, b), rgb[c])))
                    n[near[r, g, b]] += 1
            row += n.most_common(1)[0][0]
        rows.append(row)
    return rows


def lone(rows):
    """Cells with nothing next to them across or up and down: dropped."""
    def at(x, y):
        return rows[y][x] if 0 <= y < len(rows) and 0 <= x < len(rows[y]) else "."
    return ["".join("." if c != "." and all(at(x + dx, y + dy) == "." for dx, dy in
                                            ((-1, 0), (1, 0), (0, -1), (0, 1))) else c
                    for x, c in enumerate(r)) for y, r in enumerate(rows)]


def pairs(r, p):
    """The row's run widened to whole pairs from p (0 or 2), its gaps grey."""
    xs = [i for i, c in enumerate(r) if c != "."]
    if not xs:
        return r
    a = (xs[0] - p) // 4 * 4 + p
    b = (xs[-1] + 4 - p) // 4 * 4 + p
    return r[:a] + r[a:b].replace(".", "G") + r[b:]


def fit(views, p):
    """The views in pairs from p, cut to the box: (pixels drawn, arts, rows)."""
    views = [[pairs(r, p) for r in v] for v in views]
    used = [i for v in views for i, r in enumerate(v) if r.strip(".")]
    top, bottom = min(used), max(used)
    xs = [i for v in views for r in v for i, c in enumerate(r) if c != "."]
    half = max(MID - min(xs), max(xs) + 1 - MID)
    half += (MID - half - p) % 4                    # the box's edge on a pair
    arts = [[r[MID - half:MID + half] for r in v[top:bottom + 1]] for v in views]
    return sum(len(r.strip(".")) for a in arts for r in a), arts, (top, bottom)
