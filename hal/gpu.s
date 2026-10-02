; ---------------------------------------------------------------------------
; GPU program: replays the PPU command log written by the 68k and renders
; GB (CGB) scanlines straight into 176x144 RGB16 framebuffers (8 hidden pixels
; on each side: no clipping anywhere). Loaded at $F03000 by init_gpu.
;
; Everything the line renderer needs is prepared when the data changes, not
; when it is drawn:
; - GRAW: raw copy of VRAM (both banks). A tile data long that does not change
;   costs a compare: streamed tiles can be sent again every frame.
; - GCHK: the tile data as "chunky" rows: one word per tile row, pixel 0 in
;   bits 15-14 (colour number hi, lo); same layout as VRAM. GCHK + $8000 holds
;   the same rows mirrored (horizontal flip = another address).
; - DMAP: the maps decoded: one long per cell = address of the tile's chunky
;   data << 11 | BG priority << 10 | palette << 6, with the mirror, the bank
;   and the vertical flip (row offset ^ 14) in the address. 4 tables (map,
;   LCDC.4), 32 rows of 64 cells (32 columns twice: 21 tiles never wrap).
; - PT / OPT: per palette, 16 pixel pairs: entry a*4+b = rgb(a)<<16 | rgb(b)
;   (OBJ: 0 for the transparent colour, KMASK = what is kept of the picture).
; - CTAB: GB colour -> RGB16 (built by the 68k).
; - SPL: the OAM entries that can be on screen.
; In MAME a taken jump costs 4 cycles and any other instruction 1: the hot
; loops avoid jumps.
; ---------------------------------------------------------------------------

; local RAM layout: the code ends below TBASE
TBASE           equ     $f03a90
SPL             equ     TBASE           ; sprite list: up to 40 OAM entries, the sentinel, 1 spare
REGS            equ     SPL+168         ; 16 longs: copy of $ff40-$ff4f
PT              equ     REGS+64         ; 8 BG palettes x 16 pixel pairs
OPT             equ     PT+512          ; 8 OBJ palettes (must follow PT)
KMASK           equ     OPT+512         ; 16 longs: picture bits kept by an OBJ pixel pair
TMP4            equ     KMASK+64        ; 4 longs (road palette)
WLINE           equ     TMP4+16         ; window line counter
SPEND           equ     WLINE+4         ; address of the sprite list sentinel
SPDIRTY         equ     SPEND+4         ; OAM changed: the list is rebuilt
NPRIO           equ     SPDIRTY+4       ; number of cells with BG priority in each map
LASTPAL         equ     NPRIO+8         ; road: source of BG palette 0 (0: unknown)
TEND            equ     LASTPAL+4       ; (= G_HEAD)

                .phrase
gpu_code::
                .gpu
                .org    $f03000

gpu_start::
                movei   #G_HEAD,r20
                movei   #G_TAIL,r21
                movei   #LOGBUF,r31             ; (no GPU interrupts: r31 is free)
                load    (r21),r22
                shlq    #2,r22
                add     r31,r22
                movei   #GCHK,r23
                movei   #FB0,r24
                movei   #FB1,r25
                moveq   #0,r26                  ; current line
                movei   #REGS,r27
                movei   #$ffff,r28
                movei   #main,r29
                movei   #post,r19
                movei   #$0f0f0f0f,r0
                moveta  r0,r0
                movei   #$33333333,r0
                moveta  r0,r1
; head and tail are 16-bit long indexes into the log (atomic for the 68k)
main:
                move    r22,r0
                sub     r31,r0
                shrq    #2,r0
                store   r0,(r21)
m_wait:         load    (r20),r0
                and     r28,r0
                shlq    #2,r0
                add     r31,r0
                cmp     r22,r0
                jr      eq,m_wait
                nop
                load    (r22),r1
                addqt   #4,r22
                moveta  r1,r5                   ; (flags: see post)
                move    r1,r2
                shlq    #2,r2
                shrq    #26,r2
                shlq    #2,r2                   ; op * 4
                movei   #jtab,r3
                add     r2,r3
                load    (r3),r3
                jump    t,(r3)
                nop

; ---- after any command: bit 31 of the command = render the current line and step to
;      the next one
post:
                movefa  r5,r1
                btst    #31,r1
                jump    eq,(r29)
                nop
p_rl:           move    r26,r1
                addq    #1,r26
; ---------------------------------------------------------------------------
; render line r1
; ---------------------------------------------------------------------------
render:
                .if     NOGPULINE               ; (measurement: no line rendering)
                jump    t,(r29)
                nop
                .endif
                move    r1,r0                   ; r0 = L
                moveta  r0,r3                   ; (kept in the alternate r3)
                movei   #FB_PITCH,r14
                mult    r0,r14
                add     r24,r14
                moveta  r14,r6                  ; (alternate r6: the line in the framebuffer)
                load    (r27),r1                ; r1 = LCDC
                ; ---- background
                move    r27,r2
                addq    #8,r2
                load    (r2),r3                 ; SCY
                addqt   #4,r2
                load    (r2),r5                 ; SCX
                moveta  r5,r2                   ; (alternate r2)
                add     r0,r3
                shlq    #24,r3
                shrq    #24,r3                  ; y
                move    r3,r11
                shlq    #29,r11
                shrq    #28,r11                 ; row * 2
                moveta  r11,r8                  ; (alternate r8)
                shrq    #3,r3
                shlq    #8,r3                   ; map row * 256
                move    r1,r4
                shlq    #27,r4
                shrq    #30,r4                  ; LCDC bits 3 (map), 4 (tile data)
                shlq    #13,r4
                add     r4,r3
                movei   #DMAP,r4
                add     r4,r3                   ; decoded map row
                moveta  r3,r7                   ; (alternate r7)
                move    r5,r6
                shlq    #29,r6
                shrq    #29,r6                  ; fine scroll
                shrq    #3,r5
                shlq    #2,r5
                move    r3,r9
                add     r5,r9                   ; first cell
                moveq   #8,r4
                sub     r6,r4
                shrq    #1,r4
                shlq    #2,r4
                add     r4,r14                  ; long of the first tile's pixel 0
                moveq   #21,r10
                movei   #bg_done,r13
                btst    #0,r6
                movei   #tl_even,r2
                jr      eq,bg_go
                nop
                movei   #tl_odd,r2
bg_go:          jump    t,(r2)
                nop
bg_done:
                ; ---- window
                movefa  r3,r0                   ; L
                load    (r27),r1                ; LCDC
                movei   #1000,r13               ; window start (framebuffer pixel ; 1000: none)
                btst    #5,r1
                movei   #no_win,r18
                jump    eq,(r18)
                nop
                move    r27,r2
                addq    #20,r2
                addq    #20,r2
                load    (r2),r3                 ; WY
                cmp     r3,r0                   ; L - WY
                jump    cs,(r18)                ; L < WY
                addqt   #4,r2
                load    (r2),r3                 ; WX
                movei   #167,r4
                cmp     r4,r3                   ; WX - 167
                jump    cc,(r18)                ; WX >= 167
                nop
                sub     r3,r4                   ; 167 - WX
                addq    #7,r4
                shrq    #3,r4
                move    r4,r10                  ; tiles
                addq    #1,r3                   ; pixel 0 of the window: WX - 7 + 8
                moveta  r3,r4                   ; (alternate r4)
                movei   #WLINE,r7
                load    (r7),r6                 ; window line
                move    r6,r8
                addq    #1,r8
                store   r8,(r7)
                move    r6,r11
                shlq    #29,r11
                shrq    #28,r11                 ; row * 2
                moveta  r11,r10                 ; (alternate r10)
                shrq    #3,r6
                shlq    #8,r6
                move    r1,r4
                shlq    #25,r4
                shrq    #31,r4
                shlq    #13,r4                  ; LCDC bit 6: map
                btst    #4,r1
                jr      eq,wn_v
                nop
                bset    #14,r4                  ; LCDC bit 4: tile data
wn_v:           add     r4,r6
                movei   #DMAP,r4
                add     r4,r6
                moveta  r6,r9                   ; (alternate r9: decoded window row)
                move    r6,r9
                movefa  r6,r14
                move    r3,r4
                shrq    #1,r4
                shlq    #2,r4
                add     r4,r14
                movei   #wn_done,r13
                btst    #0,r3
                movei   #tl_even,r2
                jr      eq,wn_go
                nop
                movei   #tl_odd,r2
wn_go:          jump    t,(r2)
                nop
no_win:         moveta  r13,r4
wn_done:
                ; ---- sprites
                movefa  r3,r0                   ; L
                load    (r27),r1                ; LCDC
                btst    #1,r1
                jump    eq,(r29)
                nop
                movei   #SPDIRTY,r2
                load    (r2),r3
                movei   #sp_ok,r4
                cmpq    #0,r3
                jump    eq,(r4)
                moveq   #0,r3
                ; the OAM changed: list of the entries with y in 1-159
                store   r3,(r2)
                movei   #OAMX,r2
                movei   #SPL,r3
                moveq   #20,r6
                shlq    #1,r6                   ; 40 entries
                movei   #159,r5
sb_l:           load    (r2),r7
                addqt   #4,r2
                move    r7,r8
                shrq    #24,r8
                subq    #1,r8
                cmp     r5,r8
                jr      cc,sb_n
                nop
                store   r7,(r3)
                addqt   #4,r3
sb_n:           subq    #1,r6
                jr      ne,sb_l
                nop
                movei   #SPEND,r2
                store   r3,(r2)
sp_ok:          moveq   #8,r5                   ; height
                btst    #2,r1
                jr      eq,sp_h
                nop
                moveq   #16,r5
sp_h:           move    r0,r9
                addq    #17,r9
                sub     r5,r9                   ; lowest y of a sprite on this line
                movei   #SPEND,r2
                load    (r2),r12
                move    r9,r7
                shlq    #24,r7
                store   r7,(r12)                ; sentinel: always on the line
                movei   #SPL,r2
                movei   #SEL,r3
                moveq   #0,r4                   ; count
                load    (r2),r7
sp_s1:          addqt   #4,r2
                shrq    #24,r7
                sub     r9,r7
                cmp     r5,r7
                jr      cc,sp_s1                ; not on this line (unsigned y - lowest >= h)
                load    (r2),r7                 ; (the next entry)
                move    r2,r6
                subq    #4,r6                   ; the entry
                cmp     r12,r6
                jr      eq,sp_draw              ; the sentinel
                nop
                store   r6,(r3)
                addqt   #4,r3
                addq    #1,r4
                cmpq    #10,r4
                jr      ne,sp_s1
                nop
sp_draw:        cmpq    #0,r4
                jump    eq,(r29)
                nop
                ; draw the selected sprites from the last to the first
                movei   #NPRIO,r2               ; tiles with BG priority in the BG map, and in
                load    (r2),r6                 ; the window map when the window is on the line
                addqt   #4,r2
                load    (r2),r7
                move    r6,r13
                btst    #3,r1
                jr      eq,sp_m0
                nop
                move    r7,r13
sp_m0:          movefa  r4,r2
                shrq    #9,r2                   ; (1000: no window)
                jr      ne,sp_m2
                btst    #6,r1
                jr      eq,sp_m1
                nop
                move    r7,r6
sp_m1:          add     r6,r13
sp_m2:          movei   #sd_end,r18
                movei   #sd_loop,r10
sd_loop:
                subqt   #4,r3
                load    (r3),r2                 ; OAM entry
                load    (r2),r17                ; y x tile attr
                move    r17,r8
                shlq    #8,r8
                shrq    #24,r8                  ; x = framebuffer pixel of pixel 0
                move    r8,r7
                subq    #1,r7
                movei   #167,r6
                cmp     r6,r7
                jump    cc,(r18)                ; x = 0 or x >= 168: off screen
                move    r17,r7
                shrq    #24,r7                  ; y
                move    r0,r9
                addq    #16,r9
                sub     r7,r9                   ; row
                btst    #6,r17
                jr      eq,sd_nv
                move    r17,r16
                sub     r5,r9
                not     r9                      ; vflip: h - 1 - row
sd_nv:          shlq    #16,r16
                shrq    #24,r16                 ; tile
                cmpq    #8,r5
                jr      eq,sd_8
                nop
                bclr    #0,r16
sd_8:           shlq    #3,r16
                add     r9,r16
                shlq    #1,r16                  ; tile * 16 + row * 2
                move    r17,r6
                shlq    #10,r6
                movei   #$a000,r7
                and     r7,r6                   ; bank (attr bit 3), mirrored copy (bit 5: hflip)
                add     r6,r16
                add     r23,r16
                loadw   (r16),r11               ; chunky row
                cmpq    #0,r11
                jump    eq,(r18)                ; transparent row
                nop
                ; BG in front? LCDC.0 and (OBJ behind BG, or tiles with BG priority)
                movei   #sd_nm,r12
                btst    #0,r1
                jump    eq,(r12)
                btst    #7,r17
                jr      ne,sd_mk
                cmpq    #0,r13
                jump    eq,(r12)
                nop
sd_mk:          movefa  r4,r7
                sub     r8,r7                   ; pixels left of the window
                movei   #mk,r12
                movei   #sd_m2,r30
                moveq   #0,r9
                cmpq    #8,r7
                jump    pl,(r12)                ; 8 or more: all on the BG
                nop
                moveq   #1,r9
                cmpq    #1,r7
                jump    mi,(r12)                ; none: all on the window
                nop
                shlq    #1,r7                   ; both: the window part first
                move    r28,r2
                sh      r7,r2
                move    r11,r7
                and     r2,r11
                xor     r11,r7
                moveta  r7,r11                  ; (BG part)
                movei   #sd_m1,r30
                jump    t,(r12)
                nop
sd_m1:          moveta  r11,r12
                movefa  r11,r11
                moveq   #0,r9
                movei   #mk,r12
                movei   #sd_m3,r30
                jump    t,(r12)
                nop
sd_m3:          movefa  r12,r2
                or      r2,r11
sd_m2:          cmpq    #0,r11
                jump    eq,(r18)                ; nothing left
                nop
sd_nm:          move    r17,r6
                shlq    #29,r6
                shrq    #23,r6                  ; palette * 64
                movei   #OPT,r14
                add     r6,r14
                movei   #KMASK,r15
                movefa  r6,r16
                move    r8,r6
                shrq    #1,r6
                shlq    #2,r6
                add     r6,r16                  ; long of pixel 0
                shlq    #16,r11                 ; pixel pairs from the top
                btst    #0,r8
                jr      eq,sp_l
                nop
                shrq    #2,r11                  ; odd x: pixel 0 in a low word
sp_l:           move    r11,r6
                shrq    #28,r6
                jr      eq,sp_k                 ; transparent pair
                shlq    #4,r11
                shlq    #2,r6
                load    (r14+r6),r7             ; colours
                load    (r15+r6),r12            ; what stays of the picture
                load    (r16),r2
                and     r12,r2
                or      r7,r2
                store   r2,(r16)
sp_k:           cmpq    #0,r11
                jr      ne,sp_l
                addqt   #4,r16
sd_end:         subq    #1,r4
                jump    ne,(r10)
                nop
                jump    t,(r29)
                nop

; r11 := the sprite row r11 without the pixels hidden by the BG (r9 = 0) or by the window
; (r9 != 0): OBJ behind BG (attr bit 7, r17) or tiles with BG priority, BG colours 1-3
; r8 = x ; returns via r30 ; uses r2 r6 r7 r12 r14 r16
mk:
                cmpq    #0,r9
                jr      eq,mk_b
                movefa  r4,r12
                move    r8,r6
                sub     r12,r6                  ; window pixel under pixel 0 (< 0: left of it)
                movefa  r9,r2
                jr      t,mk_c
                movefa  r10,r16
mk_b:           movefa  r2,r6                   ; SCX
                add     r8,r6
                subq    #8,r6
                shlq    #24,r6
                shrq    #24,r6                  ; BG pixel under pixel 0
                movefa  r7,r2                   ; decoded row
                movefa  r8,r16                  ; row * 2
mk_c:           move    r6,r12
                sharq   #3,r12
                shlq    #2,r12
                add     r12,r2
                load    (r2),r7                 ; the two cells under the sprite
                addqt   #4,r2
                load    (r2),r12
                move    r7,r2
                shrq    #11,r2
                xor     r16,r2
                loadw   (r2),r2                 ; their chunky rows
                move    r12,r14
                shrq    #11,r14
                xor     r16,r14
                loadw   (r14),r14
                btst    #7,r17
                jr      ne,mk_a                 ; OBJ behind the colours 1-3 of any tile
                nop
                btst    #10,r7                  ; else: of the tiles with BG priority
                jr      ne,mk_p
                nop
                moveq   #0,r2
mk_p:           btst    #10,r12
                jr      ne,mk_a
                nop
                moveq   #0,r14
mk_a:           shlq    #16,r2
                or      r14,r2                  ; 16 BG pixels
                move    r2,r14
                shrq    #1,r14
                or      r14,r2                  ; colour != 0: low bit of each pixel
                moveq   #7,r14
                and     r14,r6
                shlq    #1,r6
                neg     r6
                sh      r6,r2                   ; (left by 2 * fine position)
                shrq    #16,r2
                movei   #$5555,r14
                and     r14,r2
                move    r2,r14
                shlq    #1,r14
                or      r14,r2                  ; both bits of each hidden pixel
                not     r2
                jump    t,(r30)
                and     r2,r11
; ---------------------------------------------------------------------------
; tile loops: r9 first decoded cell, r10 tiles, r11 row * 2, r14 destination
; long of pixel 0 ; continue at r13
; tl_even: pixel 0 at the high word ; tl_odd: pixel 0 at the low word
; ---------------------------------------------------------------------------
tl_even:
                moveq   #15,r17
                shlq    #2,r17                  ; 60
                movei   #$1c0,r30
                movei   #PT,r0
                movei   #te_l,r18
te_l:           load    (r9),r16                ; decoded cell
                addqt   #4,r9
                move    r16,r15
                and     r30,r15
                add     r0,r15                  ; pair table of the palette
                shrq    #11,r16
                xor     r11,r16
                loadw   (r16),r3                ; chunky row
                move    r3,r6
                shrq    #12,r6
                shlq    #2,r6
                load    (r15+r6),r7
                store   r7,(r14)
                move    r3,r6
                shrq    #6,r6
                and     r17,r6
                load    (r15+r6),r7
                store   r7,(r14+1)
                move    r3,r6
                shrq    #2,r6
                and     r17,r6
                load    (r15+r6),r7
                store   r7,(r14+2)
                shlq    #2,r3
                and     r17,r3
                load    (r15+r3),r7
                store   r7,(r14+3)
                subq    #1,r10
                jump    ne,(r18)
                addqt   #16,r14
                jump    t,(r13)
                nop

tl_odd:
                moveq   #15,r17
                shlq    #2,r17                  ; 60
                movei   #$1c0,r30
                movei   #PT,r0
                movei   #to_l,r18
                load    (r14),r2                ; (the pixel left of pixel 0 stays)
                shrq    #16,r2
                shlq    #16,r2
to_l:           load    (r9),r16                ; decoded cell
                addqt   #4,r9
                move    r16,r15
                and     r30,r15
                add     r0,r15                  ; pair table of the palette
                shrq    #11,r16
                xor     r11,r16
                loadw   (r16),r3                ; chunky row
                move    r3,r6                   ; pixel 0: low word, after the pixel kept in r2
                shrq    #14,r6
                shlq    #2,r6
                load    (r15+r6),r7
                and     r28,r7
                or      r2,r7
                store   r7,(r14)
                move    r3,r6                   ; pixels 1-6
                shrq    #8,r6
                and     r17,r6
                load    (r15+r6),r7
                store   r7,(r14+1)
                move    r3,r6
                shrq    #4,r6
                and     r17,r6
                load    (r15+r6),r7
                store   r7,(r14+2)
                move    r3,r6
                and     r17,r6
                load    (r15+r6),r7
                store   r7,(r14+3)
                shlq    #30,r3                  ; pixel 7: high word of the next long
                shrq    #26,r3
                load    (r15+r3),r2
                shrq    #16,r2
                shlq    #16,r2
                subq    #1,r10
                jump    ne,(r18)
                addqt   #16,r14
                store   r2,(r14)                ; (the pixel after it is never visible)
                jump    t,(r13)
                nop

; ---- line (op 8): w2 = line ; the lines after it can come as flags
h_line:
                shlq    #24,r1
                shrq    #24,r1
                move    r1,r26
                movei   #render,r2
                jump    t,(r2)
                addq    #1,r26

; ---- register $ff40-$ff4f (op 2)
h_reg:
                move    r1,r4
                shlq    #28,r4
                shrq    #26,r4
                add     r27,r4
                move    r1,r5
                shlq    #8,r5
                shrq    #24,r5
                jump    t,(r19)
                store   r5,(r4)

; ---- scroll (op 15): b1 = SCY, b3 = SCX
h_scroll:
                move    r1,r5
                shlq    #8,r5
                shrq    #24,r5
                move    r27,r4
                addq    #8,r4
                store   r5,(r4)
                shlq    #24,r1
                shrq    #24,r1
                addqt   #4,r4
                jump    t,(r19)
                store   r1,(r4)

; ---- OAM entry (op 5): w2 = offset ; long: the entry (y x tile attr)
h_oam:
                movei   #$fc,r4
                and     r1,r4
                movei   #OAMX,r5
                add     r5,r4
                load    (r22),r7
                addqt   #4,r22
                store   r7,(r4)
                movei   #SPDIRTY,r4
                jump    t,(r19)
                store   r4,(r4)
; ---- whole OAM (op 7): 40 longs
h_oamall:
                movei   #OAMX,r4
                moveq   #20,r6
                shlq    #1,r6
ho_l:           load    (r22),r7
                addqt   #4,r22
                store   r7,(r4)
                subq    #1,r6
                jr      ne,ho_l
                addqt   #4,r4
                movei   #SPDIRTY,r4
                jump    t,(r19)
                store   r4,(r4)

; ---- end of frame (op 9): publish the framebuffer (index 1-3), then the next one to draw
;      into: neither this one (r24), nor the one published before (r25: the VBlank may be
;      taking it right now), nor the one shown (G_SHOWN, set by the 68k at the VBlank). With
;      three buffers one is free, except when the last two frames came within one VBlank:
;      then wait for the next VBlank.
h_frame:
                move    r24,r5
                shrq    #16,r5
                subq    #16,r5
                subq    #1,r5                   ; index of FBn: (address >> 16) - $11
                movei   #G_DISP,r4
                store   r5,(r4)
                movei   #G_SHOWN,r9
                movei   #hf_c,r10
                movei   #hf_w,r11
hf_w:           load    (r9),r6
                moveq   #1,r7
hf_c:           move    r7,r8
                addq    #16,r8
                addq    #1,r8
                shlq    #16,r8                  ; FBn address: (n + $11) << 16
                cmp     r8,r24
                jr      eq,hf_n
                cmp     r8,r25
                jr      eq,hf_n
                cmp     r7,r6
                jr      eq,hf_n
                nop
                move    r24,r25
                jr      t,hf_ok
                move    r8,r24
hf_n:           addq    #1,r7
                cmpq    #4,r7
                jump    ne,(r10)
                nop
                jump    t,(r11)                 ; (none free yet)
                nop
hf_ok:          addqt   #4,r4                   ; G_FRAMES
                load    (r4),r5
                addq    #1,r5
                store   r5,(r4)
                movei   #WLINE,r4
                moveq   #0,r5
                jump    t,(r19)
                store   r5,(r4)

h_wrap:
                jump    t,(r19)
                move    r31,r22

; ---- colours ---------------------------------------------------------------
; colour r4 (0-31: palette * 4 + colour) of the BG (r2 = 0) or OBJ (r2 != 0) palettes
; := rgb r10 in its 7 pixel pairs ; returns via r30 ; uses r4 r5 r6 r11 r12
setcol:
                move    r4,r6
                shlq    #30,r6
                shrq    #30,r6                  ; colour
                shrq    #2,r4
                shlq    #6,r4
                movei   #PT,r5
                add     r5,r4                   ; pair table of the palette
                cmpq    #0,r2
                jr      eq,sc_bg
                nop
                movei   #OPT-PT,r5
                add     r5,r4
                cmpq    #0,r6
                jump    eq,(r30)                ; OBJ colour 0: transparent
                nop
sc_bg:          move    r6,r5
                shlq    #4,r5
                add     r4,r5                   ; pairs (c, x): high word
                shlq    #2,r6
                add     r4,r6                   ; pairs (x, c): low word
                move    r10,r4
                shlq    #16,r4
                moveq   #4,r11
sc_l:           load    (r5),r12
                and     r28,r12
                or      r4,r12
                store   r12,(r5)
                addqt   #4,r5
                load    (r6),r12
                shrq    #16,r12
                shlq    #16,r12
                or      r10,r12
                store   r12,(r6)
                subq    #1,r11
                jr      ne,sc_l
                addqt   #16,r6
                jump    t,(r30)
                nop

; rgb r10 := GB colour in the low word of r1, LASTPAL := 0 ; returns via r30 ; uses r9
getcol:
                move    r1,r9
                shlq    #17,r9
                shrq    #16,r9
                movei   #CTAB,r10
                add     r10,r9
                loadw   (r9),r10
                movei   #LASTPAL,r9
                jump    t,(r30)
                store   r28,(r9)                ; (not an address)

; ---- whole colour (op 11 BG, 12 OBJ): b1 = colour index 0-31, w2 = GB colour
h_col:
                movei   #getcol,r3
                movei   #hc_1,r30
                jump    t,(r3)
                nop
hc_1:           move    r1,r4
                shlq    #11,r4
                shrq    #27,r4                  ; colour index
                subq    #32,r2
                subq    #12,r2                  ; 0 BG, 4 OBJ
                movei   #setcol,r12
                jump    t,(r12)
                move    r19,r30

; ---- gradient (op 14): colour 0 of the BG palettes in the mask b1 := w2
h_grad3:
                movei   #getcol,r3
                movei   #g3_1,r30
                jump    t,(r3)
                nop
g3_1:           move    r1,r3
                shlq    #8,r3
                shrq    #24,r3                  ; palette mask
                moveq   #0,r2
                moveq   #0,r16
                movei   #g3_next,r17
                movei   #setcol,r18
g3_loop:        btst    #0,r3
                jump    eq,(r17)
                move    r16,r4
                jump    t,(r18)
                move    r17,r30
g3_next:        addq    #4,r16
                shrq    #1,r3
                jr      ne,g3_loop
                nop
                jump    t,(r19)
                nop

; ---- road line (op 16): b1 = SCY, b2 = SCX ; long: address of the 8 bytes of BG palette 0
h_roadln:
                move    r1,r5
                shlq    #8,r5
                shrq    #24,r5
                move    r27,r4
                addq    #8,r4
                store   r5,(r4)                 ; SCY
                move    r1,r5
                shlq    #16,r5
                shrq    #24,r5
                addqt   #4,r4
                store   r5,(r4)                 ; SCX
                load    (r22),r7                ; palette source
                addqt   #4,r22
                movei   #LASTPAL,r4
                load    (r4),r5
                cmp     r5,r7
                jump    eq,(r19)                ; already there
                store   r7,(r4)
                movei   #CTAB,r12
                movei   #PT,r14
                movei   #TMP4,r15
                movei   #rl_c,r16
                movei   #rl_d,r17
                moveq   #4,r6
rl_c:           loadb   (r7),r9                 ; the 4 colours: high words of their pairs
                addqt   #1,r7
                loadb   (r7),r2
                addqt   #1,r7
                shlq    #8,r2
                or      r2,r9
                shlq    #17,r9
                shrq    #16,r9
                add     r12,r9
                loadw   (r9),r9
                store   r9,(r15)
                addqt   #4,r15
                shlq    #16,r9
                store   r9,(r14)
                store   r9,(r14+1)
                store   r9,(r14+2)
                store   r9,(r14+3)
                subq    #1,r6
                jump    ne,(r16)
                addqt   #16,r14
                subq    #16,r15
                subq    #32,r14
                subq    #32,r14
                moveq   #4,r6
rl_d:           load    (r15),r9                ; low words
                addqt   #4,r15
                load    (r14),r3
                or      r9,r3
                store   r3,(r14)
                load    (r14+4),r3
                or      r9,r3
                store   r3,(r14+4)
                load    (r14+8),r3
                or      r9,r3
                store   r3,(r14+8)
                load    (r14+12),r3
                or      r9,r3
                store   r3,(r14+12)
                subq    #1,r6
                jump    ne,(r17)
                addqt   #4,r14
                jump    t,(r19)
                nop

; ---- VRAM -------------------------------------------------------------------
; r13 := offset in the bank (r1 & $1fff), r4 := its address in GRAW (bank = bit 16 of r1)
; returns via r30 ; uses r5
vaddr:
                move    r1,r4
                shlq    #19,r4
                shrq    #19,r4
                move    r4,r13
                move    r1,r5
                shlq    #15,r5
                shrq    #31,r5
                shlq    #13,r5                  ; bank * $2000
                add     r5,r4
                movei   #GRAW,r5
                jump    t,(r30)
                add     r5,r4

; ---- VRAM byte (op 0 / 1 = bank): b1 = value, w2 = address
h_vram:
                move    r1,r4
                shlq    #19,r4
                shrq    #19,r4
                move    r4,r13                  ; offset in the bank
                shlq    #11,r2                  ; bank * $2000 (r2 = op * 4)
                add     r2,r4
                movei   #GRAW,r5
                add     r5,r4
                move    r1,r8
                shrq    #16,r8                  ; (low byte: the value)
                movei   #$1800,r5
                cmp     r5,r13
                jr      cs,hv_t
                nop
                storeb  r8,(r4)                 ; maps: the byte, then its cell
                move    r13,r2
                sub     r5,r2                   ; cell
                moveq   #1,r0
                movei   #hm_l,r7
                jump    t,(r7)
                move    r19,r16
hv_t:           moveq   #3,r7                   ; tile data: its long through the block code
                and     r4,r7
                sub     r7,r4
                sub     r7,r13
                movei   #SCR,r9
                load    (r4),r6
                store   r6,(r9)
                add     r9,r7
                storeb  r8,(r7)
                movei   #hb_go,r7
                jump    t,(r7)
                moveq   #1,r6

; ---- VRAM block from an address (op 3): b1 = (16-byte blocks - 1) << 1 | bank, w2 = address ;
;      long: source address (ROM: the data is read when the command is played)
h_blkp:
                movei   #vaddr,r3
                movei   #bp_1,r30
                jump    t,(r3)
                nop
bp_1:           move    r1,r6
                shlq    #8,r6
                shrq    #25,r6
                addq    #1,r6
                shlq    #2,r6                   ; longs
                load    (r22),r9
                movei   #hb_go,r7
                jump    t,(r7)
                addqt   #4,r22

; ---- VRAM block (op 6): b1 = bank, w2 = address ; long: byte count ; data
h_block:
                movei   #vaddr,r3
                movei   #hb_1,r30
                jump    t,(r3)
                nop
hb_1:           load    (r22),r6
                addqt   #4,r22
                move    r22,r9
                add     r6,r22                  ; (the data follows)
                shrq    #2,r6
; r6 longs from r9 to GRAW at r4 (r13 = offset in the bank): the longs that change are
; stored, then converted (tile data) or decoded (maps)
hb_go:
                movei   #$1800,r5
                movei   #$00ff00ff,r10
                movei   #$00f000f0,r11
                movei   #$0c0c0c0c,r12
                movei   #$22222222,r14
                movei   #hb_l,r15
                movei   #hb_nx,r16
                movei   #GCHK-GRAW,r17
                movei   #hb_map,r18
hb_l:           load    (r9),r7
                addqt   #4,r9
                load    (r4),r8
                cmp     r7,r8
                jump    eq,(r16)                ; unchanged
                cmp     r5,r13
                jump    cc,(r18)                ; maps
                store   r7,(r4)
                ; two rows lo0 hi0 lo1 hi1: swap the bytes, then shuffle hi/lo bits
                move    r7,r8
                shrq    #8,r8
                and     r10,r8
                and     r10,r7
                shlq    #8,r7
                or      r8,r7
                move    r7,r8
                shrq    #4,r8
                xor     r7,r8
                and     r11,r8
                xor     r8,r7
                shlq    #4,r8
                xor     r8,r7
                move    r7,r8
                shrq    #2,r8
                xor     r7,r8
                and     r12,r8
                xor     r8,r7
                shlq    #2,r8
                xor     r8,r7
                move    r7,r8
                shrq    #1,r8
                xor     r7,r8
                and     r14,r8
                xor     r8,r7
                shlq    #1,r8
                xor     r8,r7
                move    r4,r3
                add     r17,r3
                store   r7,(r3)                 ; chunky rows
                movefa  r1,r2                   ; mirrored: the 8 pixels of each word reversed
                move    r7,r8
                shrq    #2,r8
                and     r2,r8
                and     r2,r7
                shlq    #2,r7
                or      r8,r7
                movefa  r0,r2
                move    r7,r8
                shrq    #4,r8
                and     r2,r8
                and     r2,r7
                shlq    #4,r7
                or      r8,r7
                move    r7,r8
                shrq    #8,r8
                and     r10,r8
                and     r10,r7
                shlq    #8,r7
                or      r8,r7
                bset    #15,r3
                store   r7,(r3)
hb_nx:          addqt   #4,r13
                subq    #1,r6
                jump    ne,(r15)
                addqt   #4,r4
                jump    t,(r19)
                nop
; a long of map bytes (tiles or attributes): its 4 cells
hb_map:         move    r13,r2
                sub     r5,r2                   ; first cell
                moveq   #4,r0
; decode r0 cells from cell r2 (map << 10 | row << 5 | column) ; continue at r16
; uses r0 r1 r2 r3 r7 r8 r30
hm_l:           movei   #GRAW+$1800,r7
                add     r2,r7
                loadb   (r7),r3                 ; tile
                bset    #13,r7
                loadb   (r7),r8                 ; attributes
                move    r8,r1
                shlq    #29,r1
                shrq    #23,r1                  ; palette << 6
                btst    #7,r8
                jr      eq,hm_np
                nop
                bset    #10,r1                  ; BG priority
hm_np:          shlq    #4,r3                   ; tile * 16
                move    r23,r7
                btst    #3,r8
                jr      eq,hm_b0
                nop
                bset    #13,r7                  ; bank 1
hm_b0:          btst    #5,r8
                jr      eq,hm_nh
                nop
                bset    #15,r7                  ; hflip: mirrored copy
hm_nh:          btst    #6,r8
                jr      eq,hm_nv
                nop
                addq    #14,r7                  ; vflip: row offset ^ 14
hm_nv:          add     r3,r7
                move    r7,r8
                shlq    #11,r8
                or      r1,r8                   ; cell with LCDC.4 = 1 (tiles at $8000)
                btst    #11,r3
                jr      ne,hm_hi
                nop
                bset    #12,r7                  ; LCDC.4 = 0: tiles 0-127 at $9000
hm_hi:          shlq    #11,r7
                or      r1,r7
                move    r2,r3
                shrq    #10,r3
                shlq    #13,r3                  ; map
                move    r2,r1
                shlq    #22,r1
                shrq    #27,r1
                shlq    #8,r1                   ; row
                add     r1,r3
                move    r2,r1
                shlq    #27,r1
                shrq    #25,r1                  ; column
                add     r1,r3
                movei   #DMAP,r1
                add     r1,r3
                load    (r3),r1                 ; BG priority changed: count the cells that have it
                xor     r7,r1
                btst    #10,r1
                jr      eq,hm_sp
                nop
                movei   #NPRIO,r1
                btst    #10,r2                  ; (the map of the cell)
                jr      eq,hm_m0
                nop
                addq    #4,r1
hm_m0:          load    (r1),r30
                btst    #10,r7
                jr      eq,hm_pd
                subq    #1,r30
                addq    #2,r30
hm_pd:          store   r30,(r1)
hm_sp:          store   r7,(r3)                 ; LCDC.4 = 0
                bset    #7,r3
                store   r7,(r3)                 ; (columns 32-63)
                bset    #14,r3
                store   r8,(r3)                 ; LCDC.4 = 1
                bclr    #7,r3
                store   r8,(r3)
                addq    #1,r2
                subq    #1,r0
                movei   #hm_l,r1
                jump    ne,(r1)
                nop
                jump    t,(r16)
                nop

                .long
jtab:           dc.l    h_vram,h_vram,h_reg,h_blkp,post,h_oam,h_block,h_oamall,h_line,h_frame,h_wrap,h_col,h_col,post,h_grad3,h_scroll,h_roadln
gpu_end_addr::
                .if     gpu_end_addr > TBASE
                .error  "GPU code too long"
                .endif
                .68000
                .phrase
gpu_code_end::
