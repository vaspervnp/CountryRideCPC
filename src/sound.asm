;; ===========================================================================
;; sound.asm - the sound: the race's music, the engine, the effects - what
;; the interrupt plays (SOUND.BIN: the loader loads it at SOUND_BLOB, and
;; boot_car puts it in place - records, as CARn.BIN's).
;;
;; The PSG (AY-3-8912), through the PPI:
;;   A, B   the music (gen/music.asm: tools/mksound.py), the lead and the
;;          bass, in the race;
;;   C      the engine, its pitch from the speed and the gear, a rumble on
;;          the grass, its tyres squealing in a hard curve; or an effect for
;;          a while: the count's beeps and GO!, a checkpoint, a bump, a
;;          crash, time up, the finish.
;; The interrupt plays it all - snd_irq, from irq_idle, every other frame:
;; 25 times a second, as the game draws - so it is in pages 0 and 2, in
;; pieces of a line (hw.asm SND_P0..), mapped whatever the RAM
;; configuration. Once a picture the main loop tells it what the game is
;; doing (sndgame.asm, in RACE.BIN): the race on or not, the engine, an
;; effect to begin.
;;
;; The PSG is written only where something changes: a channel's period at
;; a new note, its volume at a note and as it falls; channel C's registers
;; (c_regs) where they differ from what was written last (c_last).
;; read_keys reads the keyboard through the PSG too, with interrupts off.
;; ===========================================================================

CH_ORD      EQU 0               ; a music channel: its next bar in its order
CH_PAT      EQU 2               ; list, its next row, its period, its volume,
CH_PER      EQU 4               ; ... at a note, its fall an update, the
CH_VOL      EQU 6               ; volume it stays at, its list's start, its
CH_V0       EQU 7               ; period's (low) register and its volume's
CH_DEC      EQU 8
CH_SUS      EQU 9
CH_START    EQU 10
CH_RP       EQU 12
CH_RV       EQU 13

MIX_TONES   EQU %00111000       ; the mixer (a bit set: off): tones A, B and C,
MIX_NOISE_C EQU %00100000       ; no noise (and the PSG's port in: the
MIX_TONE_C  EQU %00000100       ; keyboard); C's noise; C's tone

;; ---------------------------------------------------------------------------
    REC_BEGIN SND_P0

;; snd_irq - (irq_idle) every other frame: the music a tick on, channel C as
;; it should be. Keeps all but AF, BC, HL (the interrupt's).
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
    inc hl                              ; (snd_rows: the row's number + 1)
    inc (hl)
    ld ix,snd_ch_a
    call snd_row
    ld ix,snd_ch_b
    jp snd_row

;; psg_w - C = a PSG register, E = its value: written. psg_wa: the register
;; in A. Destroys AF, B. (sndgame.asm's too, with interrupts off.)
psg_w
    ld a,c
psg_wa
    ld b,#F4
    out (c),a
    ld b,#F6
    ld a,#C0
    out (c),a
    xor a
    out (c),a
    ld b,#F4
    out (c),e
    ld b,#F6
    ld a,#80
    out (c),a
    xor a
    out (c),a
    ret

    REC_END SND_P0,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_P1

;; snd_row - IX = a channel: its next row (from its next bar's pattern at
;; the bar's first)
snd_row
    ld a,(snd_rows)
    dec a
    and 7
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
    jp z,sr_vol                         ; off (A = 0)
    dec a                               ; the tune's note A: its period
    add a,a
    add a,lo(snd_periods)
    ld l,a
    adc a,hi(snd_periods)
    sub l
    ld h,a
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    jp sr_per

    REC_END SND_P1,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_P2

;; snd_bar - IX = a channel: its next bar's pattern (round again at #FFFF)
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
sd_out                                  ; (A = the volume) written
    ld e,a
    ld c,(ix+CH_RV)
    jp psg_w

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

;; snd_chan_c - channel C (c_regs: registers 4-7 and 10): an effect
;; snd_frame asked for begins; one under way goes on, a step at a time; or
;; the engine. Then what changed written.
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
    jp z,scc_engine                     ; (over, sr_per's piece)
scc_fx                                  ; as its step has it
    ld hl,(fx_per)
    bit 7,h
    ld a,MIX_TONES
    jr z,scc_tone
    ld a,l                              ; noise of period L
    ld (c_regs+2),a
    ld a,MIX_TONES-MIX_NOISE_C+MIX_TONE_C
    jr scc_mix
scc_tone
    ld (c_regs),hl
scc_mix
    ld (c_regs+3),a
    ld a,(fx_vol)
    ld (c_regs+4),a
    jp snd_cout
scc_on
    ld a,(fx_ticks)
    or a
    jp z,scc_engine
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

    REC_END SND_P3,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_P4

;; sr_per - (snd_row) HL = a note's period: its registers that changed
;; written, then its volume
sr_per
    ld c,(ix+CH_RP)
    ld a,l
    cp (ix+CH_PER)
    jr z,sp_hi
    ld (ix+CH_PER),a
    ld e,a
    call psg_w
sp_hi
    inc c
    ld a,h
    cp (ix+CH_PER+1)
    jr z,sp_vol
    ld (ix+CH_PER+1),a
    ld e,a
    call psg_w
sp_vol
    ld a,(ix+CH_V0)
sr_vol
    ld (ix+CH_VOL),a
    jp sd_out

scc_engine                              ; (snd_chan_c) the engine, as
    ld hl,(eng_regs)                    ; snd_frame has it
    ld (c_regs),hl
    ld hl,(eng_regs+2)
    ld (c_regs+2),hl
    ld a,(eng_regs+4)
    ld (c_regs+4),a
;; snd_cout - channel C's registers that differ from c_last written
snd_cout
    ld hl,c_regs+4
    ld de,c_last+4
    ld c,4                              ; (the register - 4: 10 last)
sco_reg
    ld a,(de)
    cp (hl)
    jr nz,sco_write
sco_next
    dec l
    dec e
    dec c
    jp p,sco_reg
    ret
sco_write
    ld a,(hl)
    ld (de),a
    push de
    ld e,a
    ld a,c
    add a,4
    cp 8
    jr c,$+4
    ld a,10
    call psg_wa
    pop de
    jr sco_next

    REC_END SND_P4,SND_PIECE
;; ---------------------------------------------------------------------------
    REC_BEGIN SND_P5

;; the interrupt's state
snd_music   defb 0                      ; 1: the music plays (snd_switch)
snd_ticks   defb 1                      ; updates to the next row, then
snd_rows    defb 0                      ; ... rows so far (8 a bar)
c_regs      defb 0,0,0,MIX_TONES,0      ; channel C's registers 4-7 and 10,
c_last      defs 5,#FF                  ; ... as last written
    ASSERT hi(c_regs) == hi(c_regs+4) && hi(c_last) == hi(c_last+4)
eng_regs    defw ENG_IDLE               ; the engine (snd_frame): the same
            defb ENG_GRASS,MIX_TONES,0
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
            defb 0,8
snd_ch_b    defw 0,0,0
            defb 0,BASS_V0,BASS_DEC,BASS_SUS
            defw mus_bass
            defb 2,9
    ASSERT snd_ch_b-snd_ch_a == CH_RV+1

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

    INCLUDE "gen/music.asm"
