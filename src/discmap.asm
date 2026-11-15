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
;; SELECT.BIN put at UNPACK: under #4000, past where CARn.BIN unpacks
;; (zx0check.py), where nothing else goes while the loader runs. Not at the
;; top of memory: the ROMs' workspace is there, and under it the characters
;; 240-255 (the loader's letters) - at #A67C on a 6128, but an M4 board beside
;; AMSDOS takes 128 bytes more, and SYMBOL wrote the letters over the
;; unpacker when it was at #A600: the loader died once the car was picked
;; (2026-11-15). Nothing the loader puts at PACK_LOW or past it goes past
;; MEM_TOP, those characters' place on such a 6128 (HIMEM #A5FB).
PACK_LOW    EQU #8000
PACK_HIGH   EQU #C000
UNPACK      EQU #3F80
UNPACK_LOW  EQU UNPACK                  ; (disc/country.bas: CALL &3F80)
UNPACK_HIGH EQU UNPACK+5                ; (... CALL &3F85)
MEM_TOP     EQU #A5FC

;; SPIN.BIN: the cars turning on the select screen (spin.asm), loaded after
;; the turning's streams (SPINA-E.BIN, into banks 4-7 and #4000) and before
;; the menu; past what PACK_LOW's files take, before MEM_TOP; the game's files
;; go over it (and over the streams) once the car is picked and it is stopped
SPIN_CODE   EQU #9C00
