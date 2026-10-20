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

The variant runs in the shadow register set. The entry table gives the code
address of every pair, so a core hanging off the right of the screen is
entered part-way in, and one hanging off the left is cut short by writing
JP (HL) (HL' = line_done_shadow) over the first pair that must not be drawn.

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
from cpcgfx import (BANDS, HALF_MAX, MIN_HALF, ROWS, FAR_Z, far_mask, m0_byte, m0_solid,
                    road_row_pixels, row_half_bytes, row_depth, SCR_BYTES,
                    ROAD_Y, ROAD_TOP_MAX, CURVE_K, curve_group, curve_shift)

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


def core_bytes(band, half, parity):
    """Screen bytes of the core, left to right, and H (bytes each side of
    the centre before the parity widening)."""
    b = BANDS[band]
    pens, total = road_row_pixels(half, band)
    H = (total + 1) // 2
    # pixel 0 of the byte-aligned core is centre_px - 2H
    px = [b["grass"]] * (4 * H)
    off = 2 * H - total
    for i, p in enumerate(pens):
        px[off + i] = p
    if parity:
        px = [b["grass"]] * 2 + px + [b["grass"]] * 2
    out = [m0_byte(px[i], px[i + 1]) for i in range(0, len(px), 2)]
    return out, H


# The register set a band's cores run with: band 2 (far away) is drawn by
# road_draw as band A, so its white kerb cannot be PUSH AF (AF' is red then)
# and comes out as LD BC/PUSH BC.
REG_BAND = {0: 0, 1: 1, 2: 0}
FAR_HALF = row_half_bytes(max(r for r in range(1, ROWS + 1)
                              if row_depth(r) > FAR_Z))


def compile_variant(band, half, parity):
    """Returns (code bytes, entry offsets [NP+1], NP, H)."""
    regs = BANDS[REG_BAND[band]]
    road = m0_solid(regs["road"])
    kerb = m0_solid(regs["kerb"])
    data, H = core_bytes(band, half, parity)
    n = len(data)
    assert n % 2 == 0
    code = []
    entry = []
    for j in range(n // 2):
        lo = data[n - 2 - 2 * j]       # left byte of the pair
        hi = data[n - 1 - 2 * j]       # right byte, written first by PUSH
        entry.append(len(code))
        if lo == hi == road:
            code.append(0xD5)                     # PUSH DE
        elif lo == hi == kerb:
            code.append(0xF5)                     # PUSH AF
        else:
            w = word(lo, hi)
            code += [0x01, w & 0xFF, w >> 8, 0xC5]  # LD BC,nn / PUSH BC
    entry.append(len(code))
    code += [0xD9, 0x08, 0xDD, 0xE9]              # EXX / EX AF,AF' / JP (IX)
    return code, entry, n // 2, H


def halves(band):
    """The widths a row can have. Band 2 is only ever used past FAR_Z, where
    the road is narrow."""
    return range(MIN_HALF, (FAR_HALF if band == 2 else HALF_MAX) + 1)


def template(variants, band, half, shift):
    """What road_draw pops for a row of `half` moved `shift` bytes right of
    the centre (see common.asm): core entry (IY), left grass entry (IX), AF
    (A = right grass entry, Z = no exit patch), then the exit patch address
    if the core hangs off the left of the screen. A core cut short there has
    no left grass, so IX holds the byte the patch hides instead. Returns the
    words."""
    code, entry, np_, H = variants[(band, half, 0)]
    c = CENTRE + shift
    parity = (c + H) & 1
    code, entry, np_, H = variants[(band, half, parity)]
    name = "rc_%d_%d_%d" % (band, half, parity)
    u = (c + H + parity) // 2
    l = u - np_
    rg = max(0, min(u, PAIRS))
    patch = None
    if u <= 0 or l >= PAIRS:
        iy = "empty_core"
    else:
        iy = "%s+%d" % (name, entry[max(0, u - PAIRS)])
        if l < 0:
            patch = "%s+%d" % (name, entry[u])
    reg = REG_BAND[band]
    ix = "lgrass%s+%d" % ("ab"[reg], PAIRS - max(0, min(l, PAIRS)))
    if patch:
        ix = "#%04X" % code[entry[u]]
    af = "#%02X%02X" % (rg, 0x40 if patch is None else 0)
    return [iy, ix, af] + ([patch] if patch else [])


GROUND = ["empty_core", "lgrassa+%d" % PAIRS, "#0040"]


def template_slots(variants):
    """The layout of a template set: [(kind, group, size, offset)], kind
    'ground', 'near' (bands 0 and 1) or 'far' (band 2). A slot is 8 bytes if
    any level's template in it has an exit patch, else 6."""
    rows = range(1, ROWS + 1)
    near = list(dict.fromkeys(curve_group(r) for r in rows))
    far = list(dict.fromkeys(curve_group(r) for r in rows if row_depth(r) > FAR_Z))
    half = {curve_group(r): row_half_bytes(r) for r in rows}
    row = {}
    for r in rows:
        row.setdefault(curve_group(r), r)
    slots = [("ground", None, 6)]
    for kind, groups, bands in (("near", near, (0, 1)), ("far", far, (2,))):
        for g in groups:
            words = max(len(template(variants, b, half[g], curve_shift(k, row[g])))
                        for b in bands for k in range(-CURVE_K, CURVE_K + 1))
            slots.append((kind, g, 2 * words))
    out, off = [], 0
    for kind, g, size in slots:
        out.append((kind, g, size, off))
        off += size
    assert off <= TMPL_SET, "templates: %d bytes a level, %d room" % (off, TMPL_SET)
    return out, half, row


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
                 ";; rc_<band>_<half>_<parity>.", ""]
        emit = lines.append
        size = 0
        for band in bands:
            for half in halves(band):
                for parity in range(2):
                    code, entry, np_, H = variants[(band, half, parity)]
                    name = "rc_%d_%d_%d" % (band, half, parity)
                    emit(name)
                    for i in range(0, len(code), 16):
                        emit("    defb " + ",".join("#%02X" % c for c in code[i:i + 16]))
                    size += len(code)
        sizes[fname] = size
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
        emit("GRASS%d_PAIR EQU #%04X" % (band, word(m0_solid(b["grass"]),
                                                  m0_solid(b["grass"]))))
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
        for k in range(-CURVE_K, CURVE_K + 1):
            emit(";; curve level %d" % k)
            for kind, g, size, off in slots:
                if kind == "ground":
                    words = GROUND if side == "a" else None
                elif kind == "near":
                    words = template(variants, 0 if side == "a" else 1, ghalf[g],
                                     curve_shift(k, grow[g]))
                else:
                    words = (template(variants, 2, ghalf[g], curve_shift(k, grow[g]))
                             if side == "a" else None)
                if words is None:
                    emit("    defs %d,0" % size)
                    continue
                emit("    defw " + ",".join(words) + "   ; %s %s" % (kind, g or ""))
                if 2 * len(words) < size:
                    emit("    defs %d,0" % (size - 2 * len(words)))
            emit("    defs %d,0" % (TMPL_SET - used))
        open(os.path.join(ROOT, "src", "gen", fname), "w").write("\n".join(lines) + "\n")

    # --- bank 6: rows, hill tables, line addresses ---
    lines = [";; Generated by tools/mkroad.py - do not edit.",
             ";; Bank 6: what road_project needs to turn a hill and a camera depth",
             ";; into a template for every road line.", ""]
    emit = lines.append

    def page(name, vals, comment):
        emit("    ALIGN 256")
        emit("%s   ; %s" % (name, comment))
        for i in range(0, len(vals), 8):
            emit("    defb " + ",".join(vals[i:i + 8]))

    tl, dp, mk, th, tl2, th2 = [], [], [], [], [], []
    for r in range(ROWS + 1):
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
    emit(";; Per row r (1..%d; 0 = the ground), page-aligned so a row is an" % ROWS)
    emit(";; index and the next array is INC H away. The stripe or dash a row")
    emit(";; is in is (depth + camera) AND mask, which needs only low bytes.")
    emit(";; The templates are the row's group's in the first curve level's set:")
    emit(";; a level is TMPL_SET/256 pages further, and near rows' band 1 is")
    emit(";; TMPL_B - TMPL_A = #2000 above band 0 - mask 16 rotated left once is")
    emit(";; the #20 to add to the high byte. Rows past FAR_Z: a longer dash, and")
    emit(";; band 0's or band 2's template.")
    page("rr_tlo", tl, "band 0 template, low byte")
    page("rr_depth", dp, "depth, low byte")
    page("rr_mask", mk, "16; 32, 64, 128 past FAR_Z; 0 for the ground")
    page("rr_thi", th, "band 0 template, high byte")
    page("rr_tlo2", tl2, "far rows: band 2 template, low byte")
    emit("    ALIGN 256")
    emit(";; Line list order is bottom line first. For each entry, where SP starts:")
    emit(";; the end of that line, relative to the bottom half's base (#8000 for")
    emit(";; buffer 0, #0000 for buffer 1).")
    emit("line_ends")
    for k in range(ROWS):
        y = 271 - k
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
    emit("    ALIGN 256")
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
