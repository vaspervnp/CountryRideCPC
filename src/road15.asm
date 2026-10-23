;; ===========================================================================
;; road15.asm - more of road_project, in the rest of common fragment 15
;; after the bushes' data: the near lines when the road has not moved, and
;; how lines are compared when the hill has (fragments 5 and 7 are full).
;; ===========================================================================

    ORG bushdata_end,FRAG_ST15+bushdata_end-FRAG15

;; ---------------------------------------------------------------------------
;; rp_near_skip - the near lines when nothing moved since this buffer was
;; last drawn - the same hill, curve level and place, no bush taken off the
;; road (rp_mode: rp_skip). Each line shows the row it showed then; if it is
;; in the stripe it was in then too, its template is the one in the list
;; and the line is already right: flagged 3, road_draw goes straight on to
;; the next (the stripes are long: most lines). Else flagged 1, only the
;; road. A = rp_near, BC = line -> row table, DE = template slot.
;;
;; When only the curve level moved, the nearest rows have not (rp_part_k):
;; their lines are taken as above, the rest by road_project's own loop.
;; ---------------------------------------------------------------------------
rp_near_skip
    exx
    ld b,a
    exx
rp_skip_line
    ld a,(bc)                           ; the row this line shows
rp_skip_r
    cp 0                                ; (self-modified: 0, or the first
    jr c,rp_skip_rest                   ; row the curve did not move)
    inc bc
    ld l,a
    ld h,hi(rr_depth)
    ld a,(hl)                           ; depth, low byte
rp_zlo10
    add a,0                             ; + zcam (self-modified)
    inc h
    and (hl)
    rrca                                ; band B is #2000 higher
    inc h
    add a,(hl)                          ; template, high byte
rp_lvl11
    add a,0                             ; + the curve level (self-modified)
    inc e
    ex de,hl
    cp (hl)                             ; the template of then?
    jr nz,rp_skip_diff
    dec hl
    ex de,hl
    ld h,hi(rr_tlo)
rp_skip_same
    ld a,(hl)                           ; template, low byte
rp_skip_s3
    or 3                                ; the same: 3, skipped (self-
                                        ; modified: 1 in rp_seg_in's window)
rp_skip_put
    ld (de),a
    inc e                               ; (an entry never crosses a page)
    inc de                              ; next entry's template slot
    inc e
    inc e
    exx
    dec b
    exx
    jr nz,rp_skip_line
rp_skip_end
    ld a,(rp_dirty)
    or a
    call nz,rp_force
    jp rp_far
rp_skip_diff                            ; the stripe of then? (the level's
    ld ixh,a                            ; set may be another: the row is
    xor (hl)                            ; where it was; bit 14: not an
    and #60                             ; interrupt's return address there)
    ld a,ixh
    ld (hl),a
    dec hl
    ex de,hl
    ld h,hi(rr_tlo)
    jr z,rp_skip_same
rp_skip_chg                             ; another stripe: only the road - but
    ld a,ixh                            ; band A's now, on a striped row, the
    and #20                             ; grass's stripe has moved on too: all
    jr nz,rp_skip_road                  ; of it
    ld a,l
    cp GRASS_ROW
    ld a,(hl)
    jr nc,rp_skip_put
    db #FE                              ; (CP n: over the next)
rp_skip_road
    ld a,(hl)
rp_skip_rf
    or 1                                ; (self-modified: 2 when flag 1 is
    jr rp_skip_put                      ; a margin - rp_mode_set)
rp_skip_rest                            ; a row that moved: the rest
    jp rp_skip_rest0                    ; (self-modified: rp_seg_in, out)
rp_skip_rest0
    ld a,(rp_dirty)                     ; road_project's way (rp_near_go,
    or a                                ; rp_cmp_go)
    call nz,rp_force
    exx
    ld a,b
    exx
rp_skip_jp
    jp 0                                ; (self-modified)

;; ---------------------------------------------------------------------------
;; rp_near_same - the near lines when nothing at all moved since this
;; buffer was last drawn (rp_mode_all): each shows the row it showed then,
;; from the same template set. A line whose template is the one in the list
;; - its band the same - is already right: flagged 3. Else as RP_LINE does:
;; 1, only the road, or 0 if the grass's stripe has moved on it. Faster
;; than rp_near_skip, which can take another set's template for the same.
;; A = rp_near, BC = line -> row table, DE = template slot.
;; ---------------------------------------------------------------------------
rp_near_same
    ld ixh,a
rp_same_line
    ld a,(bc)                           ; the row this line shows
    inc bc
    ld l,a
    ld h,hi(rr_depth)
    ld a,(hl)                           ; depth, low byte
rp_zlo11
    add a,0                             ; + zcam (self-modified)
    ld ixl,a
    inc h
    and (hl)
    rrca
    inc h
    add a,(hl)                          ; template, high byte
rp_lvl12
    add a,0                             ; + the curve level (self-modified)
    inc e
    ex de,hl
    cp (hl)                             ; the band of then?
    ld (hl),a
    dec hl                              ; (not DEC E: the flags)
    ex de,hl
    ld h,hi(rr_tlo)
    ld a,3
    jr z,rp_same_put                    ; the same: skipped
    ld a,ixl
    add a,a
rp_dz8
    cp 0                                ; (self-modified, as rp_dz)
    sbc a,a
    inc a
rp_same_put
    or (hl)                             ; template, low byte
    ld (de),a
    inc e
    inc de
    inc e
    inc e
    dec ixh
    jr nz,rp_same_line
    jr rp_skip_end

;; rp_rows_r - (rp_mode_rows) the hill moved too: rows nearer than both
;; hills' |h| show on the lines they did (h/r is 0), so rp_near_cmp takes
;; the lines from the bottom up to those rows' and rp_skip_r's as
;; rp_near_skip does, if there are any (rp_skip).
rp_rows_r
    ld hl,(rp_vars)
    ld a,(hl)                           ; the level now
    call rp_habs
    ld b,a
    ld a,(rp_old_level)
    call rp_habs
    cp b
    jr nc,$+3
    ld a,b
    inc a
    ld b,a                              ; B = max(|h|) + 1
    ld a,(rp_skip_r+1)
    cp b
    jr nc,$+3
    ld a,b
    ld (rp_skip_r+1),a
    cp ROWS+1
    ld a,0
    adc a,a                             ; 1 if a row is left
    ld (rp_skip),a
    ret
rp_habs                                 ; A = |h| for level A: |2A - 128|
    sub 64
    jp p,$+5
    neg
    add a,a
    ret

;; rp_mode_rows - the hill moved: the near lines' rows are compared with
;; the ones they showed then (rp_cmp). A = 0 if nothing else moved: a line
;; that shows another row gets a margin - only its road if it is a nearer
;; row and the road straight and in the middle. Else the others get the
;; margin the road's move sideways needs, and such a line that and a row's
;; (rp_side_hill) - or is drawn whole, if that is too much. Returns A = 0
;; (rp_mode).
rp_mode_rows
    or a
    jr z,rp_rows_h
    call rp_side_hill                   ; (cache.asm)
    ld hl,(#20*256)+0                   ; JR NZ and no second INC A:
    ld c,0                              ; another row, flag 0; far: off
    jr nc,rp_rows_op
    or 1                                ; (NZ: no nearer rows' way)
rp_rows_h
    ld c,#3C                            ; (INC A)
    ld hl,(#28*256)+0                   ; JR Z: another row, flag 2
    jr nz,rp_rows_op
    ld a,(road_curve)
    ld b,a
    ld a,(road_x)
    or b
    jr nz,rp_rows_op
    ld hl,(#30*256)+rp_far_hill_dash2-rp_far_near-2   ; JR NC: or a nearer
rp_rows_op                                            ; one, flag 1
    ld a,1
    ld (rp_cmp),a
    ld a,h
    ld (rp_flx),a
    ld a,l
    ld (rp_far_near+1),a
    ld a,c
    ld (rp_flx2),a
    call rp_rows_r
    xor a
    ret


road15_end
    ASSERT road15_end <= FRAG15+FRAG_LEN
