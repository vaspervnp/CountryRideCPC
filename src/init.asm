;; ===========================================================================
;; init.asm - what runs once, as the game starts (bank 7, RAM_C1): from
;; CURVE_RING on, past the game's code - game_init runs it before the
;; track's rings and prop_spr are worked out over it.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; game_init - (game_start) the car picked, the road forgotten, the sky ring
;; and both buffers' HUDs and what never changes in them; the music's
;; volumes 0 (sndgame.asm); prop_spr last (props.asm: over this code's
;; rest).
;; ---------------------------------------------------------------------------
game_init
    call car_setup
    call road_reset
    call hud_forget
    call hud_snapshot
    call draw_ring
    xor a
    call draw_screen
    ld a,1
    call draw_screen
    xor a
    call snd_mute
    jp prop_init
gi_end
    ASSERT gi_end <= prop_spr

;; ---------------------------------------------------------------------------
;; car_setup - the car picked (car_id: CARn.BIN) as fast, as quick and as
;; steerable as it is: its car_stats put into the code that drives it -
;; speed_player's top speed, grass top speed and acceleration, the demo's
;; (it drives the same car), steer's steering and curve push factors.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
car_setup
    ld a,(car_id)
    ld l,a
    add a,a
    add a,a
    add a,l                             ; CAR_STATS_LEN bytes a car
    ld l,a
    ld h,0
    ld de,car_stats
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)                           ; DE = the top speed
    inc hl
    ld (sp_max+1),de
    ld (demo_max+1),de
    srl d
    rr e
    ld (sp_grass+1),de                  ; (on the grass: half)
    ld e,(hl)
    inc hl
    ld d,0
    ld (sp_acc+1),de
    ld (demo_acc+1),de
    ld a,(hl)
    inc hl
    ld (steer_k+1),a
    ld a,(hl)
    ld (steer_m+1),a
    ld a,(steer_k+1)                    ; (the full lock's: 127 x k / 64)
    ld h,127
    ld e,a
    call mul8
    call shr6
    ld (steer_full+1),hl
    ret
    ASSERT CAR_STATS_LEN == 5

;; ---------------------------------------------------------------------------
;; draw_screen - A = buffer: everything but the road, the whole HUD included
;; (hud_update draws a picture's share at a time, so it is called until it is
;; done).
;; ---------------------------------------------------------------------------
draw_screen
    call select_buf
    call draw_static
    ld a,HUD_SHARE
    ld (hud_quota),a
    ld b,16
draw_screen_hud
    push bc
    call hud_update
    call hud_msg
    pop bc
    djnz draw_screen_hud
    SET_RAM RAM_C1
    ret

;; ---------------------------------------------------------------------------
;; draw_static - everything of the selected buffer that never changes: the
;; HUD ground and its labels, the ground at the top of the road part.
;; ---------------------------------------------------------------------------
draw_static
    ; the HUD, on the top colour of the sky - its first seven character
    ; rows: the eighth is never shown (the CRTC's R6), and holds code
    ; (tools/mkbush.py HUD_ROW7)
    ld hl,0
    ld b,HUD_H-8
    ld de,SOLID_NAVY*#101
    call fill_lines

    ; the ground between the mountains and the road (the road's own ground
    ; lines go on from it when a crest hides the far road) - from the road
    ; part's first line shown: the lines above it hold the car's views on
    ; hills (CARn.BIN)
    ld hl,ROAD_Y&#F8                    ; (rasm divides in floating point:
    ld b,ROAD_Y&7                       ; no /8*8)
    ld de,SOLID_GROUND*#101
    call fill_lines

    ; under the road, the screen's last lines: black (the road stops at
    ; ROAD_END)
    ld hl,ROAD_END
    ld b,SCR_H-ROAD_END
    ld de,SOLID_BLACK*#101
    call fill_lines

    ; the labels: the words (labels.asm, from their masks), the marks
    call lbl_draw
    ld ix,lbl_apos
    ld bc,(TOTAL_VAL_X+TOTAL_APOS_X)*256+TOTAL_VAL_Y
    call draw_label
    ld ix,lbl_quote
    ld bc,(TOTAL_VAL_X+TOTAL_QUOTE_X)*256+TOTAL_VAL_Y
    jr draw_label

;; ---------------------------------------------------------------------------
;; draw_label - IX = label (defb width, then 8 lines), B = x, C = y.
;; ---------------------------------------------------------------------------
draw_label
    ld d,(ix+0)
    ld e,8
    push ix
    pop hl
    inc hl
    jp blit

;; ---------------------------------------------------------------------------
;; fill_lines - fill whole lines with a two-byte pattern.
;;   HL = first line, B = number of lines, DE = pattern (E left, D right)
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
fill_lines
    push bc
    push de
    push hl
    call line_addr
    pop bc                      ; line number
    pop de
    push de
    push bc
    ld b,SCR_BYTES/2
fill_lines_byte
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    djnz fill_lines_byte
    pop hl
    inc hl
    pop de
    pop bc
    djnz fill_lines
    ret
