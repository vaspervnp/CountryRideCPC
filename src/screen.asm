;; ===========================================================================
;; screen.asm - drawing into one of the two screens (bank 7).
;;
;; select_buf picks the buffer being drawn: it maps that buffer's top half
;; at #4080 (RAM_C1 or RAM_C3), so line_tab works for both; the bottom halves
;; differ by #8000, which line_addr takes care of.
;; ===========================================================================

tgt_buf     defb 0              ; buffer being drawn into
tgt_ram     defb RAM_C1         ; its RAM configuration

;; ---------------------------------------------------------------------------
;; select_buf - A = buffer (0/1). Destroys AF, BC.
;; ---------------------------------------------------------------------------
select_buf
    ld (tgt_buf),a
    or a
    ld a,RAM_C1
    jr z,select_buf_set
    ld a,RAM_C3
select_buf_set
    ld (tgt_ram),a
    ld b,GA_PORT
    out (c),a
    ret

;; ---------------------------------------------------------------------------
;; line_addr - HL = line (0..271) -> HL = its address in the target buffer.
;; Destroys AF, DE.
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
    res 7,h                     ; buffer 1's bottom half is #8000 lower;
    ret                         ; top-half addresses have bit 7 clear anyway

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
;; blit - copy a block into the top half of the screen (lines 0..159).
;;   HL = source, B = x (bytes), C = y, D = width, E = height
;; The line address is worked out once and then stepped: the next line is
;; #800 on, except at the end of a character row, where it is #3800 back and
;; one row (96 bytes) on.
;; Destroys everything but IX.
;; ---------------------------------------------------------------------------
blit
    ld a,d
    ld (blit_w+1),a
    ld a,e
    ld iyh,a                    ; lines to go
    ld a,c
    and 7
    ld iyl,a                    ; raster line within the character row
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
blit_line
    push de
blit_w
    ld bc,0                     ; width (self-modified)
    ldir
    pop de
    inc iyl
    ld a,iyl
    and 7
    jr z,blit_row
    ld a,d
    add a,8
    ld d,a
    dec iyh
    jr nz,blit_line
    ret
blit_row
    ld iyl,a
    ld a,d
    sub #38
    ld d,a
    ld a,e
    add a,96
    ld e,a
    jr nc,blit_next
    inc d
blit_next
    dec iyh
    jr nz,blit_line
    ret

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
;; draw_static - everything that never changes: the HUD ground and its
;; labels, the sky, the mountains, the ground below them. Draws into the
;; selected buffer.
;; ---------------------------------------------------------------------------
draw_static
    ; the HUD: the top of the sky, in one colour
    ld hl,0
    ld b,HUD_H
    ld de,SOLID_NAVY*#101
    call fill_lines

    ; the sky: each line one dithered pair of bytes repeated
    ld ix,sky_pairs
    ld hl,HUD_H
    ld b,MOUNT_TOP-HUD_H
draw_static_sky
    push bc
    push hl
    ld e,(ix+0)
    ld d,(ix+1)
    ld b,1
    call fill_lines
    pop hl
    inc hl
    inc ix
    inc ix
    pop bc
    djnz draw_static_sky

    ; the mountains, a line at a time
    ld hl,MOUNT_TOP
    ld (ds_line),hl
    ld hl,mountains
    ld (ds_src),hl
    ld b,BLOCK_BOTTOM-MOUNT_TOP
draw_static_mount
    push bc
    ld hl,(ds_line)
    call line_addr
    ex de,hl
    ld hl,(ds_src)
    ld bc,SCR_BYTES
    ldir
    ld (ds_src),hl
    ld hl,(ds_line)
    inc hl
    ld (ds_line),hl
    pop bc
    djnz draw_static_mount

    ; the ground between the mountains and the road (the road's own ground
    ; lines go on from it when a crest hides the far road)
    ld hl,BLOCK_BOTTOM
    ld b,ROAD_Y-BLOCK_BOTTOM
    ld de,SOLID_GROUND*#101
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

ds_line     defw 0
ds_src      defw 0

