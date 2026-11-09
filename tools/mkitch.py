#!/usr/bin/env python3
"""The itch.io page's theme: a banner and a background, in the game's own
pictures (tools/scene.py, the reference model) and the SUNSET stage's colours.

banner.png      960 wide (the page's column): the title as on the loader's
                screen (tools/mkselect.py) over the sunset, the road, the
                traffic and the ROSSO GT - a picture of the game, its mode 0
                pixels 6 x 3 (twice that in banner-2x.png, for HiDPI)
background.png  3840 x 1080 (itch.io's widest), the same pixels, centred on
                the banner: the sky, the mountains all round and the grass
                in stripes going on either side of it, palms and stumps
                beside the column; its last lines one green - the page's
                background colour below it

Writes assets/itch/.
"""

import os
import random
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import course  # noqa: E402
import mkselect  # noqa: E402
import scene as S  # noqa: E402
from cpcgfx import FAR_Z, FIRMWARE, PENS  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "itch")
SX, SY = 6, 3                   # a mode 0 pixel, in the PNG's
STAGE = "SUNSET"


def inks():
    """Each pen's colour on the stage (course.py STAGES' pens)."""
    st = next(s for s in course.STAGES if s["name"] == STAGE)
    fw = [c for _, c in PENS]
    for name, c in st["pens"].items():
        fw[S.PEN[name]] = c
    return [FIRMWARE[c][1] for c in fw]


def rgb_rows(pens):
    ink = inks()
    return [[ink[p] for p in row] for row in pens]


def stamp_select(rows, x, y, art):
    """mkselect art (its own pens, None clear) onto RGB rows."""
    for j, r in enumerate(art):
        for i, p in enumerate(r):
            if p is not None and 0 <= y + j < len(rows) and 0 <= x + i < len(rows[0]):
                rows[y + j][x + i] = FIRMWARE[mkselect.PENS[p][1]][1]


def save(rows, name, k=1):
    h, w = len(rows), len(rows[0])
    im = Image.new("RGB", (w, h))
    im.putdata([c for row in rows for c in row])
    im = im.resize((w * SX * k, h * SY * k), Image.NEAREST)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    im.save(path, optimize=True)
    print("wrote %s (%d x %d)" % (os.path.relpath(path, ROOT), im.width, im.height))


# ---------------------------------------------------------------------------
# The banner: lines BANNER_Y.. of a picture of the race, the middle 160 of
# its 192 pixels, the title in the navy above the sky's dither
# ---------------------------------------------------------------------------

BANNER_Y, BANNER_END = 112, 264
BANNER_X, BANNER_W = 16, 160
TITLE_Y = BANNER_Y + 4
ZCAM = 128                      # (the grass's stripes as the background's)
ROAD = dict(hill=0, zcam=ZCAM, curve=3, view=0, bushes=False,
            traffic=[(ZCAM + 330, 2, 0, 0, 1, 1), (ZCAM + 520, 1, 0, 1, 3, 3)])
PROPS = [(130, "palm", -1, 0), (200, "palm", 1, 0)]     # (scene.prop_item's)
HEADING = 20                    # (sky_lines': words)


def banner():
    sky = S.sky_lines(heading=HEADING)
    road = S.road_area(**ROAD)
    for prop in sorted(PROPS, reverse=True):
        S.draw_prop(road, S.ROAD_AREA_Y, prop, ROAD["hill"], ROAD["curve"])
    hud = [[S.HUD_BG] * S.SCR_W for _ in range(S.HUD_H)]
    pic = S.shown(hud, sky, road, 0)
    rows = rgb_rows([r[BANNER_X:BANNER_X + BANNER_W] for r in pic[BANNER_Y:BANNER_END]])
    t = mkselect.title(mkselect.TITLE)
    stamp_select(rows, (BANNER_W - len(t[0])) // 2, TITLE_Y - BANNER_Y, t)
    return rows


# ---------------------------------------------------------------------------
# The background: BG_W x BG_H pixels, its line 0 the banner's first (the
# picture's BANNER_Y) and its middle the banner's, so that the mountains and
# the horizon go on either side of it where the banner is at the page's top;
# below them the grass in the race's stripes - further down than the race
# shows, on to the nearest stripe, one green (the page's colour below it) -
# and the stage's trees standing in it beside the column
# ---------------------------------------------------------------------------

BG_W, BG_H = 640, 360           # 3840 x 1080: itch.io's largest width
COLUMN = 80                     # half the page's column, pixels (480 px)
BG_ZCAM = ZCAM                  # the stripes' camera: the nearest one (depth
                                # 0-63) plain, and on as in the banner
BG_TREES = 26                   # a side
BG_SEED = 1985


def bg_pen(x, y, top, pano):
    """The pen at line y (the race picture's), pixel x of the panorama
    (scene.horizon_panorama's top and lines)."""
    if y < S.BLOCK_BOTTOM:
        if y < top:
            return S.sky_pen(x, y)
        return pano[y - top][x % S.PANORAMA_W]
    r = y - S.HORIZON_Y
    if r < 1:
        return S.GROUND_PEN
    z = S.row_depth(r)
    if z > FAR_Z:
        return S.PEN["GRASS_A"]
    return S.PEN["GRASS_B"] if (z + BG_ZCAM) >> 6 & 1 else S.PEN["GRASS_A"]


def trees():
    """(row, x, kind): where each tree stands, the furthest first - rows
    the race's (prop sizes as there), x from the middle as the race lays a
    tree out, so many metres off the road: near, further out."""
    rnd = random.Random(BG_SEED)
    out = []
    for side in (-1, 1):
        n = 0
        while n < BG_TREES:
            r = rnd.randint(10, S.NEAR_ROW)
            d = rnd.uniform(1.4, 8.0)
            x = int(d * r)
            kind = "stump" if rnd.random() < 0.3 else "palm"
            if not COLUMN + 6 <= x <= BG_W // 2 - 4 or S.prop_size_of(r) is None:
                continue
            if any(abs(r - r2) < 3 and abs(side * x - x2) < 12 for r2, x2, _ in out):
                continue
            out.append((r, side * x, kind))
            n += 1
    return sorted(out)


def background():
    y0 = BANNER_Y
    pano_x = BANNER_X + BANNER_W // 2 + 4 * HEADING - BG_W // 2
    top, pano = S.horizon_panorama()
    pens = [[bg_pen(x + pano_x, y0 + j, top, pano) for x in range(BG_W)]
            for j in range(BG_H)]
    for r, x, kind in trees():
        spr = S.prop_sprite(kind, S.prop_size_of(r))
        left = BG_W // 2 + x - 2 * S.prop_hw(kind, len(spr[0]) // 2)
        base = S.HORIZON_Y + r - y0
        for j, row in enumerate(spr):
            yy = base - len(spr) + 1 + j
            for i, p in enumerate(row):
                if p is not None and 0 <= left + i < BG_W and 0 <= yy < BG_H:
                    pens[yy][left + i] = p
    assert len({tuple(r) for r in pens[-40:]}) == 1      # (one green below)
    return rgb_rows(pens)


def main():
    rows = banner()
    save(rows, "banner.png")
    save(rows, "banner-2x.png", 2)
    rows = background()
    save(rows, "background.png")
    print("background's colour below it: #%02X%02X%02X" % rows[-1][0])


if __name__ == "__main__":
    main()
