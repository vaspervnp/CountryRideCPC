;; ===========================================================================
;; cache.asm - the road off the middle of the screen: common fragments 6 and
;; 5, and the parts in banks 4 (cache4.asm) and 5 (cache5.asm).
;;
;; The car stays in the middle of the screen and the road moves under it,
;; in perspective: road_x pairs right of the middle on the bottom row, less
;; further up (cpcgfx.road_shift). The template sets in banks 4 and 5 are
;; made for the road in the middle; off it, road_project takes its templates
;; from one set more in each bank - the cache, at CACHE_LEVEL - made for the
;; curve level cache_k and road_x.
;;
;; Where each group of rows goes is worked out in bank 5 (cache5.asm) from
;; a sum it keeps for its curve level and road_x, rounded once, as
;; cpcgfx.road_shift does: a, the byte its core's left edge is at. Its
;; templates follow when that moves (TM_PUT, cachemac.asm) - band B's in
;; bank 5 there and then, band A's and band 2's in bank 4 after, from a list
;; of the groups that moved (rd_list; st4, job4).
;;
;; - road_x a pair or two (cache_step): every group's share of it moves,
;;   and the templates of those that moved with it, between two pictures,
;;   so none shows the road half moved - worked out ahead in the time left
;;   before the flips (cache_pre: pre5, pre4, into staging sets laid out
;;   as the cache's) and only copied into place then (cm5, cm4), or, with
;;   none worked out ahead, there and then (st5, st4).
;; - cache_k a level (cache_curve): every group is to be put at that level
;;   (rd_gk bit 1) - a batch at a time (cache_job: job5, job4) in whatever
;;   time is left before each flip, so a picture may show some groups a
;;   level behind cache_k (road_project draws margins for that). Off the
;;   middle any of them can move a byte, if not most; only those that do
;;   have their templates made (and are noted as moved: cache_mark).
;; ===========================================================================

    ORG FRAG6,FRAG_ST6
frag6_start

road_x      defb 0          ; the road's pairs right of the middle, signed
                            ; (cache_step)
cache_k     defb 0          ; curve level the cache is made for (cache_curve)
rd_s        defb 0          ; road_x's step (cache_step)
rd_kdir     defb 0          ; cache_k's last step: 1 or -1
rd_n2       defb 0          ; groups still to be put at cache_k
rd_next     defb 0          ; the group the next batch looks at first
job_left    defb 0          ; (job5: groups still to put at cache_k)
rd_lsp      defw 0          ; the list's first word (rd_list, st5, job5)
pre_s       defb 0          ; the step worked out ahead (cache_pre): 1 or 2
                            ; either way, 0 none
pre_g       defb 0          ; the groups it has gone through (pre5)
pre_sync    defb 0          ; the staging sets the cache's: bit 0 STAGE_B
                            ; and SGP, bit 1 STAGE_A (both: 3)

;; ---------------------------------------------------------------------------
;; cache_step - A = 1 or 2 either way: road_x that many pairs on, and the
;; cache with it - the step worked out ahead copied into place if there is
;; one (cm5, cm4: cache_ready lets no other through then), else worked out
;; there and then (st5, st4). RAM_C1 in and out. Destroys everything.
;; ---------------------------------------------------------------------------
cache_step
    ld (rd_s),a
    ld hl,road_x
    add a,(hl)
    ld (hl),a
    ld hl,st5
    ld de,st4
    ld a,(pre_g)
    or a
    jr z,cs_now                         ; (the staging sets fall behind)
    ld hl,cm5
    ld de,cm4
    ld a,3                              ; (they are the cache's after it)
cs_now
    ld (pre_sync),a
    xor a
    ld (pre_g),a
    ld (pre_s),a
                                        ; (on into cache_both)

;; cache_both - HL = work in bank 5, DE = then in bank 4 (cr_ret: none).
;; RAM_C1 in and out. NZ. Destroys everything.
cache_both
    ld a,RAM_C5
    call cache_ram
    push de
    call cb_hl
    ld a,RAM_C4
    call cache_ram
    pop hl
    call cb_hl
    ld a,RAM_C1
                                        ; (on into cache_ram)

;; cache_ram - A = a RAM configuration: noted for the flip (main_cfg) and
;; set. NZ. Destroys B, F.
cache_ram
    ld (main_cfg),a
    ld b,#7F
    out (c),a
    or a
cr_ret
    ret
cb_hl
    jp (hl)

;; ---------------------------------------------------------------------------
;; rp_force - after rp_near_skip (road15.asm): the near lines a bush on the
;; inside stood on (rp_dlo..rp_dhi) that it skipped get their road drawn
;; after all - taking the bush away put grass there: flag 3 becomes 1.
;; Line ROAD_AREA_Y + y is entry 111 - y. Keeps BC, DE.
;; ---------------------------------------------------------------------------
    ASSERT SCR_H-1-ROAD_AREA_Y == 111
rp_force
    ld a,(rp_dhi)
    cpl
    add a,112
    ld l,a                              ; L = the first entry, 111 - rp_dhi
    ld a,(rp_dlo)
    cpl
    add a,112
    ld h,a                              ; H = the last, 111 - rp_dlo ...
    ld a,(rp_near)
    dec a
    cp h
    jr nc,$+3
    ld h,a                              ; ... a near line's at most
    ld a,h
    sub l
    ret c                               ; none
    inc a
    push bc
    push de
    ld b,a
    ld h,0
    add hl,hl
    add hl,hl
    ld de,(rp_slot)
    add hl,de
    ld de,4
rp_force_line
rp_force_res
    res 1,(hl)                          ; (self-modified: RES 0 - rp_flag2)
    add hl,de
    djnz rp_force_line
    pop de
    pop bc
    ret

;; per buffer: 1 + the last group the cache has worked out afresh
;; (cache_mark) since the buffer was last drawn from it (rd_ghi) - 0: none,
;; 255: any, it was drawn from a curve level's own set - and the first
;; (rd_glo; 255: none)
rd_ghi      defb 255,255
rd_glo      defb 0,0
    ASSERT hi(rd_ghi) == hi(rd_glo+1)
rp_lo_c     defb 0                      ; (rp_mode_chg: rows from it on ...)

;; ---------------------------------------------------------------------------
;; rp_mode_chg - (rp_mode_set) D, E = the levels a group can have moved
;; right and left: none if the cache has worked no group out afresh since
;; this buffer was last drawn from it (rd_ghi) - every group shows the
;; level it did. With road_x the same, no row has moved then; else only
;; the rows of the groups it worked out: from the first one's first row
;; (rp_lo_c, for rp_flag2_road) to the next one's after the last
;; (rp_skip_r). Keeps HL, IX.
;; ---------------------------------------------------------------------------
rp_mode_chg
    push hl
    xor a
    ld (rp_lo_c),a
    ld hl,rd_ghi
    ld a,(road_buf)
    add a,l
    ld l,a
    ld c,(hl)                           ; C = 1 + the last group since
    ld (hl),255                         ; (a curve level's own set: any)
    inc l
    inc l
    ld b,(hl)                           ; B = the first
    ld (hl),0
    ld a,(rp_cache)
    or a
    jr z,rp_mode_chg_x
    ld (hl),255                         ; drawn as the cache is now
    dec l
    dec l
    ld (hl),0
    ld a,c
    or a
    jr nz,rp_mode_chg_r
rp_mode_chg_0
    ld d,a                              ; no group has moved a level
    ld e,a
    ld a,ixl
    or ixh
    jr nz,rp_mode_chg_x                 ; road_x has: every row
    ld (rp_skip_r+1),a
rp_mode_chg_x
    pop hl
    ret
rp_mode_chg_r
    cp NGROUPS+1
    jr nc,rp_mode_chg_x                 ; (any)
    ld a,ixl
    or ixh
    jr nz,rp_mode_chg_x
    ld a,c
    add a,lo(rr_gfirst)
    ld l,a
    ld h,hi(rr_gfirst)
    ld a,(hl)                           ; rows from the next group's on have
    ld (rp_skip_r+1),a                  ; not moved (cf_rows does not hold
    ld c,a                              ; off the middle)
    ld a,b                              ; ... nor those before the first's
    or a
    jr z,rp_mode_chg_x
    add a,lo(rr_gfirst)
    ld l,a
    ld a,(hl)
    cp c
    jr nc,rp_mode_chg_n                 ; none left
    ld (rp_lo_c),a
    jr rp_mode_chg_x
rp_mode_chg_n
    xor a
    jr rp_mode_chg_0


;; ---------------------------------------------------------------------------
;; cache_curve - road_curve has moved a level (A = 1 or -1): cache_k
;; follows, and every group is to be put at it (cache_all: off the middle
;; any of them can move). Destroys AF, B, HL.
;; ---------------------------------------------------------------------------
cache_curve
    ld (rd_kdir),a
    ld a,(road_curve)
    ld (cache_k),a
;; cache_all - every group to be put at cache_k (cache_init too)
cache_all
    ld hl,rd_gk
    ld b,NGROUPS
cl_loop
    set 1,(hl)
    inc l
    djnz cl_loop
    ld a,NGROUPS
    ld (rd_n2),a
    ret

    ASSERT $ <= #3640
    defs #3640-$,0

;; per group (g = 0 .. NGROUPS-1, the slot 1 + g of a template set):
rd_gk       defs NGROUPS,0          ; bit 1: to be put at cache_k
    defs #40-NGROUPS,0
rd_list     defs #80,0              ; the groups that moved, for bank 4
rd_ltop                             ; (st5, job5, pre5: tl_a)
rd_gfree    defs #80,0              ; (free)
    INCLUDE "cachegap.asm"          ; (64 bytes of code)
    defs #CD-#C0,0
rd_gp       defs NGROUPS,0          ; per group, at its lane (#CD + g): how
                                    ; far road_x moves its rows, for the
                                    ; bushes (bush.asm): a less its a with
                                    ; the road in the middle (st5, j5_s0)
    ASSERT rd_gk == #3640 && rd_list == rd_gk+#40 && cachegap_start == rd_gk+#140
    ASSERT lo(rd_gp) == #CD && 2*(NGROUPS+NFAR+2) <= rd_ltop-rd_list
frag6_end
    ASSERT frag6_end <= FRAG6+FRAG_LEN

;; ===========================================================================
;; Fragment 5, after road.asm's: the jobs.
;; ===========================================================================
    ORG frag5_end,FRAG_ST5+frag5_end-FRAG5

;; ---------------------------------------------------------------------------
;; cache_job - the cache's next piece of work: a batch of groups put at
;; cache_k (job5, job4) - none after a step (the next pictures draw the
;; road moved, with a margin: a new level's on top is too much) - or with
;; none to put, a piece of the next step worked out ahead (cache_pre: it
;; changes nothing drawn). A job running past the flip would start the next
;; picture that much later: in the last 3.3 ms before it (JOB_LATE) there
;; are none (they take up to ~3 ms). NZ if there was any. RAM_C1 in and
;; out. Destroys everything.
;; ---------------------------------------------------------------------------
JOB_LATE    EQU 11                      ; from this interrupt since the flip on,
                                        ; no job

cache_job
    ld a,(irq_n)
    cp JOB_LATE
    jr c,cj_go
cj_none
    xor a                               ; too close to the flip
    ret
cj_go
    ld a,(rd_n2)
    or a
    jp z,cache_pre
    ld a,(pre_g)
    or a
    jr nz,cache_drop                    ; (a job moves the sums as they are)
    ld a,(rd_s)
    or a
    jr nz,cj_none
    ld (pre_sync),a                     ; (the staging sets fall behind)
    ld hl,job5
    ld de,job4
    jp cache_both

;; ---------------------------------------------------------------------------
;; cache_drop - the step worked out ahead dropped: the sums it has moved
;; put back (undo5), the staging sets no longer the cache's. NZ. RAM_C1 in
;; and out. Destroys everything.
;; ---------------------------------------------------------------------------
cache_drop
    ld a,(pre_g)
    or a
    jr z,cd_s
    ld hl,undo5
    ld de,cr_ret
    call cache_both
    xor a
    ld (pre_g),a
    ld (pre_sync),a
cd_s
    ld (pre_s),a
    or 1
    ret

;; ---------------------------------------------------------------------------
;; cache_init - the cache sets made whole, for road_curve and the road in
;; the middle. RAM_C1 in and out. Destroys everything.
;; ---------------------------------------------------------------------------
cache_init
    xor a
    ld (pre_g),a
    ld (pre_s),a
    ld (pre_sync),a
    ld (rd_s),a
    ld hl,cache_reset
    ld de,job4_ground
    call cache_both
    ld a,(road_curve)
    ld (cache_k),a
    call cache_all
cache_init_job
    xor a                               ; (no flip to wait for)
    ld (irq_n),a
    call cache_job
    jr nz,cache_init_job
    ret

;; per curve level k = -7..6: the first row a move between k and k + 1
;; leaves where it was
cf_rows     defb CF_ROW6,CF_ROW5,CF_ROW4,CF_ROW3,CF_ROW2,CF_ROW1,CF_ROW0
            defb CF_ROW0,CF_ROW1,CF_ROW2,CF_ROW3,CF_ROW4,CF_ROW5,CF_ROW6
    ASSERT CURVE_K == 7 && hi(cf_rows) == hi(cf_rows+13)

;; rp_part_k - (rp_mode_set) HL = the least curve level a group was at when
;; this buffer was last drawn (the greatest two bytes on), B, C now's: in
;; rp_skip_r the first row no move between those levels moved - 0 if the
;; curve did not move, 255 (none) if the road moved sideways (IXL, IXH).
;; Keeps BC, HL, IX.

rp_part_k
    ld a,ixl
    or ixh
    ld a,255
    jr nz,rp_part_k1                    ; the road moved sideways
    ld a,b
    add a,CURVE_K
    ld e,a
    ld a,(hl)
    add a,CURVE_K
    cp e
    jr nc,$+3
    ld e,a                              ; E = the least level then or now
    ld a,c
    add a,CURVE_K
    ld d,a
    inc hl
    inc hl
    ld a,(hl)
    dec hl
    dec hl
    add a,CURVE_K
    cp d
    jr c,$+3
    ld d,a                              ; D = the greatest (both + CURVE_K)
    ld a,d
    sub e
    jr z,rp_part_k1                     ; the curve did not move: 0
    push hl
    ld d,a
    ld a,e
    add a,lo(cf_rows)
    ld l,a
    ld h,hi(cf_rows)
    dec d
    ld a,(hl)                           ; the first row left by k <-> k + 1
    jr z,rp_part_k2
    inc l
    cp (hl)                             ; ... and by k + 1 <-> k + 2
    jr nc,rp_part_k2
    ld a,(hl)
rp_part_k2
    pop hl
rp_part_k1
    ld (rp_skip_r+1),a
    ret

cache5_end
    ASSERT cache5_end <= FRAG5+FRAG_LEN

;; ===========================================================================
;; Page 1, beside the HUDs: the eighth chunk tools/mkbush.py leaves for this
;; (seen with RAM_C1 only) - the cache's work that runs in RAM_C1.
;; ===========================================================================
    ORG #7E00
cache1_start

;; ---------------------------------------------------------------------------
;; cache_ready - (cache_steps) C = the pairs road_x is to move, either way:
;; Z if there is no step worked out ahead (cache_pre) - cache_steps' own
;; gate then, for st5. Else NZ and in B the interrupt since the flip from
;; which on the step may not go: it goes whenever cache_steps runs, being
;; a copy (~5 ms) - as C then - if it is done, goes as far as C at most
;; and its way, and is a pair while a new curve level has the road drawn
;; with a margin; else not at all (B = 0) till it is done or dropped.
;; Destroys AF, E.
;; ---------------------------------------------------------------------------
cache_ready
    ld a,(pre_g)
    or a
    ret z
    ld b,0
    cp NGROUPS
    ret nz                              ; not done
    ld a,(pre_s)
    ld e,a
    ld a,c
    sub e
    jr z,cr_wait
    xor e
    jp m,cr_no                          ; further than C, or the other way
cr_wait
    ld a,(curve_wait)
    or a
    jr z,cr_go
    ld a,e
    inc a
    cp 3
    jr nc,cr_no                         ; two pairs, with the margin
cr_go
    ld c,e
    ld b,#7F                            ; (past any)
cr_no
    or 1
    ret

;; ---------------------------------------------------------------------------
;; cache_pre - (cache_job, with no groups to put at cache_k) the step
;; road_x is to take next, towards steer_x, worked out ahead a piece at a
;; time (each up to ~3 ms, as a batch of jobs): the staging sets made the
;; cache's first if they are not (rs5, then rs4), then PRE_BATCH groups a
;; piece (pre5, pre4). One that goes further, or the other way, is dropped
;; (cache_drop). NZ if there was any work. RAM_C1 in and out. Destroys
;; everything.
;; ---------------------------------------------------------------------------
cache_pre
    ld a,(road_x)
    ld b,a
    ld a,(steer_x)
    sub b
    ret z                               ; none to take
    ld b,2
    call clamp_ab
    ld hl,pre_s
    ld e,(hl)
    inc e
    dec e
    jr nz,cp_was
    ld (hl),a                           ; a new one
    jr cp_work
cp_was
    sub e
    jr z,cp_work
    xor e
    jp m,cache_drop
cp_work
    ld hl,pre_sync
    ld a,(hl)
    cp 3
    jr z,cp_piece
    scf
    rla
    ld (hl),a                           ; 0: 1 - 1: 3
    ld hl,rs5
    ld de,cr_ret
    dec a
    jr z,cp_both
    ld hl,cr_ret
    ld de,rs4
    jr cp_both
cp_piece
    ld a,(pre_g)
    cp NGROUPS
    ret z                               ; done
    ld hl,pre5
    ld de,pre4
cp_both
    jp cache_both

cache1_end
    ASSERT cache1_end <= #8000
