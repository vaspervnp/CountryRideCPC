#!/usr/bin/env python3
"""Compile the bushes beside the road: src/gen/bush.asm, bushdata.asm and
bushcode.asm.

    bush.asm      (bank 7) the bushes along the track, constants
    bushdata.asm  (common fragments 8-15, page 2) the tables a bush is
                  projected with, the sprite directory, each sprite's lines
                  as data
    bushcode.asm  (page 1, #x600-#x7FF of each 2K block: RAM_C1) each sprite
                  as code (but one, in the fragments, if there is no room)
    cars.asm      CAR0.BIN-CAR3.BIN: each car's own code and car_views,
                  which boot.asm puts in place of the first car's (the
                  loader loads the picked one's)

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
import copy
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cpcgfx as G
import scene as S
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "gen"))
try:
    from trafleft import LEFT as TRAFLEFT       # (tools/mktrafcode.py)
except ImportError:
    TRAFLEFT = []
from mktrafcode import lay  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FRAG_LEN = 0x2C0
FRAG_FIRST = 8                  # fragments 8-15: page 2, #x540-#x7FF
FRAG_COUNT = 8
CODE_CHUNKS = [0x4600 + 0x800 * b for b in range(8)]   # page 1 gaps (the
CHUNK_LENS = [0x200] * 6 + [0xC0, 0x100]  # seventh's first #140 bytes,
                                        # #7600, are the player's:
                                        # player.asm; the eighth's first
                                        # half, #7E00, the cache's)
SINFO_FIELDS = ["half width", "width", "first line's end", "height",
                "how its box is erased", "code", "data", "half width it is hit in"]


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


def ch_slot(ch, label, codes):
    """Each car's code for one view, placed from where ch is: car 0's in ch
    (BOOT.BIN), labelled `label`, and ch then padded to the most any car
    uses of each chunk, so that any car's fits there. Returns per car its
    pieces for CARn.BIN: (address, its dest, lines), labels car<n>_<label>."""
    used0, len0 = list(ch.used), [len(o) for o in ch.out]
    pieces, finals = [], []
    for n, code in enumerate(codes):
        c = copy.deepcopy(ch)
        c.code("car%d_%s" % (n, label), code)
        pieces.append([(Chunks.start(k) + used0[k], "#%04X" % (Chunks.start(k) + used0[k]),
                        c.out[k][len0[k]:])
                       for k in range(len(CODE_CHUNKS)) if c.out[k][len0[k]:]])
        finals.append(c)
    most = [max(f.used[k] for f in finals) for k in range(len(CODE_CHUNKS))]
    ch.code(label, codes[0])
    for k in range(len(CODE_CHUNKS)):
        if most[k] > ch.used[k]:
            ch.out[k].append("    defs %d   ; (another car's is longer)" % (most[k] - ch.used[k]))
            ch.used[k] = most[k]
    ch.cur = max(f.cur for f in finals)
    return pieces


def frag_slot(fc, label, codes):
    """As ch_slot, in the fragments' runs (FragCode) - nothing goes there
    after it, so no padding. A piece's dest is where BOOT.BIN has it (the
    fragment's FRAG_ST: boot.asm copies the fragments into place after)."""
    pieces = []
    n0, size0, placed0 = len(fc.piece.lines), fc.piece.size, len(fc.sp.placed)
    run0 = fc.runs[fc.cur][0]
    fc.spare = None                     # what the longest leaves of the runs
    for n, code in enumerate(codes):
        f = copy.deepcopy(fc)
        first = f.sp.placed[placed0 - 1][3]
        f.code("car%d_%s" % (n, label), code)
        left = f.left + sum(ln for a, ln in f.runs[f.cur + 1:])
        if fc.spare is None or left < fc.spare:
            fc.spare = left
            a, ln = f.runs[f.cur]           # ... as runs, past it
            fc.after = [(a + ln - f.left, f.left)] + f.runs[f.cur + 1:]
        ps = [(run0 + size0, first.lines[n0:])]
        ps += [(a, d.lines) for a, _, _, d in f.sp.placed[placed0:]]
        # (into the fragments in place: boot.asm has copied 8-15 out of
        # BOOT.BIN before boot_car)
        pieces.append([(a, "#%04X" % a, lines) for a, lines in ps if lines])
    fc.code(label, codes[0])
    return pieces


# The views uphill and downhill (car_view 3-8) and spun (9-10) - CARn.BIN
# only - go where the car's code can run (RAM_C1) and nothing else writes:
# bank 7 from CAR_HILL_ORG on, and the road parts' lines 160-172 of buffer
# 0 (page 2) and of buffer 1's first four 2K blocks (page 0: the rest of
# page 0 is where the loader loads CARn.BIN). The CRTC shows the road parts from line
# 184 (draw_static draws nothing above it), and lines 173-178 hold the
# sound (hw.asm SND_P0..): a bush's top or a prop's is never above line 179
# (bush_top; the props' below).
CAR_HILL_ORG = 0xF100
SOUND_LINES = (173, 179)        # (hw.asm SND_P0..SND_P5: lines 173-178)


def bush_top():
    """The highest line a bush's top is on: whatever its row's sprite, on
    whatever hill (bush_one: on line ROAD_Y or lower)."""
    top = 999
    for r in range(1, G.ROWS + 1):
        for size in range(len(G.BUSH_SIZES)):
            i = G.bush_sprite_of(size, r)
            if i is None:
                continue
            for hill in range(-128, S.HILL_MAX + 1, 2):
                q = abs(hill) // r
                y = G.HORIZON_Y + r + (q if hill >= 0 else -q)
                if G.ROAD_Y <= y < S.ROAD_AREA_Y + 128:
                    top = min(top, y - G.BUSH_H[i] + 1)
    return top


def hidden_runs(base, blocks):
    return [(base + b * 0x800, 192 if b < 5 else 96) for b in blocks]


# ... and first the HUDs' eighth character rows in page 1, which the CRTC
# never shows (its R6: seven rows): 96 bytes of each HUD in each 2K block,
# #x2A0 and #x5A0 - those free when boot_car copies the car's records in
# (boot.asm): not where fragments 3-6 are still stored then (#x2A0 of
# blocks 1-3: the sound's, after them - hw.asm SND_M0..), nor boot_car
# itself (#x5A0 of block 1).
HUD_ROW7 = [(0x4000 + b * 0x800 + off, 96) for b in range(8) for off in (0x2A0, 0x5A0)
            if not (off == 0x2A0 and b in (1, 2, 3)) and not (off == 0x5A0 and b == 1)]
# (#0038-#003A, in buffer 1's block 0, is IM 1's JP to the interrupt handler:
# boot.asm)
IM1_JP = 0x0038
HILL_RUNS = (HUD_ROW7 + [(CAR_HILL_ORG, 0x10000 - CAR_HILL_ORG)] + hidden_runs(0x8000, range(8))
             + [(0x0000, IM1_JP), (IM1_JP + 3, 192 - IM1_JP - 3)] + hidden_runs(0x0000, range(1, 4)))
# The traffic's pieces left over from the fragments go - in every CARn.BIN,
# after the car's records - in what the views on hills leave of HILL_RUNS in
# pages 0 and 2 (mapped whatever the configuration), then in buffer 1's
# blocks 4-6: the loader loads CARn.BIN over them, but boot.asm has read
# those bytes of it by the time it copies these (cars_asm: TRAF_BLOB_MIN).
TRAF_HIDDEN = hidden_runs(0x0000, range(4, 7))
TRAF_BLOB_MIN = max(a + ln for a, ln in TRAF_HIDDEN)


class Runs:
    """Code in free runs, one after the other, on from one to the next with
    a JP (as FragCode). pieces: (address, lines) per run used."""

    def __init__(self, runs):
        self.runs = runs
        self.cur, self.used = 0, 0
        self.pieces = []

    def code(self, label, code):
        if self.runs[self.cur][1] - self.used < 8:
            self.cur, self.used = self.cur + 1, 0
        lines = [label]
        start = self.runs[self.cur][0] + self.used
        for text, step in code:
            n = SIZE[kind(text)]
            if self.runs[self.cur][1] - self.used < n + 3 and not (
                    text == "jp bush_spr_done" and self.runs[self.cur][1] - self.used >= n):
                if self.cur + 1 >= len(self.runs):
                    raise SystemExit("bushes: no room left for the cars' views on hills")
                lines.append("    jp #%04X" % self.runs[self.cur + 1][0])
                self.pieces.append((start, lines))
                self.cur, self.used = self.cur + 1, 0
                lines, start = [], self.runs[self.cur][0]
            lines.append("    " + text)
            self.used += n
        self.pieces.append((start, lines))


def runs_slots(allcars, views):
    """Each car's code for these views in HILL_RUNS, every view where it is
    for all cars (after the longest car's last): per car its pieces, where
    each view starts, the bytes used and the runs left after them."""
    pieces = [[] for _ in allcars]
    starts = []
    r = Runs(HILL_RUNS)
    for v in views:
        finals = []
        for n, cars in enumerate(allcars):
            c = copy.deepcopy(r)
            c.pieces = []
            c.code("car%d_view%d" % (n, v), cars[v][0])
            pieces[n] += [(a, "#%04X" % a, lines) for a, lines in c.pieces]
            finals.append(c)
        if r.runs[r.cur][1] - r.used < 8:
            starts.append(r.runs[r.cur + 1][0])
        else:
            starts.append(r.runs[r.cur][0] + r.used)
        r = max(finals, key=lambda f: (f.cur, f.used))
    used = sum(ln for a, ln in HILL_RUNS[:r.cur]) + r.used
    a, ln = HILL_RUNS[r.cur]
    return pieces, starts, used, [(a + r.used, ln - r.used)] + HILL_RUNS[r.cur + 1:]


# --- the props --------------------------------------------------------------
# The props beside the road (src/props.asm): each kind's sprites from
# tools/propsart.py (tools/mkprops.py), PROP_SIZES of them, smallest first.
PROP_REC0 = 8                   # bush_sinfo's records 8..15: the prop in sight's
                                # sprites, smallest first (props.asm: prop_take)
PROP_TOP = SOUND_LINES[1] - S.ROAD_AREA_Y   # lines from ROAD_AREA_Y a prop
                                # may be drawn on: 160-172 hold code
                                # (HILL_RUNS), 173-178 the sound


def prop_sprite(kind, rows):
    """A prop's sprite as the game has it (src/props.asm, prop_draw): its
    centre's byte, its width, its column's lines (the trunk or the post:
    its last lines, alike, one run of a byte or two), its height; the
    column's run - a byte (its first byte from the left | its bytes << 4)
    and its bytes; then the lines above the column, as groups of the same
    line - its lines, then the line's runs, each a byte (the bytes from the
    end of the run before, or from the left | its bytes << 4 | #80 on the
    line's last) and its bytes."""
    import mkprops
    import propsart
    pen = {c: G.PEN[name] for c, name in propsart.LETTERS.items()}

    def run_bytes(pairs):
        return [G.m0_byte(pen[p[0]], pen[p[1]]) for p in pairs]
    groups = mkprops.groups(rows)
    w = len(rows[0]) // 2
    assert w <= 16, (kind, w)                    # (a byte's left nibble)
    cl, col = groups[-1]
    assert len(col) == 1 and len(col[0][1]) <= 2, (kind, len(rows))
    out = [G.prop_hw(kind, w), w, cl, len(rows)]
    x, pairs = col[0]
    out.append(x | len(pairs) << 4)
    out += run_bytes(pairs)
    for n, runs in groups[:-1]:
        assert runs and n < 256, (kind, len(rows))
        out.append(n)
        end = 0
        for j, (x, pairs) in enumerate(runs):
            assert 0 <= x - end <= 15 and 1 <= len(pairs) <= 7, (kind, len(rows))
            out.append(x - end | len(pairs) << 4 | (0x80 if j == len(runs) - 1 else 0))
            out += run_bytes(pairs)
            end = x + len(pairs)
    return out


def prop_sprites():
    """{(kind, size): its sprite's bytes}, for course.PROP_KINDS."""
    import course
    import propsart
    assert list(propsart.PROPS_ART) == course.PROP_KINDS
    out = {}
    for kind in course.PROP_KINDS:
        hs = sorted(propsart.PROPS_ART[kind])
        assert hs == G.prop_heights(kind if kind != "curve_r" else "curve"), kind
        for s, h in enumerate(hs):
            out[kind, s] = prop_sprite(kind, propsart.PROPS_ART[kind][h])
    return out


PROP_NEAR, PROP_OFF = 5, 12     # (src/propdraw.asm pd_near)


def props_off_road(props):
    """That a prop's erase boxes (props.asm prop_draw) lie on no road where
    bush_one leaves it off the inside (a straight with no crest, or a curve's
    outside on the flat) - but the smaller sizes, which pd_near puts on the
    inside on a straight with the road PROP_OFF or more pairs off the
    middle (the road's far rows hardly move with road_x, theirs do). Over
    hills, curve levels and road_x (every other), depths every 4 units."""
    import course as T
    grass = {G.PEN["GRASS_A"], G.PEN["GRASS_B"]}
    bad = []
    for hill in (0, -10, -26, -42, -64, -90, -128):
        h = min(S.level_hill(S.hill_level(hill)), S.HILL_MAX)
        top = next(r for r in S.project(h) if r)
        for k in range(-G.CURVE_K, G.CURVE_K + 1):
            if k and hill:
                continue                # (a curve on a hill: both inside)
            for x in range(-32, 33, 2):
                lines = S.road_lines(h, 0, k, x)
                for zr in range(G.BUSH_ZNEAR, T.PROP_ZVIS, 4):
                    r = G.bush_row(zr)
                    if not r or r < top:
                        continue
                    q = abs(h) // r
                    y = G.HORIZON_Y + r + (q if h >= 0 else -q)
                    s = G.prop_size_of(r)
                    if y < G.ROAD_Y or (s < PROP_NEAR and not k and abs(x) >= PROP_OFF):
                        continue
                    for kind in T.PROP_KINDS:
                        hw, w, cl, hh, col = props[kind, s][:5]
                        for side in (-1, 1):
                            if k * side > 0:
                                continue        # (the inside)
                            for lat in sorted(set(T.TREE_LATS) | {T.SIGN_LAT}):
                                cx = (G.bush_centre(k, r) + G.player_shift(k, x, r)
                                      + side * min(G.bush_lat(lat, r), 127))
                                if not 0 <= cx < G.SCR_W // 2:
                                    continue
                                left, ty = cx - hw, y - hh + 1
                                for by, bn, bx, bw in ((ty, hh - cl, left, w),
                                                       (ty + hh - cl, cl, left + (col & 15), 2)):
                                    x0, x1 = max(bx, 0), min(bx + bw, G.SCR_W // 2)
                                    if bn <= 0 or x1 <= x0:
                                        continue
                                    xr = min(x0 + (x1 - x0 + 1) // 2 * 2, G.SCR_W // 2)
                                    xl = xr - (x1 - x0 + 1) // 2 * 2
                                    if any(lines[yy - G.ROAD_Y][px] not in grass
                                           for yy in range(max(by, G.ROAD_Y), by + bn)
                                           for px in range(2 * max(xl, 0), 2 * xr)):
                                        bad.append((kind, s, hill, k, x, zr, side, lat))
    assert not bad, bad[:5]


def prop_label(kind, s):
    return "prop_%s%d" % (kind, s)


def defb_lines(data):
    return ["    defb " + ",".join("#%02X" % v for v in data[j:j + 16])
            for j in range(0, len(data), 16)]


def cars_asm(pieces, ends, codes, traffic):
    """gen/cars.asm: per car, CARn.BIN - a magic word, then records (defw
    dest, length, then the bytes) up to a 0: car_views, car_id, its code,
    then the traffic's pieces in the hidden lines (the same in each; their
    labels are car 0's). codes: per car_view, its code's address (the same
    for every car)."""
    lines = [";; Generated by tools/mkbush.py - do not edit.",
             ";; CAR0.BIN-CAR3.BIN, one a car: what boot.asm copies over the first",
             ";; car's when the loader has loaded it at CAR_BLOB - car_views (where",
             ";; each view's first line's run ends, and its code), car_id, and its code",
             ";; in the same places (mkbush.py: the most any car needs) - the views on",
             ";; hills where only CARn.BIN puts them. Records: defw dest, length, then",
             ";; the bytes; a dest of #FFFF ends them (#0000 is one).", ""]
    for n, ps in enumerate(pieces):
        lines += ["    BANK", "    ORG CAR_BLOB", "car%d_blob" % n,
                  "    defw CAR_MAGIC",
                  "    defw car_views,%d" % (4 * len(codes))]
        lines += ["    defw #%04X,%s" % (e, c) for e, c in zip(ends[n], codes)]
        lines += ["    defw car_id,1", "    defb %d" % n]
        tr = [(a, d, c if n == 0 else [t for t in c if t.startswith(" ")])
              for a, d, c in traffic]
        for j, (addr, dest, code) in enumerate(ps + tr):
            if j == len(ps):
                lines += ["car%d_traffic" % n,
                          "    ASSERT car%d_traffic >= #%04X   ; (read before they go there)"
                          % (n, TRAF_BLOB_MIN)]
            p = "car%d_p%d" % (n, j)
            lines += ["    defw %s,%s_end-%s" % (dest, p, p),
                      "%s_ph" % p,
                      "    ORG #%04X,%s_ph" % (addr, p),
                      p] + code + ["%s_end" % p,
                                   "    ORG %s_ph+%s_end-%s" % (p, p, p)]
        lines += ["    defw #FFFF", "car%d_blob_end" % n,
                  "    ASSERT car%d_blob_end <= FRAG7   ; (in place before boot_car)" % n,
                  '    SAVE "CAR%d.BIN",CAR_BLOB,car%d_blob_end-CAR_BLOB,DSK,'
                  '"build/countryride.dsk"' % (n, n), ""]
    return lines


def main():
    nspr = len(G.BUSH_H)
    assert nspr <= 16                   # the directory's columns
    maxw = max(len(d) for k in range(nspr) for a, d in sprite_lines(k))
    box = max(wb for wb, spans in S.BUSH_SPRITES)
    rows = range(G.ROWS + 1)
    sp = Space()

    # bushcode.asm: the sprites' code, smallest first (one of them in the
    # fragments if page 1 has no room for all)
    # every car's views (the first's is BOOT.BIN's), and where each view's
    # first line's run ends in buffer 0
    allcars, ends = [], []
    for c in range(len(S.CARS)):
        S.set_car(c)
        allcars.append([car_code(S.car_runs(v), S.CAR_Y, S.CAR_X // 2)
                        for v in range(S.CAR_VIEWS)])
        e = []
        for v in range(S.CAR_VIEWS):
            y, (a0, d0) = next((y, r) for y, r in enumerate(S.car_runs(v)) if r[1])
            e.append(line_addr(S.CAR_Y + y) + S.CAR_X // 2 + a0 + len(d0))
        ends.append(e)
    S.set_car(0)
    # the views on hills: CARn.BIN only (above), the first car's too
    assert bush_top() >= SOUND_LINES[1], bush_top()
    hill_pieces, hill_starts, hill_used, hill_left = runs_slots(allcars, range(3, S.CAR_VIEWS))

    def build(ks):
        ch = Chunks()
        p0 = ch_slot(ch, "car_code0", [c[0][0] for c in allcars])   # (the car
        out = {}                                # first: it is drawn most;
        for k in ks:                            # turning right: FragCode)
            code, us = sprite_code(k)
            out[k] = [code, us, sum(SIZE[kind(t)] for t, s in code)]
        for k in ks:
            ch.code("bush_c%d" % k, out[k][0])
        p1 = ch_slot(ch, "car_code1", [c[1][0] for c in allcars])   # (and
        return ch, out, [a + b for a, b in zip(p0, p1)]     # turning left
                                                            # after them)

    def fits(ks):
        try:
            return build(ks)
        except SystemExit:
            return None
    # if page 1 is too full, the smallest sprite's code that makes room
    # goes in the fragments instead (beside the car turning right)
    in_frags = []
    got = fits(range(nspr))
    for k in sorted(range(nspr), key=lambda k: len(sprite_code(k)[0])) if not got else []:
        got = fits([j for j in range(nspr) if j != k])
        if got:
            in_frags = [k]
            break
    if not got:
        raise SystemExit("bushes: no room left in page 1 for the cars' views")
    ch, codes, pieces = got
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

    # the props: each kind's sprites' directory, and the sprites, biggest
    # first, in what is left of page 1 - the rest in the hidden lines with
    # the traffic's pieces (below). (The courses' lists: mkgfx.py, gfx.asm.)
    import course as T
    props = prop_sprites()
    ch.data("prop_dir", [prop_label(pk, s) for pk in T.PROP_KINDS
                         for s in range(G.PROP_SIZES)])
    props_left = []
    for (pk, s), data in sorted(props.items(), key=lambda kv: -len(kv[1])):
        try:
            ch.bytes(prop_label(pk, s), "%s, size %d: %d lines" % (pk, s, data[3]), data)
        except SystemExit:
            props_left.append((pk, s))

    # the car turning right: code in what is left of fragments 8-14
    # (road15.asm has the rest of fragment 15)
    fc = FragCode(sp, sp.take_runs(frag_addr(FRAG_FIRST + FRAG_COUNT - 1)))
    for k in in_frags:
        code, us = sprite_code(k)
        fc.code("bush_c%d" % k, code)
        codes[k] = [code, us, sum(SIZE[kind(t)] for t, s in code)]
    p2 = frag_slot(fc, "car_code2", [c[2][0] for c in allcars])
    # the traffic's pieces left over (mktrafcode.py): in the runs past the
    # longest car turning right, then fragment 15's holes (its end after
    # the last thing placed there is road15.asm's)
    end15 = max(a + len(d) for a, l, c, d in sp.placed
                if frag_addr(FRAG_FIRST + FRAG_COUNT - 1) <= a)
    free = [[a, ln] for a, ln in fc.after if ln > 0]
    free += [[a, min(ln, end15 - a)] for a, ln in sorted(sp.runs + [(h, 0x80) for h in sp.halves])
             if frag_addr(FRAG_FIRST + FRAG_COUNT - 1) <= a < end15]
    runs, at = [[a, ln, []] for a, ln in free], 0
    hidden0 = [(a, ln) for a, ln in hill_left            # (not page 1 nor bank 7:
               if (a < 0x4000 or 0x8000 <= a < 0xC000) and ln > 0] + TRAF_HIDDEN  # the
    # traffic runs with RAM_C4/C6)
    hidden = [[a, ln, []] for a, ln in hidden0]
    hat = 0
    for code in TRAFLEFT:
        got = lay(code, runs, at)
        if got is not None:
            at = got
            continue
        hat = lay(code, hidden, hat)
        if hat is None:
            raise SystemExit("traffic: no room in the fragments or the hidden lines for "
                             "%s; runs %s, %s" % (code[0], free, hill_left))
    traf_used = 0
    for (a, ln), (_, rm, laid) in zip(free, runs):
        if laid:
            piece = CodePiece()
            piece.lines = laid
            piece.size = ln - rm
            sp.placed.append((a, None, None, piece))
            traf_used += ln - rm
    # the props' sprites page 1 has no room for: after the traffic's pieces,
    # each in the run that fits it best
    for pk, s in props_left:
        data = props[pk, s]
        fits = [r for r in hidden if r[1] >= len(data)]
        if not fits:
            raise SystemExit("props: no room in the hidden lines for %s %d" % (pk, s))
        r = min(fits, key=lambda r: r[1])
        r[2] += ["%s   ; %s, size %d: %d lines" % (prop_label(pk, s), pk, s, data[3])]
        r[2] += defb_lines(data)
        r[1] -= len(data)
    traf_hidden = [(r[0], "#%04X" % r[0], r[2]) for r in hidden if r[2]]
    traf_hidden_used = sum(ln - r[1] for (a, ln), r in zip(hidden0, hidden))
    pieces = [a + b + c for a, b, c in zip(pieces, p2, hill_pieces)]
    view_code = ["car_code0", "car_code1", "car_code2"] + ["#%04X" % a for a in hill_starts]

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
                    emit("    defb %d" % (wb // 2))
                    emit("    defs 5,0")
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
    # the lines of the car: a buffer that last showed another view, or the
    # car elsewhere, has them drawn whole (car_lines) - all of them, for
    # any car
    emit("CAR_Y         EQU %d   ; the car's top line" % S.CAR_Y)
    emit("CAR_HALF      EQU %d   ; its half width, bytes" % (S.CAR_W // 4))
    emit("CAR_TOP       EQU %d   ; its lines from there, drawn whole when it changes"
         % S.CAR_H)
    emit("CAR_HILL_ORG  EQU #%04X ; the views on hills from here (CARn.BIN)" % CAR_HILL_ORG)
    emit("SPIN_VIEW     EQU %d   ; car_view: spun left in a crash, then right" % S.SPIN_VIEW)
    emit("SPIN_OFF      EQU %d  ; ... seen so at most this far from the middle"
         % S.SPIN_OFF)
    emit(";; per car_view (on the level, uphill, downhill; each straight, turning")
    emit(";; left, turning right; spun left, right): where its first line's run")
    emit(";; ends in buffer 0, and its code - the first car's; boot.asm copies the")
    emit(";; picked one's over it (CARn.BIN, which alone has the views on hills and")
    emit(";; spun: here the level's, and turning)")
    emit("car_views")
    for v in range(S.CAR_VIEWS):
        lv = v % 3 if v < S.SPIN_VIEW else 1 + v - S.SPIN_VIEW     # (spun:
        emit("    defw #%04X,car_code%d" % (ends[0][lv], lv))      # turning)
    emit("car_id        defb 0   ; the car picked, 0-3 (CARn.BIN; tools/run.py)")
    emit(";; per car: its top speed, its acceleration (both 8.8 depth units a")
    emit(";; VSYNC), its steering's and the curves' factors (steer: k, m)")
    emit(";; (scene.py CAR_LEVELS; car_setup)")
    emit("car_stats")
    for c, (sp_, ac, gr) in enumerate(S.CAR_LEVELS):
        steer_, drift = S.GRIP[gr]
        emit("    defw #%04X   ; %s: speed %d, acceleration %d, grip %d"
             % (S.TOP_SPEED[sp_], S.CARS[c], sp_, ac, gr))
        emit("    defb %d,%d,%d" % (S.ACCEL[ac], steer_, drift))
    emit("CAR_STATS_LEN EQU 5   ; bytes a car")
    emit("")
    emit(";; per curve level 0..CURVE_K: its centre table")
    emit("bush_cxs")
    emit("    defw " + ",".join("bush_cx%d" % i for i in range(G.CURVE_K + 1)))
    emit("")
    # the props: every row a prop is drawn on (BUSH_ZNEAR up to PROP_ZVIS
    # ahead) has a size, and their tops are on PROP_TOP or lower, whatever
    # the hill (bush_one: a crest no stronger than BUSH_HILL_MAX)
    sizes = [G.prop_size_of(r) for r in range(G.ROWS + 1)]
    assert all(sizes[G.bush_row(zr)] is not None for zr in range(G.BUSH_ZNEAR, T.PROP_ZVIS)
               if G.bush_row(zr))      # (row 0: below the screen)
    first = [sizes.index(s) for s in range(G.PROP_SIZES)]
    assert all(sizes[r] == max(s for s in range(G.PROP_SIZES) if first[s] <= r)
               for r in range(first[0], G.ROWS + 1))
    top = 999
    for r in range(first[0], G.ROWS + 1):
        h = max(props[pk, sizes[r]][3] for pk in T.PROP_KINDS)
        for hill in range(-128, S.HILL_MAX + 1, 2):
            q = abs(hill) // r
            y = G.HORIZON_Y + r + (q if hill >= 0 else -q) - S.ROAD_AREA_Y
            if G.ROAD_Y - S.ROAD_AREA_Y <= y < 128:
                top = min(top, y - h + 1)
    assert top >= PROP_TOP, top
    props_off_road(props)
    emit(";; the props (src/props.asm)")
    emit("PROP_REC0     EQU %d   ; bush_sinfo's records from here on: the prop in"
         % PROP_REC0)
    emit("                      ; sight's sprites")
    emit("PROP_SIZES    EQU %d" % G.PROP_SIZES)
    emit("PROP_KINDS    EQU %d" % len(T.PROP_KINDS))
    emit("PROP_ZVIS     EQU %d   ; drawn from this far ahead" % T.PROP_ZVIS)
    emit("PROP_TOP      EQU %d    ; and on lines from ROAD_AREA_Y + this on (above:"
         % PROP_TOP)
    emit("                      ; code; their tops are on line %d at the highest)"
         % top)
    emit("PROP_BOX      EQU %d   ; the widest sprite, bytes"
         % max(d[1] for d in props.values()))
    emit(";; per size, the first row it is drawn on (prop_init)")
    emit("prop_rows")
    emit("    defb " + ",".join(str(r) for r in first))
    emit(";; per lateral class, its offset tables: right, left")
    emit("prop_lats")
    emit("    defw " + ",".join("bush_latR%d,bush_latL%d" % (c, c)
                              for c in range(len(G.BUSH_LATS))))
    emit(";; per kind (%s): the bushes that may be in reach while it is in sight"
         % ", ".join(T.PROP_KINDS))
    emit("prop_rooms")
    emit("    defb " + ",".join(str(T.PROP_ROOM[k]) for k in T.PROP_KINDS))
    emit("")
    open(os.path.join(ROOT, "src", "gen", "bush.asm"), "w").write(
        "\n".join(lines) + "\n")
    open(os.path.join(ROOT, "src", "gen", "cars.asm"), "w").write(
        "\n".join(cars_asm(pieces, ends, view_code, traf_hidden)) + "\n")
    print("bushes: %d on the track, %d sprites, code for %d (%d bytes left in page 1);"
          " %d bytes of fragments %d-%d left, and %d where the car turning right is"
          % (len(S.BUSHES), nspr, len(codes), ch.free(),
             sp.free(), FRAG_FIRST, FRAG_FIRST + FRAG_COUNT - 1, fc.spare))
    print("  the cars' views on hills: %d of %d bytes" % (hill_used, sum(ln for a, ln in HILL_RUNS)))
    print("  the traffic's pieces in the fragments: %d bytes, %d left there; in the "
          "hidden lines (CARn.BIN): %d bytes, %d left there"
          % (traf_used, sum(r[1] for r in runs), traf_hidden_used, sum(r[1] for r in hidden)))
    for c, cars in enumerate(allcars):
        print("  car %d: %d lines; views %s bytes of code, %s us"
              % (c, S.CAR_H, "/".join(str(sum(SIZE[kind(t)] for t, st in car))
                                      for car, us in cars),
                 "/".join(str(us) for car, us in cars)))
    for k, (code, us, size) in sorted(codes.items()):
        print("  sprite %2d: %2d lines, %3d bytes of code, %4d us%s"
              % (k, G.BUSH_H[k], size, us, " (in the fragments)" if k in in_frags else ""))


if __name__ == "__main__":
    main()
