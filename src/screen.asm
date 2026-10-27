;; ===========================================================================
;; screen.asm - drawing into one of the two screens (bank 7).
;;
;; With RAM_C1 both HUDs are in page 1 at #4000 (buffer 1's HUD1_OFF on) and
;; the road parts at #8000 and #0000, so select_buf only notes the buffer and
;; line_addr does the rest. The sky ring is page 3, drawn once (draw_ring).
;; ===========================================================================

tgt_buf     defb 0              ; buffer being drawn into

;; ---------------------------------------------------------------------------
;; select_buf - A = buffer (0/1). Destroys AF, BC.
;; ---------------------------------------------------------------------------
select_buf
    ld (tgt_buf),a
    SET_RAM RAM_C1
    ret

;; ---------------------------------------------------------------------------
;; line_addr - HL = line (0..63, 160..271) -> HL = its address in the target
;; buffer. Destroys AF, DE.
;; ---------------------------------------------------------------------------
line_addr
    add hl,hl
    ld de,line_tab
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld a,(tgt_buf)
    or a
    ret z
    bit 7,h
    jr z,line_addr_hud
    res 7,h                     ; buffer 1's road part is #8000 lower,
    ret
line_addr_hud
    ld de,HUD1_OFF              ; its HUD HUD1_OFF on
    add hl,de
    ret

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

;; ---------------------------------------------------------------------------
;; blit - copy a block into the HUD (lines 0..63).
;;   HL = source, B = x (bytes), C = y, D = width (1..BLIT_MAX), E = height
;; The line address is worked out once and then stepped: the next line is
;; #800 on, within a character row; a row's lines are done in one run, then
;; the address goes #4000 back and one row (96 bytes) on. A line is a run
;; of LDIs, entered as far in as the width says.
;; Destroys everything but IX.
;; ---------------------------------------------------------------------------
BLIT_MAX    EQU 32

blit
    ld a,BLIT_MAX
    sub d
    add a,a                     ; two bytes an LDI
    ld (blit_jr+1),a
    ld a,c
    and 7
    sub 8
    neg
    ld iyl,a                    ; lines to the end of the first row
    ld iyh,e                    ; lines to go
    push hl
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
    ld d,a                      ; DE = destination
    pop hl
blit_row
    ld a,iyh
    cp iyl
    jr nc,blit_run
    ld iyl,a                    ; the block ends in this row
blit_run
    ld a,iyh
    sub iyl
    ld iyh,a                    ; lines left after this row
blit_line
    push de
blit_jr
    jr blit_ldi                 ; (self-modified: past BLIT_MAX - width LDIs)
blit_ldi
    REPEAT BLIT_MAX
    ldi
    REND
    pop de
    ld a,d
    add a,8
    ld d,a
    dec iyl
    jr nz,blit_line
    ld a,iyh
    or a
    ret z
    ld a,d                      ; the next row: 8 lines on is #4000 on
    sub #40
    ld d,a
    ld a,e
    add a,96
    ld e,a
    jr nc,blit_next_row
    inc d
blit_next_row
    ld iyl,8
    jr blit_row

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
;; draw_static - everything of the selected buffer that never changes: the
;; HUD ground and its labels, the ground at the top of the road part.
;; ---------------------------------------------------------------------------
draw_static
    ; the HUD, on the top colour of the sky
    ld hl,0
    ld b,HUD_H
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

    ; the labels
    ld ix,lbl_time
    ld bc,TIME_LBL_X*256+TIME_LBL_Y
    call draw_label
    ld ix,lbl_speed
    ld bc,SPEED_LBL_X*256+SPEED_LBL_Y
    call draw_label
    ld ix,lbl_total
    ld bc,TOTAL_LBL_X*256+TOTAL_LBL_Y
    call draw_label
    ld ix,lbl_fuel
    ld bc,FUEL_LBL_X*256+FUEL_LBL_Y
    call draw_label
    ld ix,lbl_apos
    ld bc,(TOTAL_VAL_X+TOTAL_APOS_X)*256+TOTAL_VAL_Y
    call draw_label
    ld ix,lbl_quote
    ld bc,(TOTAL_VAL_X+TOTAL_QUOTE_X)*256+TOTAL_VAL_Y
    jp draw_label

;; ---------------------------------------------------------------------------
;; draw_ring - the sky ring, shared by both buffers, looking straight on:
;; the sky part's rows at the start of page 3, a column at a time.
;; ---------------------------------------------------------------------------
draw_ring
    xor a
    ld (ring_head),a
    ld hl,0
    ld (ring_w0),hl
    ld c,0
draw_ring_col
    push bc
    ld a,c
    ld (rc_col),a
    ld l,c
    ld h,0
    di                          ; ring_col reads with POP
    SET_RAM RAM_C3
    call ring_col
    SET_RAM RAM_C1
    ei
    pop bc
    inc c
    ld a,c
    cp SCR_BYTES/2
    jr c,draw_ring_col
    ret


