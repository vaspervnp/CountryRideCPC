;; ===========================================================================
;; sound.asm - the sound: the race's music, the engine, the effects
;; (SOUND.BIN: the loader loads it at SOUND_BLOB, and boot_car puts it in
;; place - records, as CARn.BIN's).
;;
;; The PSG (AY-3-8912), through the PPI:
;;   A, B   the music (gen/music.asm: tools/mksound.py), the lead and the
;;          bass, in the race;
;;   C      the engine, its pitch from the speed, a rumble on the grass; or
;;          an effect for a while: the count's beeps and GO!, a checkpoint,
;;          a bump, a crash, time up, the finish.
;; The interrupt plays it all - snd_irq, from irq_idle, every other frame:
;; 25 times a second, as the game draws - so it is in pages 0 and 2, in
;; pieces of a line (hw.asm SND_P0..), mapped whatever the RAM
;; configuration. Once a picture, the main loop (snd_frame, page 1, hw.asm
;; SND_M0..) tells it what the game is doing: the race on or not, the
;; engine's pitch, an effect to begin. Only the PSG's registers that changed
;; are written. read_keys reads the keyboard through the PSG too, with
;; interrupts off.
;; ===========================================================================

CH_ORD      EQU 0               ; a music channel: its next bar in its order
CH_PAT      EQU 2               ; list, its next row, its period, its volume,
CH_PER      EQU 4               ; ... at a note, its fall an update, the
CH_VOL      EQU 6               ; volume it stays at, its list's start
CH_V0       EQU 7
CH_DEC      EQU 8
CH_SUS      EQU 9
CH_START    EQU 10

MIX_TONES   EQU %00111000       ; the mixer (a bit set: off): tones A, B and C,
MIX_NOISE_C EQU %00100000       ; no noise (and the PSG's port in: the
MIX_TONE_C  EQU %00000100       ; keyboard); C's noise; C's tone

ENG_IDLE    EQU 960             ; the engine's period standing still (65 Hz),
ENG_VOL     EQU 9               ; ... less 3/8 of the speed (8.8)
ENG_GRASS   EQU 12              ; its noise's period on the grass
    ASSERT ENG_IDLE-(SPEED_MAX+SPEED_MAX/2)/4 > 200

;; ---------------------------------------------------------------------------
    REC_BEGIN SND_P0

;; snd_irq - (irq_idle) every other frame: the music a tick on, channel C as
;; it should be, the PSG's registers that changed written. Keeps all but AF,
;; BC, HL (the interrupt's).
snd_irq
    ld a,(vbl_count)
    rra
    jp c,isr_out                        ; (every other frame)
    push de
    push ix
    ld a,(snd_music)
    or a
    call nz,snd_tick
    call snd_chan_c
    call snd_out
    pop ix
    pop de
    jp isr_out

;; snd_tick - the music: the volumes fall; every ROW_TICKS updates a row
;; (every 8 a new bar)
snd_tick
    ld ix,snd_ch_a
    call snd_decay
    ld ix,snd_ch_b
    call snd_decay
    ld hl,snd_ticks
    dec (hl)
    ret nz
    ld (hl),ROW_TICKS
    inc hl                              ; (snd_rows)
    ld a,(hl)
    inc (hl)
    and 7
    ld c,a                              ; C = 0: a new bar
    ld ix,snd_ch_a
    call snd_row
    ld ix,snd_ch_b
    jp snd_row

    REC_END SND_P0,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_P1

;; snd_row - IX = a channel: its next row (C = 0: from its next bar's
;; pattern). Keeps C.
snd_row
    ld a,c
    or a
    call z,snd_bar
    ld l,(ix+CH_PAT)
    ld h,(ix+CH_PAT+1)
    ld a,(hl)
    inc hl
    ld (ix+CH_PAT),l
    ld (ix+CH_PAT+1),h
    or a
    ret z                               ; held
    dec a
    jr nz,sr_note
    ld (ix+CH_VOL),a                    ; off
    ret
sr_note
    dec a                               ; semitones above C2
    ld b,-1
sr_oct
    inc b
    sub 12
    jr nc,sr_oct
    add a,12                            ; its semitone, B its octave
    add a,a
    add a,lo(snd_periods)
    ld l,a
    adc a,hi(snd_periods)
    sub l
    ld h,a
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a                              ; HL = the period an octave 2
    ld a,b
    or a
    jr z,sr_set
sr_half                                 ; halved an octave up (rounded)
    dec b
    jr z,sr_last
    srl h
    rr l
    jr sr_half
sr_last
    srl h
    rr l
    jr nc,sr_set
    inc hl
sr_set
    ld (ix+CH_PER),l
    ld (ix+CH_PER+1),h
    ld a,(ix+CH_V0)
    ld (ix+CH_VOL),a
    ret

    REC_END SND_P1,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_P2

;; snd_bar - IX = a channel: its next bar's pattern (round again at #FFFF).
;; Keeps C.
snd_bar
    ld l,(ix+CH_ORD)
    ld h,(ix+CH_ORD+1)
sb_read
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld a,d
    inc a
    jr nz,sb_set
    ld l,(ix+CH_START)
    ld h,(ix+CH_START+1)
    jr sb_read
sb_set
    ld (ix+CH_ORD),l
    ld (ix+CH_ORD+1),h
    ld (ix+CH_PAT),e
    ld (ix+CH_PAT+1),d
    ret

;; snd_decay - IX = a channel: its volume a step down to its level (0, off,
;; stays 0)
snd_decay
    ld a,(ix+CH_VOL)
    cp (ix+CH_SUS)
    ret c
    ret z
    sub (ix+CH_DEC)
    jr c,sd_sus
    cp (ix+CH_SUS)
    jr nc,sd_set
sd_sus
    ld a,(ix+CH_SUS)
sd_set
    ld (ix+CH_VOL),a
    ret

;; fx_load - HL = an effect's step: into fx_ticks.. (fx_ptr past it); Z: it
;; is the end
fx_load
    ld de,fx_ticks
    ld bc,FX_STEP
    ldir
    ld (fx_ptr),hl
    ld a,(fx_ticks)
    or a
    ret

    REC_END SND_P2,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_P3

;; snd_chan_c - channel C (registers 4-7 and 10 of snd_regs): an effect
;; snd_frame asked for begins; one under way goes on, a step at a time; or
;; the engine
snd_chan_c
    ld hl,fx_new
    ld a,(hl)
    ld (hl),0
    or a
    jr z,scc_on
    ld l,a                              ; (its first step)
    ld h,hi(fx_steps)
scc_load
    call fx_load
    jr z,scc_engine                     ; (over)
scc_fx                                  ; as its step has it
    ld hl,(fx_per)
    bit 7,h
    ld a,MIX_TONES
    jr z,scc_tone
    ld a,l                              ; noise of period L
    ld (snd_regs+6),a
    ld a,MIX_TONES-MIX_NOISE_C+MIX_TONE_C
    jr scc_mix
scc_tone
    ld (snd_regs+4),hl
scc_mix
    ld (snd_regs+7),a
    ld a,(fx_vol)
    ld (snd_regs+10),a
    ret
scc_on
    ld a,(fx_ticks)
    or a
    jr z,scc_engine
    dec a
    ld (fx_ticks),a
    ld hl,(fx_ptr)
    jr z,scc_load                       ; its next step
    ld a,(fx_vol)
    ld hl,fx_dec
    sub (hl)
    jr nc,$+3
    xor a
    ld (fx_vol),a
    jr scc_fx
scc_engine                              ; (8 and 9: snd_out's)
    ld hl,eng_regs
    ld de,snd_regs+4
    ld bc,7
    ldir
    ret

    REC_END SND_P3,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_P4

;; snd_out - the music's periods and volumes into snd_regs, and the PSG's
;; registers that differ from what was written last (snd_last) written
snd_out
    ld hl,(snd_ch_a+CH_PER)
    ld (snd_regs),hl
    ld hl,(snd_ch_b+CH_PER)
    ld (snd_regs+2),hl
    ld a,(snd_ch_a+CH_VOL)
    ld (snd_regs+8),a
    ld a,(snd_ch_b+CH_VOL)
    ld (snd_regs+9),a
    ld hl,snd_regs+10
    ld de,snd_last+10
    ld c,10
so_reg
    ld a,(de)
    cp (hl)
    jr nz,so_write
so_next
    dec l
    dec e
    dec c
    jp p,so_reg
    ret
so_write
    ld a,(hl)
    ld (de),a
    ld b,#F4                            ; the PSG: register C ...
    out (c),c
    ld b,#F6
    ld a,#C0
    out (c),a
    xor a
    out (c),a
    ld b,#F4                            ; ... = (HL)
    ld a,(hl)
    out (c),a
    ld b,#F6
    ld a,#80
    out (c),a
    xor a
    out (c),a
    jr so_next

    REC_END SND_P4,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_P5

;; the interrupt's state
snd_music   defb 0                      ; 1: the music plays (snd_switch)
snd_ticks   defb 1                      ; updates to the next row, then
snd_rows    defb 0                      ; ... rows so far (8 a bar)
snd_regs    defb 0,0,0,0,0,0,0,MIX_TONES,0,0,0  ; the PSG's registers 0-10,
snd_last    defs 11,#FF                 ; ... as last written
    ASSERT hi(snd_regs) == hi(snd_regs+10) && hi(snd_last) == hi(snd_last+10)
eng_regs    defw ENG_IDLE               ; the engine (snd_frame): registers 4-10
            defb ENG_GRASS,MIX_TONES    ; as it has them (8 and 9 not used)
            defb 0,0,0
fx_new      defb 0                      ; an effect to begin: its first step's
                                        ; address's low byte (snd_frame)
fx_ticks    defb 0                      ; the effect's step: its updates left,
fx_vol      defb 0                      ; ... its volume, its fall an update,
fx_dec      defb 0                      ; ... its period (fx_steps)
fx_per      defw 0
FX_STEP     EQU $-fx_ticks
fx_ptr      defw 0                      ; ... its next step

;; the music's channels: CH_...
snd_ch_a    defw 0,0,0
            defb 0,LEAD_V0,LEAD_DEC,LEAD_SUS
            defw mus_lead
snd_ch_b    defw 0,0,0
            defb 0,BASS_V0,BASS_DEC,BASS_SUS
            defw mus_bass

    REC_END SND_P5,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_P6

;; the effects: steps of FX_STEP bytes - updates (0: the end), the volume,
;; its fall an update, the period (#8000 + n: noise of period n)
fx_steps
fx_beep     defb 6,13,1
            defw 142                    ; A4
            defb 0
fx_go       defb 12,14,1
            defw 71                     ; A5
            defb 0
fx_finish   defb 2,13,0
            defw 119                    ; C5 E5 G5, then as at a checkpoint
            defb 2,13,0
            defw 95
            defb 2,13,0
            defw 80
fx_cp       defb 2,13,0
            defw 119                    ; C5 E5 G5 C6
            defb 2,13,0
            defw 95
            defb 2,13,0
            defw 80
            defb 8,14,1
            defw 60
            defb 0
fx_bump     defb 4,14,3
            defw #8008
            defb 0
fx_crash    defb 3,15,0
            defw #8006
            defb 16,15,1
            defw #801F
            defb 0
fx_timeup   defb 5,13,1
            defw 159                    ; G4 E4 C4
            defb 5,13,1
            defw 189
            defb 10,13,1
            defw 239
            defb 0
fx_end
    ASSERT hi(fx_steps) == hi(fx_end-1) && lo(fx_steps) != 0

    REC_END SND_P6,SND_PIECE
;; ---------------------------------------------------------------------------
;; What the main loop runs (RAM_C1): in page 1
    REC_BEGIN SND_M0

;; snd_frame - (the main loop, once a picture) the sound as the game is: the
;; music in the race, the engine while the player's car is out (not in the
;; demo), an effect when something begins. Destroys AF, BC, DE, HL.
snd_frame
    ld a,(game_mode)                    ; the music: in the race, from its
    cp MODE_RACE                        ; start
    ld a,0
    jr nz,$+3
    inc a
    ld hl,snd_music
    cp (hl)
    call nz,snd_switch
    ld a,(game_mode)
    or a
    ld hl,ENG_IDLE
    ld c,a                              ; (C: its volume, 0 in the demo)
    jr z,sf_engine
    ld hl,(speed)
    srl h
    rr l
    srl h
    rr l                                ; speed / 4
    ld d,h
    ld e,l
    srl d
    rr e                                ; ... + speed / 8
    add hl,de
    ex de,hl
    ld hl,ENG_IDLE
    or a
    sbc hl,de                           ; its period
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
sf_engine
    jp sf_set

    REC_END SND_M0,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_M1

sf_set
    ld (eng_regs),hl
    ld a,c
    ld (eng_regs+6),a
    ld a,(car_x)                        ; on the grass: its rumble
    add a,OFFROAD_X-1
    cp 2*OFFROAD_X-1
    ld a,MIX_TONES
    jr c,$+4
    ld a,MIX_TONES-MIX_NOISE_C
    ld (eng_regs+3),a
    ld b,0                              ; B: the effect, if one
    ld a,(count_gear)                   ; the count: a beep, and GO! at its end
    ld hl,sf_count
    cp (hl)
    ld (hl),a
    jr z,sf_msg
    ld b,lo(fx_beep)
    or a
    jr nz,sf_msg
    ld b,lo(fx_go)
sf_msg
    ld a,(msg)                          ; EXTENDED TIME, TIME UP, FINISH
    ld hl,sf_msgs
    cp (hl)
    ld (hl),a
    jr z,sf_coll
    cp MSG_EXTENDED_TIME
    jr nz,$+4
    ld b,lo(fx_cp)
    cp MSG_TIME_UP
    jr nz,$+4
    ld b,lo(fx_timeup)
    cp MSG_FINISH
    jr nz,sf_coll
    ld b,lo(fx_finish)
sf_coll
    jp sf_colls

sf_count    defb 0                      ; at the last picture: the count, the
sf_msgs     defb 0                      ; message, coll_t; the engine's hum
sf_coll_t   defb 0
sf_hum      defb 0

    REC_END SND_M1,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_M2

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

;; snd_switch - A = 1: the music from its start; 0: none
snd_switch
    or a
    jr nz,ssw_on
    ld (snd_music),a
    ld (snd_ch_a+CH_VOL),a
    ld (snd_ch_b+CH_VOL),a
    ret
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

    REC_END SND_M2,SND_PIECE

;; ---------------------------------------------------------------------------
    REC_BEGIN SND_P10

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
    ld (eng_regs+6),a
    ld (fx_ticks),a
    ld (snd_ch_a+CH_VOL),a
    ld (snd_ch_b+CH_VOL),a
    ret
sh_music    defb 0                      ; snd_music when it stopped

    REC_END SND_P10,SND_PIECE

    INCLUDE "gen/music.asm"
