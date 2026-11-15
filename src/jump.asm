;; ===========================================================================
;; jump.asm - a crash at speed flips the car over, Out Run's way (RACE.BIN,
;; as the race's extras: line 174 of buffer 1, hw.asm JUMP_P0, and the
;; free ends of sndgame.asm's pieces).
;;
;; A bush hit (or a car's) at 3/4 of the car's top speed or faster: the
;; car turned side-on by the blow and thrown up, tumbling over three times
;; in three hops, each lower and slower, and down on its wheels side-on a
;; while, then turned back - flip_tab (CARn.BIN: tools/scene.py flip_seq)
;; a picture at a time, its view (car_vfull: ROLL_VIEW's frames, each
;; standing on the line the car's wheels do) and its rows up - a character
;; row (8 lines) at a time, as its views' code is made for the lines of its
;; rows: car_draw starts it car_up rows higher (car_raise). Never higher than
;; the road's top in the picture (car_jump): on a crest the ground behind it
;; is not drawn again. In each buffer the car's lines where it was drawn
;; last - up to ROLL_ABOVE over its top line, where a frame reaches - are
;; drawn whole, so nothing of it stays behind (car_lines), a far line's too
;; (jump_frame); where it is now the road is right as road_project has it,
;; and the car is drawn over it. (Since 2026-11-15; a barrel roll seen from
;; behind, thrown up and down once, before.)
;; ===========================================================================

JUMP_SPEED  EQU SPEED_MAX*3/4   ; a crash this fast or faster: thrown up (the
                                ; first car's: car_setup puts each car's in
                                ; jump_min, 3/4 of its top speed)

;; ---------------------------------------------------------------------------
    REC_BEGIN JUMP_P0

;; car_jump - (car_lines) the flip a picture on (flip_tab): car_vfull its
;; view, car_up its rows up, no higher than the road's top; this buffer's
;; lines of the car then whole. Keeps C; NZ: flipping (car_lines has no
;; more to do).
car_jump
    ld hl,jump_t
    ld a,(hl)
    ld de,(drawn_up)
    or e
    or d
    ret z                               ; (no flip, in both buffers)
    push bc
    ld a,(hl)
    or a
    jr z,cj_up                          ; (A = 0: over)
    inc (hl)
    add a,lo(flip_tab-1)
    ld e,a
    adc a,hi(flip_tab-1)
    sub e
    ld d,a
    ld a,(de)
    inc a
    jr nz,cj_air
    ld (hl),a                           ; (#FF: the end)
    jr cj_up
cj_air
    dec a
    call cj_view                        ; (A = its rows up)
    ld (car_up),a
    or #80                              ; (a frame of the flip)
    jr cj_was
cj_up
    ld (car_up),a
cj_was                                  ; A = this picture's: its rows up,
    ld b,a                              ; #80 on flipping - this buffer's
    ld hl,drawn_up                      ; lines of it then, whole
    call buf_entry                      ; (A lost)
    ld c,(hl)
    ld (hl),b
    ld a,b
    or c
    jr z,cj_done
    ld a,c
    and 7
    call cj_mark
cj_done
    ld a,(jump_t)
    or a
    pop bc
    ret

    REC_END JUMP_P0,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_TAIL jump_m2,rec_SND_M2_end

;; cj_mark - A = rows up: the car's lines there whole, ROLL_ABOVE more over
;; it (their line list entries' flags off; the grass's middle line's,
;; rp_grass, in rd_mid_t)
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
    ld b,CAR_TOP+ROLL_ABOVE             ; (up to where rolling over reaches)
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

;; jump_start - (coll_start) a crash: DE its kind and its pictures
;; (coll_t) - at jump_min or faster (3/4 of the car's top speed), the car
;; flips over (FLIP_T pictures, then back to the middle). Keeps BC.
jump_start
    ld hl,(speed)
jump_min
    ld de,-JUMP_SPEED                   ; (car_setup: the car's)
    add hl,de
    ld de,256+CRASH_T+BACK_T
    ret nc
    ld e,FLIP_T+BACK_T
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

;; cj_view - (car_jump) A = flip_tab's byte: car_vfull its view; A its rows
;; up, but the road's top no lower (on a crest the ground behind it is not
;; drawn again). Destroys DE, HL, C.
cj_view
    ld c,a
    and 31
    ld (car_vfull),a
    ld a,c
    rlca
    rlca
    rlca
    and 7
    ld c,a                              ; C = its rows up
    ld a,(hill)
    add a,128
    srl a
    ld l,a
    ld h,0
    ld de,hz_ground
    add hl,de
    ld a,CAR_Y-ROLL_ABOVE-ROAD_Y
    sub (hl)
    jr nc,$+3
    xor a
    rrca
    rrca
    rrca
    and 31
    cp c
    ret c
    ld a,c
    ret

jump_t      defb 0                      ; the flip's picture + 1 (0: none)
car_up      defb 0                      ; the car's rows up this picture
drawn_up    defb 0,0                    ; ... as each buffer last showed it,
                                        ; #80 on for a frame of the flip
    ASSERT CAR_Y-ROLL_ABOVE-ROAD_Y >= 8*FLIP_ROWS   ; (on the level, the
                                        ; highest under the road's top)
    ASSERT FLIP_T+BACK_T < 256 && CRASH_T+BACK_T < 256

    REC_TAIL_END jump_p10,rec_SND_P10_end,SND_P10+SND_PIECE
