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

Also written here, for road.asm:
  * a template per (band, half) for the road centred on the screen - the four
    words road_draw pops for a line (core entry, left grass entry, exit patch
    address, right grass entry) - see road.asm,
  * per-row tables: depth, 256/row and the templates of the row's two bands.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cpcgfx import (BANDS, HALF_MAX, MIN_HALF, ROWS, FAR_Z, far_mask, m0_byte, m0_solid,
                    road_row_pixels, row_half_bytes, row_depth, SCR_BYTES,
                    ROAD_Y, ROAD_TOP_MAX)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "src", "gen", "roadcores.asm")

PAIRS = SCR_BYTES // 2          # 48 pairs per line
CENTRE = SCR_BYTES // 2         # the road is centred on byte 48


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


def template(variants, band, half):
    """The four words road_draw pops for a road of `half` centred on the
    screen (see common.asm)."""
    code, entry, np_, H = variants[(band, half, 0)]
    parity = (CENTRE + H) & 1
    code, entry, np_, H = variants[(band, half, parity)]
    name = "rc_%d_%d_%d" % (band, half, parity)
    u = (CENTRE + H + parity) // 2
    l = u - np_
    rg = max(0, min(u, PAIRS))
    if u <= 0 or l >= PAIRS:
        iy = "empty_core"
        patch = "patch_dummy"
    else:
        iy = "%s+%d" % (name, entry[max(0, u - PAIRS)])
        patch = "%s+%d" % (name, entry[u]) if l < 0 else "patch_dummy"
    reg = REG_BAND[band]
    ix = "lgrass%s+%d" % ("ab"[reg], PAIRS - max(0, min(l, PAIRS)))
    flags = (0x80 if reg else 0) | (0x40 if patch == "patch_dummy" else 0)
    return "tmpl_%d_%d  defw %s,%s,%s,#%02X%02X" % (band, half, iy, ix, patch,
                                                   rg, flags)


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
                 ";; Road core variants for stripe band(s) %s." % (bands,),
                 ";; rc_<band>_<half>_<parity>: the code; _e: one byte per pair,",
                 ";; the offset of that pair's code, then the offset of the end.", ""]
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
                    emit(name + "_e")
                    for i in range(0, len(entry), 16):
                        emit("    defb " + ",".join(str(e) for e in entry[i:i + 16]))
                    size += len(code) + len(entry)
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
    emit("")
    emit(";; How wide (pairs) and how far right of the centre (bytes) each")
    emit(";; variant reaches, for when the road is not centred")
    for (band, half, parity), (code, entry, np_, H) in sorted(variants.items()):
        emit("rc_%d_%d_%d_NP EQU %d" % (band, half, parity, np_))
        emit("rc_%d_%d_%d_H  EQU %d" % (band, half, parity, H))
    open(os.path.join(ROOT, "src", "gen", "roadconsts.asm"), "w").write(
        "\n".join(lines) + "\n")

    # --- templates: band 0 (and band 2) in fragment 5, band 1 in fragment 6
    # at the same offsets, #800 on ---
    head = [";; Generated by tools/mkroad.py - do not edit.",
            ";; Centred templates, in common memory: what road_draw pops for a",
            ";; line whose road is centred on byte %d:" % CENTRE,
            ";;   dw core entry (IY), left grass entry (IX), exit patch address,",
            ";;   and a word for POP AF: A = right grass entry (low byte),",
            ";;   F: bit 7 (S) = band B registers, bit 6 (Z) = no exit patch.", ""]
    for band in range(2):
        lines = list(head)
        lines.append("tmpl_band%d" % band)
        for half in halves(band):
            lines.append(template(variants, band, half))
        if band == 0:
            lines += ["", ";; band 2 - far away: band A's grass and asphalt, band B's",
                      ";; markings - drawn with band A's registers"]
            for half in halves(2):
                lines.append(template(variants, 2, half))
        open(os.path.join(ROOT, "src", "gen", "roadtmpl%d.asm" % band), "w").write(
            "\n".join(lines) + "\n")

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
            for a in (tl, tl2):
                a.append("lo(tmpl_ground)")
            for a in (th, th2):
                a.append("hi(tmpl_ground)")
            dp.append("0")
            mk.append("0")
            continue
        h = row_half_bytes(r)
        tl.append("lo(tmpl_0_%d)" % h)
        th.append("hi(tmpl_0_%d)" % h)
        far = row_depth(r) > FAR_Z
        tl2.append("lo(tmpl_2_%d)" % h if far else "0")
        th2.append("hi(tmpl_2_%d)" % h if far else "0")
        dp.append(str(row_depth(r) & 0xFF))
        mk.append(str(far_mask(r)))
    emit(";; Per row r (1..%d; 0 = the ground), page-aligned so a row is an" % ROWS)
    emit(";; index and the next array is INC H away. The stripe or dash a row")
    emit(";; is in is (depth + camera) AND mask, which needs only low bytes.")
    emit(";; Near rows: band 1's template is #800 above band 0's, and mask 16")
    emit(";; rotated right once is the #08 to add to the high byte. Rows past")
    emit(";; FAR_Z: a longer dash, and band 0's or band 2's template.")
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

    print("road cores: bank 4 %d bytes, bank 5 %d bytes (code + entry offsets)"
          % (sizes["roada.asm"], sizes["roada.asm" if False else "roadb.asm"]))


if __name__ == "__main__":
    main()
