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
irq_phase   defb IRQ_LOST   ; interrupts since the last VSYNC (IRQ_LOST + n:
                            ; not in step with the frame yet)
flip_req    defb 0          ; R12 for the next VSYNC to show, 0 = none
flip_drop   defb 0          ; ... and how far its horizon is down
flip_last   defb 0          ; vbl_count when the last flip happened
front_buf   defb 0          ; buffer being shown (0/1)

;; --- the split of the frame being shown (see rup_frame) ---------------------
rup_base    defb BUF0_R12   ; R12 of the buffer shown
rup_drop    defb 0          ; lines the horizon is down
rup_r5a     defb 0          ; R5 of the HUD part
rup_r5b     defb 0          ; R5 of the sky part
rup_r4c     defb TOTAL_ROWS-BLOCK_ROW-1 ; R4 of the road part
rup_r6c     defb CRTC_R7-BLOCK_ROW      ; R6 and R7 of the road part
rup_c       defw 0          ; R13, R12 of the road part

;; --- road engine inputs ---------------------------------------------------
zcam        defw 0          ; camera depth, 16 depth units = one stripe
hill        defb 0          ; signed: + crest ahead, - the road rises ahead
road_buf    defb 0          ; buffer road_project/road_draw work on

;; --- road_draw state ---------------------------------------------------------
patch_save  defb 0          ; the byte the exit patch replaced
patch_dummy defb 0          ; harmless target for lines that need no patch
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
;; The one inside VSYNC is recognised by reading PPI port B, and is the top
;; of the frame: vbl_count ticks, and a pending flip is made. The flip waits
;; for two VSYNCs since the last one, which is what holds the game to 25
;; pictures a second when it could draw faster.
;;
;; The frame is split into three by raster ruptures (hw.asm), and each
;; interrupt sets the CRTC up for the parts coming next: rup_frame at the
;; VSYNC, rup_phase at the five others. The Gate Array's interrupts come at
;; fixed lines - 2 after the VSYNC starts and every 52 after that - so each
;; knows where the beam is.
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
    ld b,#F5                    ; PPI port B: bit 0 = VSYNC
    in a,(c)
    rra
    jr nc,isr_mid
    call rup_vsync
    jr isr_out
isr_mid
    call rup_mid
isr_out
    pop hl
    pop bc
    pop af
isr_sp
    ld sp,0                     ; (self-modified)
    ei
    reti

    defs 24,0
isr_stack

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
;; The raster ruptures (hw.asm has the layout). Called by the interrupt
;; handler; may use AF, BC and HL only.
;;
;; rup_vsync - the interrupt inside VSYNC, line ~274: the top of a frame.
;; ---------------------------------------------------------------------------
rup_vsync
    ld hl,vbl_count
    inc (hl)
    ld a,(irq_phase)
    cp 5
    jr z,rup_vsync_in_step
    cp IRQ_LOST
    jr nc,rup_vsync_in_step     ; the first VSYNC: from here on in step
    call rup_safe               ; a VSYNC where there should be none: the
    ld a,IRQ_LOST               ; frame is not what it was set up to be
    ld (irq_phase),a
    ret
rup_vsync_in_step
    xor a
    ld (irq_phase),a
    ld a,(flip_req)             ; a picture waiting, and two frames since the
    or a                        ; last: show it from this frame on
    jr z,rup_frame
    ld a,(hl)
    ld hl,flip_last
    sub (hl)
    cp 2
    jr c,rup_frame
    ld a,(vbl_count)
    ld (hl),a
    ld a,(flip_req)
    ld (rup_base),a
    ld a,(flip_drop)
    ld (rup_drop),a
    xor a
    ld (flip_req),a
    jr rup_frame

;; rup_mid - the other five interrupts
rup_mid
    ld hl,irq_phase
    inc (hl)
    ld a,(hl)
    cp IRQ_LOST
    jr nc,rup_mid_lost
    cp 6
    jp c,rup_phase
    call rup_safe               ; six without a VSYNC: back to a plain frame
    ld a,IRQ_LOST
    ld (irq_phase),a
rup_mid_count
    ld hl,vbl_count             ; and count a frame, so the game goes on
    inc (hl)
    ret
rup_mid_lost
    cp IRQ_LOST+6               ; waiting for a VSYNC: a frame every six
    ret c
    ld (hl),IRQ_LOST
    jr rup_mid_count

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

;; ---------------------------------------------------------------------------
;; rup_frame - work out the frame's split from the drop of the buffer it
;; shows, and start its HUD part.
;; ---------------------------------------------------------------------------
rup_frame
    ld a,(rup_drop)
    ld (rup_r5a),a              ; the HUD part: R5 = drop lines of border
    neg
    and 7
    ld (rup_r5b),a              ; the sky part: what brings the road onto a row
    ld a,(rup_drop)
    add a,7
    rrca
    rrca
    rrca
    and #1F
    ld c,a                      ; C = q: the road starts at row BLOCK_ROW + q
    ld a,TOTAL_ROWS-BLOCK_ROW-1
    sub c
    ld (rup_r4c),a
    ld a,CRTC_R7-BLOCK_ROW
    sub c
    ld (rup_r6c),a
    ld a,c                      ; the road part starts (BLOCK_ROW + q) * 48
    add a,BLOCK_ROW             ; characters into the buffer
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
    ld a,l
    add a,BUF_R13
    ld (rup_c),a
    ld a,(rup_base)
    adc a,h
    and #3F
    ld (rup_c+1),a

    ld bc,#BC00+12              ; the HUD part starts with the buffer
    out (c),c
    ld a,(rup_base)
    ld b,#BD
    out (c),a
    ld bc,#BC00+13
    out (c),c
    ld bc,#BD00+BUF_R13
    out (c),c
    ld bc,#7F10                 ; navy border for the lines above the sky
    out (c),c
    ld c,BORDER_TOP_HW
    out (c),c
    ret

    ASSERT HUD_ROWS*8 == HUD_H
    ASSERT BLOCK_ROW*8 == BLOCK_BOTTOM

;; rup_phase - the other interrupts, A = 1..5
rup_phase
    dec a
    jr z,rup_hud
    dec a
    jr z,rup_sky
    dec a
    jp z,rup_road
    dec a
    ret z

    ; 5, line ~222, in the road part: its size, and the VSYNC at line 272
    ld bc,#BC00+4
    out (c),c
    ld a,(rup_r4c)
    ld b,#BD
    out (c),a
    ld bc,#BC00+5
    out (c),c
    ld bc,#BD00
    out (c),c
    ld bc,#BC00+6
    out (c),c
    ld a,(rup_r6c)
    ld b,#BD
    out (c),a
    ld bc,#BC00+7
    out (c),c
    ld b,#BD
    out (c),a
    ret

    ; 1, line ~14, in the HUD part: its size and R5 lines, no VSYNC; where
    ; the sky part starts
rup_hud
    ld bc,#BC00+4
    out (c),c
    ld bc,#BD00+HUD_ROWS-1
    out (c),c
    ld bc,#BC00+5
    out (c),c
    ld a,(rup_r5a)
    ld b,#BD
    out (c),a
    ld bc,#BC00+6               ; the R5 lines, one row past the last, are
    out (c),c                   ; border
    ld bc,#BD00+HUD_ROWS
    out (c),c
    ld bc,#BC00+7
    out (c),c
    ld bc,#BD7F
    out (c),c
    ld bc,#BC00+12
    out (c),c
    ld a,(rup_base)
    add a,hi(HUD_ROWS*48)
    ld b,#BD
    out (c),a
    ld bc,#BC00+13
    out (c),c
    ld bc,#BD00+BUF_R13+lo(HUD_ROWS*48)
    out (c),c
    ret
    ASSERT BUF_R13+lo(HUD_ROWS*48) < 256

    ; 2, line ~66, after the HUD part's last row: the sky part's size
rup_sky
    ld bc,#BC00+4
    out (c),c
    ld bc,#BD00+SKY_ROWS-1
    out (c),c
    ld bc,#BC00+6
    out (c),c
    ld bc,#BD00+SKY_ROWS
    out (c),c
    ret

    ; 3, line ~118, after the HUD part's R5 lines: the sky part's R5 lines,
    ; where the road part starts, the border below the mountains
rup_road
    ld bc,#BC00+5
    out (c),c
    ld a,(rup_r5b)
    ld b,#BD
    out (c),a
    ld bc,#BC00+12
    out (c),c
    ld a,(rup_c+1)
    ld b,#BD
    out (c),a
    ld bc,#BC00+13
    out (c),c
    ld a,(rup_c)
    ld b,#BD
    out (c),a
    ld bc,#7F10
    out (c),c
    ld c,BORDER_LOW_HW
    out (c),c
    ret

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
;; the line in the screen) and a template - four more words, popped in turn:
;;
;;   IY      where to enter the road core (part-way in if it hangs off the
;;           right of the screen)
;;   IX      where to enter the left grass block (how much grass is left)
;;   patch   if the core hangs off the left of the screen, the first byte of
;;           it that must not run: JP (HL) is written over it, and put back
;;           when the core leaves through it
;;   AF      A = low byte of the right grass block entry;
;;           F: S = stripe band B, Z = no patch
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
;; Band A cores are in bank 4 and band B cores in bank 5, so changing band
;; changes the RAM configuration too - which is why this code is here.
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
    ld a,(patch_save)
    ld (de),a                           ; put back what the exit patch hid
line_done_a
    ld sp,(line_ptr)
    pop hl                              ; where SP starts on the screen
    pop de                              ; template
    ei                                  ; one instruction's chance for an
    ld (line_ptr),sp                    ; interrupt: its return address then
    di                                  ; lands on the template just read
    ex de,hl
    ld sp,hl
    pop iy
    pop ix
    pop hl                              ; patch address
    pop af                              ; A = right grass entry, S = band B,
    jp m,to_band_b                      ; Z = no patch
line_go
    ex de,hl                            ; DE = patch address, HL = screen
    ld sp,hl
    ld l,a
    ld h,hi(rgrass)
    jr z,line_go_now
    ld a,(de)
    ld (patch_save),a
    ld a,#E9                            ; JP (HL)
    ld (de),a
line_go_now
    jp (hl)

;; --- band B -------------------------------------------------------------------
line_done_shadow_b
    exx
    ex af,af'
    ld a,(patch_save)
    ld (de),a
line_done_b
    ld sp,(line_ptr)
    pop hl
    pop de
    ei
    ld (line_ptr),sp
    di
    ex de,hl
    ld sp,hl
    pop iy
    pop ix
    pop hl
    pop af
    jp p,to_band_a
    ex de,hl
    ld sp,hl
    ld l,a
    ld h,hi(rgrass)
    jr z,line_go_now_b
    ld a,(de)
    ld (patch_save),a
    ld a,#E9
    ld (de),a
line_go_now_b
    jp (hl)

;; --- switching band: registers, and the bank the cores are in -----------------
;; A, F, DE and HL are in use (right grass entry, no-patch flag, screen,
;; patch address).
to_band_b
    ld sp,band_keep+2
    push af
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
    ld sp,band_keep
    pop af
    jr line_go

to_band_a
    ld sp,band_keep+2
    push af
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
    ld sp,band_keep
    pop af
    jr line_go

band_keep   defw 0
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
list0
    defs LIST_LEN,0
    ASSERT $ <= FRAG3+FRAG_LEN

    ORG FRAG4,FRAG_STORE+4*FRAG_LEN
    defs LIST_GUARD,0
list1
    defs LIST_LEN,0
    ASSERT $ <= FRAG4+FRAG_LEN

;; ===========================================================================
;; Fragments 5 and 6: the road templates, band 0 then band 1 at the same
;; offset #800 further on - road_project relies on that.
;; ===========================================================================
    ORG FRAG5,FRAG_STORE+5*FRAG_LEN
    INCLUDE "gen/roadtmpl0.asm"

;; a line with no road: 48 pairs of band A grass
tmpl_ground defw empty_core,lgrassa+48,patch_dummy,#0040
;; the end of the list
tmpl_end    defw render_end,lgrassa+48,patch_dummy,#3040
;; a line that is already right: nothing pushed
tmpl_skip   defw empty_core,lgrassa+48,patch_dummy,#3040
    ASSERT $ <= FRAG5+FRAG_LEN

    ORG FRAG6,FRAG_STORE+6*FRAG_LEN
    INCLUDE "gen/roadtmpl1.asm"
    ASSERT tmpl_band1 == tmpl_band0+#800
    ASSERT $ <= FRAG6+FRAG_LEN
