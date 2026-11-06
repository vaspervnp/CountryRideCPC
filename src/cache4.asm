;; ===========================================================================
;; cache4.asm - the cache's work in bank 4 (RAM_C4; see cache.asm).
;; ===========================================================================

CACHE_A     EQU TMPL_A+CACHE_LEVEL*TMPL_SET  ; (its slot 0, the ground's
    ASSERT (CACHE_A & #1FF) == 0 && (rd_t4 & #FF) == 0  ; template, is
    ASSERT tmpl_ground == CACHE_A                       ; roadtmpla.asm's)

;; ---------------------------------------------------------------------------
;; st4, job4 - after st5 (a step sideways) or job5: band A's templates of
;; the groups on the list, and band 2's (slot 1 + NGROUPS + g: on it as
;; group NGROUPS + g). Destroy everything.
;; ---------------------------------------------------------------------------
st4
job4
    TM_PASS a,lgrassa,rd_t4,CACHE_A

;; ---------------------------------------------------------------------------
;; The next step worked out ahead (cache5.asm): band A's and band 2's
;; templates after it in the staging set STAGE_A, set out as the cache set.
;; ---------------------------------------------------------------------------
STAGE_A     EQU #7E00

;; pre4 - after pre5: the templates of the groups on its list, in STAGE_A.
;; Destroys everything.
pre4
    ld a,hi(STAGE_A)
    ld (tm_a_page+1),a
    call tl_a
    ld a,hi(CACHE_A)
    ld (tm_a_page+1),a
    ret

;; cm4 - (cache_commit) STAGE_A's templates into the cache set; rs4 - the
;; other way, STAGE_A made the cache set's again. Destroy BC, DE, HL.
cm4
    ld hl,STAGE_A+8
    ld de,CACHE_A+8
c4_n
    ld bc,8*(NGROUPS+NFAR)
c4_copy
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    ldi
    jp pe,c4_copy
    ret
rs4
    ld hl,CACHE_A+8
    ld de,STAGE_A+8
    jr c4_n

cache4_end
    ASSERT STAGE_A+8*(1+NGROUPS+NFAR) <= #8000
