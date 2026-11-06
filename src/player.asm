;; ===========================================================================
;; player.asm - the keys and the player's speed, in page 1 at #7600 (the
;; seventh 2K block's gap, which mkbush.py leaves free), seen at #4000 with
;; RAM_C1 - as it is while steer and demo_step run.
;; ===========================================================================

    ORG #7600

;; ---------------------------------------------------------------------------
;; read_keys - A: bit 0 = left held (cursor left, O, joystick left), bit 1 =
;; right (cursor right, P, joystick right), bit 2 = faster (cursor up, Q,
;; space, joystick up or fire), bit 3 = slower (cursor down, A, joystick
;; down), bit 4 = the music on or off (M: KEY_MUSIC), bit 5 = the pause
;; (ESC: KEY_PAUSE). The keyboard is read through the PSG's port (register
;; 14), the PPI's port A turned round for it - with interrupts off: the
;; interrupt writes the PSG too (sound.asm). Destroys BC, DE.
;; ---------------------------------------------------------------------------
KEY_MUSIC   EQU 16
KEY_PAUSE   EQU 32
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
    set 2,d
    rra
    jr nc,$+4
    set 1,d
    rra
    jr nc,$+4
    set 3,d
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
    ld a,#48                    ; row 8: Q (bit 3), A (bit 5), ESC (bit 2)
    call rk_row
    ld e,a
    and 8
    jr z,$+4
    set 2,d
    ld a,e
    and #20
    jr z,$+4
    set 3,d
    ld a,e
    and 4
    jr z,$+4
    set 5,d
    ld a,#49                    ; row 9: joystick up, down, left, right
    call rk_row                 ; (bits 0-3), fire 2 and 1 (4, 5)
    ld e,a
    and #31
    jr z,$+4
    set 2,d
    ld a,e
    and 2
    jr z,$+4
    set 3,d
    ld a,e
    and #0C
    rrca
    rrca
    or d
    ld d,a
    ld bc,#F782                 ; port A out again
    out (c),c
    ld bc,#F600
    out (c),c
    ei
    ld a,d
    ret
rk_row                          ; A = #40 + row: its keys, 1 = held
    ld b,#F6
    out (c),a
    ld b,#F4
    in a,(c)
    cpl
    ret

;; ---------------------------------------------------------------------------
;; speed_player - (demo_step, once the player has pressed faster or slower)
;; one VSYNC of the player's speed: SPEED_ACC up while faster is held,
;; SPEED_BRK down while slower is (both: slower), SPEED_COAST down with
;; neither. On the grass - a wheel off the road, car_x OFFROAD_X (5 a lane)
;; or more either way - the car goes no faster than SPEED_GRASS: over it, it slows
;; down by SPEED_DRAG a VSYNC. Goes on with demo_speed_set, HL = the speed.
;; The top speeds and the acceleration are the car's (car_setup).
;; ---------------------------------------------------------------------------
SPEED_COAST EQU 2
SPEED_GRASS EQU SPEED_MAX/2
SPEED_DRAG  EQU 12
OFFROAD_X   EQU 20

speed_player
    ld hl,(speed)
    ld a,(coll_kind)            ; a crash: to a standstill (game.asm
    or a                        ; coll_start)
    ld de,-CRASH_BRK
    jr nz,sp_less
    ld a,(keys_now)
    ld de,-SPEED_BRK
    bit 3,a
    jr nz,sp_less               ; slower
sp_acc
    ld de,SPEED_ACC             ; (car_setup: the car's)
    bit 2,a
    jr nz,sp_more               ; faster
    ld de,-SPEED_COAST
sp_less
    add hl,de
    jr c,sp_top
    ld hl,0                     ; standing still
    jr sp_top
sp_more
    add hl,de
sp_top                          ; HL = the speed asked: no more than the top
sp_max
    ld de,SPEED_MAX             ; (car_setup: the car's)
    ld a,(car_x)
sp_off
    add a,OFFROAD_X-1           ; (self-modified: the lanes' - cache.asm
    cp 2*OFFROAD_X-1            ; lane_road) CF: on the road
    jr c,sp_top_de
sp_grass
    ld de,SPEED_GRASS
sp_top_de
    or a
    sbc hl,de
    add hl,de
    jp c,demo_speed_set         ; under it
    ld hl,(speed)               ; else down to it: at once on the road (the
    ld bc,-SPEED_DRAG           ; speed was not over SPEED_MAX), SPEED_DRAG
    add hl,bc                   ; a VSYNC on the grass
    or a
    sbc hl,de
    add hl,de
    jp nc,demo_speed_set        ; still over it
    ex de,hl
    jp demo_speed_set

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
;; steer_x: NZ - Z if none. step_even - A = how far road_x is to go: the
;; step that takes it there, or as far as a step goes (STEP_MAX pairs either
;; way) - an even number of pairs, road_x being even: none for a pair.
;; Destroys B.
;; ---------------------------------------------------------------------------
STEP_MAX    EQU 4               ; pairs a step worked out ahead takes at most
                                ; (one made there and then: two, cache_steps)
cp_pend
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
