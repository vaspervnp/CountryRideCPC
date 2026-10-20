;; ===========================================================================
;; game.asm - the main loop (bank 7, RAM_C1, #C000).
;;
;; One picture every two VSYNCs: the HUD changes and the road are drawn into
;; the buffer that is not on screen, then the interrupt handler shows it at
;; the next VSYNC that is at least two frames after the last one.
;;
;; This milestone has no car and no player: it drives a plain four-lane road
;; over a looping run of crests, dips and curves, and fills the HUD with
;; plausible numbers, so the screen layout and the frame rate can be judged.
;; ===========================================================================

back_buf    defb 1              ; the buffer being drawn
last_vbl    defb 0              ; vbl_count when the last picture started
hud_tick    defb 1              ; pictures until the HUD takes a new copy

;; --- the demo car's state -------------------------------------------------------
speed       defw 0              ; depth units per VSYNC, 8.8
speed_phase defw 0              ; where in the accelerate/cruise/brake cycle
time_vbls   defb 50             ; VSYNCs left in the current second
fuel_vbls   defw 0
drawn_curve defb 0,0            ; curve level each buffer was drawn with
pic_bent    defb 0              ; 1: this picture's curve level is new to
                                ; its buffer
heading     defb 0              ; where the sky looks: words right
head_acc    defw 0              ; turning towards the next word, signed

SPEED_MAX   EQU #0540           ; 5.25 depth units per VSYNC: a stripe in ~3
SPEED_ACC   EQU 5               ; per VSYNC, 8.8 - full speed in ~5.4 s
SPEED_BRK   EQU 9
GEAR_STEP   EQU SPEED_MAX/6+1   ; speed per gear
MAX_STEPS   EQU 4               ; 50 Hz steps caught up per picture at most
HEAD_STEP   EQU 128             ; curve level x depth units for the sky to
                                ; turn a word: at the strongest level and
                                ; full speed, a word every 2 pictures

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
    call draw_ring
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
    call demo_gauges
    call hud_snapshot
main_hud_kept
    ld a,(back_buf)
    call draw_picture

    ; show it at the next VSYNC that keeps the 25 Hz cadence, its horizon
    ; as far down as its road's top, its sky looking its way - unless its
    ; road bent further (draw_picture): the sky then turns with the next
    ; picture, which has the time
    call picture_drop
    ld (flip_drop),a
    call picture_heading
    ld hl,pic_bent
    bit 0,(hl)
    jr z,main_head
    ld a,(ring_head)
main_head
    ld (flip_head),a
    ld a,(back_buf)
    inc a
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
;; (hud_update draws a picture's share at a time, so it is called until it is
;; done).
;; ---------------------------------------------------------------------------
draw_screen
    call select_buf
    call draw_static
    ld b,16
draw_screen_hud
    push bc
    call hud_update
    pop bc
    djnz draw_screen_hud
    SET_RAM RAM_C1
    ret

;; ---------------------------------------------------------------------------
;; draw_picture - A = buffer: HUD changes, then the road.
;;
;; When the curve level is not the one the buffer was last drawn with, every
;; far road line moves and is drawn again (~2.5 ms more): the HUD then waits
;; for the buffer's next picture, and the sky's turn for the next picture
;; (pic_bent), so the picture keeps to its 40 ms.
;; ---------------------------------------------------------------------------
draw_picture
    push af
    call select_buf
    ld hl,drawn_curve
    call buf_entry
    ld a,(curve)
    cp (hl)
    ld (hl),a                   ; (the flags are cp's)
    ld hl,pic_bent
    ld (hl),0
    jr nz,draw_picture_bent
    call hud_update
    jr draw_picture_road
draw_picture_bent
    inc (hl)
draw_picture_road
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
;; demo_gauges - the speed gauge and the gear, from the speed: only the HUD
;; shows them, so they are worked out when it takes its copy.
;; ---------------------------------------------------------------------------
demo_gauges
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

    ; the hill and the curve under the camera: hill_profile and
    ; curve_profile[(zcam / 32) mod 256]
    add hl,hl
    add hl,hl
    add hl,hl                   ; H = zcam / 32
    ld l,h
    ld h,0
    ld de,hill_profile
    add hl,de
    ld a,(hl)
    ld (hill),a
    ld de,curve_profile-hill_profile
    add hl,de
    ld a,(hl)
    ld (curve),a

    ; the sky turns with the road: head_acc += curve x speed (whole depth
    ; units a VSYNC), a word right or left every HEAD_STEP
    ld e,a
    ld d,0
    rla
    jr nc,demo_head_pos
    dec d                       ; DE = curve level, sign extended
demo_head_pos
    ld a,(speed+1)
    or a
    jr z,demo_head_done
    ld b,a
    ld hl,(head_acc)
demo_head_mul
    add hl,de
    djnz demo_head_mul
    ld (head_acc),hl
    bit 7,h
    jr nz,demo_head_left
    ld de,-HEAD_STEP
    add hl,de
    jr nc,demo_head_done        ; not a word yet
    ld (head_acc),hl
    ld a,(heading)
    inc a
    cp PANO_WORDS
    jr c,demo_head_set
    xor a
    jr demo_head_set
demo_head_left
    ld de,HEAD_STEP
    add hl,de
    jr c,demo_head_done
    ld (head_acc),hl
    ld a,(heading)
    or a
    jr nz,demo_head_dec
    ld a,PANO_WORDS
demo_head_dec
    dec a
demo_head_set
    ld (heading),a
demo_head_done

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
