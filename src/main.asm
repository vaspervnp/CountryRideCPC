;; ===========================================================================
;; COUNTRY RIDE - Amstrad CPC 6128
;;
;; main.asm - the whole build. rasm assembles four memory spaces at once, so
;; every label is visible everywhere, and writes the four files the BASIC
;; loader loads:
;;
;;   ROADA.BIN  bank 4 (#4000)  road templates and cores for stripe band A
;;   ROADB.BIN  bank 5 (#4000)  road cores and templates for stripe band B
;;   ROADC.BIN  bank 6 (#4000)  road rows and hill tables, the traffic
;;   GAME.BIN   bank 7 (#C000)  the game: main loop, HUD, graphics
;;   BOOT.BIN   base   (#4000)  takes the machine over, then the common
;;                              memory fragments it copies into place, and
;;                              the bush sprites' code, already in place
;;                              in page 1
;;   CARn.BIN   (#1900)         car n's own code, for BOOT.BIN to put in
;;                              place (the loader loads the picked car's)
;;   SOUND.BIN  (#98C0)         the sound, for BOOT.BIN to put in place
;;   SELECT.SCR (#C000)         the screen the car is picked on
;;
;; Build: make (see Makefile). README.md describes the memory plan.
;; ===========================================================================

    INCLUDE "hw.asm"
    INCLUDE "gen/consts.asm"
    INCLUDE "gen/roadconsts.asm"
    INCLUDE "cachemac.asm"


;; Where the fragments sit in BOOT.BIN (page 1, where it is loaded): two to
;; each 2K block's first #600 bytes, which the HUDs take later - fragments 0
;; and 1 after the boot code. #x600-#x7FF of each block is the bush sprites'
;; code, for good.
FRAG_ST0    EQU boot_end
FRAG_ST1    EQU boot_end+FRAG_LEN
FRAG_ST2    EQU #4800
FRAG_ST3    EQU #4800+FRAG_LEN
FRAG_ST4    EQU #5000
FRAG_ST5    EQU #5000+FRAG_LEN
FRAG_ST6    EQU #5800
FRAG_ST7    EQU #5800+FRAG_LEN
FRAG_ST8    EQU #6000
FRAG_ST9    EQU #6000+FRAG_LEN
FRAG_ST10   EQU #6800
FRAG_ST11   EQU #6800+FRAG_LEN
FRAG_ST12   EQU #7000
FRAG_ST13   EQU #7000+FRAG_LEN
FRAG_ST14   EQU #7800
FRAG_ST15   EQU #7800+FRAG_LEN

;; ---------------------------------------------------------------------------
;; bank 4: band A - the templates in #4000-#5FFF, the cores from #6000
;; (road_draw tells a band A template from a band B one by bit 13)
;; ---------------------------------------------------------------------------
    BANK
    ORG TMPL_A
roada_start
    INCLUDE "gen/roadtmpla.asm"
    ASSERT $ <= TMPL_A+#2000
    ORG CORES_A
    INCLUDE "gen/roada.asm"
    INCLUDE "gen/roadgeoa.asm"
    INCLUDE "cache4.asm"
    INCLUDE "gen/trafcode_4.asm"        ; (traffic sprite pieces: room)
roada_end
    ASSERT roada_end <= #8000
    SAVE "ROADA.BIN",#4000,roada_end-#4000,DSK,"build/countryride.dsk"

;; ---------------------------------------------------------------------------
;; bank 5: band B - the cores in #4000-#5FFF, the templates from #6000
;; ---------------------------------------------------------------------------
    BANK
    ORG CORES_B
roadb_start
    INCLUDE "gen/roadb.asm"
    INCLUDE "gen/roadgeob.asm"
    INCLUDE "cache5.asm"
    ASSERT $ <= TMPL_B
    ORG TMPL_B
    INCLUDE "gen/roadtmplb.asm"
roadb_end
    ASSERT roadb_end <= #8000
    SAVE "ROADB.BIN",#4000,roadb_end-#4000,DSK,"build/countryride.dsk"

;; ---------------------------------------------------------------------------
;; bank 6: road rows and hill tables; the traffic (its code, its tables
;; and pieces of its sprites - the rest in banks 4 and 7, the fragments and
;; the hidden lines, tools/mktrafcode.py)
;; ---------------------------------------------------------------------------
    BANK
    ORG #4000
roadc_start
    INCLUDE "gen/roadrows.asm"
    INCLUDE "road6.asm"
    INCLUDE "traffic.asm"
    INCLUDE "gen/traffic.asm"
    INCLUDE "gen/trafcode_6.asm"
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
;; bush.asm's per buffer: where its records end (low byte), then the records
;; (in one page)
BUSH_RECS   EQU 60                      ; ((BUSH_MAX + 2) x BUSH_REC: below -
                                        ; the bushes', a prop's two)
bush_recs0  defb lo(bush_recs0+1)
    defs BUSH_RECS,0
bush_recs1  defb lo(bush_recs1+1)
    defs BUSH_RECS,0
    ASSERT hi(bush_recs0) == hi($-1)
    INCLUDE "gen/consts_data.asm"
    INCLUDE "gen/gfx.asm"
    INCLUDE "gen/roadground.asm"
    INCLUDE "gen/bush.asm"
    INCLUDE "game.asm"
    INCLUDE "bush.asm"
    ASSERT BUSH_RECS == (BUSH_MAX+2)*BUSH_REC
    INCLUDE "props.asm"
    INCLUDE "hud.asm"
    INCLUDE "horizon.asm"
    INCLUDE "screen.asm"
    INCLUDE "course.asm"
game_bank_end
    ASSERT game_bank_end <= CURVE_RING && HILL_RING+64 <= CAR_HILL_ORG
    ORG CURVE_RING                          ; (run once, before the rings are
    INCLUDE "init.asm"                      ; worked out over it)
init_end
    ASSERT init_end <= CAR_HILL_ORG         ; (the rest: the car's views on
                                            ; hills, CARn.BIN)
    SAVE "GAME.BIN",#C000,init_end-#C000,DSK,"build/countryride.dsk"

;; ---------------------------------------------------------------------------
;; base memory: boot and the common fragments
;; ---------------------------------------------------------------------------
    BANK
    ORG #4000
    INCLUDE "boot.asm"
    INCLUDE "common.asm"
    INCLUDE "road.asm"
    INCLUDE "cache.asm"
    INCLUDE "gen/bushdata.asm"
    INCLUDE "road15.asm"
    INCLUDE "gen/bushcode.asm"
    INCLUDE "player.asm"
    ASSERT FRAG_ST1+FRAG_LEN <= #4600
    SAVE "BOOT.BIN",#4000,#4000,DSK,"build/countryride.dsk"

;; ---------------------------------------------------------------------------
;; the cars: each one's own code and car_views (CARn.BIN, which the loader
;; loads at CAR_BLOB for the car picked and boot.asm puts in place), and the
;; screen the car is picked on (SELECT.SCR, tools/mkselect.py)
;; ---------------------------------------------------------------------------
CAR_BLOB    EQU #1900                   ; (the loader's MEMORY is below it;
                                        ; the hidden lines of buffer 1's block 3
                                        ; are below it too: boot_car puts code
                                        ; there)
CAR_MAGIC   EQU #5243                   ; "CR"
    INCLUDE "gen/cars.asm"

;; ---------------------------------------------------------------------------
;; the sound (SOUND.BIN, which the loader loads at SOUND_BLOB and boot.asm
;; puts in place, after the car's records: records too)
;; ---------------------------------------------------------------------------
SOUND_BLOB  EQU #98C0                   ; buffer 0's lines 179 on in its fourth
                                        ; 2K block: past the car's records'
                                        ; hidden lines, before fragment 11
    BANK
    ORG SOUND_BLOB
    defw CAR_MAGIC
    INCLUDE "sound.asm"
    defw #FFFF
sound_end
    ASSERT sound_end <= FRAG8+3*#800       ; (fragment 11's place)
    SAVE "SOUND.BIN",SOUND_BLOB,sound_end-SOUND_BLOB,DSK,"build/countryride.dsk"

    BANK
    ORG #C000
    INCBIN "gen/select.scr"
    SAVE "SELECT.SCR",#C000,#4000,DSK,"build/countryride.dsk"

    PRINT "bank 4 (ROADA.BIN): ",{hex}roada_end-#4000," bytes"
    PRINT "bank 5 (ROADB.BIN): ",{hex}roadb_end-#4000," bytes"
    PRINT "bank 6 (ROADC.BIN): ",{hex}roadc_end-#4000," bytes"
    PRINT "bank 7 (GAME.BIN):  ",{hex}game_bank_end-#C000," bytes"
    PRINT "SOUND.BIN:          ",{hex}sound_end-SOUND_BLOB," bytes"
