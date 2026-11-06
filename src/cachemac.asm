;; ===========================================================================
;; cachemac.asm - making a template for the cache set (cache.asm): a copy of
;; this goes in bank 5, for band B's set (st5), and one in bank 4, for band
;; A's and band 2's (tl_a).
;; ===========================================================================

;; TM_PUT n,lg,tab,cache,next - A = 2 g + 2, L = 2 g, H = a (the byte group
;; g's core's left edge is at, H + its shift: cache5.asm): the template
;; tools/mkroad.py template() makes for it - core entry (IY), AF (A = right
;; grass entry, F: Z = no exit patch), left grass entry (IX) or the byte the
;; patch hides, exit patch - at slot 1 + g of the cache set {cache} (or of
;; the set tm_<n>_page's operand is the page of: pre5, pre4); then JP
;; {next}. lg is the band's left grass, tab its per group table
;; (tools/mkroad.py: K = lo(lg) + PAIRS + H + p, the core's code, its entry
;; table). The core's edges, in pairs from the left of the screen:
;;
;;   p = a AND 1    u = 24 + (a + 1) / 2    l = u - H - p
;;
;; Destroys AF, BC, DE, HL.

MACRO TM_PUT n,lg,tab,cache,next
    add a,a
    add a,a
    ld e,a
tm_{n}_page
    ld a,hi({cache})                    ; (self-modified)
    adc a,0
    ld d,a                              ; DE = slot 1 + g
    ld a,h
    inc a
    sra a
    rr l                                ; L = g, + 128 for p = 0
    add a,24
    ld c,a                              ; C = u
    ld h,hi({tab})                      ; HL: K
    dec a
    cp PAIRS
    jr nc,@right                        ; u > PAIRS, or u <= 0
    ld a,(hl)
    sub c                               ; lo(lg) + PAIRS - l
    cp lo({lg})+PAIRS+1
    jr nc,@left                         ; l < 0
    ld b,a                              ; all of it on the screen:
    set 6,l
    ld a,(hl)
    inc h
    ld h,(hl)
    ld l,a                              ; HL = the core's code
    ex de,hl
    ld (hl),e
    inc l
    ld (hl),d                           ; IY: its first pair
    inc l
    ld (hl),#40                         ; F: Z, no exit patch
    inc l
    ld (hl),c                           ; A: u
    inc l
    ld (hl),b
    inc l
    ld (hl),hi({lg})                    ; IX: lg + PAIRS - l
    jp {next}

@left                                   ; cut off on the left
    set 6,l
    ld b,(hl)                           ; B = the code's low byte
    inc h
    ld a,(hl)
    res 6,l
    ld l,(hl)
    ld h,a                              ; HL: the entry table, in its page
    ex de,hl
    ld (hl),b
    inc l
    ld (hl),d                           ; IY: the core's first pair
    inc l
    ld (hl),0                           ; F: NZ, an exit patch
    inc l
    ld (hl),c                           ; A: u
    inc l
    ex de,hl
    ld a,c
@patch                                  ; A = u, HL: the entry table, DE =
    TM_ENTRY                            ; slot + 4: the patch is pair u's
    ld a,(hl)                           ; code ...
    ex de,hl
    ld (hl),a                           ; IX: the byte it hides
    inc l
    ld (hl),0
    inc l
    ld (hl),e
    inc l
    ld (hl),d                           ; ... the patch
    jp {next}

@right                                  ; past the right edge (A = u - 1)
    or a
    jp m,@none_l                        ; u <= 0: none of it on the screen
    ld a,(hl)
    sub c                               ; lo(lg) + PAIRS - l
    cp lo({lg})+1
    jr c,@none_r                        ; l >= PAIRS: none of it either
    cp lo({lg})+PAIRS+1
    jr nc,@both                         ; l < 0: cut off on the left too
    ld iyh,a
    set 6,l
    ld b,(hl)                           ; B = the code's low byte
    inc h
    ld a,(hl)
    res 6,l
    ld l,(hl)
    ld h,a                              ; HL: the entry table
    ld a,c
    sub PAIRS
    TM_ENTRY                            ; HL = pair u - PAIRS's code
    ex de,hl
    ld (hl),e
    inc l
    ld (hl),d                           ; IY: in there
    inc l
    ld (hl),#40                         ; F: Z
    inc l
    ld (hl),PAIRS                       ; A: no right grass
    inc l
    ld a,iyh
    ld (hl),a
    inc l
    ld (hl),hi({lg})                    ; IX: lg + PAIRS - l
    jp {next}
@both                                   ; past both edges
    set 6,l
    ld b,(hl)
    inc h
    ld a,(hl)
    res 6,l
    ld l,(hl)
    ld h,a                              ; HL: the entry table
    ld a,l
    ld iyl,a
    ld a,c
    sub PAIRS
    TM_ENTRY
    ex de,hl
    ld (hl),e
    inc l
    ld (hl),d                           ; IY: in at the right edge
    inc l
    ld (hl),0                           ; F: NZ
    inc l
    ld (hl),PAIRS
    inc l
    ld a,iyl
    ld e,a
    ex de,hl                            ; HL: the entry table again
    ld a,c
    jp @patch

@none_l                                 ; all left of the screen: grass
    ld b,0
    ld a,lo({lg})+PAIRS
    jr @none
@none_r                                 ; all right of it
    ld b,PAIRS
    ld a,lo({lg})
@none
    ex de,hl
    ld (hl),lo(empty_core)
    inc l
    ld (hl),hi(empty_core)
    inc l
    ld (hl),#40
    inc l
    ld (hl),b
    inc l
    ld (hl),a
    inc l
    ld (hl),hi({lg})
    jp {next}
MEND

;; TM_ENTRY - A = j, C's bit 0 j's, B = a core's code's low byte, HL = its
;; entry table (re_..., the code's page): HL = pair j's code - the entry
;; table has every other pair's; an odd pair is 1 byte on, or 4 after LD
;; BC,nn / PUSH BC. Destroys AF.
MACRO TM_ENTRY
    srl a
    add a,l
    ld l,a
    ld a,(hl)
    add a,b
    ld l,a
    bit 0,c
    jr z,@even
    ld a,(hl)
    inc l
    cp 1
    jr nz,@even
    inc l
    inc l
    inc l
@even
MEND

;; TM_PASS n,lg,tab,cache - tl_<n>: the templates (TM_PUT) of the groups on
;; the list (rd_lsp: words a * 256 + 2 g, up to #00FE), read with POP - an
;; interrupt only writes below SP, where the list is done with. Destroys
;; everything.
MACRO TM_PASS n,lg,tab,cache
tl_{n}
    ld (@sp+1),sp
    ld sp,(rd_lsp)
    jr tl_{n}_next
@sp
    ld sp,0                             ; (self-modified)
    ret
tl_{n}_next
    pop hl                              ; L = 2 g, H = a
    ld a,l
    add a,2
    jr z,@sp                            ; (#FE: the end)
    TM_PUT {n},{lg},{tab},{cache},tl_{n}_next
MEND

;; LANE_COPY n,tab - lc_<n>: E = an index of a per group table ({tab}, two
;; pages: g, or NGROUPS + g), D = the first page of a lane count's own
;; (lanes.asm, lanes5.asm): its entries - +0, +64, +128, +192 of both
;; pages - copied into the table. Destroys AF, B, HL.
MACRO LANE_COPY n,tab
lc_{n}
    ld b,hi({tab})
    call @page
    inc d
    inc b
    call @page
    dec d
    ret
@page
    ld l,e
@byte
    ld h,d
    ld a,(hl)
    ld h,b
    ld (hl),a
    ld a,l
    add a,64
    ld l,a
    jr nc,@byte
    ret
MEND
