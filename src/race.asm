;; ===========================================================================
;; race.asm - the race's extras (RACE.BIN: the loader loads it at RACE_BLOB,
;; and boot_car puts it in place - records, as SOUND.BIN's): the pause, the
;; best times, the start of a race.
;;
;; Bank 7 has no room left for them: they run with RAM_C1 from hidden lines
;; of pages 0 and 2 (hw.asm RACE_P0..), called from the main loop and the
;; race's rules (game.asm).
;;
;; The pause: ESC in the race (or getting ready for it, or after it) holds
;; the game - the picture as it was, the sound silent, PAUSE on the message
;; line - till ESC is pressed again.
;;
;; The best times: the TIMES fastest races to the finish, their TOTAL
;; TIMEs, as long as the machine is on. In the demo the message line
;; shows, a slot of SLOT_T VSYNCs each, PRESS FIRE blinking, then TOP
;; TIMES and each of them, its place first - the last race's blinking, if
;; it is one of them, and first in line when the demo comes back.
;; ===========================================================================

TIMES       EQU 5               ; best times kept
SLOT_T      EQU BLINK           ; VSYNCs a slot of the demo's messages
SLOT_TOP    EQU 4               ; slots 0-3: PRESS FIRE; then TOP TIMES,
SLOTS       EQU SLOT_TOP+1+TIMES    ; then the best times, the fastest first

;; ---------------------------------------------------------------------------
    REC_BEGIN RACE_P0

;; rules_demo - (rules_vbl) a VSYNC of the demo's message line
rules_demo
    ld hl,blink_t
    inc (hl)
    ld a,(hl)
    and SLOT_T-1
    jr nz,rd_msg
    ld hl,demo_slot             ; the next slot
    ld a,(hl)
    inc a
    cp SLOTS
    jr c,$+3
    xor a
    ld (hl),a
    sub SLOT_TOP+1
    call nc,entry_text          ; (a best time's)
rd_msg
    ld a,(demo_slot)
    ld b,MSG_PRESS_FIRE
    cp SLOT_TOP
    jr c,rd_blink
    ld b,MSG_TOP_TIMES
    jr z,rd_set
    sub SLOT_TOP                ; a best time: its place
    ld b,MSG_ENTRY
    ld hl,times_new
    cp (hl)
    jr nz,rd_set                ; (the last race's blinks)
rd_blink
    ld a,(blink_t)
    and SLOT_T-1
    cp BLINK_ON
    jr c,rd_set
    ld b,MSG_NONE
rd_set
    ld a,b
    ld (msg),a
    ret

;; entry_text - A = a best time (0 = the fastest): MSG_ENTRY's text is its
;; place and its m'ss"cc
entry_text
    ld b,a
    inc a
    ld (msg_texts+MSG_ENTRY_AT),a
    ld a,b
    add a,a
    add a,a
    add a,b                     ; (5 bytes each)
    add a,lo(times_tab)
    ld l,a
    adc a,hi(times_tab)
    sub l
    ld h,a
    ld de,msg_texts+MSG_ENTRY_AT+2
    ldi                         ; m
    inc de                      ; (')
    ldi                         ; ss
    ldi
    inc de                      ; (")
    ldi                         ; cc
    ldi
    xor a                       ; (both buffers to redraw the line: the
    ld (msg_done),a             ; message may be MSG_ENTRY already)
    ld (msg_done+1),a
    ret

;; times_add - (rules_finish) the race's total time among the best, if it
;; is faster than one of them: times_new its place, and the demo to start
;; with them
times_add
    ld hl,times_tab
    ld b,1
ta_entry
    push hl
    ld de,total_time
    ld c,5
ta_cmp
    ld a,(de)
    cp (hl)
    jr c,ta_in                  ; faster
    jr nz,ta_next               ; slower
    inc hl
    inc de
    dec c
    jr nz,ta_cmp
ta_next                         ; (as fast: after it)
    pop hl
    ld de,5
    add hl,de
    inc b
    ld a,b
    cp TIMES+1
    jr c,ta_entry
    ret                         ; (times_new: 0 since rules_start)
ta_in
    pop de                      ; DE = its place's
    ld a,b
    ld (times_new),a
    ld a,SLOT_TOP
    ld (demo_slot),a
    ld a,TIMES                  ; the slower ones down a place
    sub b
    jr z,ta_set
    push de
    ld c,a
    add a,a
    add a,a
    add a,c
    ld c,a
    ld b,0
    ld hl,times_tab+(TIMES-1)*5-1
    ld de,times_tab+TIMES*5-1
    lddr
    pop de
ta_set
    ld hl,total_time
    ld bc,5
    ldir
    ret

    REC_END RACE_P0,192
;; ---------------------------------------------------------------------------
    REC_BEGIN RACE_P1

;; race_pause - (main_loop) ESC pressed, not in the demo: the game held, the
;; sound silent and PAUSE shown, till it is pressed again; then on from
;; where it was (pause_req: steer's again in this picture)
race_pause
    ld a,(game_mode)
    or a
    ret z
    xor a
    call snd_hold               ; (sound.asm)
    ld a,MSG_PAUSE
    call msg_both
    ld b,3
rp_wait                         ; ESC let go, pressed again, let go
    halt                        ; (an interrupt apart: no bounce)
    push bc
    call read_keys
    pop bc
    and KEY_PAUSE
    jr z,rp_up
    bit 0,b                     ; held: what B = 2 waits for
    jr nz,rp_wait
    djnz rp_wait
rp_up
    bit 0,b                     ; let go: what 3 and 1 wait for
    jr z,rp_wait
    djnz rp_wait
    ld a,(msg)                  ; the message back
    call msg_both
    ld a,1
    call snd_hold
    call read_keys              ; (what was pressed meanwhile not news)
    ld (keys_was),a
    ld a,(vbl_count)            ; the game on from now: no VSYNCs to make up
    ld (last_vbl),a
    ret

;; msg_both - A = a message: on both buffers' message line at once
msg_both
    ld (hv_msg),a
    xor a
    ld (msg_done),a
    ld (msg_done+1),a
    call mb_buf                 ; (A = 0: buffer 0)
    ld a,1
mb_buf
    call select_buf
mb_cells
    call hud_msg                ; (MSG_CELLS a call)
    ld hl,msg_done
    call buf_entry
    ld a,(hl)
    or a
    jr z,mb_cells
    ret

    REC_END RACE_P1,96
;; ---------------------------------------------------------------------------
    REC_BEGIN RACE_P2

;; rules_start - (steer) fire pressed in the demo: a race begins. The demo
;; brakes to a standstill at the start, START_X, the clock and the
;; checkpoints set for it.
rules_start
    ld a,MODE_READY
    ld (game_mode),a
    ld a,MSG_GET_READY
    ld (msg),a
    xor a
    ld (mode_t),a
    ld (msg_t),a
    ld (cp_level),a
    ld (times_new),a
    ld (demo_slot),a
    ld hl,total_time
    ld (hl),a
    ld de,total_time+1
    ld bc,4
    ldir
    ld (stage),a
    ld (msg_next),a
    ld a,START_TIME
    ld (time_left),a
    ld a,EXT_FIRST
    ld (cp_ext),a
    ld hl,course_hold           ; the road to the flat, and straight on
    ld de,props_none
    ld a,1
    jp course_set

;; the best times, as total_time: m, s tens, s units, cs tens, cs units
times_tab   defb 3,3,0,0,0, 3,4,0,0,0, 3,5,0,0,0, 4,0,0,0,0, 4,1,0,0,0
    ASSERT $-times_tab == TIMES*5
times_new   defb 0              ; the last race's place among them (0: none)
demo_slot   defb 0              ; the demo's message line's slot
pause_req   defb 0              ; KEY_PAUSE: ESC pressed (steer)

    REC_END RACE_P2,96
