;; ===========================================================================
;; horizon.asm - how far the horizon drops (bank 7).
;;
;; The sky and the mountains go down the screen as far as the road's top
;; does, so the band of ground between them stays the same. Moving them is
;; the interrupt handler's job (raster ruptures, see hw.asm); the game only
;; says how far, with each picture it asks to be shown.
;; ===========================================================================

;; ---------------------------------------------------------------------------
;; picture_drop - A = the drop for the picture drawn with (hill): the lines
;; at the top of the road that no row reaches.
;; ---------------------------------------------------------------------------
picture_drop
    ld a,(hill)
    add a,128
    srl a                       ; the hill level, as road_project has it
    ld l,a
    ld h,0
    ld de,hz_ground
    add hl,de
    ld a,(hl)
    ret
