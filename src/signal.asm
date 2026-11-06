;; ===========================================================================
;; signal.asm - the player's car's indicators (bank 6, RAM_C6: called through
;; car_blink_go). Moving over to another lane, it blinks the one on that
;; side as the traffic does (traffic.asm to_blink): one pixel in yellow over
;; its lights (car_blinks: tools/mkbush.py, scene.car_blinker), lit every
;; other TR_BLINK pictures.
;; ===========================================================================

CAR_SIGNAL_T EQU 12                     ; pictures it blinks after it last
                                        ; moved that way (~0.5 s)

;; ---------------------------------------------------------------------------
;; car_blink - (draw_picture, after car_draw) A = coll_t, E = car_x, D =
;; car_off, L = car_view, H = car_vfull, IXL = car_id (bank 7's). Steered
;; left or right (car_view 1, 2) and its place on the road (car_x) a pair
;; or more that way from the last picture's, the car blinks on that side
;; till CAR_SIGNAL_T pictures after: its indicator's pixel into the buffer
;; (road_buf) when lit - not in a bump or a crash (coll_t), up in the air
;; (car_up) or spun. tools/run.py tells from cb_t, cb_side, frames_drawn,
;; car_up and car_vfull whether it drew it. Destroys everything.
;; ---------------------------------------------------------------------------
car_blink
    or a
    ld a,e
cb_last
    ld b,0                              ; (self-modified: the last picture's)
    ld (cb_last+1),a
    jr nz,cb_off                        ; (a bump or a crash)
    sub b
    ld b,a                              ; B = its move, pairs (left +)
    ld a,l
    ld c,0                              ; C = the side: 0 left, 2 right
    dec a
    jr z,cb_way
    dec a
    jr nz,cb_t
    ld c,2
    xor a
    sub b
    ld b,a                              ; (right: its move that way)
cb_way
    dec b
    jp m,cb_t                           ; not that way
    ld a,c
    ld (cb_side+1),a
    ld a,CAR_SIGNAL_T+1
    ld (cb_t+1),a
cb_t
    ld a,0                              ; (self-modified: pictures left)
    or a
    ret z
    dec a
    ld (cb_t+1),a
    ret z
    ld a,(frames_drawn)                 ; lit this picture?
    and TR_BLINK
    ret z
    ld a,(car_up)
    or a
    ret nz
    ld a,h
    cp SPIN_VIEW
    ret nc
    ld c,a
    ld a,ixl
    ld b,a
    add a,a
    add a,a
    add a,a
    add a,b
    add a,c                             ; car_id x 9 + the view
    add a,a
    add a,a
cb_side
    add a,0                             ; (self-modified: the side)
    ld c,d                              ; C = car_off
    add a,lo(car_blinks)
    ld l,a
    adc a,hi(car_blinks)
    sub l
    ld h,a
    ld e,(hl)
    inc hl
    ld d,(hl)                           ; DE = its byte in buffer 0, + #4000
    ld a,c                              ; for a right pixel
    add a,a
    ld l,a
    add a,a
    sbc a,a
    ld h,a
    add hl,de                           ; + car_off pairs
    ld a,(road_buf)
    or a
    jr z,$+4
    res 7,h                             ; (buffer 1: #8000 lower)
    bit 6,h
    res 6,h
    ld a,(hl)
    jr nz,cb_right
    and #55
    or TR_LIT_L
    jr cb_put
cb_right
    and #AA
    or TR_LIT_R
cb_put
    ld (hl),a
    ret
cb_off
    xor a
    ld (cb_t+1),a
    ret
    ASSERT 4*(4*9-1)+2 < 256            ; (car_id x 9 + the view, x 4: a byte)
