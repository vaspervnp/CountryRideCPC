;; ===========================================================================
;; lanes.asm - the road's lanes changing, bank 4's part (RAM_C4; see
;; lanes5.asm): the groups lane_g5c or lane_g5m gave new lanes.
;; ===========================================================================

    ASSERT rd_s4_3 == rd_s4_4+#200 && rd_s4_2 == rd_s4_3+#200

;; ---------------------------------------------------------------------------
;; lane_g4 - (after lane_g5c, lane_g5m) every group on the list (rd_lsp):
;; its band A table, and band 2's, lane_next's lanes' (rd_s4_<n>), and its
;; templates made (tl_a). Destroys everything.
;; ---------------------------------------------------------------------------
lane_g4
    ld a,(lane_next)
    cpl
    add a,4+1                           ; 4 - lanes
    add a,a
    add a,hi(rd_s4_4)
    ld d,a                              ; D = their table's first page
    ld hl,(rd_lsp)
lg4_entry
    ld a,(hl)                           ; 2 g (2 (NGROUPS + g))
    cp #FE
    jp z,tl_a                           ; (the end)
    rrca
    ld e,a
    push hl
    call lc_b4
    pop hl
    inc hl
    inc hl
    jr lg4_entry

    LANE_COPY b4,rd_t4
lanes_end
