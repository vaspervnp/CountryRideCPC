;; ===========================================================================
;; roadm2.asm - road_draw's way for a line flagged 2 when the hill and the
;; road have both moved since its buffer was last drawn (rp_side_hill): a
;; copy in bank 4 for band A's lines and one in bank 5 for band B's, each
;; run with its bank in (road_draw: lg2_a, lg2_b).
;; ===========================================================================

;; LINE_M2 n,lt - line_m2_<n>: as line_marg2_<n> (common.asm) - only the
;; road and a margin - with the margin rp_side_hill set (lm2_mt: PAIRS - the
;; right one; lt: lo(lgrass) + PAIRS - the left one), not rd_margin's: a
;; line showing another row needs a row's margin as well as the road's
;; move's. HL = the template + 2, DE = the screen. Keeps BC.
MACRO LINE_M2 n,lt
line_m2_{n}
    dec l
    dec l
    ld sp,hl
    pop iy
    pop af                              ; A = right grass entry, Z = no patch
    pop ix
    jr nz,@patch
    ld l,a
    ld a,({lt})
    cp ixl
    jr c,@right
    ld ixl,a                            ; no more left grass than the margin
@right
    ld a,(lm2_mt)
    ld h,a
    ld a,l
    cp h
    jp nc,line_margin_all               ; no more right grass than it either
    sub h
    add a,a
    ld l,a
    ld a,h
    ld h,#FF
    add hl,de
    ld sp,hl                            ; the screen, the margin right of the
    ld l,a                              ; core: that many pairs of grass
    ld h,hi(rgrass)
    jp (hl)

@patch                                  ; the core hangs off the left: no
    pop hl                              ; left grass; SP at the patch address
    ld (hl),#E9                         ; JP (HL)
    ex de,hl                            ; DE = patch address, HL = screen
    ld ixh,a
    ld a,(lm2_mt)
    sub ixh
    jr c,@all
    jr z,@all
    add a,a
    neg
    add a,l
    ld l,a                              ; the screen, the margin right of the
    jr c,$+3                            ; core
    dec h
    ld a,(lm2_mt)
    jr @go
@all
    ld a,ixh
@go
    ld sp,hl
    ld l,a
    ld h,hi(rgrass)
    jp (hl)
MEND
