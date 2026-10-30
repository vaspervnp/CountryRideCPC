;; ===========================================================================
;; jump.asm - a crash at speed throws the car up (RACE.BIN, as the race's
;; extras: line 174 of buffer 1, hw.asm JUMP_P0, and the free ends of
;; sndgame.asm's pieces).
;;
;; A bush hit at JUMP_SPEED or faster: the car goes up and comes down as
;; jump_rows has it, spinning as the crash has it, then bounces once - a
;; character row (8 lines) at a time, as its views' code is made for the
;; lines of its rows: car_draw starts it car_up rows higher (car_raise).
;; Never higher than the road's top in the picture (car_jump): on a crest
;; the ground behind it is not drawn again. In each buffer the car's lines
;; where it was drawn last and where it is now are drawn whole, so nothing
;; of it stays behind (car_lines), a far line's too (jump_frame).
;; ===========================================================================

JUMP_SPEED  EQU SPEED_MAX*4/5   ; a crash this fast or faster: thrown up

;; ---------------------------------------------------------------------------
    REC_BEGIN JUMP_P0

;; car_jump - (car_lines) the jump a picture on: car_up the rows up, no
;; higher than the road's top; this buffer's lines of the car then and now
;; whole. Keeps C; NZ: in the air (car_lines has no more to do).
car_jump
    ld a,(jump_t)
    ld hl,(drawn_up)
    or l
    or h
    ret z                               ; (on the ground, in both buffers)
    push bc
    ld hl,jump_t
    ld a,(hl)
    or a
    jr z,cj_up                          ; (A = 0: on the ground)
    inc (hl)
    add a,lo(jump_rows-1)
    ld e,a
    adc a,hi(jump_rows-1)
    sub e
    ld d,a
    ld a,(de)
    inc a
    jr nz,cj_air
    ld (hl),a                           ; (#FF: the end)
    jr cj_up
cj_air
    dec a
    ld c,a                              ; C = its rows up
    ld a,(hill)                         ; ... but the road's top no lower
    add a,128
    srl a
    ld l,a
    ld h,0
    ld de,hz_ground
    add hl,de
    ld a,CAR_Y-ROAD_Y
    sub (hl)
    jr nc,$+3
    xor a
    rrca
    rrca
    rrca
    and 31
    cp c
    jr c,cj_up
    ld a,c
cj_up                                   ; A = its rows up: this buffer's
    ld (car_up),a                       ; lines of it then and now, whole
    ld b,a
    ld hl,drawn_up
    call buf_entry                      ; (A lost)
    ld c,(hl)
    ld (hl),b
    ld a,b
    or c
    jr z,cj_done
    ld a,c
    call cj_mark
    ld a,(car_up)
    call cj_mark
cj_done
    ld a,(car_up)
    or a
    pop bc
    ret

    REC_END JUMP_P0,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_TAIL jump_m2,rec_SND_M2_end

;; cj_mark - A = rows up: the car's lines there whole (their line list
;; entries' flags off; the grass's middle line's, rp_grass, in rd_mid_t)
cj_mark
    ld hl,rd_mid_t
    res 0,(hl)
    res 1,(hl)
    add a,a
    add a,a
    add a,a
    add a,a
    add a,a                             ; (4 bytes an entry, 8 lines a row)
    add a,4*(LAST_Y-(CAR_Y+CAR_TOP-1-ROAD_AREA_Y))
    ld e,a
    ld d,0
    ld hl,(rp_slot)
    add hl,de                           ; its last line's entry
    ld e,4
    ld b,CAR_TOP
cjm_line
    ld a,(hl)
    and #FC
    ld (hl),a
    add hl,de                           ; (the line above)
    djnz cjm_line
    ret

    REC_TAIL_END jump_m2,rec_SND_M2_end,SND_M2+SND_PIECE
;; ---------------------------------------------------------------------------
    REC_TAIL jump_m1,rec_SND_M1_end

;; jump_frame - (draw_picture) the road (road_frame); while the car is up,
;; or one buffer still has it up, every far line's road drawn (rp_dirty, as
;; traffic_pre has it for a car up there) - a far line the same as last
;; time is skipped, and car_jump's whole lines would not draw it.
jump_frame
    ld a,(jump_t)
    ld hl,(drawn_up)
    or l
    or h
    jp z,road_frame
    ld a,#80
    ld (rp_dirty),a
    jp road_frame

    REC_TAIL_END jump_m1,rec_SND_M1_end,SND_M1+SND_PIECE
;; ---------------------------------------------------------------------------
    REC_TAIL jump_m0,rec_SND_M0_end

;; jump_start - (coll_start) a crash: at JUMP_SPEED or faster, the car
;; thrown up. Keeps BC.
jump_start
    ld hl,(speed)
    ld de,-JUMP_SPEED
    add hl,de
    ret nc
    ld a,1
    ld (jump_t),a
    ret

    REC_TAIL_END jump_m0,rec_SND_M0_end,SND_M0+SND_PIECE
;; ---------------------------------------------------------------------------
    REC_TAIL jump_m3,rec_SND_M3_end

;; car_raise - (car_draw) HL = where the car's first line starts: car_up
;; rows higher. Keeps DE.
car_raise
    ld a,(car_up)
    or a
    ret z
    ld bc,-96
cr_row
    add hl,bc
    dec a
    jr nz,cr_row
    ret

    REC_TAIL_END jump_m3,rec_SND_M3_end,SND_M3+SND_PIECE
;; ---------------------------------------------------------------------------
    REC_TAIL jump_p10,rec_SND_P10_end

;; the rows up a picture, from the crash's (jump_t 1) on - up, down, a
;; bounce - and #FF, the end
jump_rows   defb 1,3,4,5,5,6,6,6,6,5,5,4,3,1,0,0,1,1,0,#FF
jump_t      defb 0                      ; the jump's picture + 1 (0: none)
car_up      defb 0                      ; the car's rows up this picture
drawn_up    defb 0,0                    ; ... as each buffer last showed it
    ASSERT CAR_Y-ROAD_Y <= 6*8

    REC_TAIL_END jump_p10,rec_SND_P10_end,SND_P10+SND_PIECE
