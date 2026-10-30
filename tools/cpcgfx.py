"""Shared Amstrad CPC graphics helpers and the game's design constants.

Every generator in tools/ imports this module, so the palette, the screen
geometry and the road shape are defined exactly once. tools/mkconsts.py writes
the same numbers out as src/gen/consts.asm for the Z80 side.
"""

from functools import lru_cache

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
    ("GREY",        13),   # 7  rock, asphalt
    ("GRASS_A",     18),   # 8  the grass, distant ground strip
    ("BUSH",        9),    # 9  bushes: dark green
    ("RED",         6),    # 10 kerb (band A), gauge
    ("ORANGE",      15),   # 11 gauge
    ("YELLOW",      24),   # 12 HUD labels, gauge
    ("GRASS_B",     21),   # 13 the grass's other stripe: lime
    ("CAR_DARK",    3),    # 14 the car's shading: dark red
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
# which moves the sky and the mountains down with the road). The sky, the
# mountains and the road take the screen's bottom half; above them is the
# HUD's navy:
HUD_H = 64                  # lines 0..63: the HUD on its single-colour ground
SKY_Y = 132                 # lines 64..131: navy; 132..179: the sky part, 6
BLOCK_BOTTOM = 180          # rows - navy, the dither from 136, the mountains
ROAD_Y = 188                # lines 180..187: ground; 188..267: the road area
ROAD_TOP_MIN = 188          # road 3/10 of the screen at most ...
ROAD_TOP_MAX = 202          # ... and 1/4 at least
ROAD_END = 268              # the road stops here: lines 268..271 stay black
                            # (a monitor's edge hides them anyway)
ROAD_LINES = ROAD_END - ROAD_Y      # 80 scanlines redrawn every frame

# ---------------------------------------------------------------------------
# The road.
#
# Flat road: screen line y (188..267) shows row r = y - 187, so r runs from
# 1 (furthest) to 80 (nearest). A row's half-width grows linearly with r.
# Hills move rows up and down the screen; see src/road.asm. The road's
# shape is laid out over rows 1..ROWS, as if it went on to the screen's
# last line; the last rows drawn are NEAR_ROW's.
# ---------------------------------------------------------------------------

ROWS = SCR_H - ROAD_Y       # 84 rows: the road's shape
NEAR_ROW = ROAD_LINES       # 80: the nearest row drawn
HORIZON_Y = ROAD_Y - 1      # row r sits on line HORIZON_Y + r when flat

LANES = 4
LANE_W_BOTTOM = 50          # pixels per lane on the bottom line (car is 45)
KERB_BOTTOM = 16            # kerb width on the bottom line, pixels
LINE_BOTTOM = 3             # lane line width on the bottom line, pixels
MIN_LINE_ROW = 8            # rows further away than this have no lane lines

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


# Depth of a row: z = DEPTH_K / r. 16 bits; the near row is z ~= 71, as
# with the horizon higher (105 lines of road, DEPTH_K 7760): a depth is as
# far from the car, and a stripe as long, as then.
DEPTH_K = 5980
BAND_SHIFT = 6              # a stripe band is 64 depth units long
FAR_Z = 660                 # beyond this the stripes stop (they would alias:
                            # the rows are about a stripe apart - z * z /
                            # DEPTH_K - and a group of rows is all past it or
                            # none of it: rows 1-9)


def far_mask(r):
    """Past FAR_Z the grass and the asphalt stop striping, but the kerbs and
    the lane dashes keep moving - with a longer dash, so that it still
    covers a row or two instead of flickering. The mask is the bit of
    (depth + camera) that says which half of the dash the row is in: 64
    near (the stripes' own), 128 far away."""
    if row_depth(r) <= FAR_Z:
        return 1 << BAND_SHIFT
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
# The engine keeps one template per *group* of rows: two rows (or one) where
# the road is narrow (far away, where the bend moves most from row to row),
# else all the rows of one width. A group moves as its middle row would.
#
# Where a group goes is worked out as a whole number of bytes from an exact
# sum (road_shift): the curve - curve_c1, kept in 1/50 bytes - and the
# player's share. It is rounded once, so the edges never step back and
# forth from group to group, and with a slight bias that keeps the lane
# lines straight too (road_shift).
# ---------------------------------------------------------------------------

CURVE_K = 7
CURVE_TOP = 64
CURVE_ROW_GROUPS = 4        # rows narrower than this half-width: two a group


def curve_group(r):
    """The template group of row r: ('rows', half-width, r // 2) or ('half',
    half-width)."""
    h = row_half_bytes(r)
    return ("rows", h, r // 2) if h < CURVE_ROW_GROUPS else ("half", h)


@lru_cache(maxsize=None)
def _group_mid(g):
    rows = [r for r in range(1, ROWS + 1) if curve_group(r) == g]
    return (rows[0] + rows[-1]) / 2


@lru_cache(maxsize=None)
def _row_c1(r):
    t = (ROWS - _group_mid(curve_group(r))) / (ROWS - 1)
    return int(256 * CURVE_TOP * t * t / CURVE_K + 0.5)


def curve_c1(r):
    """How far curve level 1 moves row r's group right, in 1/256 bytes (level
    k: k times as far)."""
    return _row_c1(r)


@lru_cache(maxsize=None)
def curve_d(r):
    """How fast that changes from one half-width to the next about row r's
    group, in 1/512 bytes: c1 of the half-width one more less c1 of the one
    less (twice a one-sided step at either end) - never more than 0. 0 where
    the groups are rows two at a time."""
    h = row_half_bytes(r)
    if h < CURVE_ROW_GROUPS:
        return 0
    rs = range(1, ROWS + 1)
    lo = [q for q in rs if row_half_bytes(q) == h - 1]
    hi = [q for q in rs if row_half_bytes(q) == h + 1]
    if not lo:
        return 2 * (_row_c1(hi[0]) - _row_c1(r))
    if not hi:
        return 2 * (_row_c1(r) - _row_c1(lo[-1]))
    return _row_c1(hi[0]) - _row_c1(lo[-1])


# ---------------------------------------------------------------------------
# The player. The car stays in the middle of the screen and the road moves
# under it, in perspective: road_x pairs (4 pixels) of it moves a row of
# half-width h right by x * PERSP_P * h / 256 bytes - the bottom row a
# little less than x pairs (500/256 bytes a pair), the horizon not at all.
#
# A group's place in bytes is F + 1/2 rounded down, F being the exact sum of
# its curve shift and its share of road_x - one rounding, so every edge
# moves one way from group to group, as its exact place does. But the lane
# lines are a whole number of bytes from the centre only every other
# half-width (road_row_pixels), so the rounding is biased: by up to a
# quarter of a byte, up on an even half-width and down on an odd one where
# the road goes right as it nears (the other way round going left), most
# where it goes half a byte a half-width - none where it goes a byte or
# more, nor where it stands still. That keeps them going one way too.
#
# All of it is whole numbers of 1/256 bytes (the Z80 does it so, a 16-bit
# sum a group):
#   A = k c1 + x PERSP_P h + 128      (256 F + 128)
#   v = k d + 2 PERSP_P x             (512 times F's slope, a byte a
#                                      half-width)
#   tau = |v| / 4 up to 256, (512 - |v|) / 4 up to 512, else 0 (rounded
#         down)
#   t = tau, its sign v's, the other way for an odd h (none for the rows
#       grouped two at a time: they have no lane lines)
#   shift = floor((A + t) / 256)
# ---------------------------------------------------------------------------

ROAD_X_MAX = 32             # pairs either way: the car on the grass beside it
PERSP_P = 10                # a pair of road_x moves half-width h h * 10 / 256
                            # bytes


def shift_tau(v):
    """The bias a slope v puts on a row's shift, in 1/256 bytes: w = v / 4
    rounded down, itself up to 64 either way, then back to 0 by 128 (the Z80
    works it out from w alone: cache5.asm)."""
    w = v >> 2
    if -64 <= w <= 64:
        return w
    if 64 < w < 128:
        return 128 - w
    if -128 <= w < -64:
        return -128 - w
    return 0


def road_shift(k, r, x=0):
    """Bytes to the right that row r moves at curve level k, the road x
    pairs right of the middle."""
    h = row_half_bytes(r)
    a = k * curve_c1(r) + x * PERSP_P * h + 128
    if h < CURVE_ROW_GROUPS:
        return a >> 8                   # (no lane lines: no bias)
    t = shift_tau(k * curve_d(r) + 2 * PERSP_P * x)
    if h & 1:
        t = -t
    return (a + min(t, 63)) >> 8        # (63: the Z80's table holds t - 64)


def curve_shift(k, r):
    """Bytes to the right that row r moves at curve level k, the road in the
    middle."""
    return road_shift(k, r, 0)


@lru_cache(maxsize=None)
def group_row(r):
    """The first row of row r's template group (the one its shift is worked
    out for)."""
    g = curve_group(r)
    return next(q for q in range(1, ROWS + 1) if curve_group(q) == g)


def player_shift(k, x, r):
    """Bytes right that road_x = x moves row r by at curve level k, as its
    template group does (for the bushes: they move with their row)."""
    q = group_row(r)
    return road_shift(k, q, x) - road_shift(k, q, 0)


# ---------------------------------------------------------------------------
# Colours per stripe band. Band 0 = A, band 1 = B.
# ---------------------------------------------------------------------------

BANDS = [
    dict(kerb=PEN["RED"], road=PEN["GREY"], line=PEN["WHITE"]),
    dict(kerb=PEN["WHITE"], road=PEN["GREY"],
         line=None),                       # dashed: no lane lines on band B
    # far away: the asphalt of band A, the kerb and the (absent) lane line of
    # band B - the markings move on where the stripes stop
    dict(kerb=PEN["WHITE"], road=PEN["GREY"], line=None),
]
GROUND_PEN = PEN["GRASS_A"]                # the strip between hills and peaks

# The grass is striped too, with stripes twice as long as the kerbs' - bit 7
# of (depth + camera) - from the near rows to GRASS_ROW: as far as two lines
# next to each other are never more than a kerb stripe apart (so the grass
# changes colour exactly where a kerb's band B gives way to band A, which is
# where the road engine changes it). Further away it is GRASS_A, as is the
# ground, and the grass between a bush's leaves.
PLAIN_GRASS = PEN["GRASS_A"]
GRASS_SHIFT = 7
GRASS_ROW = 14
GRASS_STRIPES = True


def grass_pen(r, zcam):
    """The grass beside row r for the camera at zcam."""
    if GRASS_STRIPES and r >= GRASS_ROW and (row_depth(r) + zcam) >> GRASS_SHIFT & 1:
        return PEN["GRASS_B"]
    return PLAIN_GRASS


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
        # lane lines: the middle one centred, the others 2 * (half // 2)
        # pixels either side - a whole number of bytes, so that the rounding
        # of road_shift can keep them straight - and as wide again outwards
        assert lanes == 4
        c = 2 * (half // 2)
        for start in (total - c - lw, total - lw // 2, total + c):
            for i in range(start, start + lw):
                if kw <= i < 2 * total - kw:
                    pens[i] = b["line"]
    return pens, total


# ---------------------------------------------------------------------------
# Bushes beside the road. The demo track loops every TRACK_PERIOD depth units
# (src/game.asm reads its hills and curves at (zcam / 32) mod 256); a bush
# stands at a depth z on it, on one side, in one of BUSH_SIZES (its height
# in metres - 1 m is 50/ROWS of a line per row, the lane being 3.7 m) and at
# a lateral factor from BUSH_LATS: its centre is that many times as far from
# the road's centre as the outer edge of the kerb.
#
# The engine has a sprite for each of BUSH_H heights (lines), 1.2 pixels wide
# a line (so a bush is 2.4 times as wide as it is tall), and per row tables
# of which sprite a size class uses and how far out a lateral class is. A
# size class is first drawn when its sprite would be BUSH_H_MIN lines high.
# ---------------------------------------------------------------------------

TRACK_PERIOD = 8192
BUSH_SIZES = [0.4, 0.6, 0.85]          # metres
BUSH_LATS = [1.2, 1.4, 1.6, 1.85, 2.1]
BUSH_LAT_OF = [(0, 2), (1, 3), (3, 4)]  # lateral classes each size can have
BUSH_H = [5, 6, 7, 9, 11, 13, 16]
BUSH_H_MIN = 4.5                        # lines: a smaller bush is not drawn
BUSH_ASPECT = 1.2                       # pixels across per line of height
BUSH_LINES_PER_M = 50 / ROWS            # lines per metre, per row
BUSH_ROW_MIN = 5                        # further away a bush is not drawn
BUSH_ZNEAR = 72                         # nearer than this it has gone by
BUSH_ZFAR = 1024                        # the depth tables end here
BUSH_GAP = (100, 300)                   # depth units from one bush to the next
BUSH_MAX = 8                            # bushes drawn at most, nearest first
BUSH_BIG_GAP = 400                      # ... and from one of the biggest size
BUSH_IN_REACH = 3                       # bushes in reach at once, at most
BUSH_SEED = 5


def bush_row(zr):
    """The row a bush zr depth units ahead stands on, 0 if none: the tables
    have it every 2 units up to 512 and every 8 beyond."""
    if zr < BUSH_ZNEAR or zr >= BUSH_ZFAR:
        return 0
    z = (zr & ~1) + 1 if zr < 512 else (zr & ~7) + 4
    r = int(DEPTH_K / z + 0.5)
    return r if BUSH_ROW_MIN <= r <= NEAR_ROW else 0


def bush_sprite_of(size, r):
    """The sprite index a bush of size class `size` uses on row r, None if it
    is too small to draw."""
    h = BUSH_SIZES[size] * BUSH_LINES_PER_M * r
    if h < BUSH_H_MIN:
        return None
    return min(range(len(BUSH_H)), key=lambda i: abs(BUSH_H[i] - h))


def bush_zvis(size):
    """How far ahead a bush of size class `size` is first drawn: one past the
    furthest it has a sprite at."""
    return 1 + max(zr for zr in range(BUSH_ZNEAR, BUSH_ZFAR)
                   if bush_row(zr) and bush_sprite_of(size, bush_row(zr)) is not None)


def bush_centre(k, r):
    """The road's centre on row r at curve level k, in bytes, for a bush."""
    return SCR_BYTES // 2 + bush_shift(k, r)


def bush_lat(lat, r):
    """Bytes from the road's centre to a bush's centre on row r - a byte
    more than the lateral factor says: off the middle a row's kerb is a byte
    wider at an odd byte (the core's parity), and the nearest bushes would
    stand on it."""
    return int(BUSH_LATS[lat] * (2 * HALF_MAX + KERB_BOTTOM) / ROWS / 2 * r + 0.5) + 1


# ---------------------------------------------------------------------------
# Props beside the road (tools/mkprops.py, scene.py): palms, dead trees,
# signs. They stand as bushes do (bush_row, bush_lat, bush_centre), but all
# of them on one scale of PROP_SIZES sprites, PROP_RATIO apart in height:
# a prop's sprite s is PROP_CAPS[kind] x PROP_RATIO ** (PROP_SIZES - 1 - s)
# lines high, and every kind takes sprite s on the same rows (prop_size_of:
# those where the tallest kind's would be nearest PROP_M metres high).
# ---------------------------------------------------------------------------

PROP_SIZES = 8
PROP_RATIO = 0.78
PROP_CAPS = dict(palm=44, stump=24, dead=28, limit=28, curve=22)
PROP_REF = "palm"
PROP_M = 1.6                            # the tallest kind's height, in bush
                                        # metres: its cap from row 42 on, its
                                        # top below the horizon (HORIZON_Y)


def prop_heights(kind):
    """Kind's sprites' heights, the smallest first."""
    cap = PROP_CAPS[kind]
    return [max(4, int(round(cap * PROP_RATIO ** (PROP_SIZES - 1 - s))))
            for s in range(PROP_SIZES)]


def prop_hw(kind, w):
    """The byte of a prop's sprite, `w` bytes wide, that its centre (its
    trunk's or post's foot) is on: its middle one - the left of the two
    middle ones of the curve sign pointing right, the left one's mirrored."""
    return w - 1 - w // 2 if kind == "curve_r" else w // 2


def prop_size_of(r):
    """The sprite (0 .. PROP_SIZES - 1) the props take on row r, None if they
    are too small to draw there."""
    h = PROP_M * BUSH_LINES_PER_M * r
    ref = prop_heights(PROP_REF)
    if h < 0.85 * ref[0]:
        return None
    return min(range(PROP_SIZES), key=lambda s: abs(ref[s] - h))


def bush_curve8(r):
    """8/7 of what curve level 1 moves row r by, as a parabola in rows (not
    in template groups as the road does: a bush need not be that exact)."""
    t = (ROWS - r) / (ROWS - 1)
    return int(CURVE_TOP * 8 * t * t / CURVE_K + 0.5)


def bush_shift(k, r):
    """Bytes right that curve level k moves a bush on row r."""
    v = (abs(k) * bush_curve8(r)) >> 3
    return v if k >= 0 else -v
