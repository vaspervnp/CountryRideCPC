;; ===========================================================================
;; horizon.asm - where the horizon is (bank 7).
;;
;; The sky and the mountains go down the screen as far as the road's top
;; does, so the band of ground between them stays the same, and turn
;; sideways as the road bends. Moving them is the interrupt handler's job
;; (raster ruptures and the sky ring, see hw.asm); the game only says where,
;; with each picture it asks to be shown.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; picture_drop - A = the drop for the picture drawn with (hill): the lines
;; at the top of the road that no row reaches.
;; ---------------------------------------------------------------------------
picture_drop
    ld a,(hill)
    add a,128
    srl a                       ; the hill level, as road_project has it
    ld l,a
    ld h,0
    ld de,hz_ground
    add hl,de
    ld a,(hl)
    ret

;; ---------------------------------------------------------------------------
;; picture_heading - A = where the sky looks for the picture, in words to
;; the right (0..PANO_WORDS-1): it turns as the road bends (demo_step).
;; ---------------------------------------------------------------------------
picture_heading
    ld a,(heading)
    ret

;; one row of a column: HL = its character's line 0, DE = #800, the eight
;; lines' bytes from SP; HL is left on the next row's character. Lines go
;; left to right and right to left in turn, so L only steps once a line.
MACRO RING_ROW
    REPEAT 4
    pop bc
    ld (hl),c
    inc l
    ld (hl),b
    add hl,de
    pop bc
    ld (hl),b
    dec l
    ld (hl),c
    add hl,de
    REND
    ld a,l                      ; a row (96 bytes) on, eight lines back, and
    add a,96                    ; round the 2K ring
    ld l,a
    ld a,h
    adc a,-#40
    and hi(RING_BASE)+7
    ld h,a
MEND
    ASSERT (RING_BASE & #7FF) == 0

;; ---------------------------------------------------------------------------
;; ring_turn - turn the sky ring a word towards flip_head. Called by the
;; interrupt handler at a flip, which is always made while the game waits
;; for it in RAM_C1, so this bank is mapped; done before the sky part is on
;; screen (~1.4 ms from line ~274), so nothing is ever seen half done. May
;; use AF, BC and HL only.
;;
;; The sky part shows ring characters ring_w0 .. ring_w0 + 527, 48 a row.
;; Moving the start one on turns every row one word right: the character
;; after each row's last becomes its last - it was the first of the row
;; below, which now starts after it - and is given the row's next column of
;; the panorama. Moving it back is the same on the left.
;; ---------------------------------------------------------------------------
ring_turn
    ld a,(flip_head)
    ld hl,ring_head
    sub (hl)
    ret z
    push de
    push ix
    SET_RAM RAM_C3              ; the ring at #4000
    call ring_step
    SET_RAM RAM_C1
    pop ix
    pop de
    ret

;; A = (aim - head), HL = ring_head
ring_step
    jr nc,ring_step_pos
    add a,PANO_WORDS            ; (aim - head) mod PANO_WORDS
ring_step_pos
    cp PANO_WORDS/2
    jr nc,ring_left

    ld a,(hl)                   ; right: one word more, the new column at
    inc a                       ; the right edge
    cp PANO_WORDS
    jr c,ring_right_head
    xor a
ring_right_head
    ld (hl),a
    add a,SCR_BYTES/2-1
    cp PANO_WORDS
    jr c,ring_right_col
    sub PANO_WORDS
ring_right_col
    ld (rc_col),a
    ld hl,(ring_w0)
    inc hl
    ld a,h
    and hi(RING_WORDS-1)
    ld h,a
    ld (ring_w0),hl
    ld bc,SCR_BYTES/2-1
    add hl,bc
    jr ring_col

ring_left
    ld a,(hl)                   ; left: one word less, the new column at
    or a                        ; the left edge
    jr nz,ring_left_head
    ld a,PANO_WORDS
ring_left_head
    dec a
    ld (hl),a
    ld (rc_col),a
    ld hl,(ring_w0)
    dec hl
    ld a,h
    and hi(RING_WORDS-1)
    ld h,a
    ld (ring_w0),hl

;; HL = ring character of the column in the sky part's first row: write
;; panorama column rc_col down all its rows, and the row after them green -
;; some CRTCs show that row in the sky part's R5 lines (hw.asm), and it is
;; the column's next character either way the ring turns. Reads the bytes
;; with POP, so interrupts must be off (they are in the interrupt handler).
;; Destroys AF, BC, DE, HL, IXL.
ring_col
    ld (ring_col_sp+1),sp
    ld a,h
    and hi(RING_WORDS-1)
    ld h,a
    add hl,hl                   ; the character's line 0
    ld a,h
    or hi(RING_BASE)
    ld h,a
    ld de,#800
    ld sp,sky_pairs             ; the plain sky rows: a dither pair a line
    ld ixl,(PANO_Y0-SKY_Y)/8
    ASSERT PANO_Y0 > SKY_Y && (PANO_Y0-SKY_Y)%8 == 0
ring_col_sky
    RING_ROW
    dec ixl
    jr nz,ring_col_sky
    ex de,hl                    ; the mountain rows: the panorama's column
    ld a,(rc_col)
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl                   ; * 64
    ASSERT PANO_COL_BYTES == 64
    ld bc,panorama_cols
    add hl,bc
    ld sp,hl
    ex de,hl
    ld de,#800
    ld ixl,(BLOCK_BOTTOM-PANO_Y0)/8
ring_col_pano
    RING_ROW
    dec ixl
    jr nz,ring_col_pano
    ld sp,green_pairs           ; the row after: the ground's green
    RING_ROW
ring_col_sp
    ld sp,0                     ; (self-modified)
    ret

rc_col      defb 0              ; panorama column being written

;; eight lines of the ground's green, for ring_col
green_pairs
    REPEAT 8
    defw SOLID_GROUND*#101
    REND

;; ---------------------------------------------------------------------------
;; hill_near - NZ if the track has a hill under the camera or in the next
;; HILL_AHEAD entries (32 depth units each); hill_near_b - in the next
;; B - 1. Destroys AF, B, DE, HL.
;; ---------------------------------------------------------------------------
hill_near
    ld b,HILL_AHEAD+1
hill_near_b
    ld hl,(zcam)
    add hl,hl
    add hl,hl
    add hl,hl                   ; H = zcam / 32
hill_near_one
    ld e,h
    ld d,0
    push hl
    ld hl,hill_profile
    add hl,de
    ld a,(hl)
    pop hl
    or a
    ret nz
    inc h
    djnz hill_near_one
    xor a                       ; (Z: none)
    ret
