;; ===========================================================================
;; bush.asm - the bushes beside the road (bank 7, RAM_C1).
;;
;; tools/mkbush.py places the bushes along the track and makes a sprite for
;; each of BUSH_SPRITES heights; scene.py says what they look like and where
;; they go, and this has to match it.
;;
;; The grass is plain, so a bush is drawn over it as it is - a run of bytes a
;; line, a whole number of pairs, the grass between its leaves already in -
;; and taken away by pushing the grass back over the box it was drawn in. A
;; picture:
;;
;;   bush_erase  the selected buffer's bushes of last time go (before the
;;               road is drawn, which puts back any road a bush stood on)
;;   road_frame
;;   bush_draw   the prop in sight (props.asm) is drawn; the bushes that
;;               have come into reach join those in reach (bush_reach,
;;               nearest first, mkbush.py); those on the screen are drawn,
;;               each noted for the next bush_erase of this buffer
;;
;; A bush moves sideways with the road (road_x: as far as its row does,
;; cpcgfx.player_shift). One on the inside of a
;; curve may stand in front of the far road. When such a bush goes,
;; road_project must not skip a far line whose dash has not moved
;; (rp_dirty), nor a near line the bush stood on (rp_dlo, rp_dhi).
;;
;; A bush is drawn one of two ways:
;;
;;   its code   all of it on the screen: the sprite's own code (bushcode.asm,
;;              in page 1) PUSHes it, line by line from the right end of each
;;              run, each line loading the step to the next one's end.
;;   copied     cut by a side of the screen or the top of the road part:
;;              its lines are copied from its data (bushdata.asm) with LDIs,
;;              each cut to fit (bush_copy).
;;
;; While SP points into the screen interrupts are off, but each line gives
;; them one instruction's chance with SP at the right end of the run it is
;; about to push: the return address an interrupt leaves there is pushed
;; over (the interrupt handler puts nothing else on the stack it finds). A
;; sprite's code CALLs bush_next_row there too.
;; ===========================================================================

BUSH_REC    EQU 6                       ; a drawn bush's box, for bush_erase:
                                        ; its top right; its lines (bit 7: on
                                        ; the inside of a curve) and its top
                                        ; line (from ROAD_AREA_Y); how it is
                                        ; erased

;; a sprite's record: bush_sinfo + 16 * sprite (mkbush.py)
SI_HW       EQU 0                       ; half its width
SI_W        EQU 1                       ; its width (even)
SI_R0       EQU 2                       ; where its first line's run ends
SI_H        EQU 3                       ; height
SI_WAY      EQU 4                       ; how its box is erased (be_r<pairs>)
SI_CODE     EQU 6                       ; its code
SI_DATA     EQU 8                       ; its lines as data
SI_HIT      EQU 10                      ; half the width it is hit in
;; (records PROP_REC0 on are the prop in sight's sprites, props.asm)

bd_rec      defw 0                      ; where the next erase record goes
bd_ranges   defb LAST_Y,0,LAST_Y,0      ; per buffer: the first and last line
                                        ; (from ROAD_AREA_Y) its bushes on the
                                        ; inside stood on (none: LAST_Y, 0)
bd_k        defb #7F                    ; the curve level of the last picture
                                        ; (#7F: none yet)

;; (bush_recs0, bush_recs1: per buffer, where its records end (low byte),
;; then the records - in one page: src/main.asm has them at bank 7's start)

;; HL = the selected buffer's lines its bushes on the inside stood on
bd_range_ptr
    ld hl,bd_ranges
    ld a,(tgt_buf)
    or a
    ret z
    inc hl
    inc hl
    ret

;; the bush about to be drawn is on the inside (IYH): its lines, C (its top,
;; signed) on, go in the selected buffer's range
bd_note
    call bd_range_ptr
    ld a,c
    or a
    jp p,$+4
    xor a
    cp (hl)
    jr nc,$+3
    ld (hl),a
    inc hl
    ld a,c
    add a,(ix+SI_H)
    dec a
    cp (hl)
    ret c
    ld (hl),a
    ret

;; HL = the selected buffer's erase records
bush_rec_ptr
    ld hl,bush_recs0
    ld a,(tgt_buf)
    or a
    ret z
    ld hl,bush_recs1
    ret

;; ---------------------------------------------------------------------------
;; bush_erase - the grass back over the boxes the selected buffer's bushes
;; were drawn in; rp_dirty set if one of them stood on the inside of a curve,
;; and rp_dlo, rp_dhi to the lines those stood on. A box is erased a
;; character row's lines at a time (as many as are in it, up to where the
;; grass of then changes its green: be_prep), each line PUSHes from its
;; right end. Destroys everything.
;; ---------------------------------------------------------------------------
bush_erase
    call bd_range_ptr
    ld a,(hl)
    ld (rp_dlo),a
    ld (hl),LAST_Y
    inc hl
    ld a,(hl)
    ld (rp_dhi),a
    ld (hl),0
    call bush_rec_ptr
    xor a
    ld (rp_dirty),a
    ld a,(hl)                           ; where the records end
    inc hl
    cp l
    ret z                               ; none
    ld (be_end+1),a
    push hl
    call be_prep                        ; (road.asm) the grass of then
    pop hl
    ld (be_sp+1),sp
    di                                  ; (SP in the records: what an interrupt
    ld sp,hl                            ; pushes lands on one already read)
be_rec
    pop hl                              ; the box's top right
    pop bc                              ; C = lines, B = its top line
    pop iy                              ; how it is erased
    ld (be_ptr+1),sp
    ld a,c
    and #80
    jr z,be_box
    ld (rp_dirty),a                     ; it stood on the inside of a curve
    xor c
    ld c,a
be_box
    ld a,b
    ld ixl,a                            ; IXL = the line, from ROAD_AREA_Y
    call be_grass                       ; DE = its grass, IXH = where it changes
    jp be_seg                           ; (fragments 2 and 15: room)
be_boxd
be_ptr
    ld sp,0                             ; (self-modified: the next record)
    ld a,(be_ptr+1)
be_end
    cp 0                                ; (self-modified: where they end)
    jr nz,be_rec
be_sp
    ld sp,0                             ; (self-modified)
    ei
    ret

;; B lines of a box PAIRS pairs wide, from HL: #800 apart
MACRO BE_WAY pairs
@line
    ld sp,hl
    ei                                  ; (an interrupt's return address goes
    ld a,h                              ; where the first push will)
    di
    add a,8
    ld h,a
    REPEAT {pairs}
    push de
    REND
    djnz @line
    jp be_segd
MEND
be_r1   BE_WAY 1
be_r2   BE_WAY 2
be_r3   BE_WAY 3
be_r4   BE_WAY 4
be_r5   BE_WAY 5
be_r6   BE_WAY 6
be_r7   BE_WAY 7
be_r8   BE_WAY 8
    ASSERT BUSH_BOX <= 16 && PROP_BOX <= 16

;; the way for a box of 1..8 pairs
be_ways
    defw be_r1,be_r2,be_r3,be_r4,be_r5,be_r6,be_r7,be_r8

;; ---------------------------------------------------------------------------
;; bush_draw - the prop in sight, then the bushes ahead into the selected
;; buffer, nearest first (they hardly ever overlap), BUSH_MAX at most, each
;; noted for the next bush_erase of this buffer. Destroys everything.
;; ---------------------------------------------------------------------------
bush_draw
    ; the road's hill: even, no stronger a crest than BUSH_HILL_MAX; the
    ; furthest row in sight on it (if it is not the last picture's)
    ld a,(hill)
    and #FE
    cp BUSH_HILL_MAX+1
    jr c,bd_hill
    cp #80
    jr nc,bd_hill
    ld a,BUSH_HILL_MAX
bd_hill
    ld hl,b1_hill+1
    cp (hl)
    jr z,bd_hill_same
    ld (hl),a
    add a,128
    rrca
    and #7F
    or lo(bush_rtop)
    ld l,a
    ld h,hi(bush_rtop)
    ld a,(hl)
    ld (b1_top+1),a
bd_hill_same
    ; which side is the inside, where a bush may stand in front of the far
    ; road: the side the curve bends to
    ld de,0                             ; D: the left's mark, E: the right's
    ld a,(road_curve)
    call bd_side                        ; (flags: the level's)
    ld a,(hill)
    jr z,bd_side_crest
    or a                                ; a curve still on a hill (its level
    jr z,bd_side_set                    ; lags the track's): the layout does
    jr bd_side_both                     ; not keep a bush on either side off
bd_side_crest                           ; the road there; nor on a crest -
    dec a                               ; one on a row it hides is drawn
    jp m,bd_side_set                    ; where a nearer, wider row shows,
bd_side_both                            ; and can touch its kerb
    ld de,#8080
bd_side_set
    ld a,e
    ld (b1_inr+1),a
    ld a,d
    ld (b1_inl+1),a
    ; the curve: its level's centre table, mirrored for a left curve (if it
    ; is not the last picture's)
    ld a,(road_curve)
    ld hl,bd_k
    cp (hl)
    jr z,bd_curve_same
    ld (hl),a
    ld hl,0                             ; (nop, nop; add a,0)
    ld c,l
    or a
    jp p,bd_curve
    neg
    ld hl,#44ED                         ; (neg; add a,SCR_BYTES)
    ld c,SCR_BYTES
bd_curve
    ld (b1_mirror),hl
    ld hl,b1_mirror+3
    ld (hl),c
    add a,a
    ld l,a
    ld h,0
    ld de,bush_cxs
    add hl,de
    ld a,(hl)
    ld (b1_cxl+1),a
    inc hl
    ld a,(hl)
    ld (b1_cxh+1),a
bd_curve_same
    ; -zcam
    ld hl,(zcam)
    xor a
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a
    ld (bd_nz+1),hl
    ; the buffer: its lines are #8000 lower for buffer 1
    ld a,(tgt_buf)
    or a
    ld hl,0                             ; (nop, nop)
    jr z,bd_buf
    ld hl,#BCCB                         ; (res 7,h)
bd_buf
    ld (b1_buf),hl
    ld (bc_buf),hl
    ld (pd_buf),hl
    ld (pb_buf),hl
    call bush_rec_ptr                   ; no records yet
    ld (bd_head+1),hl
    inc hl
    ld (bd_rec),hl

    ; the prop in sight first (props.asm), then BUSH_MAX bushes at most
    call prop_reach
    call prop_one
bd_props_done                           ; (tools: timing)
    ld a,(bd_rec)
    add a,BUSH_MAX*BUSH_REC
    ld (bd_lim+1),a

    ; those that have come into reach join the bushes in reach (bush_reach,
    ; nearest first)
    ld hl,(bush_head)
bd_start
    ld a,(zcam)
    sub (hl)
    inc hl
    ld a,(zcam+1)
    sbc a,(hl)
    and hi(BUSH_PERIOD-1)
    cp hi(BUSH_PERIOD/2)
    jr nc,bd_started                    ; not yet
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push hl
    call bush_join
    pop hl
    ld de,bush_starts_end
    or a
    sbc hl,de
    add hl,de
    jr nz,bd_start
    ld hl,bush_starts
    jr bd_start
bd_started
    dec hl
    ld (bush_head),hl

    ; draw them, nearest first; those gone by (at the front) leave
    ld a,(bush_nreach)
    or a
    jr z,bd_done
    ld b,a
    ld c,0                              ; C = how many have gone by
    ld hl,bush_reach
bd_act
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push hl
    push bc
    ex de,hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl                              ; HL = its sprite table
    ex de,hl
bd_nz
    ld bc,0                             ; (self-modified: -zcam)
    add hl,bc
    ld a,h
    and hi(BUSH_PERIOD-1)
    ld h,a
    cp hi(BUSH_PERIOD/2)
    jr nc,bd_gone                       ; behind
    or a
    jr nz,bd_ahead
    ld a,l
    cp BUSH_ZNEAR
    jr c,bd_gone                        ; closer than BUSH_ZNEAR
bd_ahead
    ex de,hl                            ; DE = how far ahead
    call bush_one
    pop bc
    pop hl
    ld a,(bd_rec)
bd_lim
    cp 0                                ; (self-modified: BUSH_MAX drawn)
    jr z,bd_drop
    djnz bd_act
    jr bd_drop
bd_gone
    pop bc
    pop hl
    inc c
    djnz bd_act
bd_drop
    ld a,c                              ; those gone by leave
    or a
    jr z,bd_done
    ld hl,bush_nreach
    ld a,(hl)
    sub c
    ld (hl),a
    jr z,bd_done
    add a,a
    ld b,0
    ld e,c
    ld c,a                              ; BC = the bytes of those left
    ld a,e
    add a,a
    add a,lo(bush_reach)
    ld l,a
    ld h,hi(bush_reach)
    ld de,bush_reach
    ldir
bd_done
    ld a,(bd_rec)                       ; where the records end
bd_head
    ld (0),a                            ; (self-modified: the buffer's)
    ret

;; A > 0: the right is the inside (E = #80); A < 0: the left (D = #80)
bd_side
    or a
    ret z
    jp m,bd_side_l
    ld e,#80
    ret
bd_side_l
    ld d,#80
    ret

;; bush_join - DE = a bush that has come into reach: into bush_reach, after
;; those nearer - unless a prop in sight while it is leaves no room for it
;; (prop_room)
bush_join
    ld (bj_bush+1),de
    ex de,hl
    call bj_ahead
    ld (bj_its+1),hl
    ld a,(bush_nreach)
    ld b,a
    call prop_room
    ret nz                              ; (it is never in reach)
    ld hl,bush_nreach
    ld a,(hl)
    cp BUSH_RMAX
    ret nc                              ; (never: mkbush.py)
    inc (hl)
    ld a,(bush_nreach)
    add a,a
    add a,lo(bush_reach)-2
    ld l,a
    ld h,hi(bush_reach)                   ; HL = the slot after the last
bj_slot
    ld a,l
    cp lo(bush_reach)
    jr z,bj_put                         ; the first
    dec hl
    ld d,(hl)
    dec hl
    ld e,(hl)                           ; DE = the one before
    push hl
    push de
    ex de,hl
    call bj_ahead
    ex de,hl
bj_its
    ld hl,0                             ; (self-modified: how far ahead it is)
    or a
    sbc hl,de
    pop de
    pop hl
    jr nc,bj_after                      ; the one before is nearer
    inc hl                              ; it moves up a slot
    inc hl
    ld (hl),e
    inc hl
    ld (hl),d
    dec hl
    dec hl
    dec hl
    jr bj_slot
bj_after
    inc hl
    inc hl
bj_put
bj_bush
    ld de,0                             ; (self-modified: the bush)
    ld (hl),e
    inc hl
    ld (hl),d
    ret

;; HL = a bush -> HL = how far ahead it is
bj_ahead
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld de,(zcam)
    or a
    sbc hl,de
    ld a,h
    and hi(BUSH_PERIOD-1)
    ld h,a
    ret

;; ---------------------------------------------------------------------------
;; bush_one - DE = how far ahead a bush is (in reach), HL = its sprite table
;; in bush_tab: draw it, if it is in sight, and note its box. (A prop's too:
;; prop_one, with b1_way to prop_draw.)
;; ---------------------------------------------------------------------------
bush_one
    ; the row it stands on
    ld a,d
    cp 2
    jr nc,b1_far
    rra                                 ; below 512: every 2
    ld a,e
    rra
    ld e,a
    ld d,hi(bush_rz1)
    jr b1_rz
b1_far
    ld a,e                              ; beyond: every 8
    srl d
    rra
    srl d
    rra
    srl d
    rra
    sub 512/8
    or lo(bush_rz2)
    ld e,a
    ld d,hi(bush_rz2)
b1_rz
    ld a,(de)
    ld c,a                              ; C = row
b1_top
    cp 0                                ; (self-modified: the furthest row in
    ret c                               ; sight) behind the crest

    ; its sprite's record
    ld a,(hl)
    or c
    ld e,a
    inc hl
    ld d,(hl)
    inc hl
    ld a,(de)
    ld ixl,a
    ld ixh,hi(bush_sinfo)               ; IX = its sprite's record

    ; how far from the road's centre (signed: its side's table), and
    ; whether that is the inside
    ld a,(hl)
    or c
    ld e,a
    inc hl
    ld d,(hl)
    ld a,(de)
    ld e,a                              ; E = the offset
    rla
b1_inr
    ld a,0                              ; (self-modified: #80 if the right is
    jr nc,b1_ins                        ; the inside)
b1_inl
    ld a,0                              ; (self-modified: the left)
b1_ins
    ld iyh,a                            ; IYH: #80 on the inside

    ; and as far again as road_x moves its row (rd_gp, by its
    ; template group: bush_rh); far off if that is beyond a byte
    ld a,c
    or lo(bush_rh)
    ld l,a
    ld h,hi(bush_rh)
    ld l,(hl)
    ld h,hi(rd_gp)
    ld a,(hl)
    add a,e
    ret pe
    ld e,a

    ; its centre: the road's + the offset; it is drawn while that is on the
    ; screen. Its left: half its width less
    ld a,c
b1_cxl
    or 0                                ; (self-modified: the curve level's
    ld l,a                              ; centre table)
b1_cxh
    ld h,0
    ld a,(hl)
b1_mirror
    nop                                 ; (self-modified: NEG, ADD A,SCR_BYTES
    nop                                 ; for a left curve)
    add a,0
    add a,e
    ret pe                              ; (far off)
    cp SCR_BYTES
    ret nc                              ; off the screen (or left of it)
    sub (ix+SI_HW)
    ld d,a                              ; D = left (signed)

    ; its line, counted from ROAD_AREA_Y: HORIZON_Y + r, moved |hill| / r
    ; down (a crest) or up (a dip)
b1_hill
    ld a,1                              ; (self-modified: the hill; 1: none
    or a                                ; yet)
    jr z,b1_flat
    ld h,a
    jp p,b1_down
    neg
b1_down
    ld l,0
b1_div
    sub c
    jr c,b1_divided
    inc l
    jr b1_div
b1_divided
    ld a,h
    or a
    ld a,l
    jp p,b1_flat
    neg
b1_flat
    add a,HORIZON_Y-ROAD_AREA_Y
    add a,c
    cp ROAD_Y-ROAD_AREA_Y
    ret c                               ; above the road's top
    cp 128
    ret nc                              ; (well above it)
    ld c,a                              ; C = its base line
    cp HIT_Y
    jr c,b1_free                        ; touching our car: its base line in
    ld a,(car_off)                      ; the car's lower half, the two
    add a,a                             ; overlapping, HIT_TRIM bytes in from
    neg                                 ; either's side (coll)
    add a,d
    add a,(ix+SI_HW)
    sub SCR_BYTES/2
    ld b,#40                            ; (left of ours)
    jp m,b1_hit
    inc b                               ; (right)
    neg
b1_hit
    add a,(ix+SI_HIT)
    add a,CAR_HALF-HIT_TRIM
    jp m,b1_free
    jr z,b1_free
    ld a,b
    ld (coll),a
b1_free
    ld a,c
    sub (ix+SI_H)
    inc a
    ld c,a                              ; C = its top line (signed)
    ld a,iyh
    or a
    call nz,bd_note
b1_way
    jp b1_bush                          ; (self-modified: prop_draw for a prop,
                                        ; prop_one)
    ; which way: its code if it is all on the screen
b1_bush
    ld a,c
    or a
    jp m,bush_copy                      ; cut off at the top
    ld a,d
    or a
    jp m,bush_copy                      ; out to the left
    add a,(ix+SI_W)
    cp SCR_BYTES+1
    jp nc,bush_copy                     ; out to the right
    ld b,a                              ; B = its right end
    ld a,(ix+SI_R0)
    add a,d
    ld d,a                              ; D = where its first line's run ends

    ; its top line's start
    ld a,c
    add a,a
    ld l,a
    ld h,hi(bush_ltab)
    ld a,(hl)
    inc l
    ld h,(hl)
b1_buf
    res 7,h                             ; (self-modified: nop, nop for buffer 0)
    ld l,a
    add a,d
    ld e,a
    ld a,h
    adc a,0
    ld d,a
    push de                             ; (where its first line's run ends)
    ld a,l                              ; its box, for bush_erase: [left,
    add a,b                             ; left + width), whole pairs
    ld e,a
    ld a,h
    adc a,0
    ld d,a                              ; DE = the box's top right
    ld hl,(bd_rec)
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld a,(ix+SI_H)
    or iyh
    ld (hl),a                           ; its lines; inside the curve
    inc hl
    ld (hl),c                           ; its top line
    inc hl
    ld a,(ix+SI_WAY)
    ld (hl),a                           ; how it is erased
    inc hl
    ld a,(ix+SI_WAY+1)
    ld (hl),a
    inc hl
    ld (bd_rec),hl
    ld l,(ix+SI_CODE)
    ld h,(ix+SI_CODE+1)
    ex (sp),hl                          ; (its code on the stack), HL = where
    ld (b1_sp+1),sp                     ; its first line's run ends
    di
    ret                                 ; into its code

;; the sprites' code comes back here
bush_spr_done
b1_sp
    ld sp,0                             ; (self-modified)
    pop af                              ; (the code's address)
    ei
    ret

;; a sprite's code calls this where a line's step has gone past the last
;; line of a character row: on to the next row (the return address lands
;; where the line's first push goes)
bush_next_row
    ld a,h
    sub #40
    ld h,a
    ld a,l
    add a,96
    ld l,a
    ret nc
    inc h
    ret

;; ---------------------------------------------------------------------------
;; car_lines - after road_project, before road_draw (road_frame): where the
;; car is drawn - road_x - car_x pairs right of the middle (car_off), the
;; demo's and the tools' in the middle. If this buffer last showed it
;; elsewhere or seen another way (car_vfull: car_view, and on a slope -
;; the hill at least HILL_PITCH either way - uphill or downhill; spun, the
;; same on a slope, or turning near the screen's edges), the lines at its top where the
;; views' runs differ (CAR_TOP) are drawn whole - else what the old one had
;; there and the new one has not would stay on any of them road_project
;; left as it was. Line ROAD_AREA_Y + y is entry LAST_Y - y.
;; Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
    ASSERT CAR_TOP > 0 && CAR_Y+CAR_TOP <= ROAD_END
car_lines
    ld a,(hill)                 ; the car seen on a slope: uphill where the
    ld b,0                      ; road ahead climbs (a dip), downhill where
    or a                        ; it falls away (a crest)
    jp p,car_lines_crest
    neg
    cp HILL_PITCH
    jr c,car_lines_pitch
    ld b,3
    jr car_lines_pitch
car_lines_crest
    cp HILL_PITCH
    jr c,car_lines_pitch
    ld b,6
car_lines_pitch
    ld a,(car_view)
    cp SPIN_VIEW                ; (spun: so on a slope too)
    jr nc,$+3
    add a,b
    ld (car_vfull),a
    ld a,(car_free)             ; (the demo's, the tools': the middle)
    or a
    jr z,car_lines_off
    ld a,(car_x)
    ld b,a
    ld a,(road_x)
    sub b
    ld b,CAR_LEAD+2             ; (road_x can have gone a step on)
    call clamp_ab
car_lines_off
    ld (car_off),a
    ld (car_offc),a
    ld c,a
    ld a,(car_vfull)            ; spun, but further than SPIN_OFF from the
    cp SPIN_VIEW                ; middle (its box is wider): seen turning,
    jr c,car_lines_seen         ; which keeps off the screen's edges
    ld a,c
    add a,SPIN_OFF
    cp 2*SPIN_OFF+1
    jr c,car_lines_seen
    ld a,(car_vfull)
    sub SPIN_VIEW-1
    ld (car_vfull),a
car_lines_seen
    ld hl,drawn_off
    call buf_entry
    ld a,(hl)
    ld (hl),c
    sub c
    ld c,a                      ; C = 0: in the same place
    ld hl,drawn_view
    call buf_entry
    ld a,(car_vfull)
    cp (hl)
    ld (hl),a
    jr nz,car_lines_whole
    ld a,c
    or a
    ret z
car_lines_whole
    ld hl,(rp_slot)
    ld de,4*(LAST_Y-(CAR_Y+CAR_TOP-1-ROAD_AREA_Y))
    add hl,de
    ld e,4
    ld b,CAR_TOP
car_lines_one
    ld a,(hl)
    and #FC                             ; flags off: the whole line
    ld (hl),a
    add hl,de
    djnz car_lines_one
    ret

;; ---------------------------------------------------------------------------
;; car_draw - the player's car into the selected buffer, over the road and
;; the bushes: its code (bushcode.asm, scene.py's art) pushes it the way a
;; bush's does. It is in the same place in every picture and drawn over
;; whatever is there, so it is never taken away. Destroys everything.
;; ---------------------------------------------------------------------------
car_draw
    ld a,(car_vfull)                    ; how it is seen: car_views
    add a,a                             ; (gen/bush.asm)
    add a,a
    ld l,a
    ld h,0
    ld de,car_views
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)                           ; DE = where its first line's run ends
    inc hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a                              ; HL = its code
    ex de,hl
    ld a,(car_off)                      ; car_off pairs right (bytes: twice
    add a,a                             ; that, signed)
    ld c,a
    add a,a
    sbc a,a
    ld b,a
    add hl,bc
    ld a,(tgt_buf)
    or a
    jr z,cd_buf
    res 7,h                             ; (buffer 1: #8000 lower)
cd_buf
    push de
    ld (b1_sp+1),sp
    di
    ret                                 ; into its code

;; ---------------------------------------------------------------------------
;; bush_copy - the other way: its lines copied from its data with LDIs, each
;; cut at x = 0 and x = SCR_BYTES, those above line 0 left out.
;; C = top line, D = left, IX = its sprite's record, IYH = inside.
;; ---------------------------------------------------------------------------
bush_copy
    ; the first line drawn: its top, or line 0 if that is cut off
    ld a,c
    or a
    jp p,bc_first
    xor a
bc_first
    add a,a
    ld l,a
    ld h,hi(bush_ltab)
    ld a,(hl)
    inc l
    ld h,(hl)
bc_buf
    res 7,h                             ; (self-modified: nop, nop for buffer 0)
    ld l,a
    push hl

    ; its box, for bush_erase: [x0, x1) = [max(left, 0), min(left + width,
    ; SCR_BYTES)) in pairs, up to xr = min(x0 + 2 * pairs, SCR_BYTES)
    ld a,d
    or a
    jp p,bc_x0
    xor a
bc_x0
    ld b,a                              ; B = x0
    ld a,d
    add a,(ix+SI_W)
    cp SCR_BYTES+1
    jr c,bc_x1
    ld a,SCR_BYTES
bc_x1
    sub b
    inc a
    srl a
    ld e,a                              ; E = pairs
    add a,a
    add a,b
    cp SCR_BYTES+1
    jr c,bc_xr
    ld a,SCR_BYTES
bc_xr
    add a,l
    ld l,a
    jr nc,bc_tr
    inc h
bc_tr
    push de
    ex de,hl                            ; DE = the box's top right
    ld hl,(bd_rec)
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    pop de                              ; D = left, E = pairs
    ld a,d
    ld (bc_left+1),a
    ld a,c                              ; its lines drawn ...
    or a
    ld a,(ix+SI_H)
    jp p,bc_all
    add a,c
bc_all
    ld (bc_n+1),a
    or iyh                              ; ... inside the curve
    ld (hl),a
    inc hl
    ld a,c
    or a
    jp p,bc_first2
    xor a
bc_first2
    ld (hl),a                           ; its top line (cut: 0)
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
bc_n
    ld b,0                              ; (self-modified) B = lines drawn
    pop iy                              ; IY = the line's start

    ld l,(ix+SI_DATA)
    ld h,(ix+SI_DATA+1)                 ; HL = its data
    ld a,c
    or a
    jp p,bc_draw
bc_above                                ; cut off at the top: past those
    inc hl
    ld a,(hl)
    inc hl
    add a,l
    ld l,a
    jr nc,bc_above2
    inc h
bc_above2
    inc c
    jr nz,bc_above
bc_draw
    ld ixh,b                            ; lines to draw
bc_line
    ld a,(hl)                           ; the run: its first byte ...
    inc hl
bc_left
    add a,0                             ; (self-modified: the bush's left)
    ld c,(hl)                           ; ... its bytes
    inc hl
    jp m,bc_lcut                        ; starts left of the screen
    ld e,a                              ; E = x
    add a,c
    sub SCR_BYTES+1
    jr nc,bc_rcut                       ; ends right of it
bc_copy                                 ; C bytes, to x = E
    ld a,iyl
    add a,e
    ld e,a
    ld a,iyh
    adc a,0
    ld d,a
    ld a,c
    cpl
    add a,BUSH_MAXW+1
    add a,a
    ld (bc_jr+1),a
bc_jr
    jr bc_ldi                           ; (self-modified: past MAXW - C)
bc_ldi
    REPEAT BUSH_MAXW
    ldi
    REND
bc_next
    ld a,iyh                            ; the next line: #800 on ...
    add a,8
    ld iyh,a
    bit 6,a
    jr nz,bc_wrap
bc_count
    dec ixh
    jr nz,bc_line
    ret
bc_wrap                                 ; ... or the next character row
    sub #40
    ld iyh,a
    ld a,iyl
    add a,96
    ld iyl,a
    jr nc,bc_count
    inc iyh
    jr bc_count

bc_lcut                                 ; -A bytes of it left of the screen
    neg
    ld e,a
    ld a,c
    sub e
    jr c,bc_none
    jr z,bc_none
    ld c,a                              ; those on it, from x = 0
    ld a,e
    add a,l
    ld l,a
    jr nc,bc_lcut2
    inc h
bc_lcut2
    ld e,0
    jr bc_copy

bc_rcut                                 ; A + 1 bytes of it right of the
    inc a                               ; screen
    ld (bc_over+1),a                    ; (LDI takes BC)
    neg
    add a,c
    jr nc,bc_none                       ; (all of it)
    jr z,bc_none
    ld c,a                              ; those on it
    ld a,iyl
    add a,e
    ld e,a
    ld a,iyh
    adc a,0
    ld d,a
    ld a,c
    cpl
    add a,BUSH_MAXW+1
    add a,a
    ld (bc_jr2+1),a
bc_jr2
    jr bc_ldi2                          ; (self-modified)
bc_ldi2
    REPEAT BUSH_MAXW
    ldi
    REND
bc_over
    ld a,0                              ; (self-modified) past those off it
bc_past
    add a,l
    ld l,a
    jr nc,bc_next
    inc h
    jr bc_next
bc_none
    ld a,c                              ; none of it: past all its bytes
    jr bc_past
