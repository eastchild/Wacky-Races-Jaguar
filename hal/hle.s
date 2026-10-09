; ---------------------------------------------------------------------------
; Native (HLE) versions of hot GB raster routines.
; STAT handlers are dispatched here by irq_req before any GB code runs: same
; side effects as the GB handler (palettes, BCPS/OCPS, C1A5 chain pointer, IME).
; Register use: d6, d7, a0, a1 only (like any HAL routine).
; ---------------------------------------------------------------------------


; ---- colour helpers (per-line raster state: not output in undrawn frames) ----
hle_skip:       rts
; register d6.w := d7.b (logged only in drawn frames)
hle_reg::
                tst.b   rnd.w
                bne     log_reg
                move.b  d7,(a5,d6.w)
                rts
; BG colour d6.b (0-31) := d7.w (GB colour). Keeps d7.
bg_col::
                tst.b   rnd.w
                beq     hle_skip
                st      grad_last.w
                move.b  #LC_BGCOL,(a6)+
                move.b  d6,(a6)+
                move.w  d7,(a6)+
                andi.w  #$1f,d6
                add.w   d6,d6
                lea     bgpal_raw.w,a0
                move.b  d7,(a0,d6.w)
                ror.w   #8,d7
                move.b  d7,1(a0,d6.w)
                ror.w   #8,d7
                cmpa.l  log_limit.w,a6
                bcc     log_slow
                rts
; OBJ palette byte d6.b (0-63) := d7.b
ob_byte::
                tst.b   rnd.w
                beq     hle_skip
                andi.w  #$3f,d6
                lea     obpal_raw.w,a0
                move.b  d7,(a0,d6.w)
                move.b  #LC_OBCOL,(a6)+         ; (the whole colour)
                move.w  d6,d7
                lsr.w   #1,d7
                move.b  d7,(a6)+
                add.w   d7,d7
                move.b  1(a0,d7.w),(a6)+
                move.b  (a0,d7.w),(a6)+
                cmpa.l  log_limit.w,a6
                bcc     log_slow
                rts
; OBJ colour d6.b (0-31) := d7.w
ob_col::
                tst.b   rnd.w
                beq     hle_skip
                move.b  #LC_OBCOL,(a6)+
                move.b  d6,(a6)+
                move.w  d7,(a6)+
                andi.w  #$1f,d6
                add.w   d6,d6
                lea     obpal_raw.w,a0
                move.b  d7,(a0,d6.w)
                ror.w   #8,d7
                move.b  d7,1(a0,d6.w)
                ror.w   #8,d7
                cmpa.l  log_limit.w,a6
                bcc     log_slow
                rts
; whole palette d6.b (0-7 BG, 8-15 OBJ) := 8 bytes at a0 (any alignment)
pal4::
                tst.b   rnd.w
                beq     hle_skip
; (palette state, not a per-line raster effect: also in undrawn frames)
pal4_all::
                st      grad_last.w
                andi.w  #15,d6
                move.w  d6,d7
                lsl.w   #3,d7
                lea     bgpal_raw.w,a1          ; (obpal_raw follows)
                adda.w  d7,a1
                moveq   #7,d7
.c:             move.b  (a0)+,(a1)+
                dbra    d7,.c
                subq.l  #8,a1
                moveq   #LC_BGCOL,d7            ; 4 whole colours
                bclr    #3,d6
                beq.s   .bg
                moveq   #LC_OBCOL,d7
.bg:            lsl.b   #2,d6                   ; colour index of colour 0
                move.b  d7,(a6)+
                move.b  d6,(a6)+
                move.b  1(a1),(a6)+
                move.b  (a1),(a6)+
                addq.b  #1,d6
                move.b  d7,(a6)+
                move.b  d6,(a6)+
                move.b  3(a1),(a6)+
                move.b  2(a1),(a6)+
                addq.b  #1,d6
                move.b  d7,(a6)+
                move.b  d6,(a6)+
                move.b  5(a1),(a6)+
                move.b  4(a1),(a6)+
                addq.b  #1,d6
                move.b  d7,(a6)+
                move.b  d6,(a6)+
                move.b  7(a1),(a6)+
                move.b  6(a1),(a6)+
                cmpa.l  log_limit.w,a6
                bcc     log_slow
                rts
; colour 0 of BG palettes 0-2 := d7.w, BCPS := $92
grad3::
                moveq   #7,d6
                bsr.s   grad_m
                move.b  #$92,R_BCPS(a5)
                rts
; colour 0 of the BG palettes in mask d6.b := d7.w (skipped when the GPU already has it)
grad_m::
                tst.b   rnd.w
                beq.s   .gx
                swap    d7
                move.b  d6,d7
                swap    d7
                andi.l  #$00ffffff,d7
                cmp.l   grad_last.w,d7
                beq.s   .gx
                move.l  d7,grad_last.w
                move.b  #LC_GRAD3,(a6)+
                move.b  d6,(a6)+
                move.w  d7,(a6)+                ; (bgpal_raw not kept: per-line raster state)
                cmpa.l  log_limit.w,a6
                bcc     log_slow
.gx:            rts
; d7.w := little-endian word at a0
rdw_a0::
                move.b  1(a0),d7
                lsl.w   #8,d7
                move.b  (a0),d7
                rts

; ---- STAT dispatch ----------------------------------------------------------
; d7.w = GB handler address (C1A5). Z=1: handled natively (IME set as the GB
; handler's return would), Z=0: not a native handler.
stat_native::
                cmp.w   #$1aac,d7
                beq     hle_1aac
                cmp.w   #$1b13,d7
                beq     hle_1b13
                cmp.w   #$1b4d,d7
                beq     hle_1b4d
                cmp.w   #$1a73,d7
                beq     hle_1a73
                cmp.w   #$1bec,d7
                bcs.s   .no
                cmp.w   #$2559,d7
                bcc.s   .no
                ; race chain: expected entry first
                movea.l sc_ptr.w,a0
                cmp.w   (a0),d7
                beq.s   .hit
                lea     sc_tab,a0
.f:             cmp.w   (a0),d7
                beq.s   .hit
                addq.l  #8,a0
                cmpa.l  #sc_end,a0
                bcs.s   .f
.no:            moveq   #1,d7                   ; Z=0
                rts
.hit:           move.b  3(a0),$c1a5+G(a5)       ; C1A5 := next handler
                move.b  2(a0),$c1a6+G(a5)
                st      gb_ime.w                ; reti (sc_last clears it again)
                movea.l a0,a1
                addq.l  #8,a0
                cmpa.l  #sc_end,a0
                bcs.s   .nw
                lea     sc_tab,a0
.nw:            move.l  a0,sc_ptr.w
                move.w  4(a1),d6                ; routine index * 4
                lea     sc_rout,a0
                movea.l (a0,d6.w),a0
                moveq   #0,d7
                move.b  6(a1),d7                ; param
                moveq   #0,d6
                move.b  7(a1),d6                ; param2
                jsr     (a0)
                cmp.b   d7,d7                   ; Z=1
                rts
; ---- 0:1AAC sky gradient (intro, language menu...) --------------------------
hle_1aac::
                moveq   #0,d7
                move.b  $ca90+G(a5),d7
                bclr    #0,d7
                move.b  $c1a0+G(a5),d6
                cmp.b   #$7b,d6
                beq.s   .spec
                cmp.b   #$78,d6
                beq.s   .spec
                cmp.b   #$76,d6
                bne.s   .norm
.spec:          cmp.b   #$68,d7
                bcs.s   .norm
                bne.s   .stop
                move.b  $cae7+G(a5),d7          ; SCX := (CAE7)
                move.w  #$ff43,d6
                bsr     hle_reg
                bra.s   .next
.stop:          clr.b   $ca90+G(a5)             ; plain RET: IME stays off
                sf      gb_ime.w
                cmp.b   d7,d7
                rts
.norm:          lea     $ca00+G(a5),a0
                adda.w  d7,a0
                bsr     rdw_a0
                move.b  $c1a0+G(a5),d6
                cmp.b   #$76,d6
                beq.s   .two
                cmp.b   #$7b,d6
                beq.s   .two
                cmp.b   #$78,d6
                beq.s   .two
                moveq   #$47,d6                 ; palettes 0, 1, 2, 6
                bsr     grad_m
                move.b  #$b2,R_BCPS(a5)
                bra.s   .next
.two:           moveq   #3,d6                   ; palettes 0, 1
                bsr     grad_m
                move.b  #$8a,R_BCPS(a5)
.next:          addq.b  #1,$ca90+G(a5)
                cmpi.b  #$90,$ca90+G(a5)
                bne.s   .r
                clr.b   $ca90+G(a5)
.r:             st      gb_ime.w
                cmp.b   d7,d7
                rts

; ---- 0:30BC / 0:30FF (race, every frame): (DE) := (HL) + (BC) / (HL) - (BC), BC HL E += 1,
; ten at a time until E = $78 (A = $78, Z set). Fast path: BC in WRAMX, HL in ROMX, DE in WRAM0.
hle_30bc::
                moveq   #0,d7
                bra.s   hle_30x
hle_30ff::
                moveq   #1,d7
hle_30x:        movem.l d4-d5/a2,-(a7)
                move.b  d7,d4                   ; subtract
                moveq   #$78,d5
                sub.b   d2,d5
                andi.w  #$ff,d5                 ; count (0: 256)
                bne.s   .n
                move.w  #256,d5
.n:             subq.w  #1,d5
                cmp.w   #$d000,d1
                bcs.s   .slow
                cmp.w   #$df00,d1
                bcc.s   .slow
                cmp.w   #$4000,d3
                bcs.s   .slow
                cmp.w   #$7f00,d3
                bcc.s   .slow
                cmp.w   #$c000,d2
                bcs.s   .slow
                cmp.w   #$d000,d2
                bcc.s   .slow
                lea     (a3,d1.w),a0            ; BC
                lea     (a4,d3.w),a1            ; HL
                lea     (a5,d2.w),a2            ; DE
                move.w  d5,d7
                addq.w  #1,d7
                add.w   d7,d1
                add.w   d7,d3
                tst.b   d4
                bne.s   .sub
.al:            move.b  (a1)+,d0
                add.b   (a0)+,d0
                move.b  d0,(a2)+
                dbra    d5,.al
                bra.s   .end
.sub:           move.b  (a1)+,d0
                sub.b   (a0)+,d0
                move.b  d0,(a2)+
                dbra    d5,.sub
                bra.s   .end
.slow:          move.w  d3,d6                   ; generic: byte by byte
                jsr     gb_rd
                move.b  d7,d0
                move.w  d1,d6
                jsr     gb_rd
                tst.b   d4
                bne.s   .ss
                add.b   d7,d0
                bra.s   .sw
.ss:            sub.b   d7,d0
.sw:            move.b  d0,d7
                move.w  d2,d6
                jsr     gb_wr
                addq.w  #1,d1
                addq.w  #1,d3
                addq.b  #1,d2
                dbra    d5,.slow
.end:           move.b  #$78,d2
                move.b  #$78,d0
                movem.l (a7)+,d4-d5/a2
                cmp.b   d0,d0                   ; (cp $78: Z, no carry)
                rts

; ---- 23:7A00 (menus, every frame): ld d,$1e / 30 x 4 x (ld a,(hl+) / ld (bc),a / inc c)
; = 120 bytes (HL) -> (B:C), C wrapping in its page; D = 0, Z set, carry kept
hle_23_7a00::
                move    sr,-(a7)
                move.l  d5,-(a7)
                moveq   #119,d5
                cmp.w   #$4000,d3               ; fast path: HL in ROMX, BC in WRAM0
                bcs.s   .slow
                cmp.w   #$7f80,d3
                bcc.s   .slow
                cmp.w   #$c000,d1
                bcs.s   .slow
                cmp.w   #$d000,d1
                bcc.s   .slow
                lea     (a4,d3.w),a0
.cl:            move.b  (a0)+,d0
                move.b  d0,(a5,d1.w)
                addq.b  #1,d1
                dbra    d5,.cl
                add.w   #120,d3
                bra.s   .end
.slow:          move.w  d3,d6
                jsr     gb_rd
                move.b  d7,d0
                addq.w  #1,d3
                move.b  d0,d7
                move.w  d1,d6
                jsr     gb_wr
                addq.b  #1,d1
                dbra    d5,.slow
.end:           andi.w  #$00ff,d2               ; D = 0
                move.l  (a7)+,d5
                move    (a7)+,sr
                ori     #4,ccr                  ; (dec d: Z)
                rts

; ---- 6:43E0 (challenge menu loop): B lines: wait HBlank (0:3E58), BCPS := $80, colour 0
; of BG palette 0 := word (HL+). Exit: B = 0, HL += 2B, A = last byte, BCPS $82, Z, no carry.
; After the first line, when nothing else can happen at a line end (no STAT interrupt taken:
; checked once, nothing changes it in the loop), the HBlanks are inlined as fast_line.
hle_06_43e0::
                move.l  d5,-(a7)
                moveq   #0,d5
                move.w  d1,d5
                lsr.w   #8,d5                   ; B
                bne.s   .n
                move.w  #256,d5
.n:             subq.w  #1,d5
                bsr     hal_wait_hbl
                cmpi.b  #2,v_phase.w            ; the next lines inline? (d5 bit 31)
                bne.s   .col
                move.b  R_STAT(a5),d6
                andi.b  #$78,d6
                beq.s   .ok
                cmp.b   #$08,d6
                bne.s   .col
                tst.b   gb_ime.w                ; HBlank interrupt: only pending
                beq.s   .pd
                tst.b   v_inirq.w
                bne.s   .pd
                btst    #1,R_IE(a5)
                bne.s   .col
.pd:            bset    #1,if_pend.w
.ok:            bset    #31,d5
                bra.s   .col
.lp:            tst.l   d5
                bpl.s   .gen
                cmpi.b  #143,v_ly.w
                bcc.s   .gen
                tst.b   rnd.w
                beq.s   .na
                move.l  #LC_LINE<<24,d6
                move.b  v_ly.w,d6
                move.l  d6,(a6)+
                moveq   #7,d7
                and.b   d6,d7
                bne.s   .na
                PUBLISH d7
.na:            tst.b   hdma_on.w
                beq.s   .nh
                bsr     hdma_step
.nh:            addq.b  #1,v_ly.w
                addq.w  #4,div_cnt.w
                bra.s   .col
.gen:           bsr     hal_wait_hbl
.col:           cmp.w   #$4000,d3               ; colour (HL), HL += 2
                bcs.s   .gr
                cmp.w   #$7ffe,d3
                bcc.s   .gr
                move.b  #LC_BGCOL,(a6)+         ; (ROMX: direct ; always logged, as io_w_bcpd)
                clr.b   (a6)+
                move.b  1(a4,d3.w),(a6)+
                move.b  (a4,d3.w),(a6)+
                addq.w  #2,d3
                bra.s   .gc
.gr:            move.w  d3,d6
                jsr     gb_rd
                move.b  d7,d0
                addq.w  #1,d3
                move.w  d3,d6
                jsr     gb_rd
                addq.w  #1,d3
                move.b  #LC_BGCOL,(a6)+
                clr.b   (a6)+
                move.b  d7,(a6)+
                move.b  d0,(a6)+
.gc:            cmpa.l  log_limit.w,a6
                bcs.s   .nl
                bsr     log_slow
.nl:            dbra    d5,.lp
                lea     bgpal_raw.w,a0          ; GB palette RAM: the last colour
                move.b  -1(a6),(a0)
                move.b  -2(a6),d0               ; A = last byte
                move.b  d0,1(a0)
                st      grad_last.w
                move.b  #$82,R_BCPS(a5)
                andi.w  #$00ff,d1               ; B = 0
                move.l  (a7)+,d5
                move    #4,ccr                  ; (dec b: Z ; carry clear since 3E58)
                rts

; ---- 6:40A8 (challenge menu): wait for STAT mode 1 (VBlank). The GB loop reads STAT until
; it sees the VBlank: the lines up to 144 advance (inlined when possible, as hal_wait_ly91),
; then the read in the VBlank advances one more. Exit: A = 1, Z, no carry.
hle_06_40a8::
                btst    #7,R_LCDC(a5)
                beq.s   .off
.lp:            cmpi.b  #144,v_ly.w
                bcc.s   .vb
                bsr     fast_line
                beq.s   .lp
                bsr     vadvance_line
                bra.s   .lp
.vb:            bsr     vadvance_line
.off:           moveq   #1,d0
                move    #4,ccr
                rts

; ---- 6:4298 / 6:42D2 (challenge menu): 7 rows of 12 map bytes (HL+) at BC (VRAM bank as
; set: tiles, then attributes + E = 8), one row per line (0:3E58 before each), BC += 32.
; Exit: D = 0, A = B, BC / HL advanced, Z, no carry.
hle_06_4298::
                moveq   #0,d0                   ; (value added)
                bra.s   hle_maprows
hle_06_42d2::
                move.b  #8,d2                   ; ld e,8
                moveq   #8,d0
hle_maprows:
                andi.w  #$00ff,d2
                ori.w   #$0700,d2               ; D = 7 rows
.row:           move.b  d0,-(a7)
                bsr     hal_wait_hbl
                move.b  (a7)+,d0
                move.w  d3,d7                   ; source: ROMX / WRAM0 direct, else byte by byte
                cmp.w   #$4000,d7
                bcs.s   .sg
                cmp.w   #$7ff4,d7
                bcs.s   .sx
                cmp.w   #$c000,d7
                bcs.s   .sg
                cmp.w   #$cff4,d7
                bcc.s   .sg
                lea     (a5,d7.w),a0
                bra.s   .sd
.sx:            lea     (a4,d7.w),a0
                bra.s   .sd
.sg:            lea     hl_buf.w,a1             ; (other areas: via gb_rd)
                moveq   #12,d6
                bsr     hl_copy
                subi.w  #12,d3
                lea     hl_buf.w,a0
.sd:            addi.w  #12,d3
                moveq   #11,d6
.by:            move.b  (a0)+,d7
                add.b   d0,d7
                move.b  d7,(a2,d1.w)            ; (as vram_wr: maps)
                move.b  vbk_cur.w,(a6)+
                move.b  d7,(a6)+
                move.w  d1,(a6)+
                addq.b  #1,d1                   ; (inc c)
                dbra    d6,.by
                subq.b  #1,d1
                addi.w  #$15,d1                 ; (BC = (C + 11) + $15 with the carry)
                cmpa.l  log_limit.w,a6
                bcs.s   .nl
                bsr     log_slow
.nl:            subi.w  #$0100,d2
                cmp.w   #$0100,d2
                bcc.s   .row
                move.w  d1,d0
                lsr.w   #8,d0                   ; A = B
                move    #4,ccr
                rts
; ---- 35:61C0 (menus): BG palettes 1-7 := the 56 bytes at word (FF8F) + 9, one palette per
; line (waits for the HBlank as 0:3E58 before each). Exit: A = last byte, C = $69, DE = $0009,
; HL after the data, BCPS = $80, Z, no carry.
hle_35_61c0::
                move.b  #$69,d1
                move.b  $ff90+G(a5),d3
                lsl.w   #8,d3
                move.b  $ff8f+G(a5),d3
                addi.w  #9,d3
                move.w  #$0709,d2
.lp:            bsr     hal_wait_hbl
                lea     hl_buf.w,a1
                moveq   #8,d6
                bsr     hl_copy
                lea     hl_buf.w,a0
                move.w  d2,d6
                lsr.w   #8,d6
                neg.b   d6
                addq.b  #8,d6                   ; palette 8 - D
                bsr     pal4_all
                subi.w  #$0100,d2
                cmp.w   #$0100,d2
                bcc.s   .lp
                move.b  hl_buf+7.w,d0
                move.b  #$80,R_BCPS(a5)
                move    #4,ccr
                rts
; ---- 35:61E9 (menus): OBJ palettes 0-6 := colour 0 black, colours 1-3 from the 42 bytes at
; HL. Exit: A = last byte, C = $6b, D = 0, HL after the data, OCPS = $b8, Z, no carry.
hle_35_61e9::
                move.b  #$6b,d1
                andi.w  #$00ff,d2
                ori.w   #$0700,d2
.lp:            lea     hl_buf.w,a1
                clr.w   (a1)+
                moveq   #6,d6
                bsr     hl_copy
                move.w  d2,d6
                lsr.w   #8,d6
                neg.b   d6
                add.b   #15,d6                  ; OBJ palette 7 - D
                move.w  d6,d7
                andi.w  #7,d7
                lsl.w   #3,d7
                lea     obpal_raw.w,a0          ; (the GPU has it already: nothing to send)
                adda.w  d7,a0
                move.l  hl_buf.w,d7
                cmp.l   (a0)+,d7
                bne.s   .snd
                move.l  hl_buf+4.w,d7
                cmp.l   (a0),d7
                beq.s   .n
.snd:           lea     hl_buf.w,a0
                bsr     pal4_all
.n:             subi.w  #$0100,d2
                cmp.w   #$0100,d2
                bcc.s   .lp
                move.b  hl_buf+7.w,d0
                move.b  #$b8,R_OCPS(a5)
                move    #4,ccr
                rts
; copy d6.w bytes from the GB address HL (d3, advanced) to a1 (advanced)
hl_copy:
                move.w  d3,d7
                add.w   d6,d7
                subq.w  #1,d7                   ; (last byte)
                eor.w   d3,d7
                andi.w  #$f000,d7
                bne.s   .slow                   ; (crosses a 4 KB area)
                move.w  d3,d7
                cmp.w   #$4000,d7
                bcs.s   .f
                cmp.w   #$8000,d7
                bcs.s   .rx
                cmp.w   #$c000,d7
                bcs.s   .slow
                cmp.w   #$d000,d7
                bcc.s   .slow
.f:             lea     (a5,d7.w),a0
                bra.s   .c
.rx:            lea     (a4,d7.w),a0
.c:             add.w   d6,d3
                subq.w  #1,d6
.cl:            move.b  (a0)+,(a1)+
                dbra    d6,.cl
                rts
.slow:          move.w  d6,-(a7)
.sl:            move.w  d3,d6
                jsr     gb_rd
                move.b  d7,(a1)+
                addq.w  #1,d3
                subq.w  #1,(a7)
                bne.s   .sl
                addq.l  #2,a7
                rts

; ---- sound engine (banks 20 / 21: "GHX Sound Engine", Martin Wodok 1999) ------------------
; On the GB a sound effect takes the channels it needs from the music (it overwrites their
; state in the engine RAM and the music skips its notes there until the effect is over).
; Here the engine runs as two instances: the music (the engine RAM in place, DSP channels
; 1-4) and the effects (its own copy of the engine RAM at SDRV, swapped in while it runs, and
; its own sound registers: DSP channels 5-8, mixed with the music). The effects instance has
; its sequencer off (C30D bit 7) and no music.
; exchange the engine RAM (C200-C2AF, C300-C33F) with the other instance's ; uses d6/d7/a0/a1
snd_swap:
                lea     $c200+G(a5),a0
                lea     SDRV,a1
                moveq   #($b0/4)-1,d7
.l1:            move.l  (a0),d6
                move.l  (a1),(a0)+
                move.l  d6,(a1)+
                dbra    d7,.l1
                lea     $c300+G(a5),a0
                moveq   #($40/4)-1,d7
.l2:            move.l  (a0),d6
                move.l  (a1),(a0)+
                move.l  d6,(a1)+
                dbra    d7,.l2
                ; C334 (car speed, written by the race code, 1:4077) stays in place: it sets
                ; the pitch of the engine hum (ch3 instrument, 4C4A), played by the effects
                ; instance
                move.b  $c334+G(a5),d6
                move.b  SDRV+$b0+$34.w,$c334+G(a5)
                move.b  d6,SDRV+$b0+$34.w
                not.b   snd_inst.w
                rts
; run the GB engine routine a0.w in the effects instance, the GB registers kept
snd_inb:
                movem.l d0-d3,snd_save.w
                move.w  a0,-(a7)
                bsr     snd_swap
                move.b  #$80,$c30d+G(a5)        ; (no music in this instance)
                movea.w (a7)+,a0
                jsr     call_gb
                bsr.s   snd_act
                bsr     snd_swap
                movem.l snd_save.w,d0-d3
                rts
; (effects instance in place) channels in use by an effect (C203, C22F, C25B, C287 != 0);
; an effect that is over keeps sounding (its instrument goes on) until the music plays a
; note on that channel (snd_take) ; uses d0-d1
snd_act:
                moveq   #0,d0
                tst.b   $c203+G(a5)
                beq.s   .c2
                bset    #0,d0
.c2:            tst.b   $c22f+G(a5)
                beq.s   .c3
                bset    #1,d0
.c3:            tst.b   $c25b+G(a5)
                beq.s   .c4
                bset    #2,d0
.c4:            tst.b   $c287+G(a5)
                beq.s   .cx
                bset    #3,d0
.cx:            move.b  snds_act.w,d1
                move.b  d0,snds_act.w
                or.b    snds_tail.w,d1          ; tail: over (or already in tail), not in use
                not.b   d0
                and.b   d0,d1
                move.b  d1,snds_tail.w
                ; a tail needs the engine update while its instrument program goes on (steps
                ; left: C214 + $2c * channel, or a vibrato: C209) ; (the wave channel: always)
                moveq   #0,d0
                btst    #0,d1
                beq.s   .t2
                move.b  $c214+G(a5),d0
                or.b    $c209+G(a5),d0
.t2:            btst    #1,d1
                beq.s   .t3
                or.b    $c240+G(a5),d0
                or.b    $c235+G(a5),d0
.t3:            btst    #2,d1
                beq.s   .t4
                st      d0
.t4:            btst    #3,d1
                beq.s   .t5
                or.b    $c298+G(a5),d0
                or.b    $c28d+G(a5),d0
.t5:            or.b    snds_act.w,d0
                sne     snds_on.w               ; (something to update)
                tst.b   $c336+G(a5)             ; (a pending looping effect)
                beq.s   .ox
                st      snds_on.w
.ox:            rts
; (from io_w_snd, music instance, d6.w = register, d7 = value: both kept) a note triggered by
; the music on a channel where the tail of an effect sounds: that sound stops (its DAC off,
; its instrument program ended in the effects instance's RAM)
snd_take:
                move.b  d7,-(a7)
                btst    #7,d7
                beq.s   .tx                      ; (not a trigger)
                moveq   #0,d7
                cmp.w   #$ff14,d6
                beq.s   .t
                moveq   #1,d7
                cmp.w   #$ff19,d6
                beq.s   .t
                moveq   #2,d7
                cmp.w   #$ff1e,d6
                beq.s   .t
                moveq   #3,d7
                cmp.w   #$ff23,d6
                bne.s   .tx
.t:             bclr    d7,snds_tail.w
                beq.s   .tx                      ; (no tail there)
                movem.l d6/a1,-(a7)
                lea     snd_off(pc),a0
                move.w  d7,d6
                add.w   d6,d6
                move.w  (a0,d6.w),d6            ; its NRx2 / NR30
                lea     SDRV+$14,a1             ; C214 + $2c * channel: instrument steps left
                mulu    #$2c,d7
                clr.b   (a1,d7.w)
                moveq   #0,d7
                st      snd_inst.w              ; (the effects instance's register)
                bsr     io_w_snd
                sf      snd_inst.w
                movem.l (a7)+,d6/a1
.tx:            move.b  (a7)+,d7
                rts
snd_off:        dc.w    $ff12,$ff17,$ff1a,$ff21
; 4000: play music A (the music instance; the effects instance's engine on)
snd_play::
                movea.w #$4102,a0
                jsr     call_gb
                move.b  #$ff,SDRV+$b0.w
                rts
; 4003: once per frame: the music, then the effects when there are some
snd_update::
                movea.w #$426c,a0
                jsr     call_gb
                tst.b   snds_on.w
                beq.s   .ux
                movea.w #$426c,a0
                bra     snd_inb
.ux:             rts
; 4015: sound effect A: the effects instance only
snd_fx::
                st      snds_on.w
                bsr     snd_swap
                move.b  #$80,$c30d+G(a5)
                movea.w #$4de1,a0
                jsr     call_gb
                movem.l d0-d1,-(a7)
                bsr     snd_act
                movem.l (a7)+,d0-d1
                st      snds_on.w               ; (updated from the next frame on)
                bra     snd_swap
; 4006 (stop), 4009 (sound on, restart the looping effect), 4018 (off): both instances
snd_both6::
                movea.w #$4248,a0
                bra.s   snd_both
snd_both9::
                movea.w #$4225,a0
                bra.s   snd_both
snd_both18::
                movea.w #$4265,a0
snd_both:
                move.w  a0,-(a7)
                jsr     call_gb
                movea.w (a7)+,a0
                st      snds_on.w
                bra     snd_inb
; ---- 0:1A73 results screen gradient: colour 0 of BG palettes 0-3 and 6 ---------
hle_1a73::
                moveq   #0,d7
                move.b  $ca90+G(a5),d7
                bclr    #0,d7
                lea     $ca00+G(a5),a0
                adda.w  d7,a0
                bsr     rdw_a0
                moveq   #$4f,d6
                bsr     grad_m
                move.b  #$b2,R_BCPS(a5)
                addq.b  #1,$ca90+G(a5)
                cmpi.b  #$90,$ca90+G(a5)
                bne.s   .r
                clr.b   $ca90+G(a5)
.r:             st      gb_ime.w
                cmp.b   d7,d7
                rts

; ---- 0:1B13 main menu gradient (+ mid-frame OAM DMA) -------------------------
hle_1b13::
                moveq   #0,d7
                move.b  $ca90+G(a5),d7
                bclr    #0,d7
                lea     $ca00+G(a5),a0
                adda.w  d7,a0
                bsr     rdw_a0
                bsr     grad3
                addq.b  #1,$ca90+G(a5)
                move.b  $ca90+G(a5),d7
                cmp.b   #$48,d7
                bne.s   .n48
                clr.b   $ca90+G(a5)
                sf      gb_ime.w                ; plain RET
                cmp.b   d7,d7
                rts
.n48:           cmp.b   #$3c,d7
                bne.s   .r
                move.b  #$c1,d7
                bsr     oam_dma
.r:             st      gb_ime.w
                cmp.b   d7,d7
                rts

; ---- 0:1B4D racer select: BG gradient (even counts), OBJ palettes (odd counts),
; SCX := (CAA9) at count $30, mid-frame OAM DMA at $3C, plain RET at $50
hle_1b4d::
                moveq   #0,d7
                move.b  $ca90+G(a5),d7
                btst    #0,d7
                bne.s   .odd
                lea     $ca00+G(a5),a0          ; colour 0 of BG palettes 0-2
                adda.w  d7,a0
                bsr     rdw_a0
                bsr     grad3
                bra.s   .next
.odd:           cmp.b   #$2f,d7
                bcs.s   .lo
                cmp.b   #$3f,d7
                bcc.s   .next
                sub.b   #$2f,d7                 ; OCPS := l*4+$82, 6 bytes from C538+l*3
                lea     $c538+G(a5),a1
                adda.w  d7,a1
                adda.w  d7,a1
                adda.w  d7,a1
                move.b  d7,d6
                lsl.b   #2,d6
                add.b   #$82,d6
                move.l  d5,-(a7)
                moveq   #6,d5
                bsr     ob_bytes_a1
                move.l  (a7)+,d5
                bra.s   .next
.lo:            bclr    #0,d7                   ; colour 1 of OBJ palettes 0, 1 := word CAA8+l
                lea     $caa8+G(a5),a0
                adda.w  d7,a0
                bsr     rdw_a0
                moveq   #1,d6
                bsr     ob_col
                moveq   #5,d6
                bsr     ob_col
                move.b  #$8c,R_OCPS(a5)
.next:          addq.b  #1,$ca90+G(a5)
                move.b  $ca90+G(a5),d7
                cmp.b   #$50,d7
                bne.s   .n50
                clr.b   $ca90+G(a5)
                sf      gb_ime.w                ; plain RET
                cmp.b   d7,d7
                rts
.n50:           cmp.b   #$30,d7
                bne.s   .n30
                move.b  $caa9+G(a5),d7
                move.w  #$ff43,d6
                bsr     hle_reg
                bra.s   .r
.n30:           cmp.b   #$3c,d7
                bne.s   .r
                move.b  #$c1,d7
                bsr     oam_dma
.r:             st      gb_ime.w
                cmp.b   d7,d7
                rts

; ---- race chain routines (d7 = param, d6 = param2) ----------------------------
sc_grad0::
                move.b  $c654+G(a5),d7
                move.w  #$ff42,d6
                bsr     hle_reg
                move.b  $c779+G(a5),d7
                move.w  #$ff43,d6
                bsr     hle_reg
                moveq   #0,d7
sc_grad::
                add.b   $c47f+G(a5),d7
                andi.w  #$ff,d7
                lea     $c400+G(a5),a0
                adda.w  d7,a0
                bsr     rdw_a0
                bra     grad3

; OBJ palette 5 colour 1 := word C1xx (d7 = xx), OCPS := $AC, then constants (d6 != $ff)
sc_objw::
                andi.w  #$ff,d7
                lea     $c100+G(a5),a0
                adda.w  d7,a0
                move.l  d6,-(a7)
                bsr     rdw_a0
                moveq   #21,d6
                bsr     ob_col
                move.b  #$ac,R_OCPS(a5)
                move.l  (a7)+,d6
                cmp.b   #$ff,d6
                bne.s   sc_const
                rts
; constant OBJ palette writes: sc_consts + d6 = (ocps, count, bytes)..., 0
sc_const::
                andi.w  #$ff,d6
                lea     sc_consts,a1
                adda.w  d6,a1
.lp:             move.b  (a1)+,d6                ; ocps
                beq.s   .xx
                move.l  d5,-(a7)
                move.b  (a1)+,d5                ; count
                bsr     ob_bytes_a1
                move.l  (a7)+,d5
                bra.s   .lp
.xx:             rts
; OCPS := d6, then d5.b bytes from a1 (a1 advanced), final OCPS as the GB auto-increment
ob_bytes_a1::
                andi.w  #$3f,d6
                tst.b   rnd.w
                beq.s   .nd                     ; undrawn: final OCPS only (as ob_byte)
                btst    #0,d6
                bne.s   .bb
                btst    #0,d5
                bne.s   .bb
                lea     obpal_raw.w,a0          ; whole colours: one command each
.pp:            move.b  (a1)+,(a0,d6.w)
                move.b  (a1)+,1(a0,d6.w)
                move.b  #LC_OBCOL,(a6)+
                move.w  d6,d7
                lsr.w   #1,d7
                move.b  d7,(a6)+
                move.b  1(a0,d6.w),(a6)+
                move.b  (a0,d6.w),(a6)+
                addq.b  #2,d6
                andi.b  #$3f,d6
                subq.b  #2,d5
                bne.s   .pp
                cmpa.l  log_limit.w,a6
                bcs.s   .fin
                move.w  d6,-(a7)
                bsr     log_slow
                move.w  (a7)+,d6
                bra.s   .fin
.nd:            add.b   d5,d6
                andi.b  #$3f,d6
                bra.s   .fin
.bb:            move.b  (a1)+,d7
                move.w  d6,-(a7)
                bsr     ob_byte
                move.w  (a7)+,d6
                addq.b  #1,d6
                andi.b  #$3f,d6
                subq.b  #1,d5
                bne.s   .bb
.fin:           ori.b   #$80,d6
                move.b  d6,R_OCPS(a5)
                rts
; OCPS := d6, 6 bytes from GB address d7.w (ROM0 / WRAM0: flat image)
sc_ocprom:
                lea     (a5,d7.w),a1
                move.l  d5,-(a7)
                moveq   #6,d5
                bsr     ob_bytes_a1
                move.l  (a7)+,d5
                rts
; d7.b := d7.b * 6 (mod 256)
mul6:
                move.b  d7,d6
                add.b   d7,d7
                add.b   d6,d7
                add.b   d7,d7
                rts

; line 9 (0:1D3C)
sc_objrom::
                moveq   #-1,d6
                bsr     sc_objw
                move.b  $c529+G(a5),d7
                bsr     mul6
                andi.w  #$ff,d7
                addi.w  #$2582,d7
                move.b  #$ba,d6
                bra     sc_ocprom
; line 49 (0:2242): OBJ palette 7 colours 1-3 by state C1EC
sc_2242::
                move.b  $c1ec+G(a5),d7
                add.b   d7,d7
                bcs.s   .c70
                bne.s   .c6a
                tst.b   $c1f4+G(a5)
                bne.s   .cf5
                move.b  $c1c3+G(a5),d7
                bsr     mul6
                andi.w  #$ff,d7
                addi.w  #$25d6,d7
                bra.s   .ww
.c70:           move.w  #$2570,d7
                bra.s   .ww
.c6a:           move.w  #$256a,d7
                bra.s   .ww
.cf5:           move.w  #$c1f5,d7
.ww:             move.b  #$ba,d6
                bra     sc_ocprom
; line 53 (0:22FF): OBJ palette 5 colours 1-3
sc_22ff::
                move.l  d5,-(a7)
                move.b  $c518+G(a5),d7
                beq.s   .t
                move.w  #$2576,d6
                cmp.b   #$18,d7
                bcs.s   .w6
                move.w  #$257c,d6
                add.b   d7,d7
                bcs.s   .w6
.t:             move.b  $ff97+G(a5),d7
                beq.s   .z
                addq.b  #1,d7
                beq.s   .bz
                move.w  #$2906,d5
                bra.s   .bb
.bz:            move.w  #$2606,d5
.bb:             moveq   #0,d6
                move.b  $c516+G(a5),d6
                lsl.b   #5,d6                   ; (C516 << 5) & $ff
                move.w  d6,d7
                add.w   d6,d6
                add.w   d7,d6                   ; * 3
                add.w   d5,d6
                move.b  $c520+G(a5),d7
                lsr.b   #3,d7
                bsr.s   .m6
                add.w   d7,d6
                bra.s   .w6
.z:             move.b  $c516+G(a5),d7
                bsr.s   .m6
                move.w  #$25d6,d6
                add.w   d7,d6
.w6:            move.w  d6,d7
                move.l  (a7)+,d5
                move.b  #$aa,d6
                bra     sc_ocprom
.m6:            move.b  d7,d5
                add.b   d7,d7
                add.b   d5,d7
                add.b   d7,d7
                andi.w  #$ff,d7
                rts
; line 47 (0:2209): OAM DMA of the lower-area sprites
sc_dma::
                bra     hal_oam_dma
sc_none::
                rts
; line 71 (0:254E): plain RET, IME stays off until the main loop's EI
sc_last::
                sf      gb_ime.w
                rts


;; ---------------------------------------------------------------------------
; 0:32AE road renderer (lines 73-142), native. Same side effects as the GB code:
; OAM buffer entries C000+4k, C6xx consumption, HDMA sprite tile streaming (one
; block per line), BG palette 0 / sky colour, SCX/SCY, FF8A-FF8E, MBC bank.
; Line routine n (0..69) runs during line 73+n; its register writes show on 74+n.
; Inside the loop the ROM bank is switched locally (a4 from bank_base, d3 = bank);
; the MBC state is synchronised once at the end (or before any GB interrupt).
; ---------------------------------------------------------------------------
                .macro  FBANK                   ; d7.b = bank -> a4, d3
                andi.w  #$3f,d7
                move.b  d7,d3
                add.w   d7,d7
                add.w   d7,d7
                lea     bank_base.w,a0
                movea.l (a0,d7.w),a4
                .endm

hle_road::
                movem.l d0-d5/a1,-(a7)
                moveq   #0,d0
                moveq   #0,d1
                btst    #0,$ff9e+G(a5)
                beq.s   .p0
                move.w  #$0500,d0
                moveq   #$50,d1
.p0:            move.b  d0,R_HDMA4(a5)
                lsr.w   #8,d0
                move.b  d0,R_HDMA3(a5)
                move.b  d1,$ff8d+G(a5)
                moveq   #1,d7
                move.w  #$ff4f,d6
                bsr     io_w_vbk
                bsr     rd_wait73
.go:            sf      rl_rend.w
                clr.l   rl_tbl.w                ; per-frame road palette source setup
                tst.b   rnd.w
                beq.s   .nt
                move.b  $ff9a+G(a5),d7
                andi.w  #$3f,d7
                add.w   d7,d7
                add.w   d7,d7
                lea     bank_base.w,a0
                move.l  (a0,d7.w),rl_pbase.w
                tst.b   $ff97+G(a5)
                bne.s   .nt
                move.b  $ff99+G(a5),d7          ; word table (FF99:FF98) + 2*row in WRAM0
                lsl.w   #8,d7
                move.b  $ff98+G(a5),d7
                cmp.w   #$c000,d7
                bcs.s   .nt
                cmp.w   #$ce00,d7
                bcc.s   .nt
                lea     (a5,d7.w),a0
                move.l  a0,rl_tbl.w
.nt:            move.b  cur_bank.w,d3
                bsr     rh_load
                tst.b   gb_ime.w                ; no GB interrupt in between, palette pointers
                bne.s   .gen                    ; from the WRAM0 table: the fast loop
                tst.b   rnd.w
                beq     road_fast
                tst.l   rl_tbl.w
                bne     road_fast
.gen:           moveq   #0,d4                   ; n (word: index)
.line:          btst    #0,d4
                bne     .odd
                ; ---- even line (0:38DC): object descriptor C655+n/2
                move.w  d4,d7
                lsr.w   #1,d7
                lea     $c655+G(a5),a1
                move.b  (a1,d7.w),d5
                bmi     .new
                moveq   #0,d7                   ; continuing object: offset d5 in its data
                move.b  $ff8a+G(a5),d7
                lea     $c600+G(a5),a1
                adda.w  d7,a1
                move.b  (a1)+,d7
                FBANK
                moveq   #0,d6
                move.b  1(a1),d6
                lsl.w   #8,d6
                move.b  (a1),d6
                andi.w  #$ff,d5
                add.w   d5,d6
                cmp.w   #$4000,d6
                bcs.s   .eg
                cmp.w   #$7fff,d6
                bcc.s   .eg
                move.b  (a4,d6.w),$ff8b+G(a5)   ; (ROMX: direct)
                move.b  1(a4,d6.w),$ff8c+G(a5)
                bra     .row
.eg:            bsr     rd8
                move.b  d7,$ff8b+G(a5)
                bsr     rd8
                move.b  d7,$ff8c+G(a5)
                bra     .row
.new:           move.b  d5,$ff8a+G(a5)
                moveq   #0,d7
                move.b  d5,d7
                lea     $c600+G(a5),a1
                adda.w  d7,a1
                move.b  (a1)+,d7
                FBANK
                moveq   #0,d6
                move.b  1(a1),d6
                lsl.w   #8,d6
                move.b  (a1),d6
                bsr     rd8
                move.b  d7,R_HDMA2(a5)
                bsr     rd8
                move.b  d7,R_HDMA1(a5)
                lsl.w   #8,d7                   ; new DMA source
                move.b  R_HDMA2(a5),d7
                andi.w  #$fff0,d7
                move.w  d7,rh_src.w
                sf      rh_valid.w
                bsr     rd8
                move.b  d7,$ff8b+G(a5)
                bsr     rd8
                move.b  d7,$ff8c+G(a5)
                bra.s   .row
                ; ---- odd line (0:3988): OAM buffer entry C000+4*(n/2) from the current object
.odd:           move.b  d4,$ff8e+G(a5)
                moveq   #0,d7
                move.b  $ff8a+G(a5),d7
                lea     $c600+G(a5),a1
                adda.w  d7,a1
                cmp.b   #69,d4                  ; (same object, same bank as the even line
                bne.s   .sb                     ;  before: only the final MBC state needs it)
                move.b  (a1),d7
                FBANK
.sb:            move.w  d4,d6
                andi.b  #$fe,d6
                add.w   d6,d6
                lea     $c000+G(a5),a0
                adda.w  d6,a0
                move.b  $ff8b+G(a5),d7
                add.b   -1(a1),d7
                move.b  d7,(a0)+
                move.b  $ff8c+G(a5),d7
                add.b   -2(a1),d7
                move.b  d7,(a0)+
                move.b  $ff8d+G(a5),d7
                move.b  d7,(a0)+
                addq.b  #2,d7
                move.b  d7,$ff8d+G(a5)
                move.b  -3(a1),(a0)
                ; ---- line part: C6[n] = road row + 1 (0 = sky), cleared
.row:           lea     $c600+G(a5),a1
                moveq   #0,d5
                move.b  (a1,d4.w),d5
                clr.b   (a1,d4.w)
                tst.b   d5
                beq     .sky
                subq.b  #1,d5                   ; row
                tst.b   rnd.w
                beq.s   .adv                    ; undrawn: no palette pointer
                move.l  rl_tbl.w,d7             ; WRAM0 pointer table (set up per frame)
                beq.s   .ptg
                movea.l d7,a0
                move.w  d5,d7
                add.w   d7,d7
                move.b  1(a0,d7.w),d0
                lsl.w   #8,d0
                move.b  (a0,d7.w),d0            ; GB address of the 8 palette bytes
                cmp.w   #$4000,d0
                bcc.s   .ptr
                lea     (a5,d0.w),a0
                move.l  a0,d0
                bra.s   .adv
.ptr:           movea.l rl_pbase.w,a0
                adda.w  d0,a0
                move.l  a0,d0
                bra.s   .adv
.ptg:           bsr     rd_ppg                  ; (other tables)
                ; ---- line 73+n is drawn, its HBlank DMA block is copied, LY advances
.adv:           tst.b   gb_ime.w
                bne     .slw
                tst.b   rnd.w
                beq.s   .nl
                tst.b   rl_rend.w               ; (rendered by the last LC_ROADLN)
                bne.s   .rr
                move.l  #LC_LINE<<24,d7
                move.b  v_ly.w,d7
                move.l  d7,(a6)+
.rr:            sf      rl_rend.w
                moveq   #7,d7
                and.b   v_ly.w,d7
                bne.s   .nl
                PUBLISH d7
.nl:            tst.b   strm.w                  ; HBlank DMA block rh_src -> rh_dst
                beq     .skp                    ; (tiles not needed by the next frame)
                tst.b   rh_valid.w
                bne.s   .v
                move.w  rh_src.w,d7
                bsr     src_ptr
                move.l  a0,rh_ptr.w
                st      rh_valid.w
.v:             movea.l rh_ptr.w,a0
                move.w  rh_dst.w,d6
                lea     (a2,d6.w),a1
                move.b  #LC_BLOCK,(a6)+         ; (the GPU skips what does not change)
                move.b  vbk_cur.w,(a6)+
                move.w  d6,(a6)+
                moveq   #16,d1
                move.l  d1,(a6)+
                move.l  (a0)+,d1
                move.l  d1,(a1)+
                move.l  d1,(a6)+
                move.l  (a0)+,d1
                move.l  d1,(a1)+
                move.l  d1,(a6)+
                move.l  (a0)+,d1
                move.l  d1,(a1)+
                move.l  d1,(a6)+
                move.l  (a0)+,d1
                move.l  d1,(a1)+
                move.l  d1,(a6)+
.ha:            addi.l  #16,rh_ptr.w
                bra.s   .hs
.skp:           sf      rh_valid.w              ; (pointer recomputed when streaming resumes)
                move.w  rh_dst.w,d6
.hs:            addi.w  #16,rh_src.w
                addi.w  #16,d6
                andi.w  #$1ff0,d6
                ori.w   #$8000,d6
                move.w  d6,rh_dst.w
                addq.b  #1,v_ly.w               ; (v_phase, DIV: at the end of the road)
                cmpa.l  log_limit.w,a6
                bcs.s   .sc
                bsr     log_slow
                ; ---- SCY / SCX of line 74+n, road palette
.sc:            move.b  #$3e,d7                 ; SCY = row + $3E - n
                sub.b   d4,d7
                add.b   d5,d7
                move.b  d7,R_SCY(a5)
                lea     $c700+G(a5),a1          ; SCX = C700[row]
                move.b  (a1,d5.w),d6
                move.b  d6,R_SCX(a5)
                tst.b   rnd.w
                beq.s   .nd
                cmp.b   #69,d4                  ; the GPU reads BG palette 0 itself
                bcc.s   .r0
                move.b  #LC_ROADLN|LF_LINE,(a6)+ ; and renders line 74+n right after
                st      rl_rend.w
                bra.s   .r1
.r0:            move.b  #LC_ROADLN,(a6)+
.r1:            move.b  d7,(a6)+
                move.b  d6,(a6)+
                clr.b   (a6)+
                move.l  d0,(a6)+                ; 8 bytes at d0
                move.l  d0,rl_pal.w
.nd:            cmp.b   #69,d4                  ; (BCPS and the FF9A bank are only seen
                bne.s   .next                   ;  after the last line)
                move.b  $ff9a+G(a5),d7
                FBANK
                move.b  #$88,R_BCPS(a5)
.next:          addq.b  #1,d4
                cmp.b   #70,d4
                bne     .line
                bra     .end
.slw:           bsr     rd_slow                 ; interrupts enabled: the generic line
                bra     .sc
.sky:           move.b  d4,d7                   ; colour C4[(C47F) + $48 + 2*(n/2)]
                andi.b  #$fe,d7
                addi.b  #$48,d7
                add.b   $c47f+G(a5),d7
                andi.w  #$ff,d7
                lea     $c400+G(a5),a0
                adda.w  d7,a0
                bsr     rdw_a0
                move.w  d7,d0
                bsr     rd_adv
                move.w  d0,d7
                bsr     grad3
                bra.s   .next
.end:
road_end:       move.b  #2,v_phase.w
                addi.w  #4*70,div_cnt.w
                bsr     rh_store
                bsr     rd_sync
                move.l  rl_pal.w,d7              ; GB palette RAM: last road palette
                beq.s   .np0
                movea.l d7,a0
                lea     bgpal_raw.w,a1
                moveq   #7,d7
.rp:            move.b  (a0)+,(a1)+
                dbra    d7,.rp
                clr.l   rl_pal.w
                st      grad_last.w
.np0:
                PUBLISH d6
                movem.l (a7)+,d0-d5/a1
                rts

; ---------------------------------------------------------------------------
; Fast loop of 0:32AE: used when no GB interrupt can run in between (IME off) and, in a
; drawn frame, the palette pointers come from the WRAM0 table. Nothing but the final state
; has to match the GB code line by line, so:
; - the GPU gets one command per line (scroll + palette address, or sky colour) that also
;   renders the line;
; - the HBlank DMA blocks (16 bytes of object tiles per line) are sent once per object, as
;   a block that the GPU reads from the ROM itself;
; - the ROM bank is only switched at the end (bank (FF9A), as the GB code leaves it).
; d4 = $c600 + n, d3 = address of the next object descriptor, d2 = $3e - n, d1 = DMA blocks
; of the current run, a1 = C600 + object, a2 = OAM buffer entry, a3 = object data
; ---------------------------------------------------------------------------
road_fast:
                move.l  a2,rd_a2.w
                move.l  a3,rd_a3.w
                tst.b   rnd.w
                beq.s   .nm
                move.l  #(LC_LINE<<24)|73,(a6)+ ; line 73: drawn before the first change
.nm:            lea     $c000+G(a5),a2
                move.w  #$c600,d4
                move.w  #$c655,d3
                moveq   #$3e,d2
                moveq   #0,d1
                bsr     rd_obj                  ; the object going on from the last frame
.line:          btst    #0,d4
                bne.s   .odd
                ; ---- even line: object descriptor C655+n/2
                addq.w  #1,d3
                moveq   #0,d5
                move.b  -1(a5,d3.w),d5
                bmi.s   .new
                move.b  (a3,d5.w),$ff8b+G(a5)   ; same object: y, x at this offset of its data
                move.b  1(a3,d5.w),$ff8c+G(a5)
                bra.s   .row
.new:           bsr     rd_flush                ; (the blocks of the object before)
                move.b  d5,$ff8a+G(a5)
                bsr     rd_obj
                move.b  (a3),R_HDMA2(a5)        ; its data: DMA source, y, x
                move.b  1(a3),d7
                move.b  d7,R_HDMA1(a5)
                lsl.w   #8,d7
                move.b  (a3),d7
                andi.w  #$fff0,d7
                move.w  d7,rh_src.w
                move.b  2(a3),$ff8b+G(a5)
                move.b  3(a3),$ff8c+G(a5)
                bra.s   .row
                ; ---- odd line: OAM buffer entry C000+4*(n/2) from the current object
.odd:           move.b  $ff8b+G(a5),d7
                add.b   -1(a1),d7
                move.b  d7,(a2)+
                move.b  $ff8c+G(a5),d7
                add.b   -2(a1),d7
                move.b  d7,(a2)+
                move.b  $ff8d+G(a5),(a2)+
                addq.b  #2,$ff8d+G(a5)
                move.b  -3(a1),(a2)+
                ; ---- line part: C6[n] = road row + 1 (0 = sky), cleared
.row:           moveq   #0,d5
                move.b  (a5,d4.w),d5
                beq     .sky
                clr.b   (a5,d4.w)
                subq.b  #1,d5                   ; row
                move.b  d2,d7
                add.b   d5,d7                   ; SCY = row + $3E - n
                move.b  d7,R_SCY(a5)
                lea     $c700+G(a5),a0
                move.b  (a0,d5.w),d6            ; SCX = C700[row]
                move.b  d6,R_SCX(a5)
                tst.b   rnd.w
                beq.s   .next
                move.b  #LC_ROADLN|LF_LINE,(a6)+ ; line 74+n with them and BG palette 0
                move.b  d7,(a6)+
                move.b  d6,(a6)+
                clr.b   (a6)+
                movea.l rl_tbl.w,a0             ; GB address of the 8 palette bytes
                add.w   d5,d5
                move.b  1(a0,d5.w),d0
                lsl.w   #8,d0
                move.b  (a0,d5.w),d0
                cmp.w   #$4000,d0
                bcc.s   .ph
                lea     (a5,d0.w),a0
                bra.s   .pa
.ph:            movea.l rl_pbase.w,a0
                adda.w  d0,a0
.pa:            move.l  a0,(a6)+
                move.l  a0,rl_pal.w
                sf      rl_rend.w               ; (the last command is a road row)
.next:          addq.w  #1,d1                   ; one more DMA block
                subq.b  #1,d2
                addq.w  #1,d4
                moveq   #15,d7
                and.b   d4,d7
                bne.s   .nx2
                PUBLISH d7                      ; every 16 lines
                cmpa.l  log_limit.w,a6
                bcs.s   .nx2
                bsr     log_slow
.nx2:           cmp.b   #70,d4
                bne     .line
                bra     .end
.sky:           move.b  #$92,R_BCPS(a5)         ; sky: colour C4[(C47F) + $48 + 2*(n/2)]
                tst.b   rnd.w
                beq     .next
                move.b  d4,d7
                andi.b  #$fe,d7
                addi.b  #$48,d7
                add.b   $c47f+G(a5),d7
                andi.w  #$ff,d7
                lea     $c400+G(a5),a0
                move.b  1(a0,d7.w),d0
                lsl.w   #8,d0
                move.b  (a0,d7.w),d0
                move.l  #((LC_GRAD3|LF_LINE)<<24)|$70000,d7
                move.w  d0,d7
                move.l  d7,d6
                andi.l  #$00ffffff,d6
                cmp.l   grad_last.w,d6
                beq.s   .sk1
                move.l  d6,grad_last.w
                move.l  d7,(a6)+
                bra.s   .sk2
.sk1:           move.l  #(LC_NOP|LF_LINE)<<24,(a6)+
.sk2:           st      rl_rend.w               ; (the last command is a sky line)
                bra     .next
.end:           tst.b   rnd.w
                beq.s   .e1
                lea     -8(a6),a0               ; line 143 is not rendered from here
                tst.b   rl_rend.w
                beq.s   .e0
                addq.l  #4,a0
.e0:            bclr    #7,(a0)
.e1:            sf      rl_rend.w
                bsr     rd_flush
                move.b  #69,$ff8e+G(a5)
                movea.l rd_a2.w,a2
                movea.l rd_a3.w,a3
                addi.b  #70,v_ly.w
                move.b  $ff9a+G(a5),d7
                FBANK
                move.b  #$88,R_BCPS(a5)
                bra     road_end

; current object (FF8A): a1 := its entry in C6xx, a4 := its ROM bank, a3 := its data
rd_obj:
                moveq   #0,d7
                move.b  $ff8a+G(a5),d7
                lea     $c600+G(a5),a1
                adda.w  d7,a1
                move.b  (a1),d7
                andi.w  #$3f,d7
                add.w   d7,d7
                add.w   d7,d7
                lea     bank_base.w,a0
                movea.l (a0,d7.w),a4
                move.b  2(a1),d7
                lsl.w   #8,d7
                move.b  1(a1),d7
                bsr.s   rd_ptr
                movea.l a0,a3
                rts
; a0 := 68k address of the GB address d7.w (ROMX: bank a4 ; VRAM / WRAMX: the bases saved
; in rd_a2 / rd_a3)
rd_ptr:
                cmp.w   #$4000,d7
                bcs.s   .f
                cmp.w   #$8000,d7
                bcs.s   .xx
                cmp.w   #$a000,d7
                bcs.s   .v
                cmp.w   #$d000,d7
                bcs.s   .f
                cmp.w   #$e000,d7
                bcs.s   .wt
.f:             lea     (a5,d7.w),a0
                rts
.xx:            lea     (a4,d7.w),a0
                rts
.v:             movea.l rd_a2.w,a0
                adda.w  d7,a0
                rts
.wt:            movea.l rd_a3.w,a0
                adda.w  d7,a0
                rts
; the d1 HBlank DMA blocks done since the last call: rh_src -> rh_dst (VRAM bank vbk_cur),
; counters advanced, d1 := 0. From the ROM: one command, the GPU reads the data.
rd_flush:
                tst.w   d1
                beq     .r
                tst.b   strm.w
                beq.s   .adv                    ; (tiles not needed by the next frame)
                move.w  rh_src.w,d7
                cmp.w   #$8000,d7
                bcc.s   .ram
                bsr     rd_ptr
                move.w  d1,d7
                subq.w  #1,d7
                add.w   d7,d7
                or.b    vbk_cur.w,d7
                move.b  #LC_BLKP,(a6)+
                move.b  d7,(a6)+
                move.w  rh_dst.w,(a6)+
                move.l  a0,(a6)+
                bra.s   .adv
.ram:           movem.l d1-d2,-(a7)             ; from RAM: the data itself, block by block
                move.w  rh_dst.w,d2
                subq.w  #1,d1
.rb:            bsr     rd_ptr
                movea.l rd_a2.w,a1
                adda.w  d2,a1
                move.b  #LC_BLOCK,(a6)+
                move.b  vbk_cur.w,(a6)+
                move.w  d2,(a6)+
                moveq   #16,d6
                move.l  d6,(a6)+
                moveq   #3,d6
.rc:            move.l  (a0),(a1)+
                move.l  (a0)+,(a6)+
                dbra    d6,.rc
                cmpa.l  log_limit.w,a6
                bcs.s   .rn
                bsr     log_slow
.rn:            addi.w  #16,d7
                addi.w  #16,d2
                andi.w  #$1ff0,d2
                ori.w   #$8000,d2
                dbra    d1,.rb
                movem.l (a7)+,d1-d2
.adv:           move.w  d1,d7
                lsl.w   #4,d7
                add.w   d7,rh_src.w
                add.w   rh_dst.w,d7
                andi.w  #$1ff0,d7
                ori.w   #$8000,d7
                move.w  d7,rh_dst.w
                moveq   #0,d1
.r:             rts

; advance the virtual PPU to LY = 73. Lines 0-72 whose only STAT source is HBlank
; (the race HUD chain) take a fast path: line marker + native STAT handler.
rd_wait73::
                moveq   #$49,d5                 ; (d5 is free before the road loop)
.lp:            cmp.b   v_ly.w,d5
                beq.s   .dn
                move.b  $c1a6+G(a5),d7          ; race HUD chain handler (1BEC-2558)?
                lsl.w   #8,d7
                move.b  $c1a5+G(a5),d7
                cmp.w   #$1bec,d7
                bcs.s   .nr
                cmp.w   #$2559,d7
                bcc.s   .nr
                bsr     chain_fast
                cmp.b   v_ly.w,d5
                beq.s   .dn
                bsr     chain_draw
                cmp.b   v_ly.w,d5
                beq.s   .dn
                bsr     chain_nodraw
                bra.s   .gen
.nr:            move.b  v_ly.w,-(a7)            ; other native handlers (menus): lines in
                bsr     fast_to                 ; a batch up to line 73
                move.b  (a7)+,d7
                cmp.b   v_ly.w,d7
                bne.s   .lp
.gen:           cmp.b   v_ly.w,d5
                beq.s   .dn
                bsr     fast_line
                beq.s   .lp
                bsr     vadvance_line
                bra.s   .lp
.dn:            rts

; drawn frame, the whole race HUD chain from line 0 (the normal case): lines 0-72 by the
; straight code generated by statchain68.py (sc_fastbody), one command per line for the
; GPU, then the state the chain leaves. Anything else: chain_draw.
chain_fast::
                tst.b   rnd.w
                beq     .no
                tst.b   v_ly.w
                bne     .no
                tst.b   hdma_on.w
                bne     .no
                tst.b   gb_ime.w
                beq     .no
                tst.b   v_inirq.w
                bne     .no
                btst    #1,R_IE(a5)
                beq     .no
                move.b  R_STAT(a5),d6
                andi.b  #$78,d6
                cmp.b   #$08,d6
                bne     .no
                cmpi.b  #$c3,$c1a4+G(a5)
                bne     .no
                cmpi.b  #$1e,$c1a5+G(a5)        ; next handler: 1C1E (1BEC was taken at EI)
                bne     .no
                cmpi.b  #$1c,$c1a6+G(a5)
                bne     .no
                cmpi.b  #$b9,$c47f+G(a5)        ; (the gradient colours do not wrap in C4xx)
                bcc     .no
                movem.l d3-d5,-(a7)
                move.w  #$c400,d4
                moveq   #0,d6
                move.b  $c47f+G(a5),d6
                add.w   d6,d4                   ; gradient colours at (a5,d4.w)
                move.l  grad_last.w,d5          ; last gradient sent, as its command
                ori.l   #(LC_GRAD3|LF_LINE)<<24,d5
                move.l  #((LC_GRAD3|LF_LINE)<<24)|$70000,d3
                cmpa.l  log_limit.w,a6
                bcs.s   .go
                bsr     log_slow
.go:            bsr     sc_fastbody
                move.l  d5,d6
                rol.l   #8,d6
                cmp.b   #LC_GRAD3|LF_LINE,d6
                bne.s   .ng
                andi.l  #$00ffffff,d5
                move.l  d5,grad_last.w
.ng:            movem.l (a7)+,d3-d5
                move.b  #73,v_ly.w
                addi.w  #4*73,div_cnt.w
                move.b  #$92,R_BCPS(a5)         ; (last gradient line)
                move.l  #sc_tab,sc_ptr.w        ; next handler 1BEC
                move.b  #$ec,$c1a5+G(a5)
                move.b  #$1b,$c1a6+G(a5)
                bset    #1,if_pend.w            ; (HBlanks after the chain end, IME off)
                move.b  #2,v_phase.w
.no:            rts

; drawn frame: race HUD chain lines up to 72 played straight from sc_tab: once the
; expected handler is checked, one entry per line in sequence (line marker + routine)
; until the entry that returns with IME off; C1A5 / sc_ptr / IF are written at the end.
; Anything unexpected at the start: generic path.
chain_draw::
                tst.b   rnd.w
                beq     .no
                tst.b   hdma_on.w
                bne     .no
                tst.b   gb_ime.w
                beq     .no
                tst.b   v_inirq.w
                bne     .no
                btst    #1,R_IE(a5)
                beq     .no
                move.b  R_STAT(a5),d6
                andi.b  #$78,d6
                cmp.b   #$08,d6
                bne     .no
                cmpi.b  #$c3,$c1a4+G(a5)
                bne     .no
                movea.l sc_ptr.w,a0
                move.b  $c1a6+G(a5),d6
                lsl.w   #8,d6
                move.b  $c1a5+G(a5),d6
                cmp.w   (a0),d6
                bne     .no                     ; not the expected handler
                movem.l d0-d3,-(a7)
                move.l  a0,d2                   ; next entry
                moveq   #0,d0
                move.b  v_ly.w,d0               ; line (kept in d0 during the loop)
                move.l  #LC_LINE<<24,d1
                move.b  d0,d1                   ; line marker (d1 += 1 per line)
                moveq   #0,d3                   ; lines done
.lp:            cmp.b   #$49,d0
                bcc     .dn
                move.l  d1,(a6)+
                addq.l  #1,d1
                moveq   #7,d6
                and.b   d0,d6
                bne.s   .nl
                PUBLISH d6
.nl:            tst.b   gb_ime.w
                beq     .adv                    ; (chain over: IF set at the end)
                movea.l d2,a1
                addq.l  #8,d2
                cmp.l   #sc_end,d2
                bcs.s   .nw
                move.l  #sc_tab,d2
.nw:            move.w  4(a1),d6                ; routine index * 4
                cmp.w   #4,d6                   ; sc_grad, inlined
                bne.s   .nsg
                moveq   #0,d7
                move.b  6(a1),d7
                add.b   $c47f+G(a5),d7
                lea     $c400+G(a5),a0
                adda.w  d7,a0
                move.b  1(a0),d6
                lsl.w   #8,d6
                move.b  (a0),d6                 ; colour 0 of BG palettes 0-2
                moveq   #7,d7
                swap    d7
                move.w  d6,d7
                cmp.l   grad_last.w,d7
                beq.s   .adv
                move.l  d7,grad_last.w
                move.b  #LC_GRAD3,(a6)+
                move.b  #7,(a6)+
                move.w  d6,(a6)+
                bra.s   .adv
.nsg:           cmp.w   #32,d6                  ; sc_none
                beq.s   .adv
                lea     sc_rout,a0
                movea.l (a0,d6.w),a0
                moveq   #0,d7
                move.b  6(a1),d7
                moveq   #0,d6
                move.b  7(a1),d6
                move.b  d0,v_ly.w               ; (routines may look at LY / DIV)
                jsr     (a0)                    ; (the last one leaves IME off)
.adv:           addq.b  #1,d0
                addq.w  #1,d3
                cmpa.l  log_limit.w,a6
                bcs     .lp
                bsr     log_slow
                bra     .lp
.dn:            move.b  d0,v_ly.w
                add.w   d3,d3
                add.w   d3,d3
                add.w   d3,div_cnt.w
                move.b  #$92,R_BCPS(a5)         ; (last gradient line)
                movea.l d2,a0                   ; C1A5 := next entry's handler
                move.l  a0,sc_ptr.w
                move.b  1(a0),$c1a5+G(a5)
                move.b  (a0),$c1a6+G(a5)
                tst.b   gb_ime.w
                bne.s   .x2
                bset    #1,if_pend.w            ; (HBlanks after the chain end, IME off)
.x2:            move.b  #2,v_phase.w
                movem.l (a7)+,d0-d3
.no:            rts

; undrawn frame: race HUD chain lines up to 72 with only their state effects
; (C1A5 chain, IME, BCPS/OCPS, SCX/SCY, OAM DMA): no line marker, no dispatch checks
chain_nodraw::
                tst.b   rnd.w
                bne     .no
                tst.b   gb_ime.w
                beq     .no
                tst.b   v_inirq.w
                bne     .no
                tst.b   hdma_on.w
                bne     .no
                btst    #1,R_IE(a5)
                beq     .no
                move.b  R_STAT(a5),d6
                andi.b  #$78,d6
                cmp.b   #$08,d6
                bne     .no
                cmpi.b  #$c3,$c1a4+G(a5)
                bne     .no
                ; the whole chain from line 0: only its final state matters
                tst.b   v_ly.w
                bne.s   .lp
                move.b  $c1a6+G(a5),d7
                lsl.w   #8,d7
                move.b  $c1a5+G(a5),d7
                cmp.w   #$1bec,d7
                beq.s   .all
                cmp.w   #$1c1e,d7               ; (1BEC already taken at EI, pending HBlank)
                bne.s   .lp
.all:           move.b  $c654+G(a5),R_SCY(a5)   ; line 0
                move.b  $c779+G(a5),R_SCX(a5)
                bsr     hal_oam_dma             ; line 47
                move.b  #$92,R_BCPS(a5)         ; last gradient line
                move.b  #$b0,R_OCPS(a5)         ; line 53: OCPS $aa + 6 colours bytes
                sf      gb_ime.w                ; line 71: plain RET
                move.l  #sc_tab,sc_ptr.w        ; next handler 1BEC (set by line 70's handler)
                move.b  #$ec,$c1a5+G(a5)
                move.b  #$1b,$c1a6+G(a5)
                move.b  #72,v_ly.w
                addi.w  #4*72,div_cnt.w
                bset    #1,if_pend.w            ; (HBlanks after the chain end, IME off)
                bra.s   .no
.lp:            cmpi.b  #$48,v_ly.w
                bcc.s   .no                     ; lines 72+: generic
                tst.b   gb_ime.w
                beq.s   .pd                     ; (after the chain's last handler)
                movea.l sc_ptr.w,a0
                move.b  $c1a6+G(a5),d7
                lsl.w   #8,d7
                move.b  $c1a5+G(a5),d7
                cmp.w   (a0),d7
                bne.s   .no                     ; not the expected handler
                sf      gb_ime.w
                bsr     stat_native
                bra.s   .adv
.pd:            bset    #1,if_pend.w
.adv:           addq.b  #1,v_ly.w
                addq.w  #4,div_cnt.w
                bra.s   .lp
.no:            move.b  #2,v_phase.w
                rts
; batch of lines up to 143 whose HBlank handler is the plain 0:1AAC sky gradient
; (the handler's effects inline: line marker, colour, CA90 step; IME unchanged)
grad_batch::
                tst.b   gb_ime.w
                beq     .no
                tst.b   v_inirq.w
                bne     .no
                tst.b   hdma_on.w
                bne     .no
                btst    #1,R_IE(a5)
                beq     .no
                move.b  R_STAT(a5),d6
                andi.b  #$78,d6
                cmp.b   #$08,d6
                bne     .no
                cmpi.b  #$c3,$c1a4+G(a5)
                bne     .no
                cmpi.b  #$ac,$c1a5+G(a5)
                bne     .no
                cmpi.b  #$1a,$c1a6+G(a5)
                bne     .no
                move.b  $c1a0+G(a5),d6
                cmp.b   #$76,d6
                beq     .no
                cmp.b   #$78,d6
                beq     .no
                cmp.b   #$7b,d6
                beq     .no
.lp:            move.b  v_ly.w,d7
                cmp.b   #143,d7
                bcc     .no
                tst.b   rnd.w
                beq.s   .nl
                move.l  #LC_LINE<<24,d6
                move.b  d7,d6
                move.l  d6,(a6)+
                andi.b  #7,d7
                bne.s   .np
                PUBLISH d7
.np:            moveq   #0,d7
                move.b  $ca90+G(a5),d7
                bclr    #0,d7
                lea     $ca00+G(a5),a0
                adda.w  d7,a0
                move.b  1(a0),d7
                lsl.w   #8,d7
                move.b  (a0),d7
                moveq   #$47,d6
                bsr     grad_m
.nl:            move.b  #$b2,R_BCPS(a5)
                addq.b  #1,$ca90+G(a5)
                cmpi.b  #$90,$ca90+G(a5)
                bne.s   .nw
                clr.b   $ca90+G(a5)
.nw:            addq.b  #1,v_ly.w
                addq.w  #4,div_cnt.w
                cmpa.l  log_limit.w,a6
                bcs.s   .lp
                bsr     log_slow
                bra.s   .lp
.no:            move.b  #2,v_phase.w
                rts

; advance one visible line (0-142) when no STAT source but HBlank is enabled and no
; HBlank DMA runs: line marker + HBlank STAT handler (native when possible).
; Z=1: done, Z=0: the caller must use vadvance_line.
fast_line::
                move.b  v_ly.w,d7
                cmp.b   #143,d7
                bcc     .no
                tst.b   hdma_on.w
                bne     .no
                move.b  R_STAT(a5),d6
                andi.b  #$78,d6
                beq     .ok
                cmp.b   #$08,d6
                bne     .no
.ok:            tst.b   rnd.w
                beq     .nl
                move.l  d6,-(a7)
                move.l  #LC_LINE<<24,d6
                move.b  d7,d6
                move.l  d6,(a6)+
                move.l  (a7)+,d6
                andi.b  #7,d7
                bne     .nl
                PUBLISH d7
.nl:            tst.b   d6
                beq     .adv
                bset    #1,if_pend.w            ; (IF, taken now or later)
                tst.b   gb_ime.w
                beq     .adv
                tst.b   v_inirq.w
                bne     .adv
                btst    #1,R_IE(a5)
                beq     .adv
                bclr    #1,if_pend.w
                sf      gb_ime.w
                cmpi.b  #$c3,$c1a4+G(a5)
                bne     .girq
                move.b  $c1a6+G(a5),d7
                lsl.w   #8,d7
                move.b  $c1a5+G(a5),d7
                bsr     stat_native
                beq     .adv
.girq:          st      gb_ime.w                ; not native: the generic dispatch
                moveq   #2,d6
                bsr     irq_req
.adv:           addq.b  #1,v_ly.w
                move.b  #2,v_phase.w
                addq.w  #4,div_cnt.w
                cmpa.l  log_limit.w,a6
                bcs     .z
                bsr     log_slow
.z:             cmp.b   d7,d7
                rts
.no:            moveq   #1,d6
                rts
; advance visible lines until v_ly == d5.b (hal_wait_lyn) with the HBlank STAT
; handler resolved once (none, or native 1AAC / 1B13 / 1B4D, which keep C1A5).
; Stops at line 143, at the target, or does nothing when the conditions do not
; hold (the caller then uses vadvance_line). Leaves v_phase = 2.
fast_to::
                tst.b   hdma_on.w
                bne     .fx
                move.b  R_STAT(a5),d6
                andi.b  #$78,d6
                beq.s   .none
                cmp.b   #$08,d6
                bne     .fx
                btst    #1,R_IE(a5)
                beq     .fx                     ; (masked: pending IF, generic path)
                cmpi.b  #$c3,$c1a4+G(a5)
                bne     .fx
                move.b  $c1a6+G(a5),d7
                lsl.w   #8,d7
                move.b  $c1a5+G(a5),d7
                lea     hle_1aac,a0
                cmp.w   #$1aac,d7
                beq.s   .h
                lea     hle_1b13,a0
                cmp.w   #$1b13,d7
                beq.s   .h
                lea     hle_1b4d,a0
                cmp.w   #$1b4d,d7
                beq.s   .h
                lea     hle_1a73,a0
                cmp.w   #$1a73,d7
                beq.s   .h
                bra.s   .fx
.none:          suba.l  a0,a0
.h:             move.l  a0,ft_rout.w
.lp:            move.b  v_ly.w,d7
                cmp.b   #143,d7
                bcc.s   .fx
                tst.b   rnd.w
                beq.s   .nl
                move.l  #LC_LINE<<24,d6
                move.b  d7,d6
                move.l  d6,(a6)+
                andi.b  #7,d7
                bne.s   .nl
                PUBLISH d7
.nl:            move.l  ft_rout.w,d6
                beq.s   .adv
                tst.b   gb_ime.w
                beq.s   .pd
                tst.b   v_inirq.w
                bne.s   .pd
                bclr    #1,if_pend.w
                sf      gb_ime.w
                movea.l d6,a0
                jsr     (a0)
                bra.s   .adv
.pd:            bset    #1,if_pend.w
.adv:           addq.b  #1,v_ly.w
                addq.w  #4,div_cnt.w
                cmpa.l  log_limit.w,a6
                bcs.s   .ck
                bsr     log_slow
.ck:            cmp.b   v_ly.w,d5
                bne.s   .lp
.fx:             move.b  #2,v_phase.w
                rts

; road HDMA counters: GB registers <-> rh_src / rh_dst (the 68k source pointer is
; recomputed lazily: rh_valid)
rh_load::
                move.b  R_HDMA1(a5),d7
                lsl.w   #8,d7
                move.b  R_HDMA2(a5),d7
                andi.w  #$fff0,d7
                move.w  d7,rh_src.w
                move.b  R_HDMA3(a5),d7
                lsl.w   #8,d7
                move.b  R_HDMA4(a5),d7
                andi.w  #$1ff0,d7
                ori.w   #$8000,d7
                move.w  d7,rh_dst.w
                sf      rh_valid.w
                rts
rh_store::
                move.w  rh_src.w,d7
                move.b  d7,R_HDMA2(a5)
                lsr.w   #8,d7
                move.b  d7,R_HDMA1(a5)
                move.w  rh_dst.w,d7
                move.b  d7,R_HDMA4(a5)
                lsr.w   #8,d7
                andi.b  #$1f,d7
                move.b  d7,R_HDMA3(a5)
                rts

; MBC state := local bank d3
rd_sync::
                move.b  d3,d7
                st      cur_bank.w
                bra     mbc_bank

; d7.b := GB byte at d6.w (ROM0 / ROMX local bank / other), d6 += 1
rd8::
                cmp.w   #$4000,d6
                bcs.s   .f
                cmp.w   #$8000,d6
                bcc.s   .g
                move.b  (a4,d6.w),d7
                addq.w  #1,d6
                rts
.f:             move.b  (a5,d6.w),d7
                addq.w  #1,d6
                rts
.g:             cmp.w   #$c000,d6
                bcs.s   .gg
                cmp.w   #$d000,d6
                bcs.s   .f
                cmp.w   #$e000,d6
                bcc.s   .gg
                move.b  (a3,d6.w),d7
                addq.w  #1,d6
                rts
.gg:            bsr     gb_rd
                addq.w  #1,d6
                rts

; road palette pointer from other tables than the WRAM0 one (d5 = row) -> d0.l 68k address
rd_ppg::
                moveq   #0,d6                   ; palette pointer
                move.b  $ff99+G(a5),d6
                lsl.w   #8,d6
                move.b  $ff98+G(a5),d6
                tst.b   $ff97+G(a5)
                bne.s   .vb
                add.w   d5,d6                   ; word at (FF98) + 2*row
                add.w   d5,d6
                cmp.w   #$4000,d6
                bcc.s   .ptx
                move.b  1(a5,d6.w),d0
                lsl.w   #8,d0
                move.b  (a5,d6.w),d0
                bra.s   .cv
.ptx:           cmp.w   #$8000,d6
                bcc.s   .pgen
                lea     (a4,d6.w),a0
.prx:           move.b  1(a0),d0
                lsl.w   #8,d0
                move.b  (a0),d0
                bra.s   .cv
.pgen:          lea     (a5,d6.w),a0             ; WRAM tables: direct
                cmp.w   #$c000,d6
                bcs.s   .pg2
                cmp.w   #$d000,d6
                bcs.s   .prx
                lea     (a3,d6.w),a0
                cmp.w   #$e000,d6
                bcs.s   .prx
.pg2:           bsr     rd8
                move.b  d7,d2
                bsr     rd8
                lsl.w   #8,d7
                move.b  d2,d7
                move.w  d7,d0
                bra.s   .cv
.vb:            move.w  d5,d7                   ; (FF98) + 8*row
                lsl.w   #3,d7
                add.w   d7,d6
                move.w  d6,d0
; d0.w = GB address of the 8 palette bytes -> d0.l = 68k address (bank (FF9A))
.cv:            cmp.w   #$4000,d0
                bcc.s   .cvx
                lea     (a5,d0.w),a0
                move.l  a0,d0
                rts
.cvx:           move.b  $ff9a+G(a5),d7
                andi.w  #$3f,d7
                add.w   d7,d7
                add.w   d7,d7
                lea     bank_base.w,a0
                movea.l (a0,d7.w),a0
                adda.w  d0,a0
                move.l  a0,d0
                rts

; line 73+n is drawn, its HBlank DMA block is copied, LY advances
rd_adv::
                tst.b   gb_ime.w
                bne.s   rd_slow
                tst.b   rnd.w
                beq.s   .nl
                move.l  #LC_LINE<<24,d7
                move.b  v_ly.w,d7
                tst.b   rl_rend.w               ; (rendered by the last LC_ROADLN)
                bne.s   .rr
                move.l  d7,(a6)+
.rr:            sf      rl_rend.w
                andi.b  #7,d7
                bne.s   .nl
                PUBLISH d7
.nl:            bsr     rd_hdma16
                addq.b  #1,v_ly.w               ; (v_phase, DIV: at the end of the road)
                cmpa.l  log_limit.w,a6
                bcc     log_slow
                rts
rd_slow::
.slow:          sf      rl_rend.w
                bsr     rd_sync                 ; interrupts may run GB code: real MBC state
                bsr     rh_store
                move.b  #$80,d7
                move.w  #$ff55,d6
                bsr     io_w_hdma5
                bsr     vadvance_line
                bra     rh_load

; one 16-byte HDMA block rh_src -> rh_dst (VRAM bank 1), counters advanced
rd_hdma16::
                tst.b   strm.w
                beq     .skp                     ; tiles not needed by the next frame
                tst.b   rh_valid.w
                bne.s   .v
                move.w  rh_src.w,d7
                bsr     src_ptr
                move.l  a0,rh_ptr.w
                st      rh_valid.w
.v:             movea.l rh_ptr.w,a0
                move.w  rh_dst.w,d6
                lea     (a2,d6.w),a1
                move.b  #LC_BLOCK,(a6)+
                move.b  vbk_cur.w,(a6)+
                move.w  d6,(a6)+
                moveq   #16,d1
                move.l  d1,(a6)+
                move.l  (a0)+,d1
                move.l  d1,(a1)+
                move.l  d1,(a6)+
                move.l  (a0)+,d1
                move.l  d1,(a1)+
                move.l  d1,(a6)+
                move.l  (a0)+,d1
                move.l  d1,(a1)+
                move.l  d1,(a6)+
                move.l  (a0)+,d1
                move.l  d1,(a1)+
                move.l  d1,(a6)+
.adv:           addi.l  #16,rh_ptr.w
                addi.w  #16,rh_src.w
                addi.w  #16,d6
                andi.w  #$1ff0,d6
                ori.w   #$8000,d6
                move.w  d6,rh_dst.w
                rts
.skp:           sf      rh_valid.w              ; (pointer recomputed when streaming resumes)
                addi.w  #16,rh_src.w
                move.w  rh_dst.w,d6
                addi.w  #16,d6
                andi.w  #$1ff0,d6
                ori.w   #$8000,d6
                move.w  d6,rh_dst.w
                rts



; ---------------------------------------------------------------------------
; Infogrames logo (scene 0:01ED, before the LCD is switched on): remove the
; "Licensed by Nintendo" text = BG map rows 14-17, columns 5-14 -> blank tile $C8
; ---------------------------------------------------------------------------
hal_nolicense::
                movem.l d0-d2,-(a7)
                lea     VRAM68+$1800+(14*32)+5,a0
                cmpi.b  #$5a,(a0)
                bne.s   .nx
                cmpi.b  #$7f,105(a0)             ; row 17, column 14
                bne.s   .nx
                move.l  #$9800+(14*32)+5,d1
                moveq   #3,d2
.rw:            moveq   #9,d0
.cl:            move.b  #$c8,(a0)
                clr.b   $2000(a0)
                addq.l  #1,a0
                move.b  #LC_VRAM0,(a6)+
                move.b  #$c8,(a6)+
                move.w  d1,(a6)+
                move.b  #LC_VRAM1,(a6)+
                clr.b   (a6)+
                move.w  d1,(a6)+
                addq.w  #1,d1
                dbra    d0,.cl
                lea     22(a0),a0
                addi.w  #22,d1
                dbra    d2,.rw
                cmpa.l  log_limit.w,a6
                bcs.s   .nx
                bsr     log_slow
.nx:            movem.l (a7)+,d0-d2
                rts
