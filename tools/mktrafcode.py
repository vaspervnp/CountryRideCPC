#!/usr/bin/env python3
"""The traffic's sprites as code, and the tables src/traffic.asm projects
and draws a car with: src/gen/traffic.asm (bank 6) and the pieces' code,
src/gen/trafcode_<region>.asm.

A piece (tools/trafficart.py: a near size's top or bottom, or a further
size's whole car) is code like a bush's, entered with HL at the right end
of its first line's run on the screen and interrupts off, but its paint -
black in the art - comes from registers: the car's colour for the even
lines (from the car's top) in DE, both bytes the same, the odd lines' in IY
(a checkerboard of two pens is a byte one way round on even lines, the other
on odd ones; a pen alone, both the same). A byte is all paint or none
(tools/mktraffic.py), so a word of paint is PUSH DE or PUSH IY, and a word
half paint is the paint byte from E or IYL and the other loaded, as a
plain word is: a painted car costs no more than a fixed one. IX holds the
piece's most used plain word. A further size's whole car loads its bottom's
colour (tr_cw2) at the line its top ends. Per line:

    ld sp,hl
    call tr_st<dx>      the step to the next line's right end, dx bytes on
                        (src/trafglue.asm: HL += #800 + dx, on to the next
                        character row past its last line, interrupts a
                        chance) - or LD BC,#800+dx and CALL tr_st; a line of
                        one word steps there and then, with no interrupt
    pushes              right to left

and JP tr_done after the last. The call's return address, and an
interrupt's, land where the line's first two words go.

The pieces go in what is free of banks 4, 6 and 7, the fragments and the
road parts' hidden lines (REGIONS); a piece is run in its bank's RAM
configuration (src/trafglue.asm: tr_go). Pieces that end the same way share
their last lines. The directory gives each its code, its
configuration, the lines before its first (from its top) and where its
first line's run ends (bytes from the car's left).
"""

import collections
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cpcgfx as G  # noqa: E402
from cpcgfx import PEN, m0_byte  # noqa: E402
import mktraffic as T  # noqa: E402
import scene as S  # noqa: E402
from trafficart import TRAFFIC_ART  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
NEAR = T.NEAR
COLOURS = S.TRAFFIC_COLOURS
TR_ZFAR = 640                   # src/traffic.asm TR_ZAWAY: no car further

# Where the pieces go: name, its RAM configuration, where it must end, and
# the room it has (what is free there at run time - the ASSERT is the judge
# of what the binary has there) - each right after what is already there
# (src/main.asm, common.asm), or at its start (the holes below). A piece is
# laid in the regions of one configuration, on from one to the next with a
# JP where one is full (fragment 4's goes with bank 6's: it is mapped
# whatever the configuration). Bank 4 has its code, the cache's sets and
# the lanes' tables, and the staging set from #7E00: 5.2K free before it
# since 2026-11-06, but only 170 bytes of it are offered (the rest kept for
# the road), as bank 7 keeps its room for the game. What does not fit
# (src/gen/trafleft.py)
# mkbush.py lays the same way in the fragments' free runs, then - in every
# CARn.BIN - in the road parts' hidden lines.
REGIONS = [("6", "RAM_C6", "#8000", 5430),     # bank 6, after the traffic's code
                                                # (all of it, since the hill
                                                # tables are shared: mkroad.py)
           ("f4", "RAM_C6", "FRAG4+FRAG_LEN", 21),      # fragment 4's end
           ("4", "RAM_C4", "STAGE_A", 170)]     # bank 4, after the lanes'
                                                # tables (main.asm)


def holes():
    """The row tables' pages in bank 6 (src/gen/roadrows.asm) end where
    their rows do, and mkroad.py includes src/gen/rowhole<n>.asm before each
    next page: [(n, where the page ends, bytes free)]."""
    out, first, size = [], None, 0
    for line in open(os.path.join(ROOT, "src", "gen", "roadrows.asm")):
        t = line.split(";")[0].strip()
        if t.startswith('INCLUDE "rowhole'):
            n = int(t[len('INCLUDE "rowhole'):].split(".")[0])
            free = (256 - size % 256) % 256 if first else 0
            out.append((n, "%s+%d" % (first, (size | 255) + 1) if first else None, free))
            first, size = None, 0
        elif not t or t.startswith(("ALIGN", "ASSERT")) or " EQU " in t:
            continue
        elif t.startswith("defb"):
            size += len(t[4:].split(","))
        elif t.startswith("defw"):
            size += 2 * len(t[4:].split(","))
        elif t.startswith("defs"):
            size += eval(t[4:].split(",")[0])  # (a number, or one less another)
        elif first is None:
            first = t
    return out


# bank 6's holes, after its region (src/gen/rowhole<n>.asm)
REGIONS[1:1] = [("rh%d" % n, "RAM_C6", end, free, "rowhole%d" % n)
                for n, end, free in holes() if free]
HOOKS = [n for n, end, free in holes()]


STEP_DX = range(-4, 5)          # tr_st<dx> (trafglue.asm)

# instruction: (bytes, time in NOPs) - the step's call with its routine
COST = {"ld ix": (4, 4), "ld sp,hl": (1, 2), "call tr_st": (3, 19), "call tr_stx": (3, 16),
        "ld bc": (3, 3), "add hl,bc": (1, 3), "bit 6,h": (2, 2), "call nz": (3, 3),
        "push de": (1, 4), "push iy": (2, 5), "push ix": (2, 5), "push bc": (1, 4),
        "ld b": (2, 2), "ld c": (2, 2), "ld c,e": (1, 1), "ld b,e": (1, 1),
        "ld c,iyl": (2, 2), "ld b,iyl": (2, 2), "ld de,(": (4, 6), "ld iy,(": (4, 6),
        "jp": (3, 3)}


def cost(text):
    k = max((k for k in COST if text.startswith(k)), key=len)
    return COST[k]


def piece_runs(rows):
    """(the empty lines before its first, [(first byte, bytes)] a line): a
    byte is 'P' for paint."""
    skip = 0
    while not rows[skip].strip("."):
        skip += 1
    rows = rows[skip:]
    while not rows[-1].strip("."):
        rows = rows[:-1]
    out = []
    for r in rows:
        assert r.strip("."), "an empty line inside a piece"
        xs = [i for i, c in enumerate(r) if c != "."]
        a, b = xs[0], xs[-1] + 1
        assert a % 2 == 0 and (b - a) % 4 == 0, (r, a, b)
        data = []
        for x in range(a, b, 2):
            p = r[x:x + 2]
            if T.PAINT in p:
                assert p == T.PAINT * 2, r
                data.append("P")
            else:
                data.append(m0_byte(PEN[T.LETTERS[p[0]]], PEN[T.LETTERS[p[1]]]))
        out.append((a // 2, data))
    return skip, out


def compile_lines(lines, ix, split=None, nxt=None):
    """The code for lines [(line from the car's top, first byte, bytes)],
    without its end: ix the word IX holds (None: none), split the line where
    its bottom's colour begins, nxt the line after the last ((first byte,
    bytes); None: none)."""
    code = []
    for i, (y, a, d) in enumerate(lines):
        odd = y & 1
        if y == split:
            code += ["    ld de,(tr_cw2)", "    ld iy,(tr_cw2+2)"]
        code.append("    ld sp,hl")
        n2 = lines[i + 1][1:] if i + 1 < len(lines) else nxt
        if n2 is not None:
            a2, d2 = n2
            dx = (a2 + len(d2)) - (a + len(d))
            if len(d) < 4:                      # one word: no interrupt
                code += ["    ld bc,#%04X" % ((0x800 + dx) & 0xFFFF), "    add hl,bc",
                         "    bit 6,h", "    call nz,tr_next_row"]
            elif dx in STEP_DX:
                code.append("    call tr_st%s" % ("m%d" % -dx if dx < 0 else "%d" % dx))
            else:
                code += ["    ld bc,#%04X" % ((0x800 + dx) & 0xFFFF), "    call tr_stx"]
        bc = None
        n = len(d)
        for j in range(n - 2, -1, -2):          # right to left
            lft, rgt = d[j], d[j + 1]
            if lft == "P" and rgt == "P":
                code.append("    push iy" if odd else "    push de")
                continue
            if lft != "P" and rgt != "P":
                v = rgt << 8 | lft
                if v == ix:
                    code.append("    push ix")
                    continue
                if bc == (rgt, lft):
                    pass
                elif bc is not None and bc[0] == rgt:
                    code.append("    ld c,#%02X" % lft)
                elif bc is not None and bc[1] == lft:
                    code.append("    ld b,#%02X" % rgt)
                else:
                    code.append("    ld bc,#%04X" % v)
                bc = (rgt, lft)
                code.append("    push bc")
                continue
            if lft == "P":                      # C the left byte, B the right
                code.append("    ld c,iyl" if odd else "    ld c,e")
                if bc is None or bc[0] != rgt:
                    code.append("    ld b,#%02X" % rgt)
                bc = (rgt, "P")
            else:
                code.append("    ld b,iyl" if odd else "    ld b,e")
                if bc is None or bc[1] != lft:
                    code.append("    ld c,#%02X" % lft)
                bc = ("P", lft)
            code.append("    push bc")
    return code


def size_of(code):
    return sum(cost(t.strip())[0] for t in code if t.startswith(" "))


def time_of(code):
    return sum(cost(t.strip())[1] for t in code if t.startswith(" "))


def groups():
    """The pieces in groups that may share their last lines - per size, a
    near one's tops and its bottoms, a further one's whole cars: (its name,
    its pieces (label, size index, kind, the line it is drawn from - from the
    car's top -, its lines [(line, first byte, bytes)]), its split - a whole
    car's: None else)."""
    out = []
    for k, s in enumerate(TRAFFIC_ART):
        if s["whole"]:
            b = next(iter(s["bottoms"].values()))
            out.append(("tr_s%d_cars" % k, [(t, 0, s["tops"][t] + b) for t in T.TOPS],
                        s["split"]))
            continue
        out.append(("tr_s%d_tops" % k, [(t, 0, s["tops"][t]) for t in T.TOPS], None))
        out.append(("tr_s%d_bottoms" % k,
                    [(b, s["split"], s["bottoms"][b]) for b in T.BOTTOMS], None))
    res = []
    for name, g, split in out:
        k = int(name[4:name.index("_", 4)])
        ms = []
        for kind, line0, rows in g:
            skip, runs = piece_runs(rows)
            ms.append(("tr_s%d_%s" % (k, kind), k, kind, line0,
                       [(line0 + skip + i, a, d) for i, (a, d) in enumerate(runs)]))
        res.append((name, ms, split))
    return res


def compile_group(name, ms, split, shared):
    """A group's code: its pieces, the last `shared` lines of them (the
    same in each) laid once after the last, the others going there with a
    JP. Returns (its lines, per piece (label, size index, kind, the lines
    before its first, where its first line's run ends - bytes from the
    car's left -, bytes, time))."""
    tail = ms[0][4][len(ms[0][4]) - shared:] if shared else []
    words = collections.Counter()
    for lines in [m[4][:len(m[4]) - shared] for m in ms] + [tail]:
        for y, a, d in lines:
            for j in range(0, len(d), 2):
                if "P" not in d[j:j + 2]:
                    words[d[j + 1] << 8 | d[j]] += 1
    ix = None
    if words:
        v, n = words.most_common(1)[0]
        if n >= 3:
            ix = v
    tcode = compile_lines(tail, ix, split) + ["    jp tr_done"] if shared else []
    tl = name + "_tail"
    code, recs = [], []
    for i, (label, k, kind, line0, lines) in enumerate(ms):
        head = lines[:len(lines) - shared]
        hc = compile_lines(head, ix, split, tail[0][1:] if shared else None)
        if any(t == "    push ix" for t in hc + tcode):
            hc.insert(0, "    ld ix,#%04X" % ix)
        if not shared:
            hc.append("    jp tr_done")
        elif i < len(ms) - 1:
            hc.append("    jp %s" % tl)
        code += [label] + hc
        a, d = lines[0][1:]
        recs.append((label, k, kind, lines[0][0] - line0, a + len(d),
                     size_of(hc + tcode), time_of(hc + tcode)))
    if shared:
        code += [tl] + tcode
    return code, recs


def units():
    """Every group's code, sharing what its pieces end with where that
    saves room: [(lines, bytes, per piece as compile_group's)]."""
    out = []
    for name, ms, split in groups():
        c = 0
        n = min(len(m[4]) for m in ms)
        while c < n - 1 and all(m[4][-1 - c] == ms[0][4][-1 - c] for m in ms):
            c += 1
        best = min((compile_group(name, ms, split, cc) for cc in {0, c}),
                   key=lambda u: size_of(u[0]))
        out.append((best[0], size_of(best[0]), best[1]))
    return out


def lay(code, runs, at):
    """Lay code (lines, labels not indented) into runs ([name, room,
    [lines]]) from run `at`, on from one to the next with a JP where it
    would run on past one's end. Returns the run it ends in, or None (and
    nothing laid) if they are full."""
    laid = [list(r[2]) for r in runs]
    room = [r[1] for r in runs]
    i, falls, labels = at, False, []
    for line in code:
        if not line.startswith(" "):
            labels.append(line)
            continue
        n = cost(line.strip())[0]
        ends = line.strip().startswith("jp ")
        while room[i] < n + (0 if ends else 3):
            if i + 1 >= len(runs):
                return None
            if falls:
                cont = "%s_c%d" % (code[0], i + 1)
                laid[i].append("    jp %s" % cont)
                room[i] -= 3
                labels.insert(0, cont)
            i += 1
        laid[i] += labels + [line]
        labels = []
        room[i] -= n
        falls = not ends
    for r, ln, rm in zip(runs, laid, room):
        r[1], r[2] = rm, ln
    return i


def place(us):
    """The units, biggest first, each in the configuration with the most
    room left: {configuration: its regions [name, room, [lines]]}, the
    configuration of each piece, and the units left over (for the
    fragments)."""
    by_cfg = collections.OrderedDict()
    for r in REGIONS:
        by_cfg.setdefault(r[1], []).append([r[0], r[3], []])
    cur = {cfg: 0 for cfg in by_cfg}
    cfg_of, left = {}, []
    for u in sorted(us, key=lambda u: -u[1]):
        for cfg in sorted(by_cfg, key=lambda c: -sum(r[1] for r in by_cfg[c][cur[c]:])):
            end = lay(u[0], by_cfg[cfg], cur[cfg])
            if end is not None:
                cur[cfg] = end
                break
        else:
            cfg = "0"
            left.append(u)
        for r in u[2]:
            cfg_of[r[0]] = cfg
    return by_cfg, cfg_of, left


def size_rows():
    """Per row (0..ROWS): the size a car on it is drawn at (None: not)."""
    return [S.traffic_size(r) for r in range(G.ROWS + 1)]


def main():
    us = units()
    ps = [r for u in us for r in u[2]]          # every piece, in the directory's order
    by_cfg, cfg_of, left = place(us)
    room = {}
    for cfg, regions in by_cfg.items():
        for name, rm, laid in regions:
            r = next(r for r in REGIONS if r[0] == name)
            end = r[2]
            room[name] = rm
            lines = [";; Generated by tools/mktrafcode.py - do not edit.",
                     ";; Traffic sprite pieces, region %s (%s)." % (name, cfg), "",
                     "trafcode_%s" % name] + laid + [
                     "trafcode_%s_end" % name,
                     "    ASSERT trafcode_%s_end <= %s" % (name, end)]
            fname = r[4] if len(r) > 4 else "trafcode_%s" % name
            open(os.path.join(ROOT, "src", "gen", fname + ".asm"), "w").write(
                "\n".join(lines) + "\n")
    for n in HOOKS:                     # (the pages with no room: none)
        if not any(len(r) > 4 and r[4] == "rowhole%d" % n for r in REGIONS):
            open(os.path.join(ROOT, "src", "gen", "rowhole%d.asm" % n), "w").write(
                ";; Generated by tools/mktrafcode.py - do not edit. (No room here.)\n")
    out = ['"""Generated by tools/mktrafcode.py - do not edit.', "",
           "The traffic's sprite pieces that are left for the fragments (mkbush.py",
           "lays them there with mktrafcode.lay): LEFT = [[asm line]], labels not",
           'indented."""', "", "LEFT = ["]
    for u in left:
        out.append("    [")
        out += ["        %r," % t for t in u[0]]
        out.append("    ],")
    out += ["]", ""]
    open(os.path.join(ROOT, "src", "gen", "trafleft.py"), "w").write("\n".join(out))

    rsize = size_rows()
    lines = [";; Generated by tools/mktrafcode.py - do not edit.",
             ";; The traffic's tables (bank 6): the sizes, their pieces, the rows",
             ";; and the colours.", ""]
    emit = lines.append
    emit("TR_SIZES    EQU %d" % len(TRAFFIC_ART))
    emit("TR_NEAR     EQU %d   ; the nearest sizes, in two pieces" % NEAR)
    emit("TR_ROW_MIN  EQU %d" % S.TRAFFIC_ROW_MIN)
    znear = next(z for z in range(TR_ZFAR, 0, -1)
                 if S.bush_row(z) and S.traffic_size(S.bush_row(z)) is not None
                 and S.traffic_size(S.bush_row(z)) < NEAR) + 1
    assert all(S.traffic_size(S.bush_row(z)) < NEAR for z in range(G.BUSH_ZNEAR, znear)
               if S.bush_row(z))
    emit("TR_ZNEARSIZE EQU %d   ; nearer than this, a car is at a near size" % znear)
    emit("")
    emit(";; per size: its width (bytes), its lines, its top's lines, its first")
    emit(";; piece's record (tr_pieces); then its left indicator with each bottom")
    emit(";; (BOTTOMS): its line from its top, its pixel from its left")
    emit(";; (scene.traffic_blinker)")
    emit("tr_sinfo")
    index = {p[0]: i for i, p in enumerate(ps)}
    for k, s in enumerate(TRAFFIC_ART):
        top = s["tops"][T.TOPS[0]]
        bottom = next(iter(s["bottoms"].values()))
        first = index["tr_s%d_%s" % (k, T.TOPS[0])]
        blink = [v for b in range(len(T.BOTTOMS)) for v in S.traffic_blinker(k, b)]
        emit("    defb %d,%d,%d,%d, %s   ; size %d: %d x %d pixels" % (
            len(top[0]) // 2, len(top) + len(bottom), s["split"], first * 5,
            ",".join(map(str, blink)), k, len(top[0]), len(top) + len(bottom)))
    emit("TR_SINFO_LEN EQU %d" % (4 + 2 * len(T.BOTTOMS)))
    emit("TR_SINFO_BLINK EQU 4")
    emit("TR_BLINK    EQU %d   ; frames_drawn's bit: an indicator lit" % S.TRAFFIC_BLINK)
    assert S.TRAFFIC_BLINK & (S.TRAFFIC_BLINK - 1) == 0
    lit = G.PEN[S.CAR_PEN[S.TRAFFIC_LIT]]
    emit("TR_LIT_L    EQU #%02X   ; its pixel lit: the left one of a byte" % G.m0_left(lit))
    emit("TR_LIT_R    EQU #%02X   ; the right one" % G.m0_right(lit))
    emit("")
    emit(";; per piece: its code, its RAM configuration (0: any), the lines before")
    emit(";; its first (from its top), where its first line's run ends (bytes from")
    emit(";; the car's left): a near size's tops (mktraffic.py TOPS) then its")
    emit(";; bottoms (BOTTOMS); a further size's whole cars, one a top")
    emit("tr_pieces")
    for p in ps:
        emit("    defw %s" % p[0])
        emit("    defb %s,%d,%d   ; %d bytes, %d us" % (cfg_of[p[0]], p[3], p[4], p[5], p[6]))
    emit("TR_PIECE_LEN EQU 5")
    emit("TR_TOPS     EQU %d   ; a near size's tops, then its bottoms" % len(T.TOPS))
    emit("TR_BOTTOMS  EQU %d" % len(T.BOTTOMS))
    assert len(ps) * 5 < 256
    emit("")
    emit("tr_rsize    ; per row: the size a car on it is drawn at - its record in")
    emit("            ; tr_sinfo (#FF: none)")
    vals = [0xFF if v is None else (4 + 2 * len(T.BOTTOMS)) * v for v in rsize]
    for j in range(0, len(vals), 16):
        emit("    defb " + ",".join("#%02X" % v for v in vals[j:j + 16]))
    lats = [(4, 0, "the inner right lane of four"), (4, 1, "the outer right lane of four"),
            (3, 0, "the right lane of three"), (2, 0, "the right lane of two")]
    for i, (lanes, lane, what) in enumerate(lats):
        emit("tr_lat%d    ; per row: a car's left in %s, bytes from the road's"
             % (i + 1, what))
        emit("    ; centre (the left lanes': -this - its width)")
        vals = []
        for r in range(G.ROWS + 1):
            if rsize[r] is None:
                vals.append(0)
                continue
            s = TRAFFIC_ART[rsize[r]]
            wb = len(s["tops"][T.TOPS[0]][0]) // 2
            vals.append(S.traffic_lefts(r, wb, lanes)[lane] & 0xFF)
        for j in range(0, len(vals), 16):
            emit("    defb " + ",".join("#%02X" % v for v in vals[j:j + 16]))
    emit("    ASSERT tr_lat4 == tr_lat1+%d" % (3 * (G.ROWS + 1)))
    assert 3 * (G.ROWS + 1) < 256
    # the lanes (scene.TRAFFIC_LANES): each one's table, from tr_lat1, and
    # 0 right of the middle, 1 left (mirrored), 2 the middle one of three
    L = S.TRAFFIC_LANES
    sel = []
    for lanes, way in L:
        if way == 0:
            sel += [0, 2]
            continue
        k = next(i for i, (n, l, w) in enumerate(lats) if n == lanes and l == abs(way) - 1)
        sel += [k * (G.ROWS + 1), 1 if way < 0 else 0]
    emit("tr_lsel     ; per lane (TR_LANE): its tr_lat table, from tr_lat1, and 0")
    emit("            ; right of the middle, 1 left, 2 the middle one of three")
    emit("    defb " + ",".join(str(v) for v in sel))
    emit("tr_lcount   ; per lane: the road's lanes it is one of")
    emit("    defb " + ",".join(str(n) for n, w in L))
    # where a car is: its lane's middle, in twelfths of the road's half
    # (four: 3, 9; three: 0, 8; two: 6)
    mid = {(4, 1): 3, (4, 2): 9, (3, 0): 0, (3, 1): 8, (2, 1): 6}
    pos = [mid[(n, abs(w))] * (1 if w >= 0 else -1) for n, w in L]
    emit("tr_spawn    ; per lanes 2, 3, 4 and two random bits: the lane a car")
    emit("            ; comes in")
    spawn = {2: [7, 8, 7, 8], 3: [4, 5, 6, 5], 4: [0, 1, 2, 3]}
    emit("    defb " + ",".join(str(v) for n in (2, 3, 4) for v in spawn[n]))
    assert all(L[v][0] == n for n in spawn for v in spawn[n])
    emit("tr_chg      ; per lane, and bit 3 of a random byte: the lane next to it")
    emit("            ; it may change to (the other on its side, or the other")
    emit("            ; side's inner one)")
    chg = []
    for i, (n, w) in enumerate(L):
        mine = [j for j, (m, v) in enumerate(L) if m == n and j != i]
        side = [j for j in mine if pos[j] * pos[i] > 0] or \
            [min(mine, key=lambda j: abs(pos[j] - pos[i]))]
        inner = [j for j in mine if abs(L[j][1]) == 1 and pos[j] * pos[i] < 0]
        if n == 3 and w == 0:
            inner = [j for j in mine if pos[j] > 0]  # (the middle one: the right)
        chg += [side[0], inner[0] if (n == 4 and abs(w) == 1) or (n == 3 and w == 0)
                else side[0]]
    emit("    defb " + ",".join(str(v) for v in chg))
    emit("tr_merge    ; per lane and lanes 4, 3, 2 there: the nearest lane of those")
    emit("            ; (its middle's; the one towards the road's middle if two)")
    merge = []
    for i, (n, w) in enumerate(L):
        for m in (4, 3, 2):
            them = [j for j, (k, v) in enumerate(L) if k == m]
            merge.append(min(them, key=lambda j: (abs(pos[j] - pos[i]), abs(pos[j]),
                                                   pos[j] < 0)))
    emit("    defb " + ",".join(str(v) for v in merge))
    for n in (2, 3, 4):
        emit("tr_edge%d    ; per row: how far either side of its centre its road reaches"
             % n)
        emit("            ; with %d lanes" % n)
        vals = [S.traffic_edge(r, n) if r else 0 for r in range(G.ROWS + 1)]
        for j in range(0, len(vals), 16):
            emit("    defb " + ",".join("%d" % v for v in vals[j:j + 16]))
    emit("    ASSERT tr_edge3 == tr_edge2+%d && tr_edge4 == tr_edge3+%d"
         % (G.ROWS + 1, G.ROWS + 1))
    emit("")
    emit(";; per curve level 1..CURVE_K, per template group (NGROUPS, bush_rh's")
    emit(";; order): how far right the level moves it")
    emit("tr_cs")
    groups = list(dict.fromkeys(G.curve_group(r) for r in range(1, G.ROWS + 1)))
    for k in range(1, G.CURVE_K + 1):
        vals = [G.curve_shift(k, next(r for r in range(1, G.ROWS + 1) if G.curve_group(r) == g))
                for g in groups]
        assert all(0 <= v < 128 for v in vals)
        for j in range(0, len(vals), 17):
            emit("    defb " + ",".join("%d" % v for v in vals[j:j + 17]))
    emit("    ASSERT $ - tr_cs == CURVE_K * NGROUPS")
    emit("")
    emit(";; the colours: the even lines' byte, the odd lines' (a car's record has")
    emit(";; its colours' offsets)")
    emit("tr_colours")
    for c in COLOURS:
        pens = c * 2 if len(c) == 1 else c
        p1, p2 = PEN[pens[0]], PEN[pens[1]]
        emit("    defb #%02X,#%02X   ; %s" % (m0_byte(p1, p2), m0_byte(p2, p1), "/".join(c)))
    emit("")
    for r in REGIONS:
        emit(";; region %s: %d of %d bytes" % (r[0], r[3] - room[r[0]], r[3]))
    if left:
        emit(";; in the fragments: %d bytes" % sum(u[1] for u in left))
    open(os.path.join(ROOT, "src", "gen", "traffic.asm"), "w").write("\n".join(lines) + "\n")

    for p in ps:
        print("traffic: %-16s %4d bytes %5d us" % (p[0], p[5], p[6]))
    print("traffic: %d bytes of code; room left %s; %d bytes for the fragments" % (
        sum(u[1] for u in us), ", ".join("%s %d" % kv for kv in room.items()),
        sum(u[1] for u in left)))


if __name__ == "__main__":
    main()
