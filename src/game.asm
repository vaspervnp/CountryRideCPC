;; ===========================================================================
;; game.asm - the main loop (bank 7, RAM_C1, #C000).
;;
;; One picture every two VSYNCs: the HUD changes and the road are drawn into
;; the buffer that is not on screen, then the interrupt handler shows it at
;; the next VSYNC that is at least two frames after the last one.
;;
;; A plain four-lane road over crests, dips and curves (course.asm). The
;; demo drives a loop of them until fire is pressed; then the car stops on
;; the flat, the count goes 3-2-1 and the player races the clock over the
;; stages of the course: TIME counts down, the checkpoint at each stage's
;; end gives more, the last one is the finish, and at 0 the car stops; then
;; the demo drives again (rules_vbl).
;; ===========================================================================

back_buf    defb 1              ; the buffer being drawn
last_vbl    defb 0              ; vbl_count when the last picture started
hud_tick    defb 1              ; pictures until the HUD takes a new copy

;; --- the race --------------------------------------------------------------
MODE_DEMO   EQU 0               ; the demo drives; fire starts a race
MODE_READY  EQU 1               ; to a standstill at the start, the count
MODE_RACE   EQU 2               ; the player races the clock
MODE_OVER   EQU 3               ; time up: to a standstill, GAME OVER
START_TIME  EQU 70              ; seconds on the clock at the start
START_X     EQU -6              ; road_x at the start: the car in the third
                                ; lane from the left (lanes 12.5 pairs wide)
EXT_FIRST   EQU 50              ; seconds the first checkpoint gives,
EXT_DROP    EQU 2               ; ... each next one this many fewer,
EXT_MIN     EQU 36              ; ... down to these
TIME_MAX    EQU 99
COUNT_T     EQU 150             ; VSYNCs of the count, 3-2-1
GO_T        EQU 50              ; ... GO! shown
EXT_T       EQU 125             ; ... EXTENDED TIME shown
OVER_T      EQU 150             ; ... GAME OVER shown, standing still
STAGE_T     EQU 100             ; ... STAGE n shown (after GO!, EXTENDED TIME)
BLINK       EQU 64              ; PRESS FIRE: shown BLINK_ON of every BLINK
BLINK_ON    EQU 44

game_mode   defb MODE_DEMO
mode_t      defb 0              ; VSYNCs left of the count or of GAME OVER
                                ; (0: not begun)
msg_t       defb 0              ; ... of GO! or EXTENDED TIME (0: none)
blink_t     defb 0
count_gear  defb 0              ; the count's digit, in the gear's place
cp_z        defw 0              ; where the stage starts: the last checkpoint
stage       defb 0              ; the stage (0 ..; STAGES: the race finished)
                                ; (stage_id: race.asm)
msg_next    defb 0              ; the message after this one (msg_t)
cp_ext      defb EXT_FIRST      ; seconds the next checkpoint gives
keys_was    defb 0              ; read_keys at the last picture (fire's press)
car_free    defb 0              ; 1: the player steers, the car on the screen
                                ; where car_x says (car_lines); 0: the middle

;; --- the car's state ----------------------------------------------------------
speed       defw 0              ; depth units per VSYNC, 8.8
speed_phase defw 0              ; where in the demo's accelerate/brake cycle
time_vbls   defb 50             ; VSYNCs left in the current second
drawn_curve defb 0,0            ; curve level each buffer was drawn with
drawn_x     defb 0,0            ; ... and road_x
curve_wait  defb 0              ; pictures before the curve level may move
sky_turns   defb 0              ; not 0: the sky turns at this flip
steer_x     defb 0              ; where the player wants road_x
car_x       defb 0              ; where the road is from the car, as road_x
                                ; (the player's: road_x follows it)
car_off     defb 0              ; the car's pairs right of the middle on the
                                ; screen: road_x - car_x (car_lines)
drawn_off   defb 0,0            ; ... as each buffer last showed it
car_view    defb 0              ; the car seen straight, turning left, right
car_vfull   defb 0              ; ... and uphill (+3) or downhill (+6): the
                                ; car_view of gen/bush.asm's car_views
drawn_view  defb 0,0            ; ... as each buffer last showed it
car_xf      defb 0              ; car_x's fraction of a pair (steer)
steer_s     defw 0              ; the wheel, -127 (right) to 127 (left)
push_v      defw 0              ; a curve carrying the car out: pairs a
                                ; picture, 8.8, signed
coll_t      defb 0              ; pictures left of a bump or a crash
coll_kind   defb 0              ; 0 a bump (or none), 1 a crash, 2 after
                                ; it: back to the road's middle
coll_v      defw 0              ; the shove, pairs a picture, 8.8, signed
player      defb 0              ; not 0: the tools drive - #FF setting
                                ; steer_x, else as the player, the demo's
                                ; speed till faster or slower (no rules)
demo_t      defw 0              ; pictures, for the demo's steering
pic_bent    defb 0              ; 1: this picture's curve level is new to
                                ; its buffer
heading     defb 0              ; where the sky looks: words right
head_acc    defw 0              ; turning towards the next word, signed

SPEED_MAX   EQU #0690           ; 6.6 depth units per VSYNC: a kerb stripe
                                ; (64) in ~5 pictures
SPEED_ACC   EQU 5               ; per VSYNC, 8.8 - full speed in ~6.7 s
SPEED_BRK   EQU 12
GEAR_STEP   EQU SPEED_MAX/6+1   ; speed per gear
MAX_STEPS   EQU 4               ; 50 Hz steps caught up per picture at most
HEAD_STEP   EQU 128             ; curve level x depth units for the sky to
                                ; turn a word: at the strongest level and
                                ; full speed, a word every ~1.5 pictures

;; ---------------------------------------------------------------------------
;; game_start - entered from boot.asm with RAM_C1, interrupts on.
;; ---------------------------------------------------------------------------
game_start
    ld sp,STACK_TOP
    call game_init              ; the car, the parts that never change in
                                ; both buffers (init.asm: first, as the
                                ; track's rings go over it)
    call course_fill            ; the track's first entries (course.asm)
    call cache_init             ; the cache sets, for the road in the middle

    ; a first picture into each buffer, and only then light the palette
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
    ld a,(pause_req)            ; M or ESC pressed: the music on or off,
    or a                        ; or the pause (player.asm)
    call nz,race_keys
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
    call snd_frame              ; (sound.asm)
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
;; draw_picture - A = buffer: last time's bushes taken away, the road, then
;; this picture's bushes and the car (bush.asm), and last the HUD's changes.
;;
;; The road's curve level and road_x are the cache's (cache_idle): one
;; level for both buffers. When this buffer last showed another level, the
;; road has moved sideways on most lines and road_project draws them with a
;; margin of grass (~6 ms more), and the sky's turn waits for the next
;; picture (pic_bent).
;;
;; The HUD has the time that is left: its whole share up to the 10th
;; interrupt since the flip (~2 ms at most: done 35.3 ms after the flip),
;; the smaller one at the 10th (~0.8 ms: 37.5 ms), none from the 11th - and
;; then its copy waits too, for a picture that has the time. The message
;; line's cells (~0.8 ms at most) only before the 9th: done by 32.8 ms.
;; ---------------------------------------------------------------------------
HUD_FULL_BY EQU 10              ; the interrupt from which the HUD has less
MSG_BY      EQU 9               ; ... and no message cells
draw_picture
    push af
    call select_buf
    ld c,0
    ld hl,drawn_curve
    call buf_entry              ; HL = the level this buffer was drawn with
    ld a,(road_curve)
    cp (hl)
    ld (hl),a
    jr z,draw_picture_x
    inc c                       ; a new level
draw_picture_x
    ld a,c
    ld (pic_bent),a
    ld hl,drawn_x
    call buf_entry
    ld a,(road_x)
    ld (hl),a
    SET_RAM RAM_C1
    call bush_erase             ; last time's bushes, before the road
pic_erased
    pop af
    ld (road_buf),a
    call jump_frame             ; (jump.asm: road_frame)
pic_road
    call bush_draw              ; this picture's on top of it
pic_bushes
    call car_draw               ; and the car on top of all
    ld a,(coll_t)               ; its indicator (signal.asm, bank 6: what
    ld de,(car_x)               ; it needs of bank 7's - car_off, car_vfull
    ld hl,(car_view)            ; next)
    ld ix,(car_id)
    call car_blink_go
pic_car
    ld a,(irq_n)                ; the HUD, with the time left (RAM_C1)
    ld b,HUD_SHARE
    cp HUD_FULL_BY
    jr c,draw_picture_q
    ld b,HUD_SHARE_LOW
    jr z,draw_picture_q
    ld b,0
draw_picture_q
    ld a,b
    ld (hud_quota),a
    or a                        ; (none: its next copy waits too)
    ret z
    ld hl,hud_tick              ; the HUD's values, every HUD_EVERY pictures
    dec (hl)
    jr nz,draw_picture_hud
    ld (hl),HUD_EVERY
    call demo_gauges
    call hud_snapshot
draw_picture_hud
    call hud_update
    ld a,(irq_n)
    cp MSG_BY
    ret nc
    jp hud_msg

;; ---------------------------------------------------------------------------
;; cache_steps - after a picture: the road's next steps (cache.asm), whose
;; templates cache_job then works out while the picture waits for its flip.
;;
;; No new curve level on a hill or just before one, nor while the last
;; picture's hill moved (as the road leaves a hill): a picture whose hill
;; moves compares each line's row with then's, and a level on top of that
;; - or the cache catching up with one - is too much. A level waits for a
;; hill HILL_STEP_AHEAD track entries ahead: the two pictures it makes heavy
;; (both buffers draw all of the road moved) are done by then. (The track
;; has no curve on a hill: a level only waits when it is late.) A step
;; sideways goes on a hill too - with the road 80 lines high a picture
;; whose hill moves and road moved sideways fits (37.4 ms at worst); while
;; the hill holds a level back, a step the player wants is worked out in
;; its place (cp_turn).
;;
;; The curve level moves a level towards the game's - not within two
;; pictures of the last move, so that a buffer's road moves a level at most
;; between two of its pictures - holding back the sky's turn at this flip
;; (sky_stay: the next picture would pay for both) - only once the cache
;; has the level worked out ahead, and then all of the road moves to it at
;; once (cache_kstep). (Till 2026-11-05 the road in the middle was drawn
;; from each curve level's own template sets, and moved a level there and
;; then.)
;;
;; Then road_x moves towards steer_x - two or four pairs (STEP_MAX), so it
;; is always even: with steer_x a pair from it, it waits - the whole cache
;; with it (cache_step). A step
;; the cache has worked out ahead (cache_ready) is only copied into place,
;; ~5 ms, and goes whenever this runs; else one of two pairs is made there
;; and then, and only if it is sure to be done before the flip
;; (STEP_LATE): else the road waits a picture, which then is lighter
;; (nothing moved sideways) and leaves the time. A step holds the sky's
;; turn and the cache's jobs back for a picture.
;; ---------------------------------------------------------------------------
cache_steps
    ld a,(rp_cmp)               ; a level only if the last picture's hill
    or a                        ; did not move
    jp nz,cache_steps_x
    ld b,HILL_STEP_AHEAD+1      ; nor is a hill here or just ahead
    call hill_near_b
    jp nz,cache_steps_x
    ld a,(curve_wait)
    or a
    jr nz,cache_steps_x
    ld a,(curve)
    ld hl,road_curve
    sub (hl)
    jr z,cache_steps_x
    ld c,a
    jp cache_kstep              ; (cache.asm)
cache_steps_x
    ld a,(back_buf)             ; no more than STEP_MAX pairs from where the
    xor 1                       ; next picture's buffer last had it (the
    ld hl,drawn_x               ; margin it draws): two steps in a row would
    add a,l                     ; make it twice that
    ld l,a
    ASSERT hi(drawn_x) == hi(drawn_x+1)
    ld c,(hl)
    ld a,(steer_x)
    sub c
    call step_even              ; (player.asm)
    add a,c
    ld hl,road_x
    sub (hl)
    ret z
    ld c,a
    call cache_ready            ; (one worked out ahead: its own gate)
    jr nz,cache_steps_gate
    ld b,2                      ; else two pairs at most, made there and
    ld a,c                      ; then
    call clamp_ab
    ld c,a
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
    ld a,(curve_wait)           ; (not while a new curve level has the
    or a                        ; road drawn with a margin)
    ret nz
    ld a,(irq_n)
    inc a
    cp b
    ret nc
    xor a
    ld (step_turn),a            ; (cp_turn)
    ld a,c
    call cache_step
    jp sky_stay                 ; (the next picture has the road moved)


;; ---------------------------------------------------------------------------
;; steer - where the car is on the road (car_x) and where the road is to go
;; (steer_x), once a picture, and how the car is seen (car_view).
;;
;; The player, as Out Run (SMS: L264D) does it. Left or right turns the
;; wheel (steer_s) towards 127 or -127, neither brings it back to 0,
;; STEER_RAMP a picture at most: 0.2 s to the full lock, 0.4 s from one to
;; the other.
;; The wheel moves the car - left: car_x up, the road under it going right
;; - its turn x the car's k / 64 / 256 pairs a picture (0.62-0.87 at the
;; full lock): all of it from STEER_SPEED on, as much less as the car is
;; slower below it, none standing still. Turning, the car goes a gauge
;; segment slower at the most (STEER_LOSS). And a curve carries the car out of
;; it - out of a right curve the car goes left, the road right: push_v
;; goes towards the curve level L x (1 + L / 14) x the speed / 16 x the
;; car's m / 65536 pairs a picture, STEER_RAMP at most. On a level 7 curve
;; at full speed that is 1.24 pairs a picture for the first car, 2.5 times
;; its full lock: it has to slow down (Out Run's common sharp curves carry
;; its car out 71-75% of its full lock). Both moves add up in car_x and its
;; fraction car_xf. The car moves on the screen at once, and the road
;; follows it as fast as its steps can (steer_x = car_x): the car is drawn
;; road_x - car_x pairs right of the middle (car_lines), CAR_LEAD at most.
;; The car is seen turning while left or right is held (not both).
;;
;; Outside the race the demo steers: a new place every DEMO_HOLD pictures
;; - before the race START_X - the car seen turning while the road moves to
;; it, the car in the middle (car_x = road_x). In the demo, fire (faster)
;; pressed starts a race (rules_start).
;; ---------------------------------------------------------------------------
DEMO_HOLD   EQU 128
HILL_AHEAD  EQU 3               ; track entries (32 depth units) the sky's
                                ; turn looks ahead for a hill (main)
HILL_STEP_AHEAD EQU 2           ; ... and a new curve level (~6 pictures
                                ; at full speed)
STEPS_LATE  EQU 10              ; from this interrupt since the flip on, no
                                ; steps
STEP_LATE   EQU 8               ; ... and no road_x step
HILL_PITCH  EQU 20              ; the hill, either way, from which the car
                                ; is seen uphill or downhill (car_lines)
CAR_LEAD    EQU 16              ; pairs it may be from the middle of the
                                ; screen, road_x - car_x
STEER_RAMP  EQU 28              ; the most the wheel's turn and the push
                                ; (8.8 pairs a picture) move a picture: Out
                                ; Run's 64 and 5 a step, ~10.9 steps a second
STEER_SPEED EQU #0400           ; slower, the wheel moves the car less
STEER_LOSS  EQU SPEED_MAX/GAUGE_SEGS ; the top speed lost turning: a segment
CAR_STEER_K EQU 85              ; (the first car's; car_setup: each its own)
CAR_PUSH_M  EQU 64
HIT_Y       EQU CAR_Y+CAR_TOP/2-ROAD_AREA_Y ; a car or a bush touches ours with
                                ; its base line on the car's lower half...
HIT_TRIM    EQU 2               ; ... the two overlapping, this many bytes in
BUMP_T      EQU 25              ; a bump (Out Run: a car hit), pictures
BUMP_V      EQU 240             ; ... the shove away from it, 8.8 pairs a
                                ; picture (Out Run: 12 a step for 10 steps)
BUMP_SPEED  EQU TR_SPEED*256-#40 ; ... the speed at most: the car hit goes on
CRASH_T     EQU 45              ; a crash (a bush), pictures (Out Run: 1.5-2 s)
CRASH_V     EQU 480             ; ... the shove away from it (24 a step, 20)
CRASH_BRK   EQU 16              ; ... the speed lost a VSYNC, to a standstill
BACK_V      EQU 160             ; then back to the middle (8 a step)
BACK_T      EQU 64              ; ... in this many pictures at most

steer
    call read_keys              ; (player.asm)
    ld (keys_now),a
    ld c,a
    ld hl,coll                  ; B = what the car touched last picture
    ld b,(hl)
    ld (hl),0
    ld a,(player)
    inc a
    jp z,steer_look             ; (#FF: tools/ steer by steer_x)
    dec a
    jr nz,steer_tools           ; (tools/ drive as the player)
    ld a,(keys_was)             ; E = keys pressed since the last picture
    cpl
    and c
    ld e,a
    ld a,c
    ld (keys_was),a
    ld a,e
    and KEY_PAUSE+KEY_MUSIC
    ld (pause_req),a            ; (main_loop: player.asm race_keys)
    ld a,(game_mode)
    cp MODE_RACE
    jr nc,steer_go              ; the player's
    or a
    jp nz,steer_demo            ; (READY: to the start)
    bit 2,e
    call nz,rules_start
    jp steer_demo
steer_tools
    or c
    ld (player),a
steer_go
    ld a,1
    ld (car_free),a
    ld a,(coll_t)               ; a bump or a crash begins - not in one
    or a
    jr nz,steer_coll
    or b
    call nz,coll_start
steer_coll
    ld a,(coll_kind)            ; (a crash: the wheel back to the middle)
    or a
    ld a,c                      ; HL = where the wheel is to go: left 127,
    ld hl,0                     ; right -127, neither or both 0 - and
    jr nz,steer_keys            ; car_view 1, 2, 0
    and 3
    jr z,steer_keys
    cp 3
    jr z,steer_both
    ld l,127
    cp 1
    jr z,steer_keys
    ld hl,-127
    jr steer_keys
steer_both
    xor a
steer_keys
    ld (car_view),a
    ld a,l                      ; turning (the wheel to go to a full lock):
    or a                        ; the top speed on the road a gauge segment
    push hl                     ; lower (speed_player's - it slows down to
    ld hl,(demo_max+1)          ; it as on the grass)
    ld de,-STEER_LOSS
    jr z,$+3
    add hl,de
    ld (sp_max+1),hl
    pop hl
    ld de,(steer_s)
    call ramp
    ld (steer_s),hl

    ; HL = the wheel's move: |turn| x k / 64 - k the car's, from
    ; STEER_SPEED on; slower, k x speed / STEER_SPEED
    ld a,l
    or a
    jr z,steer_moved            ; (HL 0)
    jp p,$+5
    neg
    ld c,a                      ; C = |turn|
    ld de,(speed)
    ld a,d
    cp hi(STEER_SPEED)
    jr c,steer_slow
    ld a,c
    cp 127
steer_full
    ld hl,0                     ; (car_setup: the full lock's move)
    jr z,steer_sign
steer_k
    ld e,CAR_STEER_K            ; (car_setup: the car's)
    jr steer_mul
steer_slow
    ASSERT STEER_SPEED == #0400
    srl d
    rr e
    srl d
    rr e
    ld h,e                      ; speed / 4 (below #400: a byte)
    ld a,(steer_k+1)
    ld e,a
    call mul8
    ld e,h
steer_mul
    ld h,c
    call mul8
    call shr6
steer_sign
    ld a,(steer_s)
    or a
    call m,neg_hl
steer_moved
    push hl

    ; HL = the push asked: |level| (1 + |level| / 14) x (speed / 16 x m) /
    ; 256, outwards - m the car's; a sharper curve's more, by up to half at
    ; the sharpest (push_levels: twice that factor)
    ld hl,(speed)
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl                   ; H = speed / 16
steer_m
    ld e,CAR_PUSH_M             ; (car_setup: the car's)
    call mul8
    srl h
    rr l
    ex de,hl                    ; DE = speed / 16 x m / 2
    ld hl,0
    ld a,(road_curve)
    or a
    jr z,steer_pushed
    ld c,a
    jp p,$+5
    neg
    add a,lo(push_levels-1)     ; (race.asm)
    ld l,a
    ld h,hi(push_levels)
    ld b,(hl)
    ld hl,0
    xor a
steer_pmul
    add hl,de                   ; (A: the bits over 16)
    adc a,0
    djnz steer_pmul
    ld l,h
    ld h,a
    bit 7,c
    call nz,neg_hl
steer_pushed
    ld de,(push_v)
    call ramp
    ld (push_v),hl
    pop de
    add hl,de                   ; the car's move: the wheel's and the push
    ld a,(coll_t)
    or a
    call nz,coll_step
    ld a,(car_xf)
    add a,l
    ld (car_xf),a
    ld a,(car_x)
    adc a,h
    ld hl,road_x                ; the car on, no further than CAR_LEAD from
    sub (hl)                    ; where the road is nor ROAD_X_MAX from the
    ld b,CAR_LEAD               ; middle; the road to follow it
    call clamp_ab
    add a,(hl)
    ld b,ROAD_X_MAX
    call clamp_ab
    ld (car_x),a
    ld (steer_x),a
    ret

;; ramp - HL = where to go, DE = where it is now: HL = moved towards it,
;; STEER_RAMP at most. Destroys AF.
ramp
    or a
    sbc hl,de
    bit 7,h
    jr nz,ramp_neg
    ld a,h
    or a
    jr nz,ramp_up
    ld a,l
    cp STEER_RAMP+1
    jr c,ramp_add
ramp_up
    ld hl,STEER_RAMP
    jr ramp_add
ramp_neg
    ld a,h
    inc a
    jr nz,ramp_down
    ld a,l
    cp -STEER_RAMP
    jr nc,ramp_add
ramp_down
    ld hl,-STEER_RAMP
ramp_add
    add hl,de
    ret

;; mul8 - HL = H x E, unsigned. Destroys B, D, F.
mul8
    ld d,0
    ld l,d
    ld b,8
mul8_loop
    add hl,hl
    jr nc,$+3
    add hl,de
    djnz mul8_loop
    ret

;; shr6 - HL = HL / 64. Destroys AF.
shr6
    xor a
    add hl,hl
    rla
    add hl,hl
    rla
    ld l,h
    ld h,a
    ret

;; neg_hl - HL = -HL. Destroys AF.
neg_hl
    xor a
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a
    ret

;; ---------------------------------------------------------------------------
;; coll_start - B = what the car touched (coll): a bump or a crash begins,
;; as in Out Run (SMS: L2B84). A car (bit 7): BUMP_T pictures of the car
;; shoved away from it, and no faster than BUMP_SPEED, so that the one it
;; hit goes on ahead; meanwhile no other bump. A bush (bit 6), off the
;; road: a crash, CRASH_T pictures of the car shoved away from it - across
;; the road - out of control, slowing to a standstill (speed_player); then
;; back to the middle of the road, BACK_T pictures at most, and off again.
;; Both wobble (coll_step).
;; ---------------------------------------------------------------------------
coll_start
    ld hl,BUMP_V
    ld de,BUMP_T                        ; (D: the kind, a bump)
    bit 6,b
    jr z,coll_set
    call jump_start                     ; (jump.asm: at speed, thrown up)
    ld hl,CRASH_V
    ld de,256+CRASH_T+BACK_T
coll_set
    bit 0,b                             ; away: its right of ours, our car
    call z,neg_hl                       ; left (car_x up)
    ld (coll_v),hl
    ld (coll_t),de
    ASSERT coll_kind == coll_t+1
    bit 6,b
    ret nz
    ld hl,(speed)                       ; a bump: no faster than BUMP_SPEED
    ld de,BUMP_SPEED
    or a
    sbc hl,de
    ret c
    ld (speed),de
    ret

;; coll_step - A = coll_t, not 0: a picture of a bump or a crash. HL = the
;; car's move: the shove added - or, the crash over, the way back to the
;; road's middle in its place. Sets car_view: in a bump the car wobbles,
;; left and right; in a crash it spins (spin_views). Destroys AF, DE.
coll_step
    dec a
    ld (coll_t),a
    ld e,a
    jr nz,coll_on
    ld (coll_kind),a                    ; (over)
coll_on
    ld a,(coll_kind)
    or a
    jr z,coll_bump
    ld a,e
    cp BACK_T
    jr c,coll_back
    ld a,CRASH_T+BACK_T-1               ; a crash: a view each 2 pictures
    sub e
    rra
    and 7
    ld e,a
    ld d,0
    push hl
    ld hl,spin_views
    add hl,de
    ld a,(coll_v+1)                     ; shoved right: the other way
    rla
    sbc a,a
    and 3
    xor (hl)
    pop hl
    jr coll_shove
coll_bump
    ld a,e
    rra
    and 1
    inc a
coll_shove
    ld (car_view),a
    ld de,(coll_v)
    add hl,de
    ret
;; the car in a crash, shoved left: its nose swung right by the blow, and
;; seen spun right, then back and spun left, and so on - XOR 3 the other
;; way (1 and 2, SPIN_VIEW and SPIN_VIEW+1 swapped)
    ASSERT SPIN_VIEW == 9
spin_views
    defb 2,SPIN_VIEW+1,SPIN_VIEW+1,2,1,SPIN_VIEW,SPIN_VIEW,1
coll_back
    ld a,(car_x)                        ; car_x towards 0
    ld hl,BACK_V
    or a
    jp m,coll_view
    ld hl,-BACK_V
    jr nz,coll_view
    ld (coll_kind),a                    ; there: off again
    ld (coll_t),a
    ld (car_xf),a
    ld l,a
    ld h,a
coll_view
    xor a
    ld (car_view),a
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
    ld a,(game_mode)            ; (READY: to the start)
    or a
    ld a,START_X
    jr nz,steer_demo_x
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
    call demo_lanes             ; (cache.asm: as wide as the road is)
steer_demo_x
    ld (steer_x),a
    ld a,(road_x)               ; (the car in the middle, for when the
    ld (car_x),a                ; player takes over)
steer_look                      ; the car turns the way the road is to go
    xor a
    ld (car_free),a
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
;; demo_gauges - the speed gauge and the gear, from the speed (the count's
;; digit in the gear's place), and in the race the checkpoint gauge, from
;; how far on the car is: only the HUD shows them, so they are worked out
;; when it takes its copy.
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
    ld a,(count_gear)
    or a
    jr z,$+5
    ld (gear),a
    ld a,(game_mode)
    cp MODE_RACE
    ret nz
    ld hl,(zcam)                ; segments: 1 + how far on, in eighths
    ld de,(cp_z)
    or a
    sbc hl,de
    ld de,STAGE_LEN/GAUGE_SEGS
    ld b,1
    jp m,demo_cp_set            ; (the race's track not reached yet: GO)
    dec b
demo_cp
    inc b
    or a
    sbc hl,de
    jr nc,demo_cp
demo_cp_set
    ld a,b
    cp GAUGE_SEGS+1
    jr c,$+4
    ld a,GAUGE_SEGS
    ld (cp_level),a
    ret


;; ---------------------------------------------------------------------------
;; demo_step - one VSYNC of the drive: the speed - the demo's, the player's
;; in the race (player.asm), braking to a standstill before it and after it
;; - the camera, the sky's turn, the race's rules.
;; ---------------------------------------------------------------------------
demo_step
    ld a,(player)               ; the tools' (#FF, or as the player: once
    inc a                       ; faster or slower is pressed, the keys')
    jr z,demo_cycle
    dec a
    jr nz,demo_tools
    ld a,(game_mode)
    cp MODE_RACE
    jp z,speed_player
    jr c,demo_mode
    ld hl,(speed)               ; time up: braking (player.asm)
    ld de,-SPEED_BRK
    jp sp_less
demo_mode
    or a
    jr z,demo_cycle
    ld de,(speed)               ; to the start: braking
    jr demo_brake
demo_tools
    and #0C
    jp nz,speed_player
demo_cycle
    ; speed: accelerate for 16 s, then brake, repeat every 20 s
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
demo_acc
    ld hl,SPEED_ACC             ; (car_setup: the car's)
    add hl,de
demo_max
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

    ; the hill and the curve under the camera, the track worked out a few
    ; entries on (course.asm): HILL_RING and CURVE_RING[(zcam / 32) mod 64]
    call course_fill
    ld hl,(zcam)
    add hl,hl
    add hl,hl
    add hl,hl                   ; H = zcam / 32
    ld a,h
    and RING_MASK
    or lo(HILL_RING)
    ld l,a
    ld h,hi(HILL_RING)
    ld a,(hl)
    ld (hill),a
    res 6,l                     ; (CURVE_RING)
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

    jp rules_vbl

;; ---------------------------------------------------------------------------
;; rules_vbl - (demo_step) a VSYNC of the race's rules (the start of a race,
;; the demo's messages and the best times: race.asm).
;;
;; The demo: PRESS FIRE blinks, and the best times show. READY: once the car stands at the start,
;; the count, 3-2-1 in the gear's place, then GO!: the race. The race: the
;; total time counts up, the clock down a second at a time; CP_DIST on from
;; the last checkpoint is the next - TIME and EXTENDED TIME, cp_ext seconds,
;; EXT_DROP fewer each time down to EXT_MIN; TIME at 0 is time up: the car
;; brakes to a standstill (demo_step), the road under it, GAME OVER, then
;; the demo again.
;; ---------------------------------------------------------------------------
rules_vbl
    ld a,(game_mode)
    dec a
    jr z,rules_ready
    dec a
    jp z,rules_race
    dec a
    jp z,rules_over
    jp rules_demo               ; (race.asm)

rules_ready
    ld a,(mode_t)
    or a
    jr nz,rules_count
    ld hl,(speed)               ; standing at the start yet?
    ld a,h
    or l
    ret nz
    ld a,(road_x)
    cp START_X
    ret nz
    ld a,COUNT_T
rules_count
    dec a
    ld (mode_t),a
    jr z,rules_go
    ld b,3                      ; the count: 3, 2, 1, a second each
    cp 2*COUNT_T/3
    jr nc,rules_count_set
    dec b
    cp COUNT_T/3
    jr nc,rules_count_set
    dec b
rules_count_set
    ld a,b
    ld (count_gear),a
    ret
rules_go
    ld (count_gear),a
    ld (car_xf),a               ; the player's, from the middle of the road
    ld (coll_t),a               ; where the demo left it
    ld (coll_kind),a
    ld h,a
    ld l,a
    ld (steer_s),hl
    ld (push_v),hl
    ld a,(road_x)
    ld (car_x),a
    ld hl,(crs_z)               ; the course from the next entry worked
    ld (cp_z),hl                ; out on: the first stage starts there
    ld hl,course_st0
    ld de,props_st0
    xor a
    ld (stage_id),a
    call course_set             ; (A = 0 after)
    inc a
    ld (msg_texts+MSG_STAGE_N),a
    ld a,MSG_STAGE
    ld (msg_next),a
    ld a,50
    ld (time_vbls),a
    ld a,MODE_RACE
    ld (game_mode),a
    ld a,MSG_GO
    ld b,GO_T
rules_msg                       ; message A for B VSYNCs
    ld (msg),a
    ld a,b
    ld (msg_t),a
    ret

rules_race
    ld hl,msg_t                 ; GO! or EXTENDED TIME shown long enough:
    ld a,(hl)                   ; the next, if any (STAGE n)
    or a
    jr z,rules_total
    dec (hl)
    jr nz,rules_total
    ld hl,msg_next
    ld a,(hl)
    ld (hl),0
    ld (msg),a
    or a
    jr z,rules_total
    ld a,STAGE_T
    ld (msg_t),a

    ; TOTAL TIME counts up two hundredths a VSYNC: m'ss"cc
rules_total
    ld hl,total_time+4
    ld a,(hl)
    add a,2
    cp 10
    jr c,rules_tt_set
    sub 10
    ld (hl),a
    dec hl                      ; cs tens
    inc (hl)
    ld a,(hl)
    cp 10
    jr c,rules_tt_done
    ld (hl),0
    dec hl                      ; s units
    inc (hl)
    ld a,(hl)
    cp 10
    jr c,rules_tt_done
    ld (hl),0
    dec hl                      ; s tens
    inc (hl)
    ld a,(hl)
    cp 6
    jr c,rules_tt_done
    ld (hl),0
    dec hl                      ; minutes
    inc (hl)
    ld a,(hl)
    cp 10
    jr c,rules_tt_done
    ld (hl),0
    jr rules_tt_done
rules_tt_set
    ld (hl),a
rules_tt_done

    ; a checkpoint: the stage's end - the next stage, its colours; past the
    ; last, the finish. FORK_Z before it, the fork's message: the stage on
    ; the left and the one on the right (stage_fork)
    ld hl,(zcam)
    ld de,(cp_z)
    or a
    sbc hl,de
    ld de,STAGE_LEN
    or a
    sbc hl,de
    jp p,rules_cp               ; (signed: at GO it is ahead of the car;
    ld de,FORK_Z                ; DE = STAGE_LEN there)
    add hl,de
    jr nc,rules_clock
    ld a,(stage)
    cp STAGES-1
    jr nc,rules_clock           ; (the last: the finish)
    add a,MSG_FORK
    ld (msg),a
    jr rules_clock
rules_cp
    ld hl,(cp_z)
    add hl,de
    ld (cp_z),hl
    ld hl,stage
    inc (hl)
    ld a,(hl)
    cp STAGES
    jr z,rules_finish
    ld a,(stage_id)
    call stage_colours
    ld a,(stage)
    inc a
    ld (msg_texts+MSG_STAGE_N),a
    ld a,MSG_STAGE
    ld (msg_next),a
    ld a,(cp_ext)
    ld b,a
    ld a,(time_left)
    add a,b
    cp TIME_MAX+1
    jr c,$+4
    ld a,TIME_MAX
    ld (time_left),a
    ld a,b
    sub EXT_DROP
    cp EXT_MIN
    jr nc,$+4
    ld a,EXT_MIN
    ld (cp_ext),a
    ld a,MSG_EXTENDED_TIME
    ld b,EXT_T
    call rules_msg

    ; TIME counts down a second at a time: at 0, time up
rules_clock
    ld hl,time_vbls
    dec (hl)
    ret nz
    ld (hl),50
    ld hl,time_left
    dec (hl)
    ret nz
    ld a,MSG_TIME_UP
rules_end                       ; the race over: message A, to a standstill
    ld (msg),a
    ld a,MODE_OVER
    ld (game_mode),a
    xor a
    ld (mode_t),a
    ld (msg_t),a
    ld (msg_next),a
    ret
rules_finish
    call times_add              ; (race.asm)
    ld a,MSG_FINISH
    jr rules_end

rules_over
    ld a,(mode_t)
    or a
    jr nz,rules_over_t
    ld hl,(speed)               ; standing still, the road under the car
    ld a,h                      ; (road_x stops a pair short of an odd
    or l                        ; car_x)?
    ret nz
    ld a,(car_x)
    ld hl,road_x
    sub (hl)
    inc a
    cp 3
    ret nc
    ld a,(stage)                ; (finished: FINISH stays - or FASTEST
    cp STAGES                   ; TIME!, race.asm)
    ld a,MSG_GAME_OVER
    call z,finish_msg
    ld (msg),a
    ld a,OVER_T
rules_over_t
    dec a
    ld (mode_t),a
    ret nz
    ld (game_mode),a            ; (MODE_DEMO) the demo drives on from here,
    ld (blink_t),a              ; its loop after the road is brought to the
    ld (coll_t),a               ; flat, in the first stage's colours
    ld (coll_kind),a
    call stage_colours
    ld hl,course_demo
    ld de,props_demo
    ld a,1
    jp course_set

zfrac       defb 0
