;; ===========================================================================
;; lanes5.asm - the road's lanes changing, bank 5's part (RAM_C5; then
;; lanes.asm's in bank 4: cache.asm lane_can, common.asm lane_must).
;;
;; Each template group has its lanes - 4, 3 or 2 - in RA_LN, and the road
;; on its rows is as wide as they are (cpcgfx.lane_half: each lane as wide
;; as four's). The track asks for others from lane_z on (lane_ask,
;; common.asm): each group takes them, the furthest first (lane_h), when
;; its furthest row is past lane_z (lane_bt) - or up to LANE_EARLY before,
;; in the time left before a flip (lane_at). Its H (lane_hs) and so its A'
;; and its a move as far as its core's edge does, its per group tables
;; (rd_t5, rd_t4) are the new lanes' (rd_s5_<n>, rd_s4_<n>), its templates
;; are made afresh, and both buffers draw its rows whole next (lane_ghi,
;; lane_glo; road6.asm rp_lane_whole).
;; ===========================================================================

LANE_CAN_N  EQU 5                       ; groups at most at a time: before a
LANE_MUST_N EQU 1                       ; flip (lane_g5c), and before
                                        ; road_project (lane_g5m: ~0.8 ms a
                                        ; far one, in a picture that may be
                                        ; heavy - the road bent on a hill)
    ASSERT rd_s5_3 == rd_s5_4+#200 && rd_s5_2 == rd_s5_3+#200
    ASSERT lane_dh == lane_dl+#100 && lo(lane_dl) == 0 && lo(lane_hs) == 0
                                        ; (lo(rd_ltop) 0: main.asm)

;; ---------------------------------------------------------------------------
;; lane_g5c, lane_g5m - the groups whose lanes can change now (lane_at) or
;; must (lane_bt), to lane_next's - a few at most, and none from the flip's
;; last 3.3 ms on (JOB_LATE): band B's templates made, the list of them
;; for lane_g4 (rd_lsp: a * 256 + 2 g, and band 2's 2 (NGROUPS + g) for the
;; far ones). With all of them done and the camera past lane_z, the lanes
;; are lane_next's (and an empty list). Destroys everything.
;; ---------------------------------------------------------------------------
lane_g5c
    ld hl,lane_at
    ld a,LANE_CAN_N
    jr lg5_go
lane_g5m
    ld hl,lane_bt
    ld a,LANE_MUST_N
lg5_go
    ld (lg5_left+1),a
    ld (lg5_x+2),hl
    ld ix,rd_ltop-2
    ld (ix+0),#FE                       ; an empty list
    ld (ix+1),#00
    xor a
    ld (pre_sync),a                     ; (the staging sets: no longer the
lg5_grp                                 ; cache's)
    ld hl,(zcam)
lg5_x
    ld de,(lane_at)                     ; (self-modified: lane_at, lane_bt)
    or a
    sbc hl,de
    jp m,lg5_list                       ; not yet
    ld a,(lane_h)
    cp NGROUPS+1
    jp nc,lg5_end                       ; all done: the camera past lane_z
    add a,#CD-1
    ld d,a                              ; D = its lane, #CD + g
    sub #CD
    ld e,a                              ; E = g
    ld l,d
    ld h,hi(RA_LN)
    ld a,(lane_next)
    ld (hl),a
    cpl
    add a,4+1
    ld c,a                              ; C = 4 - lanes
    rrca
    rrca
    or e
    ld l,a
    ld h,hi(lane_hs)
    ld b,(hl)                           ; B = its H with them
    ld l,d
    ld h,hi(RA_H)
    ld a,b
    sub (hl)
    ld (hl),b
    ld b,a                              ; B = how far its edge moves
    ld h,hi(RA_AH)
    add a,(hl)
    ld (hl),a                           ; A' and a as far
    ld h,hi(RA_AO)
    ld a,(hl)
    add a,b
    ld (hl),a
    ld b,a                              ; B = a
    ld a,c
    add a,a
    add a,hi(rd_s5_4)
    ld d,a
    push bc
    call lc_b5                          ; band B's table: the new lanes'
    pop bc
    ld a,e
    add a,a                             ; on the list: 2 g, a ...
    dec ix
    dec ix
    ld (ix+0),a
    ld (ix+1),b
    cp 2*NFAR
    jr nc,lg5_mark
    add a,2*NGROUPS                     ; ... and band 2's
    dec ix
    dec ix
    ld (ix+0),a
    ld (ix+1),b
lg5_mark
    ld a,e
    ld hl,lane_ghi                      ; both buffers draw its rows whole
    call mark_hl                        ; (common.asm)
    push bc
    push de
    ld hl,lane_h                        ; the next group's turn: from when
    inc (hl)                            ; its furthest row is past lane_z
    ld a,(hl)
    dec a
    ld hl,(lane_z)
    ld d,h
    ld e,l
    cp NGROUPS
    jr nc,lg5_last                      ; (none: when the camera is)
    ld l,a
    ld h,hi(lane_dl)
    ld c,(hl)
    inc h
    ld b,(hl)                           ; BC = that row's depth
    ex de,hl
    or a
    sbc hl,bc
    ld d,h
    ld e,l
    ld bc,-LANE_EARLY
    add hl,bc
lg5_last
    ld (lane_at),hl
    ld (lane_bt),de
    pop de
    pop bc
    ld a,e
    add a,a
    ld l,a                              ; L = 2 g, H = a
    ld h,b
    add a,2
    TM_PUT lb,lgrassb,rd_t5,CACHE_B,lg5_back  ; its band B template
lg5_back
    ld a,(irq_n)
    cp JOB_LATE
    jr nc,lg5_list                      ; the flip near
lg5_left
    ld a,0                              ; (self-modified: groups left)
    dec a
    ld (lg5_left+1),a
    jp nz,lg5_grp
lg5_list
    ld (rd_lsp),ix
    ret
lg5_end                                 ; the camera past lane_z: the lanes
    ld a,ixl                            ; are lane_next's - once the list is
    cp lo(rd_ltop-2)                    ; empty (lane_g4 reads lane_next)
    jr nz,lg5_list
    ld a,(lane_next)
    ld (lane_now),a
    xor a
    ld (lane_h),a
    ld hl,lane_pend
    ld a,(hl)
    ld (hl),0
    or a
    jr z,lg5_list
    ld hl,(zcam)                        ; one asked for meanwhile: from here
    call lane_ask                       ; on (common.asm)
    jr lg5_list

    LANE_COPY b5,rd_t5
lanes5_end
