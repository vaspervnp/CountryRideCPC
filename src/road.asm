;; ===========================================================================
;; road.asm - road_project, in common fragment 7, and road_init and
;; rp_near_cmp, in fragment 5. They run with RAM_C6: bank 6 holds the row
;; arrays and the hill tables (src/gen/roadrows.asm).
;;
;; road_project writes, for every road line, the template of the row of road
;; that line shows into the line list; road_draw (common.asm) then draws it.
;;
;; The road is made of rows 1..NEAR_ROW (its shape laid out over ROWS, as
;; if it went on to the screen's last line). On a flat road row r is on line
;; HORIZON_Y+r, so row NEAR_ROW is on the road's last line, ROAD_END - 1,
;; and row 1 the furthest. A row
;; knows its depth and its width, and so its template: the stripe band is
;; bit 6 of (depth + zcam).
;;
;; Curves: the templates are the cache set's (cache.asm), made for the curve
;; level and road_x - every row already moved sideways as far as they move
;; it - so a curve costs road_project nothing either.
;;
;; Hills: a crest ahead of strength h moves row r down by h/r lines - the
;; same h/r a parabolic crest gives in perspective - so the near road hardly
;; moves, the far road drops away, and from the row where h/r grows faster
;; than r shrinks the road is hidden behind the crest. A negative h lifts the
;; far road instead; it is cut off at ROAD_Y, the top of the road area.
;; Lines no row reaches show the ground. Which row each line shows is worked
;; out by tools/mkroad.py for every even h and kept in bank 6: one byte per
;; line, so a hill costs road_project nothing that a flat road does not.
;; ===========================================================================

    ORG FRAG7,FRAG_ST7

;; ---------------------------------------------------------------------------
;; road_project - write the templates into (road_buf)'s line list, from
;; (zcam) and (hill).
;;
;; Lines that cannot have changed since this buffer was last drawn are left
;; off the end of the list - it runs from the bottom line up, and what does
;; not change is at the top: the ground behind a crest. The end marker goes
;; in after the last line that is drawn.
;; Destroys everything.
;; ---------------------------------------------------------------------------
road_project
    ld de,list0+2
    ld hl,rp_level
    ld a,(road_buf)
    or a
    jr z,rp_buf
    ld de,list1+2
    inc hl
rp_buf
    ld (rp_slot),de
    push hl
    ld hl,ROAD_LINES*4                  ; the permanent end marker: an interrupt
    add hl,de                           ; taken while road_draw read it left
    ld (hl),lo(tmpl_end)                ; its return address there
    inc hl
    ld (hl),hi(tmpl_end)
    pop hl

    ; hill level: hill = 2*level - 128
    ld a,(hill)
    add a,128
    srl a
    ld c,a                              ; C = level now
    ld b,0
    ld a,(hl)                           ; level this buffer was drawn with
    ld (hl),c
    ld (rp_vars),hl
    ld (rp_old_level),a
    cp #FF
    jr z,rp_skip_none                   ; nothing known
    ld hl,level_ground                  ; unchanged ground = min(old, new)
    ld e,a
    ld d,b
    add hl,de
    ld a,(hl)
    ld hl,level_ground
    add hl,bc
    cp (hl)
    jr c,rp_skip_a
    ld a,(hl)
    jr rp_skip_a
rp_skip_none
    xor a
rp_skip_a
    neg
    add a,ROAD_LINES                    ; lines to draw
    ld (rp_count),a
    ld hl,level_near                    ; of them, the striped rows' lines
    add hl,bc
    cp (hl)
    jr c,rp_near_ok
    ld a,(hl)
rp_near_ok
    ld (rp_near),a

    ld hl,level_addr                    ; this level's line -> row table
    add hl,bc
    add hl,bc
    ld a,(hl)
    inc hl
    ld b,(hl)
    ld c,a

    ld a,(zcam)
    call rp_zsets                       ; (common.asm, fragment 4)
    ld a,(road_curve)                   ; A = the curve level, 2 a level (the
    add a,CURVE_K                       ; templates are always the cache's,
    add a,a                             ; rr_thi)

    ; this buffer's last picture: its curve set (did it move?) and zcam
    ld hl,(rp_vars)
    inc hl
    inc hl                              ; rp_set
    ld e,(hl)
    ld (hl),a
    sub e
    ld e,a
    ld a,(rp_old_level)
    inc a
    jr nz,rp_known
    inc e                               ; nothing known: as if it moved
rp_known
    ld a,e
    ld (rp_moved),a                     ; 0: the same curve
    call rp_mode
    call rp_dzset                       ; (common.asm, fragment 4)

    ld de,(rp_slot)
    ld a,(rp_near)
    or a
    jr z,rp_far
    ld l,a
    ld a,(rp_cmp)
    or a
    ld a,l
    jp nz,rp_near_cmp
    ld a,(rp_skip)
    or a
    ld a,l
rp_skip_go
    jp nz,rp_near_skip                  ; (or rp_near_same: rp_mode_set)
rp_near_go                              ; (A lines: rp_near_skip's rest)

;; BC = line -> row table, DE = template slot of the list entry. Two lines
;; per turn of the loop; an odd count starts half way in. Each is flagged
;; 1, only the road (and the margin) - or 0, all of it, if the grass's
;; stripe on it is not what it was: (depth + zcam) AND 127 less than zcam's
;; move since then (rp_dzset: twice it, compared with twice that; 255 when
;; every line is drawn whole).
MACRO RP_LINE zl,dz
    ld a,(bc)                           ; the row this line shows
    inc bc
    ld l,a
    ld h,hi(rr_depth)
    ld a,(hl)                           ; depth, low byte
{zl}
    add a,0                             ; + zcam (self-modified)
    ld ixl,a
    add a,a                             ; (bit 7 out)
{dz}
    cp 0                                ; (self-modified) CF: the grass's
    sbc a,a                             ; stripe has moved on it
    inc a                               ; 0: all of it, 1: only the road
    dec h
    or (hl)                             ; template, low byte
    ld (de),a
    inc e                               ; (an entry never crosses a page)
    ld a,ixl
    inc h
    inc h
    and (hl)                            ; 64 (0 for the ground)
    rrca                                ; band B is #2000 higher
    inc h
    add a,(hl)                          ; template, high byte
    ld (de),a
    inc de                              ; next entry's template slot
    inc e
    inc e
MEND
    ASSERT rr_depth == rr_tlo+#100

    srl a                               ; pairs of lines (A = rp_near)
    exx
    ld b,a
    exx
    jr nc,rp_pair
    inc a                               ; odd: one more turn, entered half way
    exx
    ld b,a
    exx
    jr rp_second
rp_pair
    RP_LINE rp_zlo,rp_dz
rp_second
    RP_LINE rp_zlo2,rp_dz2
    exx
    dec b
    exx
    jr nz,rp_pair
    jp rp_far

;; Past FAR_Z the grass and the asphalt stay band A's; the kerbs and lane
;; dashes go on moving: band 0's template or band 2's, by a longer dash.
;; Long dashes change seldom. When this buffer's last picture had the same
;; curve level, a far line that shows the same row as it did then - always,
;; if the hill is the same too - has changed only if its dash has: the bit
;; of (depth + zcam) its mask picks is not what it was for the zcam of then.
;; A line that has not changed gets the skip template - no pushes at all.

;; A = (depth + zcam) AND mask (0: band 0), L = the row: write the line's
;; template - fl = 1: only the road - and step DE to the next entry's
MACRO RP_FAR_TMPL fl
    or a
    ld h,hi(rr_tlo)
    jr z,$+4
    ld h,hi(rr_tlo2)
    ld a,(hl)                           ; template, low byte
    IF {fl} == 1
    inc a                               ; (templates are at even addresses)
    ENDIF
    IF {fl} == 2
rp_far_fl
    or 0                                ; 1: only the road (self-modified)
    ENDIF
    IF {fl} == 3
rp_far_hfl
    or 0                                ; 2: a margin (rp_far_m), 0: whole
    ENDIF
    ld (de),a
    inc e
    inc h
    inc h
    inc h                               ; rr_thi / rr_thi2
    ld a,(hl)                           ; template, high byte
    ld (de),a
    inc de
    inc e
    inc e
MEND

rp_far
    ld (rp_tail),de                     ; the end, if no far line is drawn
    ld a,(rp_near)
    ld l,a
    ld a,(rp_count)
    sub l
    jp z,rp_done
    exx
    ld b,a
    exx
    ld a,(rp_moved)
    or a
    jp nz,rp_far_all
    ld hl,(rp_vars)
    ld a,(rp_old_level)
    cp (hl)
    jp nz,rp_far_hill

rp_far_line
    ld a,(bc)                           ; the row this line shows
    inc bc
    ld l,a
    ld h,hi(rr_depth)
    ld a,(hl)
    ld ixl,a
rp_zlo3
    add a,0                             ; + zcam (self-modified)
    inc h
    and (hl)                            ; which half of the dash now ...
    ld ixh,a
    ld a,ixl
rp_zold
    add a,0                             ; + zcam then (self-modified)
    and (hl)                            ; ... and then
    cp ixh
rp_fdash
    jr nz,rp_far_new                    ; (or JR: rp_dirty)
    ld a,lo(tmpl_skip)                  ; the same
    ld (de),a
    inc e
    ld a,hi(tmpl_skip)
    ld (de),a
    inc de
    inc e
    inc e
    exx
    dec b
    exx
    jr nz,rp_far_line
    jp rp_done
rp_far_new                              ; the same row: only the road
    ld a,ixh
    RP_FAR_TMPL 1
    ld (rp_tail),de                     ; the list goes at least this far
    exx
    dec b
    exx
    jr nz,rp_far_line
    jp rp_done

;; the hill moved: a line still showing the row it showed then (by the old
;; level's line -> row table, in IY) is checked as above, the others drawn
rp_far_hill
    ld l,a
    ld h,0
    add hl,hl
    push de
    ld de,level_addr
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,(rp_near)
    ld l,a
    ld h,0
    add hl,de
    push hl
    pop iy                              ; the old table, at the first far line
    pop de
rp_far_hill_line
    ld a,(bc)                           ; the row this line shows
    inc bc
    cp (iy+0)
    inc iy
    ld l,a
    ld h,hi(rr_depth)
    ld a,(hl)
    jr nz,rp_far_hill_new               ; not the row of then
    ld ixl,a
rp_zlo5
    add a,0                             ; + zcam (self-modified)
    inc h
    and (hl)
    ld ixh,a
    ld a,ixl
rp_zold2
    add a,0                             ; + zcam then (self-modified)
    and (hl)
    cp ixh
rp_fdash2
    jr nz,rp_far_hill_dash              ; (or JR: rp_dirty)
    ld a,lo(tmpl_skip)                  ; the same
    ld (de),a
    inc e
    ld a,hi(tmpl_skip)
    ld (de),a
    inc de
    inc e
    inc e
    exx
    dec b
    exx
    jp nz,rp_far_hill_line
    jp rp_done
rp_far_hill_new                         ; another row: the whole line, or a
rp_far_near                             ; margin if the hill alone moved
    jr nc,rp_far_hill_dash2             ; (rp_far_m) - only the road if it is
rp_zlo6                                 ; nearer and the road straight (offset
    add a,0                             ; self-modified, 0 = off: rp_mode)
    inc h                               ; + zcam (self-modified)
    and (hl)
    ld ixl,a
    ld a,l
    or a
    ld a,ixl
    jr z,rp_far_ground                  ; the ground: always whole
    RP_FAR_TMPL 3
    jr rp_far_hill_next
rp_far_ground
    RP_FAR_TMPL 0
    jr rp_far_hill_next
rp_far_hill_dash2
rp_zlo9
    add a,0                             ; + zcam (self-modified)
    inc h
    and (hl)
    RP_FAR_TMPL 1
    jr rp_far_hill_next
rp_far_hill_dash                        ; the same row: only the road
    ld a,ixh
    RP_FAR_TMPL 1
rp_far_hill_next
    ld (rp_tail),de
    exx
    dec b
    exx
    jp nz,rp_far_hill_line
    jp rp_done

;; the curve moved (or nothing is known): every far line is drawn, with
;; only its road and a margin if the hill is the same (rp_mode)
rp_far_all
    ld a,(bc)
    inc bc
    ld l,a
    ld h,hi(rr_depth)
    ld a,(hl)
rp_zlo4
    add a,0                             ; + zcam (self-modified)
    inc h
    and (hl)
    RP_FAR_TMPL 2
    exx
    dec b
    exx
    jr nz,rp_far_all
    ld (rp_tail),de

;; The end marker goes after the last line that is drawn: far lines that
;; are already right at the end of the list are not even looked at.
rp_done
    call rp_lane_whole                  ; (road6.asm: lanes changed)
    ld hl,(rp_tail)
    ld (hl),lo(tmpl_end)
    inc hl
    ld (hl),hi(tmpl_end)
    jp rp_grass                         ; (common.asm, fragment 4)

;; ---------------------------------------------------------------------------
;; be_prep - (bush_erase, here for room) the lines the grass of the selected
;; buffer's last picture changed its green at (road_draw: rd_gb0, rd_gb1),
;; for be_grass: be_ys, 255, then from the bottom up the first line below
;; each change (from ROAD_AREA_Y), then 0; be_c0 the bottom line's green.
;; Destroys AF, BC, DE, HL, IX.
;; ---------------------------------------------------------------------------
be_prep
    ld hl,rd_gb0
    ld de,list0
    ld a,(tgt_buf)
    or a
    jr z,be_prep_buf
    ld hl,rd_gb1
    ld de,list1
be_prep_buf
    ld a,(hl)
    ld (be_c0),a
    ld bc,RD_GB
    add hl,bc                           ; the first change's high byte
    ld ix,be_ys
    ld (ix+0),255
be_prep_one
    inc ix
    ld b,(hl)
    dec hl
    ld c,(hl)                           ; BC = the list past the line's entry
    dec hl
    ld a,b
    or c
    jr z,be_prep_end
    push hl
    ld h,b
    ld l,c
    or a
    sbc hl,de
    srl h
    rr l
    srl l                               ; entries: line ROAD_AREA_Y + LAST_Y
    ld a,LAST_Y+2                       ; + 1 - it
    sub l
    ld (ix+0),a                         ; the line below it
    pop hl
    jr be_prep_one
be_prep_end
    ld (ix+0),a
    ret

rp_level    defb #FF,#FF                ; hill level each buffer was drawn with
rp_set      defb 0,0                    ; ... curve set (pages on)
rp_zcam     defb 0,0                    ; ... zcam, low byte
rp_xmin     defb 0,0                    ; ... the least road_x a group was at
rp_xmax     defb 0,0                    ; ... the greatest
rp_kmin     defb 0,0                    ; ... the least curve level
rp_kmax     defb 0,0                    ; ... the greatest
rp_kdir     defb 0,0                    ; ... the cache's last level step
rp_vars     defw 0                      ; this buffer's rp_level entry
rp_moved    defb 0                      ; 0: the same curve as then
rp_old_level defb 0                     ; hill level then (#FF: none)
rp_cmp      defb 0                      ; 1: lines checked against the old rows
rp_skip     defb 0                      ; 1: near lines with their stripe of
                                        ; then skipped (rp_near_skip)
    ASSERT rp_set == rp_level+2
    ASSERT rp_zcam == rp_level+4
    ASSERT rp_xmin == rp_level+6 && rp_xmax == rp_level+8
    ASSERT rp_kmin == rp_level+10 && rp_kmax == rp_level+12
    ASSERT rp_kdir == rp_level+14
rp_count    defb 0                     ; lines to draw
rp_near     defb 0                     ; of which striped rows
rp_slot     defw 0
rp_tail     defw 0                      ; where the end marker goes


frag7_end
    ASSERT frag7_end <= FRAG7+FRAG_LEN

;; ===========================================================================
;; Fragment 5: road_init, and road_project's lines for a hill that moved
;; (fragment 7 is full); RAM_C6 as there.
;; ===========================================================================
    ORG FRAG5,FRAG_ST5
frag5_start

;; ---------------------------------------------------------------------------
;; road_init - fill both line lists with where each line starts, every line
;; ground, and the end marker; forget what either buffer shows.
;; ---------------------------------------------------------------------------
road_init
    ld a,#FF
    ld (rp_level),a
    ld (rp_level+1),a
    ld hl,list0
    ld b,hi(BOT0_BASE)
    call road_init_list
    ld hl,list1
    ld b,hi(BOT1_BASE)
road_init_list
    ld de,line_ends
    ld c,ROAD_LINES
road_init_loop
    ld a,(de)
    inc de
    ld (hl),a
    inc hl
    ld a,(de)
    inc de
    add a,b
    ld (hl),a
    inc hl
    ld (hl),lo(tmpl_ground)
    inc hl
    ld (hl),hi(tmpl_ground)
    inc hl
    dec c
    jr nz,road_init_loop
    xor a                               ; the end: SP is never used
    ld (hl),a
    inc hl
    ld (hl),a
    inc hl
    ld (hl),lo(tmpl_end)
    inc hl
    ld (hl),hi(tmpl_end)
    ret

;; the hill moved: IY = the old level's line -> row table
rp_near_cmp
    push af
    ld a,(rp_old_level)
    ld l,a
    ld h,0
    add hl,hl
    push de
    ld de,level_addr
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    push de
    pop iy
    pop de
    ld a,(rp_skip)                      ; the lines no move moved first
    or a                                ; (rp_rows_r), as rp_near_skip
    jr z,rp_cmp_all                     ; does: IY on with BC after them
    push iy
    pop hl
    sbc hl,bc                           ; (CF clear)
    ld (rp_cmp_d+1),hl
    ld hl,rp_cmp_go
    ld (rp_skip_jp+1),hl
    ld hl,rp_skip_rest1                 ; (rp_force once, at the end)
    ld (rp_skip_rest+1),hl
    pop af
    jp rp_near_skip
rp_cmp_go                               ; A: the lines left
rp_cmp_d
    ld hl,0                             ; (self-modified: old table - new)
    add hl,bc
    push hl
    pop iy
    push af
rp_cmp_all
    pop af
    push iy
    exx
    pop hl                              ; HL': the rows then
    ld b,a                              ; B': lines
    exx

;; One line a turn. A line that shows the row it showed then (IY) is
;; already right if it is in the band it was in then too - its template the
;; one in the list (as rp_near_same) - when nothing but the hill moved; else
;; flagged as RP_LINE does. Another row: as rp_mode_rows says (rp_flx), or
;; 0, all of it, if the grass's stripe on it is not the one on the row then.
rp_line_cmp
    ld a,(bc)                           ; the row this line shows
    inc bc
    ld l,a
    ld h,hi(rr_depth)
    ld a,(hl)                           ; depth, low byte
rp_zlo7
    add a,0                             ; + zcam (self-modified)
    ld ixl,a
    ld a,l
    exx
    cp (hl)                             ; ... and showed then
    inc hl
    exx
    jr nz,rp_other_cmp
    inc h
    ld a,ixl
    and (hl)                            ; 64 (0 for the ground)
    rrca
    inc h
    add a,(hl)                          ; template, high byte
    inc e
    ex de,hl
rp_cmp_sk
    cp (hl)                             ; the band of then? (self-modified:
    ld (hl),a                           ; OR A, never, if more than the hill
    dec hl                              ; moved - rp_mode_rows, rp_dzset)
    ex de,hl                            ; (not DEC E: the flags)
    ld h,hi(rr_tlo)
    ld a,3
    jr z,rp_same_cmp                    ; the same: skipped
    ld a,ixl
    add a,a
rp_dz7
    cp 0                                ; (self-modified, as rp_dz)
    sbc a,a
    inc a                               ; 0: all of it, 1: only the road
rp_same_cmp
    or (hl)                             ; template, low byte
    ld (de),a
    inc e
    inc de                              ; next entry's template slot
    inc e
    inc e
    exx
    dec b
    exx
    jr nz,rp_line_cmp
    jp rp_skip_end                      ; (road15.asm: rp_force, rp_far)

rp_put_cmp
    dec h
    or (hl)                             ; template, low byte
    ld (de),a
    inc e
    ld a,ixl
    inc h
    inc h
    and (hl)                            ; 64 (0 for the ground)
    rrca
    inc h
    add a,(hl)                          ; template, high byte
    ld (de),a
    inc de
    inc e
    inc e
    exx
    dec b
    exx
    jr nz,rp_line_cmp
    jp rp_skip_end

rp_other_cmp                            ; another row (CF: a further one)
    ld a,0
rp_flx
    jr z,$+3                            ; (or JR NC, JR NZ: rp_mode_rows)
    inc a                               ; 2: the road and a margin
rp_flx2
    inc a
    or a
    jr z,rp_put_cmp                     ; (0: all of it anyway)
    ld ixh,a                            ; another row's flag ...
    ld a,l
    cp GRASS_ROW
    ld a,ixl
    jr nc,$+4
    and #7F                             ; (past the stripes: GRASS_PAIR's)
    ld ixl,a                            ; (bit 7 is not the band's)
    push hl
    exx
    dec hl
    ld a,(hl)
    inc hl
    exx
    ld l,a                              ; ... unless the row then's grass
    ld a,(hl)                           ; stripe is another
rp_zo
    add a,0                             ; + zcam then (self-modified)
    ld h,a
    ld a,l
    cp GRASS_ROW
    ld a,h
    jr nc,$+4
    and #7F
    pop hl
    xor ixl
    add a,a
    sbc a,a
    cpl
    and ixh
    jr rp_put_cmp

;; ---------------------------------------------------------------------------
;; rp_mode - how this picture's lines are drawn, from E = the curve set now
;; minus then (2 a level; odd: nothing is known) and the hill now and then.
;;
;; A line that shows the row it did when this buffer was last drawn, at the
;; same curve level, needs only its road drawn: the grass is plain and
;; already right. If the curve has moved one or two levels, the road has
;; moved at most 5 pairs a level (tools/mkroad.py), so its road and that
;; many pairs of grass either side will do (rd_margin). More, or nothing
;; known: whole lines. If the hill moved, each line's row is compared with
;; the one the old level's table gives (rp_cmp); on a straight road a line
;; that now shows a nearer row needs only its road too - the old, narrower
;; one lies under it.
;;
;; Returns A = the flag for every near line: 1 = only the road (and the
;; margin), 0 = whole lines or as rp_cmp says. Sets rp_cmp, rp_far_fl (far
;; lines when the curve moved) and the compare branches.
;;
;; A far line whose dash has not moved is skipped - unless a bush that may
;; have stood in front of the far road was taken away (rp_dirty, bush.asm):
;; then it gets its road drawn.
;; ---------------------------------------------------------------------------
rp_mode
    push bc                             ; (the line -> row table)
    ld a,(rp_dirty)
    or a
    ld a,#20                            ; JR NZ
    jr z,rp_mode_dash
    ld a,#18                            ; JR
rp_mode_dash
    ld (rp_fdash),a
    ld (rp_fdash2),a
    call rp_mode_set
    pop bc
    ret
;; A = how far a group can have moved: 0 if less
rp_mode_pos
    or a
    ret p
    xor a
    ret

;; A = levels a group can have moved: 0 if less, 5 pairs a level; more than
;; two: whole lines (rp_mode_far)
rp_mode_lvl
    or a
    jp p,rp_mode_lvl_p
    xor a
    ret
rp_mode_lvl_p
    cp 3
    jr c,rp_mode_lvl_ok
    ld a,1
    ld (rp_mode_far+1),a
    xor a
    ret
rp_mode_lvl_ok
    ld d,a
    add a,a
    add a,a
    add a,d
    ret

;; CF: neither B nor C is more than RP_MARGIN_MAX
rp_mode_max
    ld a,b
    cp c
    jr nc,$+3
    ld a,c
    cp RP_MARGIN_MAX+1
    ret

;; ---------------------------------------------------------------------------
;; rd_margin - B, C = the pairs of grass road_draw draws left and right of
;; the road on an only-the-road line (both 0: none, the fast way).
;; ---------------------------------------------------------------------------
RP_MARGIN_MAX EQU 12                    ; more and whole lines are drawn
RP_HILL_M   EQU 3                       ; a line's row moved: the least margin
RP_HILL_STEP EQU 10                     ; hill levels (h/2) it may have moved
                                        ; (rp_far_m's margins allow for it)

rd_margin
    ld hl,line_road_a
    ld de,line_road_b
    ld a,b
    or c
    jr z,rd_margin_jr
    ld a,PAIRS                          ; MT = PAIRS - M: on the right
    sub c
    ld (lm_m1+1),a
    ld (lm_m2+1),a
    ld (lm_m3+1),a
    ld (lm_p1+1),a
    ld (lm_p2+1),a
    ld (lm_p3+1),a
    ld a,lo(lgrassa)+PAIRS              ; ... on the left
    sub b
    ld (lm_la+1),a
    ld (lm_la2+2),a
    ld (lm_ca+1),a
    ld (lm_ca2+2),a
    add a,(lo(lgrassb)-lo(lgrassa))&255
    ld (lm_lb+1),a
    ld (lm_lb2+2),a
    ld (lm_cb+1),a
    ld (lm_cb2+2),a
    ld hl,line_lmarg_a                  ; one side only: the faster ways
    ld de,line_lmarg_b
    ld a,c
    or a
    jr z,rd_margin_jr
    ld hl,line_rmarg_a
    ld de,line_rmarg_b
    ld a,b
    or a
    jr z,rd_margin_jr
    ld hl,line_margin_a
    ld de,line_margin_b
rd_margin_jr
    ld (lg_jr_a+1),hl
    ld (lg_jr_b+1),de
    ret

;; rd_road - only the road on an only-the-road line, whatever the margin
rd_road
    ld hl,line_road_a
    ld de,line_road_b
    jr rd_margin_jr

;; ---------------------------------------------------------------------------
;; be_grass - (bush_erase) DE = the grass then on line IXL (from
;; ROAD_AREA_Y), IXH = the next line further down whose green is the other
;; (255: none), be_p where that is in be_ys (be_prep). Keeps BC, HL.
;; be_next - the line is IXH's: DE the other green, IXH the next.
;; ---------------------------------------------------------------------------
be_grass
    push hl
    ld hl,be_ys
    ld a,ixl
    ld e,0
be_grass_one
    inc hl
    cp (hl)                             ; the changes below the line
    jr nc,be_grass_at
    inc e
    jr be_grass_one
be_grass_at
    dec hl
    ld (be_p),hl
    ld a,(hl)
    ld ixh,a
    ld a,(be_c0)
    bit 0,e
    jr z,$+4
    xor GRASS_X
    ld e,a
    ld d,a
    pop hl
    ret
be_next
    push hl
    ld hl,(be_p)
be_next_one
    ld a,e
    xor GRASS_X
    ld e,a
    ld d,a
    dec hl
    ld a,(hl)
    cp ixl
    jr z,be_next_one                    ; (two on one line: it changes back)
    ld ixh,a
    ld (be_p),hl
    pop hl
    ret

be_c0       defb lo(GRASS_PAIR)
be_p        defw 0
be_ys       defs 8,0

frag5_end
    ASSERT frag5_end <= FRAG5+FRAG_LEN
