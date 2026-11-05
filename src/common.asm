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
;; Fragment 0: variables, the interrupt handler, prop_draw's lines
;; ===========================================================================
    ORG FRAG0,FRAG_ST0
frag0_start

;; --- frame timing -----------------------------------------------------------
vbl_count   defb 0          ; +1 at every VSYNC (50 Hz)
lost_count  defb 0          ; interrupts since the frame was lost track of
flip_req    defb 0          ; buffer + 1 to show from the next VSYNC, 0 = none
flip_drop   defb 0          ; ... how far its horizon is down
flip_head   defb 0          ; ... and where its sky looks (words right)
flip_last   defb 0          ; vbl_count when the last flip happened
irq_n       defb 0          ; interrupts since then (the 12th shows the next)
car_offc    defb 0          ; car_off this picture (car_lines), for
                            ; traffic_draw
coll        defb 0          ; what our car touched this picture (traffic_draw,
                            ; bush_one): bit 7 a car, bit 6 a bush, bit 0
                            ; it was right of ours (steer)
main_cfg    defb RAM_C1     ; the RAM configuration the main code is in
                            ; while it waits for a flip (cache_job)
front_buf   defb 0          ; buffer being shown (0/1)

;; --- the split of the frame being shown (see rup_frame) ---------------------
rup_buf     defb 0          ; buffer shown
rup_drop    defb 0          ; lines the horizon is down
rup_r4a     defb HUD_ROWS-1+(SKY_Y-HUD_H)/8 ; HUD part: rows - 1, its border
rup_r5a     defb (SKY_Y-HUD_H)&7            ; rows too; its R5 lines (the
                            ; values here are drop 0's: rup_frame works
                            ; them out only when a picture is shown)
rup_r4b     defb SKY_ROWS-1 ; sky part: rows - 1, a border row too
rup_r5b     defb (ROAD_Y/8*8-BLOCK_BOTTOM)&7 ; sky part: R5 lines
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
rp_dirty    defb 0          ; a bush may have covered the far road (bush.asm)
rp_dlo      defb 0          ; ... and the lines it stood on, from
rp_dhi      defb 0          ; ROAD_AREA_Y (rp_force)
    ASSERT rp_dhi == rp_dlo+1   ; (rp_force: IX)

;; --- profiling (read by tools/run.py) ---------------------------------------
frames_drawn defw 0         ; pictures completed
frames_late  defw 0         ; pictures that took more than two VSYNCs
frame_vbls   defb 0         ; VSYNCs the last picture took

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
    ld hl,irq_n
    inc (hl)
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
    ld c,a                      ; C = the road's drop
    ld hl,sky_drops
    add a,l
    ld l,a
    jr nc,$+3
    inc h
    ld a,(hl)                   ; H = SKY_Y - HUD_H + the sky's drop
    ld h,a                      ; (scene.sky_drop) - not DE: the interrupt
    and 7                       ; keeps AF, BC, HL only
    ld (rup_r5a),a              ; HUD part: H mod 8 R5 lines ...
    ld a,h
    rrca
    rrca
    rrca
    and #1F                     ; ... after H / 8 border rows
    add a,HUD_ROWS-1
    ld (rup_r4a),a
    ld a,c                      ; the road part: from the row the top of the
    add a,ROAD_Y                ; road is in
    rrca
    rrca
    rrca
    and #1F
    ld b,a                      ; B = its row, ROAD_ROW+3..ROAD_ROW+5
    add a,a
    add a,a
    add a,a
    sub BLOCK_BOTTOM-(SKY_Y-HUD_H)
    sub h                       ; green border lines after the sky, 0..7
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

sky_drops                       ; per road drop: the sky's
    SKY_DROP_TABLE
    ASSERT $-sky_drops == SKY_DROP_N

    INCLUDE "propdraw.asm"

frag0_end
    ASSERT frag0_end <= FRAG0+FRAG_LEN

;; ===========================================================================
;; Fragment 1: trampolines and the stack
;; ===========================================================================
    ORG FRAG1,FRAG_ST1
frag1_start

;; ---------------------------------------------------------------------------
;; road_frame - project and draw the road into buffer (road_buf).
;; Called from the game code in bank 7 with RAM_C1; returns with RAM_C1.
;; Bank 7 is not mapped while the road engine runs, so this has to live here.
;; ---------------------------------------------------------------------------
road_frame
    SET_RAM RAM_C6
    call traffic_pre            ; (traffic.asm)
    call road_project
rf_projected                    ; (tools: timing)
    SET_RAM RAM_C1
    call car_lines              ; (bush.asm)
    call road_draw
rf_drawn                        ; (tools: timing)
    SET_RAM RAM_C6
    call traffic_draw
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
    ld (irq_n),a
    call rup_frame              ; the HUD part's start first: it is near
    ld bc,#7F00+RAM_C1          ; then turn the sky the new picture looks at
    out (c),c                   ; (game code, bank 7 - while the main code
    call ring_turn              ; may be making the cache, banks 4 and 5:
    ld a,(main_cfg)             ; main_cfg)
    ld b,#7F
    out (c),a
    ret

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
    ASSERT SKY_ROWS*8 == BLOCK_BOTTOM-SKY_Y
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

;; line ~66, the HUD part's display over (its border rows go on): the sky
;; part's rows
irq_sky
    NEXT_IRQ irq_idle
    CRTC_N 6,SKY_ROWS
    jp isr_out

;; line ~118, in the HUD part's border: the sound (sound.asm)
irq_idle
    NEXT_IRQ irq_road
    jp snd_irq

;; line ~170, in the sky part: its size and R5 lines, where the road part
;; starts, the border below the mountains
irq_road
    NEXT_IRQ irq_size
    ld hl,rup_r4b
    CRTC_HL 4
    ld hl,rup_r5b
    CRTC_HL 5
    ld hl,rup_c+1
    CRTC_HL 12
    ld hl,rup_c
    CRTC_HL 13
    ld bc,#7F10
    out (c),c
irq_ground
    ld c,BORDER_LOW_HW                  ; (self-modified: the stage's ground,
    out (c),c                           ; stage_colours)
    jp isr_out
    ASSERT SKY_Y+5 < 170 && BLOCK_BOTTOM > 175

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

;; cache_mark - (cf_run5, job5) A = a group worked out afresh: both
;; buffers have its rows to draw as moved. Destroys AF, HL.
cache_mark
    ld hl,rd_ghi
    inc a
    cp (hl)
    jr c,$+3
    ld (hl),a
    inc l
    cp (hl)
    jr c,$+3
    ld (hl),a
    inc l
    dec a
    cp (hl)
    jr nc,$+3
    ld (hl),a
    inc l
    cp (hl)
    ret nc
    ld (hl),a
    ret

;; ---------------------------------------------------------------------------
;; rp_flag2_marg, rp_flag2_road - (rp_mode_set) what flag 2 means to
;; road_draw (lg2_a, lg2_b): the road and a margin - a line showing another
;; row than then, the hill having moved - or, while flag 1 is the road and
;; a margin, only the road: what rp_near_skip gives a line whose row did not
;; move (rp_skip_rf), and rp_force a skipped one (rp_force_res). Then
;; rp_near_skip may also have a window of rows that did move after its
;; first ones (rp_lo_c: rp_seg_in). Destroys AF, BC, HL.
;; ---------------------------------------------------------------------------
rp_flag2_road
    ld hl,line_road2_a
    ld (lg2_a+1),hl
    ld hl,rp_skip_rest0
    ld a,(rp_lo_c)
    or a
    jr z,rp_flag2_w
    ld hl,rp_seg_in
    ld b,a
    ld a,(rr_gfirst+NFAR)               ; and with the far groups as then,
    cp b                                ; the far lines have not moved
    jr c,$+4
    jr nz,rp_flag2_w
    xor a
    ld (rp_moved),a
rp_flag2_w
    ld (rp_skip_rest+1),hl
    ld hl,line_road2_b
    ld bc,#8602                         ; RES 0,(HL): flag 3 into 2
    jr rp_flag2_set
rp_flag2_marg
    ld hl,rp_skip_rest0
    ld (rp_skip_rest+1),hl
    ld hl,line_marg2_a
    ld (lg2_a+1),hl
    ld hl,line_marg2_b
    ld bc,#8E01                         ; RES 1,(HL): flag 3 into 1
rp_flag2_set
    ld (lg2_b+1),hl
    ld a,c
    ld (rp_skip_rf+1),a
    ld a,b
    ld (rp_force_res+1),a
    ld a,3
    ld (rp_skip_s3+1),a
    ret

;; rp_seg_in - (rp_near_skip, at the first row the curve may have moved)
;; the window of rows that did, down to the first group the cache worked
;; out (rp_lo_c): their lines are drawn with the margin - flag 1 if
;; unchanged too - and the skip loop goes on to the window's end, then
;; (rp_seg_out) on as before, to the last line. The line is looked at again.
rp_seg_in
    ld hl,rp_seg_out
    ld a,(rp_lo_c)
    ld ixh,1
    jr rp_seg_set
rp_seg_out
    ld hl,rp_skip_rest0                 ; (not again: rp_skip_r 0)
    xor a
    ld ixh,3
rp_seg_set
    ld (rp_skip_rest+1),hl
    ld (rp_skip_r+1),a
    ld a,ixh
    ld (rp_skip_s3+1),a                 ; 1 or 3 ...
    inc a
    srl a
    ld (rp_skip_rf+1),a                 ; ... and 1 or 2
    jp rp_skip_line

;; ---------------------------------------------------------------------------
;; rp_far_m - the hill alone moved: B = C = the margin a line that now
;; shows another row needs - 3 + |curve level| / 2 pairs, one more with
;; road_x 17 or more either way (tools: the edges of the rows a line can
;; show then and now, the hill RP_HILL_STEP levels or less apart) - and
;; RP_HILL_M at least. The far lines get it too (rp_far_hfl).
rp_far_m
    ld a,2
    ld (rp_far_hfl+1),a
    ld a,(road_curve)
    or a
    jp p,$+5
    neg
    srl a
    add a,3
    ld c,a
    ld a,(road_x)
    add a,16
    cp 33                               ; (CF: 16 or less either way)
    ld a,c
    sbc a,-1
    cp RP_HILL_M
    jr nc,rp_far_m_bc
    ld a,RP_HILL_M
rp_far_m_bc
    ld b,a
    ld c,a
    ret

;; ---------------------------------------------------------------------------
;; sky_next - (main) NZ if the next picture draws its buffer's road moved:
;; road_x has since it was last drawn, or groups the cache worked out
;; (rd_ghi) - the sky's turn waits then. Keeps BC.
sky_next
    ld a,(back_buf)
    xor 1
    ld e,a
    ld d,0
    ld hl,drawn_x
    add hl,de
    ld a,(road_x)
    cp (hl)
    ret nz
    ld hl,rd_ghi
    add hl,de
    ld a,(hl)
    dec a
    cp NGROUPS                          ; (1..NGROUPS: worked out)
    sbc a,a
    ret

frag1_end
    ASSERT frag1_end <= STACK_TOP-48       ; leave the stack 48 bytes (it
                                           ; takes ~24: tools)

;; ===========================================================================
;; Fragment 2: road_draw
;; ===========================================================================
    ORG FRAG2,FRAG_ST2
frag2_start

PAIRS       EQU SCR_BYTES/2 ; two-byte pairs a line, one PUSH each

;; ---------------------------------------------------------------------------
;; road_draw - draw the lines in the line list of (road_buf).
;;
;; A line list entry is two words: where SP starts for that line (the end of
;; the line in the screen) and a template - three or four more words, popped
;; in turn (tools/mkroad.py makes them, one set per curve level). Bit 0 of
;; the template's address set means "only the road": the grass is plain and
;; already right, so the line is only its core (line_road_a) - or, when
;; road_project has set a margin (rd_margin), its core and that many pairs of
;; grass either side, as far as the core can have moved since (line_margin_a).
;;
;;   IY      where to enter the road core (part-way in if it hangs off the
;;           right of the screen)
;;   AF      A = low byte of the right grass block entry; F: Z = no patch
;;   IX      where to enter the left grass block (how much grass is left)
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
    call rd_start                       ; the list, the grass (fragment 3)
    di
    SET_RAM RAM_C4                      ; start in band A
    exx
    ld hl,line_done_shadow_a
    ld de,ROAD0_PAIR
    exx
    ld sp,kerb0_word
    pop af
    ex af,af'
    ld bc,(rd_grass)
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
    bit 0,l
lg_jr_a
    jp nz,line_road_a                   ; only the road (or line_margin_a)
    bit 1,l
lg2_a
    jp nz,line_marg2_a                  ; the road and a margin (or
                                        ; line_road2_a: rp_mode_set)
    ld sp,hl
    pop iy
    pop af                              ; A = right grass entry, Z = no patch
    pop ix
    jr nz,line_patch
    ex de,hl                            ; HL = screen
    ld sp,hl
    ld l,a
    ld h,hi(rgrass)
    jp (hl)

;; Only the road: the line shows the same row in the same place as when
;; this buffer was last drawn, so the grass on either side is right. SP
;; starts at the core's right edge, (48 - A) pairs in from the end of the
;; line, and the core leaves into no left grass. Flag 2 can mean only the
;; road too (rp_mode_set: lg2_a).
line_road2_a
    dec l
line_road_a
    bit 1,l                             ; 3: already right (rp_near_skip)
    jr nz,line_done_a
    dec l                               ; (templates are at even addresses)
    ld sp,hl
    pop iy
    pop af
    jr nz,line_road_patch
    sub PAIRS
    add a,a
    ld l,a
    sbc a,a
    ld h,a
    add hl,de
    ld sp,hl
    ld ix,lgrassa+PAIRS
    exx
    ex af,af'
    jp (iy)

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
    bit 0,l
lg_jr_b
    jp nz,line_road_b                   ; (or line_margin_b)
    bit 1,l
lg2_b
    jp nz,line_marg2_b                  ; (or line_road2_b)
    ld sp,hl
    pop iy
    pop af
    pop ix
    jr nz,line_patch
    ex de,hl
    ld sp,hl
    ld l,a
    ld h,hi(rgrass)
    jp (hl)

line_road2_b
    dec l
line_road_b
    bit 1,l                             ; 3: already right (rp_near_skip)
    jr nz,line_done_b
    dec l
    ld sp,hl
    pop iy
    pop af
    jr nz,line_road_patch
    sub PAIRS
    add a,a
    ld l,a
    sbc a,a
    ld h,a
    add hl,de
    ld sp,hl
    ld ix,lgrassb+PAIRS
    exx
    ex af,af'
    jp (iy)

;; only the road, cut short at the left: A = right grass entry, DE = screen,
;; SP at the template's IX
line_road_patch
    pop ix                              ; the byte the patch hides
    pop hl
    ld (hl),#E9                         ; JP (HL)
    ex de,hl                            ; DE = patch address, HL = screen
    sub PAIRS
    add a,a
    jr nc,line_road_patch_go            ; the core reaches the right edge
    add a,l
    ld l,a
    jr c,line_road_patch_go
    dec h
line_road_patch_go
    ld sp,hl
    exx
    ex af,af'
    jp (iy)

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
    ld bc,(rd_grass)                    ; the grass goes on as it was
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
    ld bc,(rd_grass)
tb_jp
    jp tb_stripe                        ; (self-modified: line_go_a past the
                                        ; grass's stripes)

;; Only the road and a margin: at most M pairs of grass each side (the
;; constants marked MT are PAIRS - M, set by rd_margin). The left grass is
;; what the template says, but no more than M pairs. A line flagged 2 (not
;; 1) always gets one: it shows another row than when its buffer was last
;; drawn, the hill having moved (road_project).
line_marg2_a
    dec l
line_margin_a
    dec l
    ld sp,hl
    pop iy
    pop af                              ; A = right grass entry, Z = no patch
    pop ix
    jr nz,line_margin_patch
    ld l,a
    ld a,ixl
lm_la
    cp lo(lgrassa)+PAIRS                ; lo(lgrassa) + MT (self-modified)
    jr nc,line_margin_right
lm_la2
    ld ixl,lo(lgrassa)+PAIRS            ; lo(lgrassa) + MT (self-modified)
    jr line_margin_right

line_marg2_b
    dec l
line_margin_b
    dec l
    ld sp,hl
    pop iy
    pop af
    pop ix
    jr nz,line_margin_patch
    ld l,a
    ld a,ixl
lm_lb
    cp lo(lgrassb)+PAIRS                ; lo(lgrassb) + MT (self-modified)
    jr nc,line_margin_right
lm_lb2
    ld ixl,lo(lgrassb)+PAIRS            ; lo(lgrassb) + MT (self-modified)
    jr line_margin_right

;; L = right grass entry, DE = screen; then the right grass and on
line_margin_right
    ld a,l
lm_m1
    cp PAIRS                            ; MT (self-modified)
    jr nc,line_margin_all               ; no more right grass than M pairs
lm_m2
    sub PAIRS                           ; MT (self-modified)
    add a,a
    ld l,a
    ld h,#FF
    add hl,de
    ld sp,hl                            ; the screen, M pairs right of the core
lm_m3
    ld l,PAIRS                          ; MT (self-modified): M pairs of grass
    ld h,hi(rgrass)
    jp (hl)

line_margin_all
    ex de,hl
    ld sp,hl
    ld l,a
    ld h,hi(rgrass)
    jp (hl)

;; ... the core hanging off the left: no left grass; A = right grass entry,
;; DE = screen, SP at the patch address
line_margin_patch
    pop hl
    ld (hl),#E9                         ; JP (HL)
    ex de,hl                            ; DE = patch address, HL = screen
lm_p1
    cp PAIRS                            ; MT (self-modified)
    jr nc,line_margin_patch_go
lm_p2
    sub PAIRS                           ; MT (self-modified)
    add a,a
    add a,l
    ld l,a
    jr c,$+3
    dec h
lm_p3
    ld a,PAIRS                          ; MT (self-modified)
line_margin_patch_go
    ld sp,hl
    ld l,a
    ld h,hi(rgrass)
    jp (hl)

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
    jp rd_end

;; Templates for every frame, here because they are band A's (bit 13 of the
;; address clear) and must be read in either bank:
;; the end of the list
    ALIGN 4                             ; bits 0 and 1 of a template's
tmpl_end    defw render_end,#3040,lgrassa+48   ; address are flags (road_draw)
    defs 2,0
;; a line that is already right: nothing pushed
tmpl_skip   defw 0,lo(rgrass_skip)*256+#40,0
    ASSERT (tmpl_end & #2000) == 0
    ASSERT ((tmpl_end | tmpl_skip) & 3) == 0

;; Only the road and a margin on the right (none on the left): the right
;; grass is what the template says, but no more than M pairs (as
;; line_margin_a); the core leaves into no left grass. The _s ways look for
;; flag 3 first (rp_skip_jr).
line_rmarg_sa
    bit 1,l
    jp nz,line_done_a
line_rmarg_a
    dec l
    ld sp,hl
    pop iy
    pop af                              ; A = right grass entry, Z = no patch
    jr nz,line_rmarg_p
    ld ix,lgrassa+PAIRS
    ld l,a
    jp line_margin_right
line_rmarg_sb
    bit 1,l
    jp nz,line_done_b
line_rmarg_b
    dec l
    ld sp,hl
    pop iy
    pop af
    jr nz,line_rmarg_p
    ld ix,lgrassb+PAIRS
    ld l,a
    jp line_margin_right
line_rmarg_p                            ; the core hangs off the left
    pop ix
    jp line_margin_patch

;; sky_stay - (cache_steps, here for room) the flip is not to turn the sky
;; after all: the next picture has the road moved sideways to draw.
sky_stay
    ld a,(ring_head)
    ld (flip_head),a
    xor a
    ld (sky_turns),a
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
    ASSERT hi(lgrassa) == hi(lgrassa+PAIRS) && hi(lgrassb) == hi(lgrassb+PAIRS)
                                        ; (cachemac.asm: an entry is its low byte)

;; Only the road and a margin on the left (none on the right): the left grass
;; is what the template says, but no more than M pairs (MT = PAIRS - M, set
;; by rd_margin); a core cut short at the left has none anyway.
line_lmarg_a
    dec l
    ld sp,hl
    pop iy
    pop af
    jp nz,line_road_patch
    pop ix
    ld l,a
    ld a,ixl
lm_ca
    cp lo(lgrassa)+PAIRS                ; lo(lgrassa) + MT (self-modified)
    jr nc,$+5
lm_ca2
    ld ixl,lo(lgrassa)+PAIRS            ; (self-modified)
    ld a,l
    sub PAIRS
    add a,a
    ld l,a
    sbc a,a
    ld h,a
    add hl,de
    ld sp,hl
    exx
    ex af,af'
    jp (iy)

line_lmarg_b
    dec l
    ld sp,hl
    pop iy
    pop af
    jp nz,line_road_patch
    pop ix
    ld l,a
    ld a,ixl
lm_cb
    cp lo(lgrassb)+PAIRS                ; lo(lgrassb) + MT (self-modified)
    jr nc,$+5
lm_cb2
    ld ixl,lo(lgrassb)+PAIRS            ; (self-modified)
    ld a,l
    sub PAIRS
    add a,a
    ld l,a
    sbc a,a
    ld h,a
    add hl,de
    ld sp,hl
    exx
    ex af,af'
    jp (iy)

;; bush_erase's next lines of a box (bush.asm; fragment 15: be_segd)
be_seg
    ld a,ixl                            ; B lines this time: to the end of the
    and 7                               ; row, of the box, or of the grass
    sub 8
    neg
    cp c
    jr c,$+3
    ld a,c
    ld b,a
    ld a,ixh
    sub ixl
    cp b
    jr nc,$+3
    ld b,a
    ld a,c
    sub b
    ld c,a                              ; C = lines after these
    ld a,ixl
    add a,b
    ld ixl,a
    jp (iy)

frag2_end
    ASSERT frag2_end <= FRAG2+FRAG_LEN

;; ===========================================================================
;; Fragments 3 and 4: the line lists. 32 bytes of guard in front for what an
;; interrupt pushes while the first entry is being read; then one entry per
;; road line, bottom line first; then the end.
;; ===========================================================================
LIST_GUARD  EQU 32
LIST_LEN    EQU (ROAD_LINES+1)*4

    ORG FRAG3,FRAG_ST3
    defs LIST_GUARD,0
list0                                   ; 4-aligned: road_project steps
    ASSERT (list0 & 3) == 0             ; within an entry with INC E
    defs LIST_LEN,0

;; ---------------------------------------------------------------------------
;; The grass's stripes, for road_draw (fragment 2 is full). From the bottom
;; line up the grass is rd_grass0's green (rp_grass) and changes to the
;; other at each line where a kerb's band B gives way to band A - which is
;; where bit GRASS_SHIFT of (depth + zcam) changes, the rows being less than
;; a kerb stripe apart there - up to the first line past GRASS_ROW, whose
;; entry road_project has given tmpl_mid: from there on it is GRASS_PAIR's.
;; The lines it changed at are noted in the buffer's rd_gb list, for
;; bush_erase to put back the grass of then.
;; ---------------------------------------------------------------------------
RD_GB       EQU 14                      ; room for six changes and the end
rd_grass    defw GRASS_PAIR             ; the grass now (road_draw: BC)
rd_grass0   defb lo(GRASS_PAIR)         ; the bottom line's (rp_grass)
rd_gbp      defw 0                      ; where the next change is noted
rd_mid_t    defw 0                      ; tmpl_mid's line's own template
;; per buffer: the bottom line's grass, then the changes - each the list
;; pointer past the line's entry, pushed bottom line first - and a 0
rd_gb0      defb lo(GRASS_PAIR)
            defs RD_GB,0
rd_gb1      defb lo(GRASS_PAIR)
            defs RD_GB,0

;; rd_start - (road_draw) the line list of (road_buf), and the grass
;; striped from its bottom line up.
rd_start
    ld hl,tb_stripe
    ld (tb_jp+1),hl
    ld hl,rd_gb0
    ld de,list0
    ld a,(road_buf)
    or a
    jr z,rd_start_go
    ld hl,rd_gb1
    ld de,list1
rd_start_go
    ld (line_ptr),de
    ld a,(rd_grass0)
    ld (hl),a                           ; the bottom line's green, noted
    ld e,a
    ld d,a
    ld (rd_grass),de
    ld de,1+RD_GB
    add hl,de
    ld (rd_gbp),hl
    ret

;; (to_band_a) a kerb's band B gave way to band A, and so does the grass's
;; stripe: the other green on, the line noted. BC = the grass, DE = the
;; template, HL = the screen.
tb_stripe
    ld a,c
    xor GRASS_X
    ld c,a
    ld b,a
    ld (rd_grass),bc
    ld ix,(line_ptr)
    ld sp,(rd_gbp)
    push ix
    ld (rd_gbp),sp
    jp line_go_a

;; the first line past the grass's stripes: GRASS_PAIR's green on, and its
;; own template back in the list, then read
    ALIGN 4
tmpl_mid    defw tm_mid,#3040,lgrassa+48
    defs 2,0
    ASSERT (tmpl_mid & #2000) == 0
tm_mid
    exx
    ex af,af'                           ; (as the grass block left them)
    ld hl,line_go_a
    ld (tb_jp+1),hl                     ; no more stripes
    ld de,(rd_mid_t)
    ld ix,(line_ptr)
    ld (ix-2),e
    ld (ix-1),d
    ld hl,0
    add hl,sp                           ; HL = the screen
    ld a,c
    cp lo(GRASS_PAIR)
    jr z,tm_mid_go                      ; that green already
    ld bc,GRASS_PAIR
    ld (rd_grass),bc
    ld sp,(rd_gbp)                      ; noted (IX: the list past the line)
    push ix
    ld (rd_gbp),sp
tm_mid_go
    bit 5,d                             ; (a near row's: band B's may be)
    jp z,line_go_a
    jp to_band_b

;; (render_end) the end of the buffer's grass changes, and back
rd_end
    ld sp,(rd_gbp)
    ld hl,0
    push hl
    ld sp,(rd_save_sp)
    ei
    ret

;; rp_zsets - (road_project) A = zcam's low byte: twice it - the stripes'
;; coordinates are depth and zcam doubled (cpcgfx.STRIPE_K) - into its loops.
rp_zsets
    add a,a
    ld (rp_zlo+1),a
    ld (rp_zlo2+1),a
    ld (rp_zlo3+1),a
    ld (rp_zlo4+1),a
    ld (rp_zlo5+1),a
    ld (rp_zlo6+1),a
    ld (rp_zlo7+1),a
    ld (rp_zlo9+1),a
    ld (rp_zlo10+1),a
    ld (rp_zlo11+1),a
    ret

    INCLUDE "trafglue.asm"
    ASSERT $ <= FRAG3+FRAG_LEN

    ORG FRAG4,FRAG_ST4
    defs LIST_GUARD,0
list1
    ASSERT (list1 & 3) == 0
    defs LIST_LEN,0

;; ---------------------------------------------------------------------------
;; rp_grass - (road_project, at the end) the grass's stripes for road_draw:
;; the bottom line's green in rd_grass0, and tmpl_mid in place of the first
;; line past GRASS_ROW if it is drawn, its own template in rd_mid_t. RAM_C6.
;; Destroys AF, DE, HL.
;; ---------------------------------------------------------------------------
    ASSERT GRASS_SHIFT == 7
rp_grass
    ld hl,(rp_vars)
    ld a,(hl)                           ; the hill level now
    ld l,a
    ld h,0
    add hl,hl
    ld de,level_addr
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a                              ; HL = its line -> row table
    push hl
    ld l,(hl)                           ; the bottom line's row (a near one)
    ld h,hi(rr_depth)
    ld a,(rp_zlo+1)                     ; zcam, doubled (rp_zsets)
    add a,(hl)
    rla                                 ; CF: its stripe
    ld a,lo(GRASS_PAIR)
    jr nc,$+4
    xor GRASS_X
    ld (rd_grass0),a
    pop hl
    ld a,(rp_near)                      ; back from the last near line to the
    ld e,a                              ; first past GRASS_ROW (a few: the
    ld d,0                              ; rows from FAR_Z on are near ones)
    add hl,de
rp_grass_back
    ld a,e
    or a
    jr z,rp_grass_at
    dec hl
    ld a,(hl)
    cp GRASS_ROW
    jr nc,rp_grass_at
    dec e
    jr rp_grass_back
rp_grass_at                             ; E: that line
    ld l,e
    ld h,0
    add hl,hl
    add hl,hl
    ld de,(rp_slot)
    add hl,de                           ; its template slot
    ex de,hl
    ld hl,(rp_tail)
    or a
    sbc hl,de
    ret c
    ret z                               ; not drawn: the end marker's or past
    ex de,hl
    ld e,(hl)
    ld (hl),lo(tmpl_mid)
    inc hl
    ld d,(hl)
    ld (hl),hi(tmpl_mid)
    ld (rd_mid_t),de
    ret

;; The ways to a line's road and margin when some lines are skipped too
;; (rp_skip_jr): flag 3 is a line that is already right.
line_margin_sa
    bit 1,l
    jp nz,line_done_a
    jp line_margin_a
line_margin_sb
    bit 1,l
    jp nz,line_done_b
    jp line_margin_b
line_lmarg_sa
    bit 1,l
    jp nz,line_done_a
    jp line_lmarg_a
line_lmarg_sb
    bit 1,l
    jp nz,line_done_b
    jp line_lmarg_b

;; rp_skip_jr - (road_project) lines skipped (rp_skip) as well as drawn
;; with a margin: road_draw's way to a margin looks for flag 3 first.
rp_skip_jr
    ld a,(rp_skip)
    or a
    ret z
    ld hl,(lg_jr_a+1)
    ld a,l
    ld hl,line_margin_sa
    ld de,line_margin_sb
    cp lo(line_margin_a)
    jr z,rp_skip_jr_set
    ld hl,line_lmarg_sa
    ld de,line_lmarg_sb
    cp lo(line_lmarg_a)
    jr z,rp_skip_jr_set
    ld hl,line_rmarg_sa
    ld de,line_rmarg_sb
    cp lo(line_rmarg_a)
    ret nz                              ; (line_road_a looks for it already)
rp_skip_jr_set
    ld (lg_jr_a+1),hl
    ld (lg_jr_b+1),de
    ret
    ASSERT lo(line_margin_a) != lo(line_lmarg_a) && lo(line_margin_a) != lo(line_road_a) && lo(line_lmarg_a) != lo(line_road_a)
    ASSERT lo(line_rmarg_a) != lo(line_margin_a) && lo(line_rmarg_a) != lo(line_lmarg_a) && lo(line_rmarg_a) != lo(line_road_a)
    ASSERT lo(line_margin_a) != lo(line_margin_sa) && lo(line_lmarg_a) != lo(line_margin_sa) && lo(line_margin_a) != lo(line_lmarg_sa) && lo(line_lmarg_a) != lo(line_lmarg_sa)
    ASSERT lo(line_rmarg_sa) != lo(line_margin_a) && lo(line_rmarg_sa) != lo(line_lmarg_a) && lo(line_rmarg_sa) != lo(line_rmarg_a)
    ASSERT lo(line_rmarg_a) != lo(line_margin_sa) && lo(line_rmarg_a) != lo(line_lmarg_sa)

;; rp_dzset - (road_project, after rp_mode: A = 0 if every near line is to
;; be drawn whole, or the rows compared) rp_skip_jr; this buffer's zcam then
;; into the loops, and twice its move since (rp_dz: RP_LINE), or 255 for
;; whole lines - or a move of a kerb stripe or more. Keeps BC.
rp_dzset
    push af
    call rp_skip_jr
    ld hl,(rp_vars)
    inc hl
    inc hl
    inc hl
    inc hl                              ; rp_zcam
    ld a,(hl)
    ld (rp_zold+1),a
    ld (rp_zold2+1),a
    ld (rp_zo+1),a
    ld e,a
    ld a,(rp_zlo+1)                     ; zcam, doubled (rp_zsets)
    ld (hl),a
    sub e                               ; the move since then
    cp 64
    ld e,255
    jr c,rp_dzset_n
    xor a                               ; a kerb stripe or more: no line is
    ld (rp_skip),a                      ; skipped (its stripe can have gone
    ld a,#B7                            ; round)
    ld (rp_cmp_sk),a                    ; (OR A)
    jr rp_dzset_w
rp_dzset_n
    add a,a
    ld e,a
rp_dzset_w
    pop af
    or a
    jr nz,rp_dzset_go
    ld a,(rp_cmp)
    or a
    jr nz,rp_dzset_go
    ld e,255                            ; every line whole
rp_dzset_go
    ld a,e
    ld (rp_dz+1),a
    ld (rp_dz2+1),a
    ld (rp_dz7+1),a
    ld (rp_dz8+1),a
    ret

    INCLUDE "gen/trafcode_f4.asm"
    ASSERT $ <= FRAG4+FRAG_LEN
