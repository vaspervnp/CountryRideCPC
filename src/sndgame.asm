;; ===========================================================================
;; sndgame.asm - what the game tells the sound (sound.asm), once a picture
;; from the main loop (RAM_C1): the race's music on or off, the engine, an
;; effect to begin; and the pause's silence. In RACE.BIN, as the race's
;; extras: in page 1's HUD eighth rows (hw.asm SND_M0..) and a hidden line
;; of page 0 (SND_P10).
;;
;; The engine is a note on channel C: its pitch from the revs - the speed
;; in the gear picked, LOW's half as many again as HIGH's at a speed (as Out
;; Run's ratios), so it drops changing up - every other picture a little
;; lower (a hum); on the grass a rumble with it, and in a curve that carries
;; the car out hard (push_v) the tyres' squeal.
;; ===========================================================================

ENG_IDLE    EQU 962             ; the engine's period standing still (65 Hz)
ENG_LOW     EQU 15              ; ... less the speed x this / 32 in LOW
ENG_HIGH    EQU 10              ; ... in HIGH: 340-360 Hz at their tops
ENG_MIN     EQU 170             ; ... no shorter (LOW over its top, slowing)
ENG_VOL     EQU 9
ENG_GRASS   EQU 12              ; its noise's period on the grass
SQUEAL_N    EQU 2               ; ... in a hard curve,
SQUEAL_V    EQU #0050           ; ... the curve's push from this on (8.8
                                ; pairs a picture)
    ASSERT SPEED_MAX*ENG_LOW < 65536

;; ---------------------------------------------------------------------------
    REC_BEGIN SND_M0

;; snd_frame - (the main loop, once a picture) the sound as the game is: the
;; music in the race - unless M has turned it off -, the engine while the
;; player's car is out (not in the demo), an effect when something begins.
;; Destroys AF, BC, DE, HL.
snd_frame
    ld a,(game_mode)                    ; the music: in the race, from its
    cp MODE_RACE                        ; start
    ld a,0
    jr nz,$+3
    inc a
    ld hl,mus_want
    and (hl)
    ld hl,snd_music
    cp (hl)
    call nz,snd_switch
    ld a,(game_mode)                    ; the engine (the demo: none)
    or a
    ld hl,ENG_IDLE
    ld c,a                              ; (C: its volume, 0 in the demo)
    jr z,sf_set
    call eng_period
    ld a,(sf_hum)
    xor 1
    ld (sf_hum),a
    jr z,sf_loud
    ld d,h                              ; every other picture 1/16 longer:
    ld e,l                              ; a hum
    srl d
    rr e
    srl d
    rr e
    srl d
    rr e
    srl d
    rr e
    add hl,de
sf_loud
    ld c,ENG_VOL
sf_set
    ld (eng_regs),hl
    ld a,c
    ld (eng_regs+4),a
    jp sf_noise

mus_want    defb 1                      ; 0: no music (M: player.asm
                                        ; race_keys)

    REC_END SND_M0,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_M1

sf_noise
    ld a,(car_x)                        ; on the grass: its rumble
sf_off
    add a,OFFROAD_X-1                   ; (self-modified: cache.asm
    cp 2*OFFROAD_X-1                    ; lane_road)
    ld bc,(MIX_TONES-MIX_NOISE_C)*256+ENG_GRASS
    jr nc,sf_mix
    ld hl,(push_v)                      ; a curve carrying the car out hard:
    ld a,h                              ; the tyres squeal
    or a
    jp p,sf_push
    xor a
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a
sf_push
    ld de,-SQUEAL_V
    add hl,de
    ld c,SQUEAL_N
    jr c,sf_mix
    ld b,MIX_TONES
sf_mix
    ld a,b
    ld (eng_regs+3),a
    ld a,c
    ld (eng_regs+2),a
    ld b,0                              ; B: the effect, if one
    ld a,(count_gear)                   ; the count: a beep, and GO! at its end
    ld hl,sf_count
    cp (hl)
    ld (hl),a
    jr z,sf_msg_j
    ld b,lo(fx_beep)
    or a
    jr nz,sf_msg_j
    ld b,lo(fx_go)
sf_msg_j
    jp sf_msg

sf_count    defb 0                      ; at the last picture: the count, the
sf_msgs     defb 0                      ; message, coll_t; the engine's hum
sf_coll_t   defb 0
sf_hum      defb 0

    REC_END SND_M1,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_M2

sf_msg
    ld a,(msg)                          ; EXTENDED TIME, TIME UP, FINISH
    ld hl,sf_msgs
    cp (hl)
    ld (hl),a
    jr z,sf_colls
    cp MSG_EXTENDED_TIME
    jr nz,$+4
    ld b,lo(fx_cp)
    cp MSG_TIME_UP
    jr nz,$+4
    ld b,lo(fx_timeup)
    cp MSG_FINISH
    jr nz,sf_colls
    ld b,lo(fx_finish)
sf_colls
    ld a,(coll_t)                       ; a bump or a crash begins
    ld hl,sf_coll_t
    ld c,(hl)
    ld (hl),a
    cp c
    jr c,sf_fx
    jr z,sf_fx
    ld b,lo(fx_bump)
    ld a,(coll_kind)
    or a
    jr z,sf_fx
    ld b,lo(fx_crash)
sf_fx
    ld a,(game_mode)                    ; (none in the demo)
    or a
    ret z
    ld a,b
    or a
    ret z
    ld (fx_new),a
    ret

    REC_END SND_M2,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_M3

;; snd_switch - A = 1: the music from its start; 0: none
snd_switch
    or a
    jr nz,ssw_on
    ld (snd_music),a
    jr snd_mute
ssw_on
    ld hl,mus_lead
    ld (snd_ch_a+CH_ORD),hl
    ld hl,mus_bass
    ld (snd_ch_b+CH_ORD),hl
    ld (snd_ticks),a                    ; (A = 1: a row at the next update)
    xor a
    ld (snd_rows),a
    inc a
    ld (snd_music),a                    ; (last: the interrupt plays it now)
    ret

;; snd_hold - (race.asm: the pause) A = 0: all silent, the music held where
;; it is; else on again as it was (the engine at the next snd_frame, the
;; music's volumes at their next notes)
snd_hold
    ld hl,snd_music
    or a
    jr z,sh_off
    ld a,(sh_music)
    ld (hl),a
    ret
sh_off
    ld a,(hl)
    ld (sh_music),a
    xor a
    ld (hl),a
    ld (eng_regs+4),a
    ld (fx_ticks),a
;; snd_mute - (A = 0) the music's volumes 0, written now
snd_mute
    ld (snd_ch_a+CH_VOL),a
    ld (snd_ch_b+CH_VOL),a
    ld e,a
    ld c,8
    di
    call psg_w
    inc c
    call psg_w
    ei
    ret

sh_music    defb 0                      ; snd_music when it stopped

    REC_END SND_M3,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_P10

;; eng_period - HL = the engine's period: ENG_IDLE less the speed x the
;; gear's ENG_LOW or ENG_HIGH / 32, ENG_MIN at the shortest
eng_period
    ld de,(speed)
    ld a,(drive_gear)
    or a
    ld a,ENG_HIGH
    jr nz,$+4
    ld a,ENG_LOW
    ld hl,0
ep_mul
    add hl,de
    dec a
    jr nz,ep_mul
    ld b,5
ep_div
    srl h
    rr l
    djnz ep_div
    ex de,hl
    ld hl,ENG_IDLE-ENG_MIN
    or a
    sbc hl,de
    jr nc,$+5
    ld hl,0
    ld de,ENG_MIN
    add hl,de
    ret

    REC_END SND_P10,SND_PIECE
