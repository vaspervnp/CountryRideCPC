;; ===========================================================================
;; cache.asm - the road's templates, wherever it is: common fragments 6 and
;; 5, and the parts in banks 4 (cache4.asm) and 5 (cache5.asm).
;;
;; The car stays in the middle of the screen and the road moves under it,
;; in perspective: road_x pairs right of the middle on the bottom row, less
;; further up (cpcgfx.road_shift). road_project takes its templates from a
;; set in each bank - the cache, at CACHE_LEVEL - made for the curve level
;; cache_k and road_x. (Till 2026-11-05 each curve level had its own sets
;; too, made for the road in the middle and drawn there: 15K.)
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
;; - cache_k a level (cache_kstep): every group moves to it between two
;;   pictures, as for a step - worked out ahead into the staging sets
;;   (cache_pre: prk5, pre4; the level the track has next, cache_want) and
;;   copied into place (cmk5, cm4); road_curve waits for that. A picture
;;   never shows the road at two levels.
;; - the cache made whole (cache_init): every group put at cache_k (rd_gk
;;   bit 1) a batch at a time (cache_job: job5, job4). Only those whose
;;   byte moves have their templates made (and are noted as moved:
;;   cache_mark).
;; ===========================================================================

    ORG FRAG6,FRAG_ST6
frag6_start

road_x      defb 0          ; the road's pairs right of the middle, signed
                            ; and even (cache_step: 2 or 4 pairs a step)
cache_k     defb 0          ; curve level the cache is made for
rd_s        defb 0          ; road_x's step (cache_step)
rd_kdir     defb 0          ; cache_k's last step: 1 or -1
rd_n2       defb 0          ; groups still to be put at cache_k
rd_next     defb 0          ; the group the next batch looks at first
job_left    defb 0          ; (job5: groups still to put at cache_k)
rd_lsp      defw 0          ; the list's first word (rd_list, st5, job5)
pre_s       defb 0          ; the step worked out ahead (cache_pre): 2 or 4
                            ; either way, 0 none
pre_g       defb 0          ; the groups it has gone through (pre5)
pre_sync    defb 0          ; the staging sets the cache's: bit 0 STAGE_B
                            ; and SGP, bit 1 STAGE_A (both: 3)
pre_g0      defb 0          ; the first group whose a it moves (255: none)

;; ---------------------------------------------------------------------------
;; cache_step - A = 2 or 4 either way: road_x that many pairs on, and the
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
;; rp_force - (rp_force_all, after rp_near_skip - road15.asm - or
;; rp_line_cmp) the near lines IX says, first and last - a bush on the
;; inside stood on them (rp_dlo..rp_dhi), or a car - that were skipped get
;; their road drawn after all - taking the bush away put grass there, the
;; car is on the road: flag 3 becomes 1 (or 2: rp_flag2_road); the others
;; stay as they are. Line ROAD_AREA_Y + y is entry LAST_Y - y. Keeps BC,
;; DE.
;; ---------------------------------------------------------------------------
rp_force
    ld a,(ix+1)
    cpl
    add a,LAST_Y+1
    ld l,a                              ; L = the first entry, LAST_Y - last
    ld a,(ix+0)
    cpl
    add a,LAST_Y+1
    ld h,a                              ; H = the last, LAST_Y - rp_dlo ...
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
    bit 0,(hl)
    jr z,$+4                            ; (flags 0 and 2)
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
;; (rp_skip_r). With road_x moved, every near row - but no far one if
;; neither a step (cache_mark) nor the cache moved a far group (rp_lo_c).
;; Keeps HL, IX.
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
    ld (hl),0                           ; (drawn as the cache is now)
    inc l
    inc l
    ld b,(hl)                           ; B = the first
    ld (hl),255
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
    ld a,c
    jr z,$+4
    ld a,NGROUPS+1                      ; road_x moved: every near row (255)
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


pre_k       defb 0          ; the work ahead is a curve level: cache_k + 1
                            ; or - 1 (pre_s 0); 0 a step
pre_g1      defb 0          ; (a level's: the last group whose a it moves)

    ASSERT $ <= #3640
    defs #3640-$,0

;; per group (g = 0 .. NGROUPS-1, the slot 1 + g of a template set):
rd_gk       defs NGROUPS,0          ; bit 1: to be put at cache_k
    defs #40-NGROUPS,0
rd_list     defs #80,0              ; the groups that moved, for bank 4
rd_ltop                             ; (st5, job5, pre5: tl_a)
;; In the room after the list (common): parts of the cache's work in
;; RAM_C1 (cache_want) and in RAM_C5 (prk5, undok5: cache5.asm's) that
;; their own places have no room for.
rd_gfree
;; cache_want - (cache_pre) A = the curve level the cache is to work out
;; ahead, cache_k + 1 or - 1: towards the game's (curve), or
;; with that reached, the track's as far on as the camera goes in 8 VSYNCs
;; (about the time it takes); 0 none. Destroys F, DE, HL.
cache_want
    ld a,(curve)
    ld hl,road_curve
    sub (hl)
    jr nz,cw_way
    ld hl,(speed)
    add hl,hl
    add hl,hl
    add hl,hl
    ld e,h                              ; E = depth units in 8 VSYNCs
    ld d,a
    ld hl,(zcam)
    add hl,de
    add hl,hl
    add hl,hl
    add hl,hl
    ld a,h                              ; the track entry there
    and RING_MASK
    ld l,a
    ld h,hi(CURVE_RING)
    ld a,(hl)
    ld hl,road_curve
    sub (hl)
    ret z
cw_way
    ld a,1
    ret p
    ld a,-1
    ret

;; prk5 - (cache5.asm, with pre5)
prk5
    ld a,(cache_k)
    ld hl,pre_k
    add a,(hl)
    add a,CURVE_K
    ld (pk5_grp+1),a
    call st5_none
    ld a,hi(SGP)
    ld (j5_gp+1),a
    ld a,PRK_BATCH
    ld bc,pk5_grp
    ld de,pk5_back
    ld hl,0                             ; (road_x stays)
    jp p5_set

;; undok5 - (cache_drop) the groups prk5 has moved put back at cache_k
;; (j5_level), the last first, pre_g counted down - till the flip is near
;; (JOB_LATE: the rest next time); with none left, their a's as SB has
;; them. Destroys everything.
undok5
    ld a,(pre_g)
    add a,#CD-1
    ld l,a                              ; the last one's lane
uk5_loop
    call j5_level
    ld a,l
    sub #CD
    ld (pre_g),a
    jp z,u5_ao                          ; all put back
    dec l
    ld a,(irq_n)
    cp JOB_LATE
    jr c,uk5_loop
    ret

;; cache_all - every group to be put at cache_k (cache_init)
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

rd_gfree_end
    ASSERT rd_gfree_end <= rd_ltop+#80
    defs rd_ltop+#80-$,0
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
;; cache_k (job5, job4; cache_init) - none after a step (the
;; next pictures draw the road moved, with a margin: a new level's on top
;; is too much) - or with none to put, a piece of the next step or curve
;; level worked out ahead (cache_pre: it changes nothing drawn). A job
;; running past the flip would start the next picture that much later: in
;; the last 3.3 ms before it (JOB_LATE) there are none (they take up to ~3
;; ms; a piece worked out ahead stops there). NZ if there was any. RAM_C1
;; in and out. Destroys everything.
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
    call lane_can                       ; the lanes first (lanes5.asm)
    ret nz
    ld a,(rd_n2)
    or a
    jp z,lane_pre
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

;; lane_can - the groups that can have the new lanes now given them
;; (lanes5.asm: lane_g5c, lane_g4) - not while a step or a curve level is
;; worked out ahead (lane_due): NZ if there were any. And the car's way
;; onto the grass the lanes' (road15.asm lane_road). RAM_C1 in and out.
;; Destroys everything.
lane_can
    call lane_road
    ld a,(lane_h)
    or a
    ret z
    call lane_due                       ; (common.asm)
    jr nz,lc_not
    ld hl,(zcam)
    ld de,(lane_at)
    sbc hl,de                           ; (CF 0: OR A)
    jp m,lc_not                         ; not yet
    ld hl,lane_g5c
    ld de,lane_g4
    jp cache_both
lc_not
    xor a
    ret

;; lane_pre - cache_pre, but with the lanes changing (lanes5.asm): no step
;; worked out ahead - one is dropped (lane_due: they wait for none) - only
;; a curve level the road has still to take, to the game's (no hill holds
;; it back there: tools/course.py check_lanes).
lane_pre
    ld a,(lane_h)
    or a
    jp z,cache_pre
    ld a,(road_curve)
    ld hl,curve
    cp (hl)
    jr z,lp_none                        ; at the curve's level
    ld a,(pre_g)
    or a
    jp z,cache_pre                      ; (a new one: a level, or a step
    ld a,(pre_k)                        ; dropped next time)
    or a
    jp nz,cache_pre                     ; a level: on with it
lp_none
    ld a,(pre_g)
    or a
    jp nz,cache_drop
    ret                                 ; (Z: no work)

;; ---------------------------------------------------------------------------
;; cache_drop - the step or curve level worked out ahead dropped: the sums
;; it has moved put back (undo5; a level's a piece at a time, undok5, till
;; the flip is near), the staging sets no longer the cache's. NZ. RAM_C1
;; in and out. Destroys everything.
;;
;; A level part put back can go on (cache_pre: wanted again): the groups
;; before pre_g are as prk5 left them, those it put back keep their a and
;; staged templates (undok5 puts the a's back last), which prk5 then finds
;; in place. The staging sets stay as they are for that till all are put
;; back - made the cache's again (rs5, rs4), they would keep the old
;; level's templates for groups whose a is the new one's.
;; ---------------------------------------------------------------------------
cache_drop
    ld a,(pre_g)
    or a
    jr z,cd_s
    ld hl,undo5
    ld a,(pre_k)
    or a
    jr z,$+5
    ld hl,undok5
    ld de,cr_ret
    call cache_both
    ld a,(pre_k)
    or a
    jr z,cd_g
    ld a,(pre_g)                        ; a level's: put back a piece at a
    or a                                ; time (undok5 counts pre_g down)
    ret nz
cd_g
    xor a
    ld (pre_sync),a
    ld (pre_g),a
cd_s
    ld (pre_s),a
    ld (pre_k),a
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
    ld (pre_k),a
    ld (pre_sync),a
    ld (rd_s),a
    ld hl,cache_reset
    ld de,cr_ret
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

cache5_end
    ASSERT cache5_end <= FRAG5+FRAG_LEN

;; ===========================================================================
;; Page 1, beside the HUDs: the first half of the eighth chunk, which
;; tools/mkbush.py leaves for this (seen with RAM_C1 only) - the cache's
;; work that runs in RAM_C1.
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
;; with a margin; else not at all (B = 0) till it is done or dropped - nor
;; while a curve level is worked out ahead instead (pre_k: it goes first).
;; Destroys AF, E.
;; ---------------------------------------------------------------------------
cache_ready
    ld a,(pre_g)
    or a
    ret z
    ld b,0
    ld e,a
    ld a,(pre_k)
    or a
    ret nz                              ; a curve level
    ld a,e
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
;; cache_pre - (cache_job, with no groups to put at cache_k) the curve level
;; the road is to take next (cache_want), or else the step
;; road_x is to take next towards steer_x (cp_pend: up to four pairs),
;; worked out ahead a piece at a time (each up to ~3 ms, as a batch of
;; jobs): the staging sets made the cache's first if they are not (rs5,
;; then rs4), then PRE_BATCH groups a piece (pre5, pre4) - PRK_BATCH for a
;; level (prk5, pre4). Any other worked out ahead is dropped first
;; (cache_drop). NZ if there was any work. RAM_C1 in and out. Destroys
;; everything.
;; ---------------------------------------------------------------------------
cache_pre
    call cache_want
    or a
    jr z,cp_step
    call cp_turn                        ; (player.asm) a step's turn: first
    jr c,cp_step                        ; (the hill holds the level back)
    jr nz,cp_take
    ld hl,pre_k
    cp (hl)
    jr z,cp_work                        ; that level, under way
    ld e,a
    ld a,(pre_g)
    or a
    jp nz,cache_drop                    ; another under way: dropped first
    ld (hl),e                           ; a new one
    ld (pre_s),a
    jr cp_work
cp_step
    ld a,(pre_k)
    or a
    jp nz,cache_drop                    ; a level no longer wanted
    call cp_pend
    ret z                               ; none to take
cp_take
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
    ld a,(pre_k)
    or a
    jr z,$+5
    ld hl,prk5
    ld de,pre4
cp_both
    jp cache_both

;; ---------------------------------------------------------------------------
;; cache_kstep - (cache_steps) C = the game's curve
;; level less road_curve, HL = road_curve: it moves a level that way if
;; the cache has that level worked out ahead (cache_pre: prk5, pre4) -
;; copied into place, ~5 ms (cmk5, cm4) - and else waits; no step either
;; then (cache_ready), but with no level worked out ahead. Both buffers'
;; next pictures draw all of the road moved, ~10 ms more than the last
;; one: that has to have been done by interrupt KSTEP_LATE - 1 since the
;; flip, one later for each further level the road is behind.
;; ---------------------------------------------------------------------------
KSTEP_LATE  EQU 8

cache_kstep
    ld a,(pre_k)
    or a
    jp z,cache_steps_x                  ; none (yet): a step may go
    xor c
    ret m                               ; the other way (cache_pre drops it)
    ld a,(pre_g)
    cp NGROUPS
    ret nz                              ; not done
    ld a,c
    or a
    jp p,$+5
    neg
    add a,KSTEP_LATE-1
    ld b,a
    ld a,(irq_n)
    cp b
    ret nc                              ; the last picture too heavy: later
    ld a,(pre_k)
    ld (rd_kdir),a
    add a,(hl)
    ld (hl),a
    ld (cache_k),a
    ld a,2
    ld (curve_wait),a
    ld (step_turn),a                    ; (a step goes first next: cp_turn)
    ld a,3
    ld (pre_sync),a                     ; (the staging sets the cache's after)
    xor a
    ld (pre_g),a
    ld (pre_k),a
    ld hl,cmk5
    ld de,cm4
    call cache_both
    jp sky_stay                         ; (the next picture has the road bent)

;; demo_lanes - (game.asm steer_demo) A = where the demo steers to with
;; four lanes: as far with lane_now's - three quarters, a half - even.
;; Destroys F, B, HL.
demo_lanes
    ld hl,lane_now
    bit 2,(hl)
    ret nz                              ; four
    sra a
    ld b,a
    bit 0,(hl)
    jr z,dl_even                        ; two
    sra a
    add a,b
dl_even
    and #FE
    ret

cache1_end
    ASSERT cache1_end <= #7F00
