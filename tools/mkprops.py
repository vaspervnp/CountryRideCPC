#!/usr/bin/env python3
"""The roadside props' sprites, from photorealistic renders of their 3D
models.

tools/props3d.py (run in Blender) renders each tree - a tall palm, a short
palm, a dead tree - at each of its sprite heights into
assets/props/<tree>_<lines>.png, a cell a mode 0 pixel. This brings each
to the pens (tools/dither.py: each cell's mean colour, the
prop's own, graded, a checkerboard where two neighbouring pens mix nearer; each
prop its own pens), drops lone cells, and makes every byte - two pixels -
either clear or whole (a byte half clear takes its other pixel's pen: a
trunk a pixel wide is a byte wide), so that the game copies bytes and
leaves the grass between them. The signs - a speed limit, 80 in a red
ring, and a curve's, black chevrons on a yellow board - are drawn here as
pixels (limit_art, curve_art); the curve sign pointing right is the left
one mirrored. All in tools/propsart.py; also build/props-sheet.png, the
props on each stage's grass.
"""

import os
import re
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cpcgfx as G  # noqa: E402
from cpcgfx import PEN, FIRMWARE, PENS  # noqa: E402
import course  # noqa: E402
import dither  # noqa: E402
import mkcar  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "assets", "props")
CELL_PX = (16, 8)

LETTERS = dict(K="BLACK", D="CAR_DARK", O="ORANGE", R="RED", Y="YELLOW",
               W="WHITE", G="GREY", B="BUSH", A="GRASS_A")
# each prop's pens (letters), and the pairs of them that may mix
PROP_PENS = dict(
    palm=("KDOBA", ["KD", "DO", "KB", "BA"]),
    stump=("KDOBA", ["KD", "DO", "KB", "BA"]),
    dead=("KG", ["KG"]),
)
TREES = list(PROP_PENS)
SIGN_HEIGHTS = {k: G.prop_heights(k) for k in ("limit", "curve")}
DIGITS = {"8": ["###", "#.#", "###", "#.#", "###"],
          "0": ["###", "#.#", "#.#", "#.#", "###"]}


def heights(name):
    hs = sorted(int(m.group(1)) for f in os.listdir(SRC)
                for m in [re.match(r"%s_(\d+)\.png$" % name, f)] if m)
    assert hs, name
    return hs


def art(name, h):
    """Rows of letters, '.' clear, bytes whole (the frame's first column
    starts a byte: the frame is an odd number of cells, its middle one the
    prop's; the sprite is placed by its middle byte, so the frame is
    widened by a cell on the left first)."""
    path = os.path.join(SRC, "%s_%d.png" % (name, h))
    im = Image.open(path)
    frame = (im.width // CELL_PX[0], im.height // CELL_PX[1])
    letters, pairs = PROP_PENS[name]
    palette = {c: _rgb(LETTERS[c]) for c in letters}
    cells = prop_cells(path, frame)
    rows = dither.pattern(dither.grade(cells), palette, pairs)
    rows = ["." + r for r in mkcar.lone(rows)]          # (even width)
    out = []
    for r in rows:
        line = ""
        for x in range(0, len(r), 2):
            a, b = r[x], r[x + 1]
            if a == "." and b != ".":
                a = b
            elif b == "." and a != ".":
                b = a
            line += a + b
        out.append(line)
    # empty lines at the top go (the base line is the frame's last)
    while out and not out[0].strip("."):
        out.pop(0)
    # a line with none of it (a dead tree's limb off the trunk, small) takes
    # the trunk's foot: the game has no empty lines in a sprite
    out = [r if r.strip(".") else out[-1] for r in out]
    if len(set(out)) == 1:              # a pole (its branches too thin to
        out = out[:1] * h               # show): as high as it should be
    if name in ("palm", "stump"):       # the trunk lit on the left, the
        out = [trunk(r, name == "palm") for r in out]   # same line again and again
    return out


def trunk(r, thin):
    """A palm's line that is its trunk alone - one run of bark - lit on the
    left: orange, then dark red, black at the right; `thin`, a byte (its
    middle one)."""
    rs = runs(r)
    if len(rs) != 1 or not set("".join(rs[0][1])) <= set("DOK"):
        return r
    x, by = rs[0]
    n = 2 * len(by)
    if thin:
        x, n = x + (len(by) - 1) // 2, 2
        r = "." * len(r)
    px = "O" * max(1, n // 4) + "D" * (n - max(1, n // 4) - (n > 2)) + "K" * (n > 2)
    return r[:2 * x] + px + r[2 * x + n:]


def runs(line):
    """A line's runs of bytes: [(first byte, bytes)]."""
    by = [line[i:i + 2] for i in range(0, len(line), 2)]
    out, x = [], 0
    while x < len(by):
        if by[x] == "..":
            x += 1
            continue
        x1 = x
        while x1 < len(by) and by[x1] != "..":
            x1 += 1
        out.append((x, by[x:x1]))
        x = x1
    return out


def groups(rows):
    """The lines, top down, as groups of the same line: [(lines, runs)]."""
    out = []
    for r in rows:
        if out and out[-1][2] == r:
            out[-1][0] += 1
        else:
            out.append([1, runs(r), r])
    return [(n, rs) for n, rs, _ in out]


def stream_len(rows):
    """Bytes of the sprite as the game has it: per group its lines and its
    runs, per run its first byte, length and bytes; 0 at the end."""
    return 1 + sum(2 + sum(2 + len(b) for _, b in rs) for _, rs in groups(rows))


COVER = 0.3                     # a cell this covered is the prop's
COVER_THIN = 0.06               # ... and the most covered of a run of cells
                                # this covered (a trunk or a branch thinner
                                # than a pixel stays a pixel wide)


def prop_cells(path, frame):
    """Rows of the cells' colours - the mean of the prop's own pixels in
    each, not laid over anything - or None for a clear cell: one covered
    COVER or more, or the most covered of a run of cells covered
    COVER_THIN or more with none covered COVER."""
    im = Image.open(path).convert("RGBA")
    w = im.width
    data = list(im.get_flattened_data())
    n = CELL_PX[0] * CELL_PX[1]
    sums = [[[0.0] * 4 for _ in range(frame[0])] for _ in range(frame[1])]
    for i, (r, g, b, a) in enumerate(data):
        if not a:
            continue
        y, x = divmod(i, w)
        c = sums[y // CELL_PX[1]][x // CELL_PX[0]]
        f = a / 255.0
        c[0] += dither.LIN[r] * f
        c[1] += dither.LIN[g] * f
        c[2] += dither.LIN[b] * f
        c[3] += f
    rows = []
    for srow in sums:
        cover = [c[3] / n for c in srow]
        keep = [v >= COVER for v in cover]
        x = 0
        while x < len(cover):
            if cover[x] < COVER_THIN:
                x += 1
                continue
            x1 = x
            while x1 < len(cover) and cover[x1] >= COVER_THIN:
                x1 += 1
            if not any(keep[x:x1]):
                keep[max(range(x, x1), key=lambda i: cover[i])] = True
            x = x1
        rows.append([tuple(dither._srgb(v / c[3]) for v in c[:3]) if k else None
                     for c, k in zip(srow, keep)])
    return rows


def _rgb(pen):
    return FIRMWARE[PENS[PEN[pen]][1]][1]


def canvas(w, h):
    return [["."] * w for _ in range(h)]


def bytes_whole(rows):
    """Rows of pixels, an even number, each byte whole or clear (as art())."""
    out = []
    for r in rows:
        r = list(r) + ["."] * (len(r) & 1)
        for x in range(0, len(r), 2):
            if r[x] == "." and r[x + 1] != ".":
                r[x] = r[x + 1]
            elif r[x + 1] == "." and r[x] != ".":
                r[x + 1] = r[x]
        out.append("".join(r))
    return out


def post(c, x, y0, y1):
    """A post a byte wide: grey, its right pixel in shadow."""
    for y in range(y0, y1):
        c[y][x], c[y][x + 1] = "G", "K"


def limit_art(h):
    """A speed limit sign h lines high: a disc - a red ring, white inside,
    80 in black where there is room for it (a little wider then), else a
    mark - on a
    post a byte wide, the disc's middle between its two pixels; the disc's
    pixels are two lines high, as the screen's are."""
    ph = max(2, int(h * 0.56 + 0.5))                # the disc, lines
    digits = ph >= 14
    pw = max(2, (ph + 1) // 2 + (2 if digits else 0))   # ... pixels across
    pw += pw & 1
    w = pw + 2
    w += (2 - w % 4) % 4                            # (w/2 - 1 even: the post
    c = canvas(w, h)                                # a whole byte)
    cx = w / 2.0
    for j in range(ph):
        y = (j + 0.5) / ph * 2 - 1
        for i in range(w):
            x = (i + 0.5 - cx) / (pw / 2.0)
            d = x * x + y * y
            if d <= 1.0:
                c[j][i] = "W" if d < 0.55 and ph >= 5 else "R"
    m = w // 2
    if digits:                                      # 80, a row one or two
        rh = 2 if ph >= 14 else 1                   # lines; 8 and 0 a pixel
        top = (ph - 5 * rh) // 2                    # either side of the middle
        for k, d in enumerate("80"):
            x0 = m - 4 if k == 0 else m + 1
            for j, row in enumerate(DIGITS[d]):
                for i, ch in enumerate(row):
                    for r in range(rh):
                        c[top + j * rh + r][x0 + i] = "K" if ch == "#" else "W"
    elif ph >= 5:                                   # (a mark for it)
        for j in range(ph // 2 - (ph >= 9), ph // 2 + 1):
            c[j][m - 1] = c[j][m] = "K"
    post(c, m - 1, ph, h)
    return bytes_whole(c)


def curve_art(h):
    """A curve sign h lines high, chevrons pointing left: a yellow board
    edged in black (the desert's grass is yellow too), two black chevrons
    (one, then a mark, when it is smaller), on two posts (one when it is
    narrower than 12 pixels); its pixels are two lines high, as the screen's are."""
    bh = max(2, int(h * 0.45 + 0.5))                # the board, lines
    bw = max(4, bh + (bh & 1))                      # ... pixels across: twice
    w = bw                                          # as wide as high
    x0 = 0
    c = canvas(w, h)
    for j in range(bh):
        for i in range(bw):
            edge = j in (0, bh - 1) or i in (0, bw - 1)
            c[j][x0 + i] = "K" if edge and bh >= 4 else "Y"
    mid = (bh - 1) / 2.0
    if bh >= 5:
        n = 2 if bh >= 8 else 1
        stroke = 2 if bh >= 10 else 1
        slot = (bw - 2) // n
        reach = max(1, slot - stroke)
        for k in range(n):
            ax = x0 + 2 + k * slot
            for j in range(1, bh - 1):
                off = int(abs(j - mid) / max(1.0, mid - 1) * reach + 0.5)
                for t in range(stroke):
                    c[j][min(x0 + bw - 2, ax + off + t)] = "K"
    elif bh >= 3:
        c[bh // 2][w // 2] = "K"
    if bw >= 12:
        post(c, x0 + 2, bh, h)
        post(c, bw - 4, bh, h)
    else:
        post(c, (w // 2) // 2 * 2, bh, h)
    return bytes_whole(c)


def mirrored(rows):
    return [r[::-1] for r in rows]


def all_art():
    out = {}
    for name in TREES:
        out[name] = {h: art(name, h) for h in heights(name)}
    out["limit"] = {h: limit_art(h) for h in SIGN_HEIGHTS["limit"]}
    out["curve"] = {h: curve_art(h) for h in SIGN_HEIGHTS["curve"]}
    out["curve_r"] = {h: mirrored(rows) for h, rows in out["curve"].items()}
    return out


def sheet(arts, path):
    """Every prop at every size, on each stage's grass in its colours."""
    sx, sy = 3, 3
    stages = list(range(len(course.STAGES)))
    wide = 4 + sum((len(rows[0]) if rows else 0) + 2 for n in arts for rows in arts[n].values())
    tall = max(len(arts[n][max(arts[n])]) for n in arts)
    rowh = tall + 4
    img = Image.new("RGB", (sx * wide, sy * rowh * len(stages)), (0, 0, 0))
    for s in stages:
        fw = dict(zip(course.STAGE_PENS, course.stage_fw(s)))
        def rgb(pen):
            return FIRMWARE[fw.get(pen, PENS[PEN[pen]][1])][1]
        y0 = s * rowh
        for yy in range(rowh):
            c = rgb("GRASS_A" if (yy // 3) % 2 else "GRASS_B")
            for xx in range(img.width // sx):
                for dx in range(sx):
                    for dy in range(sy):
                        img.putpixel((xx * sx + dx, (y0 + yy) * sy + dy), c)
        x0 = 2
        for name in arts:
            for h in sorted(arts[name]):
                rows = arts[name][h]
                for j, r in enumerate(rows):
                    for i, ch in enumerate(r):
                        if ch == ".":
                            continue
                        c = rgb(LETTERS[ch])
                        for dx in range(sx):
                            for dy in range(sy):
                                img.putpixel(((x0 + i) * sx + dx, (y0 + rowh - 2 - len(rows) + j) * sy + dy), c)
                x0 += (len(rows[0]) if rows else 0) + 2
    img.save(path)


def main():
    arts = all_art()
    lines = ['"""Generated by tools/mkprops.py - do not edit."""', "",
             "LETTERS = %r" % LETTERS,
             "PROPS_ART = {"]
    for name in arts:
        lines.append("    %r: {" % name)
        for h in sorted(arts[name]):
            lines.append("        %d: [" % h)
            for r in arts[name][h]:
                lines.append("            %r," % r)
            lines.append("        ],")
        lines.append("    },")
    lines.append("}")
    with open(os.path.join(ROOT, "tools", "propsart.py"), "w") as f:
        f.write("\n".join(lines) + "\n")
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    sheet(arts, os.path.join(ROOT, "build", "props-sheet.png"))
    total = 0
    for name in arts:
        sizes = {h: stream_len(rows) for h, rows in sorted(arts[name].items())}
        if name != "curve_r":
            total += sum(sizes.values())
        print("%-8s %d bytes: %s" % (name, sum(sizes.values()), sizes))
    print("total %d bytes (the right curve sign the left mirrored)" % total)


if __name__ == "__main__":
    main()
