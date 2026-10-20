#!/usr/bin/env python3
"""Write a copy of chips' mc6845.h with the vertical timing of a real CRTC.

    crtc_patch.py <original mc6845.h> <patched copy>

The game splits the frame with raster ruptures, and chips' CRTC is not
faithful enough to test them:

  * R5 (vertical total adjust) only lengthens the last character row, so the
    extra lines show that row again. On the CPC's CRTCs the adjust lines come
    after the last row, with the row counter one past R4: when that equals R6
    they are border, otherwise they show the next row.
  * The end of a frame is VCC >= R4 + 1, checked whenever R4 is written. A
    real CRTC only ends the frame when VCC == R4 at the end of a row, and
    runs on to row 127 if R4 was set too late - which is exactly the mistake
    a rupture can make and the test has to catch.

So this keeps everything chips does within a row and replaces what happens
at the end of a row: compare VCC with R4 there, then either the adjust lines,
a new frame, or the next row, with R6 (display) and R7 (VSYNC) compared at
the start of each row. Type 1's reloading of R12/R13 on every line of row 0
is kept.
"""

import sys

src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()


def rep(old, new):
    global s
    assert s.count(old) == 1, old[:60]
    s = s.replace(old, new)


# state for the adjust lines
rep("""    uint8_t vsync_ctr;              /* vertical sync counter */
""", """    uint8_t vsync_ctr;              /* vertical sync counter */
    bool in_adj;                    /* in the R5 lines after the last row */
    uint8_t adj_ctr;                /* R5 lines done */
""")

# a row ends after R9 + 1 lines, R5 no longer stretches the last row
rep("""    uint8_t max_scanline = c->max_scanline_addr;
    if (c->v_ctr == c->v_total) {
        max_scanline += c->v_total_adjust;
    }
""", """    uint8_t max_scanline = c->max_scanline_addr;
""")

# R4 is only looked at at the end of a row
rep("""                        case MC6845_VTOTAL:
                            _mc6845_co_cmp_vtotal(c);
                            break;""", """                        case MC6845_VTOTAL:
                            break;""")

old_start = s.index("/* per scanline updates */")
old_end = s.index("uint64_t mc6845_tick(mc6845_t* c) {")
s = s[:old_start] + """/* per scanline updates (patched: see tools/emu/crtc_patch.py) */
static inline void _mc6845_new_row(mc6845_t* c) {
    if (c->v_ctr == c->v_displayed) {
        c->v_de = false;
    }
    if (c->v_ctr == c->v_sync_pos) {
        c->vs = true;
        c->vsync_ctr = 0;
    }
}

static inline void _mc6845_new_frame(mc6845_t* c) {
    c->in_adj = false;
    c->r_ctr = 0;
    c->v_ctr = 0;
    c->v_de = true;
    c->ma_store = (c->start_addr_hi<<8) | c->start_addr_lo;
    c->ma_row_start = c->ma_store;
    _mc6845_new_row(c);
}

static inline void _mc6845_scanline(mc6845_t* c) {
    c->r_ctr = (c->r_ctr + 1) & 0x1F;
    if (c->in_adj) {
        if (++c->adj_ctr >= c->v_total_adjust) {
            _mc6845_new_frame(c);
        }
    }
    else {
        _mc6845_co_cmp_raster(c);
        if (c->co_raster) {
            c->co_raster = false;
            c->r_ctr = 0;
            if (c->v_ctr == c->v_total) {
                if (c->v_total_adjust) {
                    /* the adjust lines: one row past R4, on from the next
                       row's address */
                    c->in_adj = true;
                    c->adj_ctr = 0;
                    c->v_ctr = (c->v_ctr + 1) & 0x7F;
                    c->ma_row_start = c->ma_store;
                    _mc6845_new_row(c);
                }
                else {
                    _mc6845_new_frame(c);
                }
            }
            else {
                c->v_ctr = (c->v_ctr + 1) & 0x7F;
                c->ma_row_start = c->ma_store;
                _mc6845_new_row(c);
            }
        }
    }
    /* type 1 reloads the start address on every line of row 0 */
    if ((c->type == MC6845_TYPE_UM6845R) && (c->v_ctr == 0) && !c->in_adj) {
        c->ma_store = (c->start_addr_hi<<8) | c->start_addr_lo;
        c->ma_row_start = c->ma_store;
    }
    if (c->vs) {
        _mc6845_co_cmp_vswidth(c);
        c->vsync_ctr++;
        if (c->co_vswidth) {
            c->co_vswidth = false;
            c->vs = false;
        }
    }
}

""" + s[old_end:]

open(dst, "w").write(s)
