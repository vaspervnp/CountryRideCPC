;; ===========================================================================
;; screen.asm - drawing into one of the two screens (bank 7).
;;
;; With RAM_C1 both HUDs are in page 1 at #4000 (buffer 1's HUD1_OFF on) and
;; the road parts at #8000 and #0000, so select_buf only notes the buffer and
;; line_addr does the rest. The sky ring is page 3, drawn once (draw_ring).
;; ===========================================================================

tgt_buf     defb 0              ; buffer being drawn into
blit_odd    defb 0              ; (blit_twice: the line's second time)

;; ---------------------------------------------------------------------------
;; select_buf - A = buffer (0/1). Destroys AF, BC.
;; ---------------------------------------------------------------------------
select_buf
    ld (tgt_buf),a
    SET_RAM RAM_C1
    ret

;; ---------------------------------------------------------------------------
;; line_addr - HL = line (0..63, 160..271) -> HL = its address in the target
;; buffer: with RAM_C1, buffer 0's HUD at HUD_BASE (lines 0-63), its road
;; part's memory at BOT0_BASE (from ROAD_AREA_Y on); a character row 96
;; bytes, its lines #800 apart. Destroys AF, DE.
;; ---------------------------------------------------------------------------
line_addr
    ld a,l
    and 7
    add a,a
    add a,a
    add a,a
    ld d,a                      ; D: its line in the row, #800s
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l                        ; L = its character row
    ld a,l
    sub ROAD_ROW
    jr c,line_addr_top
    ld l,a
    ld a,hi(BOT0_BASE)-hi(HUD_BASE)
    add a,d
    ld d,a
line_addr_top
    ld a,l
    add a,a
    add a,l
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl                   ; 96 a row
    ld a,h
    add a,d
    add a,hi(HUD_BASE)
    ld h,a
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
    ASSERT ROAD_AREA_Y % 8 == 0 && ((HUD_BASE|BOT0_BASE) & #FF) == 0

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
blit_twice
    jr blit_down                ; (self-modified: 0 - draw_big's, each line
    ld a,(blit_odd)             ; twice: the first time back over it)
    xor 1
    ld (blit_odd),a
    jr z,blit_down
    ld bc,-BIG_W
    add hl,bc
blit_down
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
