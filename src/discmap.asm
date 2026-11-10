;; ===========================================================================
;; discmap.asm - where the loader (disc/country.bas) puts the disc's files:
;; main.asm assembles them for these places, pack.asm packs them for them
;; ===========================================================================

CAR_BLOB    EQU #1900                   ; CARn.BIN (past the loader's program,
                                        ; its MEMORY above: disc/country.bas;
                                        ; the hidden lines of buffer 1's block 3
                                        ; are below it too: boot_car puts code
                                        ; there)
SOUND_BLOB  EQU #98C0                   ; SOUND.BIN: buffer 0's lines 179 on in
                                        ; its fourth 2K block: past the car's
                                        ; records' hidden lines, before fragment 11
RACE_BLOB   EQU #A0C0                   ; RACE.BIN: buffer 0's lines 180 on in
                                        ; its fifth 2K block: the same

;; Each file is on the disc packed (pack.asm): the loader loads it at
;; PACK_LOW - while the select screen shows at #C000 - or at PACK_HIGH - once
;; the screen is black, for the car's file and BOOT.BIN, which would reach the
;; sound's and the race's - and CALLs UNPACK_LOW or UNPACK_HIGH, which
;; SELECT.BIN put at UNPACK: past RACE.BIN's place, before the 6128's
;; characters 240-255 (#A67C, the loader's letters)
PACK_LOW    EQU #8000
PACK_HIGH   EQU #C000
UNPACK      EQU #A600
UNPACK_LOW  EQU UNPACK                  ; (disc/country.bas: CALL &A600)
UNPACK_HIGH EQU UNPACK+5                ; (... CALL &A605)
