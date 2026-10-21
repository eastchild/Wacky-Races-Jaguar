; ---------------------------------------------------------------------------
; Road service of the DSP (included by dsp.s after the sound code): the fast loop of the race road
; renderer 0:32AE (hle.s road_fast, DSPROAD), run by the DSP's main code (register bank 1)
; between its I2S interrupts. On the console the 68000 pays ~16 cycles per bus access; the
; DSP runs from its local RAM and reaches main RAM much faster.
;
; The 68k fills RDP (long writes), sets RD_GO = 1 and waits for RD_GO = 0. RD_STAT = 1: the
; log needs room (the 68k calls log_slow, publishes, sets RD_LOG and RD_GO = 2, the DSP goes
; on); RD_STAT = 2: done (RD_LOG, RD_RHS, RD_RHD, RD_GL, RD_PAL hold the results). Same log
; and same final GB state as the 68k loop; the HRAM bytes, SCY/SCX and the consumed line
; table C600-C645 are written once at the end (only the final state matters).
;
; DSP write bug: an external store must follow a completed external load (XW before each).
;
; Registers (bank 1): r4 A5, r5 log, r6 VRAM copy base, r7 WRAMX base, r8 ROMX base of the
; object, r9 palette table, r10 palette ROM base, r11 flags, r12 grad_last, r13 rh_src,
; r14 rh_dst, r15 n, r16 DMA blocks, r17-r20 FF8B FF8C FF8D FF8A, r21 object entry, r22
; object data, r23 log at the chunk start, r24 SCY << 8 | SCX (bit 16: a road row), r25
; palette of the last road row, r26 last command (0 road row, 1 sky), r27 / r28 returns,
; r0-r3 r29-r31 temporary.
; ---------------------------------------------------------------------------
                .macro  GBA r                   ; r := 68k address of the GB address r
                shlq    #16,\r
                sharq   #16,\r
                add     r4,\r
                .endm
                .macro  XW                      ; external read before an external store
                load    (r4),r29
                or      r29,r29
                .endm

rd_start:
                movei   #RDP,r0
                load    (r0),r4                 ; A5
                addqt   #4,r0
                load    (r0),r5                 ; log
                addqt   #4,r0
                load    (r0),r6                 ; VRAM copy
                addqt   #4,r0
                load    (r0),r7                 ; WRAMX
                addqt   #4,r0
                load    (r0),r9                 ; palette table
                addqt   #4,r0
                load    (r0),r10                ; palette ROM base
                addqt   #4,r0
                load    (r0),r11                ; flags
                addqt   #4,r0
                load    (r0),r12                ; grad_last
                addqt   #4,r0
                load    (r0),r13                ; rh_src
                addqt   #4,r0
                load    (r0),r14                ; rh_dst
                addqt   #4,r0
                load    (r0),r20                ; FF8A FF8B FF8C FF8D
                move    r20,r19
                move    r20,r18
                move    r20,r17
                shlq    #24,r19
                shlq    #16,r18
                shlq    #8,r17
                shrq    #24,r19                 ; FF8D
                shrq    #24,r18                 ; FF8C
                shrq    #24,r17                 ; FF8B
                shrq    #24,r20                 ; FF8A
                move    r5,r23
                moveq   #0,r15
                moveq   #0,r16
                moveq   #0,r24
                moveq   #0,r25
                moveq   #0,r26
                btst    #0,r11
                jr      eq,rs_1
                nop
                movei   #(LC_LINE<<24)|73,r0    ; line 73: drawn before the first change
                XW
                store   r0,(r5)
                addqt   #4,r5
rs_1:           movei   #rl_line,r27            ; the object going on from the last frame
                movei   #rd_obj_d,r30
                jump    t,(r30)
                nop

; ---- line n
rl_line:        move    r5,r0                   ; RDROOM bytes of log since the chunk start:
                sub     r23,r0                  ; the 68k makes room
                movei   #RDROOM,r1
                cmp     r1,r0
                jr      cs,rl_b
                nop
                movei   #rl_b,r28
                movei   #rd_yield,r30
                jump    t,(r30)
                nop
rl_b:           btst    #0,r15
                movei   #rl_odd,r30
                jump    ne,(r30)
                nop
                ; even line: object descriptor C655 + n/2
                move    r15,r0
                shrq    #1,r0
                movei   #$c655,r1
                add     r1,r0
                GBA     r0
                loadb   (r0),r1
                btst    #7,r1
                movei   #rl_new,r30
                jump    ne,(r30)
                nop
                move    r22,r0                  ; same object: y, x at this offset of its data
                add     r1,r0
                loadb   (r0),r17
                addqt   #1,r0
                loadb   (r0),r18
                movei   #rl_row,r30
                jump    t,(r30)
                nop
rl_new:         move    r1,r20                  ; FF8A
                movei   #rn_1,r27               ; (the blocks of the object before)
                movei   #rd_flush_d,r30
                jump    t,(r30)
                nop
rn_1:           movei   #rn_2,r27
                movei   #rd_obj_d,r30
                jump    t,(r30)
                nop
rn_2:           loadb   (r22),r0                ; its data: DMA source (HDMA1-2), y, x
                move    r22,r1
                addqt   #1,r1
                loadb   (r1),r2
                movei   #$ff51,r3
                GBA     r3
                XW
                storeb  r2,(r3)
                addqt   #1,r3
                XW
                storeb  r0,(r3)
                shlq    #8,r2
                or      r2,r0
                movei   #$fff0,r2
                and     r2,r0
                move    r0,r13
                addqt   #1,r1
                loadb   (r1),r17
                addqt   #1,r1
                loadb   (r1),r18
                movei   #rl_row,r30
                jump    t,(r30)
                nop
rl_odd:         move    r21,r0                  ; odd line: OAM buffer entry C000 + 4*(n/2)
                subq    #1,r0
                loadb   (r0),r1
                subq    #1,r0
                loadb   (r0),r2
                subq    #1,r0
                loadb   (r0),r3
                add     r17,r1                  ; y
                add     r18,r2                  ; x
                movei   #$ff,r0
                and     r0,r1
                and     r0,r2
                shlq    #24,r1
                shlq    #16,r2
                or      r2,r1
                move    r19,r2
                shlq    #8,r2
                or      r2,r1                   ; tile (FF8D)
                or      r3,r1                   ; attributes
                move    r15,r0
                shrq    #1,r0
                shlq    #2,r0
                movei   #$c000,r2
                add     r2,r0
                GBA     r0
                XW
                store   r1,(r0)
                addq    #2,r19
                movei   #$ff,r0
                and     r0,r19
rl_row:         movei   #$c600,r0               ; C6[n] = road row + 1 (0 = sky)
                add     r15,r0
                GBA     r0
                loadb   (r0),r1
                cmpq    #0,r1
                movei   #rl_sky,r30
                jump    eq,(r30)
                nop
                subq    #1,r1                   ; row
                movei   #$3e,r2
                add     r1,r2
                sub     r15,r2
                movei   #$ff,r0
                and     r0,r2                   ; SCY = row + $3E - n
                movei   #$c700,r0
                add     r1,r0
                GBA     r0
                loadb   (r0),r3                 ; SCX = C700[row]
                move    r2,r24
                shlq    #8,r24
                or      r3,r24
                bset    #16,r24
                btst    #0,r11
                movei   #rl_next,r30
                jump    eq,(r30)                ; undrawn: no command
                nop
                movei   #(LC_ROADLN|LF_LINE)<<24,r0 ; line 74+n with them and BG palette 0
                shlq    #16,r2
                or      r2,r0
                shlq    #8,r3
                or      r3,r0
                XW
                store   r0,(r5)
                addqt   #4,r5
                move    r1,r0                   ; GB address of the 8 palette bytes
                add     r1,r0
                add     r9,r0
                loadb   (r0),r2
                addqt   #1,r0
                loadb   (r0),r3
                shlq    #8,r3
                or      r3,r2
                movei   #$4000,r3
                cmp     r3,r2
                jr      cc,rl_ph
                nop
                jr      t,rl_pa
                add     r4,r2                   ; (< $4000: flat)
rl_ph:          shlq    #16,r2
                sharq   #16,r2
                add     r10,r2
rl_pa:          XW
                store   r2,(r5)
                addqt   #4,r5
                move    r2,r25
                movei   #rl_next,r30
                jump    t,(r30)
                moveq   #0,r26
rl_sky:         btst    #0,r11                  ; sky: colour C4[(C47F) + $48 + 2*(n/2)]
                movei   #rl_next,r30
                jump    eq,(r30)
                nop
                move    r15,r0
                bclr    #0,r0
                movei   #$48,r1
                add     r1,r0
                movei   #$c47f,r1
                GBA     r1
                loadb   (r1),r1
                add     r1,r0
                movei   #$ff,r1
                and     r1,r0
                movei   #$c400,r1
                add     r1,r0
                GBA     r0
                loadb   (r0),r2
                addqt   #1,r0
                loadb   (r0),r3
                shlq    #8,r3
                or      r3,r2
                movei   #$70000,r0
                or      r0,r2                   ; mask << 16 | colour
                cmp     r12,r2
                jr      eq,rl_nop
                nop
                move    r2,r12
                movei   #(LC_GRAD3|LF_LINE)<<24,r0
                or      r0,r2
                XW
                store   r2,(r5)
                jr      t,rl_sk2
                addqt   #4,r5
rl_nop:         movei   #(LC_NOP|LF_LINE)<<24,r0
                XW
                store   r0,(r5)
                addqt   #4,r5
rl_sk2:         moveq   #1,r26
rl_next:        addq    #1,r16                  ; one more DMA block
                addq    #1,r15
                movei   #70,r0
                cmp     r0,r15
                movei   #rl_line,r30
                jump    ne,(r30)
                nop
                ; ---- end: the last line is not rendered from here (its command loses
                ; LF_LINE), the blocks left, the line table cleared, the final state
                btst    #0,r11
                jr      eq,re_1
                nop
                move    r5,r0
                subq    #8,r0
                cmpq    #0,r26
                jr      eq,re_0
                nop
                addq    #4,r0
re_0:           load    (r0),r1
                bclr    #31,r1
                XW
                store   r1,(r0)
re_1:           movei   #re_2,r27
                movei   #rd_flush_d,r30
                jump    t,(r30)
                nop
re_2:           movei   #$c600,r0               ; C600-C645 := 0
                GBA     r0
                moveq   #17,r1
                moveq   #0,r2
re_c:           XW
                store   r2,(r0)
                subq    #1,r1
                jr      ne,re_c
                addqt   #4,r0
                XW
                storew  r2,(r0)
                movei   #$ff8a,r0               ; FF8A-FF8D
                GBA     r0
                XW
                storeb  r20,(r0)
                addqt   #1,r0
                XW
                storeb  r17,(r0)
                addqt   #1,r0
                XW
                storeb  r18,(r0)
                addqt   #1,r0
                XW
                storeb  r19,(r0)
                btst    #16,r24                 ; SCY / SCX of the last road row
                movei   #re_3,r30
                jump    eq,(r30)
                nop
                movei   #$ff42,r0
                GBA     r0
                move    r24,r1
                shrq    #8,r1
                XW
                storeb  r1,(r0)
                addqt   #1,r0
                XW
                storeb  r24,(r0)
re_3:           movei   #RD_LOG,r0
                store   r5,(r0)
                movei   #RD_RHS,r0
                store   r13,(r0)
                addqt   #4,r0
                store   r14,(r0)
                movei   #RD_GL,r0
                store   r12,(r0)
                movei   #RD_PAL,r0
                store   r25,(r0)
                movei   #RD_STAT,r0
                moveq   #2,r1
                store   r1,(r0)
                movei   #RD_GO,r0
                moveq   #0,r1
                store   r1,(r0)
                movei   #dsp_idle,r30
                jump    t,(r30)
                nop

; ---- the 68k makes room in the log: wait for RD_GO = 2 ; return r28 ; uses r0 r29
rd_yield:       movei   #RD_LOG,r29
                store   r5,(r29)
                movei   #RD_STAT,r29
                moveq   #1,r0
                store   r0,(r29)
                movei   #RD_GO,r29
                moveq   #0,r0
                store   r0,(r29)
ry_w:           load    (r29),r0
                cmpq    #0,r0
                jr      eq,ry_w
                nop
                movei   #RD_LOG,r29
                load    (r29),r5
                move    r5,r23
                jump    t,(r28)
                nop

; ---- object FF8A (r20): r21 := its entry C600 + FF8A, r8 := its ROMX base, r22 := its
; data ; return r27 ; uses r0-r3 r28 r29
rd_obj_d:       movei   #$c600,r21
                add     r20,r21
                GBA     r21
                loadb   (r21),r0                ; bank
                movei   #$3f,r1
                and     r1,r0
                shlq    #2,r0
                movei   #bank_base,r1
                add     r1,r0
                load    (r0),r8
                move    r21,r0
                addqt   #1,r0
                loadb   (r0),r1
                addqt   #1,r0
                loadb   (r0),r2
                shlq    #8,r2
                or      r2,r1                   ; GB address of the data
                movei   #ro_1,r28
                movei   #rd_ptr_d,r30
                jump    t,(r30)
                move    r1,r0
ro_1:           jump    t,(r27)
                move    r0,r22

; ---- r0 := 68k address of the GB address r0 (ROMX: r8 ; VRAM: r6 ; WRAMX: r7) ; return
; r28 ; uses r3 r29
rd_ptr_d:       move    r0,r3
                shrq    #12,r3
                shlq    #2,r3
                movei   #rp_tab,r29
                add     r29,r3
                load    (r3),r3
                jump    t,(r3)
                nop
rp_f:           GBA     r0
                jump    t,(r28)
                nop
rp_x:           jump    t,(r28)
                add     r8,r0
rp_v:           shlq    #16,r0
                sharq   #16,r0
                jump    t,(r28)
                add     r6,r0
rp_w:           shlq    #16,r0
                sharq   #16,r0
                jump    t,(r28)
                add     r7,r0
                .long
rp_tab:         dc.l    rp_f,rp_f,rp_f,rp_f,rp_x,rp_x,rp_x,rp_x
                dc.l    rp_v,rp_v,rp_f,rp_f,rp_f,rp_w,rp_f,rp_f

; ---- the r16 HBlank DMA blocks done since the last call: rh_src -> rh_dst (VRAM bank),
; counters advanced, r16 := 0 ; return r27 ; uses r0-r3 r28-r31
rd_flush_d:     cmpq    #0,r16
                movei   #rf_x,r30
                jump    eq,(r30)
                nop
                btst    #1,r11
                movei   #rf_adv,r30
                jump    eq,(r30)                ; (tiles not needed by the next frame)
                nop
                .if     ^^defined RDRAM
                moveq   #0,r0                   ; (test build: every source by the RAM path)
                .else
                movei   #$8000,r0
                .endif
                cmp     r0,r13
                movei   #rf_ram,r30
                jump    cc,(r30)
                nop
                movei   #rf_1,r28               ; from the ROM: one command, the GPU reads it
                movei   #rd_ptr_d,r30
                jump    t,(r30)
                move    r13,r0
rf_1:           move    r16,r1
                subq    #1,r1
                add     r1,r1
                move    r11,r2
                shrq    #8,r2
                or      r2,r1                   ; (blocks - 1) << 1 | VRAM bank
                shlq    #16,r1
                or      r14,r1
                movei   #LC_BLKP<<24,r2
                or      r2,r1
                XW
                store   r1,(r5)
                addqt   #4,r5
                XW
                store   r0,(r5)
                movei   #rf_adv,r30
                jump    t,(r30)
                addqt   #4,r5
rf_ram:         move    r16,r31                 ; from RAM: the data itself, block by block
                move    r13,r1                  ;  (into the 68k's VRAM copy and the log)
                move    r14,r2
rr_l:           move    r5,r0
                sub     r23,r0
                movei   #RDROOM,r3
                cmp     r3,r0
                jr      cs,rr_b
                nop
                movei   #rr_b,r28
                movei   #rd_yield,r30
                jump    t,(r30)
                nop
rr_b:           movei   #rr_1,r28
                movei   #rd_ptr_d,r30
                jump    t,(r30)
                move    r1,r0
rr_1:           move    r11,r3
                shrq    #8,r3
                shlq    #16,r3
                or      r2,r3
                movei   #LC_BLOCK<<24,r29
                or      r29,r3
                XW
                store   r3,(r5)
                addqt   #4,r5
                moveq   #16,r3
                XW
                store   r3,(r5)
                addqt   #4,r5
                move    r2,r3
                shlq    #16,r3
                sharq   #16,r3
                add     r6,r3                   ; VRAM copy
                load    (r0),r29                ; (each load also clears the DSP write bug)
                or      r29,r29
                store   r29,(r3)
                load    (r0),r29
                or      r29,r29
                store   r29,(r5)
                addqt   #4,r0
                addqt   #4,r3
                addqt   #4,r5
                load    (r0),r29
                or      r29,r29
                store   r29,(r3)
                load    (r0),r29
                or      r29,r29
                store   r29,(r5)
                addqt   #4,r0
                addqt   #4,r3
                addqt   #4,r5
                load    (r0),r29
                or      r29,r29
                store   r29,(r3)
                load    (r0),r29
                or      r29,r29
                store   r29,(r5)
                addqt   #4,r0
                addqt   #4,r3
                addqt   #4,r5
                load    (r0),r29
                or      r29,r29
                store   r29,(r3)
                load    (r0),r29
                or      r29,r29
                store   r29,(r5)
                addqt   #4,r5
                movei   #16,r3
                add     r3,r1                   ; next source
                add     r3,r2
                movei   #$1ff0,r3
                and     r3,r2
                bset    #15,r2                  ; next destination
                subq    #1,r31
                movei   #rr_l,r30
                jump    ne,(r30)
                nop
rf_adv:         move    r16,r0                  ; rh_src += 16 * blocks, rh_dst too (in VRAM)
                shlq    #4,r0
                add     r0,r13
                movei   #$ffff,r1
                and     r1,r13
                add     r0,r14
                movei   #$1ff0,r1
                and     r1,r14
                bset    #15,r14
                moveq   #0,r16
rf_x:           jump    t,(r27)
                nop
