;; ===========================================================================
;; game.asm - the main loop (bank 7, RAM_C1, #C000).
;;
;; One picture every two VSYNCs: the HUD changes and the road are drawn into
;; the buffer that is not on screen, then the interrupt handler shows it at
;; the next VSYNC that is at least two frames after the last one.
;;
;; This milestone drives a plain four-lane road over a looping run of
;; crests, dips and curves, and fills the HUD with plausible numbers; the
;; player's car stays in the middle, and the player steers it (the road
;; moves under it) - the demo does until then.
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
drawn_x     defb 0,0            ; ... and road_x
curve_wait  defb 0              ; pictures before the curve level may move
sky_turns   defb 0              ; not 0: the sky turns at this flip
steer_x     defb 0              ; where the player wants road_x
car_view    defb 0              ; the car seen straight, turning left, right
drawn_view  defb 0,0            ; ... as each buffer last showed it
drift_acc   defw 0              ; a curve carrying the car out (steer)
player      defb 0              ; not 0: the player has steered (#FF: the
                                ; tools do, setting steer_x)
demo_t      defw 0              ; pictures, for the demo's steering
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
    call cache_init             ; the cache sets, for the road in the middle

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
    ld hl,curve_wait
    ld a,(hl)
    or a
    jr z,main_curve_free
    dec (hl)
main_curve_free
    ld hl,hud_tick              ; the HUD's values, every HUD_EVERY pictures
    dec (hl)
    jr nz,main_hud_kept
    ld (hl),HUD_EVERY
    call demo_gauges
    call hud_snapshot
main_hud_kept
    ld a,(back_buf)
    call draw_picture
picture_done                    ; (tools/run.py looks at the picture here)

    ; show it at the next VSYNC that keeps the 25 Hz cadence, its horizon
    ; as far down as its road's top, its sky looking its way - unless its
    ; road bent further (draw_picture), or its hill moved or a hill is near
    ; (the next picture would pay for both): the sky then turns with a later
    ; picture, which has the time
    call picture_drop
    ld (flip_drop),a
    call hill_near              ; (destroys B)
    ld hl,pic_bent
    ld b,(hl)
    jr z,$+3
    inc b
    call sky_next               ; (common.asm; keeps B)
    jr z,$+3
    inc b
    ld hl,rp_cmp
    call picture_heading
    ld c,a
    ld a,b
    or (hl)
    ld a,c
    jr z,main_head
    ld a,(ring_head)
main_head
    ld (flip_head),a
    ld hl,ring_head
    sub (hl)
    ld (sky_turns),a
    ld a,(back_buf)
    inc a
    ld (flip_req),a
main_asked                      ; (tools/run.py: the picture's deadline)
    call steer
    xor a
    ld (rd_s),a                 ; (cache_step: a step now)
    ld a,(irq_n)                ; the road's next steps, if they and the
    cp STEPS_LATE               ; first of the cache's work can be done
    jr nc,main_wait             ; before the flip (not after it: the next
    ld a,(flip_req)             ; picture would start that late)
    or a
    call nz,cache_steps
main_wait                       ; the cache's work until the flip
    ld a,(irq_n)                ; (cache_job) - none in its last 3.3 ms
    cp JOB_LATE                 ; (JOB_LATE), so none can start just
    jr nc,main_spin             ; after it either
    ld a,(flip_req)
    or a
    jr z,main_flipped
    call cache_job
main_job                        ; (tools: timing)
    jr main_wait
main_spin
    ld a,(flip_req)
    or a
    jr nz,main_spin
main_flipped
    ld a,(back_buf)
    ld (front_buf),a
    xor 1
    ld (back_buf),a
    ld hl,(frames_drawn)
    inc hl
    ld (frames_drawn),hl
    jp main_loop

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
;; draw_picture - A = buffer: HUD changes, last time's bushes taken away,
;; the road, then this picture's bushes and the car (bush.asm).
;;
;; The road's curve level and road_x are the cache's (cache_idle): one
;; level for both buffers. When this buffer last showed another level, the
;; road has moved sideways on most lines and road_project draws them with a
;; margin of grass (~6 ms more): the HUD then has a smaller share, and the
;; sky's turn waits for the next picture (pic_bent). The HUD has the
;; smaller share too when road_x has moved since then.
;; ---------------------------------------------------------------------------
draw_picture
    push af
    call select_buf
    ld b,HUD_SHARE
    ld c,0
    ld hl,drawn_curve
    call buf_entry              ; HL = the level this buffer was drawn with
    ld a,(road_curve)
    cp (hl)
    ld (hl),a
    jr z,draw_picture_x
    ld b,HUD_SHARE_LOW          ; a new level
    inc c
draw_picture_x
    ld a,c
    ld (pic_bent),a
    ld hl,drawn_x
    call buf_entry
    ld a,(road_x)
    cp (hl)
    ld (hl),a
    jr z,draw_picture_hud
draw_picture_low                ; the road moved sideways
    ld b,HUD_SHARE_LOW
draw_picture_hud
    ld a,b
    ld (hud_quota),a
    call hud_update
pic_hud                         ; (tools: how long each part takes)
    SET_RAM RAM_C1
    call bush_erase             ; last time's bushes, before the road
pic_erased
    pop af
    ld (road_buf),a
    call road_frame
pic_road
    call bush_draw              ; this picture's on top of it
pic_bushes
    jp car_draw                 ; and the car on top of all

;; ---------------------------------------------------------------------------
;; cache_steps - after a picture: the road's next steps (cache.asm), whose
;; templates cache_job then works out while the picture waits for its flip.
;;
;; Nothing moves on a hill or just before one, nor while the last
;; picture's hill moved (as the road leaves a hill): a picture whose hill
;; moves compares each line's row with then's, and a new level or a step
;; sideways on top of that - or the cache catching up with a level - is too
;; much. A new level and a step sideways wait for a hill HILL_STEP_AHEAD
;; track entries ahead: the two pictures either makes heavy (both buffers
;; draw all of the road moved) are done by then. (The track has no curve
;; on a hill: a level only waits when it is late; the road waits to move
;; sideways.)
;;
;; The curve level moves a level towards the game's - not within two
;; pictures of the last move, so that a buffer's road moves a level at most
;; between two of its pictures - holding back the sky's turn at this flip
;; (sky_stay: the next picture would pay for both). With the road in the
;; middle that is
;; all (the curve levels' own sets are drawn, and the cache follows them
;; when it can); off it, only once the cache has the level worked out
;; ahead, and then all of the road moves to it at once (cache_kstep).
;;
;; Then road_x moves two pairs towards steer_x - always two, so it is
;; always even: with steer_x a pair from it, it waits - the whole cache with
;; it (cache_step), out of the middle only once the cache has caught up with
;; the curve level, into it only once it has caught up too. A step the
;; cache has worked out ahead
;; (cache_ready) is only copied into place, ~5 ms, and goes whenever this
;; runs; else it is made there and then, and only if it is sure to be done
;; before the flip (STEP_LATE): else the road waits a picture, which then
;; is lighter (nothing moved sideways) and leaves the time. A step holds the
;; sky's turn and the cache's jobs back for a picture.
;; ---------------------------------------------------------------------------
cache_steps
    ld a,(rp_cmp)               ; the last picture's hill did not move
    or a
    ret nz
    ld b,HILL_STEP_AHEAD+1      ; nor is a hill here or just ahead
    call hill_near_b
    ret nz
    ld a,(curve_wait)
    or a
    jr nz,cache_steps_x
    ld a,(curve)
    ld hl,road_curve
    sub (hl)
    jr z,cache_steps_x
    ld c,a
    ld a,(road_x)
    or a
    jp nz,cache_kstep           ; off the middle: worked out ahead (cache.asm)
    ld a,c
    or a
    ld a,1
    jp p,cache_steps_kd
    ld a,-1
cache_steps_kd
    push af
    add a,(hl)
    ld (hl),a
    ld a,2
    ld (curve_wait),a
    pop af
    call cache_curve
    call sky_stay               ; (the next picture has the road bent)
cache_steps_x
    ld a,(back_buf)             ; no more than 2 pairs from where the next
    xor 1                       ; picture's buffer last had it (the margin
    ld hl,drawn_x               ; it draws): two steps of two in a row would
    add a,l                     ; make it 4
    ld l,a
    ASSERT hi(drawn_x) == hi(drawn_x+1)
    ld c,(hl)
    ld a,(steer_x)
    sub c
    ld b,2
    call clamp_ab
    add a,c
    ld hl,road_x
    sub (hl)
    ret z
    ld c,a
    ld a,(hl)
    or a
    jr nz,cache_steps_go
    ld a,(rd_n2)                ; leaving the middle
    or a
    ret nz
cache_steps_go
    call cache_ready            ; (one worked out ahead: its own gate)
    jr nz,cache_steps_gate
    ld b,STEP_LATE              ; only if it is done before the flip: a
    ld a,(road_curve)           ; pair takes up to ~13.5 ms (two ~14.2 ms) -
    ld e,a                      ; ~14.7 ms (two ~16.1 ms) with the road 8
    ld a,(road_x)               ; pairs or more to the side a curve of 3
    bit 7,e                     ; levels or more bends to (many groups cut
    jr z,$+4                    ; short on that side): a tick earlier then;
    neg                         ; two pairs (all there are) a tick earlier
    cp 8
    jp m,cache_steps_gate
    ld a,e
    add a,2
    cp 5
    jr c,cache_steps_gate
    dec b
cache_steps_gate
    ld a,c
    or a
    jp p,$+5
    neg
    cp 2
    ret c                       ; (a pair is all it is to go: it waits)
    ld a,(curve_wait)           ; (nor while a new curve level has the
    or a                        ; road drawn with a margin)
    ret nz
    ld a,(irq_n)
    inc a
    cp b
    ret nc
    ld b,2                      ; two pairs
    ld a,c
    call clamp_ab
    ld c,a
    ld hl,road_x
    add a,(hl)
    jr nz,cache_steps_step
    ld a,(rd_n2)                ; into the middle only once the cache has
    or a                        ; caught up (the level's own set is the
    ret nz                      ; same then)
cache_steps_step
    ld a,c
    call cache_step
    jp sky_stay                 ; (the next picture has the road moved)

;; ---------------------------------------------------------------------------
;; steer - where the road is to go (steer_x), once a picture, and how the
;; car is seen (car_view).
;;
;; The player: a pair right of where the road is while left is held - the
;; car goes left, so the road under it goes right - a pair left while
;; right is. And a curve carries the car out of it: drift_acc adds up the
;; curve level x the speed, and every DRIFT_STEP of it is a pair outwards -
;; out of a right curve the car goes left, the road right. Steering against
;; it, the two cancel; with neither, the car ends up on the grass. The car
;; is seen turning while left or right is held (not both).
;;
;; Until the player first steers, the demo does: a new place every
;; DEMO_HOLD pictures, the car seen turning while the road moves to it.
;; ---------------------------------------------------------------------------
DEMO_HOLD   EQU 128
HILL_AHEAD  EQU 3               ; track entries (32 depth units) the sky's
                                ; turn looks ahead for a hill (main)
HILL_STEP_AHEAD EQU 2           ; ... and a new curve level or a step
                                ; sideways (~6 pictures at full speed)
STEPS_LATE  EQU 10              ; from this interrupt since the flip on, no
                                ; steps
STEP_LATE   EQU 8               ; ... and no road_x step
STEER_AHEAD EQU 2               ; pairs steer_x may be from road_x
DRIFT_STEP  EQU 48              ; curve level x depth units a VSYNC, a pair:
                                ; ~0.5 pairs a picture on a level 5 curve at
                                ; full speed

steer
    call read_keys
    ld c,a
    ld a,(player)
    inc a
    jp z,steer_look             ; (#FF: tools/ steer by steer_x)
    dec a
    or c
    jp z,steer_demo
    ld (player),a
    ld a,c                      ; B = the pairs the player moves the road:
    and 3                       ; left 1, right -1, neither or both 0 - and
    ld b,0                      ; car_view 1, 2, 0
    jr z,steer_keys
    cp 3
    jr z,steer_both
    inc b
    cp 1
    jr z,steer_keys
    ld b,-1
    jr steer_keys
steer_both
    xor a
steer_keys
    ld (car_view),a

    ld a,(road_curve)           ; drift_acc += curve level x speed
    ld e,a
    ld d,0
    rla
    jr nc,steer_dk
    dec d                       ; DE = the level, sign extended
steer_dk
    ld a,(speed+1)
    or a
    jr z,steer_to
    ld hl,(drift_acc)
    push bc
    ld b,a
steer_dmul
    add hl,de
    djnz steer_dmul
    pop bc
    ld (drift_acc),hl
    bit 7,h
    jr nz,steer_dleft
    ld de,-DRIFT_STEP
    add hl,de
    jr nc,steer_to              ; not a pair yet
    inc b                       ; a pair right
    jr steer_dset
steer_dleft
    ld de,DRIFT_STEP
    add hl,de
    jr c,steer_to
    dec b                       ; a pair left
steer_dset
    ld (drift_acc),hl

steer_to
    ld a,b                      ; a pair a picture at most, either way, on
    ld b,1                      ; from where the road was to go - no more
    call clamp_ab               ; than STEER_AHEAD from where it is (the
    ld b,a                      ; road goes 2 pairs a step, so it needs
    ld a,(steer_x)              ; that much), nor ROAD_X_MAX from the
    add a,b                     ; middle
    ld hl,road_x
    sub (hl)
    ld b,STEER_AHEAD
    call clamp_ab
    add a,(hl)
    ld b,ROAD_X_MAX
    call clamp_ab
    ld (steer_x),a
    ret

;; clamp_ab - A (signed) no more than B either way. Destroys F.
clamp_ab
    bit 7,a
    jr nz,clamp_ab_neg
    cp b
    ret c
    ld a,b
    ret
clamp_ab_neg
    neg
    cp b
    jr c,$+3
    ld a,b
    neg
    ret

steer_demo
    ld hl,(demo_t)
    inc hl
    ld (demo_t),hl
    add hl,hl                   ; H = demo_t / DEMO_HOLD
    ld a,h
    and 7
    ld l,a
    ld h,0
    ld de,demo_steer
    add hl,de
    ld a,(hl)
    ld (steer_x),a
steer_look                      ; the car turns the way the road is to go
    ld a,(road_x)
    ld b,a
    ld a,(steer_x)
    sub b
    jr z,steer_look_set         ; straight on
    ld a,1                      ; the road right: the car turns left
    jp p,steer_look_set
    inc a
steer_look_set
    ld (car_view),a
    ret
demo_steer
    defb 0,12,24,ROAD_X_MAX,16,-8,-28,-12

;; ---------------------------------------------------------------------------
;; read_keys - A: bit 0 = left held (cursor left, O, joystick left), bit 1 =
;; right (cursor right, P, joystick right). The keyboard is read through the
;; PSG's port (register 14), the PPI's port A turned round for it. Destroys
;; BC, DE.
;; ---------------------------------------------------------------------------
read_keys
    ld bc,#F40E                 ; PSG register 14
    out (c),c
    ld bc,#F6C0                 ; (latched)
    out (c),c
    ld c,0
    out (c),c
    ld bc,#F792                 ; PPI port A in
    out (c),c
    ld a,#40                    ; row 0: cursor right (bit 1)
    call rk_row
    and 2
    ld e,a
    ld a,#41                    ; row 1: cursor left (bit 0)
    call rk_row
    and 1
    or e
    ld e,a
    ld a,#43                    ; row 3: P (bit 3)
    call rk_row
    and 8
    ld d,a
    ld a,#44                    ; row 4: O (bit 2)
    call rk_row
    and 4
    or d
    ld d,a
    ld a,#49                    ; row 9: joystick left, right (bits 2, 3)
    call rk_row
    and #0C
    or d
    rrca
    rrca
    or e
    ld e,a
    ld bc,#F782                 ; port A out again
    out (c),c
    ld bc,#F600
    out (c),c
    ld a,e
    ret
rk_row                          ; A = #40 + row: its keys, 1 = held
    ld b,#F6
    out (c),a
    ld b,#F4
    in a,(c)
    cpl
    ret

;; ---------------------------------------------------------------------------
;; set_palette - HL = 16 Gate Array colour bytes. Border black. Interrupts
;; off meanwhile: irq_road selects the border to colour it, and between a
;; pen's selection and its colour that left the pen as it was (black).
;; ---------------------------------------------------------------------------
set_palette
    di
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
    ei
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
