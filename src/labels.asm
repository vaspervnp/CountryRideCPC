;; ===========================================================================
;; labels.asm - the HUD's words (TIME, SPEED, TOTAL TIME, CHECKPOINT), drawn
;; once from masks (SOUND.BIN: a record in buffer 1's road lines, which the
;; first picture draws over).
;;
;; A word is the small font's letters (scene.small_text): the pen where its
;; mask is set, the shadow a pixel right and a line down from it, the HUD's
;; ground elsewhere - 8 lines, a pixel wider than the mask, made even. Kept
;; as masks (gen/labels.asm) they take a quarter of their bytes; draw_static
;; (init.asm) has them drawn into each buffer's HUD, and nothing needs them
;; after.
;; ===========================================================================

LBL_AT      EQU BOT1_BASE+2*#800+4*96   ; buffer 1's lines 194, 202, ... 266:
LBL_ROOM    EQU 10*96                   ; not drawn till the first picture
LBL_ROWS    EQU 7                       ; a mask's rows

    REC_BEGIN LBL_AT

;; lbl_draw - (draw_static) the words into the selected buffer's HUD.
;; Destroys everything.
lbl_draw
    ld ix,lbl_masks
ld_word
    ld a,(ix+0)                         ; its x (#FF: no more)
    inc a
    ret z
    ld de,lbl_out
    xor a
ld_line                                 ; A = the line, DE = its bytes
    ld (ld_n+1),a
    push de
    ld hl,lbl_pix                       ; its pixels' bits (a left pixel's):
    ld b,LBL_PIXELS                     ; the ground,
ld_clear
    ld (hl),LBL_GROUND
    inc hl
    djnz ld_clear
    ld c,LBL_SHADOW                     ; the shadow: the row above, a pixel
    ld hl,lbl_pix+1                     ; right,
    dec a
    call ld_row
    ld a,(ld_n+1)                       ; the pen: its own row
    ld c,LBL_PEN
    ld hl,lbl_pix
    call ld_row
    pop de
    ld hl,lbl_pix                       ; two pixels a byte: a right one's
    call ld_width                       ; bits are a left one's a bit on
ld_pack
    ld c,(hl)
    inc hl
    ld a,(hl)
    inc hl
    rrca
    or c
    ld (de),a
    inc de
    djnz ld_pack
ld_n
    ld a,0                              ; (self-modified: the line)
    inc a
    cp 8
    jr nz,ld_line
    ld hl,lbl_out                       ; into the HUD
    call ld_width
    ld d,b
    ld e,8
    ld b,(ix+0)
    ld c,(ix+1)
    call blit
    ld ix,(ld_next)                     ; the next word: past its last row
    jr ld_word

;; B = the word's bytes: its mask's width, and its shadow's pixel, made even
ld_width
    ld a,(ix+2)
    add a,2
    rra
    ld b,a
    ret

;; ld_row - A = a row of the word's mask (none but 0..LBL_ROWS-1), HL =
;; where its first pixel goes, C = the bits its set ones get. ld_next: the
;; row's end.
ld_row
    cp LBL_ROWS
    ret nc
    push hl
    push ix
    pop hl
    ld de,4
    add hl,de
    ld e,(ix+3)                         ; (its bytes a row)
    inc a
ld_row_at
    dec a
    jr z,ld_row_go
    add hl,de
    jr ld_row_at
ld_row_go
    ex de,hl                            ; DE = its bytes
    pop hl
    ld b,(ix+2)                         ; B = its pixels
ld_byte
    ld a,(de)
    inc de
    scf                                 ; (a 1 after its 8 bits: A 0 once
    adc a,a                             ; they are out)
ld_bit
    jr nc,ld_bit_0
    ld (hl),c
ld_bit_0
    inc hl
    dec b
    jr z,ld_row_end
    add a,a
    jr nz,ld_bit
    jr ld_byte
ld_row_end
    ld (ld_next),de
    ret
ld_next     defw 0

    INCLUDE "gen/labels.asm"
lbl_rec_end
    REC_END LBL_AT,LBL_ROOM

lbl_pix     EQU lbl_rec_end             ; (after the record, in its room)
lbl_out     EQU lbl_pix+LBL_PIXELS
    ASSERT lbl_out+8*LBL_OUT_W <= LBL_AT+LBL_ROOM
