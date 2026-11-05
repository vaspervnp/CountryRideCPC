;; ===========================================================================
;; traffic.asm - the traffic (bank 6, RAM_C6): up to TR_MAX cars ahead in
;; the road's lanes, all at TR_SPEED, which the player catches up with and
;; passes. tools/mktrafcode.py makes their sprites - pieces of code that
;; take a car's paint from registers (gen/traffic.asm, gen/trafcode_*.asm,
;; gen/rowhole*.asm) - and the tables; scene.py says where they go and what
;; they look like, and this has to match it.
;;
;; A car comes TR_ZSPAWN ahead (out of sight), in a lane, closed, a sports
;; car's or a saloon's tail, its top and its bottom each one of 16 colours
;; - at random - no sooner than TR_GAP behind the last one,
;; so that only one is near at a time. It goes when it has gone by
;; (TR_ZNEAR) or got away (TR_ZAWAY). 3 in 8 change lanes, once, to one
;; next to theirs: from 256 + TR_WHEN ahead on, TR_STEP of the way a
;; picture.
;;
;; A picture (road_frame):
;;
;;   traffic_pre   (before road_project) the lines this buffer's cars of
;;                 last time stood on are to have their road drawn where
;;                 road_project would skip them (rp_force_all: a car is
;;                 always on the road); the cars move on, go, come
;;   road_project, road_draw
;;   traffic_draw  the cars in sight, the furthest first, each noted for
;;                 the next traffic_pre of this buffer
;;
;; A car is drawn like a bush (bush.asm): its row from how far ahead it is,
;; its size from its row (tr_rsize), its line h/r down (a crest) or up (a
;; dip) - and only all of it: on the screen, below the road's top (no ground
;; under it) and over near lines (road_project forces those). Its place is
;; its lane's (tr_lat1/2) from the road's centre - its template group's,
;; the curve's shift (tr_cs) and road_x's share (rd_gp) - kept on the road
;; its top line shows (tr_edge), narrower and bent more than its own row's.
;; ===========================================================================

TR_MAX      EQU 2
TR_REC      EQU 13                      ; a car:
TR_ON       EQU 0                       ;   0: none
TR_ZR       EQU 1                       ;   how far ahead (2)
TR_LANE     EQU 3                       ;   0-3, left to right
TR_TOP      EQU 4                       ;   its top's piece: 0 (from its
                                        ;   size's first; the closed alone)
TR_BOT      EQU 5                       ;   its bottom's (TR_TOPS + 0-1) x
                                        ;   TR_PIECE_LEN
TR_PT       EQU 6                       ;   its top's paint: the even lines'
                                        ;   byte, the odd lines' (tr_colours)
TR_PB       EQU 8                       ;   its bottom's
TR_SHIFT    EQU 10                      ;   changing lanes: its share of the
                                        ;   way (/256; 0: not)
TR_TO       EQU 11                      ;   the lane it changes to
TR_WHEN     EQU 12                      ;   it begins 256 + this ahead (0:
                                        ;   never, or done)
TR_STEP     EQU 8                       ; of the way a picture (32: 1.3 s)
TR_SPEED    EQU 3                       ; depth units a VSYNC
TR_ZNEAR    EQU 72                      ; nearer: gone by (as a bush)
TR_ZSPAWN   EQU 512                     ; where a car comes, out of sight
TR_ZAWAY    EQU 640                     ; further: got away
TR_GAP      EQU 160                     ; the last car at least this far
                                        ; ahead of where a new one comes
TR_PAUSE    EQU 24                      ; pictures at least between two
                                        ; at the start (then the stage's:
                                        ; tr_pauses, gen/stages6.asm)
TR_LATE     EQU 10                      ; interrupts since the flip: from
                                        ; the one before, the nearer car
                                        ; alone, from this one only at a
                                        ; near size (traffic_draw)
    ASSERT TR_ZR == 1 && 256 % TR_STEP == 0
    ASSERT TR_SPEED == 3 && TR_ZNEAR < 256 && TR_ZAWAY == #280

tr_cars     defs TR_MAX*TR_REC,0
tr_seed     defw #ACE1
tr_wait     defb TR_PAUSE
tr_zcam     defw 0                      ; zcam the last picture
tr_dropped  defb 0                      ; 1: the further car was not
                                        ; drawn, 2: neither (traffic_draw)
tr_rngp     defw tr_drawn               ; (rp_force_all) this buffer's
tr_drawn    defb LAST_Y,0,LAST_Y,0      ; per buffer: its cars' lines, first
            defb LAST_Y,0,LAST_Y,0      ; and last (from ROAD_AREA_Y)
    ASSERT hi(tr_drawn) == hi(tr_drawn+7)

;; ---------------------------------------------------------------------------
;; rp_force_all - (road_project, RAM_C6, after rp_near_skip or rp_line_cmp
;; - road15.asm) the lines a bush on the inside stood on (rp_dirty:
;; rp_dlo..rp_dhi) and those this buffer's cars stood on, that it skipped:
;; their road drawn after all (rp_force). Keeps BC, DE.
;; ---------------------------------------------------------------------------
rp_force_all
    push ix
    ld a,(rp_dirty)
    or a
    ld ix,rp_dlo
    call nz,rp_force
    ld ix,(tr_rngp)
    call rp_force
    inc ix
    inc ix
    call rp_force
    pop ix
    ret

;; A = H = 16 random bits' high byte (xorshift 7, 9, 8), L the low.
tr_rnd
    ld hl,(tr_seed)
    ld a,h
    rra
    ld a,l
    rra
    xor h
    ld h,a
    ld a,l
    rra
    ld a,h
    rra
    xor l
    ld l,a
    xor h
    ld h,a
    ld (tr_seed),hl
    ret

;; ---------------------------------------------------------------------------
;; traffic_pre - (road_frame, RAM_C6, before road_project) see above.
;; Destroys everything.
;; ---------------------------------------------------------------------------
traffic_pre
    ld a,(road_buf)                     ; this buffer's cars of last time:
    add a,a                             ; their lines (rp_force_all)
    add a,a
    add a,lo(tr_drawn)
    ld l,a
    ld h,hi(tr_drawn)
    ld (tr_rngp),hl
    ld a,(hill)                         ; one of them past the near lines (a
    add a,128                           ; hill come since): the far lines
    srl a                               ; drawn too (rp_dirty)
    add a,lo(level_near)
    ld e,a
    ld d,hi(level_near)
    ld a,(de)
    ld c,a                              ; C = the near lines now
    ld a,LAST_Y
    sub (hl)
    cp c
    jr nc,tp_dirty
    inc l
    inc l
    ld a,LAST_Y
    sub (hl)
    cp c
    jr c,tp_move
tp_dirty
    ld a,#80
    ld (rp_dirty),a
tp_move
    ; the cars move on: as far as they went, less the camera's move; those
    ; gone by or got away go
    ld hl,(zcam)
    ld de,(tr_zcam)
    ld (tr_zcam),hl
    or a
    sbc hl,de
    ld a,(frame_vbls)
    ld c,a
    add a,a
    add a,c
    ld e,a
    ld d,0
    ex de,hl
    sbc hl,de                           ; (CF clear)
    ex de,hl                            ; DE = how far ahead a car went
    ld hl,tr_cars
    call tp_one
    ld hl,tr_cars+TR_REC
    call tp_one
    ASSERT TR_MAX == 2

    ; a new one may come: a free place, the other one far enough ahead
    ld hl,tr_wait
    ld a,(hl)
    or a
    jr z,tp_may
    dec (hl)
    ret
tp_may                                  ; a free place, HL; the other one, DE
    ld a,(tr_cars+TR_ON)
    or a
    jr nz,tp_may1
    ld hl,tr_cars
    ld de,tr_cars+TR_REC+TR_ZR
    ld a,(tr_cars+TR_REC+TR_ON)
    jr tp_other
tp_may1
    ld a,(tr_cars+TR_REC+TR_ON)
    or a
    ret nz                              ; no place
    ld hl,tr_cars+TR_REC
    ld de,tr_cars+TR_ZR
    inc a                               ; (the other one is on)
tp_other
    or a
    jr z,tp_new                         ; the other one is off too
    ex de,hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld bc,TR_ZSPAWN-TR_GAP+1
    sbc hl,bc                           ; (CF clear)
    ret nc                              ; too near where it would come
    ex de,hl
tp_new
    ld (hl),1                           ; HL = the place
    inc hl
    ld (hl),lo(TR_ZSPAWN)
    inc hl
    ld (hl),hi(TR_ZSPAWN)
    inc hl
    push hl
    call tr_rnd
    ld b,a
    ld c,l
    pop hl
    and 3
    ld (hl),a                           ; lane: bits 0-1
    inc hl
    ld (hl),0                           ; the top: closed (the only one)
    inc hl
    ld a,b
    and 8
    jr z,$+4
    ld a,TR_PIECE_LEN
    add a,TR_TOPS*TR_PIECE_LEN
    ld (hl),a                           ; the tail: sport or saloon (bit 3)
    inc hl
    ld a,c                              ; the colours: the top's, and the
    bit 4,c                             ; bottom's the same or another
    jr z,tp_same
    rrca
    rrca
    rrca
    rrca
tp_same
    ld b,a
    ld a,c
    call tp_paint
    ld a,b
    call tp_paint
    ld (hl),0                           ; not changing lanes
    inc hl
    ex de,hl                            ; DE = its TR_TO
    call tr_rnd                         ; the next no sooner than the stage's
    push hl                             ; (L: this one's lanes, below)
    and 31                              ; pause (tr_pauses), and up to 31
    ld b,a                              ; pictures more
    ld a,(stage_id)                     ; (race.asm: mapped in RAM_C6)
    add a,lo(tr_pauses)
    ld l,a
    ld h,hi(tr_pauses)
    ld a,b
    add a,(hl)
    ld (tr_wait),a
    pop bc                              ; C = random
    ld hl,TR_LANE-TR_TO
    add hl,de
    ld a,(hl)                           ; the lane it may change to: the
    ld b,a                              ; other on its side, or (bit 3) the
    xor 1                               ; other side's inner one if it is
    bit 3,c                             ; in an inner one
    jr z,tp_to
    inc b
    bit 1,b
    jr z,tp_to
    xor 2
tp_to
    ld (de),a
    inc de
    ld a,c                              ; and when: 3 in 8, 256 + 128-224
    and 7                               ; ahead (bits 4-5)
    cp 3
    ld a,0
    jr nc,tp_when                       ; (never)
    ld a,c
    and #30
    add a,a
    add a,128
tp_when
    ld (de),a
    ret
    ASSERT TR_ON == 0 && TR_ZR == 1 && TR_LANE == 3 && TR_PB == 8
    ASSERT TR_SHIFT == 10 && TR_TO == 11 && TR_WHEN == 12

;; colour A AND 15's paint (tr_colours) at HL on. Destroys AF, DE.
tp_paint
    and 15
    add a,a
    push hl
    add a,lo(tr_colours)
    ld l,a
    adc a,hi(tr_colours)
    sub l
    ld h,a
    ld e,(hl)
    inc hl
    ld d,(hl)
    pop hl
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ret

;; HL = a car: if on, DE further ahead; off if now out of TR_ZNEAR..TR_ZAWAY;
;; on its way to another lane (tp_lanes). Destroys AF, B, HL.
tp_one
    ld a,(hl)
    or a
    ret z
    inc hl
    ld a,(hl)
    add a,e
    ld (hl),a
    ld b,a
    inc hl
    ld a,(hl)
    adc a,d
    ld (hl),a
    dec hl
    dec hl
    cp 2
    jr c,tp_one_lo
    jr nz,tp_one_off                    ; (and behind: negative)
    ld a,b
    cp lo(TR_ZAWAY)
    jr c,tp_lanes
    jr tp_one_off
tp_one_lo
    or a
    jr nz,tp_lanes1
    ld a,b
    cp TR_ZNEAR
    jr nc,tp_lanes
tp_one_off
    ld (hl),0
    ret

;; HL = a car still on, B its zr's low byte: changing lanes, TR_STEP more of
;; the way - all of it, in that lane; 256-511 ahead (tp_lanes1) and no
;; further than 256 + TR_WHEN, it begins to (once: TR_WHEN 0 then).
tp_lanes
    ld a,l
    add a,TR_SHIFT
    ld l,a
    ld a,(hl)
    or a
    ret z
    jr tp_step
tp_lanes1
    ld a,l
    add a,TR_SHIFT
    ld l,a
    ld a,(hl)
    or a
    jr nz,tp_step
    inc l
    inc l
    ld a,b
    cp (hl)
    ret nc                              ; not yet (or never: 0)
    ld (hl),0
    dec l
    dec l
    xor a
tp_step
    add a,TR_STEP
    ld (hl),a
    ret nz
    inc l                               ; there (0)
    ld b,(hl)
    ld a,l
    sub TR_TO-TR_LANE
    ld l,a
    ld (hl),b
    ret
    ASSERT TR_WHEN == TR_SHIFT+2 && TR_TO == TR_SHIFT+1
    ASSERT hi(tr_cars) == hi(tr_cars+TR_MAX*TR_REC-1)

;; ---------------------------------------------------------------------------
;; traffic_draw - (road_frame, RAM_C6, after road_draw) the cars in sight
;; into buffer (road_buf), the furthest first, their lines noted in
;; tr_drawn. Destroys everything.
;; ---------------------------------------------------------------------------
traffic_draw
    ld a,(hill)                         ; what the hill and the curve give,
    add a,128                           ; if they are not as they were
    srl a
td_level
    cp #FF                              ; (self-modified: the last level)
    call nz,td_hill
    ld a,(road_curve)
td_curve
    cp #80                              ; (self-modified: the last level)
    call nz,td_bend
    ld a,(road_buf)                     ; the buffer: its lines #8000 lower
    or a                                ; for buffer 1
    ld hl,0                             ; (nop, nop)
    jr z,$+5
    ld hl,#BCCB                         ; (res 7,h)
    ld (tp_buf),hl
    ld hl,(tr_rngp)                     ; its cars' lines: none yet
    ld (to_note+1),hl
    ld (hl),LAST_Y
    inc l
    ld (hl),0
    inc l
    ld (hl),LAST_Y
    inc l
    ld (hl),0

    ld hl,(tr_cars+TR_ZR)               ; the furthest first
    ld de,(tr_cars+TR_REC+TR_ZR)
    or a
    sbc hl,de
    ld ix,tr_cars
    ld hl,tr_cars+TR_REC
    jr nc,td_order
    ld ix,tr_cars+TR_REC
    ld hl,tr_cars
td_order                                ; IX the further one, HL the nearer
    ld a,(hl)                           ; (TR_ON) the nearer off: the other
    or a                                ; is the nearer
    jr nz,td_order_on
    push ix
    ex (sp),hl
    pop ix
td_order_on
    push hl
    xor a                               ; the picture late already: the
    ld (tr_dropped),a                   ; flip 10 ms away at most - a picture
    ld a,(irq_n)                        ; whose hill moves, as a rule - the
    cp TR_LATE-1                        ; nearer one alone; 6.7 ms: it alone
    jr c,td_both                        ; if at a near size, else neither
    ld c,a
    inc hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld de,TR_ZNEARSIZE
    or a
    sbc hl,de
    jr c,td_late
    ld a,c
    cp TR_LATE
    jr c,td_late
    ld a,2                              ; (neither: tr_one not called)
    ld (tr_dropped),a
    pop hl
    ret
td_late
    ld a,(ix+TR_ON)
    or a
    jr z,td_near                        ; (the further one off anyway)
    ld a,1
    ld (tr_dropped),a
    jr td_near
td_both
    call tr_one
td_near
    pop ix
    jp tr_one

;; A = the hill's level (hill = 2 level - 128): the hill as the bushes have
;; it - no stronger a crest than BUSH_HILL_MAX - and the furthest row in
;; sight on it; the road's top, its near lines and its line -> row table.
td_hill
    ld (td_level+1),a
    ld e,a
    ld d,0
    add a,a
    sub 128                             ; (even)
    cp BUSH_HILL_MAX+1
    jr c,td_hill_eff
    cp #80
    jr nc,td_hill_eff
    ld a,BUSH_HILL_MAX
td_hill_eff
    ld (to_hill+1),a
    add a,128
    rrca
    and #7F
    or lo(bush_rtop)
    ld l,a
    ld h,hi(bush_rtop)
    ld a,(hl)
    ld (to_far+1),a
    ld hl,level_ground
    add hl,de
    ld a,(hl)
    add a,ROAD_Y-ROAD_AREA_Y
    ld (to_rtop+1),a
    ld hl,level_near
    add hl,de
    ld a,(hl)
    ld (to_near+1),a
    ld hl,level_addr
    add hl,de
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld (to_rows+1),hl
    ret

;; A = the curve level: its shifts (tr_cs), right or left (none: level 0)
td_bend
    ld (td_curve+1),a
    ld c,#86                            ; (add a,(hl))
    or a
    jp p,td_bend_r
    neg
    ld c,#96                            ; (sub (hl))
td_bend_r
    jr nz,td_bend_k
    ld c,#B7                            ; (or a)
    inc a
td_bend_k
    ld b,a
    ld hl,tr_cs-NGROUPS-#CD
    ld de,NGROUPS
    add hl,de
    djnz $-1
    ld (to_cs+1),hl
    ld a,c
    ld (to_csop),a
    ret

;; A = the road's centre on row C, bytes from the middle of the screen
;; (signed): its template group's place - the curve's shift and road_x's
;; share (rd_gp). Destroys DE, HL.
tr_centre
    ld a,c
    or lo(bush_rh)
    ld l,a
    ld h,hi(bush_rh)
    ld e,(hl)                           ; E = its group's lane, #CD + g
    ld d,0
    ld l,e
    ld h,hi(rd_gp)
    ld a,(hl)                           ; road_x's share
to_cs
    ld hl,0                             ; (self-modified: the level's shifts
    add hl,de                           ; less #CD)
to_csop
    add a,(hl)                          ; (self-modified: sub (hl), or a)
    ret

;; A = a lane: its place on row C, from the road's centre (bytes, signed) -
;; lanes 2 and 3 tr_lat1 and tr_lat2 right of it, 1 and 0 those mirrored
;; (-that - the car's width). Destroys D, HL.
to_place
    ld d,a
    inc a                               ; (lanes 1 and 2: 2 and 3 - bit 1)
    and 2
    ld a,c
    jr z,to_outer
    add a,lo(tr_lat1)
    ld l,a
    adc a,hi(tr_lat1)
    jr to_lat
to_outer
    add a,lo(tr_lat2)
    ld l,a
    adc a,hi(tr_lat2)
to_lat
    sub l
    ld h,a
    ld a,(hl)                           ; the place, right
    bit 1,d
    ret nz
    neg
    ld hl,(to_size)
    sub (hl)                            ; mirrored: -place - width
    ret

;; A = car IX's share of the way to its TR_TO lane (/256), B = its place on
;; row C: B on that far, rounded towards it. Destroys AF, HL.
to_way
    push de
    push bc
    ld e,a                              ; E = the share
    ld a,(ix+TR_TO)
    call to_place
    sub b                               ; A = the way (signed)
    ld c,a
    jp p,$+5
    neg
    ld h,a
    ld l,0
    ld d,l
    ld b,8
to_mul                                  ; HL = |the way| x the share
    add hl,hl
    jr nc,$+3
    add hl,de
    djnz to_mul
    ld a,h
    bit 7,c
    jr z,$+4
    neg
    pop bc
    add a,b
    ld b,a
    pop de
    ret

;; ---------------------------------------------------------------------------
;; tr_one - car IX into the buffer, if it is in sight: its row, its size,
;; its line, its left; then its pieces (tr_piece).
;; ---------------------------------------------------------------------------
tr_one
    ld a,(ix+TR_ON)
    or a
    ret z
    ld l,(ix+TR_ZR)                     ; (TR_ZNEAR..TR_ZAWAY: traffic_pre)
    ld a,(ix+TR_ZR+1)
    cp 2                                ; its row: every 2 below 512, every 8
    jr nc,to_rz2                        ; beyond
    rra
    ld a,l
    rra
    ld l,a
    ld h,hi(bush_rz1)
    jr to_rz
to_rz2
    ld h,a
    ld a,l
    srl h
    rra
    srl h
    rra
    srl h
    rra
    sub 512/8
    or lo(bush_rz2)
    ld l,a
    ld h,hi(bush_rz2)
to_rz
    ld a,(hl)
to_far
    cp 0                                ; (self-modified: the furthest row in
    ret c                               ; sight) none, or behind the crest
    ld c,a                              ; C = its row
    add a,lo(tr_rsize)
    ld l,a
    adc a,hi(tr_rsize)
    sub l
    ld h,a
    ld a,(hl)
    cp #FF
    ret z                               ; too far to draw
    add a,lo(tr_sinfo)
    ld l,a
    adc a,hi(tr_sinfo)
    sub l
    ld h,a
    ld (to_size),hl                     ; its size's record

    ; its line, from ROAD_AREA_Y: HORIZON_Y + r, moved |hill| / r down (a
    ; crest) or up (a dip)
to_hill
    ld a,0                              ; (self-modified: the hill)
    or a
    jr z,to_flat
    ld b,a
    jp p,to_down
    neg
to_down
    ld e,0
to_div
    sub c
    jr c,to_divd
    inc e
    jr to_div
to_divd
    ld a,b
    or a
    ld a,e
    jp p,to_flat
    neg
to_flat
    add a,HORIZON_Y-ROAD_AREA_Y
    add a,c
    cp LAST_Y+1
    ret nc                              ; below the road's last line
    ld b,a                              ; B = its base line
    inc hl
    sub (hl)
    inc a                               ; A = its top line
to_rtop
    cp 0                                ; (self-modified: the road's top)
    ret c                               ; ground under it
    ld e,a
    cpl
    add a,LAST_Y+1                      ; LAST_Y - its top line: the entry
to_near
    cp 0                                ; (self-modified: the near lines)
    ret nc                              ; far lines under it
    ld (to_entry+1),a
    ld d,b
    ld (to_lines),de

    ; its left, from the middle of the screen (signed, a byte): its lane's
    ; place from the road's centre on its row (to_place) - changing lanes,
    ; on from there its share of the way to the other's (to_way)
    call tr_centre
    ld e,a                              ; E = the centre (from the middle)
    ld a,(ix+TR_LANE)
    call to_place
    ld b,a
    ld a,(ix+TR_SHIFT)
    or a
    call nz,to_way
    ld a,b
    add a,e
    ld b,a                              ; B = its left
    ; ... but on the road on its top line's row: its left from the centre
    ; there no more than the road's reach there less its width, nor less
    ; than minus the reach
to_entry
    ld a,0                              ; (self-modified: its top line's
to_rows                                 ; entry)
    ld hl,0                             ; (self-modified: the level's line ->
    add a,l                             ; row table, bottom line first)
    ld l,a
    adc a,h
    sub l
    ld h,a
    ld c,(hl)                           ; C = the row there
    call tr_centre
    ld e,a                              ; E = the centre there
    ld a,c
    add a,lo(tr_edge)
    ld l,a
    adc a,hi(tr_edge)
    sub l
    ld h,a
    ld c,(hl)                           ; C = the road's reach there
    ld a,b
    sub e
    ld b,a                              ; B = its left from the centre there
    ld hl,(to_size)
    add a,(hl)
    sub c                               ; its right past the reach, by A?
    jr z,to_in_r
    jp m,to_in_r
    neg
    add a,b
    ld b,a                              ; then that far in
to_in_r
    ld a,b
    add a,c
    jp p,to_in_l                        ; its left past minus the reach?
    ld a,c
    neg
    ld b,a                              ; then at it
to_in_l
    ld a,b
    add a,e
    ld b,a                              ; B = its left
    xor #80                             ; (+ 128: unsigned)
    cp 128-SCR_BYTES/2
    ret c                               ; out to the left
    add a,(hl)
    ret c
    cp 128+SCR_BYTES/2+1
    ret nc                              ; out to the right
    ld a,b
    add a,SCR_BYTES/2
    ld (to_left),a

    ; touching our car: its base line in the car's lower half, and the two
    ; overlapping, HIT_TRIM bytes in from either's side (coll)
    ld a,(to_lines+1)
    cp HIT_Y
    jr c,to_drawn
    ld a,(hl)
    srl a
    ld c,a                              ; C = its half width
    add a,b
    ld b,a                              ; B = its centre, from the middle
    ld a,(car_offc)
    add a,a                             ; (ours: car_off pairs right)
    neg
    add a,b
    ld b,#80                            ; (left of ours)
    jp m,to_hit
    inc b                               ; (right)
    neg
to_hit
    add a,c                             ; - |theirs - ours| + its half width
    add a,CAR_HALF-HIT_TRIM              ; + ours: still above 0?
    jp m,to_drawn
    jr z,to_drawn
    ld a,b
    ld (coll),a

to_drawn                                ; drawn: its lines noted
    ld de,(to_lines)
to_note
    ld hl,0                             ; (self-modified: this buffer's next)
    ld (hl),e
    inc l
    ld (hl),d
    inc l
    ld (to_note+1),hl

    ; the pieces: a near size's top in its colour, then its bottom in
    ; another; a further size's whole car, its bottom's colour from its
    ; top's end (tr_cw2)
    ld hl,(to_size)
    inc hl
    inc hl
    ld b,(hl)                           ; B = its top's lines
    inc hl
    ld a,(hl)                           ; its first piece's record
    ld d,(ix+TR_PT)
    ld e,d
    ld c,(ix+TR_PT+1)
    ld iyh,c
    ld iyl,c                            ; DE, IY = its top's paint
    cp TR_NEAR*(TR_TOPS+TR_BOTTOMS)*TR_PIECE_LEN
    jr c,to_near_size
    add a,(ix+TR_TOP)                   ; a further size: one piece
    ld c,a
    ld l,(ix+TR_PB)
    ld h,l
    ld (tr_cw2),hl
    ld l,(ix+TR_PB+1)
    ld h,l
    ld (tr_cw2+2),hl
    ld a,c
    ld b,0
    jp tr_piece
to_near_size
    ld c,a
    push bc
    add a,(ix+TR_TOP)
    ld b,0
    push ix
    call tr_piece
    pop ix
    pop bc
    ld d,(ix+TR_PB)
    ld e,d
    ld a,(ix+TR_PB+1)
    ld iyh,a
    ld iyl,a
    ld a,c
    add a,(ix+TR_BOT)
    jp tr_piece                         ; (B: lines on from its top)

to_size     defw 0                      ; the car's size's record
to_lines                                ; its lines, from ROAD_AREA_Y:
to_line     defb 0                      ; its top
            defb 0                      ; its base
to_left     defb 0                      ; its left, bytes

;; ---------------------------------------------------------------------------
;; tr_piece - the piece at tr_pieces + A, B lines below the car's top
;; (to_line): HL at the right end of its first line's run (to_left on), in
;; its RAM configuration (tr_go). DE, IY its paint. Destroys everything but
;; IY.
;; ---------------------------------------------------------------------------
tr_piece
    push de                             ; (the paint)
    add a,lo(tr_pieces)
    ld l,a
    adc a,hi(tr_pieces)
    sub l
    ld h,a
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push de
    pop ix                              ; IX = its code
    ld c,(hl)                           ; C = its configuration
    inc hl
    ld a,(to_line)
    add a,b
    add a,(hl)                          ; + the lines before its first
    inc hl
    add a,a
    ld e,a
    ld d,hi(bush_ltab)                  ; DE = its first line's entry
    ld a,(to_left)
    add a,(hl)                          ; + where its first line's run ends
    ex de,hl
    add a,(hl)
    inc l
    ld h,(hl)
    ld l,a
    jr nc,$+3
    inc h
tp_buf
    res 7,h                             ; (self-modified: nop, nop for buffer 0)
    pop de
    ld a,c
    jp tr_go
