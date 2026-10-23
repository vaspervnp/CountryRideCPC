;; ===========================================================================
;; cachegap.asm - code in the 64 bytes between two of the cache's per-group
;; tables (cache.asm, fragment 6; the other fragments are full).
;; ===========================================================================
cachegap_start

;; bush_erase's lines after those of a box it erased (bush.asm)
be_segd                                 ; (back here, HL a line past them)
    ld a,c
    or a
    jp z,be_boxd
    ld a,ixl
    cp ixh
    jr nz,be_same
    ld sp,(be_ptr+1)                    ; (on a record read: a stack)
    call be_next                        ; the other green
be_same
    ld a,ixl
    and 7
    jp nz,be_seg                        ; on in the same row
    ld a,h                              ; on to the next character row
    sub #40
    ld h,a
    ld a,l
    add a,96
    ld l,a
    jp nc,be_seg
    inc h
    jp be_seg

    ASSERT $-cachegap_start <= #40
    defs #40-($-cachegap_start),0
