;; ===========================================================================
;; brake.asm - the player's car's brake lights (bank 4, RAM_C4: called
;; through car_brake_go, in the hidden lines: tools/mkbush.py). The car is
;; drawn with its red lights unlit, dark (scene.py unlit); braking, each
;; side's is lit: a box three bytes wide round it filled with brake_ink -
;; the car's file has the boxes, brake_tab (tools/mkbush.py brake_table,
;; scene.brake_rects).
;; ---------------------------------------------------------------------------
;; car_brake - (car_brake_go: braking, not in a bump or a crash) H =
;; car_vfull: the view's two boxes into the buffer (road_buf), the car in the
;; middle - not up in the air (car_up) or spun. tools/run.py tells from
;; brake_on, coll_t, car_up and car_vfull whether it drew them. Destroys
;; everything but IX.
;; ---------------------------------------------------------------------------
car_brake
    ld a,(car_up)
    or a
    ret nz
    ld a,h
    cp SPIN_VIEW
    ret nc
    ld c,a
    add a,a
    add a,c
    add a,a                             ; the view's two boxes, 3 bytes each
    add a,lo(brake_tab)
    ld l,a
    adc a,hi(brake_tab)
    sub l
    ld h,a
    ld a,(road_buf)
    or a
    ld a,#FF
    jr z,$+4
    ld a,#7F                            ; (buffer 1: #8000 lower)
    ld (cbr_buf+1),a
    ld a,(brake_ink)
    ld c,a
    call cbr_box                        ; the left one, then the right
cbr_box
    ld e,(hl)
    inc hl
    ld a,(hl)
cbr_buf
    and #FF                             ; (self-modified: the buffer's)
    ld d,a                              ; DE = its first byte
    inc hl
    ld b,(hl)                           ; B = its lines
    inc hl
    ex de,hl
cbr_line
    ld (hl),c
    inc l
    ld (hl),c
    inc l
    ld (hl),c
    dec l
    dec l
    ld a,h                              ; the next line: on in the character
    add a,8                             ; row, or the next row's first
    ld h,a
    and #38
    jr z,cbr_row
cbr_on
    djnz cbr_line
    ex de,hl
    ret
cbr_row
    ld a,h
    sub #40
    ld h,a
    ld a,l
    add a,96
    ld l,a
    jr nc,cbr_on
    inc h
    jr cbr_on
    ASSERT SCR_BYTES == 96
