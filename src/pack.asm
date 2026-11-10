;; ===========================================================================
;; COUNTRY RIDE - Amstrad CPC 6128
;;
;; pack.asm - the disc. Each file main.asm makes (build/<name>.raw) packed
;; (ZX0: rasm's LZX0) behind the word where it goes; SELECT.BIN the select
;; screen packed so, after the code that puts the unpacker (dzx0.asm) at
;; UNPACK and unpacks the screen. The loader (disc/country.bas) loads each
;; file at PACK_LOW or PACK_HIGH and CALLs UNPACK_LOW or UNPACK_HIGH
;; (discmap.asm; README.md: The loader). Each one is saved too as
;; build/<name>.pk, which tools/zx0check.py unpacks and checks against its
;; .raw - and where it fits (rasm's labels past a packed section are the
;; unpacked ones in an ASSERT; only SAVE has them packed).
;;
;; Build: make, after main.asm (see Makefile).
;; ===========================================================================

    INCLUDE "discmap.asm"
    INCLUDE "dzx0.asm"

;; ---------------------------------------------------------------------------
;; SELECT.BIN, loaded at #4000 and CALLed: the unpacker put in place, then
;; the screen unpacked at #C000
;; ---------------------------------------------------------------------------
    BANK
    ORG #4000
select_bin
    ld hl,unpack_ph
    ld de,UNPACK
    ld bc,unpack_end-UNPACK
    ldir
    ld hl,select_pk
    jp unpack_file
unpack_ph
    ORG UNPACK,unpack_ph
from_low                                ; the file at PACK_LOW
    ld hl,PACK_LOW
    jr unpack_file
from_high                               ; the file at PACK_HIGH
    ld hl,PACK_HIGH
unpack_file                             ; HL = a file: where it goes, then
    ld e,(hl)                           ; its bytes, packed
    inc hl
    ld d,(hl)
    inc hl
    dzx0_standard                       ; (returns when it is all there)
unpack_end
    ORG unpack_ph+unpack_end-UNPACK
    ASSERT from_low == UNPACK_LOW && from_high == UNPACK_HIGH
    ASSERT unpack_end <= #A67C          ; (the 6128's characters 240-255)
select_pk
    defw #C000
    LZX0
    INCBIN "../build/select.raw"
    LZCLOSE
select_pk_end
    SAVE "SELECT.BIN",select_bin,select_pk_end-select_bin,DSK,"build/countryride.dsk"
    SAVE "build/select.pk",select_pk,select_pk_end-select_pk

;; ---------------------------------------------------------------------------
;; SPINA.BIN: the turning's streams, area 0 (bank 4 at #4000)
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_LOW
spina_pk
    defw #4000
    LZX0
    INCBIN "../build/spina.raw"
    LZCLOSE
spina_pk_end
    SAVE "SPINA.BIN",spina_pk,spina_pk_end-spina_pk,DSK,"build/countryride.dsk"
    SAVE "build/spina.pk",spina_pk,spina_pk_end-spina_pk

;; ---------------------------------------------------------------------------
;; SPINB.BIN: the turning's streams, area 1 (bank 5 at #4000)
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_LOW
spinb_pk
    defw #4000
    LZX0
    INCBIN "../build/spinb.raw"
    LZCLOSE
spinb_pk_end
    SAVE "SPINB.BIN",spinb_pk,spinb_pk_end-spinb_pk,DSK,"build/countryride.dsk"
    SAVE "build/spinb.pk",spinb_pk,spinb_pk_end-spinb_pk

;; ---------------------------------------------------------------------------
;; SPINC.BIN: the turning's streams, area 2 (bank 6 at #4000)
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_LOW
spinc_pk
    defw #4000
    LZX0
    INCBIN "../build/spinc.raw"
    LZCLOSE
spinc_pk_end
    SAVE "SPINC.BIN",spinc_pk,spinc_pk_end-spinc_pk,DSK,"build/countryride.dsk"
    SAVE "build/spinc.pk",spinc_pk,spinc_pk_end-spinc_pk

;; ---------------------------------------------------------------------------
;; SPIND.BIN: the turning's streams, area 3 (bank 7 at #4000)
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_LOW
spind_pk
    defw #4000
    LZX0
    INCBIN "../build/spind.raw"
    LZCLOSE
spind_pk_end
    SAVE "SPIND.BIN",spind_pk,spind_pk_end-spind_pk,DSK,"build/countryride.dsk"
    SAVE "build/spind.pk",spind_pk,spind_pk_end-spind_pk

;; ---------------------------------------------------------------------------
;; SPINE.BIN: the turning's streams, area 4 (base memory at #4000)
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_LOW
spine_pk
    defw #4000
    LZX0
    INCBIN "../build/spine.raw"
    LZCLOSE
spine_pk_end
    SAVE "SPINE.BIN",spine_pk,spine_pk_end-spine_pk,DSK,"build/countryride.dsk"
    SAVE "build/spine.pk",spine_pk,spine_pk_end-spine_pk

;; ---------------------------------------------------------------------------
;; SPIN.BIN: the turning's code (spin.asm), at SPIN_CODE
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_LOW
spin_pk
    defw SPIN_CODE
    LZX0
    INCBIN "../build/spin.raw"
    LZCLOSE
spin_pk_end
    SAVE "SPIN.BIN",spin_pk,spin_pk_end-spin_pk,DSK,"build/countryride.dsk"
    SAVE "build/spin.pk",spin_pk,spin_pk_end-spin_pk

;; ---------------------------------------------------------------------------
;; ROADA.BIN: bank 4 (the loader switches it in at #4000)
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_LOW
roada_pk
    defw #4000
    LZX0
    INCBIN "../build/roada.raw"
    LZCLOSE
roada_pk_end
    SAVE "ROADA.BIN",roada_pk,roada_pk_end-roada_pk,DSK,"build/countryride.dsk"
    SAVE "build/roada.pk",roada_pk,roada_pk_end-roada_pk

;; ---------------------------------------------------------------------------
;; ROADB.BIN: bank 5
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_LOW
roadb_pk
    defw #4000
    LZX0
    INCBIN "../build/roadb.raw"
    LZCLOSE
roadb_pk_end
    SAVE "ROADB.BIN",roadb_pk,roadb_pk_end-roadb_pk,DSK,"build/countryride.dsk"
    SAVE "build/roadb.pk",roadb_pk,roadb_pk_end-roadb_pk

;; ---------------------------------------------------------------------------
;; ROADC.BIN: bank 6
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_LOW
roadc_pk
    defw #4000
    LZX0
    INCBIN "../build/roadc.raw"
    LZCLOSE
roadc_pk_end
    SAVE "ROADC.BIN",roadc_pk,roadc_pk_end-roadc_pk,DSK,"build/countryride.dsk"
    SAVE "build/roadc.pk",roadc_pk,roadc_pk_end-roadc_pk

;; ---------------------------------------------------------------------------
;; GAME.BIN: bank 7
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_LOW
game_pk
    defw #4000
    LZX0
    INCBIN "../build/game.raw"
    LZCLOSE
game_pk_end
    SAVE "GAME.BIN",game_pk,game_pk_end-game_pk,DSK,"build/countryride.dsk"
    SAVE "build/game.pk",game_pk,game_pk_end-game_pk

;; ---------------------------------------------------------------------------
;; SOUND.BIN
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_LOW
sound_pk
    defw SOUND_BLOB
    LZX0
    INCBIN "../build/sound.raw"
    LZCLOSE
sound_pk_end
    SAVE "SOUND.BIN",sound_pk,sound_pk_end-sound_pk,DSK,"build/countryride.dsk"
    SAVE "build/sound.pk",sound_pk,sound_pk_end-sound_pk

;; ---------------------------------------------------------------------------
;; RACE.BIN
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_LOW
race_pk
    defw RACE_BLOB
    LZX0
    INCBIN "../build/race.raw"
    LZCLOSE
race_pk_end
    SAVE "RACE.BIN",race_pk,race_pk_end-race_pk,DSK,"build/countryride.dsk"
    SAVE "build/race.pk",race_pk,race_pk_end-race_pk

;; ---------------------------------------------------------------------------
;; CAR0.BIN
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_HIGH
car0_pk
    defw CAR_BLOB
    LZX0
    INCBIN "../build/car0.raw"
    LZCLOSE
car0_pk_end
    SAVE "CAR0.BIN",car0_pk,car0_pk_end-car0_pk,DSK,"build/countryride.dsk"
    SAVE "build/car0.pk",car0_pk,car0_pk_end-car0_pk

;; ---------------------------------------------------------------------------
;; CAR1.BIN
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_HIGH
car1_pk
    defw CAR_BLOB
    LZX0
    INCBIN "../build/car1.raw"
    LZCLOSE
car1_pk_end
    SAVE "CAR1.BIN",car1_pk,car1_pk_end-car1_pk,DSK,"build/countryride.dsk"
    SAVE "build/car1.pk",car1_pk,car1_pk_end-car1_pk

;; ---------------------------------------------------------------------------
;; CAR2.BIN
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_HIGH
car2_pk
    defw CAR_BLOB
    LZX0
    INCBIN "../build/car2.raw"
    LZCLOSE
car2_pk_end
    SAVE "CAR2.BIN",car2_pk,car2_pk_end-car2_pk,DSK,"build/countryride.dsk"
    SAVE "build/car2.pk",car2_pk,car2_pk_end-car2_pk

;; ---------------------------------------------------------------------------
;; CAR3.BIN
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_HIGH
car3_pk
    defw CAR_BLOB
    LZX0
    INCBIN "../build/car3.raw"
    LZCLOSE
car3_pk_end
    SAVE "CAR3.BIN",car3_pk,car3_pk_end-car3_pk,DSK,"build/countryride.dsk"
    SAVE "build/car3.pk",car3_pk,car3_pk_end-car3_pk

;; ---------------------------------------------------------------------------
;; BOOT.BIN: base memory
;; ---------------------------------------------------------------------------
    BANK
    ORG PACK_HIGH
boot_pk
    defw #4000
    LZX0
    INCBIN "../build/boot.raw"
    LZCLOSE
boot_pk_end
    SAVE "BOOT.BIN",boot_pk,boot_pk_end-boot_pk,DSK,"build/countryride.dsk"
    SAVE "build/boot.pk",boot_pk,boot_pk_end-boot_pk
