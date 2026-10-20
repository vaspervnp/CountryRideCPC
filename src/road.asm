;; ===========================================================================
;; road.asm - road_init and road_project, in common fragment 7. They run
;; with RAM_C6: bank 6 holds the row arrays and the hill tables
;; (src/gen/roadrows.asm).
;;
;; road_project writes, for every road line, the template of the row of road
;; that line shows into the line list; road_draw (common.asm) then draws it.
;;
;; The road is made of ROWS rows. On a flat road row r is on line
;; HORIZON_Y+r, so row 109 is the bottom line and row 1 the furthest. A row
;; knows its depth and its width, and so its template: the stripe band is
;; bit 4 of (depth + zcam).
;;
;; Curves: the templates come in a set per curve level, each with every row
;; already moved sideways as far as that level bends it (tools/mkroad.py), so
;; a curve only picks the set - TMPL_SET bytes on per level.
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

    ORG FRAG7,FRAG_STORE+7*FRAG_LEN

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
    ld (rp_zlo+1),a
    ld (rp_zlo2+1),a
    ld (rp_zlo3+1),a
    ld (rp_zlo4+1),a
    ld (rp_zlo5+1),a
    ld (rp_zlo6+1),a
    ld a,(road_curve)                   ; the curve level's template set:
    add a,CURVE_K                       ; this many pages on
    ASSERT TMPL_SET == 512
    add a,a
    ld (rp_lvl+1),a
    ld (rp_lvl2+1),a
    ld (rp_lvl3+1),a
    ld (rp_lvl4+1),a
    ld (rp_lvl5+1),a

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
    inc hl
    inc hl                              ; rp_zcam
    ld a,(hl)
    ld (rp_zold+1),a
    ld (rp_zold2+1),a
    ld a,(zcam)
    ld (hl),a

    ld de,(rp_slot)
    ld a,(rp_near)
    or a
    jr z,rp_far

;; BC = line -> row table, DE = template slot of the list entry. Two lines
;; per turn of the loop; an odd count starts half way in.
MACRO RP_LINE zl,lv
    ld a,(bc)                           ; the row this line shows (0 = ground)
    inc bc
    ld l,a
    ld h,hi(rr_tlo)
    ld a,(hl)                           ; template, low byte
    ld (de),a
    inc e                               ; (an entry never crosses a page)
    inc h
    ld a,(hl)                           ; depth, low byte
{zl}
    add a,0                             ; + zcam (self-modified)
    inc h
    and (hl)                            ; 16 (0 for the ground)
    rlca                                ; band B is #2000 higher
    inc h
    add a,(hl)                          ; template, high byte
{lv}
    add a,0                             ; + the curve level (self-modified)
    ld (de),a
    inc de                              ; next entry's template slot
    inc e
    inc e
MEND

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
    RP_LINE rp_zlo,rp_lvl
rp_second
    RP_LINE rp_zlo2,rp_lvl2
    exx
    dec b
    exx
    jr nz,rp_pair

;; Past FAR_Z the grass and the asphalt stay band A's; the kerbs and lane
;; dashes go on moving: band 0's template or band 2's, by a longer dash.
;; Long dashes change seldom. When this buffer's last picture had the same
;; curve level, a far line that shows the same row as it did then - always,
;; if the hill is the same too - has changed only if its dash has: the bit
;; of (depth + zcam) its mask picks is not what it was for the zcam of then.
;; A line that has not changed gets the skip template - no pushes at all.

;; A = (depth + zcam) AND mask (0: band 0), L = the row: write the line's
;; template, step DE to the next entry's
MACRO RP_FAR_TMPL lv
    or a
    ld h,hi(rr_tlo)
    jr z,$+4
    ld h,hi(rr_tlo2)
    ld a,(hl)                           ; template, low byte
    ld (de),a
    inc e
    inc h
    inc h
    inc h                               ; rr_thi / rr_thi2
    ld a,(hl)                           ; template, high byte
{lv}
    add a,0                             ; + the curve level (self-modified)
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
    jr nz,rp_far_new
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
rp_far_new
    ld a,ixh
    RP_FAR_TMPL rp_lvl3
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
    jr nz,rp_far_hill_dash
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
    jr nz,rp_far_hill_line
    jp rp_done
rp_far_hill_new
rp_zlo6
    add a,0                             ; + zcam (self-modified)
    inc h
    and (hl)
    jr rp_far_hill_draw
rp_far_hill_dash
    ld a,ixh
rp_far_hill_draw
    RP_FAR_TMPL rp_lvl5
    ld (rp_tail),de
    exx
    dec b
    exx
    jr nz,rp_far_hill_line
    jp rp_done

;; the curve moved: every far line is drawn
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
    RP_FAR_TMPL rp_lvl4
    exx
    dec b
    exx
    jr nz,rp_far_all
    ld (rp_tail),de

;; The end marker goes after the last line that is drawn: far lines that
;; are already right at the end of the list are not even looked at.
rp_done
    ld hl,(rp_tail)
    ld (hl),lo(tmpl_end)
    inc hl
    ld (hl),hi(tmpl_end)
    ret

rp_level    defb #FF,#FF                ; hill level each buffer was drawn with
rp_set      defb 0,0                    ; ... curve set (pages on)
rp_zcam     defb 0,0                    ; ... zcam, low byte
rp_vars     defw 0                      ; this buffer's rp_level entry
rp_moved    defb 0                      ; 0: the same curve as then
rp_old_level defb 0                     ; hill level then (#FF: none)
    ASSERT rp_set == rp_level+2
    ASSERT rp_zcam == rp_level+4
rp_count    defb 0                     ; lines to draw
rp_near     defb 0                     ; of which striped rows
rp_slot     defw 0
rp_tail     defw 0                      ; where the end marker goes


frag7_end
    ASSERT frag7_end <= FRAG7+FRAG_LEN
