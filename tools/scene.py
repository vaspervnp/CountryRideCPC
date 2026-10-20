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

from cpcgfx import (PEN, SCR_W, SCR_H, HUD_H, BLOCK_BOTTOM, ROAD_Y, ROWS,
                    HORIZON_Y,
                    far_mask,
                    ROAD_TOP_MIN, BANDS, GROUND_PEN, BAND_SHIFT, FAR_Z,
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
GAUGE_ZONES = [PEN["RED"], PEN["ORANGE"], PEN["YELLOW"], PEN["GREEN"]]

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

SKY_STOPS = [  # (line, pen) - the gradient passes through these. The first
    (HUD_H + 8, PEN["NAVY"]),       # character row is plain navy, like the
    (HUD_H + 22, PEN["BLUE"]),      # lines the ruptures put above it
    (HUD_H + 40, PEN["SKY"]),
    (HUD_H + 64, PEN["PASTEL"]),
    (BLOCK_BOTTOM - 4, PEN["HAZE"]),
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
# the strip can scroll later; the screen shows pixels 0..191 of it.
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


FAR_PEAKS = [(20, 24, 0.5, 0.55), (82, 30, 0.45, 0.42), (140, 22, 0.55, 0.5),
             (205, 28, 0.42, 0.5), (268, 25, 0.5, 0.48), (330, 31, 0.55, 0.45)]
NEAR_PEAKS = [(46, 38, 0.85, 1.0), (112, 28, 1.0, 0.75), (176, 44, 0.8, 1.0),
              (248, 33, 0.95, 0.85), (316, 41, 0.85, 0.9)]

# Which pens the two ranges are painted in.
MOUNT_PENS = dict(far_lit=PEN["PASTEL"], far_dark=PEN["MAUVE"],
                  rock_lit=PEN["GREY"], rock_dark=PEN["NAVY"],
                  snow_lit=PEN["WHITE"], snow_dark=PEN["PASTEL"])


def _ranges():
    far_rough = _fractal(PANORAMA_W, 7, 3.0)
    near_rough = _fractal(PANORAMA_W, 11, 4.0)
    snow_rough = [a + b for a, b in zip(_noise(PANORAMA_W, 23, 4.0, 32),
                                        _noise(PANORAMA_W, 29, 3.5, 4))]
    ridge_rough = _fractal(PANORAMA_W, 31, 3.0)
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
    ROAD_Y..SCR_H-1, top to bottom. None means the distant ground.
    Rows are laid down nearest first; a row that lands on or below the top
    of what is already drawn is hidden behind it."""
    line_row = [None] * (SCR_H - ROAD_Y)
    max_y = SCR_H
    for r in range(ROWS, 0, -1):
        y = HORIZON_Y + r + hill_offset(r, hill)
        if y < ROAD_TOP_MIN:
            y = ROAD_TOP_MIN
        if y < max_y:
            for yy in range(y, max_y):
                line_row[yy - ROAD_Y] = r
            max_y = y
            if y == ROAD_TOP_MIN:
                break
    return line_row


def road_line(r, band, cx=SCR_W // 2):
    """Pens of one road line showing row r (None = ground strip)."""
    if r is None:
        return [GROUND_PEN] * SCR_W
    b = BANDS[band]
    out = [b["grass"]] * SCR_W
    pens, left = road_row_pixels(row_half_bytes(r), band)
    for i, p in enumerate(pens):
        x = cx - left + i
        if 0 <= x < SCR_W:
            out[x] = p
    return out


def road_lines(hill, zcam):
    """Lines ROAD_Y..SCR_H-1."""
    rows = project(hill, zcam)
    return [road_line(r, row_band(r, zcam) if r else 0) for r in rows]


# ---------------------------------------------------------------------------
# The whole screen
# ---------------------------------------------------------------------------


def memory(hill=0, zcam=0, **hudvals):
    """The picture as it is in a screen buffer: HUD, sky and mountains,
    the ground band, the road."""
    pens = hud(**hudvals)
    top, pano = horizon_panorama()
    for y in range(HUD_H, BLOCK_BOTTOM):
        if y < top:
            pens.append([sky_pen(x, y) for x in range(SCR_W)])
        else:
            pens.append(pano[y - top][:SCR_W])
    pens += [[GROUND_PEN] * SCR_W for _ in range(BLOCK_BOTTOM, ROAD_Y)]
    pens += road_lines(hill, zcam)
    assert len(pens) == SCR_H
    return pens


# ---------------------------------------------------------------------------
# The horizon drops with the road. The screen is split by raster ruptures
# into three: the HUD, the sky and mountains (lines HUD_H..BLOCK_BOTTOM-1 of
# the buffer), and the road from a character row on (BLOCK_BOTTOM + 8q). To
# move the sky and mountains down by `drop` lines, the HUD part gets `drop`
# more lines, in the border colour - the HUD's navy - and the sky and
# mountains part gets the lines that bring the road back onto a character
# row, in the ground colour. With the drop equal to the road's ground, the
# band of ground between the mountains and the road always has
# ROAD_Y - BLOCK_BOTTOM lines.
# ---------------------------------------------------------------------------

BORDER_TOP = HUD_BG             # border colour above the sky ...
BORDER_LOW = GROUND_PEN         # ... and below the mountains


def ground_drop(hill):
    """How far the horizon is down for a hill: the road's ground lines."""
    return ground_lines(hill)


def rupture_rows(drop):
    """(lines in the HUD part, lines in the sky part, first road line) for
    a drop."""
    q = (drop + 7) // 8
    return HUD_H + drop, BLOCK_BOTTOM - HUD_H + 8 * q - drop, BLOCK_BOTTOM + 8 * q


def shown(mem, drop):
    """What the CRTC shows of a buffer for a drop."""
    hud_end, sky_lines, road_from = rupture_rows(drop)
    out = []
    for y in range(SCR_H):
        if y < HUD_H:
            out.append(mem[y])
        elif y < hud_end:
            out.append([BORDER_TOP] * SCR_W)
        elif y < BLOCK_BOTTOM + drop:
            out.append(mem[y - drop])
        elif y < road_from:
            out.append([BORDER_LOW] * SCR_W)
        else:
            out.append(mem[y])
    return out


def screen(hill=0, zcam=0, drop=None, **hudvals):
    """The picture on the screen, the horizon down by `drop` lines (by
    default as far as the road's ground goes)."""
    if drop is None:
        drop = ground_drop(hill)
    return shown(memory(hill, zcam, **hudvals), drop)


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
