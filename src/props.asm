;; ===========================================================================
;; props.asm - the props beside the road: palms, dead trees, speed limit and
;; curve signs (bank 7, RAM_C1).
;;
;; A course's props are a list (tools/course.py lays them out, mkbush.py
;; puts them in page 1: props_demo, props_race, props_none): per prop its
;; depth from the one before (the first: from the course's first entry), in
;; 16 units, then its byte - its kind (bits 0-3, course.PROP_KINDS), its
;; lateral class (bits 4-6, a bush's) and side (bit 7: the left); at the end
;; the depth to the course's end and #FF (round again, as the course goes)
;; or 0,#FE (no more). course_set gives the list, which starts where the
;; course's first entry does (prop_start).
;;
;; One prop is in sight at a time: the nearest that has not gone by
;; (prp_code; the one after it is read too, prp_ncode), from PROP_ZVIS ahead
;; until it is less than BUSH_ZNEAR ahead. bush_one stands it as it does a
;; bush - from bush_sinfo's records PROP_REC0 on, its kind's sprites, one a
;; size (prop_take), on the rows prop_spr gives each - and prop_draw draws
;; it from its sprite's lines, before the bushes: those few nearer stand in
;; front of it. Its drawing takes the time of bushes: while it is in sight,
;; fewer of them are in reach (bush_join: prop_room).
;;
;; A sprite (mkbush.py prop_sprite): the byte its centre is on, its width,
;; its column's lines (the trunk or the post: its last lines, alike, one run
;; of a byte or two), its height; the column's run - a byte (its first
;; byte from the sprite's left | its bytes << 4), then its bytes; then the
;; lines above the column as groups of the same line: its lines, then the
;; line's runs, each a byte (its bytes from the end of the run before, or
;; from the left | its bytes << 4 | #80 on the line's last) and its bytes.
;; ===========================================================================

PR_CL       EQU 2                       ; a prop's record: its column's lines
                                        ; (SI_R0's place: bush.asm)
prop_spr    EQU HILL_RING+64            ; per row, the record of the size the
    ASSERT lo(prop_spr) == #80          ; props take on it (#FF: none;
                                        ; prop_init)

prp_list    defw props_demo             ; the list's start (round again)
prp_ptr     defw props_demo             ; the next prop in it
prp_pend    defw props_demo             ; the list course_set gave, until its
                                        ; course starts (high byte 0: none)
prp_base    defw 0                      ; the depth the next one is from
prp_z       defw 0                      ; the nearest prop's depth,
prp_code    defb #FE                    ; ... its byte (#FE: none)
prp_nz      defw 0                      ; the one after it
prp_ncode   defb #FE
prp_tab     defw prop_spr,bush_latR0    ; as bush_tab has a bush: the nearest's
                                        ; size table, its lateral class's
                                        ; offsets (prop_take)
prp_room    defb 0                      ; the nearest's room (prop_rooms)
prp_nroom   defb 0                      ; ... and the next's

;; ---------------------------------------------------------------------------
;; prop_init - prop_spr from prop_rows (each size's first row). Destroys AF,
;; C, DE, HL.
;; ---------------------------------------------------------------------------
prop_init
    ld hl,prop_spr
    ld de,prop_rows
    ld c,#FF                            ; the size's record (none yet)
pi_row
    ld a,e
    cp lo(prop_rows+PROP_SIZES)
    jr z,pi_put                         ; the biggest from its row on
    ld a,(de)
    xor l
    and #7F                             ; (L: #80 + the row)
    jr nz,pi_put
    inc de                              ; the next size from this row on
    ld a,c
    add a,16
    jr nc,pi_rec
    ld a,PROP_REC0*16                   ; (the first)
pi_rec
    ld c,a
pi_put
    ld (hl),c
    inc l
    jr nz,pi_row
    ret

;; ---------------------------------------------------------------------------
;; prop_start - (course_entry, as a course's first segment is read) the list
;; course_set gave, from the entry being worked out on (crs_z): the next
;; prop is its first. Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
prop_start
    ld hl,(prp_pend)
    ld a,h
    or a
    ret z                               ; (the course round again)
    ld (prp_list),hl
    ld (prp_ptr),hl
    xor a
    ld (prp_pend+1),a
    ld hl,(crs_z)
    ld (prp_base),hl
    ; (fall into prop_next)

;; prop_next - the prop after the nearest, from the list: prp_nz, prp_ncode,
;; prp_nroom (#FE: none). Destroys AF, BC, DE, HL.
prop_next
    ld hl,(prp_ptr)
pn_read
    ld a,(hl)                           ; its depth from the last, 16 units
    inc hl
    ld c,(hl)                           ; its byte
    inc hl
    ex de,hl
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld a,c
    cp #FE
    jr z,pn_none                        ; (no more: the list stays at its end)
    ld bc,(prp_base)
    add hl,bc
    ld (prp_base),hl
    cp #FF
    jr z,pn_round
    ld (prp_nz),hl
    ld (prp_ncode),a
    ld (prp_ptr),de
    and #0F
    add a,lo(prop_rooms)
    ld l,a
    adc a,hi(prop_rooms)
    sub l
    ld h,a
    ld a,(hl)
    ld (prp_nroom),a
    ret
pn_round
    ld hl,(prp_list)                    ; round again
    jr pn_read
pn_none
    ld (prp_ncode),a
    ret

;; ---------------------------------------------------------------------------
;; prop_reach - (bush_draw) the nearest prop: the next when it has gone by.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
prop_reach
    ld a,(prp_code)
    cp #FE
    jr nz,prr_ahead
    ld a,(prp_ncode)                    ; none: the next, if there is one
    cp #FE
    ret z
    jr prr_on
prr_ahead
    ld hl,(prp_z)
    ld de,(zcam)
    or a
    sbc hl,de
    ld a,h
    or a
    jr nz,prr_far
    ld a,l
    cp BUSH_ZNEAR
    ret nc                              ; still ahead
prr_on
    ld hl,(prp_nz)                      ; the next is the nearest now
    ld (prp_z),hl
    ld a,(prp_nroom)
    ld (prp_room),a
    ld a,(prp_ncode)
    ld (prp_code),a
    call prop_take
    jp prop_next
prr_far
    rla
    ret nc                              ; further than 255
    jr prr_on                           ; behind

;; prop_take - A = the nearest prop's byte: its kind's sprites into
;; bush_sinfo's records from PROP_REC0 on, its side's offsets for its
;; lateral class into prp_tab. Destroys AF, BC, DE, HL.
prop_take
    cp #FE
    ret z
    ld c,a
    and #70                             ; prop_lats + 4 x its class (+ 2: on
    rrca                                ; the left)
    rrca
    bit 7,c
    jr z,$+4
    add a,2
    add a,lo(prop_lats)
    ld l,a
    adc a,hi(prop_lats)
    sub l
    ld h,a
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld (prp_tab+2),hl
    ld a,c                              ; prop_dir + 16 x its kind
    and #0F
    rlca
    rlca
    rlca
    rlca
    ld hl,prop_dir
    add a,l
    ld l,a
    jr nc,$+3
    inc h
    ld de,bush_sinfo+PROP_REC0*16
    ld b,PROP_SIZES
pt_size
    push bc
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    push hl
    ld h,b
    ld l,c                              ; its centre's byte, width, column's
    ldi                                 ; lines, height: SI_HW, SI_W, PR_CL,
    ldi                                 ; SI_H
    ldi
    ldi
    ex de,hl
    ld bc,SI_DATA-4
    add hl,bc
    ld (hl),e                           ; its lines
    inc hl
    ld (hl),d
    inc hl
    ld (hl),1                           ; SI_HIT: its trunk's (a byte)
    ld c,16-SI_HIT
    add hl,bc
    ex de,hl
    pop hl
    pop bc
    djnz pt_size
    ret
    ASSERT SI_HW == 0 && SI_W == 1 && PR_CL == 2 && SI_H == 3
    ASSERT SI_HIT == SI_DATA+2


;; ---------------------------------------------------------------------------
;; prop_room - (bush_join) HL = how far ahead a bush that has come into
;; reach is, B = the bushes in reach: NZ if it may not join - a prop is in
;; sight while it is in reach (the prop's depth ahead less than the bush's
;; + PROP_ZVIS - BUSH_ZNEAR) and as many bushes as that prop's kind allows
;; are in reach already. Destroys AF, C, DE, HL.
;; ---------------------------------------------------------------------------
prop_room
    ld de,PROP_ZVIS-BUSH_ZNEAR
    add hl,de
    ex de,hl                            ; DE: nearer, in sight while it is
    ld a,(prp_room)
    ld c,a
    ld a,(prp_code)
    ld hl,(prp_z)
    call pr_one
    ret nz
    ld a,(prp_nroom)
    ld c,a
    ld a,(prp_ncode)
    ld hl,(prp_nz)
pr_one                                  ; A = a prop's byte, HL = its depth,
    cp #FE                              ; C = its room
    jr z,pr_free
    push de
    ld de,(zcam)
    or a
    sbc hl,de                           ; how far ahead it is
    pop de
    or a
    sbc hl,de
    jr nc,pr_free                       ; gone by before it comes into sight
    ld a,b
    cp c
    jr c,pr_free
    or 1                                ; no room
    ret
pr_free
    xor a
    ret

;; ---------------------------------------------------------------------------
;; prop_one - (bush_draw, before the bushes) the nearest prop, if it is in
;; sight: stood as a bush is (bush_one, from prp_tab) and drawn (prop_draw) -
;; but not if the picture is late already (PROP_LATE interrupts since the
;; flip: as the traffic's far car - or one fewer, if it is nearer than
;; PROP_BIG_Z: a big one, up to ~4 ms), prp_late then not 0. Destroys
;; everything.
;; ---------------------------------------------------------------------------
PROP_LATE   EQU 10
PROP_BIG_Z  EQU 168
prp_late    defb 0                      ; (tools/run.py: not drawn)

prop_one
    xor a
    ld (prp_late),a
    ld a,(prp_code)
    cp #FE
    ret z
    ld hl,(prp_z)
    ld de,(zcam)
    or a
    sbc hl,de                           ; how far ahead (BUSH_ZNEAR on:
    ld de,PROP_ZVIS                     ; prop_reach)
    or a
    sbc hl,de
    ret nc                              ; not in sight yet
    add hl,de
    ld a,(irq_n)
    cp PROP_LATE
    jr nc,po_late
    cp PROP_LATE-1
    jr c,po_draw
    ld a,h                              ; (big)
    or a
    jr nz,po_draw
    ld a,l
    cp PROP_BIG_Z
    jr nc,po_draw
po_late
    ld (prp_late),a                     ; (A: not 0)
    ret
po_draw
    ex de,hl
    ld hl,prop_draw
    ld (b1_way+1),hl
    ld hl,prp_tab
    call bush_one
    ld hl,b1_bush
    ld (b1_way+1),hl
    ret

prp_hleft   defb 0                      ; prop_draw: the lines above the
                                        ; column still to draw
prp_cl      defb 0                      ; ... the column's

;; ---------------------------------------------------------------------------
;; prop_draw - (bush_one's way for a prop) its sprite into the selected
;; buffer, and its boxes noted for bush_erase: the lines above its column,
;; as wide as it is, and the column's, a pair from its run's first byte.
;; C = its top line (signed, from ROAD_AREA_Y), D = its left (signed), IX =
;; its sprite's record, IYH = #80 on the inside of a curve. If a side of the
;; screen cuts it, its runs are cut to fit (the slower way). Destroys
;; everything.
;; ---------------------------------------------------------------------------
prop_draw
    ld a,c
    sub PROP_TOP
    ret m                               ; (never: mkbush.py)
    call pd_near                        ; (propdraw.asm)
    ld a,d
    ld (pdc_x+1),a
    ld a,(ix+PR_CL)
    ld (prp_cl),a
    ld l,(ix+SI_DATA)
    ld h,(ix+SI_DATA+1)
    ld (pd_col+1),hl                    ; its column's run ...
    ld a,(hl)
    ld e,a
    rlca
    rlca
    rlca
    rlca
    and 7
    inc a
    add a,l
    ld l,a
    jr nc,$+3
    inc h
    ld (pd_heads+1),hl                  ; ... and past it, its lines above
    ld a,e                              ; the column's box: its lines, below
    and #0F                             ; those, a pair from its run's
    add a,d                             ; first byte
    push bc
    push de
    ld d,a
    ld e,2
    ld a,(ix+SI_H)
    sub (ix+PR_CL)
    ld (prp_hleft),a
    add a,c
    ld c,a
    ld b,(ix+PR_CL)
    call pd_box
    pop de
    pop bc
    ld a,(prp_hleft)                    ; the lines above its column: as wide
    or a                                ; as it is
    jr z,pd_top
    ld b,a
    ld e,(ix+SI_W)
    push bc
    push de
    call pd_box
    pop de
    pop bc
pd_top
    ld a,c                              ; IY = its top line's start + its left
    add a,a                             ; (which may be off the screen)
    ld l,a
    ld h,hi(bush_ltab)
    ld a,(hl)
    inc l
    ld h,(hl)
pd_buf
    res 7,h                             ; (self-modified: nop, nop for buffer 0)
    ld l,a
    ld a,d
    ld e,a
    add a,a
    sbc a,a
    ld d,a
    add hl,de
    push hl
    pop iy
    ld b,0                              ; (LDIR's: BC = a run's bytes)
pd_heads
    ld hl,0                             ; (self-modified: its lines above the
    ld a,(prp_hleft)                    ; column)
    or a
    jp z,pd_column
    ld a,e                              ; all of it on the screen: no cutting
    or a
    jp m,pdc_group
    add a,(ix+SI_W)
    cp SCR_BYTES+1
    jp nc,pdc_group

;; the lines above the column, a group at a time, each line's runs copied
pdf_group
    ld a,(prp_hleft)
    sub (hl)
    ld (prp_hleft),a
    ld a,(hl)                           ; its lines
    inc hl
    ld ixh,a
    ld (pdf_runs+1),hl
pdf_line
pdf_runs
    ld hl,0                             ; (self-modified: the group's runs)
    ld e,iyl
    ld d,iyh
pdf_run
    ld a,(hl)
    inc hl
    ld c,a
    or a
    ex af,af'                           ; (S: the line's last)
    ld a,c
    and #0F
    add a,e
    ld e,a
    jr nc,$+3
    inc d
    ld a,c
    rlca
    rlca
    rlca
    rlca
    and 7
    ld c,a
    ldir
    ex af,af'
    jp p,pdf_run
    ld a,iyh                            ; the next line
    add a,8
    ld iyh,a
    and #40
    call nz,pd_wrap
    dec ixh
    jr nz,pdf_line
    ld a,(prp_hleft)
    or a
    jr nz,pdf_group
    jp pd_column
