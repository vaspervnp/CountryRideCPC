#!/usr/bin/env python3
"""The screen the player picks a car on, before the race.

The loader (disc/country.bas) shows it while the game loads - the firmware's
own mode 0 screen, 160 x 200, at #C000 - and then lets the player pick:
the four cars seen from the side in a 2 x 2 grid, each in a dim frame
with its name and its speed, acceleration and grip as bars; the
loader draws the picked one's frame over in a pen of its own (LIT,
flashing), and shows a "loading" line or the keys' line, each in a pen of
its own too, by their inks alone.

It is the title screen too: COUNTRY RIDE above the cars, twice as wide
and high as the small font, yellow to orange to red down its lines; and
the credits at the bottom.

The side views are pictures of the cars the models are after (PHOTOS,
below; a car without one would show its model's render, tools/cars3d.py
SIDE=True: assets/cars/side_<car>.png), brought to this screen's own pens
as the race's views are to the game's (tools/dither.py: each cell's mean
colour over the panel's grey, graded, a checkerboard where two
neighbouring pens mix nearer), lone cells dropped, outlined in black.
Writes src/gen/select.scr (the screen's 16K, SELECT.SCR) and
build/select.png (how it looks, the first car picked), and puts its pens
in the loader's DATA line.
"""

import os
import re
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dither  # noqa: E402
import mkcar  # noqa: E402
from cpcgfx import FIRMWARE, m0_byte  # noqa: E402
from scene import CAR_LEVELS, SMALL, SMALL_NAMES  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
W, H = 160, 200
SIDE_CELLS = (88, 40)
SIDE_PX = 15.0                  # (as tools/cars3d.py: mode 0 pixels a metre
SIDE_SQUASH = 0.8               # along the car, its heights times this)
SIDE_ORIGIN = (142, 305)        # where the renders have the rear and the
                                # ground (render pixels)

# Side views not their models' renders - made for the race's small views,
# they looked wrong from the side - but pictures of the cars they are
# modelled on, in assets/cars as downloaded:
#   ferrari  photo_ferrari.png: Wikimedia Commons, File:Ferrari_Testarossa.svg
#            (charner1963, from Openclipart), CC0 - public domain - at 1280
#            x 990: a drawing facing right on a clear ground
#   player   photo_player.jpg: a photo the user gave (605 x 330, a Google
#            Images thumbnail; its source and licence unknown), facing left
#            on a car park: cut out (`cut`: the red paint's columns, top to
#            bottom - and the lights', brighter than the asphalt, in their
#            boxes - their narrow gaps closed, and the wheels' discs), mirrored
#   lotus    photo_lotus.png: Wikimedia Commons, File:Lotus_esprite.svg
#            (cactus cowboy, from Openclipart), CC0, at 1280 x 348: a
#            drawing in black and white, facing right; its glass (filled
#            from `glass_seeds`) made dark, the rest of its white and greys
#            the yellow paint, but for its rims (discs: x, y, r)
#   bmw      photo_bmw.webp: a picture the user gave (BMW's configurator,
#            548 x 232; BMW's), a blue estate facing left: the blue made
#            the race's car's white, mirrored - its length less than the
#            car's, or it would not fit its panel
# Each its car's length (metres), its lettering and badges painted out
# (boxes in its pixels: a colour, or the yellow in it greyed), its
# see-through glass - or what is not its paint in `glass_box`, a photo's
# windows showing the sky - made the renders' dark glass, its colours brighter by
# `gain` (a flat red as the renders' lit flanks: the pen, not a
# checkerboard), laid on the renders' frame as cars3d.py lays a model.
PHOTOS = {"ferrari": dict(file="photo_ferrari.png", length=4.485, gain=1.17,
                          glass=(20, 25, 40),
                          paint=[((359, 610, 428, 637), (218, 2, 0)),  # the
                                 ((429, 610, 433, 637), "yellow")],    # badge
                          grey=[(235, 619, 260, 645), (943, 619, 968, 645)]),  # caps
          "player": dict(file="photo_player.jpg", length=4.35, flip=True, gain=1.35,
                         cut=dict(close=15, wheels=[(159.5, 210.5, 41), (472, 211, 41)],
                                  lights=[(75, 155, 116, 182)]),         # the nose's
                         paint=[((397, 200, 416, 208), (150, 20, 5))],      # badge
                         glass_box=(250, 104, 410, 152), glass=(20, 25, 40)),
          "lotus": dict(file="photo_lotus.png", length=4.33, glass=(20, 25, 40),
                        glass_seeds=[(460, 60), (600, 60), (750, 70)],
                        recolour=("grey", (255, 235, 40)), rims=[(250, 241, 62), (972, 242, 62)]),
          "bmw": dict(file="photo_bmw.webp", length=4.45, flip=True,
                      recolour=("blue", (255, 255, 255)), glass=(20, 25, 40),
                      glass_box=(190, 52, 475, 100))}

# The cars, in the game's order (car_id 0-3), and their names
CARS = [("player", "ROSSO GT"), ("ferrari", "BERLINETTA"), ("lotus", "WEDGE TURBO"),
        ("bmw", "TOURING")]
TITLE = "COUNTRY RIDE"
TITLE_PENS = "YYYYOOOOORRRRR"             # its 14 lines' pens, top down
LOADING = "LOADING"
KEYS = "1-4 OR ARROWS, THEN FIRE"
CREDITS = "REVIVE8BIT - 2026 - VASPER"

# This screen's own pens: letter, firmware colour. The cars' and the
# screen's colours (pink: the red paint's highlights; pastel cyan: the
# white car's and the glass's), then the picked frame's (LIT: the loader
# makes it flash) and the two lines the loader shows or hides.
PENS = [("K", 0), ("N", 1), ("B", 2), ("S", 11), ("P", 14), ("W", 26), ("G", 13),
        ("R", 6), ("D", 3), ("O", 15), ("Y", 24), ("I", 16), ("H", 23),
        ("LIT", 24), ("LOADING", 26), ("KEYS", 1)]
PEN = {n: i for i, (n, _) in enumerate(PENS)}
RGB = {n: FIRMWARE[c][1] for n, c in PENS[:13]}
PAIRS = ["KD", "DR", "RI", "IW", "RO", "OY", "YW", "KN", "NB", "BS", "SH", "HW",
         "SP", "PW", "KG", "GW", "GP", "NG"]
BG = PEN["N"]
FRAME = PEN["B"]                              # (the picked one's: LIT)
HIDDEN = 1                                    # a hidden line's ink: the navy


def yellow(p):
    return p[3] and p[0] > 180 and p[1] > 140 and p[2] < 110


def red(p):
    return p[0] > 110 and p[0] > 1.7 * p[1] and p[0] > 1.7 * p[2]


def blue(p):
    return p[2] > p[0] + 40 and p[2] > p[1] + 20


def cut_out(im, close, wheels, lights=()):
    """A red car on a photo's ground: clear but for each column's red - or
    a light's, in its box (x0, y0, x1, y1) brighter than the asphalt - top
    to bottom, those edges' gaps narrower than `close` closed (the glass
    between the roof and the bonnet), and the wheels' discs (x, y, r)."""
    from PIL import ImageDraw
    w, h = im.size
    px = im.load()

    def car(x, y):
        return red(px[x, y]) or any(x0 <= x <= x1 and y0 <= y <= y1 and min(px[x, y][:3]) > 195
                                    for x0, y0, x1, y1 in lights)
    top, bot = [h] * w, [-1] * w
    for x in range(w):
        ys = [y for y in range(h) if car(x, y)]
        if len(ys) > 3:
            top[x], bot[x] = ys[0], ys[-1]
    k = close // 2

    def run(v, f, g):                   # f then g over 2k + 1 columns
        a = [f(v[max(0, x - k):x + k + 1]) for x in range(w)]
        return [g(a[max(0, x - k):x + k + 1]) for x in range(w)]
    top = [min(t, c) if c < h else t for t, c in zip(top, run(top, min, max))]
    bot = [max(b, c) if c >= 0 else b for b, c in zip(bot, run(bot, max, min))]
    mask = Image.new("L", (w, h), 0)
    mp = mask.load()
    for x in range(w):
        for y in range(top[x], bot[x] + 1):
            mp[x, y] = 255
    d = ImageDraw.Draw(mask)
    for cx, cy, r in wheels:
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    im.putalpha(mask)
    return im


def glass_mask(im, seeds):
    """The pixels of a drawing's glass: its white regions holding `seeds`."""
    from PIL import ImageDraw
    g = im.convert("L")
    for s in seeds:
        ImageDraw.floodfill(g, s, 1, thresh=60)
    return {(x, y) for y in range(g.size[1]) for x in range(g.size[0]) if g.getpixel((x, y)) == 1}


def recolour(p, how, paint):
    """A pixel of the paint's colour (`how`: "grey", a drawing's white and
    greys; "blue", a blue car's) made `paint`, as bright as it was."""
    r, g, b, a = p
    if how == "grey":
        v = (r + g + b) / 3
        if v < 60 or max(r, g, b) - min(r, g, b) > 30:
            return p
        k = v / 255
    else:
        if not blue(p):
            return p
        k = min(1.0, max(r, g, b) / 255 * 1.3)
    return tuple(round(c * k) for c in paint) + (a,)


def photo_side(name):
    """PHOTOS' side view of car `name`, on the renders' frame (RGBA)."""
    ph = PHOTOS[name]
    im = Image.open(os.path.join(ROOT, "assets", "cars", ph["file"])).convert("RGBA")
    if "cut" in ph:
        im = cut_out(im, **ph["cut"])
    px = im.load()
    glass = glass_mask(im, ph["glass_seeds"]) if "glass_seeds" in ph else set()
    if "glass_box" in ph:
        paint = blue if ph.get("recolour", ("",))[0] == "blue" else red
        x0, y0, x1, y1 = ph["glass_box"]
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if px[x, y][3] and not paint(px[x, y]):
                    glass.add((x, y))
    for x, y in glass:
        px[x, y] = ph["glass"] + (255,)
    if "recolour" in ph:
        rims = ph.get("rims", [])
        for y in range(im.size[1]):
            for x in range(im.size[0]):
                if (x, y) not in glass and px[x, y][3] and not any((x - cx) ** 2 + (y - cy) ** 2 <= r * r
                                             for cx, cy, r in rims):
                    px[x, y] = recolour(px[x, y], *ph["recolour"])
    for (x0, y0, x1, y1), colour in ph.get("paint", []):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if colour != "yellow":
                    px[x, y] = colour + (255,)
                elif yellow(px[x, y]):
                    px[x, y] = (218, 2, 0, 255)
    for x0, y0, x1, y1 in ph.get("grey", []):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if yellow(px[x, y]):
                    px[x, y] = (170, 170, 170, 255)
    gain = ph.get("gain", 1.0)
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b, a = px[x, y]
            if not a:
                continue
            if "glass" in ph and (a < 255 and b > r + 100 or (r, g, b) == ph["glass"]):
                px[x, y] = ph["glass"] + (255,)
            elif gain != 1.0:
                px[x, y] = tuple(min(255, round(v * gain)) for v in (r, g, b)) + (a,)
    im = im.crop(im.split()[3].getbbox())
    if ph.get("flip"):
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    sx = SIDE_PX * dither.CELL_PX[0] * ph["length"] / im.size[0]
    sy = sx * SIDE_SQUASH
    im = im.resize((round(im.size[0] * sx), round(im.size[1] * sy)), Image.LANCZOS)
    out = Image.new("RGBA", (SIDE_CELLS[0] * dither.CELL_PX[0], SIDE_CELLS[1] * dither.CELL_PX[1]))
    out.alpha_composite(im, (SIDE_ORIGIN[0], SIDE_ORIGIN[1] - im.size[1]))
    return out


def side_art(name):
    """The car seen from the side: rows of pens or None, cut to the car,
    outlined in black on its outside."""
    src = (photo_side(name) if name in PHOTOS
           else os.path.join(ROOT, "assets", "cars", "side_%s.png" % name))
    cells = dither.grade(dither.cell_colours(src, SIDE_CELLS, under=RGB["G"]))
    rows = mkcar.lone(dither.pattern(cells, RGB, PAIRS, mixed_only="G"))
    used = [y for y, r in enumerate(rows) if r.strip(".")]
    xs = [x for r in rows for x, c in enumerate(r) if c != "."]
    x0, x1 = min(xs) - 1, max(xs) + 2
    rows = [r[x0:x1] for r in rows[used[0] - 1:used[-1] + 2]]
    h, w = len(rows), len(rows[0])
    out = [[None if c == "." else PEN[c] for c in r] for r in rows]
    for y in range(h):
        for x in range(w):
            if out[y][x] is None and any(
                    0 <= y + dy < h and 0 <= x + dx < w and rows[y + dy][x + dx] != "."
                    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))):
                out[y][x] = PEN["K"]
    return out


def text(s, pen, scale_y=1, shadow=True):
    """The small font's glyphs, a pixel apart, with a black shadow a pixel
    right and scale_y lines down: rows of pens or None."""
    rows = [""] * 7
    for ch in s:
        g = SMALL[SMALL_NAMES.get(ch, ch)]
        for j in range(7):
            rows[j] += g[j] + "."
    rows = [r[:-1] for r in rows]
    w, h = len(rows[0]), 7 * scale_y
    out = [[None] * (w + 1) for _ in range(h + scale_y)]
    for j in range(h if shadow else 0):
        for i, c in enumerate(rows[j // scale_y]):
            if c == "#":
                out[j + scale_y][i + 1] = PEN["K"]
    for j in range(h):
        for i, c in enumerate(rows[j // scale_y]):
            if c == "#":
                out[j][i] = pen
    return out


def title(s):
    """The title: the small font twice as wide and high, its lines' pens
    TITLE_PENS, with a black shadow a pixel right and two lines down."""
    small = text(s, 0, 1, shadow=False)
    h = 2 * 7
    rows = [[None] * (2 * len(small[0]) + 1) for _ in range(h + 2)]
    for dy, dx, pens in ((2, 1, "K" * h), (0, 0, TITLE_PENS)):
        for j in range(h):
            for i, p in enumerate(small[j // 2][:-1]):
                if p is not None:
                    for k in range(2):
                        rows[j + dy][2 * i + k + dx] = PEN[pens[j]]
    return rows


def stamp(scr, x, y, art):
    for j, r in enumerate(art):
        for i, p in enumerate(r):
            if p is not None:
                scr[y + j][x + i] = p


def centred(scr, y, art, x0=0, w=W):
    stamp(scr, x0 + (w - len(art[0])) // 2, y, art)


PANEL_W, PANEL_H = 78, 76
PANEL_X = [1, 81]
PANEL_Y = [19, 98]                            # (the loader's frames: line 500)


# what the cars are like (scene.py CAR_LEVELS: the game drives them so),
# 1-5 a bar of five
STATS = [("SPEED", "Y"), ("ACCEL", "O"), ("GRIP", "S")]
STAT_LABEL_W = 26                             # pixels, the labels right-aligned
STAT_X = (PANEL_W - STAT_LABEL_W - 3 - 5 * 4 + 1) // 2


def stat_row(stat, level):
    """A label and a bar: `level` of five blocks lit, the rest navy."""
    name, pen = stat
    label = text(name, PEN["W"])
    w = STAT_LABEL_W + 3 + 5 * 4 - 1
    row = [[None] * w for _ in range(8)]
    for j, r in enumerate(label):
        for i, p in enumerate(r):
            row[j][STAT_LABEL_W - len(label[0]) + 1 + i] = p
    for k in range(5):
        for y in range(1, 6):
            for x in range(3):
                row[y][STAT_LABEL_W + 3 + 4 * k + x] = PEN[pen] if k < level else PEN["N"]
    return row


def frame_px(i):
    """Panel i's frame: (x, y) of its pixels - its sides a pixel wide, its
    top and bottom two lines (what the loader draws over: DRAWR)."""
    x0, y0 = PANEL_X[i % 2], PANEL_Y[i // 2]
    x1, y1 = x0 + PANEL_W - 1, y0 + PANEL_H - 1
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if x in (x0, x1) or y in (y0, y0 + 1, y1 - 1, y1):
                yield x, y


def screen():
    scr = [[BG] * W for _ in range(H)]
    centred(scr, 2, title(TITLE))
    for i, (name, label) in enumerate(CARS):
        x0, y0 = PANEL_X[i % 2], PANEL_Y[i // 2]
        for y in range(y0, y0 + PANEL_H):
            for x in range(x0, x0 + PANEL_W):
                scr[y][x] = PEN["G"]
        for x, y in frame_px(i):
            scr[y][x] = FRAME
        centred(scr, y0 + 4, text("%d %s" % (i + 1, label), PEN["W"]), x0, PANEL_W)
        art = side_art(name)
        assert len(art[0]) <= PANEL_W - 4 and len(art) <= 34, (name, len(art[0]), len(art))
        centred(scr, y0 + 47 - len(art), art, x0, PANEL_W)
        for j, (stat, level) in enumerate(zip(STATS, CAR_LEVELS[i])):
            stamp(scr, x0 + STAT_X, y0 + 48 + 8 * j, stat_row(stat, level))
    # the two lines the loader shows one at a time: no shadows (they would
    # stay when the line is hidden); the credits
    centred(scr, 176, text(LOADING, PEN["LOADING"], shadow=False))
    centred(scr, 184, text(KEYS, PEN["KEYS"], shadow=False))
    centred(scr, 192, text(CREDITS, PEN["S"]))
    return scr


def to_bytes(scr):
    mem = bytearray(0x4000)
    for y in range(H):
        a = (y & 7) * 0x800 + (y >> 3) * 80
        for b in range(80):
            mem[a + b] = m0_byte(scr[y][2 * b], scr[y][2 * b + 1])
    return mem


def png(scr, path, lit=0, ready=True, sx=4, sy=2):
    scr = [list(r) for r in scr]
    for x, y in frame_px(lit):
        scr[y][x] = PEN["LIT"]
    ink = [c for _, c in PENS]
    ink[PEN["LOADING"]] = HIDDEN if ready else 26
    ink[PEN["KEYS"]] = 26 if ready else HIDDEN
    im = Image.new("RGB", (W * sx, H * sy))
    px = im.load()
    for y in range(H * sy):
        for x in range(W * sx):
            px[x, y] = FIRMWARE[ink[scr[y // sy][x // sx]]][1]
    im.save(path)


def main():
    scr = screen()
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    open(os.path.join(ROOT, "src", "gen", "select.scr"), "wb").write(to_bytes(scr))
    png(scr, os.path.join(ROOT, "build", "select.png"))
    # the loader's DATA line with this screen's pens
    bas = os.path.join(ROOT, "disc", "country.bas")
    text = open(bas).read()
    data = "1020 DATA " + ",".join(str(c) for _, c in PENS)
    text, n = re.subn(r"^1020 DATA .*$", data, text, flags=re.M)
    assert n == 1
    open(bas, "w").write(text)
    print("select: pens (firmware) " + ",".join(str(c) for _, c in PENS))


if __name__ == "__main__":
    main()
