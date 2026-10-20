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
irq_phase   defb 0          ; interrupts since the last VSYNC
flip_req    defb 0          ; R12 for the next VSYNC to show, 0 = none
flip_last   defb 0          ; vbl_count when the last flip happened
front_buf   defb 0          ; buffer being shown (0/1)

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
;; of the frame: vbl_count ticks, and a pending flip is made. Writing R12 here
;; - during VSYNC, below the last displayed row - means the CRTC takes it at
;; the start of the next frame, on every CRTC type. The flip waits for two
;; VSYNCs since the last one, which is what holds the game to 25 pictures a
;; second when it could draw faster.
;;
;; The road renderer runs with interrupts off while SP points into the
;; screen, and turns them on for a moment between lines, so this can arrive
;; up to one road line late (~0.3 ms, five scanlines) - still inside the
;; eight-line VSYNC. In case it ever is not, six interrupts without a VSYNC
;; count as a frame too.
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

    xor a
    ld (irq_phase),a
    ld hl,vbl_count
    inc (hl)
    ld a,(flip_req)
    or a
    jr z,isr_out
    ld a,(hl)
    ld hl,flip_last
    sub (hl)
    cp 2
    jr c,isr_out                ; not two frames yet
    ld a,(vbl_count)
    ld (hl),a
    ld bc,#BC0C                 ; R12 = flip_req
    out (c),c
    ld a,(flip_req)
    ld b,#BD
    out (c),a
    ld bc,#BC0D                 ; R13 is the same for both buffers
    out (c),c
    ld bc,#BD00+BUF_R13
    out (c),c
    xor a
    ld (flip_req),a
    jr isr_out

isr_mid
    ld hl,irq_phase
    inc (hl)
    ld a,(hl)
    cp 6
    jr c,isr_out
    ld (hl),0                   ; six without a VSYNC: count a frame, but
    ld hl,vbl_count             ; never flip here - only inside VSYNC is it
    inc (hl)                    ; known where the beam is

isr_out
    pop hl
    pop bc
    pop af
isr_sp
    ld sp,0                     ; (self-modified)
    ei
    reti

    defs 16,0
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
