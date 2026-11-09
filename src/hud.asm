;; ===========================================================================
;; hud.asm - the changing parts of the HUD (bank 7).
;;
;; The HUD shows a copy of the game's values that hud_snapshot takes every
;; HUD_EVERY pictures, so it changes 6.25 times a second while the road moves
;; at 25: both buffers catch up with one copy before the next is taken, and
;; the two pictures in between have nothing to draw. Its last line is the
;; game's message (hud_msg), MSG_W small glyphs, a few at a time.
;;
;; Each buffer remembers what it shows, and hud_update redraws only what
;; differs from the copy - into the buffer being drawn, which then becomes
;; the one on screen. Everything sits on the HUD's own ground colour, so it
;; is plain copying, never masking.
;; ===========================================================================

;; --- the values the game sets ------------------------------------------------
time_left   defb START_TIME     ; seconds, two big digits
gear        defb 0              ; 0 = N, 1..6 (the start's count: 3..1)
speed_level defb 0              ; gauge segments lit, 0..GAUGE_SEGS
cp_level    defb 0              ; ... on the way to the next checkpoint
total_time  defb 0,0,0,0,0      ; m, s tens, s units, cs tens, cs units
msg         defb MSG_NONE       ; the message (gen/gfx.asm MSG_...)
HUD_VALS_LEN EQU $-time_left

;; --- the copy the HUD shows, in the same order --------------------------------
HUD_EVERY   EQU 4               ; pictures between copies
hud_vals
hv_time     defb 0
hv_gear     defb 0
hv_speed    defb 0
hv_cp       defb 0
hv_total    defb 0,0,0,0,0
hv_msg      defb 0
    ASSERT $-hud_vals == HUD_VALS_LEN

;; hud_snapshot - take the copy; neither buffer shows it yet (nor its
;; message, if that is new)
hud_snapshot
    ld a,(msg)
    ld hl,hv_msg
    cp (hl)
    jr z,hud_snapshot_vals
    xor a
    ld (msg_done),a
    ld (msg_done+1),a
hud_snapshot_vals
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
shown_cp    defb #FF,#FF
shown_total defb #FF,#FF,#FF,#FF,#FF
            defb #FF,#FF,#FF,#FF,#FF
shown_msg   defs 2*MSG_W,#FF    ; the message line's glyphs, a buffer's
                                ; after the other's
hud_done    defb 0,0            ; non-zero: the buffer shows the copy
msg_done    defb 0,0            ; ... its message

;; hud_forget - make the next update of both buffers redraw everything
hud_forget
    ld hl,shown_time
    ld de,shown_time+1
    ld (hl),#FF
    ld bc,shown_msg+2*MSG_W-1-shown_time
    ldir
    xor a
    ld (hud_done),a
    ld (hud_done+1),a
    ld (msg_done),a
    ld (msg_done+1),a
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
;; The share is hud_quota units - HUD_SHARE, about 1.1 ms, or HUD_SHARE_LOW
;; when the picture has taken long (draw_picture) - a small digit or a gauge
;; segment costs one, a big digit two. The total time's changed digits come
;; first, then at most one of the rest - the TIME digits, the gear, a segment
;; of either gauge. With the small share, every other time a gauge segment
;; goes first, so that the gauges keep up through a run of long pictures.
;; Anything left waits for the next picture of this buffer, 80 ms away; each
;; buffer has two pictures to show a copy before the next. A share of 0:
;; nothing this picture.
;; ---------------------------------------------------------------------------
HUD_SHARE   EQU 3
HUD_SHARE_LOW EQU 1
hud_quota   defb HUD_SHARE
hud_budget  defb 0
hud_turn    defb 0,0            ; (the small share's turns, per buffer)

hud_update
    ld hl,hud_done
    call buf_entry
    ld a,(hl)
    or a
    ret nz                      ; nothing new since it was brought up to date
    ld a,(hud_quota)
    or a
    ret z                       ; no share this picture
    ld (hud_budget),a
    cp HUD_SHARE
    jr nc,hud_update_total
    ld hl,hud_turn              ; the small share: a gauge's turn? (each
    call buf_entry              ; buffer its own, every other time)
    ld a,(hl)
    xor 1
    ld (hl),a
    jr z,hud_update_total
    call hud_gauge_one
    jp hud_total
hud_update_total
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
    jr z,hud_cp
    ld a,(hud_budget)
    or a
    ret z
    ld a,(hv_speed)
    ld de,speed_seg
    ld b,SPEED_GAUGE_X
    ld c,SPEED_GAUGE_Y
    jp gauge_update

    ; --- checkpoint gauge: red to green ---
hud_cp
    ld hl,shown_cp
    call buf_entry
    ld a,(hv_cp)
    cp (hl)
    jr z,hud_up_to_date
    ld a,(hud_budget)
    or a
    ret z
    ld a,(hv_cp)
    ld de,cp_seg
    ld b,CP_GAUGE_X
    ld c,CP_GAUGE_Y
    jp gauge_update

hud_up_to_date
    ld hl,hud_done
    call buf_entry
    ld (hl),1
    ret

;; a segment of the speed gauge, or else the checkpoint gauge, if one is
;; behind
hud_gauge_one
    ld hl,shown_speed
    call buf_entry
    ld a,(hv_speed)
    cp (hl)
    ld de,speed_seg
    ld bc,SPEED_GAUGE_X*256+SPEED_GAUGE_Y
    jr nz,hud_gauge_one_draw
    ld hl,shown_cp
    call buf_entry
    ld a,(hv_cp)
    cp (hl)
    ret z
    ld de,cp_seg
    ld bc,CP_GAUGE_X*256+CP_GAUGE_Y
hud_gauge_one_draw
    call gauge_update
    ld hl,hud_budget
    dec (hl)
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
;; hud_msg - the selected buffer's message line towards the copy's message
;; (hv_msg): the cells that differ from what the buffer shows, left to
;; right, MSG_CELLS of them at most (~0.2 ms each) - a message comes and
;; goes as a wipe over a few pictures.
;; ---------------------------------------------------------------------------
MSG_CELLS   EQU 4
hm_scr      defw 0              ; the first cell's first line on the screen

hud_msg
    ld hl,msg_done
    call buf_entry
    ld a,(hl)
    or a
    ret nz                      ; nothing new since it was brought up to date
    ld a,(hv_msg)               ; DE = the message's glyphs (MSG_W a message)
    ld l,a
    add a,a
    add a,a
    add a,a
    add a,a
    sub l
    ASSERT MSG_W == 15
    ld l,a
    ld h,0
    ld de,msg_texts
    add hl,de
    push hl
    ld hl,MSG_Y
    call line_addr
    ld de,MSG_X
    add hl,de
    ld (hm_scr),hl
    pop de
    ld ix,shown_msg             ; IX = what this buffer shows
    ld a,(tgt_buf)
    or a
    jr z,hud_msg_buf
    ld ix,shown_msg+MSG_W
hud_msg_buf
    ld bc,MSG_W*256+MSG_CELLS
hud_msg_loop
    ld a,(de)
    cp (ix+0)
    jr z,hud_msg_next
    dec c
    ret m                       ; this picture's share is drawn
    ld (ix+0),a
    push bc
    push de
    ld a,MSG_W                  ; DE = the cell's: hm_scr + 3 x the cell
    sub b
    ld e,a
    add a,a
    add a,e
    ld hl,(hm_scr)
    add a,l
    ld e,a
    ld d,h                      ; (no carry: see draw_cell)
    ld a,(ix+0)
    call draw_cell
    pop de
    pop bc
hud_msg_next
    inc de
    inc ix
    djnz hud_msg_loop
    ld hl,msg_done
    call buf_entry
    ld (hl),1
    ret

;; draw_small - small glyph A (0-9 the digits, then gen/gfx.asm's) at B = x
;; bytes - 64 or more - C = y.
draw_small
    ASSERT TOTAL_VAL_X >= 64
    push af
    push bc
    ld l,c
    ld h,0
    call line_addr
    pop bc
    ld a,b
    add a,l
    ld e,a
    adc a,h
    sub e
    ld d,a                      ; DE = where it goes
    pop af

;; draw_cell - (hud_msg) small glyph A at DE, its bytes in one page on each
;; line: its lines #800 apart, on to the next character row past a row's last
;; line - a line at a time from small_rows, as small_digits says. Destroys AF,
;; BC, DE, HL.
draw_cell
    add a,a
    add a,a
    add a,a
    ld c,a
    ld b,hi(small_digits)       ; BC = the glyph's lines
    ld h,hi(small_rows)
draw_cell_line
    ld a,(bc)
    ld l,a
    ld a,(hl)
    ld (de),a
    inc l
    inc e
    ld a,(hl)
    ld (de),a
    inc l
    inc e
    ld a,(hl)
    ld (de),a
    dec e                       ; (no carry: see above, and the cells end at
    dec e                       ; MSG_X + 39 in a row starting at #x40)
    inc c
    ld a,c
    and SMALL_H-1
    ret z
    ld a,d                      ; the next line
    add a,8
    ld d,a
    jp p,draw_cell_line
    sub #40                     ; the next row: 8 lines on is #4000 on
    ld d,a
    ld a,e
    add a,96
    ld e,a
    jr nc,draw_cell_line
    inc d
    jr draw_cell_line
    ASSERT SMALL_H == 8
    ASSERT MSG_Y % 8 == 0 && SMALL_W == 3

;; ---------------------------------------------------------------------------
;; draw_big - glyph A (0-9, 10 = N) at B = x bytes, C = y: its lines
;; each drawn twice (blit_twice).
;; ---------------------------------------------------------------------------
draw_big
    ld l,a                      ; 36 bytes a glyph
    ld h,0
    add hl,hl
    add hl,hl                   ; *4
    ld d,h
    ld e,l
    add hl,hl
    add hl,hl
    add hl,hl                   ; *32
    add hl,de                   ; *36
    ld de,big_glyphs
    add hl,de
    ld d,BIG_W
    ld e,BIG_H
    xor a
    ld (blit_odd),a
    ld (blit_twice+1),a         ; (each line twice)
    call blit
    ld a,blit_down-blit_twice-2
    ld (blit_twice+1),a
    ret

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
