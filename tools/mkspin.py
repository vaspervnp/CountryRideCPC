#!/usr/bin/env python3
"""The four cars turning round on the select screen, while the player picks
one (src/spin.asm plays them; README.md: The cars turning).

Each car is seen every 15 degrees (24 views, a turn in 3 seconds), its
model's photoreal render (tools/spin3d.py: tools/cars3d.py's models, heights
times 0.8 as the screen's side views, 14 mode 0 pixels a metre - a car's side
about 64 pixels, as the screen's pictures - the camera 5 degrees above, the
sun with the camera) brought to the screen's own pens as mkselect.py brings
its pictures (tools/dither.py: each cell's mean colour over the panel's grey,
graded, a checkerboard where two neighbouring pens mix nearer; lone cells
dropped; outlined in black), in its panel between its name and its bars: the
panel's rows 12-47, columns 2-75, the cars' bottoms and middles where they
stay.

    python3 tools/mkspin.py renders DIR   the renders (DIR/<car>_<angle>.png)
                                          to assets/cars/spin_<car>.png: the
                                          24 views in the screen's pens
    python3 tools/mkspin.py               src/gen/spin.asm and spin0-4.bin

What a view changes on the screen (src/gen/select.scr, the views over its
side pictures) is a stream for the player: each token the low byte of where
it jumps in a page of code (spin.asm: LDI chains for bytes as they are, LD
(DE),A : INC E chains for runs, the byte for A, an address, the end); a
first stream for each car puts its view 0 over its side picture. The streams
(about 70K) go in five 16K areas - banks 4-7 and base memory at #4000 - in
order, each area as much as packs (ZX0, rasm's: pack.asm) into what the
loader can load at PACK_LOW. They are played here too and checked against
the views, byte for byte, through two turns.

The player is timed to the beam (spin.asm), and that from what each stream
takes, worked out here: the top cars from TOP_AT microseconds after the
VSYNC's end, the bottom cars at the next VSYNC's end, then a wait to
BOTTOM_END whatever they took.
"""

import os
import re
import subprocess
import sys
import tempfile

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dither  # noqa: E402
import mkcar  # noqa: E402
import mkselect as ms  # noqa: E402
from cpcgfx import m0_byte, m0_decode  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FRAME = (80, 40)                 # the renders' frame, in cells (tools/spin3d.py)
VIEWS = 24
AREA = (2, 12, 74, 36)           # in a panel: x, y, width, rows (between its name and its bars)
GAP = 4                          # unchanged bytes written over rather than a new span
L, R = 48, 63                    # the player's longest literal and run (spin.asm)
T_RUN0 = 2 * L + 6
T_LOADA = T_RUN0 + 2 * R + 6
T_SET = T_LOADA + 8
T_END = T_SET + 10
AREAS = [0xC4, 0xC5, 0xC6, 0xC7, 0xC0]   # banks 4-7, then base memory at #4000
PACKED_MAX = 0xA600 - 0x8000 - 2         # (UNPACK - PACK_LOW, less the word)

# the timing (spin.asm), in microseconds (NOPs) from a VSYNC's end (line 248)
CALL_US = 60                     # tn_play's own, a car (its table, the bank, the call)
FLYBACK_US = 30                  # from the VSYNC's end to a car's first byte
TOP_AT = 8900                    # the top cars from here (the beam past them: 8380)
BOTTOM_BY = 11100 - 300          # the bottom cars done by here (the beam at them: 11140)
BOTTOM_END = 10350               # and their wait after them over here: line 248 + 162
PAD_US = 40                      # (the wait's own setting up)


def art(path):
    """A render as rows of pens or None, outlined in black (mkselect.side_art's way)."""
    cells = dither.grade(dither.cell_colours(path, FRAME, under=ms.RGB["G"]))
    rows = mkcar.lone(dither.pattern(cells, ms.RGB, ms.PAIRS, mixed_only="G"))
    h, w = len(rows), len(rows[0])
    out = [[None if c == "." else ms.PEN[c] for c in r] for r in rows]
    for y in range(h):
        for x in range(w):
            if out[y][x] is None and any(
                    0 <= y + dy < h and 0 <= x + dx < w and rows[y + dy][x + dx] != "."
                    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))):
                out[y][x] = ms.PEN["K"]
    return out


def sheet_path(name):
    return os.path.join(ROOT, "assets", "cars", "spin_%s.png" % name)


def write_sheet(name, arts):
    """A car's views in the screen's pens (255: clear), 6 a row."""
    im = Image.new("P", (FRAME[0] * 6, FRAME[1] * 4), 255)
    pal = []
    for n, _ in ms.PENS[:13]:
        pal += list(ms.RGB[n])
    im.putpalette(pal + [0, 0, 0] * (256 - 13))
    px = im.load()
    for k, a in enumerate(arts):
        for y, r in enumerate(a):
            for x, p in enumerate(r):
                if p is not None:
                    px[(k % 6) * FRAME[0] + x, (k // 6) * FRAME[1] + y] = p
    im.save(sheet_path(name), transparency=255)


def read_sheet(name):
    im = Image.open(sheet_path(name))
    px = im.load()
    return [[[None if px[(k % 6) * FRAME[0] + x, (k // 6) * FRAME[1] + y] == 255
              else px[(k % 6) * FRAME[0] + x, (k // 6) * FRAME[1] + y]
              for x in range(FRAME[0])] for y in range(FRAME[1])] for k in range(VIEWS)]


def screen_pens(scr):
    rows = []
    for y in range(200):
        off = (y & 7) * 0x800 + (y >> 3) * 80
        r = []
        for bx in range(80):
            r += list(m0_decode(scr[off + bx]))
        rows.append(r)
    return rows


def to_bytes(pens, under):
    """The screen of pens, over under's hidden bytes."""
    mem = bytearray(under)
    for y in range(200):
        off = (y & 7) * 0x800 + (y >> 3) * 80
        for bx in range(80):
            mem[off + bx] = m0_byte(pens[y][2 * bx], pens[y][2 * bx + 1])
    return mem


def t_lit(n):
    return 2 * (L - n)


def t_run(n):
    return T_RUN0 + 2 * (R - n)


def delta(new, old):
    """The tokens that turn the screen old into new (addresses at #C000)."""
    diffs = [i for i in range(16384) if new[i] != old[i]]
    spans = []
    for d in diffs:
        if spans and d - spans[-1][1] <= GAP:
            spans[-1][1] = d
        else:
            spans.append([d, d])
    out, a = bytearray(), None
    for s, e in spans:
        ad = 0xC000 + s
        out += bytes([T_SET, ad & 255, ad >> 8])
        i = s
        while i <= e:
            v = new[i]
            r = 1
            while i + r <= e and new[i + r] == v:
                r += 1
            rr = min(r, R, 255 - (i & 255))           # (INC E: E never wraps)
            if rr >= 4 or (rr >= 3 and a == v):
                if a != v:
                    out += bytes([T_LOADA, v])
                    a = v
                out.append(t_run(rr))
                i += rr
                continue
            j = i + 1                                  # bytes as they are, till a run
            while j <= e and j - i < L:
                r = 1
                while j + r <= e and new[j + r] == new[j] and r < 4:
                    r += 1
                if r >= 4 and 255 - (j & 255) >= 4:
                    break
                j += 1
            out.append(t_lit(j - i))
            out += new[i:j]
            i = j
    out.append(T_END)
    return bytes(out)


def play(stream, mem):
    """The player, here: the stream played over mem (the screen's 16K)."""
    i, de, a = 0, None, None
    while True:
        t = stream[i]
        i += 1
        if t == T_END:
            return
        if t == T_SET:
            de = (stream[i] | stream[i + 1] << 8) - 0xC000
            i += 2
        elif t == T_LOADA:
            a = stream[i]
            i += 1
        elif t >= T_RUN0:
            n = R - (t - T_RUN0) // 2
            assert (de & 255) + n <= 255
            mem[de:de + n] = bytes([a]) * n
            de += n
        else:
            n = L - t // 2
            mem[de:de + n] = stream[i:i + n]
            de += n
            i += n


def micros(stream):
    """What the player takes over the stream, in microseconds (NOPs)."""
    i, t = 0, 0
    while True:
        k = stream[i]
        i += 1
        if k == T_END:
            return t + 3
        t += 8                                       # TN_NEXT: LD C,(HL) INC HL LD IXL,C JP (IX)
        if k == T_SET:
            t += 8
            i += 2
        elif k == T_LOADA:
            t += 4
            i += 1
        elif k >= T_RUN0:
            t += 3 * (R - (k - T_RUN0) // 2)
        else:
            n = L - k // 2
            t += 5 * n
            i += n


def packed(data):
    """data's size packed by rasm's ZX0 (as pack.asm packs it)."""
    with tempfile.TemporaryDirectory() as d:
        open(os.path.join(d, "a.bin"), "wb").write(data)
        open(os.path.join(d, "a.asm"), "w").write(
            'org 0\nlzx0\nincbin "a.bin"\nlzclose\npk_end:\nsave "p.bin",0,pk_end\n')
        subprocess.run(["rasm", "a.asm", "-wc"], cwd=d, capture_output=True, check=True)
        return os.path.getsize(os.path.join(d, "p.bin"))


def renders(src):
    for name, _ in ms.CARS:
        arts = [art(os.path.join(src, "%s_%03d.png" % (name, a))) for a in range(0, 360, 360 // VIEWS)]
        write_sheet(name, arts)
        print(os.path.relpath(sheet_path(name)))


def main():
    select = bytearray(open(os.path.join(ROOT, "src", "gen", "select.scr"), "rb").read())
    base = screen_pens(select)
    cars = [n for n, _ in ms.CARS]
    views = {}
    for i, name in enumerate(cars):
        arts = read_sheet(name)
        ys = [y for a in arts for y, r in enumerate(a) if any(p is not None for p in r)]
        xs = [x for a in arts for r in a for x, p in enumerate(r) if p is not None]
        x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
        assert x1 - x0 <= AREA[2] and y1 - y0 <= AREA[3], (name, x1 - x0, y1 - y0)
        px, py = ms.PANEL_X[i % 2] + AREA[0], ms.PANEL_Y[i // 2] + AREA[1]
        ox = px + (AREA[2] - (x1 - x0)) // 2 - x0     # the cars' middles, their bottoms
        oy = py + AREA[3] - y1                        # on the area's last row
        views[name] = (arts, ox, oy, (px, py))
    frames = []
    for k in range(VIEWS):
        pens = [r[:] for r in base]
        for name in cars:
            arts, ox, oy, (px, py) = views[name]
            for y in range(py, py + AREA[3]):
                for x in range(px, px + AREA[2]):
                    pens[y][x] = ms.PEN["G"]
            for y, r in enumerate(arts[k]):
                for x, p in enumerate(r):
                    if p is not None:
                        pens[oy + y][ox + x] = p
        frames.append(to_bytes(pens, select))

    def only(mem, name):
        """mem in name's area, select's elsewhere."""
        out = bytearray(select)
        _, _, _, (px, py) = views[name]
        for y in range(py, py + AREA[3]):
            off = (y & 7) * 0x800 + (y >> 3) * 80
            for bx in range(px // 2, (px + AREA[2] + 1) // 2):
                out[off + bx] = mem[off + bx]
        return out

    streams = {}
    for name in cars:
        own = [only(f, name) for f in frames]
        streams[name] = [delta(own[0], select)] + [delta(own[k], own[k - 1]) for k in range(1, VIEWS)] \
            + [delta(own[0], own[VIEWS - 1])]
    mem = bytearray(select)                      # checked: two turns, all four
    for name in cars:
        play(streams[name][0], mem)
    assert mem == frames[0]
    for _ in range(2):
        for k in list(range(1, VIEWS)) + [0]:
            for name in cars:
                play(streams[name][k if k else VIEWS], mem)
            assert mem == frames[k], k
    # the timing
    bottom = max(FLYBACK_US + sum(micros(streams[cars[c]][k]) + CALL_US for c in (2, 3))
                 for k in range(VIEWS + 1))
    top = max(sum(micros(streams[cars[c]][k]) + CALL_US for c in (0, 1)) for k in range(VIEWS + 1))
    assert bottom <= BOTTOM_BY and bottom <= BOTTOM_END - PAD_US, bottom
    assert TOP_AT + top < 20000 + 4100 + 31 * 64 - 300, top
    pads = [max(1, (BOTTOM_END - FLYBACK_US - PAD_US
                    - sum(micros(streams[cars[c]][k]) + CALL_US for c in (2, 3))) // 7)
            for k in range(VIEWS + 1)]
    # into the areas, in order, each as much as packs into PACKED_MAX
    order = [(i, k) for i in range(4) for k in range(VIEWS + 1)]
    where, areas, n = {}, [], 0
    while n < len(order):
        assert len(areas) < len(AREAS), "the streams do not fit in the five areas"
        lo, hi = n + 1, len(order)              # the most streams that fit, by halves
        while sum(len(streams[cars[i]][k]) for i, k in order[n:hi]) > 16384:
            hi -= 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            data = b"".join(streams[cars[i]][k] for i, k in order[n:mid])
            if packed(data) <= PACKED_MAX:
                lo = mid
            else:
                hi = mid - 1
        data = bytearray()
        for i, k in order[n:lo]:
            where[i, k] = (AREAS[len(areas)], 0x4000 + len(data))
            data += streams[cars[i]][k]
        areas.append(bytes(data))
        n = lo
    gen = os.path.join(ROOT, "src", "gen")
    for k, data in enumerate(areas):
        open(os.path.join(gen, "spin%d.bin" % k), "wb").write(data)
    for k in range(len(areas), len(AREAS)):
        p = os.path.join(gen, "spin%d.bin" % k)
        if os.path.exists(p):
            os.remove(p)
    lines = [";; Generated by tools/mkspin.py - do not edit.", "",
             ";; the views, the player's tokens (spin.asm lays its page out so)",
             "TN_VIEWS    EQU %d" % VIEWS, "TN_TOK_L    EQU %d" % L, "TN_TOK_R    EQU %d" % R,
             "TN_T_RUN0   EQU %d" % T_RUN0, "TN_T_LOADA  EQU %d" % T_LOADA,
             "TN_T_SET    EQU %d" % T_SET, "TN_T_END    EQU %d" % T_END,
             "TN_AREAS    EQU %d" % len(areas),
             ";; the top cars' wait after the VSYNC's end (7 microseconds a turn)",
             "TN_TOP_WAIT EQU %d" % ((TOP_AT - FLYBACK_US) // 7), "",
             ";; each car's table: each view's stream - its area (RAM config) and its",
             ";; address at #4000 - view 0 over the side picture, views 1-23, view 0",
             "tn_cars"] + ["    defw tn_car%d" % i for i in range(4)]
    for i in range(4):
        lines.append("tn_car%d" % i)
        lines += ["    defb #%02X : defw #%04X" % where[i, k] for k in range(VIEWS + 1)]
    lines += ["", ";; each view's wait after the bottom cars, to end at BOTTOM_END",
              "tn_pad"] + ["    defw %d" % p for p in pads]
    open(os.path.join(gen, "spin.asm"), "w").write("\n".join(lines) + "\n")
    sizes = [len(a) for a in areas]
    print("src/gen/spin.asm, spin0-%d.bin: %d bytes in %d areas (%s); the bottom cars done by %d us"
          " (the beam at them: 11140), the top cars by %d (the beam back: 26084)"
          % (len(areas) - 1, sum(sizes), len(areas), ", ".join(map(str, sizes)), bottom, TOP_AT + top))


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "renders":
        renders(sys.argv[2])
    else:
        main()
