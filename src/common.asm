;; ===========================================================================
;; common.asm - everything that lives in the common memory fragments.
;;
;; These 704-byte pieces of pages 0 and 2 are the only RAM that is mapped in
;; every configuration the game uses (see hw.asm), so this is where the
;; variables shared between the game code (bank 7) and the road engine
;; (banks 4 and 5) live, along with the interrupt handler, the stack and the
;; part of the road renderer that has to keep running while the banks switch
;; under it. boot.asm copies each fragment into place.
;;
;; Each fragment is assembled at the address it runs at and stored, one
;; after the other, in the boot file (ORG run,store).
;; ===========================================================================

;; ===========================================================================
;; Fragment 0: variables, the IM 2 table, the interrupt handler
;; ===========================================================================
    ORG FRAG0,FRAG_STORE+0*FRAG_LEN
frag0_start

;; --- frame timing -----------------------------------------------------------
vbl_count   defb 0          ; +1 at every VSYNC (50 Hz)
lost_count  defb 0          ; interrupts since the frame was lost track of
flip_req    defb 0          ; buffer + 1 to show from the next VSYNC, 0 = none
flip_drop   defb 0          ; ... how far its horizon is down
flip_head   defb 0          ; ... and where its sky looks (words right)
flip_last   defb 0          ; vbl_count when the last flip happened
front_buf   defb 0          ; buffer being shown (0/1)

;; --- the split of the frame being shown (see rup_frame) ---------------------
rup_buf     defb 0          ; buffer shown
rup_drop    defb 0          ; lines the horizon is down
rup_r4a     defb HUD_ROWS-1 ; HUD part: rows - 1, its border rows too
rup_r5a     defb 0          ; HUD part: R5 lines
rup_late    defb 0          ; HUD part has border rows: the sky part's size
                            ; waits for line ~118
rup_r4b     defb SKY_ROWS   ; sky part: rows - 1, a border row too (the
                            ; values here are drop 0's: rup_frame works
                            ; them out only when a picture is shown)
rup_r5b     defb 0          ; sky part: R5 lines
rup_r4c     defb TOTAL_ROWS-ROAD_ROW-1 ; road part: rows - 1
rup_r6c     defb CRTC_R7-ROAD_ROW      ; road part: R6 and R7
rup_c       defw ROAD_MA0   ; road part: start (R13, R12)

;; --- the sky ring (hw.asm) ------------------------------------------------------
ring_w0     defw 0          ; the ring character the sky part starts at
ring_head   defb 0          ; where the sky looks: words right, 0..PANO_WORDS-1

;; --- road engine inputs ---------------------------------------------------
zcam        defw 0          ; camera depth, 16 depth units = one stripe
hill        defb 0          ; signed: + crest ahead, - the road rises ahead
curve       defb 0          ; signed curve level, -CURVE_K..CURVE_K: + right
road_curve  defb 0          ; ... the level the road is drawn with
road_buf    defb 0          ; buffer road_project/road_draw work on

;; --- road_draw state ---------------------------------------------------------
line_ptr    defw 0          ; next line list entry
rd_save_sp  defw 0

;; --- profiling (read by tools/run.py) ---------------------------------------
frames_drawn defw 0         ; pictures completed
frames_late  defw 0         ; pictures that took more than two VSYNCs
frame_vbls   defb 0         ; VSYNCs the last picture took

    ASSERT $ <= IM2_TABLE
    defs IM2_TABLE-$,0

;; --- IM 2 vector table -------------------------------------------------------
;; The CPC puts no defined byte on the bus when it acknowledges an interrupt,
;; so all 257 bytes are the same and the vector is #0707 whatever it reads.
    defs 257,IM2_VEC
    ASSERT $ <= IM2_VEC*#101
    defs IM2_VEC*#101-$,0

;; ---------------------------------------------------------------------------
;; isr - six interrupts a frame, one of them inside VSYNC.
;;
;; The one inside VSYNC is the top of the frame: vbl_count ticks, and a
;; pending flip is made. The flip waits for two VSYNCs since the last one,
;; which is what holds the game to 25 pictures a second when it could draw
;; faster.
;;
;; The frame is split into three by raster ruptures (hw.asm), and each
;; interrupt sets the CRTC up for the parts coming next. The Gate Array's
;; interrupts come at fixed lines - 2 after the VSYNC starts and every 52
;; after that - so each knows where the beam is, and each handler sets
;; isr_next to the next one's. Only the VSYNC's handler checks that it is
;; in VSYNC (PPI port B); if not, the frame is lost track of: a plain frame
;; (rup_safe) until the next VSYNC, irq_lost counting a frame every six.
;;
;; The road renderer runs with interrupts off while SP points into the
;; screen, and turns them on for a moment between lines, so an interrupt can
;; arrive up to one road line late (~0.3 ms, five scanlines). Every CRTC
;; write here has more slack than that. In case the VSYNC is ever missed, six
;; interrupts without one count as a frame too.
;; ---------------------------------------------------------------------------
isr
    ld (isr_sp+1),sp            ; the road renderer may have SP in its line
    ld sp,isr_stack             ; list: only the return address goes there
    push af
    push bc
    push hl
isr_next
    jp irq_lost                 ; (self-modified: this interrupt's handler)
isr_out
    pop hl
    pop bc
    pop af
isr_sp
    ld sp,0                     ; (self-modified)
    ei
    reti

    defs 40,0
isr_stack

;; ---------------------------------------------------------------------------
;; rup_frame - work out the frame's split from the drop of the buffer it
;; shows, and start its HUD part. (Here for room; see the ruptures in
;; fragment 1.)
;; ---------------------------------------------------------------------------
rup_frame
    ld a,(rup_drop)
    ld c,a
    and 7
    ld (rup_r5a),a              ; HUD part: drop mod 8 R5 lines ...
    ld a,c
    rrca
    rrca
    rrca
    and #1F
    ld (rup_late),a             ; ... after drop / 8 border rows
    add a,HUD_ROWS-1
    ld (rup_r4a),a
    ld a,c                      ; the road part: from the row the top of the
    add a,ROAD_Y                ; road is in
    rrca
    rrca
    rrca
    and #1F
    ld b,a                      ; B = its row, ROAD_ROW..ROAD_ROW+2
    add a,a
    add a,a
    add a,a
    sub BLOCK_BOTTOM
    sub c                       ; green border lines after the sky, 4..11
    ld l,SKY_ROWS-1
    cp 8
    jr c,rup_frame_r5b
    sub 8                       ; a row of it, then R5 lines
    inc l
rup_frame_r5b
    ld (rup_r5b),a
    ld a,l
    ld (rup_r4b),a
    ld a,TOTAL_ROWS-1
    sub b
    ld (rup_r4c),a
    ld a,CRTC_R7
    sub b
    ld (rup_r6c),a
    ld a,b                      ; start: (row - ROAD_ROW) * 48 into the part
    sub ROAD_ROW
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld b,h
    ld c,l
    add hl,hl
    add hl,bc
    ld bc,ROAD_MA0
    ld a,(rup_buf)
    or a
    jr z,rup_frame_road
    ld bc,ROAD_MA1
rup_frame_road
    add hl,bc
    ld (rup_c),hl

rup_frame_hud
    ld a,(rup_buf)              ; the HUD part starts with the buffer's HUD
    or a
    ld hl,HUD_MA0
    jr z,rup_frame_hud_ma
    ld hl,HUD_MA1
rup_frame_hud_ma
    ld bc,#BC00+12
    out (c),c
    ld b,#BD
    out (c),h
    ld bc,#BC00+13
    out (c),c
    ld b,#BD
    out (c),l
    ld bc,#7F10                 ; navy border for the lines above the sky
    out (c),c
    ld c,BORDER_TOP_HW
    out (c),c
    ret

frag0_end
    ASSERT frag0_end <= FRAG0+FRAG_LEN

;; ===========================================================================
;; Fragment 1: trampolines and the stack
;; ===========================================================================
    ORG FRAG1,FRAG_STORE+1*FRAG_LEN
frag1_start

;; ---------------------------------------------------------------------------
;; road_frame - project and draw the road into buffer (road_buf).
;; Called from the game code in bank 7 with RAM_C1; returns with RAM_C1.
;; Bank 7 is not mapped while the road engine runs, so this has to live here.
;; ---------------------------------------------------------------------------
road_frame
    SET_RAM RAM_C6
    call road_project
    call road_draw
    SET_RAM RAM_C1
    ret

;; ---------------------------------------------------------------------------
;; road_reset - forget what the road looked like (nothing is skipped).
;; ---------------------------------------------------------------------------
road_reset
    SET_RAM RAM_C6
    call road_init
    SET_RAM RAM_C1
    ret

;; ---------------------------------------------------------------------------
;; The raster ruptures (hw.asm has the layout): the interrupt handlers,
;; entered from isr with AF, BC and HL saved, which they may use; each ends
;; with JP isr_out.
;; ---------------------------------------------------------------------------
MACRO NEXT_IRQ handler
    ld hl,{handler}
    ld (isr_next+1),hl
MEND

;; not in step with the frame: wait for a VSYNC, counting a frame every six
irq_lost
    ld b,#F5                    ; PPI port B: bit 0 = VSYNC
    in a,(c)
    rra
    jr c,irq_vsync_in           ; from here on in step
    ld hl,lost_count
    inc (hl)
    ld a,(hl)
    cp 6
    jp c,isr_out
    ld (hl),0
    ld hl,vbl_count             ; so the game goes on
    inc (hl)
    jp isr_out

;; line ~274, in VSYNC: the top of the frame
irq_vsync
    ld b,#F5
    in a,(c)
    rra
    jr c,irq_vsync_in
    call rup_safe               ; no VSYNC where there should be one: the
    xor a                       ; frame is not what it was set up to be
    ld (lost_count),a
    NEXT_IRQ irq_lost
    jp isr_out
irq_vsync_in
    NEXT_IRQ irq_hud
    ld hl,vbl_count
    inc (hl)
    call rup_flip
    jp isr_out

;; HL = vbl_count: a pending flip, if two frames have gone since the last
rup_flip
    ld a,(flip_req)             ; a picture waiting, and two frames since the
    or a                        ; last: show it from this frame on
    jp z,rup_frame_hud          ; (else the split stays as it was)
    ld a,(hl)
    ld hl,flip_last
    sub (hl)
    cp 2
    jp c,rup_frame_hud
    ld a,(vbl_count)
    ld (hl),a
    ld a,(flip_req)
    dec a
    ld (rup_buf),a
    ld a,(flip_drop)
    ld (rup_drop),a
    xor a
    ld (flip_req),a
    call rup_frame              ; the HUD part's start first: it is near
    jp ring_turn                ; then turn the sky the new picture looks at

;; rup_safe - one plain full frame, whatever the beam is doing
rup_safe
    ld hl,rup_safe_regs
rup_safe_reg
    ld a,(hl)
    cp #FF
    ret z
    ld b,#BC
    out (c),a
    inc hl
    ld a,(hl)
    inc hl
    ld b,#BD
    out (c),a
    jr rup_safe_reg
rup_safe_regs
    defb 4,CRTC_R4, 5,0, 6,CRTC_R6, 7,CRTC_R7, #FF

;; CRTC register A = (HL)
MACRO CRTC_HL reg
    ld bc,#BC00+{reg}
    out (c),c
    ld a,(hl)
    ld b,#BD
    out (c),a
MEND
;; CRTC register = constant
MACRO CRTC_N reg,val
    ld bc,#BC00+{reg}
    out (c),c
    ld bc,#BD00+{val}
    out (c),c
MEND

    ASSERT HUD_ROWS*8 == HUD_H
    ASSERT ROAD_ROW*8 == ROAD_AREA_Y

;; line ~14, in the HUD part: its size, no VSYNC; where the sky part starts
;; in the ring
irq_hud
    NEXT_IRQ irq_sky
    ld hl,rup_r4a
    CRTC_HL 4
    ld hl,rup_r5a
    CRTC_HL 5
    CRTC_N 6,HUD_ROWS-1         ; the HUD's last row (navy) on is border, so
    CRTC_N 7,#7F                ; the R5 lines come after a border row
    ld hl,(ring_w0)
    ld bc,#BC00+12
    out (c),c
    ld a,h
    or hi(RING_MA)
    ld b,#BD
    out (c),a
    ld bc,#BC00+13
    out (c),c
    ld b,#BD
    out (c),l
    jp isr_out

;; line ~66, the HUD part's display over: the sky part's rows, and its size
;; - unless more border rows follow
irq_sky
    NEXT_IRQ irq_road
    CRTC_N 6,SKY_ROWS
    ld a,(rup_late)
    or a
    call z,rup_sky_size
    jp isr_out
rup_sky_size
    ld hl,rup_r4b
    CRTC_HL 4
    ret

;; line ~118, in the sky part: its size if not done yet, its R5 lines, where
;; the road part starts, the border below the mountains
irq_road
    NEXT_IRQ irq_idle
    ld a,(rup_late)
    or a
    call nz,rup_sky_size
    ld hl,rup_r5b
    CRTC_HL 5
    ld hl,rup_c+1
    CRTC_HL 12
    ld hl,rup_c
    CRTC_HL 13
    ld bc,#7F10
    out (c),c
    ld c,BORDER_LOW_HW
    out (c),c
    jp isr_out

;; line ~170: nothing to do
irq_idle
    NEXT_IRQ irq_size
    jp isr_out

;; line ~222, in the road part: its size, and the VSYNC at line 272
irq_size
    NEXT_IRQ irq_vsync
    ld hl,rup_r4c
    CRTC_HL 4
    CRTC_N 5,0
    ld hl,rup_r6c
    CRTC_HL 6
    CRTC_HL 7
    jp isr_out

frag1_end
    ASSERT frag1_end <= STACK_TOP-256      ; leave the stack 256 bytes

;; ===========================================================================
;; Fragment 2: road_draw
;; ===========================================================================
    ORG FRAG2,FRAG_STORE+2*FRAG_LEN
frag2_start

;; ---------------------------------------------------------------------------
;; road_draw - draw the lines in the line list of (road_buf).
;;
;; A line list entry is two words: where SP starts for that line (the end of
;; the line in the screen) and a template - three or four more words, popped
;; in turn (tools/mkroad.py makes them, one set per curve level):
;;
;;   IY      where to enter the road core (part-way in if it hangs off the
;;           right of the screen)
;;   IX      where to enter the left grass block (how much grass is left)
;;   AF      A = low byte of the right grass block entry; F: Z = no patch
;;   patch   only if NZ: the core hangs off the left of the screen, and this
;;           is the first byte of it that must not run: JP (HL) is written
;;           over it, and put back when the core leaves through it - IX then
;;           holds that byte, as there is no left grass
;;
;; A line then runs: right grass block (PUSH BC x n, main registers) ->
;; EXX/EX AF,AF' -> JP (IY) core (shadow registers: PUSH DE asphalt,
;; PUSH AF kerb, LD BC/PUSH BC anything else) -> EXX/EX AF,AF' -> JP (IX)
;; left grass block -> JP line_done_<band>. A patched core has no left grass
;; and leaves through JP (HL') = line_done_shadow_<band>, which puts the
;; patched byte back.
;;
;; Registers kept for the whole run:
;;   BC  = grass pair         DE' = asphalt pair     AF' = kerb pair
;;   HL' = line_done_shadow_<band>                   DE  = patch address
;; Band A's cores and templates are in bank 4 and band B's in bank 5, so
;; changing band changes the RAM configuration too - which is why this code
;; is here. Which bank a template is in is bit 13 of its address (TMPL_A,
;; TMPL_B), so the bank is switched before the template is read.
;;
;; Interrupts are off whenever SP points into the screen. Once per line they
;; get one instruction's chance, with SP just past the entry being read: an
;; interrupt then pushes its return address over that entry's template
;; pointer - which road_project writes afresh every frame - and isr moves to
;; its own stack before pushing anything else. (The line start words are
;; written once, by road_init, so nothing may ever land on those.)
;; ---------------------------------------------------------------------------
road_draw
    ld (rd_save_sp),sp
    di
    SET_RAM RAM_C4                      ; start in band A
    exx
    ld hl,line_done_shadow_a
    ld de,ROAD0_PAIR
    exx
    ld sp,kerb0_word
    pop af
    ex af,af'
    ld bc,GRASS0_PAIR
    ld hl,list0
    ld a,(road_buf)
    or a
    jr z,road_draw_go
    ld hl,list1
road_draw_go
    ld (line_ptr),hl
    jr line_done_a

;; --- band A -------------------------------------------------------------------
line_done_shadow_a
    exx
    ex af,af'
    ld a,ixl
    ld (de),a                           ; put back what the exit patch hid
line_done_a
    ld sp,(line_ptr)
    pop hl                              ; where SP starts on the screen
    pop de                              ; template
    ei                                  ; one instruction's chance for an
    ld (line_ptr),sp                    ; interrupt: its return address then
    di                                  ; lands on the template just read
    bit 5,d
    jp nz,to_band_b                     ; a band B template, in bank 5
line_go_a
    ex de,hl
    ld sp,hl
    pop iy
    pop ix
    pop af                              ; A = right grass entry, Z = no patch
    jr nz,line_patch
    ex de,hl                            ; HL = screen
    ld sp,hl
    ld l,a
    ld h,hi(rgrass)
    jp (hl)

;; the core hangs off the left: DE = screen, SP at the patch address
line_patch
    pop hl
    ld (hl),#E9                         ; JP (HL)
    ex de,hl                            ; DE = patch address, HL = screen
    ld sp,hl
    ld l,a
    ld h,hi(rgrass)
    jp (hl)

;; --- band B -------------------------------------------------------------------
line_done_shadow_b
    exx
    ex af,af'
    ld a,ixl
    ld (de),a
line_done_b
    ld sp,(line_ptr)
    pop hl
    pop de
    ei
    ld (line_ptr),sp
    di
    bit 5,d
    jp z,to_band_a
line_go_b
    ex de,hl
    ld sp,hl
    pop iy
    pop ix
    pop af
    jr nz,line_patch
    ex de,hl
    ld sp,hl
    ld l,a
    ld h,hi(rgrass)
    jp (hl)

;; --- switching band: registers, and the bank the cores are in -----------------
;; DE = template, HL = screen.
to_band_b
    ld bc,#7F00+RAM_C5
    out (c),c
    exx
    ld hl,line_done_shadow_b
    ld de,ROAD1_PAIR
    exx
    ld sp,kerb1_word
    pop af
    ex af,af'
    ld bc,GRASS1_PAIR
    jp line_go_b

to_band_a
    ld bc,#7F00+RAM_C4
    out (c),c
    exx
    ld hl,line_done_shadow_a
    ld de,ROAD0_PAIR
    exx
    ld sp,kerb0_word
    pop af
    ex af,af'
    ld bc,GRASS0_PAIR
    jp line_go_a

kerb0_word  defw KERB0_PAIR
kerb1_word  defw KERB1_PAIR

;; the core of a line with no road on it
empty_core
    exx
    ex af,af'
    jp (ix)

;; the template of the last entry sends the right grass block here
render_end
    exx
    ex af,af'
    ld sp,(rd_save_sp)
    ei
    ret

;; Templates for every frame, here because they are band A's (bit 13 of the
;; address clear) and must be read in either bank:
;; the end of the list
tmpl_end    defw render_end,lgrassa+48,#3040
;; a line that is already right: nothing pushed
tmpl_skip   defw 0,0,lo(rgrass_skip)*256+#40
    ASSERT (tmpl_end & #2000) == 0

    ASSERT $ <= #1700
    defs #1700-$,0

;; --- the grass blocks ----------------------------------------------------------
;; Right grass: entered at rgrass+n to push 48-n pairs; page aligned so the
;; template only has to carry the low byte.
rgrass
    REPEAT 48
    push bc
    REND
    exx
    ex af,af'
    jp (iy)
;; a line that is already right goes straight on to the next
rgrass_skip
    jp line_done_a

;; Left grass, one per band so it knows which line_done to go back to.
lgrassa
    REPEAT 48
    push bc
    REND
    jp line_done_a

lgrassb
    REPEAT 48
    push bc
    REND
    jp line_done_b

frag2_end
    ASSERT frag2_end <= FRAG2+FRAG_LEN

;; ===========================================================================
;; Fragments 3 and 4: the line lists. 32 bytes of guard in front for what an
;; interrupt pushes while the first entry is being read; then one entry per
;; road line, bottom line first; then the end.
;; ===========================================================================
LIST_GUARD  EQU 32
LIST_LEN    EQU (ROAD_LINES+1)*4

    ORG FRAG3,FRAG_STORE+3*FRAG_LEN
    defs LIST_GUARD,0
list0                                   ; 4-aligned: road_project steps
    ASSERT (list0 & 3) == 0             ; within an entry with INC E
    defs LIST_LEN,0
    ASSERT $ <= FRAG3+FRAG_LEN

    ORG FRAG4,FRAG_STORE+4*FRAG_LEN
    defs LIST_GUARD,0
list1
    ASSERT (list1 & 3) == 0
    defs LIST_LEN,0
    ASSERT $ <= FRAG4+FRAG_LEN
