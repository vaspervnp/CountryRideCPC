;; ===========================================================================
;; game.asm - the main loop (bank 7, RAM_C1, #C000).
;;
;; One picture every two VSYNCs: the HUD changes and the road are drawn into
;; the buffer that is not on screen, then the interrupt handler shows it at
;; the next VSYNC that is at least two frames after the last one.
;;
;; This milestone has no car and no player: it drives a plain four-lane road
;; over a looping run of crests and dips, and fills the HUD with plausible
;; numbers, so the screen layout and the frame rate can be judged.
;; ===========================================================================

back_buf    defb 1              ; the buffer being drawn
last_vbl    defb 0              ; vbl_count when the last picture started
hud_tick    defb 1              ; pictures until the HUD takes a new copy

;; --- the demo car's state -------------------------------------------------------
speed       defw 0              ; depth units per VSYNC, 8.8
speed_phase defw 0              ; where in the accelerate/cruise/brake cycle
time_vbls   defb 50             ; VSYNCs left in the current second
fuel_vbls   defw 0

SPEED_MAX   EQU #0380           ; 3.5 depth units per VSYNC: a stripe in ~5
SPEED_ACC   EQU 3               ; per VSYNC, 8.8 - full speed in ~6 s
SPEED_BRK   EQU 6
GEAR_STEP   EQU SPEED_MAX/6+1   ; speed per gear
MAX_STEPS   EQU 4               ; 50 Hz steps caught up per picture at most

;; ---------------------------------------------------------------------------
;; game_start - entered from boot.asm with RAM_C1, interrupts on.
;; ---------------------------------------------------------------------------
game_start
    ld sp,STACK_TOP
    call road_reset

    ; draw the parts that never change into both buffers, then a first
    ; picture into each, and only then light the palette
    call hud_forget
    call hud_snapshot
    xor a
    call draw_screen
    ld a,1
    call draw_screen
    xor a
    call draw_picture
    ld a,1
    call draw_picture
    ld hl,palette_hw
    call set_palette
    ld a,(vbl_count)            ; the drive starts now, not when the
    ld b,a                      ; machine was switched over - and at a
game_sync                       ; VSYNC, so the first picture has all of
    ld a,(vbl_count)            ; its two frames
    cp b
    jr z,game_sync
    ld (last_vbl),a

main_loop
    ld a,(vbl_count)
    ld hl,last_vbl
    ld b,(hl)
    ld (hl),a
    sub b                       ; VSYNCs since the last picture: normally 2
    ld (frame_vbls),a
    cp 3
    jr c,main_on_time
    ld hl,(frames_late)
    inc hl
    ld (frames_late),hl
    cp MAX_STEPS+1              ; a long stall is not caught up all at
    jr c,main_on_time           ; once, or the next picture is late too
    ld a,MAX_STEPS
main_on_time
    or a                        ; none yet on the very first picture
    jr z,main_draw
    ld b,a
main_steps
    push bc
    call demo_step              ; the game thinks at 50 Hz
    pop bc
    djnz main_steps

main_draw
    ld hl,hud_tick              ; the HUD's values, every HUD_EVERY pictures
    dec (hl)
    jr nz,main_hud_kept
    ld (hl),HUD_EVERY
    call hud_snapshot
main_hud_kept
    ld a,(back_buf)
    call draw_picture

    ; show it at the next VSYNC that keeps the 25 Hz cadence
    ld a,(back_buf)
    or a
    ld a,BUF0_R12
    jr z,main_flip
    ld a,BUF1_R12
main_flip
    ld (flip_req),a
main_wait
    ld a,(flip_req)
    or a
    jr nz,main_wait
    ld a,(back_buf)
    ld (front_buf),a
    xor 1
    ld (back_buf),a
    ld hl,(frames_drawn)
    inc hl
    ld (frames_drawn),hl
    jr main_loop

;; ---------------------------------------------------------------------------
;; draw_screen - A = buffer: everything but the road, the whole HUD included
;; (hud_update draws one thing at a time, so it is called until it is done).
;; ---------------------------------------------------------------------------
draw_screen
    call select_buf
    call draw_static
    ld b,8
draw_screen_hud
    push bc
    call hud_update
    pop bc
    djnz draw_screen_hud
    SET_RAM RAM_C1
    ret

;; ---------------------------------------------------------------------------
;; draw_picture - A = buffer: HUD changes, then the road.
;; ---------------------------------------------------------------------------
draw_picture
    push af
    call select_buf
    call hud_update
    SET_RAM RAM_C1
    pop af
    ld (road_buf),a
    jp road_frame

;; ---------------------------------------------------------------------------
;; set_palette - HL = 16 Gate Array colour bytes. Border black.
;; ---------------------------------------------------------------------------
set_palette
    ld bc,#7F00
set_palette_loop
    out (c),c                   ; select pen C
    ld a,(hl)
    out (c),a
    inc hl
    inc c
    ld a,c
    cp 16
    jr c,set_palette_loop
    ld a,#10
    out (c),a                   ; the border
    ld a,BORDER_HW
    out (c),a
    ret

;; ---------------------------------------------------------------------------
;; demo_step - one VSYNC of the demo drive.
;; ---------------------------------------------------------------------------
demo_step
    ; speed: accelerate for 10 s, cruise for 6 s, brake for 4 s, repeat
    ld hl,(speed_phase)
    inc hl
    ld a,h
    cp hi(1000)
    jr c,demo_phase_ok
    jr nz,demo_phase_wrap
    ld a,l
    cp lo(1000)
    jr c,demo_phase_ok
demo_phase_wrap
    ld hl,0
demo_phase_ok
    ld (speed_phase),hl
    ld de,(speed)
    ld bc,800                   ; 16 s in: brake
    or a
    sbc hl,bc
    jr nc,demo_brake
    ld hl,SPEED_ACC
    add hl,de
    ld bc,SPEED_MAX
    or a
    sbc hl,bc
    jr c,demo_acc_ok
    ld hl,0
demo_acc_ok
    add hl,bc
    jr demo_speed_set
demo_brake
    ex de,hl
    ld bc,SPEED_BRK
    or a
    sbc hl,bc
    jr nc,demo_speed_set
    ld hl,0
demo_speed_set
    ld (speed),hl

    ; move the camera: zcam += speed (8.8; the fraction is kept in zfrac)
    ld a,(zfrac)
    add a,l
    ld (zfrac),a
    ld a,h
    ld hl,(zcam)
    adc a,l
    ld l,a
    jr nc,demo_z_ok
    inc h
demo_z_ok
    ld (zcam),hl

    ; the hill under the camera: hill_profile[(zcam / 32) mod 256]
    add hl,hl
    add hl,hl
    add hl,hl                   ; H = zcam / 32
    ld l,h
    ld h,0
    ld de,hill_profile
    add hl,de
    ld a,(hl)
    ld (hill),a

    ; gauges and gear from the speed
    ld hl,(speed)
    ld a,h                      ; speed / (SPEED_MAX/GAUGE_SEGS) -> segments
    ld b,0
    ld de,SPEED_MAX/GAUGE_SEGS
demo_seg
    or a
    sbc hl,de
    jr c,demo_seg_done
    inc b
    jr demo_seg
demo_seg_done
    ld a,b
    cp GAUGE_SEGS+1
    jr c,demo_seg_ok
    ld a,GAUGE_SEGS
demo_seg_ok
    ld (speed_level),a
    ld hl,(speed)
    ld a,h
    or l
    ld b,0
    jr z,demo_gear_done         ; standing still: neutral
    ld de,GEAR_STEP
demo_gear
    inc b
    or a
    sbc hl,de
    jr nc,demo_gear
demo_gear_done
    ld a,b
    cp 7
    jr c,demo_gear_ok
    ld a,6
demo_gear_ok
    ld (gear),a

    ; TIME counts down a second at a time, from 60, round and round
    ld hl,time_vbls
    dec (hl)
    jr nz,demo_time_done
    ld (hl),50
    ld hl,time_left
    dec (hl)
    jr nz,demo_time_done
    ld (hl),60
demo_time_done

    ; TOTAL TIME counts up two hundredths a VSYNC: m'ss"cc
    ld hl,total_time+4
    ld a,(hl)
    add a,2
    cp 10
    jr c,demo_tt_set
    sub 10
    ld (hl),a
    dec hl                      ; cs tens
    inc (hl)
    ld a,(hl)
    cp 10
    jr c,demo_tt_done
    ld (hl),0
    dec hl                      ; s units
    inc (hl)
    ld a,(hl)
    cp 10
    jr c,demo_tt_done
    ld (hl),0
    dec hl                      ; s tens
    inc (hl)
    ld a,(hl)
    cp 6
    jr c,demo_tt_done
    ld (hl),0
    dec hl                      ; minutes
    inc (hl)
    ld a,(hl)
    cp 10
    jr c,demo_tt_done
    ld (hl),0
    jr demo_tt_done
demo_tt_set
    ld (hl),a
demo_tt_done

    ; FUEL drops a segment every eight seconds and is refilled when empty
    ld hl,(fuel_vbls)
    inc hl
    ld (fuel_vbls),hl
    ld bc,400
    or a
    sbc hl,bc
    ret c
    ld hl,0
    ld (fuel_vbls),hl
    ld hl,fuel_level
    dec (hl)
    ret p
    ld (hl),GAUGE_SEGS
    ret

zfrac       defb 0
