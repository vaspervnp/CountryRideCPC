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
;; Hills: a crest ahead of strength h moves row r down by h/r lines - the
;; same h/r a parabolic crest gives in perspective - so the near road hardly
;; moves, the far road drops away, and from the row where h/r grows faster
;; than r shrinks the road is hidden behind the crest. A negative h lifts the
;; far road instead; it is cut off at MOUNT_BOTTOM, which is never covered.
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
    ld hl,far_shown
    ld de,far_shown+1
    ld bc,2*FAR_SHOWN_LEN-1
    ld (hl),a
    ldir
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
;; not change is at the top: the ground behind a crest, and with the same
;; hill as last time also the far rows, which have no stripes. The end marker
;; goes in after the last line that is drawn.
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

    ; far_shown: what each far line of this buffer shows, for skipping the
    ; ones that have not changed. Lines that were drawn as near rows since it
    ; was written are not known: when the near part shrinks, forget them.
    push bc
    ld hl,far_shown
    ld de,rp_last_near
    ld a,(road_buf)
    or a
    jr z,rp_fs_buf
    ld hl,far_shown+FAR_SHOWN_LEN
    inc de
rp_fs_buf
    ld (rp_fs_base),hl
    ld a,(rp_near)
    ld c,a                              ; near now (as drawn)
    ld a,(de)                           ; near last time (#FF: unknown -
    cp ROAD_LINES                       ; then every line is)
    jr c,rp_fs_known
    ld a,ROAD_LINES
rp_fs_known
    ex de,hl
    ld (hl),c
    cp c
    jr c,rp_fs_ok                       ; grew or the same: nothing turned far
    jr z,rp_fs_ok
    sub c
    ld b,a                              ; lines c .. last-1 turned far
    ld l,c
    ld h,0
    add hl,hl
    ld de,(rp_fs_base)
    add hl,de
rp_fs_forget
    ld (hl),#FF
    inc hl
    ld (hl),#FF
    inc hl
    djnz rp_fs_forget
rp_fs_ok
    pop bc

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
    ld de,(rp_slot)
    ld a,(rp_near)
    or a
    jr z,rp_far

;; BC = line -> row table, DE = template slot of the list entry. Two lines
;; per turn of the loop; an odd count starts half way in.
MACRO RP_LINE zl
    ld a,(bc)                           ; the row this line shows (0 = ground)
    inc bc
    ld l,a
    ld h,hi(rr_tlo)
    ld a,(hl)                           ; template, low byte
    ld (de),a
    inc de
    inc h
    ld a,(hl)                           ; depth, low byte
{zl}
    add a,0                             ; + zcam (self-modified)
    inc h
    and (hl)                            ; 16 (0 for the ground)
    rrca                                ; band B is #800 higher
    inc h
    add a,(hl)                          ; template, high byte
    ld (de),a
    inc de
    inc de                              ; next entry's template slot
    inc de
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
    RP_LINE rp_zlo
rp_second
    RP_LINE rp_zlo2
    exx
    dec b
    exx
    jr nz,rp_pair

;; Past FAR_Z the grass and the asphalt stay band A's; the kerbs and lane
;; dashes go on moving: band 0's template or band 2's, by a longer dash.
;; Long dashes change seldom, so a far line whose template is what the
;; buffer already shows gets the skip template - no pushes at all.
rp_far
    ld a,(rp_near)
    ld l,a
    ld h,0
    add hl,hl
    push de
    ld de,(rp_fs_base)
    add hl,de
    pop de
    push hl
    pop ix                              ; IX = far_shown entry of this line
    ld a,(rp_near)
    ld l,a
    ld a,(rp_count)
    sub l
    jr z,rp_done
    exx
    ld b,a
    exx
rp_far_line
    ld a,(bc)                           ; the row this line shows (0 = ground)
    inc bc
    ld l,a
    ld h,hi(rr_depth)
    ld a,(hl)
rp_zlo3
    add a,0                             ; + zcam (self-modified)
    inc h
    and (hl)                            ; which half of the dash
    ld h,hi(rr_tlo)
    jr z,rp_far_a
    ld h,hi(rr_tlo2)
rp_far_a
    ld a,(hl)                           ; template, low byte
    ex af,af'
    inc h
    inc h
    inc h                               ; rr_thi / rr_thi2
    ld a,(hl)                           ; template, high byte
    cp (ix+1)
    jr nz,rp_far_new
    ex af,af'
    cp (ix+0)
    jr z,rp_far_same
    ex af,af'
rp_far_new                              ; A = high byte, A' = low byte
    ld (ix+1),a
    inc de
    ld (de),a
    dec de
    ex af,af'
    ld (ix+0),a
    ld (de),a
    jr rp_far_next
rp_far_same
    ld a,lo(tmpl_skip)
    ld (de),a
    inc de
    ld a,hi(tmpl_skip)
    ld (de),a
    dec de
rp_far_next
    inc de
    inc de
    inc de
    inc de
    inc ix
    inc ix
    exx
    dec b
    exx
    jr nz,rp_far_line

rp_done
    ld a,(rp_count)
    cp ROAD_LINES
    ret z                               ; every line: the end is in place
    ex de,hl                            ; the end marker after the last one
    ld (hl),lo(tmpl_end)
    inc hl
    ld (hl),hi(tmpl_end)
    ret

rp_level    defb #FF,#FF                ; hill level each buffer was drawn with
rp_count    defb 0                     ; lines to draw
rp_near     defb 0                     ; of which striped rows
rp_slot     defw 0
rp_last_near defb #FF,#FF               ; striped lines each buffer last had
rp_fs_base  defw 0

FAR_SHOWN_LEN EQU 2*ROAD_LINES
far_shown   EQU FRAG8                   ; per buffer, per line: the template on
                                        ; screen if it was a far line, else #FFFF

frag7_end
    ASSERT frag7_end <= FRAG7+FRAG_LEN
