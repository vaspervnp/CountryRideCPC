;; ===========================================================================
;; cache5.asm - the cache's work in bank 5 (RAM_C5; see cache.asm): where
;; each group goes, and band B's templates.
;; ===========================================================================

CACHE_B     EQU TMPL_B+CACHE_LEVEL*TMPL_SET
    ASSERT (CACHE_B & #1FF) == 0 && (rd_t5 & #FF) == 0

;; Per group g, at RA_<name> + g (tools/mkroad.py: a page each, L = #CD +
;; g its lane) - cpcgfx.road_shift's sums, in 1/256 bytes:
;;
;;   P2L, P2H   2 P, P = PERSP_P half: road_x's move of two pairs (P4L,
;;              P4H: of four)
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
    ASSERT lo(RA_P2L) == #CD && #CD+NGROUPS == 256 && PERSP_P == 10
    ASSERT RA_P2H == RA_P2L+#100 && RA_P4H == RA_P4L+#100
    ASSERT RA_AH == RA_AL+#100 && RA_AO == RA_AH+#100
    ASSERT RA_WH == RA_WL+#100 && RA_FL == RA_WH+#100
    ASSERT RA_C1H == RA_C1L+#100 && (W_NONE & #FF) == 0
    ASSERT (rd_tent0 & #FF) == 0 && (rd_tent1 & #FF) == 0

;; ---------------------------------------------------------------------------
;; st5 - road_x has moved rd_s pairs (2 or 4, either way; road_x is after's):
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
    ld h,hi(RA_P2L)                     ; (self-modified: RA_P4L)
    ld c,(hl)
    inc h
    ld b,(hl)                           ; BC = 2 P (4 P)
    ld h,hi(RA_AL)
    ld a,(hl)
st5_op1
    add a,c                             ; (self-modified: SUB C, OR A)
    ld (hl),a
    jp p,st5_bias                       ; 0..127: the bias may move a
    inc h
    ld a,(hl)
st5_op2
    adc a,b                             ; (self-modified: SBC A,B, OR A)
    ld (hl),a                           ; a: A''s high byte
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
    ld a,(hl)
gb_xh
    adc a,0                             ; (self-modified) A:C = w
    rl c
    adc a,0
    jr nz,st5_nob                       ; not -128..127: none
    rr c
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

;; st5_set - A = a step, 2 or 4 either way: st5's 2 P or 4 P (st5_ph) and
;; its way (st5_op1..3) for it. Destroys AF, BC, E.
st5_set
    ld bc,#8881                         ; ADC A,B / ADD A,C: to the right
    or a
    jp p,st5_dir
    neg
    ld bc,#9891                         ; SBC A,B / SUB C: to the left
st5_dir
    ld e,hi(RA_P2L)
    cp 4
    jr c,st5_two
    ld e,hi(RA_P4L)                     ; four pairs
st5_two
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
                                        ; (pre5 and the rest: cache5b.asm)

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
