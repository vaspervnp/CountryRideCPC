;; ===========================================================================
;; road6.asm - the part of road_project in bank 6, with the row tables
;; (RAM_C6 while road_project runs; fragment 5 is full): rp_mode's work.
;; ===========================================================================

rp_mode_set
    call rp_flag2_marg                  ; (cache.asm)
    ld hl,rp_near_skip
    ld (rp_skip_go+1),hl
    xor a
    ld (rp_cmp),a
    ld (rp_far_fl+1),a
    ld (rp_mode_far+1),a
    ld (rp_far_hfl+1),a
    ld (rp_skip),a
    ld a,e                              ; E odd: nothing known
    and 1
    ld (rp_mode_unk+1),a
    ld a,(road_x)                       ; D, E = the least and greatest
    ld d,a                              ; road_x now (all of the road is
    ld e,a                              ; there)
    ld a,(rp_cache)
    or a
    jr z,rp_mode_xk
    ld a,(rd_n2)                        ; B, C: the least and greatest curve
                                        ; level a group can be at
    or a
    jr z,rp_mode_xk
    ld a,(rd_kdir)
rp_mode_xk                              ; (A: 0 if none behind)
    ld h,a
    ld a,(road_curve)
    ld b,a
    ld c,a
    ld a,h
    or a
    jr z,rp_mode_k
    jp m,rp_mode_kl
    dec b
    jr rp_mode_k
rp_mode_kl
    inc c
rp_mode_k
    ld hl,(rp_vars)                     ; this buffer's then, now's kept
    ld a,rp_xmin-rp_level
    add a,l
    ld l,a
    jr nc,$+3
    inc h
    ld a,e                              ; how far right a group can have
    sub (hl)                            ; moved: grass on the left (IXL)
    call rp_mode_pos
    ld ixl,a
    ld (hl),d
    inc hl
    inc hl
    ld a,(hl)                           ; ... left: on the right (IXH)
    sub d
    call rp_mode_pos
    ld ixh,a
    ld (hl),e
    inc hl
    inc hl
    call rp_part_k                      ; (the rows the curve did not move)
    ld a,c                              ; and its curve level: 5 pairs a
    sub (hl)                            ; level (tools/mkroad.py)
    call rp_mode_lvl
    push af
    ld (hl),b
    inc hl
    inc hl
    ld a,(hl)
    sub b
    call rp_mode_lvl
    ld e,a
    ld (hl),c
    inc hl
    inc hl
    pop af
    ld d,a                              ; D, E = right, left
    call rp_mode_chg                    ; (none if the cache is as then)
    ld a,(rd_kdir)                      ; the cache's levels came the same way
    cp (hl)                             ; then and now: a group has moved
    ld (hl),a                           ; that way only (a level at most
    jr nz,rp_mode_kb                    ; between two of a buffer's pictures)
    or a
    jp m,rp_mode_kn
    ld e,0
    jr rp_mode_kb
rp_mode_kn
    ld d,0
rp_mode_kb
    ld a,d
    add a,ixl
    ld b,a
    ld a,e
    add a,ixh
    ld c,a
    ld a,b
    or c
rp_mode_unk
    or 0                                ; (self-modified: 1 if nothing known)
rp_mode_far
    or 0                                ; (self-modified: more than 2 levels)
    ld (rp_moved),a                     ; 0: nothing moved sideways
    ld a,(rp_mode_unk+1)
    ld h,a
    ld a,(rp_mode_far+1)
    or h
    jr nz,rp_mode_whole
    ld a,(rp_old_level)
    ld hl,(rp_vars)
    sub (hl)
    jr nz,rp_mode_hill
    call rp_mode_max
    jr nc,rp_mode_whole
    call rd_margin
    ld a,b                              ; nothing moved at all: lines in the
    or c                                ; stripe of then are skipped (but
    jr z,rp_mode_all                    ; those a bush stood on: rp_force) -
    ld hl,rp_near_go                    ; only the curve moved: the lines of
    ld (rp_skip_jp+1),hl                ; what it did not move (road15.asm)
    ld a,(rp_skip_r+1)                  ; (255: none)
    inc a
    ld (rp_skip),a
    call rp_flag2_road                  ; (those it skips: no margin)
    jr rp_mode_noskip
rp_mode_all
    ld (rp_skip_r+1),a                  ; (0: every near line)
    inc a
    ld (rp_skip),a
    ld hl,rp_near_same                  ; (road15.asm)
    ld (rp_skip_go+1),hl
rp_mode_noskip
    ld a,1
    ld (rp_far_fl+1),a                  ; the same hill: every line
    ret
rp_mode_hill                            ; the hill moved: a near line that
    jp p,rp_mode_dh                     ; shows another row than then shows
    neg                                 ; one next to it, if the hill moved
rp_mode_dh                              ; a little (rp_mode_rows)
    cp RP_HILL_STEP+1
    jr nc,rp_mode_whole
    ld a,b
    or c
    ld d,a                              ; D = 0: nothing else moved: a
    call z,rp_far_m                     ; margin for it, far lines too
    call rp_mode_max
    jr nc,rp_mode_whole
    push de
    call rd_margin
    pop de
    ld a,d
    or a
    jr nz,rp_mode_hx
    call rd_road                        ; the same row: only the road (it
    xor a                               ; takes DE: A = 0, nothing else moved)
rp_mode_hx
    jp rp_mode_rows
rp_mode_whole
    xor a
    ret

