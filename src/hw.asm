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
RAM_C4      EQU #C4         ; road engine (band A cores) at #4000
RAM_C5      EQU #C5         ; band B road cores at #4000
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

;; --- The two screens --------------------------------------------------------
;; A 272-line overscan screen needs 26 KB and so two 16K pages: the CRTC is
;; started with MA10 = MA11 = 1, so when the character counter passes the end
;; of a 2K block it carries into MA12 and the picture continues in the next
;; page. Starting 64 characters (128 bytes) into the page puts exactly 20
;; character rows in the first page and the other 14 in the next one.
;;
;;   buffer 0: R12/R13 = #1C40 - rows 0-19 in page 1, rows 20-33 in page 2
;;   buffer 1: R12/R13 = #3C40 - rows 0-19 in page 3, rows 20-33 in page 0
;;
;; Lines 0-159 (HUD, sky, mountains) are the "top half"; lines 160-271 (the
;; ground and the road) the "bottom half". With RAM_C1 the Z80 sees buffer 0's top half at
;; #4080, with RAM_C3 it sees buffer 1's there - so drawing code for the top
;; half never needs to know which buffer it is drawing into. The bottom halves
;; are at #8000 (buffer 0) and #0000 (buffer 1) in every configuration the
;; game uses, which is what lets the road engine run from banks 4 and 5.
BUF0_R12    EQU #1C
BUF1_R12    EQU #3C
BUF_R13     EQU #40
TOP_BASE    EQU #4080       ; CPU address of line 0 (either buffer)
BOT0_BASE   EQU #8000       ; CPU address of line 160, buffer 0
BOT1_BASE   EQU #0000       ; CPU address of line 160, buffer 1
TOP_LINES   EQU 160

;; --- The split frame -----------------------------------------------------------
;; The horizon drops with the road: when a crest hides the far road, the sky
;; and the mountains move down the screen as far as the road's top does. They
;; are not redrawn for it. Each buffer always holds the same picture -
;;
;;   lines   0- 63  HUD                      rows  0- 7
;;   lines  64-151  sky and mountains        rows  8-18
;;   lines 152-162  ground
;;   lines 163-271  road
;;
;; - and the CRTC is reprogrammed three times a frame (raster ruptures), so
;; that each frame is three CRTC frames with their own start address, rows
;; and R5 lines. For a drop of d lines (0..18) and q = d/8 rounded up:
;;
;;   HUD part    rows 0-7 of the buffer, then d R5 lines of border - the
;;               HUD's navy. R6 is the row count, so the R5 lines, which
;;               are one row past the last, are not displayed.
;;   sky part    rows 8-18, then 8q - d R5 lines of border in the ground's
;;               green, which bring the road part back onto a character
;;               row of the screen.
;;   road part   rows 19+q to 33 shown, VSYNC at row 34 (line 272) as
;;               always, then the rest of the 312 lines.
;;
;; On the screen the sky and mountains are then d lines down, the ground band
;; below them always 11 lines (8q - d lines of border, then the buffer's own
;; ground lines), and every line from the road part on is where it always is
;; in the buffer, so nothing that draws the road needs to know about it.
;;
;; The interrupt handler (common.asm) does the writing. Each register is
;; written while the part it is for is running and before the CRTC looks at
;; it, with ten lines or more to spare; R12/R13 during the part before
;; (after that part's first row, which a type 1 CRTC reloads them on).
HUD_ROWS    EQU HUD_H/8
SKY_ROWS    EQU (BLOCK_BOTTOM-HUD_H)/8
BLOCK_ROW   EQU BLOCK_BOTTOM/8
TOTAL_ROWS  EQU CRTC_R4+1
IRQ_LOST    EQU #80         ; irq_phase while not in step with the frame

;; --- Common memory ----------------------------------------------------------
;; Each 2K block of pages 0 and 2 holds one raster line of 14 bottom-half
;; character rows - 1344 bytes - and leaves 704 bytes at #x540-#x7FF. Pages
;; 0 and 2 are mapped in every configuration above, so these 16 fragments are
;; the only RAM that the game code, the road engine and the interrupt handler
;; can all see. They hold everything that has to be shared.
FRAG_LEN    EQU #2C0
FRAG0       EQU #0540       ; variables, IM 2 table, interrupt handler
FRAG1       EQU #0D40       ; trampolines, stack
FRAG2       EQU #1540       ; road_draw and the grass blocks
FRAG3       EQU #1D40       ; line list, buffer 0
FRAG4       EQU #2540       ; line list, buffer 1
FRAG5       EQU #2D40       ; road templates, band 0
FRAG6       EQU #3540       ; road templates, band 1
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
