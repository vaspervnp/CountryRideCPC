;; ===========================================================================
;; propdraw.asm - prop_draw's lines cut to fit the screen, its column, its
;; erase records (props.asm; here in fragment 0, which has the room: RAM_C1
;; as there).
;; ===========================================================================

;; pd_near - (prop_draw) a small prop (a far one) on a straight with the road
;; well off the middle: its boxes may lie on the far road (the road's far
;; rows hardly move with road_x, its rows do) - on the inside, then, so the
;; road is put back where they were (as a bush's: bd_note). C = its top
;; line, IX = its sprite's record, IYH = #80 on the inside. Destroys AF.
PROP_NEAR   EQU 5                       ; sizes from here on: never on the road
PROP_OFF    EQU 12                      ; ... nor smaller ones while |road_x| is
                                        ; less than this (tools/mkbush.py)
pd_near
    ld a,iyh
    or a
    ret nz                              ; (on the inside already)
    ld a,ixl
    cp (PROP_REC0+PROP_NEAR)*16
    ret nc
    ld a,(road_curve)
    or a
    ret nz
    ld a,(road_x)
    add a,PROP_OFF-1
    cp 2*PROP_OFF-1
    ret c
    ld iyh,#80
    push hl
    call bd_note
    pop hl
    ret

;; the same, each run cut to fit the screen
pdc_group
    ld a,(prp_hleft)
    sub (hl)
    ld (prp_hleft),a
    ld a,(hl)
    inc hl
    ld ixh,a
    ld (pdc_runs+1),hl
pdc_line
pdc_runs
    ld hl,0                             ; (self-modified: the group's runs)
    ld e,iyl
    ld d,iyh
pdc_x
    ld a,0                              ; (self-modified: its left)
    ld ixl,a                            ; IXL = DE's x on the screen
pdc_run
    ld a,(hl)
    inc hl
    ld c,a
    or a
    ex af,af'                           ; (S: the line's last)
    ld a,c
    and #0F
    ld b,a
    add a,ixl
    ld ixl,a                            ; the run's x
    ld a,e
    add a,b
    ld e,a
    jr nc,$+3
    inc d                               ; DE = its address
    ld a,c
    rlca
    rlca
    rlca
    rlca
    and 7
    ld c,a
    ld b,0                              ; BC = its bytes
    ld a,ixl
    or a
    jp m,pdc_lcut                       ; starts left of the screen
    add a,c
    ld ixl,a                            ; (the x past it)
    cp SCR_BYTES+1
    jr nc,pdc_rcut                      ; ends right of it
    ldir
pdc_next
    ex af,af'
    jp p,pdc_run
    ld a,iyh                            ; the next line
    add a,8
    ld iyh,a
    and #40
    call nz,pd_wrap
    dec ixh
    jr nz,pdc_line
    ld a,(prp_hleft)
    or a
    jr nz,pdc_group
    jp pd_column
pdc_lcut                                ; A = its x, left of the screen
    add a,c
    ld ixl,a                            ; (the x past it)
    jr z,pdc_skip
    jp m,pdc_skip                       ; all of it
    ld b,a                              ; B = its bytes on the screen
    ld a,c
    sub b                               ; past those off it
    add a,l
    ld l,a
    jr nc,$+3
    inc h
    ld a,c
    sub b
    add a,e
    ld e,a
    jr nc,$+3
    inc d
    ld c,b
    ld b,0
    ldir
    jr pdc_next
pdc_rcut                                ; A = the x past it, beyond the screen
    sub SCR_BYTES
    ld b,a                              ; B = its bytes off the screen
    ld a,c
    sub b
    jr c,pdc_skip
    jr z,pdc_skip                       ; (all of it)
    ld c,a
    ld a,b
    ld b,0
    ldir
    add a,l                             ; past those off it (no more of the
    ld l,a                              ; line is on the screen: DE as it is)
    jr nc,pdc_next
    inc h
    jr pdc_next
pdc_skip                                ; none of it on the screen: past it
    ld a,c
    ld b,0
    add a,l
    ld l,a
    jr nc,$+3
    inc h
    ld a,c
    add a,e
    ld e,a
    jr nc,pdc_next
    inc d
    jr pdc_next

;; the column: its run's byte or two on each of its lines (IY at the first),
;; cut to fit the screen
pd_column
pd_col
    ld hl,0                             ; (self-modified: its run)
    ld a,(hl)
    inc hl
    ld c,a
    and #0F
    ld b,a
    add a,iyl
    ld e,a
    ld a,iyh
    adc a,0
    ld d,a                              ; DE = its first byte's address
    ld a,(pdc_x+1)
    add a,b                             ; ... its x
    ld b,a
    ld a,c
    and #70
    cp #20
    ld a,b
    jr z,pd_col2
    cp SCR_BYTES
    ret nc                              ; off the screen
pd_col1
    ld c,(hl)
pd_c1go
    ld a,(prp_cl)
    ld b,a
pd_c1
    ld a,c
    ld (de),a
    ld a,d
    add a,8
    ld d,a
    and #40
    jr nz,pd_c1w
pd_c1n
    djnz pd_c1
    ret
pd_c1w
    ld a,d
    sub #40
    ld d,a
    ld a,e
    add a,96
    ld e,a
    jr nc,pd_c1n
    inc d
    jr pd_c1n
pd_col2                                 ; two bytes, the first at x = A
    inc a
    jr z,pd_col2r                       ; x = -1: the right one, at 0
    cp SCR_BYTES
    jr z,pd_col1                        ; x = SCR_BYTES - 1: the left one
    ret nc                              ; off the screen
    ld c,(hl)
    inc hl
    ld b,(hl)
    ld a,(prp_cl)
    ld ixh,a
    ex de,hl
pd_c2
    ld (hl),c
    inc hl
    ld (hl),b
    dec hl
    ld a,h
    add a,8
    ld h,a
    and #40
    jr nz,pd_c2w
pd_c2n
    dec ixh
    jr nz,pd_c2
    ret
pd_c2w
    ld a,h
    sub #40
    ld h,a
    ld a,l
    add a,96
    ld l,a
    jr nc,pd_c2n
    inc h
    jr pd_c2n
pd_col2r
    inc hl
    inc de
    ld c,(hl)
    jr pd_c1go

;; IY on a character row (past the last line of one)
pd_wrap
    ld a,iyh
    sub #40
    ld iyh,a
    ld a,iyl
    add a,96
    ld iyl,a
    ret nc
    inc iyh
    ret

;; pd_box - an erase record (bush_erase) for a box of B lines from line C,
;; bytes [D, D + E) (D signed) as cut by the screen, in pairs. Destroys AF,
;; BC, DE, HL.
pd_box
    ld a,d
    or a
    jp p,$+4
    xor a
    ld l,a                              ; L = its first byte on the screen
    ld a,d
    add a,e
    ret m                               ; (all of it left of the screen)
    cp SCR_BYTES+1
    jr c,$+4
    ld a,SCR_BYTES
    sub l
    ret c
    ret z                               ; (all of it right of the screen)
    inc a
    srl a
    ld e,a                              ; E = its pairs
    add a,a
    add a,l
    cp SCR_BYTES+1
    jr c,$+4
    ld a,SCR_BYTES
    ld d,a                              ; D = its right end
    ld a,c
    add a,a
    ld l,a
    ld h,hi(bush_ltab)
    ld a,(hl)
    inc l
    ld h,(hl)
pb_buf
    res 7,h                             ; (self-modified: nop, nop for buffer 0)
    add a,d
    ld d,h
    jr nc,$+3
    inc d
    ld h,e
    ld e,a                              ; DE = its top right
    ld a,h
    ld hl,(bd_rec)
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld e,a
    ld a,b
    or iyh
    ld (hl),a                           ; its lines; inside the curve
    inc hl
    ld (hl),c                           ; its top line
    inc hl
    ld a,e                              ; how it is erased: be_ways[pairs]
    add a,a
    add a,lo(be_ways-2)
    ld e,a
    ld a,hi(be_ways-2)
    adc a,0
    ld d,a
    ld a,(de)
    ld (hl),a
    inc hl
    inc de
    ld a,(de)
    ld (hl),a
    inc hl
    ld (bd_rec),hl
    ret
