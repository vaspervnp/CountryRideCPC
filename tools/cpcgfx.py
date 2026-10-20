"""Shared Amstrad CPC graphics helpers and the game's design constants.

Every generator in tools/ imports this module, so the palette, the screen
geometry and the road shape are defined exactly once. tools/mkconsts.py writes
the same numbers out as src/gen/consts.asm for the Z80 side.
"""

# ---------------------------------------------------------------------------
# Hardware
# ---------------------------------------------------------------------------

# Firmware colour number -> (hardware colour number, RGB). The hardware number
# is what the Gate Array wants (written as #40 + n).
FIRMWARE = {
    0: (20, (0, 0, 0)),          # black
    1: (4, (0, 0, 128)),         # blue
    2: (21, (0, 0, 255)),        # bright blue
    3: (28, (128, 0, 0)),        # red
    4: (24, (128, 0, 128)),      # magenta
    5: (29, (128, 0, 255)),      # mauve
    6: (12, (255, 0, 0)),        # bright red
    7: (5, (255, 0, 128)),       # purple
    8: (13, (255, 0, 255)),      # bright magenta
    9: (22, (0, 128, 0)),        # green
    10: (6, (0, 128, 128)),      # cyan
    11: (23, (0, 128, 255)),     # sky blue
    12: (30, (128, 128, 0)),     # yellow
    13: (0, (128, 128, 128)),    # white (grey)
    14: (31, (128, 128, 255)),   # pastel blue
    15: (14, (255, 128, 0)),     # orange
    16: (7, (255, 128, 128)),    # pink
    17: (15, (255, 128, 255)),   # pastel magenta
    18: (18, (0, 255, 0)),       # bright green
    19: (2, (0, 255, 128)),      # sea green
    20: (19, (0, 255, 255)),     # bright cyan
    21: (26, (128, 255, 0)),     # lime
    22: (25, (128, 255, 128)),   # pastel green
    23: (27, (128, 255, 255)),   # pastel cyan
    24: (10, (255, 255, 0)),     # bright yellow
    25: (3, (255, 255, 128)),    # pastel yellow
    26: (11, (255, 255, 255)),   # bright white
}

# ---------------------------------------------------------------------------
# The sixteen pens (mode 0). Names are used by every generator.
# ---------------------------------------------------------------------------

PENS = [
    # name          firmware colour
    ("BLACK",       0),    # 0  text shadow, empty gauge cells
    ("NAVY",        1),    # 1  HUD background = top of the sky
    ("BLUE",        2),    # 2  sky
    ("SKY",         11),   # 3  sky, rock in shadow
    ("PASTEL",      14),   # 4  sky near the horizon, snow in shadow
    ("HAZE",        23),   # 5  haze at the foot of the mountains
    ("WHITE",       26),   # 6  snow, HUD values, kerb (band B), lane lines
    ("GREY",        13),   # 7  rock, asphalt (band A)
    ("GRASS_A",     18),   # 8  verge (band A), distant ground strip
    ("GRASS_B",     21),   # 9  verge (band B): lime, close to the green
    ("RED",         6),    # 10 kerb (band A), gauge
    ("ORANGE",      15),   # 11 gauge
    ("YELLOW",      24),   # 12 HUD labels, gauge
    ("GREEN",       18),   # 13 gauge
    ("ASPHALT_B",   14),   # 14 asphalt (band B): pastel blue, close to grey
    ("MAUVE",       5),    # 15 distant rock
]
PEN = {name: i for i, (name, _) in enumerate(PENS)}
BORDER_FW = 0


def pen_rgb(pen):
    return FIRMWARE[PENS[pen][1]][1]


def pen_hw(pen):
    return FIRMWARE[PENS[pen][1]][0]


# Mode 0: two pixels per byte. Left pixel bits 7,3,5,1 hold pen bits 0,1,2,3;
# right pixel bits 6,2,4,0.
def m0_left(pen):
    return (((pen >> 0) & 1) << 7) | (((pen >> 1) & 1) << 3) | \
           (((pen >> 2) & 1) << 5) | (((pen >> 3) & 1) << 1)


def m0_right(pen):
    return m0_left(pen) >> 1


def m0_byte(left, right):
    return m0_left(left) | m0_right(right)


def m0_solid(pen):
    return m0_byte(pen, pen)


def m0_decode(b):
    left = ((b >> 7) & 1) | (((b >> 3) & 1) << 1) | (((b >> 5) & 1) << 2) | \
           (((b >> 1) & 1) << 3)
    right = ((b >> 6) & 1) | (((b >> 2) & 1) << 1) | (((b >> 4) & 1) << 2) | \
            (((b >> 0) & 1) << 3)
    return left, right


# ---------------------------------------------------------------------------
# Screen geometry: 96 bytes (192 mode 0 pixels) by 272 scanlines.
# ---------------------------------------------------------------------------

SCR_W = 192                 # pixels
SCR_BYTES = 96
SCR_H = 272
TOP_ROWS = 20               # character rows held in the first 16K page

# As drawn in memory (the screen is split by raster ruptures - see hw.asm -
# which moves the sky and the mountains down with the road):
HUD_H = 64                  # lines 0..63: the HUD on its single-colour ground
BLOCK_BOTTOM = 152          # lines 64..151: the sky and the mountains, 11 rows
ROAD_Y = 163                # lines 152..162: ground; 163..271: the road area
ROAD_TOP_MIN = 163          # road 2/5 of the screen at most ...
ROAD_TOP_MAX = 181          # ... and 1/3 at least
ROAD_LINES = SCR_H - ROAD_Y         # 109 scanlines redrawn every frame

# ---------------------------------------------------------------------------
# The road.
#
# Flat road: screen line y (163..271) shows row r = y - 162, so r runs from
# 1 (furthest) to 109 (nearest). A row's half-width grows linearly with r.
# Hills move rows up and down the screen; see src/road.asm.
# ---------------------------------------------------------------------------

ROWS = ROAD_LINES           # 109 rows
HORIZON_Y = ROAD_Y - 1      # row r sits on line HORIZON_Y + r when flat

LANES = 4
LANE_W_BOTTOM = 50          # pixels per lane on the bottom line (car is 45)
KERB_BOTTOM = 16            # kerb width on the bottom line, pixels
LINE_BOTTOM = 3             # lane line width on the bottom line, pixels
MIN_LINE_ROW = 10           # rows further away than this have no lane lines

# Asphalt half-width in bytes is the variant index of a row: MIN_HALF..HALF_MAX.
HALF_MAX = LANES * LANE_W_BOTTOM // 4      # 50 bytes = 100 pixels
MIN_HALF = 2                # the road never narrows to a point: 8 pixels of
                            # asphalt and two 1-pixel kerbs, 10 pixels at least


def row_half_bytes(r):
    """Asphalt half-width of row r, in bytes (the road is centred on a byte
    boundary, so a half-width in bytes keeps it symmetric)."""
    return max(MIN_HALF, (HALF_MAX * r + ROWS // 2) // ROWS)


def kerb_px(half):
    """Kerb width in pixels for a road of `half` bytes of asphalt."""
    if half == 0:
        return 1
    return max(1, (KERB_BOTTOM * half + HALF_MAX // 2) // HALF_MAX)


def line_px(half):
    if half < row_half_bytes(MIN_LINE_ROW):
        return 0
    return max(1, (LINE_BOTTOM * half + HALF_MAX // 2) // HALF_MAX)


# Depth of a row: z = DEPTH_K / r. 16 bits; the near row is z ~= 71.
DEPTH_K = 7760
BAND_SHIFT = 4              # a stripe band is 16 depth units long
FAR_Z = 360                 # beyond this the stripes stop (they would alias)


def far_mask(r):
    """Past FAR_Z the grass and the asphalt stop striping, but the kerbs and
    the lane dashes keep moving - with longer dashes the further away they
    are, so a dash still covers a row or two instead of flickering. The
    mask is the bit of (depth + camera) that says which half of the dash the
    row is in: 16 near (the stripes' own), 32, 64 or 128 far away."""
    if row_depth(r) <= FAR_Z:
        return 16
    if r >= 18:
        return 32
    if r >= 13:
        return 64
    return 128


def row_depth(r):
    return (DEPTH_K + r // 2) // r


# ---------------------------------------------------------------------------
# Curves. The road bends as a whole: at curve level k (-CURVE_K..CURVE_K,
# positive to the right) row r moves sideways by a parabola in rows - not at
# all at the bottom, where the car is, most at the horizon, CURVE_TOP bytes
# (2 pixels each) at the strongest level. The road engine has its templates
# made for every level, so a curve costs it nothing per line.
#
# The engine keeps one template per *group* of rows: a row of its own where
# the road is narrow (far away, where the bend moves most from row to row),
# else all the rows of one width. A group moves as its middle row would.
# ---------------------------------------------------------------------------

CURVE_K = 7
CURVE_TOP = 64
CURVE_ROW_GROUPS = 4        # rows narrower than this half-width: one group each


def curve_group(r):
    """The template group of row r: ('row', r) or ('half', half-width)."""
    h = row_half_bytes(r)
    return ("row", r) if h < CURVE_ROW_GROUPS else ("half", h)


def _group_mid(g):
    if g[0] == "row":
        return g[1]
    rows = [r for r in range(1, ROWS + 1) if row_half_bytes(r) == g[1]]
    return (rows[0] + rows[-1]) / 2


def curve_shift(k, r):
    """Bytes to the right that row r moves at curve level k."""
    t = (ROWS - _group_mid(curve_group(r))) / (ROWS - 1)
    v = abs(k) * CURVE_TOP * t * t / CURVE_K
    v = int(v + 0.5)
    return v if k >= 0 else -v


# ---------------------------------------------------------------------------
# Colours per stripe band. Band 0 = A, band 1 = B.
# ---------------------------------------------------------------------------

BANDS = [
    dict(grass=PEN["GRASS_A"], kerb=PEN["RED"], road=PEN["GREY"],
         line=PEN["WHITE"]),
    dict(grass=PEN["GRASS_B"], kerb=PEN["WHITE"], road=PEN["ASPHALT_B"],
         line=None),                       # dashed: no lane lines on band B
    # far away: the grass and the asphalt of band A, the kerb and the (absent)
    # lane line of band B - the markings move on where the stripes stop
    dict(grass=PEN["GRASS_A"], kerb=PEN["WHITE"], road=PEN["GREY"],
         line=None),
]
GROUND_PEN = PEN["GRASS_A"]                # the strip between hills and peaks


def road_row_pixels(half, band, lanes=LANES):
    """The road of one row as pixel pens, centred: returns (pens, left_px)
    where pens covers the kerbs and the asphalt and left_px is how many
    pixels lie left of the centre (the core is symmetric about the centre)."""
    b = BANDS[band]
    hw = half * 2                         # asphalt half-width in pixels
    kw = kerb_px(half)
    lw = line_px(half) if b["line"] is not None else 0
    total = hw + kw                       # pixels each side of the centre
    pens = [b["road"]] * (2 * total)
    for i in range(kw):
        pens[i] = b["kerb"]
        pens[2 * total - 1 - i] = b["kerb"]
    if lw:
        # lane lines at -hw + k*2hw/lanes for k = 1..lanes-1, centred
        for k in range(1, lanes):
            c = total - hw + (2 * hw * k) // lanes   # pixel index of line centre
            start = c - lw // 2
            for i in range(start, start + lw):
                if kw <= i < 2 * total - kw:
                    pens[i] = b["line"]
    return pens, total
