;; ===========================================================================
;; boot.asm - BOOT.BIN, loaded at #4000 by the BASIC loader and CALLed.
;;
;; By the time this runs the loader has put the road engine in banks 4 and 5
;; and the game in bank 7 (see disc/country.bas). This takes the machine over
;; from the firmware: ROMs off, the common fragments copied into place, IM 2,
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
    ; FRAG_ST0..): 0-7 to page 0, 8-15 to page 2
    ld hl,FRAG_ST0
    ld de,FRAG0
    ld a,FRAG_COUNT
boot_frag
    push de
    ld bc,FRAG_LEN
    ldir
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

    ; IM 2 through the table at #0600
    ld a,hi(IM2_TABLE)
    ld i,a
    im 2

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
    ASSERT $ <= #4E00
