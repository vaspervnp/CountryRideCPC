;; ===========================================================================
;; trafglue.asm - the traffic's code that runs whatever the RAM configuration
;; (fragment 3, after buffer 0's line list): into a sprite piece and back,
;; the steps between its lines, a whole car's bottom's paint. The pieces
;; (tools/mktrafcode.py) are in banks 4, 5 and 6 and the fragments.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; tr_go - (traffic_draw, RAM_C6) into a piece: IX = its code, A = its RAM
;; configuration (0: as it is), HL = where its first line's run ends, DE and
;; IY its paint. The piece ends at tr_done, which comes back in RAM_C6.
;; Destroys everything but IY.
;; ---------------------------------------------------------------------------
tr_go
    ld (tr_sp+1),sp
    or a
    jr z,tr_go_in
    ld b,#7F
    out (c),a
tr_go_in
    di
    jp (ix)
tr_done
tr_sp
    ld sp,0                     ; (self-modified)
    ld bc,#7F00+RAM_C6
    out (c),c
    ei
    ret

;; ---------------------------------------------------------------------------
;; tr_st<dx> - (a piece, SP at a line's right end) HL += #800 + dx, the next
;; line's right end - on to the next character row past the last line of
;; one; an interrupt gets its chance (its return address lands on the
;; line's second word, the call's on its first). tr_stx: BC = #800 + dx.
;; Destroys BC, F.
;; ---------------------------------------------------------------------------
tr_stm2
    ld bc,#0800-2
    jr tr_stx
tr_stm1
    ld bc,#0800-1
    jr tr_stx
tr_st1
    ld bc,#0800+1
    jr tr_stx
tr_st0
    ld bc,#0800
tr_stx
    ei
    add hl,bc
    di
    bit 6,h
    ret z
;; past a character row's last line: on to the next row. Destroys AF.
tr_next_row
    ld a,h
    sub #40
    ld h,a
    ld a,l
    add a,96
    ld l,a
    ret nc
    inc h
    ret

tr_cw2      defw 0,0            ; a further size's car: its bottom's paint
                                ; (DE, IY), from the line its top ends
