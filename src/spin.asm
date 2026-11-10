;; ===========================================================================
;; COUNTRY RIDE - Amstrad CPC 6128
;;
;; spin.asm - the four cars turning round on the select screen while the
;; player picks one (SPIN.BIN, at SPIN_CODE; tools/mkspin.py makes what they
;; play, README.md: The cars turning):
;;
;;   CALL SPIN_CODE    each car's view 0 over its side picture, and they
;;                     turn: a view every 15 degrees, a turn in 3 seconds
;;   CALL SPIN_CODE+3  they stop (before the game's files are loaded over them)
;;
;; For the loader's menu, the firmware on. The turning is done from the
;; interrupt itself, before the firmware's handler: the 6128 firmware's entry
;; in RAM (FW_INT, where #0038 jumps from RAM and from the ROM alike) jumps
;; here first, until SPIN_OFF puts its bytes back. (The firmware's events come
;; too late for it whenever BASIC keeps it busy - the flashing inks, the
;; keyboard - and #0038 alone is passed by while the lower ROM is in.)
;;
;; The interrupt in the VSYNC (the PPI's bit) counts the frames, and a view is
;; played in two halves timed to the beam from the VSYNC's end (line 248 of
;; the frame, the screen's 200 lines at 0-199), the interrupts off
;; throughout: the top cars from 8.9 ms on (the beam past the top panels'
;; area, lines 31-66: 8.4 ms) - done long before the beam is back at them;
;; then, from the next VSYNC's end, the bottom cars at once - done before the
;; beam is at their area (line 110: 11.1 ms) - and a wait, so that it all ends
;; at the same time: the interrupts held off are taken late, and the gate
;; array's next ones must fall where the next VSYNC's still comes (none in
;; the 32 lines before it). All four show in the same frame, and no car is
;; ever seen half drawn.
;;
;; A stream is what a view changes on the screen. Its tokens are where to
;; jump in the player's page of code (IX):
;;   n bytes as they are     into a chain of LDI, n from its end
;;   n times the byte in A   into a chain of LD (DE),A : INC E
;;   the byte for A          LD A,(HL)
;;   an address              DE
;;   the end                 RET
;; The streams are in banks 4-7 and base memory at #4000 (gen/spin.asm says
;; where), each switched in at #4000 while it plays; base memory after it.
;; ===========================================================================

FW_INT      EQU #B941                   ; the 6128 firmware's interrupt entry:
                                        ; DI, EX AF,AF', JR C,+#33 ...

    jp turn_on                          ; (SPIN_CODE)
    jp turn_off                         ; (SPIN_CODE+3)

    INCLUDE "gen/spin.asm"

MACRO TN_NEXT                           ; the next token: where to jump
    ld c,(hl)
    inc hl
    defb #DD,#69                        ; ld ixl,c
    jp (ix)
MEND

turn_on
    ld a,(tn_on)
    or a
    ret nz
    xor a                               ; view 0 of each car, over its picture
    ld (tn_view),a
    call tn_top
    call tn_bottom
    ld a,1
    ld (tn_view),a
    ld a,5
    ld (tn_wait),a
    di                                  ; the firmware's interrupt entry through
    ld hl,FW_INT                        ; here (the 6128's: else no turning)
    ld de,tn_fw
    ld bc,3
    ldir
    ld hl,(tn_fw)
    ld de,#08F3                         ; (DI, EX AF,AF')
    or a
    sbc hl,de
    jr nz,tn_on_done
    ld a,(tn_fw+2)
    cp #38                              ; (JR C)
    jr nz,tn_on_done
    ld a,#C3
    ld (FW_INT),a
    ld hl,tn_int
    ld (FW_INT+1),hl
    ld a,1
    ld (tn_on),a
tn_on_done
    ei
    ret

turn_off
    ld a,(tn_on)
    or a
    ret z
    di
    ld hl,tn_fw
    ld de,FW_INT
    ld bc,3
    ldir
    ei
    xor a
    ld (tn_on),a
    ret

;; the interrupt, 300 times a second
tn_int
    push af
    push bc
    ld b,#F5                            ; in the VSYNC?
    in a,(c)
    rra
    jr nc,tn_fw_int
    ld a,(tn_wait)                      ; a view due at the next frame?
    dec a
    ld (tn_wait),a
    jr nz,tn_fw_int
    push de
    push hl
    push ix
tn_vend
    in a,(c)                            ; the VSYNC's end: the beam's time from here
    rra
    jr c,tn_vend
    ld bc,TN_TOP_WAIT                   ; past the top panels,
tn_wait_top
    dec bc                              ; (7 microseconds a turn)
    ld a,b
    or c
    jr nz,tn_wait_top
    call tn_top                         ; their cars
    ld b,#F5
tn_vnext
    in a,(c)                            ; the next frame's VSYNC
    rra
    jr nc,tn_vnext
tn_vend2
    in a,(c)                            ; its end
    rra
    jr c,tn_vend2
    call tn_bottom                      ; the bottom cars
    ld a,(tn_view)                      ; then a wait, to end at the same time
    add a,a                             ; whatever they took
    ld l,a
    ld h,0
    ld de,tn_pad
    add hl,de
    ld c,(hl)
    inc hl
    ld b,(hl)
tn_wait_end
    dec bc
    ld a,b
    or c
    jr nz,tn_wait_end
    ld a,(tn_view)                      ; every fourth view a frame more (24
    and 3                               ; views in 150 frames: the next one's
    ld a,5                              ; top cars in 6 or 7 frames)
    jr nz,tn_period
    inc a
tn_period
    ld (tn_wait),a
    ld a,(tn_view)                      ; the next view
    inc a
    cp TN_VIEWS+1
    jr c,tn_next_view
    ld a,1
tn_next_view
    ld (tn_view),a
    pop ix
    pop hl
    pop de
tn_fw_int
    pop bc
    pop af
    di                                  ; what the firmware's first bytes did
    ex af,af'
    jp c,FW_INT+4+#33                   ; (its JR C, from #B943)
    jp FW_INT+4

;; the top cars' streams for the current view entry, or the bottom cars'
tn_top
    xor a
    call tn_play
    ld a,1
    jr tn_play
tn_bottom
    ld a,2
    call tn_play
    ld a,3
    ;; fall through

;; A = the car: its stream for the current view entry played
tn_play
    add a,a
    ld l,a
    ld h,0
    ld de,tn_cars
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)                           ; its table
    ld a,(tn_view)
    ld l,a
    ld h,0
    ld b,h
    ld c,l
    add hl,hl
    add hl,bc
    add hl,de
    ld a,(hl)                           ; its stream's area at #4000
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld bc,#7F00
    out (c),a
    ex de,hl
    ld ix,tn_tokens
    call tn_go
    ld bc,#7FC0                         ; base memory again
    out (c),c
    ret
tn_go
    TN_NEXT

tn_on       defb 0
tn_view     defb 0                      ; the entry next played (1 to TN_VIEWS)
tn_wait     defb 0                      ; frames till the next view's top cars
tn_fw       defs 3                      ; the firmware's entry's first bytes

;; the player's page: a token is where to jump in it
    ALIGN 256
tn_tokens
    REPEAT TN_TOK_L                     ; n bytes as they are: n LDI from the end
    ldi
    REND
    TN_NEXT
tn_k_run
    REPEAT TN_TOK_R                     ; n times A
    ld (de),a
    inc e
    REND
    TN_NEXT
tn_k_loada
    ld a,(hl)                           ; the byte for A
    inc hl
    TN_NEXT
tn_k_set
    ld e,(hl)                           ; the next span's address
    inc hl
    ld d,(hl)
    inc hl
    TN_NEXT
tn_k_end
    ret
    ASSERT tn_k_run-tn_tokens == TN_T_RUN0
    ASSERT tn_k_loada-tn_tokens == TN_T_LOADA
    ASSERT tn_k_set-tn_tokens == TN_T_SET
    ASSERT tn_k_end-tn_tokens == TN_T_END
