;; ===========================================================================
;; hud.asm - the changing parts of the HUD (bank 7).
;;
;; The HUD shows a copy of the game's values that hud_snapshot takes every
;; HUD_EVERY pictures, so it changes 6.25 times a second while the road moves
;; at 25: both buffers catch up with one copy before the next is taken, and
;; the two pictures in between have nothing to draw.
;;
;; Each buffer remembers what it shows, and hud_update redraws only what
;; differs from the copy - into the buffer being drawn, which then becomes
;; the one on screen. Everything sits on the HUD's own ground colour, so it
;; is plain copying, never masking.
;; ===========================================================================

;; --- the values the game sets ------------------------------------------------
time_left   defb 60             ; seconds, two big digits
gear        defb 0              ; 0 = N, 1..6
speed_level defb 0              ; gauge segments lit, 0..GAUGE_SEGS
fuel_level  defb GAUGE_SEGS
total_time  defb 0,0,0,0,0      ; m, s tens, s units, cs tens, cs units
HUD_VALS_LEN EQU $-time_left

;; --- the copy the HUD shows, in the same order --------------------------------
HUD_EVERY   EQU 4               ; pictures between copies
hud_vals
hv_time     defb 0
hv_gear     defb 0
hv_speed    defb 0
hv_fuel     defb 0
hv_total    defb 0,0,0,0,0
    ASSERT $-hud_vals == HUD_VALS_LEN

;; hud_snapshot - take the copy; neither buffer shows it yet
hud_snapshot
    ld hl,time_left
    ld de,hud_vals
    ld bc,HUD_VALS_LEN
    ldir
    xor a
    ld (hud_done),a
    ld (hud_done+1),a
    ret

;; --- what each buffer shows (#FF = unknown, draw it) ------------------------
shown_time  defb #FF,#FF        ; units
shown_time_hi defb #FF,#FF      ; tens
shown_gear  defb #FF,#FF
shown_speed defb #FF,#FF        ; segments lit
shown_fuel  defb #FF,#FF
shown_total defb #FF,#FF,#FF,#FF,#FF
            defb #FF,#FF,#FF,#FF,#FF
hud_done    defb 0,0            ; non-zero: the buffer shows the copy

;; hud_forget - make the next update of both buffers redraw everything
hud_forget
    ld hl,shown_time
    ld de,shown_time+1
    ld (hl),#FF
    ld bc,shown_total+9-shown_time
    ldir
    xor a
    ld (hud_done),a
    ld (hud_done+1),a
    ret

;; HL = per-buffer pair -> HL = this buffer's entry
buf_entry
    ld a,(tgt_buf)
    add a,l
    ld l,a
    ret nc
    inc h
    ret

;; ---------------------------------------------------------------------------
;; hud_update - bring the selected buffer's HUD up to date, as far as a
;; picture's share of time allows.
;;
;; The share is HUD_SHARE units, about 1.1 ms: a small digit or a gauge
;; segment costs one, a big digit two. The total time's changed digits come
;; first, then at most one of the rest - the TIME digits, the gear, a segment
;; of either gauge. Anything left waits for the next picture of this buffer,
;; 80 ms away; each buffer has two pictures to show a copy before the next.
;; ---------------------------------------------------------------------------
HUD_SHARE   EQU 3
hud_budget  defb 0

hud_update
    ld hl,hud_done
    call buf_entry
    ld a,(hl)
    or a
    ret nz                      ; nothing new since it was brought up to date
    ld a,HUD_SHARE
    ld (hud_budget),a
    call hud_total
    ret c                       ; out of time already

    ; --- time: two big digits, each redrawn only when it changes ---
    ld a,(hv_time)
    ld c,0                      ; tens
hud_time_div
    sub 10
    jr c,hud_time_split
    inc c
    jr hud_time_div
hud_time_split
    add a,10
    ld e,a                      ; units
    ld hl,shown_time
    call buf_entry
    ld a,e
    cp (hl)
    jr z,hud_time_hi
    call hud_big_ok
    ret c
    ld a,e
    ld (hl),a
    ld b,TIME_VAL_X+BIG_W
    ld c,TIME_VAL_Y
    jp draw_big
hud_time_hi
    ld hl,shown_time_hi
    call buf_entry
    ld a,c
    cp (hl)
    jr z,hud_gear
    call hud_big_ok
    ret c
    ld a,c
    ld (hl),a
    ld b,TIME_VAL_X
    ld c,TIME_VAL_Y
    jp draw_big

    ; --- gear: N or 1-6 ---
hud_gear
    ld hl,shown_gear
    call buf_entry
    ld a,(hv_gear)
    cp (hl)
    jr z,hud_speed
    call hud_big_ok
    ret c
    ld a,(hv_gear)
    ld (hl),a
    or a
    jr nz,hud_gear_digit
    ld a,10                     ; glyph 10 is N
hud_gear_digit
    ld b,GEAR_X
    ld c,GEAR_Y
    jp draw_big

    ; --- speed gauge: green to red ---
hud_speed
    ld hl,shown_speed
    call buf_entry
    ld a,(hv_speed)
    cp (hl)
    jr z,hud_fuel
    ld a,(hud_budget)
    or a
    ret z
    ld a,(hv_speed)
    ld de,speed_seg
    ld b,SPEED_GAUGE_X
    ld c,SPEED_GAUGE_Y
    jp gauge_update

    ; --- fuel gauge: red to green ---
hud_fuel
    ld hl,shown_fuel
    call buf_entry
    ld a,(hv_fuel)
    cp (hl)
    jr z,hud_up_to_date
    ld a,(hud_budget)
    or a
    ret z
    ld a,(hv_fuel)
    ld de,fuel_seg
    ld b,FUEL_GAUGE_X
    ld c,FUEL_GAUGE_Y
    jp gauge_update

hud_up_to_date
    ld hl,hud_done
    call buf_entry
    ld (hl),1
    ret

;; Carry set if the budget left is less than a big digit's two units
hud_big_ok
    ld a,(hud_budget)
    cp 2
    ret

;; --- total time: five small digits, the changed ones, the hundredths
;; first. Carry set if the budget ran out before they were all drawn. ---
hud_total
    ld hl,shown_total+4
    ld a,(tgt_buf)
    or a
    jr z,hud_total_buf
    ld hl,shown_total+9
hud_total_buf
    ld de,hv_total+4
    ld ix,total_digit_x+4
    ld b,5
hud_total_loop
    ld a,(de)
    cp (hl)
    jr z,hud_total_next
    ld a,(hud_budget)
    sub 1
    ret c
    ld (hud_budget),a
    ld a,(de)
    ld (hl),a
    push bc
    push de
    push hl
    ld a,(ix+0)
    add a,TOTAL_VAL_X
    ld b,a
    ld c,TOTAL_VAL_Y
    ld a,(de)
    call draw_small
    pop hl
    pop de
    pop bc
hud_total_next
    dec de
    dec hl
    dec ix
    djnz hud_total_loop
    ret                         ; (carry clear: cp/sub left none)

;; ---------------------------------------------------------------------------
;; draw_big - glyph A (0-9, 10 = N) at B = x bytes, C = y.
;; ---------------------------------------------------------------------------
draw_big
    ld l,a                      ; 72 bytes a glyph
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl                   ; *8
    ld d,h
    ld e,l
    add hl,hl
    add hl,hl
    add hl,hl                   ; *64
    add hl,de                   ; *72
    ld de,big_glyphs
    add hl,de
    ld d,BIG_W
    ld e,BIG_H
    jp blit

;; ---------------------------------------------------------------------------
;; draw_small - digit A at B = x bytes, C = y.
;; ---------------------------------------------------------------------------
draw_small
    ld l,a                      ; 24 bytes a digit
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl                   ; *8
    ld d,h
    ld e,l
    add hl,hl                   ; *16
    add hl,de                   ; *24
    ld de,small_digits
    add hl,de
    ld d,SMALL_W
    ld e,SMALL_H
    jp blit

;; ---------------------------------------------------------------------------
;; gauge_update - move a gauge one segment towards its value (all of it if
;; this buffer has never shown it).
;;   A = segments lit now, HL = this buffer's "shown" byte,
;;   DE = segment colour table, B = x, C = y
;; ---------------------------------------------------------------------------
gauge_update
    ld (gu_seg),de
    ld (gu_xy),bc
    ld e,(hl)                   ; segments shown
    ld d,a                      ; segments wanted
    ld a,e
    cp #FF
    jr nz,gauge_known
    ld (hl),d
    ld e,0                      ; unknown: draw all of it
    ld b,GAUGE_SEGS
gauge_range                     ; segments e .. b-1, lit if index < d
    ld a,e
    cp b
    ret nc
    push bc
    push de
    call gauge_seg
    pop de
    pop bc
    inc e
    jr gauge_range
gauge_known
    ld a,d
    cp e
    ret z
    jr c,gauge_down
    inc (hl)                    ; light segment e
    ld d,e
    inc d
    jr gauge_seg
gauge_down
    dec (hl)                    ; darken segment e-1
    dec e
    ld d,e
    jr gauge_seg

;; E = segment, D = segments lit
gauge_seg
    ld a,e
    cp d
    ld hl,gauge_off
    jr nc,gauge_seg_pen
    ld hl,(gu_seg)
    ld a,e
    add a,a
    add a,l
    ld l,a
    jr nc,gauge_seg_pen
    inc h
gauge_seg_pen
    ld c,(hl)
    inc hl
    ld b,(hl)                   ; C, B = the segment's two bytes
    ld (gs_bytes),bc
    ld bc,(gu_xy)
    ld a,e
    add a,a                     ; two bytes a segment
    add a,b
    ld b,a
    ld hl,gs_block
    ld de,(gs_bytes)
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    REPEAT GAUGE_H-1
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    REND
    ld hl,gs_block
    ld d,2
    ld e,GAUGE_H
    jp blit

gauge_off   defb SEG_OFF0,SEG_OFF1
gu_seg      defw 0
gu_xy       defw 0
gs_bytes    defw 0
gs_block    defs 2*GAUGE_H,0
