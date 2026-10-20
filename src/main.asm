;; ===========================================================================
;; COUNTRY RIDE - Amstrad CPC 6128
;;
;; main.asm - the whole build. rasm assembles four memory spaces at once, so
;; every label is visible everywhere, and writes the four files the BASIC
;; loader loads:
;;
;;   ROADA.BIN  bank 4 (#4000)  road cores for stripe band A
;;   ROADB.BIN  bank 5 (#4000)  road cores for stripe band B
;;   ROADC.BIN  bank 6 (#4000)  road rows and hill tables
;;   GAME.BIN   bank 7 (#C000)  the game: main loop, HUD, graphics
;;   BOOT.BIN   base   (#4000)  takes the machine over, then the common
;;                              memory fragments it copies into place
;;
;; Build: make (see Makefile). README.md describes the memory plan.
;; ===========================================================================

    INCLUDE "hw.asm"
    INCLUDE "gen/consts.asm"
    INCLUDE "gen/roadconsts.asm"


FRAG_STORE  EQU #4100           ; where the fragments sit inside BOOT.BIN

;; ---------------------------------------------------------------------------
;; bank 4: band A cores
;; ---------------------------------------------------------------------------
    BANK
    ORG #4000
roada_start
    INCLUDE "gen/roada.asm"
roada_end
    ASSERT roada_end <= #8000
    SAVE "ROADA.BIN",#4000,roada_end-#4000,DSK,"build/countryride.dsk"

;; ---------------------------------------------------------------------------
;; bank 5: band B cores
;; ---------------------------------------------------------------------------
    BANK
    ORG #4000
roadb_start
    INCLUDE "gen/roadb.asm"
roadb_end
    ASSERT roadb_end <= #8000
    SAVE "ROADB.BIN",#4000,roadb_end-#4000,DSK,"build/countryride.dsk"

;; ---------------------------------------------------------------------------
;; bank 6: road rows and hill tables
;; ---------------------------------------------------------------------------
    BANK
    ORG #4000
roadc_start
    INCLUDE "gen/roadrows.asm"
roadc_end
    ASSERT roadc_end <= #8000
    SAVE "ROADC.BIN",#4000,roadc_end-#4000,DSK,"build/countryride.dsk"

;; ---------------------------------------------------------------------------
;; bank 7: the game
;; ---------------------------------------------------------------------------
    BANK
    ORG #C000
game_bank_start
    jp game_start
    INCLUDE "gen/consts_data.asm"
    INCLUDE "gen/gfx.asm"
    INCLUDE "gen/roadground.asm"
    INCLUDE "game.asm"
    INCLUDE "hud.asm"
    INCLUDE "horizon.asm"
    INCLUDE "screen.asm"
game_bank_end
    ASSERT game_bank_end <= #10000
    SAVE "GAME.BIN",#C000,game_bank_end-#C000,DSK,"build/countryride.dsk"

;; ---------------------------------------------------------------------------
;; base memory: boot and the common fragments
;; ---------------------------------------------------------------------------
    BANK
    ORG #4000
    INCLUDE "boot.asm"
    INCLUDE "common.asm"
    INCLUDE "road.asm"
    SAVE "BOOT.BIN",#4000,FRAG_STORE+8*FRAG_LEN-#4000,DSK,"build/countryride.dsk"

    PRINT "bank 4 (ROADA.BIN): ",{hex}roada_end-#4000," bytes"
    PRINT "bank 5 (ROADB.BIN): ",{hex}roadb_end-#4000," bytes"
    PRINT "bank 6 (ROADC.BIN): ",{hex}roadc_end-#4000," bytes"
    PRINT "bank 7 (GAME.BIN):  ",{hex}game_bank_end-#C000," bytes"
