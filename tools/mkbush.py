#!/usr/bin/env python3
"""Compile the bushes beside the road: src/gen/bush.asm, bushdata.asm and
bushcode.asm.

    bush.asm      (bank 7) the bushes along the track, constants
    bushdata.asm  (common fragments 8-15, page 2) the tables a bush is
                  projected with, the sprite directory, each sprite's lines
                  as data
    bushcode.asm  (page 1, #x600-#x7FF of each 2K block: RAM_C1) each sprite
                  as code

scene.py has the art, the layout and the projection the engine has to match;
src/bush.asm draws them.

The per-row tables start on a 128-byte boundary, so a row is an OR away:
the sprite of each size class, the lateral offset of each lateral class,
the road's centre at each curve level (the left curves' are these
mirrored). A sprite line is one run of a whole number of pairs of bytes.

A sprite's data, for the copying way (src/bush.asm), is per line

    defb a          its first byte, from the sprite's left
    defb n          its bytes
    defb bytes...

A sprite's code, for a bush all on the screen, is per line, entered with HL
at the right end of the first line's run on the screen:

    ld sp,hl
    ei              an interrupt's return address lands where the first
    ld bc,step      PUSH goes; step = #800 + the next line's end - this
    di              line's
    add hl,bc
    bit 6,h         past the character row's last line: on to the next
    call nz,bush_next_row   (its return address lands there too)
    pushes          right to left: DE, IX, IY hold the sprite's most used
                    pairs, BC the rest

and the last line has no step; then JP bush_spr_done.
"""

import collections
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cpcgfx as G
import scene as S

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FRAG_LEN = 0x2C0
FRAG_FIRST = 8                  # fragments 8-15: page 2, #x540-#x7FF
FRAG_COUNT = 8
CODE_CHUNKS = [0x4600 + 0x800 * b for b in range(8)]   # page 1 gaps (the
CHUNK_LENS = [0x200] * 7 + [0x100]      # eighth's first half, #7E00, is the
                                        # cache's: cache.asm)
SINFO_FIELDS = ["half width", "width", "first line's end", "height",
                "how its box is erased", "code", "data"]


def frag_addr(k):
    return 0x8540 + (k - FRAG_FIRST) * 0x800


def sprite_lines(k):
    """Sprite k's lines: (first byte, bytes)."""
    return S.BUSH_SPRITES[k][1]


def sprite_data(k):
    out = []
    for a, data in sprite_lines(k):
        out += [a, len(data)] + data
    return out


# --- code -------------------------------------------------------------------
SIZE = {"ld de": 3, "ld ix": 4, "ld iy": 4, "ld sp,hl": 1, "ei": 1, "di": 1,
        "ld bc": 3, "add hl,bc": 1, "bit 6,h": 2, "call nz": 3, "push bc": 1,
        "push de": 1, "push ix": 2, "push iy": 2, "ld b": 2, "ld c": 2, "jp": 3,
        "ld hl": 3, "ld h": 2, "ld l": 2, "ld d": 2, "ld e": 2, "push hl": 1,
        "add hl,sp": 1, "nop": 1}
TIME = {"ld de": 3, "ld ix": 4, "ld iy": 4, "ld sp,hl": 2, "ei": 1, "di": 1,
        "ld bc": 3, "add hl,bc": 3, "bit 6,h": 2, "call nz": 3, "push bc": 4,
        "push de": 4, "push ix": 5, "push iy": 5, "ld b": 2, "ld c": 2, "jp": 3,
        "ld hl": 3, "ld h": 2, "ld l": 2, "ld d": 2, "ld e": 2, "push hl": 4,
        "add hl,sp": 3, "nop": 1}


def kind(text):
    for k in sorted(SIZE, key=len, reverse=True):
        if text.startswith(k):
            return k
    raise ValueError(text)


def sprite_code(k):
    """Sprite k as code: [(instruction, step line or None)], and its time."""
    return lines_code(sprite_lines(k))


def lines_code(spans):
    """A sprite's lines (first byte, bytes) as code, and its time."""
    lines = []                          # (run's right end, pairs right to left)
    for a, data in spans:
        n = len(data)
        assert n and not n & 1
        lines.append((a + n, [data[n - 1 - 2 * j] << 8 | data[n - 2 - 2 * j]
                              for j in range(n // 2)]))
    count = collections.Counter(v for r, pairs in lines for v in pairs)
    regs = {}
    for (v, c), reg in zip(count.most_common(3), ("de", "ix", "iy")):
        if c >= (2 if reg == "de" else 3):
            regs[v] = reg
    code = [("ld %s,#%04X" % (reg, v), None) for v, reg in regs.items()]
    for i, (r, pairs) in enumerate(lines):
        code.append(("ld sp,hl", None))
        bc = None
        if i < len(lines) - 1:
            step = (0x800 + lines[i + 1][0] - r) & 0xFFFF
            code += [("ei", None), ("ld bc,#%04X" % step, None), ("di", None),
                     ("add hl,bc", None), ("bit 6,h", None),
                     ("call nz,bush_next_row", None)]
        for v in pairs:
            if v in regs:
                code.append(("push " + regs[v], None))
                continue
            if v != bc:
                if bc is not None and v >> 8 == bc >> 8:
                    code.append(("ld c,#%02X" % (v & 0xFF), None))
                elif bc is not None and v & 0xFF == bc & 0xFF:
                    code.append(("ld b,#%02X" % (v >> 8), None))
                else:
                    code.append(("ld bc,#%04X" % v, None))
                bc = v
            code.append(("push bc", None))
    code.append(("jp bush_spr_done", None))
    return code, sum(TIME[kind(t)] for t, s in code)


def line_addr(y):
    """Line y's address in buffer 0 (the road part's memory: line 160 on)."""
    return 0x8000 + (y & 7) * 0x800 + ((y >> 3) - 20) * 96


def car_code(spans, y0, x0):
    """The car as code: lines (first byte, bytes) from line y0, byte x0 -
    always there, so each line's step is known, a character row's end and
    all. Entered with HL at the right end of the first line's run (lines
    with none are passed over); after a line SP is at the left end of its
    run, and the next line's right end is SP + its step (LD HL / ADD HL,SP
    / LD SP,HL). Some registers hold the
    most used pairs throughout (loaded once), the others are loaded as
    needed - the one whose pair is needed again last (HL's is gone at the
    next line); the quickest way of those tried. Interrupts get one
    instruction's chance a line, with SP at the right end of the run:
    [(instruction, None)], and its time."""
    lines = []                          # (run's right end, its bytes, pairs
    for i, (a, data) in enumerate(spans):   # right to left)
        n = len(data)
        assert not n & 1
        if not n:
            continue
        lines.append((line_addr(y0 + i) + x0 + a + n, n,
                      [data[n - 1 - 2 * j] << 8 | data[n - 2 - 2 * j]
                       for j in range(n // 2)]))
    common = [v for v, c in collections.Counter(
        v for e, n, pairs in lines for v in pairs).most_common(5)]
    best = None
    for fixed_regs in (("de",), ("de", "ix"), ("de", "ix", "iy"), ("de", "bc"),
                       ("de", "bc", "ix"), ("de", "bc", "ix", "iy")):
        fixed = dict(zip(common, fixed_regs))
        dyn = [r for r in ("bc", "de", "hl") if r not in fixed_regs]
        code = _car_code(lines, fixed, dyn)
        us = sum(TIME[kind(t)] for t, st in code)
        if best is None or us < best[1]:
            best = (code, us)
    return best


def _car_code(lines, fixed, dyn):
    code = [("ld %s,#%04X" % (reg, v), None) for v, reg in fixed.items()]
    flat = [v for e, n, pairs in lines for v in pairs]
    ends = []
    for e, n, pairs in lines:
        ends += [len(ends) + len(pairs)] * len(pairs) if not ends else \
            [ends[-1] + len(pairs)] * len(pairs)
    regs = {r: None for r in dyn}
    never = len(flat) + 1

    def next_use(w, at, until):
        for j in range(at, until):
            if flat[j] == w:
                return j
        return never

    at = 0
    for i, (e, n, pairs) in enumerate(lines):
        if i == 0:
            code.append(("ld sp,hl", None))
        else:
            pe, pn, pp = lines[i - 1]
            code += [("ld hl,#%04X" % ((e - (pe - pn)) & 0xFFFF), None),
                     ("add hl,sp", None), ("ld sp,hl", None)]
        if "hl" in regs:
            regs["hl"] = None
        code.append(("ei", None))
        window = len(code)              # the next instruction, then DI
        for v in pairs:
            end = ends[at]
            at += 1
            if v in fixed:
                code.append(("push " + fixed[v], None))
                continue
            r = next((r for r, w in regs.items() if w == v), None)
            if r is None:
                def gone(r):            # when its pair is needed next
                    w = regs[r]
                    if w is None:
                        return never + 1
                    return next_use(w, at, end if r == "hl" else len(flat))
                r = max(regs, key=gone)
                w = regs[r]
                if w is not None and w >> 8 == v >> 8:
                    code.append(("ld %s,#%02X" % (r[1], v & 0xFF), None))
                elif w is not None and w & 0xFF == v & 0xFF:
                    code.append(("ld %s,#%02X" % (r[0], v >> 8), None))
                else:
                    code.append(("ld %s,#%04X" % (r, v), None))
                regs[r] = v
            code.append(("push " + r, None))
        if kind(code[window][0]).startswith("push"):
            code.insert(window, ("nop", None))
        code.insert(window + 1, ("di", None))
    code.append(("jp bush_spr_done", None))
    return code


class Chunks:
    """The page 1 gaps, filled one after the other; code runs on from one
    to the next with a JP."""

    def __init__(self):
        self.out = []                   # (chunk, [lines])
        self.used = [0] * len(CODE_CHUNKS)
        self.cur = 0
        self.out = [[] for _ in CODE_CHUNKS]

    def room(self):
        return CHUNK_LENS[self.cur] - self.used[self.cur]

    def code(self, label, code):
        if self.room() < 8:             # (no room to start, or to jump on)
            self.next_chunk(jump=False)
        self.out[self.cur].append(label)
        for text, step in code:
            n = SIZE[kind(text)]
            if self.room() < n + 3 and not (text == "jp bush_spr_done"
                                            and self.room() >= n):
                self.next_chunk(jump=True)
            if step is not None:
                self.out[self.cur].append("%s_s%d" % (label, step))
            self.out[self.cur].append("    " + text)
            self.used[self.cur] += n

    def next_chunk(self, jump):
        if self.cur + 1 >= len(CODE_CHUNKS):
            raise SystemExit("bushes: no room left in page 1 for the code")
        if jump:
            self.out[self.cur].append("    jp #%04X" % self.start(self.cur + 1))
            self.used[self.cur] += 3
        self.cur += 1

    def data(self, label, words):
        """A table of words, in one piece, in the first chunk it fits in
        (before any code)."""
        n = 2 * len(words)
        for c in range(len(CODE_CHUNKS)):
            if CHUNK_LENS[c] - self.used[c] >= n:
                self.out[c].append(label)
                for j in range(0, len(words), 8):
                    self.out[c].append("    defw " + ",".join(words[j:j + 8]))
                self.used[c] += n
                return
        raise SystemExit("bushes: no room left in page 1 for " + label)

    def bytes(self, label, comment, data):
        """Bytes, in one piece, in the first chunk with room left."""
        for c in range(len(CODE_CHUNKS)):
            if CHUNK_LENS[c] - self.used[c] >= len(data):
                self.out[c].append("%s   ; %s" % (label, comment))
                for j in range(0, len(data), 16):
                    self.out[c].append("    defb " + ",".join("#%02X" % v
                                                              for v in data[j:j + 16]))
                self.used[c] += len(data)
                return
        raise SystemExit("bushes: no room left for " + label)

    def free(self):
        return sum(n - u for n, u in zip(CHUNK_LENS, self.used))

    @staticmethod
    def start(c):
        """Where chunk c's room starts: the eighth's second half."""
        return CODE_CHUNKS[c] + 0x200 - CHUNK_LENS[c]


# --- the fragments ----------------------------------------------------------
class Space:
    """The fragments' free bytes: aligned halves of pages, and runs."""

    def __init__(self):
        self.halves = []                # 128-byte aligned, free
        self.runs = []                  # (start, length) free, any alignment
        for k in range(FRAG_FIRST, FRAG_FIRST + FRAG_COUNT):
            a = frag_addr(k)
            self.runs.append((a, 0xC0))
            self.halves += [a + 0xC0, a + 0x140, a + 0x1C0, a + 0x240]
        self.placed = []                # (address, label, comment, bytes)

    def page(self, label, comment, data):
        for h in self.halves:
            if h & 0xFF == 0 and h + 0x80 in self.halves:
                self.halves.remove(h)
                self.halves.remove(h + 0x80)
                self.placed.append((h, label, comment, data))
                if len(data) < 0x100:
                    self.runs.append((h + len(data), 0x100 - len(data)))
                return h
        raise SystemExit("bushes: no page left for " + label)

    def half(self, label, comment, data):
        assert len(data) <= 0x80
        h = self.halves.pop(0)
        self.placed.append((h, label, comment, data))
        if len(data) < 0x80:
            self.runs.append((h + len(data), 0x80 - len(data)))
        return h

    def anywhere(self, label, comment, data):
        """Unaligned data, in the smallest free stretch it fits in (the free
        halves now count as runs too)."""
        n = len(data)
        free = sorted(self.runs + [(h, 0x80) for h in self.halves])
        self.halves = []
        merged = []
        for a, ln in free:
            if merged and merged[-1][0] + merged[-1][1] == a:
                merged[-1] = (merged[-1][0], merged[-1][1] + ln)
            elif ln:
                merged.append((a, ln))
        self.runs = merged
        fits = [i for i, (a, ln) in enumerate(self.runs) if ln >= n]
        if not fits:
            raise SystemExit("bushes: no room for " + label)
        i = min(fits, key=lambda i: self.runs[i][1])
        a, ln = self.runs[i]
        self.runs[i] = (a + n, ln - n)
        self.placed.append((a, label, comment, data))
        return a

    def free(self):
        return sum(ln for a, ln in self.runs) + 0x80 * len(self.halves)

    def take_runs(self, below):
        """All that is left below address `below`, as (start, length) runs in
        address order - for code (FragCode); it is then used."""
        free = sorted(self.runs + [(h, 0x80) for h in self.halves])
        merged = []
        for a, ln in free:
            if merged and merged[-1][0] + merged[-1][1] == a:
                merged[-1] = (merged[-1][0], merged[-1][1] + ln)
            elif ln:
                merged.append((a, ln))
        out = [(a, min(ln, below - a)) for a, ln in merged if a < below]
        self.halves = []
        self.runs = [(a, ln) for a, ln in merged if a >= below]
        return out


class CodePiece:
    """Code placed in a fragment (FragCode): its lines and its size."""

    def __init__(self):
        self.lines = []
        self.size = 0

    def __len__(self):
        return self.size


class FragCode:
    """Code in the fragments' free runs, filled one after the other like
    Chunks: code runs on from one to the next with a JP."""

    def __init__(self, sp, runs):
        self.runs = [(a, ln) for a, ln in runs if ln >= 16]
        self.sp = sp
        self.cur = -1
        self.next_run()

    def next_run(self):
        self.cur += 1
        if self.cur >= len(self.runs):
            raise SystemExit("bushes: no room left in the fragments for the car")
        self.piece = CodePiece()
        a, ln = self.runs[self.cur]
        self.left = ln
        self.sp.placed.append((a, None, None, self.piece))

    def code(self, label, code):
        if self.left < 8:
            self.next_run()
        self.piece.lines.append(label)
        for text, step in code:
            n = SIZE[kind(text)]
            if self.left < n + 3:
                self.piece.lines.append("    jp #%04X" % self.runs[self.cur + 1][0]
                                        if self.cur + 1 < len(self.runs) else "    ?")
                self.piece.size += 3
                self.next_run()
            assert step is None
            self.piece.lines.append("    " + text)
            self.piece.size += n
            self.left -= n


def main():
    nspr = len(G.BUSH_H)
    assert nspr <= 16                   # the directory's columns
    maxw = max(len(d) for k in range(nspr) for a, d in sprite_lines(k))
    box = max(wb for wb, spans in S.BUSH_SPRITES)
    rows = range(G.ROWS + 1)
    sp = Space()

    # bushcode.asm: the sprites' code, smallest first, as many as there is
    # room for; the rest are only copied
    cars = [car_code(S.car_runs(v), S.CAR_Y, S.CAR_X // 2) for v in range(3)]

    def build(ks):
        ch = Chunks()
        ch.code("car_code0", cars[0][0])        # (the car first: it is drawn
                                                # most; turning right: FragCode)
        out = {}
        for k in ks:
            code, us = sprite_code(k)
            out[k] = [code, us, sum(SIZE[kind(t)] for t, s in code)]
        for k in ks:
            ch.code("bush_c%d" % k, out[k][0])
        ch.code("car_code1", cars[1][0])        # (and turning left after them)
        return ch, out
    n = nspr
    while True:
        try:
            ch, codes = build(range(n))
            break
        except SystemExit:
            n -= 1
    # bushdata.asm
    sp.page("bush_rz1", "the row a bush zr ahead stands on, zr < 512: zr / 2",
            [G.bush_row(2 * i) for i in range(256)])
    lt = []
    for y in range(160, 272):
        a = 0x8000 + (y & 7) * 0x800 + ((y >> 3) - 20) * 96
        lt += [a & 0xFF, a >> 8]
    sp.page("bush_ltab", "per line from ROAD_AREA_Y: its address in buffer 0", lt)
    sp.page("bush_sinfo", "per sprite, 16 bytes: " + ", ".join(SINFO_FIELDS),
            [0] * 256)
    sp.half("bush_rz2", "... zr >= 512: (zr - 512) / 8",
            [G.bush_row(512 + 8 * i) for i in range((G.BUSH_ZFAR - 512) // 8)])
    rtop = []
    for level in range(S.HILL_LEVELS):
        h = min(S.level_hill(level), S.HILL_MAX)
        rtop.append(next(r for r in S.project(h) if r))
    sp.half("bush_rtop", "per hill level: the furthest row in sight", rtop)
    for size in range(len(G.BUSH_SIZES)):
        sp.half("bush_spr%d" % size, "size class %d, per row: its sprite's record "
                "(#FF none)" % size,
                [0xFF if r == 0 or G.bush_sprite_of(size, r) is None
                 else 16 * G.bush_sprite_of(size, r) for r in rows])
    for c in range(len(G.BUSH_LATS)):
        for side, name in ((1, "R"), (-1, "L")):
            sp.half("bush_lat%s%d" % (name, c), "lateral class %d, %s, per row: bytes "
                    "from the road's centre (signed, at most 127)"
                    % (c, "right" if side > 0 else "left"),
                    [side * min(G.bush_lat(c, r), 127) & 0xFF for r in rows])
    groups = list(dict.fromkeys(G.curve_group(r) for r in range(1, G.ROWS + 1)))
    sp.half("bush_rh", "per row: its template group's lane, #CD + g, for road_x's "
            "share of it (cache.asm: rd_gp)",
            [0xCD] + [0xCD + groups.index(G.curve_group(r)) for r in range(1, G.ROWS + 1)])
    for k in range(G.CURVE_K + 1):
        cx = [G.bush_centre(k, r) for r in rows]
        assert all(0 <= v < 128 for v in cx)
        sp.half("bush_cx%d" % k, "curve level %d, per row: the road's centre" % k, cx)
    for k in sorted(range(nspr), key=lambda k: -len(sprite_data(k))):
        label, comment = "bush_d%d" % k, "sprite %d: %d lines" % (k, G.BUSH_H[k])
        try:
            sp.anywhere(label, comment, sprite_data(k))
        except SystemExit:              # what is left of page 1
            ch.bytes(label, comment, sprite_data(k))

    # the car turning right: code in what is left of fragments 8-14
    # (road15.asm has the rest of fragment 15)
    fc = FragCode(sp, sp.take_runs(frag_addr(FRAG_FIRST + FRAG_COUNT - 1)))
    fc.code("car_code2", cars[2][0])

    lines = [";; Generated by tools/mkbush.py - do not edit.",
             ";; The bush sprites as code (see mkbush.py), and what else does not fit",
             ";; in the fragments, in page 1 beside the HUDs: #x600-#x7FF of each 2K",
             ";; block, seen at #4000 with RAM_C1.",
             ";; BOOT.BIN has them where they run.", ""]
    for c, chunk in enumerate(CODE_CHUNKS):
        if not ch.out[c]:
            continue
        lines.append("    ORG #%04X" % ch.start(c))
        lines += ch.out[c]
        lines.append("    ASSERT $ <= #%04X" % (chunk + 0x200))
    open(os.path.join(ROOT, "src", "gen", "bushcode.asm"), "w").write(
        "\n".join(lines) + "\n")

    lines = [";; Generated by tools/mkbush.py - do not edit.",
             ";; The tables a bush is projected with and the bush sprites as data, in",
             ";; common fragments %d-%d (page 2: mapped whatever the bank)."
             % (FRAG_FIRST, FRAG_FIRST + FRAG_COUNT - 1), ""]
    emit = lines.append
    for k in range(FRAG_FIRST, FRAG_FIRST + FRAG_COUNT):
        base = frag_addr(k)
        here = sorted(p for p in sp.placed if base <= p[0] < base + FRAG_LEN)
        emit("    ORG #%04X,FRAG_ST%d" % (base, k))
        at = base
        for a, label, comment, data in here:
            if a > at:
                emit("    defs %d,0" % (a - at))
            if isinstance(data, CodePiece):
                lines += data.lines
                at = a + len(data)
                continue
            emit("%s   ; %s" % (label, comment))
            if label == "bush_sinfo":
                for s in range(16):
                    if s >= nspr:
                        emit("    defs 16,0")
                        continue
                    wb, spans = S.BUSH_SPRITES[s]
                    a0, d0 = spans[0]
                    assert s in codes           # (bush.asm has no way for
                    code = "bush_c%d" % s       # a sprite without code)
                    emit("    defb %d,%d,%d,%d   ; sprite %d" % (wb // 2, wb, a0 + len(d0),
                                                               len(spans), s))
                    emit("    defw be_r%d,%s,bush_d%d" % (wb // 2, code, s))
                    emit("    defs 6,0")
            else:
                for j in range(0, len(data), 16):
                    emit("    defb " + ",".join("#%02X" % v for v in data[j:j + 16]))
            at = a + len(data)
        if k == FRAG_FIRST + FRAG_COUNT - 1:
            emit("bushdata_end              ; (the rest of the fragment: road.asm)")
        emit("    ASSERT $ <= #%04X" % (base + FRAG_LEN))
    for a, label, comment, data in sp.placed:
        if label and label.startswith(("bush_rz", "bush_rtop", "bush_spr", "bush_lat", "bush_cx",
                                       "bush_rh")):
            emit("    ASSERT (%s & #7F) == 0" % label)
    for label in ("bush_rz1", "bush_ltab", "bush_sinfo"):
        emit("    ASSERT (%s & #FF) == 0" % label)
    open(os.path.join(ROOT, "src", "gen", "bushdata.asm"), "w").write(
        "\n".join(lines) + "\n")

    # --- bank 7: constants, the layout ---
    lines = [";; Generated by tools/mkbush.py - do not edit.", ""]
    emit = lines.append
    emit("BUSH_SPRITES  EQU %d" % nspr)
    emit("BUSH_MAXW     EQU %d   ; bytes in a sprite's longest line" % maxw)
    emit("BUSH_BOX      EQU %d   ; the widest sprite, bytes (even)" % box)
    emit("BUSH_ZNEAR    EQU %d" % G.BUSH_ZNEAR)
    emit("BUSH_ZFAR     EQU %d" % G.BUSH_ZFAR)
    emit("BUSH_MAX      EQU %d   ; bushes drawn at most" % G.BUSH_MAX)
    emit("BUSH_PERIOD   EQU %d   ; the track loops" % G.TRACK_PERIOD)
    emit("BUSH_HILL_MAX EQU %d" % S.HILL_MAX)
    emit("")
    zvis = [G.bush_zvis(size) for size in range(len(G.BUSH_SIZES))]
    assert G.BUSH_ZFAR & 0xFF == 0 and max(zvis) <= G.BUSH_ZFAR
    P = G.TRACK_PERIOD
    bushes = S.BUSHES
    emit(";; the bushes along the track, by depth: defw z; its size class's sprite")
    emit(";; table; its lateral class's offset table for its side")
    emit("BUSH_ENTRY    EQU 6")
    emit("bush_tab")
    for z, side, size, lat in bushes:
        emit("    defw %d,bush_spr%d,bush_lat%s%d" % (z, size, "R" if side > 0 else "L", lat))
    starts = sorted(((z - zvis[size] + 1) % P, i)
                    for i, (z, side, size, lat) in enumerate(bushes))
    emit(";; where each comes into reach (the first zcam its size class draws it")
    emit(";; at), in that order: defw that, the bush")
    emit("bush_starts")
    for zs, i in starts:
        emit("    defw %d,bush_tab+%d*BUSH_ENTRY" % (zs, i))
    emit("bush_starts_end")
    # the active list at zcam 0, and the next to come into reach; then the
    # same as bush.asm does it, for every zcam over three laps
    def zr(i, zcam):
        return (bushes[i][0] - zcam) % P
    head = next((j for j, (zs, i) in enumerate(starts) if zs > 0), 0)
    act = sorted((i for i, b in enumerate(bushes) if G.BUSH_ZNEAR <= b[0] < zvis[b[2]]),
                 key=lambda i: zr(i, 0))
    act0, head0, most = list(act), head, len(act)
    for zcam in range(1, 3 * P):
        while (zcam - starts[head][0]) % P < P // 2:
            i = starts[head][1]
            act.append(i)
            act.sort(key=lambda j: zr(j, zcam))
            head = (head + 1) % len(starts)
        while act and not G.BUSH_ZNEAR <= zr(act[0], zcam) < P // 2:
            act.pop(0)
        want = sorted((i for i, b in enumerate(bushes)
                       if G.BUSH_ZNEAR <= zr(i, zcam) < zvis[b[2]]), key=lambda i: zr(i, zcam))
        assert act == want, (zcam, act, want)
        most = max(most, len(act))
    BUSH_RMAX = most + 1
    emit(";; the bushes in reach (bush_draw): how many, nearest first, at the start;")
    emit(";; and the next to come into reach")
    emit("BUSH_RMAX     EQU %d   ; in reach at most (%d over a lap)" % (BUSH_RMAX, most))
    emit("bush_nreach")
    emit("    defb %d" % len(act0))
    emit("bush_reach")
    words = ["bush_tab+%d*BUSH_ENTRY" % i for i in act0] + ["0"] * (BUSH_RMAX - len(act0))
    emit("    defw " + ",".join(words))
    emit("    ASSERT hi(bush_reach) == hi($-1)")
    emit("bush_head")
    emit("    defw bush_starts+%d*4" % head0)
    emit("BUSH_COUNT    EQU %d" % len(S.BUSHES))
    # the lines at the car's top whose runs differ from view to view: a
    # buffer that last showed another view has them drawn whole (car_lines)
    ext = [[(a, a + len(d)) for a, d in S.car_runs(v)] for v in range(3)]
    differ = [i for i in range(S.CAR_H) if len({e[i] for e in ext}) > 1]
    car_top = max(differ) + 1 if differ else 0
    emit("CAR_Y         EQU %d   ; the car's top line" % S.CAR_Y)
    emit("CAR_TOP       EQU %d   ; its lines from there that differ from view to view"
         % car_top)
    emit(";; per car_view (straight, turning left, turning right): where the")
    emit(";; car's first line's run ends in buffer 0, and its code")
    emit("car_views")
    for v in range(3):
        y, (a0, d0) = next((y, r) for y, r in enumerate(S.car_runs(v)) if r[1])
        end0 = line_addr(S.CAR_Y + y) + S.CAR_X // 2 + a0 + len(d0)
        emit("    defw #%04X,car_code%d" % (end0, v))
    emit("")
    emit(";; per curve level 0..CURVE_K: its centre table")
    emit("bush_cxs")
    emit("    defw " + ",".join("bush_cx%d" % i for i in range(G.CURVE_K + 1)))
    emit("")
    open(os.path.join(ROOT, "src", "gen", "bush.asm"), "w").write(
        "\n".join(lines) + "\n")
    print("bushes: %d on the track, %d sprites, code for %d (%d bytes left in page 1);"
          " %d bytes of fragments %d-%d left"
          % (len(S.BUSHES), nspr, len(codes), ch.free(),
             sp.free(), FRAG_FIRST, FRAG_FIRST + FRAG_COUNT - 1))
    for v, (car, car_us) in enumerate(cars):
        print("  the car, view %d: %d lines, %d bytes of code, %d us"
              % (v, S.CAR_H, sum(SIZE[kind(t)] for t, st in car), car_us))
    for k, (code, us, size) in codes.items():
        print("  sprite %2d: %2d lines, %3d bytes of code, %4d us" % (k, G.BUSH_H[k], size, us))


if __name__ == "__main__":
    main()
