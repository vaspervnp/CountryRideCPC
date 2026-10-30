;; ===========================================================================
;; course.asm - the track (bank 7, RAM_C1).
;;
;; The game reads the track an entry - 32 depth units - at a time: its hill
;; and its curve level under the camera, and a few entries on (hill_near,
;; cache_want). Those come from rings of 64 entries, HILL_RING and
;; CURVE_RING, which course_fill keeps worked out COURSE_AHEAD entries ahead
;; of the camera from a list of segments (gfx.asm: course_demo, the race's
;; course_race; tools/course.py has the model, to the bit): so the track is
;; as long as its list, and another list can follow from any entry on -
;; the road first brought to the flat (course_set).
;; ===========================================================================

COURSE_AHEAD EQU 8              ; entries kept worked out past the camera's
                                ; (hill_near looks HILL_AHEAD on, cache_want
                                ; about 2)
    ASSERT HILL_AHEAD+1 < COURSE_AHEAD && COURSE_AHEAD < RING_MASK
    ASSERT lo(CURVE_RING) == 0 && HILL_RING == CURVE_RING+64 && RING_MASK == 63

crs_z       defw 0              ; the depth of the next entry to work out
crs_ptr     defw course_demo    ; the next segment
crs_start   defw course_demo    ; the list's first (its end 0,0: round again)
crs_left    defb 0              ; the segment's entries still to come
crs_n       defb 0              ; its length
crs_v       defb 0              ; 0 straight, a curve level, a hill (|v| >= 16)
crs_t       defb 0              ; its entries so far
crs_p       defb 0              ; a hill's: 128 t / n,
crs_q       defb 0              ; ... and the remainder
crs_ramp    defb 0              ; not 0: to the flat first (course_set)
crs_k       defb 0              ; the last entry worked out: curve level,
crs_h       defb 0              ; ... hill

;; ---------------------------------------------------------------------------
;; course_set - HL = a segment list: the track from the next entry worked
;; out on (COURSE_AHEAD past the camera's) - A not 0: after the road is
;; brought to the flat, a level and HILL_RAMP of hill an entry. DE = its
;; props (props.asm), from its first entry on.
;; ---------------------------------------------------------------------------
course_set
    ld (prp_pend),de
    ld (crs_ptr),hl
    ld (crs_start),hl
    ld (crs_ramp),a
    xor a
    ld (crs_left),a
    ret

;; ---------------------------------------------------------------------------
;; course_fill - the rings worked out up to COURSE_AHEAD entries past the
;; camera's. Destroys everything.
;; ---------------------------------------------------------------------------
course_fill
    ld hl,(zcam)
    ld a,l
    and #E0
    ld e,a
    ld d,h                              ; DE = the camera's entry's depth
    ld hl,(crs_z)
    or a
    sbc hl,de
    ld de,COURSE_AHEAD*32
    or a
    sbc hl,de
    ret nc                              ; far enough
    call course_entry
    ld hl,(crs_z)
    ld de,32
    add hl,de
    ld (crs_z),hl
    sbc hl,de                           ; (no carry)
    add hl,hl
    add hl,hl
    add hl,hl                           ; H = its entry
    ld a,h
    and RING_MASK
    ld l,a
    ld h,hi(CURVE_RING)
    ld (hl),c
    set 6,l
    ld (hl),b
    ld (crs_k),bc
    jr course_fill

;; course_entry - the next entry: B = its hill, C = its curve level.
;; Destroys AF, DE, HL.
course_entry
    ld a,(crs_ramp)
    or a
    jr z,ce_seg
    ld bc,(crs_k)                       ; to the flat first
    ld a,b
    or c
    jr z,ce_flat_now
    ld a,c                              ; the curve a level nearer
    or a
    jr z,ce_ramp_h
    dec c
    jp p,ce_ramp_h
    inc c
    inc c
ce_ramp_h
    ld a,b                              ; the hill HILL_RAMP nearer
    or a
    ret z
    jp m,ce_ramp_dip
    sub HILL_RAMP
    jr nc,ce_ramp_set
    xor a
    jr ce_ramp_set
ce_ramp_dip
    add a,HILL_RAMP
    jr nc,ce_ramp_set
    xor a
ce_ramp_set
    ld b,a
    ret
ce_flat_now
    ld (crs_ramp),a                     ; (0)

ce_seg
    ld a,(crs_left)
    or a
    jr nz,ce_go
ce_next                                 ; the next segment
    ld hl,(crs_ptr)
    ld a,(hl)
    inc hl
    ld c,(hl)
    or a
    jr nz,ce_load
    dec c                               ; 0,1: straight on for good
    ld b,a
    ret z
    ld hl,(crs_start)                   ; 0,0: round again
    ld (crs_ptr),hl
    jr ce_next
ce_load
    inc hl
    ld (crs_ptr),hl
    push af
    push bc
    call prop_start                     ; (a new course's first: its props)
    pop bc
    pop af
    ld (crs_n),a
    ld hl,crs_v
    ld (hl),c
    inc hl
    ld b,4
ce_load_0
    ld (hl),0                           ; crs_t, crs_p, crs_q, (crs_ramp)
    inc hl
    djnz ce_load_0
ce_go
    dec a
    ld (crs_left),a                     ; n - 1 - t
    ld hl,crs_t
    ld e,(hl)                           ; E = t
    inc (hl)
    ld bc,0
    ld a,(crs_v)
    or a
    ret z                               ; straight on
    jp p,$+5
    neg
    cp 16
    jr nc,ce_hill
    cp e                                ; a curve: min(|v|, t, n - 1 - t),
    jr c,$+3                            ; its way
    ld a,e
    ld e,a
    ld a,(crs_left)
    cp e
    jr c,$+3
    ld a,e
    ld c,a
    ld a,(crs_v)
    or a
    ret p
    xor a
    sub c
    ld c,a
    ret

ce_hill                                 ; A = |v|: |v| sin(pi p / 128),
    ld e,a                              ; rounded, its way
    ld d,0
    ld a,(crs_p)
    cp 65
    jr c,ce_hill_q
    neg
    add a,128                           ; (the sine's second quarter)
ce_hill_q
    ld hl,sine_q
    add a,l
    ld l,a
    jr nc,$+3
    inc h
    ld h,(hl)
    ld l,d
    ld b,8
ce_hill_mul
    add hl,hl
    jr nc,$+3
    add hl,de
    djnz ce_hill_mul                    ; HL = |v| s
    ld a,l
    add a,128
    ld a,h
    adc a,b                             ; (B = 0)
    ld e,a
    ld a,(crs_v)
    or a
    ld a,e
    jp p,$+5
    neg
    ld b,a
    ld a,(crs_n)                        ; p = 128 t / n for the next
    ld e,a
    ld hl,crs_p
    ld a,(crs_q)
    add a,128
ce_hill_p
    cp e
    jr c,ce_hill_pq
    sub e
    inc (hl)
    jr ce_hill_p
ce_hill_pq
    ld (crs_q),a
    ret

;; ---------------------------------------------------------------------------
;; stage_colours - A = a stage: the pens it colours (stage_pen_ids) set to
;; its colours (stage_hw), and the border below the mountains to its
;; ground's (irq_road). Interrupts off for each pen: irq_road selects the
;; border to colour it. Destroys AF, BC, DE, HL.
;; ---------------------------------------------------------------------------
stage_colours
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,stage_hw
    add hl,de
    push hl
    ld de,stage_pen_ids
    ld b,GA_PORT
stage_colours_pen
    ld a,(de)
    inc de
    or a
    jp m,stage_colours_ground
    di
    out (c),a
    ld a,(hl)
    inc hl
    out (c),a
    ei
    jr stage_colours_pen
stage_colours_ground
    pop hl
    ld de,STAGE_GROUND
    add hl,de
    ld a,(hl)
    ld (irq_ground+1),a
    ret
