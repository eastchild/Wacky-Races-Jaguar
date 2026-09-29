; ---------------------------------------------------------------------------
; GPU program: replays the PPU command log written by the 68k and renders
; GB (CGB) scanlines into 160x144 RGB16 framebuffers.
; Loaded at $F03000 by init_gpu.
;
; GVRAM keeps the tile data ($0000-$17ff of each bank) as "chunky" rows: one
; word per tile row, pixel 0 in bits 15-14 (colour number hi,lo). The maps
; stay raw bytes. BG/window pixels are written two at a time through pair
; tables (PT: per BG palette, entry a*4+b = rgb(a)<<16 | rgb(b)) into a line
; buffer of pixel pairs (LB: long (x+8)/2, even x in the high word).
; ---------------------------------------------------------------------------

; local RAM layout
TBASE           equ     $f03980
OAML            equ     TBASE           ; 40 longs: OAM copy (one long per entry)
MCKEY           equ     OAML+160        ; map row cache (BG and window): key, dirty,
MCDIRTY         equ     MCKEY+4
MAPC            equ     MCKEY+8         ;   32 decoded columns, twice (21 tiles never wrap):
                                        ;   tile row 0 offset in GVRAM | attributes << 16
REGS            equ     MAPC+256        ; 16 longs: copy of $ff40-$ff4f
OBC             equ     REGS+64         ; 32 OBJ colours (rgb)
PT              equ     OBC+128         ; 8 BG palettes x 16 pixel pairs
TIB             equ     PT+512          ; BG tiles of the line: chunky row | priority << 16
WLINE           equ     TIB+88          ; window line counter
LB              equ     WLINE+4         ; 88 longs: pixel pairs, screen x at long (x+8)/2
LBEND           equ     LB+352
TIW             equ     $3260           ; (main RAM) window tiles of the line, as TIB
SEL             equ     $32c0           ; (main RAM) up to 10 selected sprites

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
                movei   #GVRAM,r23
                movei   #FB0,r24
                movei   #FB1,r25
                movei   #LB,r26
                movei   #REGS,r27
                movei   #$ffff,r28
                movei   #OAML,r29
                movei   #main,r19
                movei   #TBASE,r0               ; clear the tables
                moveq   #0,r1
                movei   #(G_HEAD-TBASE)/4,r2
oc_l:           store   r1,(r0)
                subq    #1,r2
                jr      ne,oc_l
                addqt   #4,r0
                movei   #MCDIRTY,r0
                store   r0,(r0)
                movei   #$0f0f,r0
                moveta  r0,r0
                movei   #$3333,r0
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
                move    r1,r2
                shrq    #24,r2
                shlq    #2,r2
                movei   #jtab,r3
                add     r2,r3
                load    (r3),r3
                jump    t,(r3)
                nop

; ---- VRAM byte (op 0/1), maps only (tile data comes as blocks): r2 = op*4
h_vram:
                move    r1,r4
                movei   #$1fff,r5
                and     r5,r4
                shlq    #11,r2                  ; bank * $2000
                add     r2,r4
                add     r23,r4
                move    r1,r5
                shrq    #16,r5
                storeb  r5,(r4)                 ; (low byte)
                movei   #MCDIRTY,r6
                store   r6,(r6)
                jump    t,(r19)
                nop

; ---- register $ff40-$ff4f
h_reg:
                move    r1,r4
                moveq   #15,r5
                and     r5,r4
                shlq    #2,r4
                add     r27,r4
                move    r1,r5
                shrq    #16,r5
                movei   #$ff,r6
                and     r6,r5
                store   r5,(r4)
                jump    t,(r19)
                nop

; ---- OAM entry: w2 = offset ; long: the entry (y x tile attr)
h_oam:
                movei   #$fc,r4
                and     r1,r4
                add     r29,r4
                load    (r22),r7
                addqt   #4,r22
                store   r7,(r4)
                jump    t,(r19)
                nop

; r4 = even byte index, r9 = GB colour, r2 = 0 (BG) / 4 (OBJ); returns through r30
; uses r4 r5 r6 r10 r11 r12
hp_set:
                move    r9,r10
                shlq    #27,r10
                shrq    #16,r10                 ; r << 11
                moveq   #31,r12
                move    r9,r11
                shrq    #10,r11
                and     r12,r11
                shlq    #6,r11
                or      r11,r10                 ; b << 6
                move    r9,r11
                shrq    #5,r11
                and     r12,r11
                move    r11,r12
                shlq    #1,r11
                shrq    #4,r12
                or      r12,r11
                or      r11,r10                 ; g6
                cmpq    #0,r2
                movei   #hp_obj,r12
                jump    ne,(r12)
                nop
                ; BG: the 7 pixel pairs using this colour
                move    r4,r6
                moveq   #6,r5
                and     r5,r6                   ; colour*2
                shrq    #3,r4
                shlq    #6,r4
                movei   #PT,r5
                add     r5,r4                   ; pair table of the palette
                move    r6,r5
                shlq    #3,r5
                add     r4,r5                   ; entries (c,x)
                shlq    #1,r6
                add     r4,r6                   ; entries (x,c)
                move    r10,r4
                shlq    #16,r4
                moveq   #4,r11
hp_l:           load    (r5),r12
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
                jr      ne,hp_l
                addqt   #16,r6
                jump    t,(r30)
                nop
hp_obj:
                shlq    #1,r4                   ; (index/2)*4
                movei   #OBC,r12
                add     r4,r12
                store   r10,(r12)
                jump    t,(r30)
                nop

; ---- road line (op 16): b1 = SCY, b2 = line to render then (0: none), b3 = SCX ;
;      long: address of 8 palette bytes (BG palette 0)
h_roadln:
                move    r1,r5
                shrq    #16,r5
                movei   #$ff,r6
                and     r6,r5
                move    r27,r4
                addq    #8,r4
                store   r5,(r4)                 ; SCY
                move    r1,r5
                and     r6,r5
                addq    #4,r4
                store   r5,(r4)                 ; SCX
                load    (r22),r7                ; palette source
                addqt   #4,r22
                moveq   #0,r2                   ; BG
                moveq   #0,r16                  ; byte index
                movei   #rl_next,r17
rl_loop:        loadb   (r7),r9
                addqt   #1,r7
                loadb   (r7),r10
                addqt   #1,r7
                shlq    #8,r10
                or      r10,r9
                move    r16,r4
                movei   #hp_set,r12
                jump    t,(r12)
                move    r17,r30
rl_next:        addq    #2,r16
                cmpq    #8,r16
                movei   #rl_loop,r12
                jump    ne,(r12)
                nop
                shrq    #8,r1                   ; b2: line to render now (0: none)
                move    r1,r4
                shlq    #24,r4
                jump    eq,(r19)
                nop
                movei   #h_line,r4
                jump    t,(r4)
                nop

; ---- scroll (op 15): b1 = SCY, b3 = SCX
h_scroll:
                move    r1,r5
                shrq    #16,r5
                movei   #$ff,r6
                and     r6,r5
                move    r27,r4
                addq    #8,r4
                store   r5,(r4)
                move    r1,r5
                and     r6,r5
                addq    #4,r4
                store   r5,(r4)
                jump    t,(r19)
                nop

; ---- gradient (op 14): colour 0 of BG palettes 0-2 := w2
h_grad3:
                move    r1,r9
                and     r28,r9                  ; colour
                move    r1,r3
                shrq    #16,r3
                movei   #$ff,r5
                and     r5,r3                   ; palette mask
                moveq   #0,r2
                moveq   #0,r16
                movei   #g3_next,r17
g3_loop:        btst    #0,r3
                jump    eq,(r17)
                nop
                move    r16,r4
                movei   #hp_set,r12
                jump    t,(r12)
                move    r17,r30
g3_next:        addq    #8,r16
                shrq    #1,r3
                movei   #g3_loop,r12
                jump    ne,(r12)
                nop
                jump    t,(r19)
                nop
; ---- whole colour (op 11 BG, 12 OBJ): b1 = colour index 0-31, w2 = GB colour
h_col:
                move    r1,r9
                and     r28,r9                  ; colour
                move    r1,r4
                shrq    #16,r4
                moveq   #31,r5
                and     r5,r4
                shlq    #1,r4                   ; byte index
                subq    #32,r2
                subq    #12,r2                  ; 0 BG, 4 OBJ
                movei   #hp_set,r12
                jump    t,(r12)
                move    r19,r30

; ---- VRAM block: long count, data (tile data converted to chunky rows)
h_block:
                move    r1,r4
                movei   #$1fff,r5
                and     r5,r4
                move    r4,r9                   ; offset in the bank
                move    r1,r5
                shrq    #16,r5
                moveq   #1,r6
                and     r6,r5
                shlq    #13,r5
                add     r5,r4
                add     r23,r4                  ; destination
                load    (r22),r6
                addqt   #4,r22
                shrq    #2,r6
                movei   #MCDIRTY,r7             ; (a block may reach the maps)
                store   r7,(r7)
                movei   #$1800,r5
                movei   #$00ff00ff,r10
                movei   #$00f000f0,r11
                movei   #$0c0c0c0c,r12
                movei   #$22222222,r14
                movei   #hb_l,r15
                movei   #hb_st,r16
hb_l:           load    (r22),r7
                addqt   #4,r22
                cmp     r5,r9
                jump    cc,(r16)                ; maps: raw
                addqt   #4,r9
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
hb_st:          store   r7,(r4)
                subq    #1,r6
                jump    ne,(r15)
                addqt   #4,r4
                jump    t,(r19)
                nop

; ---- whole OAM (40 longs)
h_oamall:
                move    r29,r4
                moveq   #20,r6
                addq    #20,r6
ho_l:           load    (r22),r7
                addqt   #4,r22
                store   r7,(r4)
                subq    #1,r6
                jr      ne,ho_l
                addqt   #4,r4
                jump    t,(r19)
                nop

; ---- end of frame: publish the framebuffer, swap
h_frame:
                movei   #G_DISP,r4
                store   r24,(r4)
                move    r24,r5
                move    r25,r24
                move    r5,r25
                movei   #G_FRAMES,r4
                load    (r4),r5
                addq    #1,r5
                store   r5,(r4)
                movei   #WLINE,r4
                moveq   #0,r5
                store   r5,(r4)
                jump    t,(r19)
                nop

h_wrap:
                move    r31,r22
                jump    t,(r19)
                nop

; ---------------------------------------------------------------------------
; decoded map row cache: make the cache at r9 (key at r9-8, dirty at r9-4)
; hold map row r4 ; r1 = LCDC ; returns via r30
; uses r5 r6 r7 r8 r10 r12 r15 r16 r17
; ---------------------------------------------------------------------------
mc_get:
                move    r4,r5
                btst    #4,r1
                jr      eq,mg_k
                nop
                bset    #28,r5                  ; (the key includes the tile data select)
mg_k:           move    r9,r6
                subq    #8,r6
                load    (r6),r7                 ; key
                addqt   #4,r6
                load    (r6),r8                 ; dirty
                cmp     r5,r7
                jr      ne,mg_ld
                nop
                cmpq    #0,r8
                jr      ne,mg_ld
                nop
                jump    t,(r30)
                nop
mg_ld:          moveq   #0,r8
                store   r8,(r6)
                subqt   #4,r6
                store   r5,(r6)
                move    r4,r5                   ; map bytes
                move    r9,r15                  ; cache
                movei   #$2000,r6
                ; tile offset = (t ^ r16) * 16 + r17
                moveq   #0,r16
                moveq   #0,r17
                btst    #4,r1
                jr      ne,mg_u
                nop
                movei   #$80,r16
                movei   #$800,r17
mg_u:           moveq   #16,r10
                shlq    #1,r10                  ; 32 columns
                movei   #mg_l,r12
mg_l:           loadb   (r5),r7                 ; tile
                move    r5,r8
                add     r6,r8
                loadb   (r8),r8                 ; attributes
                xor     r16,r7
                shlq    #4,r7
                add     r17,r7
                btst    #3,r8
                jr      eq,mg_b
                nop
                add     r6,r7                   ; bank 1
mg_b:           shlq    #16,r8
                or      r8,r7
                store   r7,(r15)
                store   r7,(r15+32)             ; (second copy)
                addqt   #4,r15
                subq    #1,r10
                jump    ne,(r12)
                addqt   #1,r5
                jump    t,(r30)
                nop

; ---------------------------------------------------------------------------
; render line r1 & $ff
; ---------------------------------------------------------------------------
h_line:
                .if     NOGPULINE               ; (measurement: no line rendering)
                jump    t,(r19)
                nop
                .endif
                movei   #$ff,r2
                move    r1,r0
                and     r2,r0                   ; r0 = L
                moveta  r0,r3                   ; (kept in the alternate r3)
                load    (r27),r1                ; r1 = LCDC
                ; ---- background
                move    r27,r2
                addq    #8,r2
                load    (r2),r3                 ; SCY
                add     r0,r3
                movei   #$ff,r4
                and     r4,r3                   ; y
                movei   #$1800,r4
                btst    #3,r1
                jr      eq,bg_m
                nop
                movei   #$1c00,r4
bg_m:           add     r23,r4
                move    r3,r5
                shrq    #3,r5
                shlq    #5,r5
                add     r5,r4                   ; r4 = map row
                movei   #MAPC,r9
                movei   #bg_mc,r30
                movei   #mc_get,r2
                jump    t,(r2)
                nop
bg_mc:          moveq   #7,r7
                and     r7,r3                   ; row
                move    r3,r11
                shlq    #1,r11                  ; row*2
                moveq   #14,r12
                sub     r11,r12                 ; (7-row)*2
                move    r27,r2
                addq    #12,r2
                load    (r2),r5                 ; SCX
                moveq   #7,r6
                and     r5,r6                   ; fine scroll
                moveta  r6,r2                   ; (kept in the alternate r2)
                shrq    #3,r5                   ; first column
                shlq    #2,r5
                add     r5,r9                   ; its decoded entry
                moveq   #21,r10
                movei   #TIB,r4
                moveq   #8,r14
                sub     r6,r14
                shrq    #1,r14
                shlq    #2,r14
                add     r26,r14                 ; long of the first tile's pixel 0
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
                movei   #256,r13                ; window start x (256: none)
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
                nop
                addq    #4,r2
                load    (r2),r3                 ; WX
                movei   #167,r4
                cmp     r4,r3                   ; WX - 167
                jump    cc,(r18)                ; WX >= 167
                nop
                sub     r3,r4                   ; 167 - WX
                addq    #7,r4
                shrq    #3,r4
                moveta  r4,r5                   ; tiles
                subq    #7,r3
                moveta  r3,r4                   ; window start x
                movei   #WLINE,r7
                load    (r7),r3                 ; window line
                move    r3,r8
                addq    #1,r8
                store   r8,(r7)
                movei   #$1800,r4
                btst    #6,r1
                jr      eq,wn_m
                nop
                movei   #$1c00,r4
wn_m:           add     r23,r4
                move    r3,r5
                shrq    #3,r5
                shlq    #5,r5
                add     r5,r4                   ; map row
                movei   #MAPC,r9
                movei   #wn_mc,r30
                movei   #mc_get,r2
                jump    t,(r2)
                nop
wn_mc:          moveq   #7,r7
                and     r7,r3
                move    r3,r11
                shlq    #1,r11
                moveq   #14,r12
                sub     r11,r12
                moveq   #0,r5
                movefa  r5,r10
                movei   #TIW,r4
                movefa  r4,r6
                move    r6,r14
                addq    #8,r14
                shrq    #1,r14
                shlq    #2,r14
                add     r26,r14
                movei   #wn_done,r13
                btst    #0,r6
                movei   #tl_even,r2
                jr      eq,wn_go
                nop
                movei   #tl_odd,r2
wn_go:          jump    t,(r2)
                nop
wn_done:        movefa  r4,r13
no_win:
                ; ---- sprites
                movefa  r3,r0                   ; L
                load    (r27),r1                ; LCDC
                btst    #1,r1
                movei   #no_spr,r18
                jump    eq,(r18)
                nop
                moveq   #8,r15                  ; height
                btst    #2,r1
                jr      eq,sp_h
                nop
                moveq   #16,r15
sp_h:           move    r29,r2                  ; OAM pointer
                movei   #SEL,r3
                moveq   #0,r4                   ; count
                moveq   #20,r6
                addq    #20,r6                  ; 40 entries
                movei   #sp_scan,r18
sp_scan:
                load    (r2),r7
                shrq    #24,r7                  ; y
                move    r0,r12
                addq    #16,r12
                sub     r7,r12                  ; L + 16 - y
                cmp     r15,r12
                jr      cc,sp_next              ; not on this line (unsigned >= h)
                nop
                store   r2,(r3)
                addqt   #4,r3
                addq    #1,r4
                cmpq    #10,r4
                jr      eq,sp_draw
                nop
sp_next:        subq    #1,r6
                jump    ne,(r18)
                addqt   #4,r2
sp_draw:
                ; draw selected sprites from the last to the first
                cmpq    #0,r4
                movei   #no_spr,r18
                jump    eq,(r18)
                nop
                movei   #160,r5
sd_loop:
                subqt   #4,r3
                load    (r3),r2                 ; OAM entry
                load    (r2),r17                ; y x tile attr
                move    r17,r8
                shlq    #8,r8
                shrq    #24,r8                  ; x
                movei   #168,r12
                cmp     r12,r8
                movei   #sd_end,r12
                jump    cc,(r12)                ; x >= 168: off screen
                nop
                move    r17,r7
                shrq    #24,r7                  ; y
                move    r17,r16
                shlq    #16,r16
                shrq    #24,r16                 ; tile
                shlq    #24,r17
                shrq    #24,r17                 ; attr
                move    r0,r9
                addq    #16,r9
                sub     r7,r9                   ; row
                btst    #6,r17
                jr      eq,sd_nv
                nop
                move    r15,r12
                subq    #1,r12
                sub     r9,r12
                move    r12,r9
sd_nv:          cmpq    #8,r15
                jr      eq,sd_8
                nop
                bclr    #0,r16
sd_8:           shlq    #4,r16
                shlq    #1,r9
                add     r9,r16
                btst    #3,r17
                jr      eq,sd_b0
                nop
                movei   #$2000,r12
                add     r12,r16
sd_b0:          add     r23,r16
                loadw   (r16),r11               ; chunky row
                cmpq    #0,r11
                movei   #sd_end,r12
                jump    eq,(r12)                ; transparent row
                nop
                ; palette
                move    r17,r6
                moveq   #7,r7
                and     r7,r6
                shlq    #4,r6
                movei   #OBC,r14
                add     r6,r14
                subq    #8,r8                   ; screen x
                ; hflip: walk the bits from the other end
                moveq   #14,r10                 ; shift for pixel 0
                moveq   #2,r9                   ; shift step (subtracted)
                btst    #5,r17
                jr      eq,sd_nh
                nop
                moveq   #0,r10
                moveq   #0,r9
                subq    #2,r9                   ; -2
sd_nh:
                ; fast path: the 8 pixels on screen and left of the window
                movei   #sd_slow,r16
                movei   #153,r12
                cmp     r12,r8                  ; x - 153
                jump    cc,(r16)                ; (x < 0 is huge unsigned too)
                nop
                move    r8,r12
                addq    #8,r12
                cmp     r12,r13                 ; window start - (x + 8)
                jump    cs,(r16)
                nop
                ; r2 = BG in front of each pixel: bits 30, 28 ... 16 (pixel 0 first)
                moveq   #0,r2
                btst    #0,r1                   ; LCDC.0: BG/window master priority
                movei   #sf_nb,r12
                jump    eq,(r12)
                nop
                movefa  r2,r6                   ; fine scroll
                add     r8,r6                   ; BG pixel p of screen x
                move    r6,r12
                shrq    #3,r12
                shlq    #2,r12
                movei   #TIB,r16
                add     r12,r16
                load    (r16),r2                ; tile p/8: row | priority << 16
                addqt   #4,r16
                load    (r16),r12               ; next tile
                moveq   #7,r16
                and     r16,r6
                shlq    #1,r6
                neg     r6                      ; left shift by 2*(p & 7)
                move    r2,r15
                shrq    #16,r15
                neg     r15
                shlq    #16,r15                 ; priority of tile p/8 -> high word
                move    r12,r16
                shrq    #16,r16
                neg     r16
                shrq    #16,r16                 ; priority of the next tile -> low word
                or      r16,r15
                btst    #7,r17
                jr      eq,sf_np
                nop
                moveq   #0,r15
                not     r15                     ; OBJ behind BG colours 1-3
sf_np:          shlq    #16,r2
                and     r28,r12
                or      r12,r2                  ; the 16 BG pixels from p & ~7
                sh      r6,r2
                sh      r6,r15
                move    r2,r12
                shrq    #1,r12
                or      r12,r2                  ; BG colour != 0 (even bits)
                and     r15,r2
sf_nb:          move    r8,r16
                addq    #8,r16
                shrq    #1,r16
                shlq    #2,r16
                add     r26,r16                 ; long of pixel x
                moveq   #8,r7
                movei   #sf_sk,r30
                movei   #sf_px,r18
sf_px:          move    r11,r6
                sh      r10,r6
                moveq   #3,r12
                and     r12,r6                  ; colour number
                jump    eq,(r30)
                nop
                btst    #30,r2
                jump    ne,(r30)                ; BG in front
                shlq    #2,r6
                load    (r14+r6),r12            ; colour
                load    (r16),r17
                btst    #0,r8
                jr      ne,sf_lo
                nop
                shlq    #16,r12
                jr      t,sf_st
                and     r28,r17
sf_lo:          shrq    #16,r17
                shlq    #16,r17
sf_st:          or      r12,r17
                store   r17,(r16)
sf_sk:          btst    #0,r8
                jr      eq,sf_ev
                addq    #1,r8
                addqt   #4,r16                  ; (odd pixel done: next long)
sf_ev:          sub     r9,r10
                shlq    #2,r2
                subq    #1,r7
                jump    ne,(r18)
                nop
                moveq   #8,r15                  ; (height again)
                btst    #2,r1
                jr      eq,sf_h8
                nop
                moveq   #16,r15
sf_h8:          movei   #sd_end,r12
                jump    t,(r12)
                nop
sd_slow:        moveq   #8,r7                   ; pixels
                movei   #sd_skip,r30
                movei   #sd_px,r18
sd_px:
                move    r11,r6
                sh      r10,r6                  ; shift right by r10
                moveq   #3,r12
                and     r12,r6                  ; colour number
                jump    eq,(r30)
                nop
                cmp     r5,r8                   ; x - 160
                jump    cc,(r30)                ; off screen (x < 0 or x >= 160)
                nop
                btst    #0,r1                   ; LCDC.0: BG/window master priority
                movei   #sd_put,r12
                jump    eq,(r12)
                nop
                ; BG colour and tile priority at x
                move    r8,r16
                cmp     r13,r8                  ; x - window start
                jr      cc,sd_w
                nop
                movefa  r2,r2                   ; fine scroll
                add     r2,r16
                movei   #TIB,r2
                jr      t,sd_i
                nop
sd_w:           sub     r13,r16
                movei   #TIW,r2
sd_i:           move    r16,r12
                shrq    #3,r12
                shlq    #2,r12
                add     r12,r2
                load    (r2),r2                 ; tile row | priority << 16
                moveq   #7,r12
                and     r12,r16
                shlq    #1,r16
                moveq   #14,r12
                sub     r16,r12
                move    r2,r16
                sh      r12,r16
                moveq   #3,r12
                and     r12,r16                 ; BG colour number
                movei   #sd_put,r12
                jump    eq,(r12)                ; colour 0: sprite in front
                nop
                btst    #7,r17
                jump    ne,(r30)                ; OBJ behind BG colours 1-3
                nop
                btst    #16,r2
                jump    ne,(r30)                ; BG tile priority
                nop
sd_put:         shlq    #2,r6
                load    (r14+r6),r12            ; colour
                move    r8,r16
                addq    #8,r16
                shrq    #1,r16
                shlq    #2,r16
                add     r26,r16                 ; long of pixel x
                load    (r16),r2
                btst    #0,r8
                jr      ne,sd_lo
                nop
                shlq    #16,r12
                and     r28,r2
                jr      t,sd_st
                nop
sd_lo:          shrq    #16,r2
                shlq    #16,r2
sd_st:          or      r12,r2
                store   r2,(r16)
sd_skip:        sub     r9,r10
                addq    #1,r8
                subq    #1,r7
                jump    ne,(r18)
                nop
sd_end:
                subq    #1,r4
                movei   #sd_loop,r18
                jump    ne,(r18)
                nop
no_spr:
                ; ---- output the line: fb + L*320
                move    r0,r2
                movei   #320,r3
                mult    r3,r2
                add     r24,r2
                move    r26,r14
                addq    #16,r14                 ; screen x 0
                moveq   #20,r4
                addq    #20,r4                  ; 40 phrases
                movei   #G_HIDATA,r10
                movei   #ol_l,r11
ol_l:           load    (r14),r5
                load    (r14+1),r6
                addqt   #8,r14
                store   r5,(r10)
                storep  r6,(r2)
                subq    #1,r4
                jump    ne,(r11)
                addqt   #8,r2
                movei   #G_LINES,r4
                load    (r4),r5
                addq    #1,r5
                store   r5,(r4)
                jump    t,(r19)
                nop

; ---------------------------------------------------------------------------
; tile loops: r5 first column, r10 tiles, r9 decoded map cache, r11/r12 row
; offset (normal/vflip), r14 destination long of pixel 0, r4 tile info
; (for the sprites) ; continue at r13
; tl_even: pixel 0 at the high word ; tl_odd: pixel 0 at the low word
; ---------------------------------------------------------------------------
tl_even:
                moveq   #15,r17
                shlq    #2,r17                  ; 60
                movei   #$1c0,r30
                movei   #PT,r0
                movei   #te_hr,r1
                movei   #t_hflip,r8
                movei   #te_l,r18
te_l:           load    (r9),r16                ; decoded column
                addqt   #4,r9
                move    r16,r2
                and     r28,r2
                add     r23,r2
                btst    #22,r16                 ; vflip
                jr      eq,te_nv
                move    r11,r6
                move    r12,r6
te_nv:          add     r6,r2
                loadw   (r2),r3                 ; chunky row
                move    r16,r15
                shrq    #10,r15
                and     r30,r15
                add     r0,r15                  ; pair table
                btst    #21,r16                 ; hflip
                jump    ne,(r8)
                nop
te_hr:          move    r16,r6
                shrq    #23,r6
                shlq    #16,r6
                or      r3,r6
                store   r6,(r4)
                addqt   #4,r4
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
                move    r3,r6
                shlq    #28,r6
                shrq    #26,r6
                load    (r15+r6),r7
                store   r7,(r14+3)
                addqt   #16,r14
                subq    #1,r10
                jump    ne,(r18)
                nop
                jump    t,(r13)
                nop

tl_odd:
                moveq   #15,r17
                shlq    #2,r17                  ; 60
                movei   #$1c0,r30
                movei   #PT,r0
                movei   #to_hr,r1
                movei   #t_hflip,r8
                movei   #to_l,r18
to_l:           load    (r9),r16                ; decoded column
                addqt   #4,r9
                move    r16,r2
                and     r28,r2
                add     r23,r2
                btst    #22,r16                 ; vflip
                jr      eq,to_nv
                move    r11,r6
                move    r12,r6
to_nv:          add     r6,r2
                loadw   (r2),r3                 ; chunky row
                move    r16,r15
                shrq    #10,r15
                and     r30,r15
                add     r0,r15                  ; pair table
                btst    #21,r16                 ; hflip
                jump    ne,(r8)
                nop
to_hr:          move    r16,r6
                shrq    #23,r6
                shlq    #16,r6
                or      r3,r6
                store   r6,(r4)
                addqt   #4,r4
                move    r3,r6                   ; pixel 0: low word
                shrq    #14,r6
                shlq    #2,r6
                load    (r15+r6),r7
                and     r28,r7
                load    (r14),r2
                shrq    #16,r2
                shlq    #16,r2
                or      r7,r2
                store   r2,(r14)
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
                move    r3,r6                   ; pixel 7: high word of the next long
                shlq    #30,r6
                shrq    #26,r6
                load    (r15+r6),r7
                shrq    #16,r7
                shlq    #16,r7
                store   r7,(r14+4)
                addqt   #16,r14
                subq    #1,r10
                jump    ne,(r18)
                nop
                jump    t,(r13)
                nop

; reverse the 8 pixels of the chunky row r3, return via r1
t_hflip:
                movefa  r1,r7                   ; $3333
                move    r3,r6
                shrq    #2,r6
                and     r7,r6
                and     r7,r3
                shlq    #2,r3
                or      r6,r3
                movefa  r0,r7                   ; $0f0f
                move    r3,r6
                shrq    #4,r6
                and     r7,r6
                and     r7,r3
                shlq    #4,r3
                or      r6,r3
                move    r3,r6
                shrq    #8,r6
                shlq    #24,r3
                shrq    #16,r3
                or      r6,r3
                jump    t,(r1)
                nop

                .long
jtab:           dc.l    h_vram,h_vram,h_reg,main,main,h_oam,h_block,h_oamall,h_line,h_frame,h_wrap,h_col,h_col,main,h_grad3,h_scroll,h_roadln
gpu_end_addr::
                .68000
                .phrase
gpu_code_end::
