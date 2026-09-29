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
                move.b  #LC_OBPAL,(a6)+
                move.b  d7,(a6)+
                move.w  d6,(a6)+
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
                st      grad_last.w
                move.b  #LC_PAL,(a6)+
                move.b  d6,(a6)+
                clr.w   (a6)+
                andi.w  #15,d6
                lsl.w   #3,d6
                lea     bgpal_raw.w,a1          ; (obpal_raw follows)
                adda.w  d6,a1
                move.w  a0,d7
                btst    #0,d7
                bne.s   .odd
                move.l  (a0)+,d7
                move.l  d7,(a1)+
                move.l  d7,(a6)+
                move.l  (a0)+,d7
                move.l  d7,(a1)+
                move.l  d7,(a6)+
                bra.s   .ck
.odd:           moveq   #7,d7
.c:             move.b  (a0),(a1)+
                move.b  (a0)+,(a6)+
                dbra    d7,.c
.ck:            cmpa.l  log_limit.w,a6
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
                move.w  d7,(a6)+
                lea     bgpal_raw.w,a0
.gl:             lsr.b   #1,d6
                bcc.s   .gn
                move.b  d7,(a0)
                ror.w   #8,d7
                move.b  d7,1(a0)
                ror.w   #8,d7
.gn:             addq.l  #8,a0
                tst.b   d6
                bne.s   .gl
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
.bb:             move.b  (a1)+,d7
                move.w  d6,-(a7)
                bsr     ob_byte
                move.w  (a7)+,d6
                addq.b  #1,d6
                andi.b  #$3f,d6
                subq.b  #1,d5
                bne.s   .bb
                ori.b   #$80,d6
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
.go:            move.b  cur_bank.w,d3
                bsr     rh_load
                moveq   #0,d4                   ; n
.line:          btst    #0,d4
                bne.s   .odd
                bsr     rd_even
                bra.s   .row
.odd:           bsr     rd_odd
.row:           bsr     rd_row
                addq.b  #1,d4
                cmp.b   #70,d4
                bne.s   .line
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

; advance the virtual PPU to LY = 73. Lines 0-72 whose only STAT source is HBlank
; (the race HUD chain) take a fast path: line marker + native STAT handler.
rd_wait73::
.lp:            cmpi.b  #$49,v_ly.w
                beq.s   .dn
                bsr     chain_nodraw
                bsr     fast_line
                beq.s   .lp
                bsr     vadvance_line
                bra.s   .lp
.dn:            rts

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

; even line (0:38DC): object descriptor C655+n/2
rd_even::
                moveq   #0,d7
                move.b  d4,d7
                lsr.b   #1,d7
                lea     $c655+G(a5),a1
                move.b  (a1,d7.w),d5
                bmi.s   .new
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
                bsr     rd8
                move.b  d7,$ff8b+G(a5)
                bsr     rd8
                move.b  d7,$ff8c+G(a5)
                rts
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
                rts

; odd line (0:3988): OAM buffer entry C000+4*(n/2) from the current object
rd_odd::
                move.b  d4,$ff8e+G(a5)
                moveq   #0,d7
                move.b  $ff8a+G(a5),d7
                lea     $c600+G(a5),a1
                adda.w  d7,a1
                move.b  (a1),d7
                FBANK
                moveq   #0,d6
                move.b  d4,d6
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
                rts

; line part: C6[n] = road row + 1 (0 = sky), cleared
rd_row::
                move.b  #$80,R_BCPS(a5)
                moveq   #0,d7
                move.b  d4,d7
                lea     $c600+G(a5),a1
                adda.w  d7,a1
                moveq   #0,d5
                move.b  (a1),d5
                clr.b   (a1)
                tst.b   d5
                beq     .sky
                subq.b  #1,d5                   ; row
                tst.b   rnd.w
                beq     .pp                     ; undrawn: no palette pointer
                moveq   #0,d6                   ; palette pointer
                move.b  $ff99+G(a5),d6
                lsl.w   #8,d6
                move.b  $ff98+G(a5),d6
                tst.b   $ff97+G(a5)
                bne.s   .vb
                add.w   d5,d6                   ; word at (FF98) + 2*row
                add.w   d5,d6
                cmp.w   #$8000,d6
                bcc.s   .pgen
                lea     (a4,d6.w),a0
                cmp.w   #$4000,d6
                bcc.s   .prx
                lea     (a5,d6.w),a0
.prx:           move.b  1(a0),d0
                lsl.w   #8,d0
                move.b  (a0),d0
                bra.s   .pp
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
                bra.s   .pp
.vb:            move.w  d5,d7                   ; (FF98) + 8*row
                lsl.w   #3,d7
                add.w   d7,d6
                move.w  d6,d0
.pp:            bsr     rd_adv
                move.b  #$3e,d7                 ; SCY = row + $3E - n
                sub.b   d4,d7
                add.b   d5,d7
                move.b  d7,R_SCY(a5)
                lea     $c700+G(a5),a1          ; SCX = C700[row]
                move.b  (a1,d5.w),d6
                move.b  d6,R_SCX(a5)
                tst.b   rnd.w
                beq.s   .nd
                move.b  #LC_ROADLN,(a6)+         ; the GPU reads BG palette 0 itself
                move.b  d7,(a6)+
                clr.b   (a6)+
                move.b  d6,(a6)+
                move.b  $ff9a+G(a5),d7          ; 8 bytes at d0 in bank (FF9A)
                FBANK
                lea     (a4,d0.w),a0
                cmp.w   #$4000,d0
                bcc.s   .rx
                lea     (a5,d0.w),a0
.rx:            move.l  a0,(a6)+
                move.l  a0,rl_pal.w
                move.b  #$88,R_BCPS(a5)
                rts
.nd:            move.b  $ff9a+G(a5),d7          ; undrawn frame: GB state only
                FBANK
                move.b  #$88,R_BCPS(a5)
                rts
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
                bra     grad3

; line 73+n is drawn, its HBlank DMA block is copied, LY advances
rd_adv::
                tst.b   gb_ime.w
                bne.s   rd_slow
                tst.b   rnd.w
                beq.s   .nl
                move.l  #LC_LINE<<24,d7
                move.b  v_ly.w,d7
                move.l  d7,(a6)+
                andi.b  #7,d7
                bne.s   .nl
                PUBLISH d7
.nl:            bsr     rd_hdma16
                addq.b  #1,v_ly.w
                move.b  #2,v_phase.w
                addq.w  #4,div_cnt.w
                cmpa.l  log_limit.w,a6
                bcc     log_slow
                rts
rd_slow::
.slow:          bsr     rd_sync                 ; interrupts may run GB code: real MBC state
                bsr     rh_store
                move.b  #$80,d7
                move.w  #$ff55,d6
                bsr     io_w_hdma5
                bsr     vadvance_line
                bra     rh_load

; one 16-byte HDMA block rh_src -> rh_dst (VRAM bank 1), counters advanced;
; an unchanged block (streamed images repeat) is not copied
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
                move.l  (a0),d1
                cmp.l   (a1),d1
                bne.s   .cp
                move.l  4(a0),d1
                cmp.l   4(a1),d1
                bne.s   .cp
                move.l  8(a0),d1
                cmp.l   8(a1),d1
                bne.s   .cp
                move.l  12(a0),d1
                cmp.l   12(a1),d1
                beq.s   .adv
.cp:            move.b  #LC_BLOCK,(a6)+
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
