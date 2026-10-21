;; ===========================================================================
;; road.asm - road_project, in common fragment 7, and road_init and
;; rp_near_cmp, in fragment 5. They run with RAM_C6: bank 6 holds the row
;; arrays and the hill tables (src/gen/roadrows.asm).
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
    ld (rp_zlo+1),a
    ld (rp_zlo2+1),a
    ld (rp_zlo3+1),a
    ld (rp_zlo4+1),a
    ld (rp_zlo5+1),a
    ld (rp_zlo6+1),a
    ld (rp_zlo7+1),a
    ld (rp_zlo8+1),a
    ld (rp_zlo9+1),a
    ld a,(road_curve)                   ; the curve level's template set:
    add a,CURVE_K                       ; this many pages on
    ASSERT TMPL_SET == 512
    add a,a
    ld (rp_lvl+1),a
    ld (rp_lvl2+1),a
    ld (rp_lvl3+1),a
    ld (rp_lvl4+1),a
    ld (rp_lvl5+1),a
    ld (rp_lvl6+1),a
    ld (rp_lvl7+1),a
    ld (rp_lvl8+1),a
    ld (rp_lvl9+1),a

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
    ld (rp_fl+1),a
    ld (rp_fl2+1),a
    ld hl,(rp_vars)                     ; (rp_vars again for what follows)
    inc hl
    inc hl
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
    ld l,a
    ld a,(rp_cmp)
    or a
    ld a,l
    jp nz,rp_near_cmp

;; BC = line -> row table, DE = template slot of the list entry. Two lines
;; per turn of the loop; an odd count starts half way in.
MACRO RP_LINE zl,lv,fl,cmp
    ld a,(bc)                           ; the row this line shows (0 = ground)
    inc bc
    IF {cmp}
    cp (iy+0)                           ; ... and showed then (IY)
    inc iy
    ENDIF
    ld l,a
    ld h,hi(rr_tlo)
    ld a,(hl)                           ; template, low byte
    IF {cmp}
{fl}
    jr nz,$+3                           ; (or JR C: rp_mode)
    inc a                               ; the same row: only the road
    ELSE
{fl}
    or 0                                ; 1: only the road (self-modified)
    ENDIF
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
    RP_LINE rp_zlo,rp_lvl,rp_fl,0
rp_second
    RP_LINE rp_zlo2,rp_lvl2,rp_fl2,0
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
MACRO RP_FAR_TMPL lv,fl
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
    RP_FAR_TMPL rp_lvl3,1
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
rp_far_hill_new                         ; another row: the whole line - but
rp_far_near                             ; only the road if it is nearer and the
    jr nc,rp_far_hill_dash2             ; road straight (offset self-modified,
rp_zlo6                                 ; 0 = off: rp_mode)
    add a,0                             ; + zcam (self-modified)
    inc h
    and (hl)
    RP_FAR_TMPL rp_lvl6,0
    jr rp_far_hill_next
rp_far_hill_dash2
rp_zlo9
    add a,0                             ; + zcam (self-modified)
    inc h
    and (hl)
    RP_FAR_TMPL rp_lvl9,1
    jr rp_far_hill_next
rp_far_hill_dash                        ; the same row: only the road
    ld a,ixh
    RP_FAR_TMPL rp_lvl5,1
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
    RP_FAR_TMPL rp_lvl4,2
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
rp_cmp      defb 0                      ; 1: lines checked against the old rows
    ASSERT rp_set == rp_level+2
    ASSERT rp_zcam == rp_level+4
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
    pop af
    srl a
    exx
    ld b,a
    exx
    jr nc,rp_pair_cmp
    inc a
    exx
    ld b,a
    exx
    jr rp_second_cmp
rp_pair_cmp
    RP_LINE rp_zlo7,rp_lvl7,rp_flx,1
rp_second_cmp
    RP_LINE rp_zlo8,rp_lvl8,rp_fly,1
    exx
    dec b
    exx
    jr nz,rp_pair_cmp
    jp rp_far

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
rp_mode_set
    xor a
    ld (rp_cmp),a
    ld (rp_far_fl+1),a
    ld a,e
    bit 0,a
    jr nz,rp_mode_whole                 ; nothing known
    or a
    jp p,rp_mode_abs
    neg
rp_mode_abs
    cp 5
    jr nc,rp_mode_whole                 ; more than two levels
    ld c,a                              ; 0, 2 or 4: M = 0, 5 or 10 pairs
    rrca
    add a,c
    add a,c                             ; 5 * A / 2
    call rd_margin
    ld a,(rp_old_level)
    ld hl,(rp_vars)
    cp (hl)
    jr nz,rp_mode_hill
    ld a,1
    ld (rp_far_fl+1),a                  ; the same hill: every line
    ret
rp_mode_hill
    ld a,1                              ; the hill moved: compare the rows
    ld (rp_cmp),a
    ld a,(rp_moved)
    ld hl,(#20*256)+0                   ; JR NZ: the same row; far: off
    or a
    jr nz,rp_mode_op
    ld a,(road_curve)
    or a
    jr nz,rp_mode_op
    ld hl,(#38*256)+rp_far_hill_dash2-rp_far_near-2   ; JR C: no farther row
rp_mode_op
    ld a,h
    ld (rp_flx),a
    ld (rp_fly),a
    ld a,l
    ld (rp_far_near+1),a
rp_mode_whole
    xor a
    ret

;; ---------------------------------------------------------------------------
;; rd_margin - A = M, the pairs of grass road_draw draws either side of the
;; road on an only-the-road line (0: none, the fast way).
;; ---------------------------------------------------------------------------
rd_margin
    or a
    ld hl,line_road_a
    ld de,line_road_b
    jr z,rd_margin_jr
    neg
    add a,PAIRS                         ; MT = PAIRS - M
    ld (lm_m1+1),a
    ld (lm_m2+1),a
    ld (lm_m3+1),a
    ld (lm_p1+1),a
    ld (lm_p2+1),a
    ld (lm_p3+1),a
    ld c,a
    add a,lo(lgrassa)
    ld (lm_la+1),a
    ld (lm_la2+2),a
    ld a,c
    add a,lo(lgrassb)
    ld (lm_lb+1),a
    ld (lm_lb2+2),a
    ld hl,line_margin_a
    ld de,line_margin_b
rd_margin_jr
    ld (lg_jr_a+1),hl
    ld (lg_jr_b+1),de
    ret

frag5_end
    ASSERT frag5_end <= FRAG5+FRAG_LEN
