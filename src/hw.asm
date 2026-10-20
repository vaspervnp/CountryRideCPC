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
;;           each 2K block, buffer 1's HUD1_OFF bytes on.
;;   sky     11 rows: the dithered sky and the mountains. Page 3, one copy for
;;           both buffers, in a ring: the CRTC's address wraps every 1024
;;           characters (2K) when MA10/MA11 are 0, so moving the start address
;;           a character scrolls the sky a word (4 pixels) for good, and only
;;           the column that comes in has to be written (ring_turn).
;;   road    14 rows, lines 160-271: three lines of ground, then the road.
;;           Page 2 (buffer 0, #8000) or page 0 (buffer 1, #0000), as the
;;           road engine in banks 4 and 5 needs: those two are mapped in every
;;           configuration the game uses. The rest of each 2K block holds the
;;           common fragments.
;;
;; The Z80 sees page 1 at #4000 with RAM_C1, page 3 there with RAM_C3.
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
;; The horizon drops with the road: when a crest hides the far road, the sky
;; part starts lower, by as many lines as the road's top has come down, under
;; border in the HUD's navy; it is followed by border in the ground's green
;; down to the character row the top of the road is in, where the road part
;; starts. So the band of ground between the mountains and the road always
;; has 11 lines, and every line of the road part is where it always is in its
;; buffer: nothing that draws the road needs to know. For a drop of d lines
;; (0..18):
;;
;;   HUD part    rows 0-6, then 8 + d lines of border: row 7 (navy anyway)
;;               and d/8 more rows that R6 keeps from being displayed, then
;;               d mod 8 R5 lines.
;;   sky part    rows 0-10 of the ring, then the green border: a row if it
;;               is 8 lines or more, then R5 lines for the rest.
;;   road part   from line (163 + d) rounded down to a row: 20 + q, q = 0..2;
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
;; its lines).
HUD_ROWS    EQU HUD_H/8
SKY_ROWS    EQU (BLOCK_BOTTOM-HUD_H)/8
ROAD_ROW    EQU ROAD_AREA_Y/8
TOTAL_ROWS  EQU CRTC_R4+1
IRQ_LOST    EQU #80         ; irq_phase while not in step with the frame

;; --- Common memory ----------------------------------------------------------
;; Each 2K block of pages 0 and 2 holds one raster line of 14 bottom-half
;; character rows - 1344 bytes - and leaves 704 bytes at #x540-#x7FF. Pages
;; 0 and 2 are mapped in every configuration above, so these 16 fragments are
;; the only RAM that the game code, the road engine and the interrupt handler
;; can all see. They hold everything that has to be shared. The others in
;; page 2 (#8D40 ... #BD40) are free.
FRAG_LEN    EQU #2C0
FRAG0       EQU #0540       ; variables, IM 2 table, interrupt handler
FRAG1       EQU #0D40       ; trampolines, stack
FRAG2       EQU #1540       ; road_draw and the grass blocks
FRAG3       EQU #1D40       ; line list, buffer 0
FRAG4       EQU #2540       ; line list, buffer 1
FRAG5       EQU #2D40       ; (free: the road templates are in banks 4 and 5)
FRAG6       EQU #3540       ; (free)
FRAG7       EQU #3D40       ; road_init, road_project
FRAG8       EQU #8540       ; (page 2) what the far road lines show

IM2_TABLE   EQU #0600       ; 257 bytes of IM2_VEC
IM2_VEC     EQU #07         ; ... so the vector is #0707
STACK_TOP   EQU #1000

;; set the RAM configuration; destroys BC
MACRO SET_RAM cfg
    ld bc,#7F00+{cfg}
    out (c),c
MEND
