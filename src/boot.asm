;; ===========================================================================
;; boot.asm - BOOT.BIN, loaded at #4000 by the BASIC loader and CALLed.
;;
;; By the time this runs the loader has put the road engine in banks 4 and 5
;; and the game in bank 7 (see disc/country.bas). This takes the machine over
;; from the firmware: ROMs off, the common fragments copied into place, IM 1,
;; the overscan CRTC set, and on to the game in bank 7. Nothing returns to
;; BASIC. The rest of the file is the fragments, and the bush sprites' code,
;; which is loaded where it runs.
;; ===========================================================================

boot
    di
    ld sp,BOT0_BASE+#540        ; the top of buffer 0's first road block,
                                ; drawn later: the game's own stack is in a
                                ; fragment not yet copied
    ld bc,#7F00+GA_MODE0
    out (c),c                   ; mode 0, both ROMs off
    SET_RAM RAM_C0

    ; every pen and the border black while the screens are garbage
    ld bc,#7F00
boot_ink
    out (c),c
    ld a,BORDER_HW
    out (c),a
    inc c
    ld a,c
    cp #11
    jr c,boot_ink

    ; the common fragments, stored two to a 2K block of this file (main.asm,
    ; FRAG_ST0..): 0-7 to page 0, 8-15 to page 2 - but 3-6, where the car's
    ; file is (CAR_BLOB), only after boot_car
    ld hl,FRAG_ST0
    ld de,FRAG0
    ld a,FRAG_COUNT
boot_frag
    push de
    ld bc,FRAG_LEN
    cp FRAG_COUNT-6             ; (A: FRAG_COUNT - the fragment)
    jr c,boot_frag_cp
    cp FRAG_COUNT-2
    jr nc,boot_frag_cp
    add hl,bc                   ; (3-6: later; B 0, as after LDIR)
    ld b,0
    jr boot_frag_on
boot_frag_cp
    ldir
boot_frag_on
    pop de
    bit 0,a                     ; the second of a block's two: on to the
    jr z,boot_frag_dst          ; next block
    ld l,b
    ld c,a
    ld a,h
    or 7
    inc a
    ld h,a
    ld a,c
boot_frag_dst
    ex de,hl
    ld bc,#800                  ; the next 2K block
    add hl,bc
    cp FRAG_COUNT/2+1
    jr nz,boot_frag_next
    ld bc,FRAG8-FRAG0-8*#800    ; on to page 2
    add hl,bc
boot_frag_next
    ex de,hl
    dec a
    jr nz,boot_frag
    call boot_car               ; the car picked, over the first one; then
                                ; fragments 3-6

    im 1                        ; (boot_car has put its JP in place)

    ; the overscan screen, showing buffer 0
    ld hl,crtc_regs
boot_crtc
    ld a,(hl)
    inc hl
    cp #FF
    jr z,boot_crtc_done
    ld b,#BC
    out (c),a
    ld a,(hl)
    inc hl
    ld b,#BD
    out (c),a
    jr boot_crtc
boot_crtc_done

    SET_RAM RAM_C1
    ei
    jp game_start
boot_end

;; the CRTC's values, after fragments 2 and 3 (where the HUDs go later)
    ORG FRAG_ST3+FRAG_LEN
crtc_regs
    defb 0,CRTC_R0, 1,CRTC_R1, 2,CRTC_R2, 3,CRTC_R3
    defb 4,CRTC_R4, 5,CRTC_R5, 6,CRTC_R6, 7,CRTC_R7
    defb 8,0, 9,CRTC_R9, 12,hi(HUD_MA0), 13,lo(HUD_MA0)
    defb #FF

;; boot_car - the car picked (the loader loads its CARn.BIN at CAR_BLOB,
;; gen/cars.asm): its records copied into place, with RAM_C1 (bank 7 at
;; #C000) - its code over the first car's in this file; its views on hills
;; and spun, some in the HUDs' eighth rows, which the fragments before have
;; left free;
;; car_views and car_id. Without one (no magic word there) the first car
;; stays, seen on the level on hills too (and turning when spun). Then
;; fragments 3-6, over the car's file, IM 1's JP, and the sound (SOUND.BIN,
;; at SOUND_BLOB: some of it where the car's file was, some where fragments
;; 2-7 were stored) and the race's extras (RACE.BIN, RACE_BLOB: some where
;; the car's file was, some here - so last, not returning here). RAM_C1
;; after.
boot_car
    SET_RAM RAM_C1
    ld hl,CAR_BLOB
    call boot_blob
    ld hl,FRAG_ST3
    ld de,FRAG3
    ld bc,FRAG_LEN
    ldir
    ld hl,FRAG_ST4
    ld de,FRAG4
    ld bc,FRAG_LEN
    ldir
    ld de,FRAG5                         ; (FRAG_ST5 follows)
    ld bc,FRAG_LEN
    ldir
    ld hl,FRAG_ST6
    ld de,FRAG6
    ld bc,FRAG_LEN
    ldir
    ld a,#C3                            ; IM 1's RST #38: JP isr (in a hidden
    ld (IM1_JP),a                       ; line, which the car's records have
    ld hl,isr                           ; left out)
    ld (IM1_JP+1),hl
    ld hl,SOUND_BLOB
    call boot_blob
    ld hl,RACE_BLOB
    jp boot_blob                        ; (its RET is boot_car's)
    ASSERT $ <= #4E00 && crtc_regs+25 <= SND_M3

    ORG FRAG_ST5+FRAG_LEN               ; (the HUDs' later, and the car's
                                        ; records start at #x5A0)
;; boot_blob - HL = a file of records (CARn.BIN, SOUND.BIN): if it starts
;; with the magic word, each record's bytes copied to where it says
boot_blob
    ld a,(hl)
    cp lo(CAR_MAGIC)
    ret nz
    inc hl
    ld a,(hl)
    cp hi(CAR_MAGIC)
    ret nz
    ld (hl),0                   ; (used up)
    inc hl
boot_blob_rec
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld a,d
    and e
    inc a
    ret z                       ; (a dest of #FFFF: the end - #0000 is one)
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    ldir
    jr boot_blob_rec
    ASSERT $ <= FRAG_ST5+FRAG_LEN+#20
    ASSERT FRAG_ST5 == FRAG_ST4+FRAG_LEN
