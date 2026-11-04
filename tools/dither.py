"""Photorealistic renders brought to mode 0's pens (tools/mkcars.py,
tools/mkselect.py).

A render is cut into cells, one a mode 0 pixel (CELL_PX render pixels):
each cell gets its pixels' mean colour (in linear light, weighted by their
alpha) and how much of it the render covers. A cell covered less than half
is clear; one covered more is laid over the asphalt's grey - as it will be,
on the road. grade() makes the colours more the CPC's, and pattern() brings
each cell to the pens given: the nearest pen, or a checkerboard of two
neighbouring ones, so that the shading's steps come out as mixtures of the
few colours there are. (dither(), error diffusion, was tried first: too
noisy on cells this big.)
"""

from PIL import Image

CELL_PX = (16, 8)
ASPHALT = (128, 128, 128)
DAMP = 0.8                      # of the error passed on


def _lin(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _srgb(v):
    v = max(0.0, min(1.0, v))
    return 255.0 * (v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055)


LIN = [_lin(float(i)) for i in range(256)]


def cell_colours(path, frame, cell_px=CELL_PX, under=ASPHALT):
    """Rows of (r, g, b) over `under`, or None for a clear cell; `path` a
    render's file, or an image."""
    im = (path if isinstance(path, Image.Image) else Image.open(path)).convert("RGBA")
    width = frame[0] * cell_px[0]
    assert im.size == (width, frame[1] * cell_px[1]), (path, im.size)
    data = list(im.getdata())
    n = cell_px[0] * cell_px[1]
    ul = [_lin(float(c)) for c in under]
    sums = [[[0.0] * 4 for _ in range(frame[0])] for _ in range(frame[1])]
    for i, (pr, pg, pb, pa) in enumerate(data):
        if not pa:
            continue
        y, x = divmod(i, width)
        s = sums[y // cell_px[1]][x // cell_px[0]]
        w = pa / 255.0
        s[0] += LIN[pr] * w
        s[1] += LIN[pg] * w
        s[2] += LIN[pb] * w
        s[3] += w
    rows = []
    for cy in range(frame[1]):
        row = []
        for cx in range(frame[0]):
            r, g, b, a = sums[cy][cx]
            cover = a / n
            if cover < 0.5:
                row.append(None)
                continue
            # the pixels are premultiplied here: what is left shows the grey
            row.append(tuple(_srgb(c / n + u * (1 - cover)) for c, u in zip((r, g, b), ul)))
        rows.append(row)
    return rows


def _dist(a, b):
    """Colour distance ("redmean": weights after how bright the red is)."""
    rm = (a[0] + b[0]) / 2
    dr, dg, db = a[0] - b[0], a[1] - b[1], a[2] - b[2]
    return (2 + rm / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256) * db * db


def dither(cells, palette, damp=DAMP):
    """cells: rows of (r, g, b) or None; palette: {letter: (r, g, b)}.
    Rows of letters, '.' clear."""
    h, w = len(cells), len(cells[0])
    err = [[[0.0, 0.0, 0.0] for _ in range(w)] for _ in range(h)]
    out = [["."] * w for _ in range(h)]
    items = list(palette.items())
    for y in range(h):
        xs = range(w) if y % 2 == 0 else range(w - 1, -1, -1)
        d = 1 if y % 2 == 0 else -1
        for x in xs:
            c = cells[y][x]
            if c is None:
                continue
            want = [max(0.0, min(255.0, c[i] + err[y][x][i])) for i in range(3)]
            letter, rgb = min(items, key=lambda it: _dist(want, it[1]))
            out[y][x] = letter
            e = [(want[i] - rgb[i]) * damp for i in range(3)]
            for dx, dy, f in ((d, 0, 7), (-d, 1, 3), (0, 1, 5), (d, 1, 1)):
                xx, yy = x + dx, y + dy
                if 0 <= xx < w and yy < h and cells[yy][xx] is not None:
                    for i in range(3):
                        err[yy][xx][i] += e[i] * f / 16
    return ["".join(r) for r in out]


def grade(cells, sat=1.5, black=0.14, knee=0.35):
    """The renders' colours made more the CPC's: more saturated (a car's
    reflections keep its colour), the darks darker - brightness `black` to
    `knee` stretched over 0 to `knee`, the rest as it was (dark plastic goes
    black, not to the asphalt's grey)."""
    import colorsys
    out = []
    for row in cells:
        r2 = []
        for c in row:
            if c is None:
                r2.append(None)
                continue
            h, s, v = colorsys.rgb_to_hsv(*(x / 255.0 for x in c))
            if v < knee:
                v = max(0.0, knee * (v - black) / (knee - black))
            r2.append(tuple(255.0 * x for x in colorsys.hsv_to_rgb(h, min(1.0, s * sat), v)))
        out.append(r2)
    return out


def _mix(a, b):
    """Two colours side by side, as the eye mixes them: their mean light."""
    return tuple(_srgb((_lin(float(x)) + _lin(float(y))) / 2) for x, y in zip(a, b))


def pattern(cells, palette, pairs, bias=0.6, mixed_only=""):
    """cells: rows of (r, g, b) or None; palette: {letter: (r, g, b)};
    pairs: the letter pairs that may mix (neighbours on a ramp: mixing
    opposite colours into a grey looks like noise). Each cell the pen
    nearest its colour - or, if nearer, a checkerboard of such a pair (an
    even mixture): the classic CPC dither, clean on flat surfaces, and the
    same pairs again and again. A mixture only if it is `bias` times as
    near as the nearest pen, or nearer: flat colours are calmer. The pens
    in `mixed_only` only in mixtures (the asphalt's grey: a cell of it
    would look like a hole). Rows of letters, '.' clear."""
    choices = [(rgb, a, a, 1.0) for a, rgb in palette.items() if a not in mixed_only]
    choices += [(_mix(palette[a], palette[b]), a, b, 1 / (bias * bias)) for a, b in pairs]
    out = []
    for y, row in enumerate(cells):
        line = ""
        for x, c in enumerate(row):
            if c is None:
                line += "."
                continue
            rgb, a, b, w = min(choices, key=lambda ch: _dist(c, ch[0]) * ch[3])
            line += a if (x + y) % 2 == 0 else b
        out.append(line)
    return out
