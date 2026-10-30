;; ===========================================================================
;; hw.asm - Amstrad CPC 6128 hardware: ports, CRTC values, RAM layout.
;;
;; The whole memory plan is here, and the split frame.
;; ===========================================================================

;; --- Gate Array (port #7Fxx) -----------------------------------------------
GA_PORT     EQU #7F
GA_MODE0    EQU #8C         ; mode 0, upper and lower ROM disabled

;; RAM configurations (#C0 + n). The CRTC always reads the base 64K; these
;; only change what the Z80 sees.
;;
;;            #0000    #4000    #8000    #C000
;;   C1       page 0   page 1   page 2   bank 7
;;   C3       page 0   page 3   page 2   bank 7
;;   C4       page 0   bank 4   page 2   page 3
;;   C5       page 0   bank 5   page 2   page 3
;;   C6       page 0   bank 6   page 2   page 3
RAM_C0      EQU #C0
RAM_C1      EQU #C1         ; game code + buffer 0's top half at #4000
RAM_C3      EQU #C3         ; game code + buffer 1's top half at #4000
RAM_C4      EQU #C4         ; band A road templates and cores at #4000
RAM_C5      EQU #C5         ; band B road cores and templates at #4000
RAM_C6      EQU #C6         ; road rows and hill tables at #4000

;; --- CRTC (select #BCxx, write #BDxx) ---------------------------------------
;; 48 characters (96 bytes, 192 mode 0 pixels) by 34 rows of 8 lines = 272
;; lines, in the usual 64 us x 312 line frame.
CRTC_R0     EQU 63          ; horizontal total
CRTC_R1     EQU 48          ; horizontal displayed
CRTC_R2     EQU 50          ; HSYNC position
CRTC_R3     EQU #8E         ; VSYNC 8 lines, HSYNC 14 characters
CRTC_R4     EQU 38          ; vertical total: 39 rows
CRTC_R5     EQU 0
CRTC_R6     EQU 34          ; vertical displayed: 34 rows = 272 lines
CRTC_R7     EQU 34          ; VSYNC position
CRTC_R9     EQU 7           ; 8 lines per character row

;; --- The screen -------------------------------------------------------------
;; The picture is three parts, each in its own memory, which the CRTC shows
;; one after the other: the frame is split into three CRTC frames by
;; reprogramming it as the beam goes down (raster ruptures). Each part has its
;; own start address, row count and R5 lines.
;;
;;   HUD     8 rows, page 1. One copy per buffer: buffer 0's at the start of
;;           each 2K block, buffer 1's HUD1_OFF bytes on. Then navy border
;;           down to the sky: the sky, the mountains and the road take the
;;           screen's bottom half.
;;   sky     6 rows from line SKY_Y (132): the dithered sky and the
;;           mountains. Page 3, one copy for both buffers, in a ring: the
;;           CRTC's address wraps every 1024 characters (2K) when MA10/MA11
;;           are 0, so moving the start address a character scrolls the sky
;;           a word (4 pixels) for good, and only the column that comes in has
;;           to be written (ring_turn).
;;   road    from line 184 (the row the road's top is in) to 271: four lines
;;           of ground, the road to line ROAD_END - 1 (267), then four black
;;           lines. Its memory is 14 rows from line 160 (ROAD_AREA_Y): the
;;           first three never shown. Page 2 (buffer 0, #8000) or page 0
;;           (buffer 1, #0000), as the road engine in banks 4 and 5 needs:
;;           those two are mapped in every configuration the game uses. The
;;           rest of each 2K block holds the common fragments.
;;
;; The Z80 sees page 1 at #4000 with RAM_C1, page 3 there with RAM_C3. The
;; HUDs take the first #600 bytes of each 2K block of page 1 - the HUD part
;; shows seven of a HUD's eight character rows, and the eighth (#x2A0 and
;; #x5A0, 96 bytes each) holds code of the car's views on hills
;; (tools/mkbush.py HUD_ROW7); the rest of each block (#x600-#x7FF) is the
;; bush sprites' code (bushcode.asm), which runs with RAM_C1.
HUD_MA0     EQU #1000       ; CRTC start of buffer 0's HUD: page 1
HUD1_OFF    EQU HUD_ROWS*96 ; buffer 1's HUD, bytes on
HUD_MA1     EQU HUD_MA0+HUD1_OFF/2
RING_MA     EQU #3000       ; the sky ring: page 3
RING_WORDS  EQU 1024
ROAD_MA0    EQU #2000       ; buffer 0's road part: page 2
ROAD_MA1    EQU #0000       ; buffer 1's: page 0
HUD_BASE    EQU #4000       ; CPU address of line 0, RAM_C1, buffer 0
RING_BASE   EQU #4000       ; CPU address of the ring, RAM_C3
BOT0_BASE   EQU #8000       ; CPU address of line 160, buffer 0
BOT1_BASE   EQU #0000       ; CPU address of line 160, buffer 1

;; --- The split frame -----------------------------------------------------------
;; The sky part starts at line SKY_Y, under border in the HUD's navy, and the
;; horizon drops with the road: when a crest hides the far road, the sky
;; part starts lower still, by up to twice as many lines as the road's top
;; has come down (scene.sky_drop); it is followed by border in the ground's
;; green down to the character row the top of the road is in, where the
;; road part starts. So the band of ground between the mountains and the
;; road narrows from 8 lines to 3-7, and every line of the road part is
;; where it always is in its buffer: nothing that draws the road needs to
;; know. For a drop of d lines (0..14), s = SKY_Y - HUD_H + the sky's drop
;; (68..88, sky_drops):
;;
;;   HUD part    rows 0-6, then 8 + s lines of border: row 7 (navy anyway)
;;               and s/8 more rows that R6 keeps from being displayed, then
;;               s mod 8 R5 lines.
;;   sky part    rows 0-5 of the ring, then the green border: a row if it
;;               is 8 lines or more, then R5 lines for the rest.
;;   road part   from line (188 + d) rounded down to a row: 23 + q, q = 0..2;
;;               VSYNC at line 272 as always, then the rest of the 312 lines.
;;
;; CRTCs differ in the R5 lines: some count them as a row past R4 and stop
;; displaying if that is R6; others (CRTC 1, and Retro Virtual Machine) leave
;; the display as the last row left it and show the row after it. So R5
;; lines are kept under 8 (a row), the HUD part's are always after a border
;; row, and the row after the sky part's - in the ring - is kept green, the
;; colour of the border there.
;;
;; The interrupt handler (common.asm) does the writing, at the Gate Array's
;; interrupts, which come at fixed lines - 2 after the VSYNC starts, then
;; every 52: ~274, 14, 66, 118, 170, 222. Each register is written with more
;; than five lines to spare after the CRTC last looked at it for the part
;; before and before it looks at it for its own part; R12/R13 during the part
;; before, after that part's first row (a type 1 CRTC reloads them on each of
;; its lines). The sky part's size waits for line ~170, in the sky part: the
;; HUD part's rows run past it till then.
HUD_ROWS    EQU HUD_H/8
SKY_ROWS    EQU (BLOCK_BOTTOM-SKY_Y)/8
ROAD_ROW    EQU ROAD_AREA_Y/8
TOTAL_ROWS  EQU CRTC_R4+1

;; --- Common memory ----------------------------------------------------------
;; Each 2K block of pages 0 and 2 holds one raster line of 14 bottom-half
;; character rows - 1344 bytes - and leaves 704 bytes at #x540-#x7FF. Pages
;; 0 and 2 are mapped in every configuration above, so these 16 fragments are
;; the only RAM that the game code, the road engine and the interrupt handler
;; can all see. They hold everything that has to be shared: fragments 0-7 in
;; page 0, 8-15 in page 2.
FRAG_LEN    EQU #2C0
FRAG0       EQU #0540       ; variables, interrupt handler, prop_draw's lines
FRAG1       EQU #0D40       ; trampolines, stack
FRAG2       EQU #1540       ; road_draw and the grass blocks
FRAG3       EQU #1D40       ; line list, buffer 0
FRAG4       EQU #2540       ; line list, buffer 1
FRAG5       EQU #2D40       ; road_init, rp_near_cmp
FRAG6       EQU #3540       ; the road cache's state and common code (cache.asm)
FRAG7       EQU #3D40       ; road_project
FRAG8       EQU #8540       ; page 2: the bush tables and sprites (bushdata.asm)
FRAG15      EQU #BD40       ; ... up to here
FRAG_COUNT  EQU 16

IM1_JP      EQU #0038       ; IM 1's JP isr: buffer 1's line 160, hidden
                            ; (tools/mkbush.py HILL_RUNS leaves it out)
STACK_TOP   EQU #1000

;; --- The sound (sound.asm, SOUND.BIN) -----------------------------------------
;; What the interrupt runs and reads, in the road parts' lines 173-178, both
;; buffers': pages 0 and 2, so mapped whatever the configuration. Never
;; shown, and nothing draws there: the hill views' code ends at line 172,
;; a bush's top is on line 183 at the highest, a prop's on 179 (both
;; checked by tools/mkbush.py), the traffic's and the road's are lower.
;; Page 0's are where the loader loads CARn.BIN: boot.asm copies the sound
;; in after the car's records. What the main loop runs (RAM_C1: sndgame.asm,
;; in RACE.BIN) goes in four of the HUDs' eighth character rows - never
;; shown, and the hill views leave them out: fragments 2-7 are stored there
;; until boot_car is done with them, and boot_car itself in the fourth -
;; and in P10.
SND_PIECE   EQU 96          ; bytes: a line (P11: the race's, below)
SND_P0      EQU BOT0_BASE+5*#800+96     ; line 173, buffer 0
SND_P1      EQU BOT0_BASE+6*#800+96     ; 174
SND_P2      EQU BOT0_BASE+7*#800+96     ; 175
SND_P3      EQU BOT0_BASE+0*#800+192    ; 176
SND_P4      EQU BOT0_BASE+1*#800+192    ; 177
SND_P5      EQU BOT0_BASE+2*#800+192    ; 178
SND_P6      EQU SND_P0-BOT0_BASE+BOT1_BASE  ; ... buffer 1's
SND_P7      EQU SND_P1-BOT0_BASE+BOT1_BASE
SND_P8      EQU SND_P2-BOT0_BASE+BOT1_BASE
SND_P9      EQU SND_P3-BOT0_BASE+BOT1_BASE
SND_P10     EQU SND_P4-BOT0_BASE+BOT1_BASE
SND_P11     EQU SND_P5-BOT0_BASE+BOT1_BASE
SND_M0      EQU HUD_BASE+1*#800+#2A0    ; page 1: buffer 0's HUD's eighth
SND_M1      EQU HUD_BASE+2*#800+#2A0    ; row, blocks 1-3, and buffer 1's
SND_M2      EQU HUD_BASE+3*#800+#2A0    ; in block 1 (mkbush.py HUD_ROW7
SND_M3      EQU HUD_BASE+1*#800+#5A0    ; leaves them out)

;; --- The race's extras (race.asm, RACE.BIN) -----------------------------------
;; The pause and the best times, run by the main loop (RAM_C1) and put in
;; place as the sound is: in hidden lines of buffer 1 nothing else has -
;; 164 and 172 (one after the other: mkbush.py TRAF_HIDDEN leaves them out),
;; 167, and 178, the sound's twelfth piece.
RACE_P0     EQU BOT1_BASE+4*#800        ; lines 164 and 172: 192 bytes
RACE_P1     EQU BOT1_BASE+7*#800        ; line 167
RACE_P2     EQU SND_P11                 ; line 178
JUMP_P0     EQU SND_P1                  ; line 174: the car thrown up
                                        ; (jump.asm; and the free ends of
                                        ; sndgame.asm's pieces)

;; a record of SOUND.BIN or RACE.BIN (boot.asm boot_blob): its code ORG'd
;; where it goes, `size` bytes there at most
MACRO REC_BEGIN at
    defw {at},rec_{at}_end-{at}
rec_{at}_ph
    ORG {at},rec_{at}_ph
MEND
MACRO REC_END at,size
rec_{at}_end
    ASSERT rec_{at}_end <= {at}+{size}
    ORG rec_{at}_ph+rec_{at}_end-{at}
MEND
;; ... a record `name` into what another one has left: from `at` (the other's
;; rec_..._end) up to `limit`
MACRO REC_TAIL name,at
    defw {at},rec_{name}_end-({at})
rec_{name}_ph
    ORG {at},rec_{name}_ph
MEND
MACRO REC_TAIL_END name,at,limit
rec_{name}_end
    ASSERT rec_{name}_end <= {limit}
    ORG rec_{name}_ph+rec_{name}_end-({at})
MEND

;; --- Bank 7, past the game's code (RAM_C1, RAM_C3) ---------------------------
;; The track a few entries ahead of the camera, per entry (zcam / 32) mod 64:
;; its curve level and its hill (course.asm). Then from CAR_HILL_ORG the
;; car's views on hills (CARn.BIN).
CURVE_RING  EQU #F000
HILL_RING   EQU CURVE_RING+64
RING_MASK   EQU 63

;; set the RAM configuration; destroys BC
MACRO SET_RAM cfg
    ld bc,#7F00+{cfg}
    out (c),c
MEND
