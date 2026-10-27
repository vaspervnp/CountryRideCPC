#!/usr/bin/env python3
"""Compile the road into Z80 code and tables: src/gen/road*.asm.

A road line is grass, then the road "core" (kerb, asphalt, lane lines, kerb),
then grass again. The grass is a run of PUSH BC; the core is different for
every road width, so each width is compiled into its own straight run of
PUSHes - a *variant* - and the renderer jumps into it.

Variant (band, half, parity):
  band    0 = stripe A, 1 = stripe B (B has no lane lines: they are dashed)
  half    asphalt half-width in bytes, 0..HALF_MAX
  parity  whether the core's right edge falls on an odd byte. PUSH writes the
          screen two bytes at a time from line_end downwards, so a core whose
          edge is odd is compiled one byte wider on each side, the extra bytes
          being grass.

Each pair of bytes (written right to left) becomes one of:
  PUSH DE          asphalt, both pixels          (DE' = asphalt pair)
  PUSH AF          kerb, both pixels             (AF' = kerb pair)
  LD BC,nn / PUSH BC   anything else
and the variant ends with EXX / EX AF,AF' / JP (IX).

The variant runs in the shadow register set. Every pair can be entered (no
pair leans on the LD BC,nn of the one before), so a core hanging off the
right of the screen is entered part-way in, and one hanging off the left is
cut short by writing JP (HL) (HL' = line_done_shadow) over the first pair
that must not be drawn.

Also written here:
  * the templates: what road_draw pops for a line (core entry, left grass
    entry, right grass entry and flags, and the exit patch address when there
    is one - see common.asm), for every curve level and every group of rows
    (cpcgfx.curve_group), the road moved sideways as far as the curve takes
    that group. One template set per level, TMPL_SET bytes; band A's (and
    band 2's) in bank 4 from TMPL_A, band B's in bank 5 from TMPL_B, at the
    same offsets - so the bank a template is in is bit 13 of its address;
  * per-row tables for road.asm: depth, stripe mask and the row's templates
    in the first level's set.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from functools import lru_cache
from cpcgfx import (BANDS, HALF_MAX, MIN_HALF, ROWS, NEAR_ROW, ROAD_END, ROAD_LINES,
                    FAR_Z, far_mask, m0_byte, m0_solid,
                    road_row_pixels, row_half_bytes, row_depth, SCR_BYTES,
                    ROAD_Y, ROAD_TOP_MAX, CURVE_K, curve_group, curve_shift,
                    curve_c1, curve_d, road_shift, shift_tau, CURVE_ROW_GROUPS, PERSP_P,
                    PLAIN_GRASS, ROAD_X_MAX,
                    GRASS_ROW, GRASS_SHIFT, GRASS_STRIPES, PEN, HUD_H, SKY_Y)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "src", "gen", "roadcores.asm")

PAIRS = SCR_BYTES // 2          # 48 pairs per line
CENTRE = SCR_BYTES // 2         # the road is centred on byte 48

TMPL_SET = 512                  # a curve level's templates (two pages)
TMPL_A = 0x4000                 # bank 4: band A's (and 2's) template sets
TMPL_B = 0x6000                 # bank 5: band B's, at the same offsets
CORES_A = 0x6000                # bank 4: band 0 and 2 cores
CORES_B = 0x4000                # bank 5: band 1 cores
LEVELS = 2 * CURVE_K + 1


def word(lo, hi):
    return lo | (hi << 8)


@lru_cache(maxsize=None)
def core_bytes(band, half, parity):
    """Screen bytes of the core - the kerbs and the asphalt -
    left to right, and H (bytes each side of the centre before the parity
    widening). What is left of the pairs it covers is kerb too (no grass:
    the grass is striped, the core is not): scene.road_line."""
    pens, total = road_row_pixels(half, band)
    H = (total + 1) // 2
    kerb = pens[0]
    # pixel 0 of the byte-aligned core is centre_px - 2H
    px = [kerb] * (4 * H)
    off = 2 * H - total
    for i, p in enumerate(pens):
        px[off + i] = p
    if parity:
        px = [kerb] * 2 + px + [kerb] * 2
    out = [m0_byte(px[i], px[i + 1]) for i in range(0, len(px), 2)]
    return out, H


# The register set a band's cores run with: band 2 (far away) is drawn by
# road_draw as band A, so its white kerb cannot be PUSH AF (AF' is red then)
# and comes out as LD BC/PUSH BC.
REG_BAND = {0: 0, 1: 1, 2: 0}
FAR_HALF = row_half_bytes(max(r for r in range(1, ROWS + 1)
                              if row_depth(r) > FAR_Z))


def compile_variant(band, half, parity):
    """Returns (code bytes, entry offsets [NP+1], NP, H). Every pair can be
    entered, so none reuses the LD BC,nn of the one before."""
    regs = BANDS[REG_BAND[band]]
    road = m0_solid(regs["road"])
    kerb = m0_solid(regs["kerb"])
    data, H = core_bytes(band, half, parity)
    n = len(data)
    assert n % 2 == 0
    code = []
    entry = []
    bc = None                          # what BC' holds, if this pair follows on
    for j in range(n // 2):
        lo = data[n - 2 - 2 * j]       # left byte of the pair
        hi = data[n - 1 - 2 * j]       # right byte, written first by PUSH
        entry.append(len(code))
        bc = None
        if lo == hi == road:
            code.append(0xD5)                     # PUSH DE
        elif lo == hi == kerb:
            code.append(0xF5)                     # PUSH AF
        elif word(lo, hi) == bc:
            code.append(0xC5)                     # PUSH BC, BC' as it is
        else:
            w = word(lo, hi)
            code += [0x01, w & 0xFF, w >> 8, 0xC5]  # LD BC,nn / PUSH BC
            bc = w
    entry.append(len(code))
    code += [0xD9, 0x08, 0xDD, 0xE9]              # EXX / EX AF,AF' / JP (IX)
    return code, entry, n // 2, H


def halves(band):
    """The widths a row can have. Band 2 is only ever used past FAR_Z, where
    the road is narrow."""
    return range(MIN_HALF, (FAR_HALF if band == 2 else HALF_MAX) + 1)


def geometry(band, half, shift):
    """For a row of `half` moved `shift` bytes right of the centre: the
    variant drawing it, and its core's right and left edges in pairs (it may
    reach past either edge of the screen)."""
    data, H = core_bytes(band, half, 0)
    c = CENTRE + shift
    parity = (c + H) & 1
    data, H = core_bytes(band, half, parity)
    u = (c + H + parity) // 2
    return (band, half, parity), u, u - len(data) // 2


def entry_pair(u, l):
    """The pair the core is entered at, None if it is all off the screen."""
    if u <= 0 or l >= PAIRS:
        return None
    return max(0, u - PAIRS)


def template(variants, band, half, shift):
    """What road_draw pops for a row of `half` moved `shift` bytes right of
    the centre (see common.asm): core entry (IY), AF (A = right grass entry,
    Z = no exit patch), left grass entry (IX), then the exit patch address
    if the core hangs off the left of the screen. A core cut short there has
    no left grass, so IX holds the byte the patch hides instead. Returns the
    words."""
    key, u, l = geometry(band, half, shift)
    code, entry, np_, H = variants[key]
    name = "rc_%d_%d_%d" % key
    rg = max(0, min(u, PAIRS))
    patch = None
    e = entry_pair(u, l)
    if e is None:
        iy = "empty_core"
    else:
        iy = "%s+%d" % (name, entry[e])
        if l < 0:
            patch = "%s+%d" % (name, entry[u])
    reg = REG_BAND[band]
    ix = "lgrass%s+%d" % ("ab"[reg], PAIRS - max(0, min(l, PAIRS)))
    if patch:
        ix = "#%04X" % code[entry[u]]
    af = "#%02X%02X" % (rg, 0x40 if patch is None else 0)
    return [iy, af, ix] + ([patch] if patch else [])


GROUND = ["empty_core", "#0040", "lgrassa+%d" % PAIRS]

CACHE_LEVEL = LEVELS            # the set after the last level's: the cache
G_OFF = 112                     # added to a pair position in the cache maths


def cache_groups():
    """The near groups in slot order (g = 0..), with (half, first row), the
    number of them with far rows (the first NFAR) and of those with nothing
    but far rows (the first NFARONLY)."""
    groups = template_groups()
    near = [(g, h, r) for kind, g, bands, h, r in groups if kind == "near"]
    far = [g for kind, g, bands, h, r in groups if kind == "far"]
    assert [g for g, h, r in near[:len(far)]] == far
    only = sum(1 for g in far
               if all(row_depth(r) > FAR_Z for r in range(1, ROWS + 1)
                      if curve_group(r) == g))
    return near, len(far), only


def cache_template(variants, band, half, row, k, x):
    """The template the Z80 works out for a cache set: as template(), the
    road also x pairs right of the middle (cpcgfx.road_shift)."""
    return template(variants, band, half, road_shift(k, row, x))


def template_groups():
    """The groups of rows a template set has a template for: (kind, group,
    bands, half, the group's first row), kind 'near' or 'far'. (The last
    groups, past NEAR_ROW, are never drawn: the cache's loops need its lanes
    to run up to 256 - cache5.asm.)"""
    rows = range(1, ROWS + 1)
    near = list(dict.fromkeys(curve_group(r) for r in rows))
    far = list(dict.fromkeys(curve_group(r) for r in rows if row_depth(r) > FAR_Z))
    half = {curve_group(r): row_half_bytes(r) for r in rows}
    row = {}
    for r in rows:
        row.setdefault(curve_group(r), r)
    return ([("near", g, (0, 1), half[g], row[g]) for g in near]
            + [("far", g, (2,), half[g], row[g]) for g in far])


def template_slots(variants):
    """The layout of a template set: [(kind, group, size, offset)], kind
    'ground', 'near' (bands 0 and 1) or 'far' (band 2). Every slot has room
    for an exit patch: with the player off the road's centre (cache sets)
    any group's may need one."""
    slots = [("ground", None, 8)]
    half, row = {}, {}
    for kind, g, bands, h, r in template_groups():
        half[g], row[g] = h, r
        slots.append((kind, g, 8))
    out, off = [], 0
    for kind, g, size in slots:
        out.append((kind, g, size, off))
        off += size
    assert off <= TMPL_SET, "templates: %d bytes a level, %d room" % (off, TMPL_SET)
    return out, half, row


def pack_pages(keys, size):
    """The variants in pages of 256 bytes, none across two: first fit, the
    biggest first."""
    pages, room = [], []
    for k in sorted(keys, key=lambda k: -size[k]):
        assert size[k] <= 256
        for i, r in enumerate(room):
            if r >= size[k]:
                pages[i].append(k)
                room[i] -= size[k]
                break
        else:
            pages.append([k])
            room.append(256 - size[k])
    return pages


# Bank 5's per group arrays (cache5.asm), one in the room after each band B
# template set's near slots: at offset BA_LANE + g, so that L is #CD + g -
# the last group's at #FF - and the next array two pages on.
BA_ARRAYS = ["P2L", "P2H", "P4L", "P4H", "AL", "AH", "AO", "WL", "WH", "FL",
             "C1L", "C1H", "DA", "KK", "H"]
BA_LANE = 0x1CD


def bank5_arrays(near):
    """The values bank 5's per group arrays start with (cache5.asm): the
    road in the middle at curve level 0."""
    out = {name: [] for name in BA_ARRAYS}
    for g, h, r in near:
        H = core_bytes(0, h, 0)[1]
        p, c1, d = PERSP_P * h, curve_c1(r), curve_d(r)
        assert 0 <= 4 * p < 2048 and 0 <= c1 * CURVE_K < 32768 and -256 < d <= 0
        none = h < CURVE_ROW_GROUPS
        vals = dict(P2L=2 * p & 255, P2H=2 * p >> 8, P4L=4 * p & 255, P4H=4 * p >> 8,
                    AL=128 + 64, AH=H, AO=0x80, WL=0, WH=W_NONE >> 8 if none else 0,
                    FL=0 if none else ("hi(rd_tent%d)" % (h & 1)),
                    C1L=c1 & 255, C1H=c1 >> 8, DA=-d, KK=CURVE_K, H=H)
        for name in BA_ARRAYS:
            out[name].append(vals[name])
    return out


# A row with no bias (no lane lines) has W this far off: w never in -128..127
W_NONE = 0x1C00


def main():
    import scene
    variants = {}
    for band in range(3):
        for half in halves(band):
            for parity in range(2):
                variants[(band, half, parity)] = compile_variant(band, half, parity)

    # --- the code: bands 0 and 2 (drawn with band A's registers) in bank 4,
    # band 1 in bank 5 ---
    sizes = {}
    for fname, bands in (("roada.asm", (0, 2)), ("roadb.asm", (1,))):
        lines = [";; Generated by tools/mkroad.py - do not edit.",
                 ";; Road core variants for stripe band(s) %s:" % (bands,),
                 ";; rc_<band>_<half>_<parity>, each after its entry table",
                 ";; re_<band>_<half>_<parity>: the offset of every other pair's",
                 ";; code (pairs 0, 2, 4 ...; an odd pair is 1 byte on, or 4 if the",
                 ";; even one is LD BC,nn / PUSH BC). Each variant is in one page:",
                 ";; its entries are low bytes (cachemac.asm).", ""]
        emit = lines.append
        keys = [(band, half, parity) for band in bands for half in halves(band)
                for parity in range(2)]
        size = {k: len(variants[k][0]) + (len(variants[k][1]) + 1) // 2 for k in keys}
        for i, page in enumerate(pack_pages(keys, size)):
            if i:
                emit("    ALIGN 256")
            for band, half, parity in page:
                code, entry, np_, H = variants[(band, half, parity)]
                n = "%d_%d_%d" % (band, half, parity)
                e2 = entry[0::2]
                emit("re_" + n)
                emit("    defb " + ",".join(str(v) for v in e2))
                emit("rc_" + n)
                for j in range(0, len(code), 16):
                    emit("    defb " + ",".join("#%02X" % c for c in code[j:j + 16]))
                emit("    ASSERT hi(re_%s) == hi($-1)" % n)
        sizes[fname] = sum(size.values())
        open(os.path.join(ROOT, "src", "gen", fname), "w").write("\n".join(lines) + "\n")

    # --- register values and variant sizes ---
    lines = [";; Generated by tools/mkroad.py - do not edit.", ""]
    emit = lines.append
    emit(";; register values per stripe band")
    for band, b in enumerate(BANDS[:2]):
        emit("ROAD%d_PAIR  EQU #%04X" % (band, word(m0_solid(b["road"]),
                                                  m0_solid(b["road"]))))
        emit("KERB%d_PAIR  EQU #%04X" % (band, word(m0_solid(b["kerb"]),
                                                  m0_solid(b["kerb"]))))
    emit("GRASS_PAIR  EQU #%04X" % word(m0_solid(PLAIN_GRASS),
                                        m0_solid(PLAIN_GRASS)))
    emit(";; the grass's other stripe: its byte is GRASS_X apart; the rows from")
    emit(";; GRASS_ROW on are striped by bit GRASS_SHIFT of (depth + zcam)")
    emit("GRASS_X     EQU #%02X" % ((m0_solid(PLAIN_GRASS) ^ m0_solid(PEN["GRASS_B"]))
                                     if GRASS_STRIPES else 0))
    emit("GRASS_ROW   EQU %d" % GRASS_ROW)
    emit("GRASS_SHIFT EQU %d" % GRASS_SHIFT)
    slots, ghalf, grow = template_slots(variants)
    soff = {(kind, g): off for kind, g, size, off in slots}
    emit("")
    emit(";; the template sets (see tools/mkroad.py): a set per curve level,")
    emit(";; level k at TMPL_A + (k + CURVE_K) * TMPL_SET; band B's TMPL_B - TMPL_A")
    emit(";; above band A's, in bank 5")
    emit("CURVE_K     EQU %d" % CURVE_K)
    emit("TMPL_SET    EQU %d" % TMPL_SET)
    emit("TMPL_A      EQU #%04X" % TMPL_A)
    emit("TMPL_B      EQU #%04X" % TMPL_B)
    emit("CORES_A     EQU #%04X" % CORES_A)
    emit("CORES_B     EQU #%04X" % CORES_B)
    emit(";; a line with no road (the first level's copy; every level has one)")
    emit("tmpl_ground EQU TMPL_A+%d" % soff[("ground", None)])
    near, nfar, nfaronly = cache_groups()
    emit("")
    emit(";; the cache sets (common.asm): the road off the middle of the screen")
    emit("CACHE_LEVEL EQU %d   ; the set after the last level's" % CACHE_LEVEL)
    emit("NGROUPS     EQU %d   ; template groups, slot 1 + g of a set" % len(near))
    emit("NFAR        EQU %d   ; the first NFAR have far rows: a slot NGROUPS on" % nfar)
    emit("NFARONLY    EQU %d   ; ... the first NFARONLY nothing else" % nfaronly)
    emit(";; bank 5's per group arrays (cache5.asm): group g at RA_<name> + g")
    emit("W_NONE      EQU #%04X   ; a row with no bias: W this far off" % W_NONE)
    for i, name in enumerate(BA_ARRAYS):
        emit("RA_%-8s EQU #%04X" % (name, TMPL_B + i * TMPL_SET + BA_LANE))
    emit("G_OFF       EQU %d   ; added to a pair position in the cache maths" % G_OFF)
    emit("ROAD_X_MAX  EQU %d   ; road_x goes this far either way" % ROAD_X_MAX)
    emit("PERSP_P     EQU %d   ; a pair of it moves half-width h h * PERSP_P / 256"
         " bytes" % PERSP_P)
    emit("")
    emit(";; per road drop (the horizon's, hz_ground): the lines from the HUD's")
    emit(";; end to the sky part's start - SKY_Y - HUD_H, and as far as the sky")
    emit(";; part goes down (scene.sky_drop)")
    drops = range(max(scene.ground_drop(h) for h in range(-128, 128, 2)) + 1)
    emit("MACRO SKY_DROP_TABLE")
    emit("    defb " + ",".join(str(SKY_Y - HUD_H + scene.sky_drop(d))
                               for d in drops))
    emit("MEND")
    emit("SKY_DROP_N  EQU %d" % len(drops))
    emit(";; a curve level's move between |k| = m and m + 1 leaves the groups from")
    emit(";; CF_SAME<m> on where they were (cache.asm: cf_same)")
    for m in range(CURVE_K):
        moved = [gi for gi, (g, h, r) in enumerate(near)
                 if curve_shift(m, r) != curve_shift(m + 1, r)
                 or curve_shift(-m, r) != curve_shift(-m - 1, r)]
        emit("CF_SAME%d    EQU %d" % (m, max(moved) + 1))
    emit(";; ... the rows from CF_ROW<m> on (255: none; road15.asm: cf_rows)")
    for m in range(CURVE_K):
        moved = [gi for gi, (g, h, r) in enumerate(near)
                 if curve_shift(m, r) != curve_shift(m + 1, r)
                 or curve_shift(-m, r) != curve_shift(-m - 1, r)]
        same = max(moved) + 1
        emit("CF_ROW%d     EQU %d" % (m, near[same][2] if same < len(near) else 255))
    open(os.path.join(ROOT, "src", "gen", "roadconsts.asm"), "w").write(
        "\n".join(lines) + "\n")

    # --- the template sets: band A's and band 2's in bank 4, band B's in
    # bank 5 at the same offsets ---
    used = slots[-1][3] + slots[-1][2]
    for fname, side in (("roadtmpla.asm", "a"), ("roadtmplb.asm", "b")):
        lines = [";; Generated by tools/mkroad.py - do not edit.",
                 ";; Road templates, band %s, a set of %d bytes per curve level"
                 % ("A (and 2)" if side == "a" else "B", TMPL_SET),
                 ";; (%d used): dw core entry (IY), left grass entry (IX), AF" % used,
                 ";; (A = right grass entry, F: Z = no exit patch)[, exit patch].", ""]
        emit = lines.append
        arrays = bank5_arrays(near)
        for k in range(-CURVE_K, CURVE_K + 1):
            emit(";; curve level %d" % k)
            for kind, g, size, off in slots:
                if kind == "far" and side == "b":
                    continue
                if kind == "ground":
                    words = GROUND if side == "a" else None
                elif kind == "near":
                    words = template(variants, 0 if side == "a" else 1, ghalf[g],
                                     curve_shift(k, grow[g]))
                else:
                    words = template(variants, 2, ghalf[g], curve_shift(k, grow[g]))
                if words is None:
                    emit("    defs %d,0" % size)
                    continue
                emit("    defw " + ",".join(words) + "   ; %s %s" % (kind, g or ""))
                if 2 * len(words) < size:
                    emit("    defs %d,0" % (size - 2 * len(words)))
            if side == "a":
                emit("    defs %d,0" % (TMPL_SET - used))
                continue
            name = BA_ARRAYS[k + CURVE_K]
            here = soff[("far", near[0][0])]
            emit("    defs %d,0" % (BA_LANE - here))
            emit("    ASSERT $ == RA_%s" % name)
            emit("    defb " + ",".join(str(v) for v in arrays[name]))
            assert BA_LANE + len(near) == TMPL_SET
        open(os.path.join(ROOT, "src", "gen", fname), "w").write("\n".join(lines) + "\n")

    # --- what the Z80 needs to make a cache set's templates (cachemac.asm):
    # per bank, per group and parity, the core's code and entry table ---
    near, nfar, nfaronly = cache_groups()
    assert nfar == nfaronly and len(near) + nfar <= 64
    for fname, tab, bands, lg in (("roadgeoa.asm", "rd_t4", (0, 2), "lgrassa"),
                                  ("roadgeob.asm", "rd_t5", (1, 1), "lgrassb")):
        lines = [";; Generated by tools/mkroad.py - do not edit.",
                 ";; Per group g (index g; band 2's of the far groups NGROUPS + g)",
                 ";; and parity p, at %s + g, + 128 for p = 0: lo(%s) + PAIRS" % (tab, lg),
                 ";; + H + p (+0) and the core's code, low byte (+64); a page on, its",
                 ";; entry table's low byte (+0) and the code's high byte (+64).",
                 "    ALIGN 256",
                 tab]
        emit = lines.append
        idx = [(bands[0], h) for g, h, r in near] + [(bands[1], h) for g, h, r in near[:nfar]]
        for page in range(2):
            for p in (1, 0):
                for lane in range(2):
                    vals = []
                    for band, h in idx:
                        H = core_bytes(band, h, p)[1]
                        n = "%d_%d_%d" % (band, h, p)
                        vals.append(((("(lo(%s)+%d)&255" % (lg, PAIRS + H + p)), "lo(rc_%s)" % n),
                                     ("lo(re_%s)" % n, "hi(rc_%s)" % n))[page][lane])
                    emit("    defb " + ",".join(vals))
                    emit("    defs %d,0" % (64 - len(vals)))
        if tab == "rd_t5":
            emit(";; Per w (-128..127, as a byte): the bias t - 64 (cpcgfx.road_shift:")
            emit(";; shift_tau(4 w), turned round for an odd half-width in rd_tent1, at")
            emit(";; most 63), for cache5.asm")
            for odd in range(2):
                emit("    ALIGN 256")
                emit("rd_tent%d" % odd)
                vals = []
                for wb in range(256):
                    w = wb - 256 if wb > 127 else wb
                    t = shift_tau(4 * w)
                    t = min(-t if odd else t, 63)
                    vals.append((t - 64) & 255)
                for i in range(0, 256, 32):
                    emit("    defb " + ",".join(str(v) for v in vals[i:i + 32]))
        open(os.path.join(ROOT, "src", "gen", fname), "w").write("\n".join(lines) + "\n")

    # --- bank 6: rows, hill tables, line addresses ---
    lines = [";; Generated by tools/mkroad.py - do not edit.",
             ";; Bank 6: what road_project needs to turn a hill and a camera depth",
             ";; into a template for every road line.", ""]
    emit = lines.append

    hooks = [0]

    def align():
        """To the next page: before it, what the rows leave of this one
        (rowhole<n>.asm, here in src/gen: tools/mktrafcode.py lays traffic
        code there)."""
        emit('    INCLUDE "rowhole%d.asm"' % hooks[0])
        hooks[0] += 1
        emit("    ALIGN 256")

    def page(name, vals, comment):
        align()
        emit("%s   ; %s" % (name, comment))
        for i in range(0, len(vals), 8):
            emit("    defb " + ",".join(vals[i:i + 8]))

    tl, dp, mk, th, tl2, th2 = [], [], [], [], [], []
    for r in range(NEAR_ROW + 1):
        if r == 0:
            a = TMPL_A + soff[("ground", None)]
            tl.append("#%02X" % (a & 0xFF))
            tl2.append("#%02X" % (a & 0xFF))
            th.append("#%02X" % (a >> 8))
            th2.append("#%02X" % (a >> 8))
            dp.append("0")
            mk.append("0")
            continue
        a = TMPL_A + soff[("near", curve_group(r))]
        tl.append("#%02X" % (a & 0xFF))
        th.append("#%02X" % (a >> 8))
        if row_depth(r) > FAR_Z:
            a = TMPL_A + soff[("far", curve_group(r))]
            tl2.append("#%02X" % (a & 0xFF))
            th2.append("#%02X" % (a >> 8))
        else:
            tl2.append("0")
            th2.append("0")
        dp.append(str(row_depth(r) & 0xFF))
        mk.append(str(far_mask(r)))
    emit(";; Per row r (1..%d; 0 = the ground), page-aligned so a row is an" % NEAR_ROW)
    emit(";; index and the next array is INC H away. The stripe or dash a row")
    emit(";; is in is (depth + camera) AND mask, which needs only low bytes.")
    emit(";; The templates are the row's group's in the first curve level's set:")
    emit(";; a level is TMPL_SET/256 pages further, and near rows' band 1 is")
    emit(";; TMPL_B - TMPL_A = #2000 above band 0 - mask 64 rotated right once is")
    emit(";; the #20 to add to the high byte. Rows past FAR_Z: a longer dash, and")
    emit(";; band 0's or band 2's template.")
    assert far_mask(NEAR_ROW) == 64 and (TMPL_B - TMPL_A) >> 8 == 64 >> 1
    page("rr_tlo", tl, "band 0 template, low byte")
    emit("    defs 128-%d,0" % len(tl))
    emit("rr_gfirst   ; per cache group (cache.asm: rp_mode_chg), its first row;")
    emit("            ; then ROWS + 1, as if one more, and 255 (none)")
    gfirst = [str(r) for g, h, r in cache_groups()[0]] + [str(ROWS + 1), "255"]
    for i in range(0, len(gfirst), 16):
        emit("    defb " + ",".join(gfirst[i:i + 16]))
    page("rr_depth", dp, "depth, low byte")
    page("rr_mask", mk, "64; 128 past FAR_Z; 0 for the ground")
    page("rr_thi", th, "band 0 template, high byte")
    page("rr_tlo2", tl2, "far rows: band 2 template, low byte")
    align()
    emit(";; Line list order is bottom line first. For each entry, where SP starts:")
    emit(";; the end of that line, relative to the bottom half's base (#8000 for")
    emit(";; buffer 0, #0000 for buffer 1).")
    emit("line_ends")
    for k in range(ROAD_LINES):
        y = ROAD_END - 1 - k
        off = (y & 7) * 0x800 + ((y >> 3) - 20) * 96 + 96
        emit("    defw #%04X   ; line %d" % (off, y))

    # hill levels: hill = 2*level - 128, clamped so the road never ends lower
    # than ROAD_TOP_MAX
    hill_max = max(h for h in range(0, 128, 2)
                   if next(i for i, r in enumerate(scene.project(h))
                           if r is not None) + ROAD_Y <= ROAD_TOP_MAX)
    maps, ground, near = [], [], []
    for level in range(scene.HILL_LEVELS):
        hill = min(scene.level_hill(level), hill_max)
        rows = scene.project(hill)                 # top line first
        bottom_first = [r or 0 for r in reversed(rows)]
        maps.append(bottom_first)
        ground.append(sum(1 for r in rows if r is None))
        near.append(sum(1 for r in rows if r and row_depth(r) <= FAR_Z))
    align()
    emit("HILL_MAX EQU %d   ; the strongest crest the road top allows" % hill_max)
    emit(";; per hill level (hill = 2*level - 128): lines at the top that are")
    emit(";; ground, and lines at the bottom that show striped rows")
    emit("level_ground")
    for i in range(0, 128, 16):
        emit("    defb " + ",".join(str(v) for v in ground[i:i + 16]))
    emit("level_near")
    for i in range(0, 128, 16):
        emit("    defb " + ",".join(str(v) for v in near[i:i + 16]))
    page("rr_thi2", th2, "far rows: band 2 template, high byte")
    emit("level_addr")
    for i in range(0, 128, 8):
        emit("    defw " + ",".join("level_%d" % l for l in range(i, i + 8)))
    emit(";; per hill level: the row each road line shows, bottom line first")
    for level, m in enumerate(maps):
        emit("level_%d" % level)
        for i in range(0, len(m), 28):
            emit("    defb " + ",".join(str(v) for v in m[i:i + 28]))
    emit("    ASSERT rr_tlo2 == rr_tlo+#400")
    emit("    ASSERT rr_thi2 == rr_tlo2+#300")
    open(os.path.join(ROOT, "src", "gen", "roadrows.asm"), "w").write(
        "\n".join(lines) + "\n")

    # the game (bank 7) needs the ground per level too: the horizon follows it
    g = [";; Generated by tools/mkroad.py - do not edit.",
         ";; level_ground again, for the game in bank 7: per hill level, the road",
         ";; lines at the top that no row reaches - how far the horizon drops.",
         "hz_ground"]
    for i in range(0, 128, 16):
        g.append("    defb " + ",".join(str(v) for v in ground[i:i + 16]))
    open(os.path.join(ROOT, "src", "gen", "roadground.asm"), "w").write(
        "\n".join(g) + "\n")

    print("road cores: bank 4 %d bytes, bank 5 %d bytes; templates %d bytes a "
          "level, %d levels" % (sizes["roada.asm"], sizes["roadb.asm"], used, LEVELS))


if __name__ == "__main__":
    main()
