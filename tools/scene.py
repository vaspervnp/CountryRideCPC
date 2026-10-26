"""The picture, worked out in Python.

This is the reference the Z80 code is checked against and the source the
generators take their data from:

  * the HUD art (labels, digits, gauges) - tools/mkgfx.py encodes it,
  * the sky and the mountains           - tools/mkgfx.py encodes them,
  * the road                             - tools/mkroad.py compiles it, and
    tools/run.py compares what the emulator shows with screen() here.

Everything works in pen numbers on a 192x272 grid of mode 0 pixels.
"""

import math
import os

from cpcgfx import (ROAD_TOP_MAX, PEN, SCR_W, SCR_H, HUD_H, SKY_Y, BLOCK_BOTTOM, ROAD_Y, ROWS,
                    ROAD_END, NEAR_ROW,
                    HORIZON_Y, road_shift, player_shift, curve_group,
                    far_mask,
                    ROAD_TOP_MIN, BANDS, GROUND_PEN, BAND_SHIFT, FAR_Z,
                    PLAIN_GRASS, grass_pen, TRACK_PERIOD, BUSH_SIZES, BUSH_LATS, BUSH_LAT_OF,
                    BUSH_H, BUSH_ASPECT, BUSH_ZNEAR, BUSH_ZFAR, BUSH_GAP,
                    BUSH_SEED, BUSH_BIG_GAP, BUSH_MAX, BUSH_IN_REACH, bush_row,
                    bush_sprite_of, bush_lat, bush_centre, bush_zvis,
                    m0_byte, m0_decode,
                    row_half_bytes, row_depth, road_row_pixels, pen_rgb)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------------------
# Fonts
# ---------------------------------------------------------------------------


def load_font(name):
    glyphs = {}
    cur = None
    for line in open(os.path.join(ROOT, "assets", name)):
        line = line.rstrip("\n")
        if line.startswith(";") or not line.strip():
            continue
        if line.startswith(":"):
            cur = line[1:]
            glyphs[cur] = []
            continue
        glyphs[cur].append(line)
    return glyphs


SMALL = load_font("font_small.txt")
BIG = load_font("font_big.txt")

SMALL_NAMES = {" ": "SPACE", '"': "QUOTE", "'": "APOS"}

HUD_BG = PEN["NAVY"]
SHADOW = PEN["BLACK"]
LABEL_PEN = PEN["YELLOW"]
VALUE_PEN = PEN["WHITE"]


def blank(w, h, pen=HUD_BG):
    return [[pen] * w for _ in range(h)]


def stamp(dst, x, y, src, transparent=None):
    for j, row in enumerate(src):
        for i, p in enumerate(row):
            if p is not transparent and 0 <= y + j < len(dst) \
                    and 0 <= x + i < len(dst[0]):
                dst[y + j][x + i] = p


def shadowed(mask_rows, pen, scale_y=1, bg=HUD_BG):
    """A glyph mask ('#'/'.') to pens, with a black shadow one pixel right
    and scale_y lines down. Returns rows (width+1) x (height*scale_y+scale_y)."""
    w = max(len(r) for r in mask_rows)
    h = len(mask_rows) * scale_y
    out = blank(w + 1, h + scale_y, bg)
    on = [[False] * w for _ in range(h)]
    for j, r in enumerate(mask_rows):
        for s in range(scale_y):
            for i, c in enumerate(r):
                if c == "#":
                    on[j * scale_y + s][i] = True
    for j in range(h):
        for i in range(w):
            if on[j][i]:
                out[j + scale_y][i + 1] = SHADOW
    for j in range(h):
        for i in range(w):
            if on[j][i]:
                out[j][i] = pen
    return out


def small_text(text, pen=LABEL_PEN):
    """A label: proportional glyphs, one pixel apart, shadowed."""
    rows = [""] * 7
    for ch in text:
        g = SMALL[SMALL_NAMES.get(ch, ch)]
        for j in range(7):
            rows[j] += g[j] + "."
    rows = [r[:-1] for r in rows]
    return shadowed(rows, pen)


def small_digit(d, pen=VALUE_PEN):
    """A digit in a fixed 3-byte (6 pixel) cell, 8 lines."""
    g = shadowed(SMALL[str(d)], pen)          # 5 wide, 8 tall
    cell = blank(6, 8)
    stamp(cell, 0, 0, g)
    return cell


def big_glyph(name, pen=VALUE_PEN):
    """A big glyph in a fixed 4-byte (8 pixel) cell, 18 lines."""
    g = shadowed(BIG[name], pen, scale_y=2)   # 7 wide, 18 tall
    cell = blank(8, 18)
    stamp(cell, 0, 0, g)
    return cell


# ---------------------------------------------------------------------------
# HUD layout: everything is placed on byte (2 pixel) boundaries.
# ---------------------------------------------------------------------------

GAUGE_SEGS = 8                   # segments per gauge, 4 pixels each
GAUGE_H = 6
GAUGE_ZONES = [PEN["RED"], PEN["ORANGE"], PEN["YELLOW"], PEN["GRASS_A"]]

HUD = dict(
    time_label=(8, 6), time_value=(8, 17),          # two big digits
    speed_label=(None, 6), speed_gauge=(80, 18), gear=(92, 31),
    total_label=(130, 6), total_value=(130, 17),    # m'ss"cc small digits
    fuel_label=(130, 31), fuel_gauge=(128, 42),
)


def gauge(level, reverse):
    """A segmented gauge, `level` segments lit of GAUGE_SEGS. Fuel runs red,
    orange, yellow, green from the left; speed the other way round."""
    out = blank(GAUGE_SEGS * 4, GAUGE_H)
    for s in range(GAUGE_SEGS):
        zone = s * 4 // GAUGE_SEGS
        pen = GAUGE_ZONES[3 - zone] if reverse else GAUGE_ZONES[zone]
        if s >= level:
            pen = PEN["BLACK"]
        for j in range(GAUGE_H):
            for i in range(3):
                out[j][s * 4 + i] = pen
    return out


def total_time_cells(centis):
    """m'ss"cc - returns [(x offset in pixels, pens)] for every character."""
    m = centis // 6000
    s = centis // 100 % 60
    c = centis % 100
    out = []
    x = 0
    for ch in "%d'%02d\"%02d" % (m, s, c):
        if ch.isdigit():
            out.append((x, small_digit(int(ch))))
            x += 6
        else:
            out.append((x, small_text(ch, VALUE_PEN)))
            x += 4 if ch == "'" else 6
    return out


def hud(time_left=60, speed_level=10, gear="4", total_centis=8345, fuel=13):
    out = blank(SCR_W, HUD_H)
    lab = small_text("TIME")
    stamp(out, *HUD["time_label"], lab)
    x, y = HUD["time_value"]
    stamp(out, x, y, big_glyph(str(time_left // 10)))
    stamp(out, x + 8, y, big_glyph(str(time_left % 10)))

    lab = small_text("SPEED")
    stamp(out, (SCR_W - len(lab[0])) // 2 // 2 * 2, HUD["speed_label"][1], lab)
    stamp(out, *HUD["speed_gauge"], gauge(speed_level, reverse=True))
    stamp(out, *HUD["gear"], big_glyph(gear))

    stamp(out, *HUD["total_label"], small_text("TOTAL TIME"))
    x, y = HUD["total_value"]
    for dx, cell in total_time_cells(total_centis):
        stamp(out, x + dx, y, cell)

    stamp(out, *HUD["fuel_label"], small_text("FUEL"))
    stamp(out, *HUD["fuel_gauge"], gauge(fuel, reverse=False))
    return out


# ---------------------------------------------------------------------------
# Sky: an ordered dither from the HUD colour down to the haze.
# ---------------------------------------------------------------------------

SKY_TOP = SKY_Y + 4         # the dither starts here: above it the sky part
SKY_STOPS = [  # (line, pen) - the gradient passes through these
    (SKY_TOP, PEN["NAVY"]),         # is plain navy, like the lines the
    (SKY_TOP + 5, PEN["BLUE"]),     # ruptures put above it
    (SKY_TOP + 13, PEN["SKY"]),
    (SKY_TOP + 24, PEN["PASTEL"]),
    (BLOCK_BOTTOM - 3, PEN["HAZE"]),
]
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def sky_pen(x, y):
    if y < SKY_STOPS[0][0]:
        return SKY_STOPS[0][1]
    for (y0, p0), (y1, p1) in zip(SKY_STOPS, SKY_STOPS[1:]):
        if y0 <= y < y1:
            t = (y - y0) / (y1 - y0)
            return p1 if BAYER[y % 4][x % 4] < t * 16 else p0
    return SKY_STOPS[-1][1]


# ---------------------------------------------------------------------------
# Mountains: two ranges, snowy, lit from the left. A 384 pixel panorama so
# the strip scrolls sideways with the road's heading; the screen shows 192
# pixels of it.
# ---------------------------------------------------------------------------

PANORAMA_W = 384


def _noise(width, seed, amp, period):
    """Periodic value noise: random points `period` pixels apart, joined by
    straight lines, so the panorama still tiles."""
    import random
    rnd = random.Random(seed)
    pts = [rnd.uniform(-amp, amp) for _ in range(width // period)]
    out = []
    for x in range(width):
        i, f = divmod(x, period)
        a, b = pts[i], pts[(i + 1) % len(pts)]
        out.append(a + (b - a) * f / period)
    return out


def _fractal(width, seed, amp):
    """Two octaves of value noise: broad undulation plus a finer crag."""
    a = _noise(width, seed, amp, 32)
    b = _noise(width, seed + 1, amp * 0.45, 8)
    return [p + q for p, q in zip(a, b)]


def _ridge(peaks, width, rough):
    """Height above BLOCK_BOTTOM per x, and which peak owns each x."""
    h = [0.0] * width
    owner = [-1] * width
    for k, (px, ph, slope_l, slope_r) in enumerate(peaks):
        for x in range(width):
            # distance with wrap-around so the panorama tiles
            d = (x - px + width // 2) % width - width // 2
            v = ph - (-d) * slope_l if d < 0 else ph - d * slope_r
            if v > h[x]:
                h[x] = v
                owner[x] = k
    for x in range(width):
        if h[x] > 0:
            h[x] += rough[x]
    return h, owner


# Drawn 44 lines high at most, then scaled down to MOUNT_H: heights, slopes
# and roughness alike, so the ranges keep their width.
MOUNT_H = 28
FAR_PEAKS = [(20, 24, 0.5, 0.55), (82, 30, 0.45, 0.42), (140, 22, 0.55, 0.5),
             (205, 28, 0.42, 0.5), (268, 25, 0.5, 0.48), (330, 31, 0.55, 0.45)]
NEAR_PEAKS = [(46, 38, 0.85, 1.0), (112, 28, 1.0, 0.75), (176, 44, 0.8, 1.0),
              (248, 33, 0.95, 0.85), (316, 41, 0.85, 0.9)]
_MS = MOUNT_H / max(ph for _, ph, _, _ in NEAR_PEAKS)
FAR_PEAKS = [(px, ph * _MS, sl * _MS, sr * _MS) for px, ph, sl, sr in FAR_PEAKS]
NEAR_PEAKS = [(px, ph * _MS, sl * _MS, sr * _MS) for px, ph, sl, sr in NEAR_PEAKS]

# Which pens the two ranges are painted in.
MOUNT_PENS = dict(far_lit=PEN["PASTEL"], far_dark=PEN["MAUVE"],
                  rock_lit=PEN["GREY"], rock_dark=PEN["NAVY"],
                  snow_lit=PEN["WHITE"], snow_dark=PEN["PASTEL"])


def _ranges():
    far_rough = _fractal(PANORAMA_W, 7, 3.0 * _MS)
    near_rough = _fractal(PANORAMA_W, 11, 4.0 * _MS)
    snow_rough = [a + b for a, b in zip(_noise(PANORAMA_W, 23, 4.0 * _MS, 32),
                                        _noise(PANORAMA_W, 29, 3.5 * _MS, 4))]
    ridge_rough = _fractal(PANORAMA_W, 31, 3.0 * _MS)
    hf, of = _ridge(FAR_PEAKS, PANORAMA_W, far_rough)
    hn, on = _ridge(NEAR_PEAKS, PANORAMA_W, near_rough)
    return hf, of, hn, on, snow_rough, ridge_rough


def mountains_top():
    """First line of the strip that has any mountain in it."""
    hf, _, hn, _, _, _ = _ranges()
    return BLOCK_BOTTOM - int(max(max(hf), max(hn))) - 2


def mountain_rows(pens=None):
    """The mountains alone, lines mountains_top()..BLOCK_BOTTOM-1 of the
    panorama: pens, None where the sky shows through."""
    mp = dict(MOUNT_PENS, **(pens or {}))
    top = mountains_top()
    hf, of, hn, on, snow_rough, ridge_rough = _ranges()
    rows = []
    for y in range(top, BLOCK_BOTTOM):
        up = BLOCK_BOTTOM - y               # height of this line above the base
        row = []
        for x in range(PANORAMA_W):
            pen = None
            # far range: lit and shadowed faces, no snow
            if up <= hf[x]:
                px, ph = FAR_PEAKS[of[x]][0], FAR_PEAKS[of[x]][1]
                d = (x - px + PANORAMA_W // 2) % PANORAMA_W - PANORAMA_W // 2
                ridge = (ph - up) * 0.3 + ridge_rough[(x + 50) % PANORAMA_W]
                pen = mp["far_lit"] if d < ridge else mp["far_dark"]
            # near range: rock with a snow cap; the ridge between the lit and
            # the shadowed face runs down and to the right of the summit
            if up <= hn[x]:
                k = on[x]
                px, ph = NEAR_PEAKS[k][0], NEAR_PEAKS[k][1]
                d = (x - px + PANORAMA_W // 2) % PANORAMA_W - PANORAMA_W // 2
                ridge = (ph - up) * 0.35 + ridge_rough[x]
                lit = d < ridge
                # snow streaks run down the gullies two pixels at a time
                snow_line = ph * 0.55 + snow_rough[x & ~1]
                if up >= snow_line:
                    pen = mp["snow_lit"] if lit else mp["snow_dark"]
                else:
                    pen = mp["rock_lit"] if lit else mp["rock_dark"]
            row.append(pen)
        rows.append(row)
    return top, rows


def horizon_panorama(pens=None):
    """Pens for lines mountains_top()..BLOCK_BOTTOM-1 of the panorama, the
    mountains over the sky."""
    top, rows = mountain_rows(pens)
    return top, [[sky_pen(x, top + s) if p is None else p
                  for x, p in enumerate(row)] for s, row in enumerate(rows)]


def ground_lines(hill):
    """Road lines at the top that no row reaches."""
    return sum(1 for r in project(hill) if r is None)


# ---------------------------------------------------------------------------
# Road: rows, hills, stripes.
# ---------------------------------------------------------------------------


def row_band(r, zcam):
    """0 or 1 for the striped rows; past FAR_Z 0 or 2 - band 2 is band A's
    grass and asphalt with band B's markings."""
    z = row_depth(r)
    on = (z + zcam) & far_mask(r)
    if z > FAR_Z:
        return 2 if on else 0
    return 1 if on else 0


def hill_offset(r, hill):
    """Screen offset of row r for hill strength `hill` (-128..127): h/r,
    rounded towards zero. Positive is a crest ahead: the far rows drop and
    are hidden behind it; negative lifts them."""
    q = abs(hill) // r
    return q if hill >= 0 else -q


HILL_LEVELS = 128                # the road engine has a table per even hill


def hill_level(hill):
    return (hill + 128) >> 1


def level_hill(level):
    return level * 2 - 128


def project(hill, zcam=0):
    """Which row each road line shows: list of (row or None) for lines
    ROAD_Y..ROAD_END-1, top to bottom. None means the distant ground.
    Rows are laid down nearest first; a row that lands on or below the top
    of what is already drawn is hidden behind it. (Deep in a dip a row past
    NEAR_ROW reaches the last line: NEAR_ROW stands in for it.)"""
    line_row = [None] * (ROAD_END - ROAD_Y)
    max_y = ROAD_END
    for r in range(ROWS, 0, -1):
        y = HORIZON_Y + r + hill_offset(r, hill)
        if y < ROAD_TOP_MIN:
            y = ROAD_TOP_MIN
        if y < max_y:
            for yy in range(y, max_y):
                line_row[yy - ROAD_Y] = min(r, NEAR_ROW)
            max_y = y
            if y == ROAD_TOP_MIN:
                break
    return line_row


HILL_MAX = max(h for h in range(0, 128, 2)
               if next(i for i, r in enumerate(project(h)) if r is not None)
               + ROAD_Y <= ROAD_TOP_MAX)


def road_line(r, band, cx=SCR_W // 2, grass=PLAIN_GRASS):
    """Pens of one road line showing row r (None = ground strip). The engine
    draws the road in whole pairs (4 pixels): the kerb fills them out."""
    if r is None:
        return [GROUND_PEN] * SCR_W
    out = [grass] * SCR_W
    pens, left = road_row_pixels(row_half_bytes(r), band)
    x0 = cx - left
    x1 = x0 + len(pens)
    for x in range(max(0, x0 & ~3), min(SCR_W, (x1 + 3) & ~3)):
        out[x] = pens[x - x0] if x0 <= x < x1 else pens[0]
    return out


def road_lines(hill, zcam, curve=0, x=0):
    """Lines ROAD_Y..SCR_H-1, the road bent by curve level `curve` and x
    pairs right of the middle (cpcgfx.road_shift), down to ROAD_END; black
    under it."""
    rows = project(hill, zcam)
    return [road_line(r, row_band(r, zcam), SCR_W // 2 + 2 * road_shift(curve, r, x),
                      grass_pen(r, zcam))
            if r else road_line(None, 0) for r in rows] + \
        [[PEN["BLACK"]] * SCR_W for _ in range(ROAD_END, SCR_H)]


# ---------------------------------------------------------------------------
# Bushes
# ---------------------------------------------------------------------------

# A bush is a few round clumps of leaves, in a box 2.4 wide and 1 high
# (square units), lit from the upper left like the mountains.
BUSH_CLUMPS = [(0.42, 0.62, 0.40), (0.95, 0.50, 0.50), (1.50, 0.55, 0.47),
               (1.98, 0.66, 0.36), (0.75, 0.30, 0.28), (1.30, 0.28, 0.27),
               (1.75, 0.38, 0.27)]
BUSH_LIGHT = (-0.5, -0.7, 0.5)
BUSH_PENS = dict(lit=PEN["GRASS_A"], body=PEN["BUSH"], dark=PEN["BLACK"])
# What fills a sprite's runs between its leaves and out to whole pairs: no
# grass, so that it looks the same on either of the grass's stripes.
BUSH_FILL = PEN["BUSH"]


def _leaf_noise(i, j, seed=3):
    """-1..1, fixed per leaf cell."""
    v = (i * 374761393 + j * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((v >> 8) & 0xFFFF) / 32767.5 - 1


def bush_art(h):
    """A bush `h` lines high: rows of pens, None where the grass shows."""
    w = max(2, int(BUSH_ASPECT * h + 0.5))
    lx, ly, lz = BUSH_LIGHT
    n = math.sqrt(lx * lx + ly * ly + lz * lz)
    lx, ly, lz = lx / n, ly / n, lz / n
    inside = [[None] * w for _ in range(h)]
    for j in range(h):
        v = (j + 0.5) / h
        for i in range(w):
            u = (i + 0.5) / w * 2.4
            best = None
            for cx, cy, r in BUSH_CLUMPS:
                d2 = (u - cx) ** 2 + (v - cy) ** 2
                if d2 <= r * r:
                    z = math.sqrt(r * r - d2)
                    if best is None or z > best[0]:
                        best = (z, (u - cx) / r, (v - cy) / r, z / r)
            inside[j][i] = best
    out = [[None] * w for _ in range(h)]
    for j in range(h):
        for i in range(w):
            b = inside[j][i]
            if b is None:
                continue
            _, nx, ny, nz = b
            lit = nx * lx + ny * ly + nz * lz
            lit += 0.35 * _leaf_noise(int(i / 1.5), j // 2)
            edge = any(not (0 <= j + dj < h and 0 <= i + di < w)
                       or inside[j + dj][i + di] is None
                       for di, dj in ((-1, 0), (1, 0), (0, -1), (0, 1)))
            if h >= 5 and j == h - 1:
                pen = BUSH_PENS["dark"]          # its shadow on the ground
            elif lit < 0.1:
                pen = BUSH_PENS["dark"]
            elif lit > 0.8 and not edge:
                pen = BUSH_PENS["lit"]
            else:
                pen = BUSH_PENS["body"]
            out[j][i] = pen
    return out


def bush_sprite(k):
    """Sprite k (BUSH_H[k] lines) as the engine draws it: (width in bytes,
    [(first byte, [bytes])] a line). Each line is one run of bytes from its
    first pixel of bush to its last, the gaps between filled in with
    BUSH_FILL, and a byte of it more where that makes it a whole number of
    pairs (the engine PUSHes them): on the left, or on the right at the
    sprite's left edge. The width is even, so that byte is always inside it."""
    art = bush_art(BUSH_H[k])
    w = len(art[0])
    wb = (w + 1) // 2
    wb += wb & 1
    lines = []
    for row in art:
        px = [i for i, p in enumerate(row) if p is not None]
        assert px, "a bush line with no bush in it"
        a, b = px[0] // 2, px[-1] // 2 + 1
        if (b - a) & 1:
            if a:
                a -= 1
            else:
                b += 1
        pens = [BUSH_FILL if p is None else p for p in row]
        pens += [BUSH_FILL] * (2 * wb - len(pens))
        lines.append((a, [m0_byte(pens[2 * x], pens[2 * x + 1]) for x in range(a, b)]))
    return wb, lines


BUSH_SPRITES = [bush_sprite(k) for k in range(len(BUSH_H))]


def bush_layout():
    """The bushes along the track, nearest first: (z, side, size, lateral),
    side -1 left or 1 right, at random gaps - pushed further on where that
    would make more than BUSH_IN_REACH bushes in reach at once (a bush is in
    reach from bush_zvis to BUSH_ZNEAR ahead)."""
    import random
    rnd = random.Random(BUSH_SEED)
    zvis = [bush_zvis(size) for size in range(len(BUSH_SIZES))]

    def reach(z, size):                 # the zcams it is in reach at
        return z - zvis[size] + 1, z - BUSH_ZNEAR

    def crowded(z, size, others):
        a, b = reach(z, size)
        spans = [(max(a, a2), min(b, b2)) for a2, b2 in
                 (reach(z2, s2) for z2, _, s2, _ in others)]
        spans = [(a2, b2) for a2, b2 in spans if a2 <= b2]
        return any(sum(1 for a3, b3 in spans if a3 <= a2 <= b3) >= BUSH_IN_REACH
                   for a2, b2 in spans)

    out = []
    z = rnd.randint(*BUSH_GAP)
    big = -BUSH_BIG_GAP
    while z < TRACK_PERIOD - BUSH_GAP[0]:
        size = rnd.randrange(len(BUSH_SIZES))
        if size == len(BUSH_SIZES) - 1:
            if z - big < BUSH_BIG_GAP:      # two of the biggest stay apart
                size -= 1
            else:
                big = z
        while crowded(z, size, out[-2 * BUSH_IN_REACH:]):
            z += 8
        lo, hi = BUSH_LAT_OF[size]
        out.append((z, rnd.choice((-1, 1)), size, rnd.randint(lo, hi)))
        z += rnd.randint(*BUSH_GAP)
    # where the track loops: the last ones against the first, a lap on
    while out and crowded(out[-1][0], out[-1][2],
                          out[-2 * BUSH_IN_REACH - 1:-1]
                          + [(z2 + TRACK_PERIOD, sd, s2, l2)
                             for z2, sd, s2, l2 in out[:2 * BUSH_IN_REACH]]):
        out.pop()
    return [b for b in out if b[0] < TRACK_PERIOD]


BUSHES = bush_layout()


def effective_hill(hill):
    """The hill the road engine draws: an even level, no stronger a crest
    than HILL_MAX lets the road's top go."""
    return min(level_hill(hill_level(hill)), HILL_MAX)


def bush_items(hill, zcam, curve, x=0):
    """The bushes on screen, in the order they are drawn - nearest first,
    BUSH_MAX at most (they hardly ever overlap): (sprite, left byte, base
    line, inside of the curve). `hill` as the road engine draws it. A bush
    going off a side of the screen is drawn until its centre goes."""
    rows = project(hill)
    top = next(r for r in rows if r)         # the furthest row in sight
    out = []
    for z, side, size, lat in BUSHES:
        zr = (z - zcam) % TRACK_PERIOD
        r = bush_row(zr)
        if not r or r < top:
            continue
        q = abs(hill) // r
        y = HORIZON_Y + r + (q if hill >= 0 else -q)
        if y < ROAD_Y:
            continue
        k = bush_sprite_of(size, r)
        if k is None:
            continue
        wb = BUSH_SPRITES[k][0]
        # drawn while its centre is on the screen (as the engine works it
        # out, in bytes: the offset at most 127)
        cx = (bush_centre(curve, r) + player_shift(curve, x, r)
              + side * min(bush_lat(lat, r), 127))
        if not 0 <= cx < SCR_W // 2:
            continue
        bx = cx - wb // 2
        out.append((zr, k, bx, y, side * curve > 0))
    out.sort(key=lambda t: t[0])
    return [t[1:] for t in out[:BUSH_MAX]]


def draw_bushes(lines, y0, hill, zcam, curve, x=0):
    """Draw the bushes into `lines` (pen rows, the first being line y0)."""
    for k, bx, y, _ in bush_items(hill, zcam, curve, x):
        wb, spans = BUSH_SPRITES[k]
        top = y - len(spans) + 1
        for j, (a, data) in enumerate(spans):
            yy = top + j
            if yy < max(y0, ROAD_AREA_Y):
                continue
            for i, b in enumerate(data):
                x = bx + a + i
                if 0 <= x < SCR_W // 2:
                    lines[yy - y0][2 * x:2 * x + 2] = list(m0_decode(b))


# ---------------------------------------------------------------------------
# The player's car: a low, wide red sports car seen from behind - a rear
# wing over a small rear window between buttresses, a black grille across
# the back with the lights behind its slats, the plate on a dark band, fat
# tyres - fixed in the middle of the screen a little above the bottom (the
# monitor's edge can hide the last lines) - the road moves under it.
# Steering, it is seen turning, its nose that way: turning left, the
# rear face a little narrower and its left flank in view. The views are
# renders of a 3D model (tools/car3d.py, in Blender) made into rows of
# pens by tools/mkcar.py: tools/carart.py. Each line is one run of whole
# pairs (4 pixels), like a bush's, so the engine draws it with PUSHes; it
# is drawn last, over the road and the bushes. The road under it is drawn
# afresh with every picture (or left as it was, car and all, when
# road_project skips the line), so it needs no erasing. The grey at the
# ends of a run is the asphalt's, rounding it out to whole pairs.
# ---------------------------------------------------------------------------

from carart import CAR_ART, CAR_ART_LEFT  # noqa: E402

CAR_W = len(CAR_ART[0])         # pixels: the same either side of the middle
CAR_X = (SCR_W - CAR_W) // 2
CAR_BOTTOM = SCR_H - 12         # the line below it
CAR_PEN = dict(R="RED", O="ORANGE", Y="YELLOW", K="BLACK", G="GREY",
               W="WHITE", N="NAVY", S="SKY", D="CAR_DARK")
CAR_H = len(CAR_ART)
CAR_Y = CAR_BOTTOM - CAR_H      # its top line
CAR_ART_RIGHT = [r[::-1] for r in CAR_ART_LEFT]
CAR_ARTS = [CAR_ART, CAR_ART_LEFT, CAR_ART_RIGHT]   # car_view 0, 1, 2
assert CAR_W % 4 == 0 and CAR_X % 2 == 0
assert all(len(a) == CAR_H and all(len(r) == CAR_W for r in a) for a in CAR_ARTS)


def car_runs(view=0):
    """The car's lines as a bush sprite's: (first byte from the car's left,
    the bytes of its run) - (0, []) for a line the view leaves empty."""
    out = []
    for row in CAR_ARTS[view]:
        if not row.strip("."):
            out.append((0, []))
            continue
        a = min(i for i, c in enumerate(row) if c != ".")
        b = max(i for i, c in enumerate(row) if c != ".") + 1
        assert a % 4 == 0 and b % 4 == 0 and "." not in row[a:b]
        pens = [PEN[CAR_PEN[c]] for c in row[a:b]]
        out.append((a // 2, [m0_byte(pens[i], pens[i + 1]) for i in range(0, len(pens), 2)]))
    return out


def draw_car(lines, y0, view=0, off=0):
    """Draw the car into `lines` (pen rows, the first being line y0), seen
    straight, turning left or turning right (view 0, 1, 2), `off` pairs right
    of the middle (the game's car_off)."""
    for j, row in enumerate(CAR_ARTS[view]):
        for i, c in enumerate(row):
            if c != ".":
                lines[CAR_Y + j - y0][CAR_X + 4 * off + i] = PEN[CAR_PEN[c]]


# ---------------------------------------------------------------------------
# The whole screen
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# The picture is made of three parts, each in its own memory, which the CRTC
# shows one after the other (raster ruptures, see hw.asm):
#
#   the HUD     lines 0..63, one copy per screen buffer;
#   the sky     the sky and the mountains, lines HUD_H..BLOCK_BOTTOM-1 when
#               nothing has moved: one copy for both buffers, kept in a ring
#               the CRTC can scroll sideways a word (4 pixels) at a time;
#   the road    lines ROAD_AREA_Y..271 (a band of ground, then the road),
#               one copy per buffer.
#
# The horizon drops with the road: for a drop of d lines the sky part starts
# d lines lower, under d lines of border in the HUD's navy, and is followed by
# border in the ground's green down to the character row where the road
# part starts - the row the top of the road is in - so the ground between
# the mountains and the road always has ROAD_Y - BLOCK_BOTTOM lines.
# ---------------------------------------------------------------------------

ROAD_AREA_Y = 160               # the road part's memory starts with line 160
BORDER_TOP = HUD_BG             # border colour above the sky ...
BORDER_LOW = GROUND_PEN         # ... and below the mountains
PANO_WORDS = PANORAMA_W // 4    # the panorama in CRTC words (4 pixels)


def pano_y0():
    """First line of the sky part that has mountains in its character row
    (the part's rows start at SKY_Y): above it every line is one dither
    pair repeated."""
    return SKY_Y + (mountains_top() - SKY_Y) // 8 * 8


def sky_lines(heading=0):
    """The sky part, lines SKY_Y..BLOCK_BOTTOM-1, looking `heading` words
    to the right. The dithered sky repeats every word, so only the mountains
    move."""
    top, pano = horizon_panorama()
    out = []
    for y in range(SKY_Y, BLOCK_BOTTOM):
        if y < top:
            out.append([sky_pen(x, y) for x in range(SCR_W)])
        else:
            row = pano[y - top]
            out.append([row[(x + 4 * heading) % PANORAMA_W] for x in range(SCR_W)])
    return out


def road_area(hill=0, zcam=0, curve=0, bushes=True, x=0, car=True, view=0,
              car_off=0):
    """The road part: lines ROAD_AREA_Y..SCR_H-1, ground then the road, the
    bushes and the car (seen as car_view `view`, car_off pairs right of the
    middle). `hill` as the road engine draws it (effective_hill)."""
    lines = ([[GROUND_PEN] * SCR_W for _ in range(ROAD_AREA_Y, ROAD_Y)]
             + road_lines(hill, zcam, curve, x))
    if bushes:
        draw_bushes(lines, ROAD_AREA_Y, hill, zcam, curve, x)
    if car:
        draw_car(lines, ROAD_AREA_Y, view, car_off)
    return lines


def ground_drop(hill):
    """How far the horizon is down for a hill: the road's ground lines."""
    return ground_lines(hill)


def road_from(drop):
    """First line of the road part on the screen: the character row with the
    top of the road in it."""
    return (ROAD_Y + drop) // 8 * 8


def sky_drop(drop):
    """How far the sky and the mountains go down for a road drop: twice as
    far, so that the ground between them and the road's top - a crest's far
    side, that the crest hides - narrows, but no further than the line
    before the road part starts (its first line is a character row's), and
    never more than 2 lines on from the drop before - from 11 lines of
    ground on the flat to 3-7 on a crest."""
    s = 0
    for k in range(1, drop + 1):
        s = min(s + 2, road_from(k) - BLOCK_BOTTOM)
    return s


def shown(hud_pens, sky, road, drop):
    """What the CRTC shows: the three parts, split for a drop."""
    out = []
    first_road = road_from(drop)
    sd = sky_drop(drop)
    for y in range(SCR_H):
        if y < HUD_H:
            out.append(hud_pens[y])
        elif y < SKY_Y + sd:
            out.append([BORDER_TOP] * SCR_W)
        elif y < BLOCK_BOTTOM + sd:
            out.append(sky[y - sd - SKY_Y])
        elif y < first_road:
            out.append([BORDER_LOW] * SCR_W)
        else:
            out.append(road[y - ROAD_AREA_Y])
    return out


def screen(hill=0, zcam=0, drop=None, heading=0, curve=0, x=0, **hudvals):
    """The picture on the screen: the horizon `drop` lines down (by default
    as far as the road's ground goes), looking `heading` words right, the
    road bent by curve level `curve`."""
    if drop is None:
        drop = ground_drop(hill)
    return shown(hud(**hudvals), sky_lines(heading),
                 road_area(effective_hill(hill), zcam, curve, x=x), drop)


def to_image(pens, scale=True):
    from PIL import Image
    h = len(pens)
    w = len(pens[0])
    img = Image.new("RGB", (w, h))
    img.putdata([pen_rgb(p) for row in pens for p in row])
    if scale:
        img = img.resize((w * 4, h * 2), Image.NEAREST)
    return img


if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build",
                                                             "mockup.png")
    hill = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    zcam = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    to_image(screen(hill, zcam)).save(out)
    print("wrote", out)
