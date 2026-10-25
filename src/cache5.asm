;; ===========================================================================
;; cache5.asm - the cache's work in bank 5 (RAM_C5; see cache.asm): where
;; each group goes, and band B's templates.
;; ===========================================================================

CACHE_B     EQU TMPL_B+CACHE_LEVEL*TMPL_SET
    ASSERT (CACHE_B & #1FF) == 0 && (rd_t5 & #FF) == 0

;; Per group g, at RA_<name> + g (tools/mkroad.py: in the room after each
;; band B template set's near slots, L = #CD + g its lane) - cpcgfx.
;; road_shift's sums, in 1/256 bytes:
;;
;;   PL, PH     P = PERSP_P half: a pair of road_x's move (P2L, P2H: two)
;;   AL, AH     A' = k c1 + x P + 128 + 64, + 256 H (H: RA_H)
;;   AO         a: H + the shift it is at, the high byte of A' - 64 + t
;;   WL, WH     W = k d / 4: the bias's w is W + 5 road_x (+ W_NONE: none)
;;   FL         the bias's table: hi(rd_tent0), or rd_tent1 (turned round
;;              for an odd half); 0: none
;;   C1L, C1H   c1: a curve level's move
;;   DA         -d: a level's slope
;;   KK         the curve level it is at, + CURVE_K
;;
;; (A' is A + 64 so that its low byte's sign tells if t, up to 64 either
;; way, can move a: only when it is 0..127.)
    ASSERT lo(RA_PL) == #CD && #CD+NGROUPS == 256 && PERSP_P == 10
    ASSERT RA_PH == RA_PL+#200 && RA_P2H == RA_P2L+#200
    ASSERT RA_AH == RA_AL+#200 && RA_AO == RA_AH+#200
    ASSERT RA_WH == RA_WL+#200 && RA_FL == RA_WH+#200
    ASSERT RA_C1H == RA_C1L+#200 && (W_NONE & #FF) == 0
    ASSERT (rd_tent0 & #FF) == 0 && (rd_tent1 & #FF) == 0

;; ---------------------------------------------------------------------------
;; st5 - road_x has moved rd_s pairs (1 or 2, either way; road_x is after's):
;; each group's A' moves P a pair. Where that moves its a, it goes on the
;; list for bank 4 (rd_lsp: tl_a), and its band B template is made there
;; and then (TM_PUT); its rows' share of road_x for the bushes (rd_gp)
;; moves as far. Destroys everything.
;; ---------------------------------------------------------------------------
st5
    call gs_set_w
    ld a,(rd_s)
    call st5_set
    ld a,st5_moved-st5_mvj-2            ; the far groups first (st5_fend)
    ld (st5_mvj+1),a
    ld a,#C3
    ld hl,st5_fend
    ld (st5_end),a
    ld (st5_end+1),hl
    ld (st5_sp+1),sp
    ld sp,rd_ltop
    ld hl,#00FE                         ; the list's end
    push hl
    ld l,#CD                            ; group 0
    jp st5_grp

;; the loop: L = a group's lane, SP = the list
st5_grp
st5_ph
    ld h,hi(RA_PL)                      ; (self-modified: RA_P2L)
    ld c,(hl)
    inc h
    inc h
    ld b,(hl)                           ; BC = P
    ld h,hi(RA_AL)
    ld a,(hl)
st5_op1
    add a,c                             ; (self-modified: SUB C, OR A)
    ld (hl),a
    jp p,st5_bias                       ; 0..127: the bias may move a
    inc h
    inc h
    ld a,(hl)
st5_op2
    adc a,b                             ; (self-modified: SBC A,B, OR A)
    ld (hl),a                           ; a: A''s high byte
    inc h
    inc h
st5_cmp
    cp (hl)                             ; (RA_AO)
st5_mvj
    jr nz,st5_moved                     ; (self-modified: st5_movedn)
st5_next
    inc l
st5_end
    jp nz,st5_grp                       ; (self-modified: JP st5_fend, JP
    ld (rd_lsp),sp                      ; j5_back)
st5_sp
    ld sp,0                             ; (self-modified)
    jp st5_mark
st5_fend                                ; the far groups done: the rest, with
    ld a,l                              ; no band 2
    cp #CD+NFAR
    jp c,st5_grp
    ld a,st5_movedn-st5_mvj-2
    ld (st5_mvj+1),a
    ld a,#C2                            ; JP NZ,st5_grp
    ld hl,st5_grp
    ld (st5_end),a
    ld (st5_end+1),hl
    ld l,#CD+NFAR
    jp st5_grp
st5_back
    ld a,ixl
    ld l,a
    jr st5_next
st5_moved
    ld b,a                              ; it moved: noted ...
    sub (hl)
    ld (hl),b
st5_gp
    ld h,hi(rd_gp)                      ; (self-modified: SGP)
    add a,(hl)
    ld (hl),a                           ; (rd_gp: as far)
    ld a,l
    ld ixl,a
    sub #CD
    add a,a
    ld c,a
    push bc                             ; ... on the list ...
    cp 2*NFAR
    jr nc,st5_tb
    add a,2*NGROUPS
    ld c,a
    push bc                             ; (band 2's too)
    sub 2*NGROUPS
    jr st5_tb
st5_movedn                              ; (a group with no far rows)
    ld b,a
    sub (hl)
    ld (hl),b
    ld h,hi(rd_gp)
    add a,(hl)
    ld (hl),a
    ld a,l
    ld ixl,a
    sub #CD
    add a,a
    ld c,a
    push bc
st5_tb
    ld l,a
    ld h,b
    add a,2
    TM_PUT b,lgrassb,rd_t5,CACHE_B,st5_back   ; ... band B's template

;; A' low byte 0..127 (A), H = RA_AL, BC = P, CF its carry: a = the high
;; byte of A' - 64 + t (cpcgfx.road_shift, shift_tau):
;;
;;   w = W + 5 road_x (gb_xl, gb_xh)
;;   t = shift_tau(4 w): -64..64, 0 out of -128..127 - turned round for an
;;       odd half-width, at most 63 (rd_tent0, 1: t - 64, -128..-1)
st5_bias
    ld e,a
    inc h
    inc h
    ld a,(hl)
st5_op3
    adc a,b                             ; (self-modified: SBC A,B, OR A)
    ld (hl),a
    ld d,a                              ; DE = A'
    ld h,hi(RA_WL)
    ld a,(hl)
gb_xl
    add a,0                             ; (self-modified: 5 road_x)
    ld c,a
    inc h
    inc h
    ld a,(hl)
gb_xh
    adc a,0                             ; (self-modified) A:C = w
    rl c
    adc a,0
    jr nz,st5_nob                       ; not -128..127: none
    rr c
    inc h
    inc h
    ld b,(hl)                           ; BC: t - 64 (RA_FL: rd_tent0, 1)
    ld a,(bc)
    add a,e
    ld a,d
    adc a,#FF
    ld h,hi(RA_AO)
    jp st5_cmp
st5_nob
    ld a,e
    sub 64
    ld a,d
    sbc a,0
    ld h,hi(RA_AO)
    jp st5_cmp

;; st5_set - A = a step, 1 or 2 either way: st5's P (st5_ph) and its way
;; (st5_op1..3) for it. Destroys AF, BC, E.
st5_set
    ld bc,#8881                         ; ADC A,B / ADD A,C: to the right
    or a
    jp p,st5_dir
    neg
    ld bc,#9891                         ; SBC A,B / SUB C: to the left
st5_dir
    ld e,hi(RA_PL)
    dec a
    jr z,st5_one
    ld e,hi(RA_P2L)                     ; two pairs
st5_one
    ld a,e
    ld (st5_ph+1),a
    ld a,c
    ld (st5_op1),a
    ld a,b
    ld (st5_op2),a
    ld (st5_op3),a
    ret

;; st5_none - st5 with no step (job5, prk5): OR A for its ops. Destroys A.
st5_none
    ld a,#B7
    ld (st5_op1),a
    ld (st5_op2),a
    ld (st5_op3),a
    ret

;; gb_xl, gb_xh: 5 road_x (gs_set_wa: 5 A). Destroys AF, DE, HL.
gs_set_w
    ld a,(road_x)
gs_set_wa
    ld l,a
    add a,a
    sbc a,a
    ld h,a
    ld d,h
    ld e,l
    add hl,hl
    add hl,hl
    add hl,de
    ld a,l
    ld (gb_xl+1),a
    ld a,h
    ld (gb_xh+1),a
    ret

;; ---------------------------------------------------------------------------
;; job5 - a batch: from group rd_next on, the next JOB_BATCH groups still
;; to be put at cache_k (rd_gk bit 1), NGROUPS looked at at most. Each has
;; its sums moved to cache_k's (j5_level) and goes where they say, as in
;; st5 with no step: on the list if it moved, and its band B template made;
;; and is noted as moved for both buffers then (cache_mark). job4 makes
;; band A's and band 2's (tl_a). Destroys everything.
;; ---------------------------------------------------------------------------
JOB_BATCH   EQU 3

job5
    ld hl,#00FE
    ld (rd_ltop-2),hl                   ; an empty list
    ld hl,rd_ltop-2
    ld (rd_lsp),hl
    call st5_none
    ld a,st5_moved-st5_mvj-2
    ld (st5_mvj+1),a
    ld a,#C3                            ; JP j5_back: one group
    ld hl,j5_back
    ld (st5_end),a
    ld (st5_end+1),hl
    ld a,(rd_next)
    ld e,a                              ; E = g
    ld a,JOB_BATCH
    ld (job_left),a
    ld c,NGROUPS                        ; C: the groups still to look at
j5_loop
    ld a,e
    or lo(rd_gk)
    ld l,a
    ld h,hi(rd_gk)
    bit 1,(hl)
    jr z,j5_next
    res 1,(hl)
    ld hl,rd_n2
    dec (hl)
    push bc
    push de
    ld a,e
    add a,#CD
    ld l,a
    call j5_level
    ld (j5_sp+1),sp
    ld sp,(rd_lsp)
    jp st5_grp
j5_back
    ld hl,(rd_lsp)
    ld (rd_lsp),sp
j5_sp
    ld sp,0                             ; (self-modified)
    ld de,(rd_lsp)
    and a
    sbc hl,de
    pop de
    pop bc
    ld a,e
    call nz,cache_mark                  ; it moved
    push bc
    push de
    ld a,e
    add a,#CD
    ld l,a
    call j5_s0                          ; (rd_gp)
    pop de
    pop bc
    ld hl,job_left
    dec (hl)
    jr z,j5_last
    ld a,(rd_n2)
    or a
    jr z,j5_last                        ; none left
j5_next
    call j5_inc
    dec c
    jr nz,j5_loop
    jr j5_end
j5_last
    call j5_inc
j5_end
    ld a,e
    ld (rd_next),a
    ret

j5_inc
    inc e
    ld a,e
    cp NGROUPS
    ret c
    ld e,0
    ret

;; j5_level - L = a group's lane: its A' moved to cache_k's curve level a
;; level at a time (RA_KK, c1), and its W worked out for it. Keeps L.
j5_level
    ld a,(cache_k)
    add a,CURVE_K
    ld c,a                              ; C = the level wanted + CURVE_K
j5_lv
    ld h,hi(RA_KK)
    ld a,(hl)
    cp c
    jr z,j5_w
    jr c,j5_up
    dec (hl)
    ld h,hi(RA_C1L)
    ld e,(hl)
    inc h
    inc h
    ld d,(hl)
    ld h,hi(RA_AL)
    ld a,(hl)                           ; a level down: - c1
    sub e
    ld (hl),a
    inc h
    inc h
    ld a,(hl)
    sbc a,d
    ld (hl),a
    jr j5_lv
j5_up
    inc (hl)
    ld h,hi(RA_C1L)
    ld e,(hl)
    inc h
    inc h
    ld d,(hl)
    ld h,hi(RA_AL)
    ld a,(hl)                           ; a level up: + c1
    add a,e
    ld (hl),a
    inc h
    inc h
    ld a,(hl)
    adc a,d
    ld (hl),a
    jr j5_lv
j5_w                                    ; W = k d / 4, rounded down
    sub CURVE_K
    ld b,a                              ; B = k
    ld h,hi(RA_DA)
    xor a
    sub (hl)
    ld e,a
    sbc a,a
    ld d,a                              ; DE = d (-DA)
    bit 7,b
    jr z,j5_wk
    ld e,(hl)
    ld d,0                              ; k < 0: -d, -k times
    ld a,b
    neg
    ld b,a
j5_wk
    ld ix,0
    inc b
    jr j5_wm1
j5_wm
    add ix,de
j5_wm1
    djnz j5_wm                          ; IX = k d
    ld a,ixh
    ld d,a
    ld a,ixl
    ld e,a
    sra d
    rr e
    sra d
    rr e
    ld h,hi(RA_FL)
    ld a,(hl)
    or a
    jr nz,j5_wb
    ld a,d
    add a,hi(W_NONE)                    ; no bias: never in range
    ld d,a
j5_wb
    ld h,hi(RA_WL)
    ld (hl),e
    inc h
    inc h
    ld (hl),d
    ret

;; j5_s0 - L = a group's lane: its rows' share of road_x for the bushes
;; (rd_gp): its a less the a it has at its curve level with the road in the
;; middle (cpcgfx.road_shift(k, r, 0), worked out as st5_bias does). Keeps
;; L. Destroys AF, BC, DE, H, IX.
j5_s0
    ld h,hi(RA_H)
    ld a,(hl)
    ld ixh,a
    ld ixl,128+64                       ; IX = 256 H + 128 + 64 ...
    ld h,hi(RA_KK)
    ld a,(hl)
    sub CURVE_K
    ld b,a                              ; B = k
    ld h,hi(RA_C1L)
    ld e,(hl)
    inc h
    inc h
    ld d,(hl)                           ; DE = c1
    or a
    jp p,j5_s0p
    neg
    ld b,a
    xor a
    sub e
    ld e,a
    sbc a,a
    sub d
    ld d,a                              ; (k < 0: -c1, -k times)
j5_s0p
    inc b
    jr j5_s0m1
j5_s0m
    add ix,de
j5_s0m1
    djnz j5_s0m                         ; ... + k c1: A' in the middle
    ld h,hi(RA_WL)
    ld c,(hl)
    inc h
    inc h
    ld a,(hl)                           ; A:C = w, W
    rl c
    adc a,0
    ld de,-64
    jr nz,j5_s0t                        ; not -128..127: t = 0
    rr c
    inc h
    inc h
    ld b,(hl)
    ld a,(bc)
    ld e,a
    add a,a
    sbc a,a
    ld d,a                              ; DE = t - 64
j5_s0t
    add ix,de
    ld h,hi(RA_AO)
    ld a,(hl)
    sub ixh
j5_gp
    ld h,hi(rd_gp)                      ; (self-modified: SGP - prk5)
    ld (hl),a
    ret

;; ---------------------------------------------------------------------------
;; cache_reset - (cache_init) every group's sums for curve level 0 and the
;; road in the middle, its place none yet (its templates are made).
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
cache_reset
    call gs_set_w
    ld l,#CD
cr_loop
    ld h,hi(rd_gp)
    ld (hl),0
    ld h,hi(RA_AL)
    ld (hl),128+64
    ld h,hi(RA_H)
    ld a,(hl)
    ld h,hi(RA_AH)
    ld (hl),a
    ld h,hi(RA_AO)
    ld (hl),#80
    ld h,hi(RA_KK)
    ld (hl),CURVE_K
    ld h,hi(RA_FL)
    ld a,(hl)
    or a
    ld a,0
    jr nz,cr_w
    ld a,hi(W_NONE)
cr_w
    ld h,hi(RA_WH)
    ld (hl),a
    ld h,hi(RA_WL)
    ld (hl),0
    inc l
    jr nz,cr_loop
    ret

;; ---------------------------------------------------------------------------
;; The next step or curve level worked out ahead (cache_pre, cache.asm):
;; into the staging sets - STAGE_B here, STAGE_A in bank 4 - the cache
;; sets' templates as they are to be after it, and into SGP rd_gp's, so
;; that the step or level itself only copies them into place (cm5 or cmk5,
;; cm4). Its sums go there and then (A', a - and a level's KK, W - for the
;; groups so far: pre_g; SB keeps the a's they had, for undo5 or undok5 to
;; put back if it is dropped).
;; ---------------------------------------------------------------------------
STAGE_B     EQU #5E00                   ; set out as a template set
SGP         EQU #5FCD                   ; per group, at its lane
SB          EQU #7FCD                   ; (the cache set's room)
    ASSERT lo(SGP) == #CD && lo(SB) == #CD && CACHE_B+8*(1+NGROUPS) <= SB
PRE_BATCH   EQU 12                      ; groups a piece at most (pre5, pre4)
PRK_BATCH   EQU 8                       ; ... a level's (prk5: more work each)
PRE_PUTS    EQU 7                       ; ... and bank 4 templates

;; pre5 - a piece: from group pre_g on, groups moved pre_s pairs as st5
;; moves them - those whose a moves on the list for pre4, their band B
;; templates in STAGE_B - till PRE_PUTS templates are to be made in bank 4,
;; PRE_BATCH groups are done or the flip is near (JOB_LATE: a group and
;; pre4's templates take up to ~1.3 ms, and the flip is 3.3 ms away then).
;; prk5 - as pre5, the groups moved to the curve level cache_k + pre_k
;; instead (j5_lv; no step), their shares for the bushes worked out afresh
;; (j5_s0, into SGP), PRK_BATCH a piece (in cache.asm's rd_gfree: no room
;; here). Destroys everything.
pre5
    ld a,(pre_s)
    call st5_set
    ld a,(pre_s)
    ld l,a
    ld a,PRE_BATCH
    ld bc,st5_grp
    ld de,p5_back
p5_set                                  ; A = the groups, BC: each one's
    ld (p5_bat+1),a                     ; work, DE: back from it, L = road_x's
    ld (p5_more+1),bc                   ; move
    ld (st5_end+1),de
    ld a,(road_x)
    add a,l
    call gs_set_wa                      ; (the bias for road_x after it)
    ld a,(pre_g)
    or a
    jr nz,p5_go
    dec a
    ld (pre_g0),a                       ; the first piece: none moved yet,
    ld hl,RA_AO                         ; the a's kept
    ld de,SB
    ld bc,NGROUPS
    ldir
p5_go
    ld a,st5_moved-st5_mvj-2
    ld (st5_mvj+1),a
    ld a,#C3                            ; JP p5_back, pk5_back: one group
    ld (st5_end),a
    ld a,hi(STAGE_B)
    ld (tm_b_page+1),a
    ld a,hi(SGP)
    ld (st5_gp+1),a
    ld hl,#00FE
    ld (rd_ltop-2),hl                   ; an empty list
    ld (p5_sp+1),sp
    ld sp,rd_ltop-2
    ld a,(pre_g)
    add a,#CD
    ld l,a                              ; L: the first group's lane
p5_bat
    add a,0                             ; (self-modified: the groups)
    jr nc,$+3
    xor a                               ; (past the last: 0)
    ld (p5_end+1),a
    or a
    jr p5_more
pk5_back                                ; (a level's)
    dec l
    call j5_s0                          ; the group's share for the bushes
    inc l
p5_back
    ld a,l
p5_end
    cp 0                                ; (self-modified: the lane after)
    jr z,p5_done
    ld a,(irq_n)
    cp JOB_LATE
    jr nc,p5_done                       ; the flip near
    ld (rd_lsp),sp
    ld a,(rd_lsp)
    cp lo(rd_ltop-2-2*PRE_PUTS)+1       ; (the templates for bank 4 so far)
p5_more
    jp nc,st5_grp                       ; (self-modified: pk5_grp)
p5_done
    ld (rd_lsp),sp
p5_sp
    ld sp,0                             ; (self-modified)
    ld a,l
    sub #CD
    ld (pre_g),a                        ; (0 - #CD: NGROUPS)
    ld a,(pre_g0)
    inc a
    call z,st5_first                    ; the first group it moves, if none
    dec a                               ; yet
    ld (pre_g0),a
    call pk5_last
    ld a,hi(CACHE_B)
    ld (tm_b_page+1),a
    ld a,hi(rd_gp)
    ld (st5_gp+1),a
    ld (j5_gp+1),a
    ret
pk5_grp
    ld c,0                              ; (self-modified: the level +
    call j5_lv                          ; CURVE_K)
    jp st5_grp

;; undo5 - (cache_drop) the groups pre5 has moved put back: their A' moved
;; pre_s pairs the other way, their a's as SB has them. Destroys
;; everything.
undo5
    ld a,(pre_s)
    neg
    call st5_set                        ; (st5 sets them again)
    ld a,(st5_ph+1)
    ld (u5_ph+1),a
    ld a,(st5_op1)
    ld (u5_op1),a
    ld a,(st5_op2)
    ld (u5_op2),a
    ld a,(pre_g)
    add a,#CD
    ld (u5_end+1),a
    ld l,#CD
u5_loop
u5_ph
    ld h,0                              ; (self-modified: RA_PL, RA_P2L)
    ld c,(hl)
    inc h
    inc h
    ld b,(hl)
    ld h,hi(RA_AL)
    ld a,(hl)
u5_op1
    add a,c                             ; (self-modified: SUB C)
    ld (hl),a
    inc h
    inc h
    ld a,(hl)
u5_op2
    adc a,b                             ; (self-modified: SBC A,B)
    ld (hl),a
    inc l
    ld a,l
u5_end
    cp 0                                ; (self-modified)
    jr nz,u5_loop
u5_ao
    ld hl,SB
    ld de,RA_AO
    ld bc,NGROUPS
    ldir
    jp gs_set_w

;; cm5 - (cache_commit) SGP into rd_gp, and STAGE_B's templates into the
;; cache set (from the first group with band B rows on); rs5 - the other
;; way, STAGE_B and SGP made the cache's again. Destroy BC, DE, HL.
cm5
    ld a,(pre_g0)
    cp 255
    call nz,st5_marka
cm5_c
    ld hl,SGP
    ld de,rd_gp
    ld bc,NGROUPS
    ldir
    ld hl,STAGE_B+8*(1+NFARONLY)
    ld de,CACHE_B+8*(1+NFARONLY)
c5_n
    ld bc,8*(NGROUPS-NFARONLY)
c5_copy
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    jp pe,c5_copy
    ret
rs5
    ld hl,rd_gp
    ld de,SGP
    ld bc,NGROUPS
    ldir
    ld hl,CACHE_B+8*(1+NFARONLY)
    ld de,STAGE_B+8*(1+NFARONLY)
    jr c5_n

;; st5_mark - after st5: the groups from the first whose a moved on are
;; noted as moved for both buffers (cache_mark; st5_marka: A = that one) -
;; the rows of those before it are as they were (rp_mode_chg). Destroys
;; AF, DE, HL.
st5_mark
    call st5_first
    or a
    ret z                               ; none moved
    dec a
st5_marka
    call cache_mark
    ld a,NGROUPS-1
    jp cache_mark

;; st5_first - after a pass of st5's loop: A = 1 + the first group on its
;; list (rd_list: pushed first, after the end), 0 if it is empty. Destroys
;; F, DE, HL.
st5_first
    ld hl,(rd_lsp)
    ld de,rd_ltop-2
    xor a
    sbc hl,de
    ret z
    ld a,(rd_ltop-4)                    ; 2 g
    srl a
    inc a
    ret

cache5_bank_end
    ASSERT cache5_bank_end <= STAGE_B

;; ---------------------------------------------------------------------------
;; In the room between STAGE_B's slots and SGP (undok5: in cache.asm's
;; rd_gfree).
;; ---------------------------------------------------------------------------
    ORG STAGE_B+8*(1+NGROUPS)
stage_room

;; pk5_last - after a piece: pre_g1 = the last group on its list, if any (a
;; level's last group moved: cmk5). Destroys AF, HL.
pk5_last
    ld hl,(rd_lsp)
    ld a,(hl)                           ; 2 g (band 2's: + 2 NGROUPS)
    cp #FE
    ret z                               ; (the list's end: none)
    cp 2*NGROUPS
    jr c,$+4
    sub 2*NGROUPS
    srl a
    ld (pre_g1),a
    ret

;; cmk5 - as cm5, for a curve level: the groups from the first whose a it
;; moved to the last noted as moved for both buffers (cache_mark).
cmk5
    ld a,(pre_g0)
    cp 255
    jp z,cm5_c
    call cache_mark
    ld a,(pre_g1)
    call cache_mark
    jp cm5_c

stage_room_end
    ASSERT stage_room_end <= SGP
