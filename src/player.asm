;; ===========================================================================
;; player.asm - the keys, in page 1 at #7600 (the
;; seventh 2K block's gap, which mkbush.py leaves free), seen at #4000 with
;; RAM_C1 - as it is while steer and demo_step run.
;; ===========================================================================

    ORG #7600

;; ---------------------------------------------------------------------------
;; read_keys - A: bit 0 = left held (cursor left, O, joystick left), bit 1 =
;; right (cursor right, P, joystick right), bit 2 = faster: the pedal (space,
;; joystick fire), bit 3 = slower: the brake (Z, joystick fire 2), bit 4 =
;; the music on or off (M: KEY_MUSIC), bit 5 = the pause (ESC: KEY_PAUSE),
;; bit 6 = LOW gear (cursor up, Q, joystick up), bit 7 = HIGH (cursor down,
;; A, joystick down) - as OutrunOutrunCPC has them (since 2026-11-11; till
;; then up was faster and down slower). The keyboard is read through the
;; PSG's port (register 14), the PPI's port A turned round for it - with
;; interrupts off: the interrupt writes the PSG too (sound.asm). Destroys
;; BC, DE.
;; ---------------------------------------------------------------------------
KEY_FASTER  EQU 4
KEY_SLOWER  EQU 8
KEY_MUSIC   EQU 16
KEY_PAUSE   EQU 32
KEY_LOW     EQU 64
KEY_HIGH    EQU 128
read_keys
    di
    ld bc,#F40E                 ; PSG register 14
    out (c),c
    ld bc,#F6C0                 ; (latched)
    out (c),c
    ld c,0
    out (c),c
    ld bc,#F792                 ; PPI port A in
    out (c),c
    ld d,0
    ld a,#40                    ; row 0: cursor up, right, down (bits 0-2)
    call rk_row
    rra
    jr nc,$+4
    set 6,d
    rra
    jr nc,$+4
    set 1,d
    rra
    jr nc,$+4
    set 7,d
    ld a,#41                    ; row 1: cursor left (bit 0)
    call rk_row
    and 1
    or d
    ld d,a
    ld a,#43                    ; row 3: P (bit 3)
    call rk_row
    and 8
    rrca
    rrca
    or d
    ld d,a
    ld a,#44                    ; row 4: O (bit 2), M (bit 6: bit 4)
    call rk_row
    and #44
    rrca
    rrca
    or d
    ld d,a
    ld a,#45                    ; row 5: space (bit 7)
    call rk_row
    rla
    jr nc,$+4
    set 2,d
    ld a,#48                    ; row 8: Z (bit 7), A (bit 5), Q (bit 3), ESC
    call rk_row                 ; (bit 2)
    ld e,a
    rla
    jr nc,$+4
    set 3,d
    bit 5,e
    jr z,$+4
    set 7,d
    bit 3,e
    jr z,$+4
    set 6,d
    bit 2,e
    jr z,$+4
    set 5,d
    ld a,#49                    ; row 9: joystick up, down, left, right
    call rk_row                 ; (bits 0-3), fire and fire 2 (4, 5)
    ld e,a
    and #3C                     ; left, right, the fires: bits 0-3
    rrca
    rrca
    or d
    ld d,a
    ld a,e
    and 3                       ; up, down: bits 6, 7
    rrca
    rrca
    or d
    ld bc,#F782                 ; port A out again
    out (c),c
    ld bc,#F600
    out (c),c
    ei
    ret
rk_row                          ; A = #40 + row: its keys, 1 = held
    ld b,#F6
    out (c),a
    ld b,#F4
    in a,(c)
    cpl
    ret

OFFROAD_X   EQU 20              ; car_x from which a wheel is off a 4-lane
                                ; road, either way: 5 a lane (game.asm
                                ; speed_player, sndgame.asm; road15.asm
                                ; lane_road)

keys_now    defb 0              ; read_keys at the last picture (steer)

;; ---------------------------------------------------------------------------
;; cp_turn - (cache_pre) A = the curve level the cache is to work out ahead:
;; CF if a hill holds the level back (cache_steps) and the player wants a
;; step: the step goes in its place (cp_step - the level dropped, if it was
;; under way). Else NZ, A = the step to work out instead (cp_pend), if it is
;; a step's turn - none has gone since a curve level last did (step_turn)
;; and no level is under way - and the player wants one. Else Z, A as it
;; was. On a winding road a level is nearly always wanted:
;; the road would not follow the steering for seconds. (Only with the road
;; no more than a level behind the track: steering fell from 0.149 pairs a
;; picture to 0.121 and the lag hardly changed, 1.43 levels for 1.53.)
;; Destroys B, D, E, HL.
;; ---------------------------------------------------------------------------
cp_turn
    ld e,a
    ld a,(steer_way)            ; changing lanes (since 2026-11-12): the
    or a                        ; step first - unless a level is under way,
    jr z,cp_turn_lv             ; or the road is two levels or more behind
    ld a,(pre_k)                ; the curve
    or a
    jr nz,cp_turn_lv
    ld a,(curve)
    ld hl,road_curve
    sub (hl)
    jp p,$+5
    neg
    cp 2
    jr c,cp_turn_hill
cp_turn_lv
    ld a,(rp_cmp)               ; a hill holds the level back?
    or a
    jr nz,cp_turn_hill
    push de
    ld b,HILL_STEP_AHEAD+1
    call hill_near_b            ; (horizon.asm)
    pop de
    jr nz,cp_turn_hill
    ld a,(pre_k)
    or a
    jr nz,cp_turn_no
    ld a,(step_turn)
    or a
    call nz,cp_pend
    ret nz
cp_turn_no
    xor a
    ld a,e
    ret
cp_turn_hill                    ; ... and a step is wanted: CF
    call cp_pend
    jr z,cp_turn_no
    scf
    ret

;; ---------------------------------------------------------------------------
;; cp_pend - (cache_pre, cp_turn) A = the step road_x is to take towards
;; steer_x: NZ - Z if none. While steer_x is going one way (steer_way), a
;; whole step that way, as far as ROAD_X_MAX lets it, even before steer_x
;; is there: worked out ahead, it goes once steer_x is (cache_ready) -
;; else a lane change took half its steps as two pairs, when the work
;; costs the same (since 2026-11-12: a lane change 20% quicker, the user's;
;; the road no further for it). step_even - A = how far road_x is to go:
;; the step that takes it there, or as far as a step goes (STEP_MAX pairs
;; either way) - an even number of pairs, road_x being even: none for a
;; pair. Destroys B.
;; ---------------------------------------------------------------------------
STEP_MAX    EQU 4               ; pairs a step worked out ahead takes at most
                                ; (one made there and then: two, cache_steps)
cp_pend
    ld a,(steer_way)
    or a
    jr z,cp_pend_to
    ld b,STEP_MAX
    jp p,$+5
    ld b,-STEP_MAX
    ld a,(road_x)
    add a,b
    jp p,$+5
    neg
    cp ROAD_X_MAX+1
    ld a,b
    jr nc,cp_pend_to
    or a
    ret
cp_pend_to
    ld a,(road_x)
    ld b,a
    ld a,(steer_x)
    sub b
step_even
    jp p,step_even_p
    inc a                       ; (an odd one towards 0)
step_even_p
    and #FE
    ret z
    ld b,STEP_MAX
    call clamp_ab
    or a
    ret

step_turn   defb 0              ; not 0: a curve level went last (cp_turn)

;; race_keys - (main_loop) A = the keys just pressed of KEY_MUSIC and
;; KEY_PAUSE (pause_req): M the race's music off, or on again (mus_want,
;; sndgame.asm), with a beep - in the demo too, for the races to come; else
;; ESC the pause (race.asm)
race_keys
    and KEY_MUSIC
    jp z,race_pause
    ld hl,mus_want
    inc (hl)
    res 1,(hl)                  ; (1, 0, 1...)
    ld a,lo(fx_beep)
    ld (fx_new),a
    ret

player_end
    ASSERT player_end <= #7740
