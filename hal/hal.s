; ---------------------------------------------------------------------------
; Wacky Races (Jaguar) - 68000 hardware abstraction layer for the recompiled
; GB code. Register model: see recomp68.py.
; Routines called from translated code may only destroy d6, d7, a0, a1 and CCR
; (d5 must survive: the translator keeps a saved carry in it).
; ---------------------------------------------------------------------------

IO              equ     -$100           ; (a5) offset of GB $ff00
R_P1            equ     IO+$00
R_LCDC          equ     IO+$40
R_STAT          equ     IO+$41
R_SCY           equ     IO+$42
R_SCX           equ     IO+$43
R_LY            equ     IO+$44
R_LYC           equ     IO+$45
R_HDMA1         equ     IO+$51
R_HDMA2         equ     IO+$52
R_HDMA3         equ     IO+$53
R_HDMA4         equ     IO+$54
R_HDMA5         equ     IO+$55
R_BCPS          equ     IO+$68
R_OCPS          equ     IO+$6a
R_IE            equ     -1

                .text
                .68000

; ===========================================================================
; boot (linked at $4000, copied there from the cartridge by the ROM stub)
; ===========================================================================
start::
                move.w  #$2700,sr
                lea     BOOTSTACK,a7
                move.l  #0,G_CTRL
                move.l  #0,D_CTRL
                move.l  #$00070007,G_END
                move.l  #$00070007,D_END
                move.w  #$100,JOYSTICK          ; mute off? (bit 8 = audio enable)

                ; clear variables and big buffers
                lea     VARS,a0
                move.w  #($3000-VARS)/4-1,d0
.cv:            clr.l   (a0)+
                dbra    d0,.cv
                lea     FLAT,a0
                move.l  #(RAMEND-FLAT)/16-1,d0
                moveq   #0,d1
.cb:            move.l  d1,(a0)+
                move.l  d1,(a0)+
                move.l  d1,(a0)+
                move.l  d1,(a0)+
                subq.l  #1,d0
                bpl.s   .cb

                ; GPU tables: GB colour -> RGB16 (r << 11 | b << 6 | g on 6 bits)
                lea     CTAB,a0
                moveq   #0,d0
.ct:            move.w  d0,d1
                andi.w  #31,d1
                ror.w   #5,d1                   ; r << 11
                move.w  d0,d2
                lsr.w   #4,d2
                andi.w  #$7c0,d2                ; b << 6
                or.w    d2,d1
                move.w  d0,d2
                lsr.w   #5,d2
                andi.w  #31,d2
                move.w  d2,d3
                add.w   d2,d2
                lsr.w   #4,d3
                or.w    d3,d2                   ; g: 5 -> 6 bits
                or.w    d2,d1
                move.w  d1,(a0)+
                addq.w  #1,d0
                bpl.s   .ct
                ; decoded maps of an empty VRAM: tile 0 (LCDC.4 = 0: at $9000), palette 0
                lea     DMAP,a0
                move.l  #(GCHK+$1000)<<11,d1
                moveq   #1,d2
.dm:            move.w  #$4000/4-1,d0
.dl:            move.l  d1,(a0)+
                dbra    d0,.dl
                move.l  #GCHK<<11,d1
                dbra    d2,.dm

                ; sound effects instance of the sound engine (snd_fx in hle.s): its RAM
                ; and registers, engine on, sequencer off
                lea     SDRV,a0
                move.w  #(SNDB+48-SDRV)/4-1,d0
.cs:            clr.l   (a0)+
                dbra    d0,.cs
                move.b  #$ff,SDRV+$b0.w         ; (C300: engine on)
                move.b  #$80,SDRV+$bd.w         ; (C30D: no music)

                bsr     init_video
                bsr     init_gpu
                bsr     init_dsp

                ; object list + video interrupt
                move.l  #FB0,disp_fb.w
                bsr     build_op
                move.l  #OPLIST+16,d0
                swap    d0
                move.l  d0,OLP
                move.l  #vbl_isr,LEVEL0
                move.w  a_vde.w,d0
                ori.w   #1,d0
                move.w  d0,VI
                .if     PROFILE
                move.w  #25,PIT0                ; 26.6MHz / (26*102) ~ 10kHz
                move.w  #101,PIT1
                move.w  #C_VIDENA|C_PITENA,INT1
                .else
                move.w  #C_VIDENA,INT1
                .endif
                move.w  #$2c7,VMODE             ; RGB16, CSYNC, BGEN, PWIDTH2 (high resolution), VIDEN
                move.w  #$2000,sr               ; enable interrupts

                ; GB memory: ROM bank 0 into the flat image
                lea     gbrom,a0
                lea     FLAT_MID,a1
                move.w  #$4000/4-1,d0
.cr:            move.l  (a0)+,(a1)+
                dbra    d0,.cr

                lea     FLAT_MID,a5
                lea     VRAM68+$8000,a2
                lea     WRAMX+$1000+$3000,a3
                move.b  #1,svbk_cur.w
                lea     bank_base.w,a0
                move.l  #gbrom-$4000,d0
                moveq   #63,d1
.bb:            move.l  d0,(a0)+
                addi.l  #$4000,d0
                dbra    d1,.bb
                moveq   #1,d7
                bsr     mbc_bank
                lea     LOGBUF,a6
                PUBLISH d0
                bsr     log_slow                ; computes log_limit
                move.l  #sc_tab,sc_ptr.w
                st      rnd.w
                st      strm.w
                st      rnd.w
                st      strm.w

                ; GB IO state after the CGB boot ROM
                move.b  #$cf,R_P1(a5)
                move.b  #$91,R_LCDC(a5)
                move.b  #$85,R_STAT(a5)
                move.b  #$fc,IO+$47(a5)
                move.b  #$e1,IO+$0f(a5)
                move.b  #$f9,IO+$70(a5)
                move.b  #$fe,IO+$4f(a5)
                clr.b   R_IE(a5)
                move.b  #$91,d7
                move.w  #$ff40,d6
                bsr     log_reg
                clr.b   v_ly.w
                move.b  #2,v_phase.w
                sf      gb_ime.w

                ; CPU state after the CGB boot ROM (A=$11 selects CGB mode)
                lea     -2(a5),a7               ; SP = $fffe
                move.l  #$11,d0
                moveq   #0,d1
                move.l  #$ff56,d2
                moveq   #$0d,d3
                moveq   #0,d4
                moveq   #0,d5
                move    #$04,ccr                ; Z=1
                jmp     g_00_0100

; ---------------------------------------------------------------------------
; video
; ---------------------------------------------------------------------------
init_video:
                move.w  CONFIG,d0
                andi.w  #VIDTYPE,d0
                beq.s   .pal
                move.w  #1,ntsc.w
                move.w  #NTSC_HMID,d2
                move.w  #NTSC_WIDTH,d0
                move.w  #NTSC_VMID,d6
                move.w  #NTSC_HEIGHT,d4
                bra.s   .calc
.pal:           clr.w   ntsc.w
                move.w  #PAL_HMID,d2
                move.w  #PAL_WIDTH,d0
                move.w  #PAL_VMID,d6
                move.w  #PAL_HEIGHT,d4
.calc:          move.w  d4,a_height.w
                move.w  d0,d1
                lsr.w   #1,d1
                move.w  d1,a_width.w            ; (pixels 2 clocks wide)
                move.w  d0,d1
                asr.w   #1,d1
                sub.w   d1,d2
                addq.w  #4,d2
                subq.w  #1,d1
                ori.w   #$400,d1
                move.w  d1,HDE
                move.w  d2,HDB1
                move.w  d2,HDB2
                move.w  d6,d5
                sub.w   d4,d5
                move.w  d5,a_vdb.w
                add.w   d4,d6
                move.w  d6,a_vde.w
                move.w  d5,VDB
                move.w  #$ffff,VDE              ; (as Atari's startup code: the branch objects of the list stop the OP)
                move.l  #0,BORD1
                move.w  #0,BG
                ; (falls into scr_calc)

; size and place the picture: the whole height of the screen, all 144 lines visible (NTSC:
; 234 lines, x1.625; PAL: 279 lines, x1.94) or the TV safe area (scr_safe, keypad #: NTSC 225 lines, PAL 270), 10:9
; (pixels 2 clocks wide: NTSC x3.56 = 570 pixels, PAL x3.47 = 555) or the whole width
; (scr_wide, keypad *)
scr_calc:
                movem.l d0-d1,-(a7)
                moveq   #62,d0                  ; vertical scale (3.5 fixed point)
                moveq   #111,d1                 ; horizontal scale (10:9)
                tst.b   scr_safe.w
                beq.s   .pfull
                moveq   #60,d0
                moveq   #108,d1
.pfull:         tst.w   ntsc.w
                beq.s   .pal
                moveq   #52,d0
                moveq   #114,d1
                tst.b   scr_safe.w
                beq.s   .pal
                moveq   #50,d0
                moveq   #109,d1
.pal:           tst.b   scr_wide.w
                beq.s   .asp
                moveq   #0,d1                   ; full width: a_width / 5 (* 32 / 160)
                move.w  a_width.w,d1
                divu    #5,d1
.asp:           move.b  d0,scr_vs.w
                move.b  d1,scr_hs.w
                mulu    #144,d0
                lsr.l   #5,d0                   ; picture lines
                neg.w   d0
                add.w   a_height.w,d0           ; lines left (3 kept for the edges of the
                subq.w  #3,d0                   ;  visible area): as many half-lines above
                bpl.s   .yp
                moveq   #0,d0
.yp:            andi.w  #$fffe,d0
                add.w   a_vdb.w,d0
                move.w  d0,scr_y.w
                andi.l  #$ff,d1
                mulu    #160,d1
                lsr.l   #5,d1                   ; picture width
                neg.w   d1
                add.w   a_width.w,d1
                asr.w   #1,d1
                bpl.s   .xp
                moveq   #0,d1
.xp:            move.w  d1,scr_x.w
                movem.l (a7)+,d0-d1
                rts

; object list (as Atari's startup code: VDE = $ffff, the list itself stops the OP outside the
; display): OPLIST+16 branch (VC > a_vde -> stop), +24 branch (VC < a_vdb -> stop), +32 scaled
; bitmap (160x144 RGB16, scr_* placement; 32-byte aligned), [+64 HUD], stop
OP_STOP         equ     OPLIST+64+(HUD*32)
build_op:
                movem.l d0-d2/a0,-(a7)
                lea     OPLIST+16,a0
                move.l  #OP_STOP>>11,(a0)+      ; branch: link (high bits)
                move.w  a_vde.w,d0
                andi.l  #$7ff,d0
                lsl.l   #3,d0
                ori.l   #(((OP_STOP>>3)&$ff)<<24)|(2<<14)|BRANCHOBJ,d0   ; YPOS < VC
                move.l  d0,(a0)+
                move.l  #OP_STOP>>11,(a0)+
                move.w  a_vdb.w,d0
                andi.l  #$7ff,d0
                lsl.l   #3,d0
                ori.l   #(((OP_STOP>>3)&$ff)<<24)|(1<<14)|BRANCHOBJ,d0   ; YPOS > VC
                move.l  d0,(a0)+
                move.l  disp_fb.w,d0
                addi.l  #FB_LEFT,d0             ; (the framebuffers are 176 pixels wide)
                lsr.l   #3,d0
                moveq   #11,d1
                lsl.l   d1,d0                   ; data << 11
                move.l  #(OPLIST+64)>>3,d1      ; link
                move.l  d1,d2
                lsr.l   #8,d2
                or.l    d2,d0
                move.l  d0,(a0)+                ; phrase 0 high
                andi.l  #$ff,d1
                ror.l   #8,d1                   ; link low 8 bits -> 31..24
                move.l  #FB_H<<14,d0
                or.l    d0,d1
                move.w  scr_y.w,d0
                andi.l  #$7ff,d0
                lsl.l   #3,d0
                or.l    d0,d1
                or.l    #SCBITOBJ,d1
                move.l  d1,(a0)+                ; phrase 0 low
                ; phrase 1: iwidth(40) >> 4 in high; low: xpos, depth 4, pitch 1, dwidth 44, iwidth low 4 bits
                move.l  #(40>>4),(a0)+
                move.w  scr_x.w,d0
                andi.l  #$fff,d0
                ori.l   #(4<<12)|(1<<15)|((FB_PITCH/8)<<18)|((40&15)<<28),d0
                move.l  d0,(a0)+
                ; phrase 2: hscale, vscale, remainder (3.5 fixed)
                clr.l   (a0)+
                moveq   #0,d0
                move.b  scr_vs.w,d0
                move.l  d0,d1
                swap    d1                      ; remainder = vscale
                lsl.l   #8,d0
                or.l    d1,d0
                move.b  scr_hs.w,d0
                move.l  d0,(a0)+
                clr.l   (a0)+
                clr.l   (a0)+
                .if     HUD
                ; debug HUD: 64x12 RGB16 bitmap at the top left (x2), then the stop object
                move.l  #(HUDBUF>>3)<<11,d0
                move.l  #(OPLIST+96)>>3,d1
                move.l  d1,d2
                lsr.l   #8,d2
                or.l    d2,d0
                move.l  d0,(a0)+
                andi.l  #$ff,d1
                ror.l   #8,d1
                move.w  a_vdb.w,d0
                addi.w  #16,d0
                andi.l  #$7ff,d0
                lsl.l   #3,d0
                or.l    d0,d1
                or.l    #(12<<14)|SCBITOBJ,d1
                move.l  d1,(a0)+                ; scaled, height 12
                move.l  #(16>>4),(a0)+
                move.l  #16|(4<<12)|(1<<15)|(16<<18)|((16&15)<<28),(a0)+
                clr.l   (a0)+
                move.l  #64|(64<<8)|(64<<16),(a0)+
                clr.l   (a0)+
                clr.l   (a0)+
                .endif
                ; stop object
                clr.l   (a0)+
                move.l  #STOPOBJ,(a0)+
                movem.l (a7)+,d0-d2/a0
                rts

                .if     HUD
; once a second: GB frames and drawn frames of the last second (60 = full speed)
hud_tick:
                subq.w  #1,hud_cnt.w
                bgt.s   .hx
                move.w  #60,hud_cnt.w
                movem.l d3-d5/a1,-(a7)
                move.l  frames.w,d0
                move.l  d0,d1
                sub.l   hud_f0.w,d1
                move.l  d0,hud_f0.w
                move.l  fsent.w,d0
                move.l  d0,d2
                sub.l   hud_s0.w,d2
                move.l  d0,hud_s0.w
                lea     HUDBUF,a0               ; clear 64x12x2
                move.w  #(64*12*2)/4-1,d0
.cl:            clr.l   (a0)+
                dbra    d0,.cl
                moveq   #0,d3                   ; x
                move.l  d1,d0
                bsr.s   hud_num
                moveq   #32,d3
                move.l  d2,d0
                bsr.s   hud_num
                movem.l (a7)+,d3-d5/a1
.hx:            rts
; two digits of d0 (0-99) at pixel column d3
hud_num:
                cmp.l   #99,d0
                bls.s   .ok
                moveq   #99,d0
.ok:            divu    #10,d0
                move.l  d0,d4
                swap    d4                      ; units
                bsr.s   hud_dig
                addq.w  #8,d3
                move.w  d4,d0
; digit d0 at column d3: 3x5 font, pixels doubled
hud_dig:
                lea     hud_font(pc),a1
                mulu    #5,d0
                adda.w  d0,a1
                lea     HUDBUF+(64*2)+2,a0
                adda.w  d3,a0
                adda.w  d3,a0
                moveq   #4,d5
.row:           move.b  (a1)+,d0
                moveq   #2,d1
.px:            btst    d1,d0
                beq.s   .pz
                move.l  #$ffffffff,(a0)
                move.l  #$ffffffff,64*2(a0)
.pz:            addq.l  #4,a0
                dbra    d1,.px
                lea     244(a0),a0          ; next pixel row pair: 2*128 - 12
                dbra    d5,.row
                rts
hud_font:       dc.b    7,5,5,5,7, 2,6,2,2,7, 7,1,7,4,7, 7,1,3,1,7, 5,5,7,1,1
                dc.b    7,4,7,1,7, 7,4,7,5,7, 7,1,1,1,1, 7,5,7,5,7, 7,5,7,1,7
                .even
                .endif

; a7 is the GB stack: only the exception frame goes there (the GB game keeps data
; right below its stack, e.g. the race's OAM buffer below $C100); the ISR has its own
vbl_isr:
                move.l  a7,isr_sp.w
                lea     ISRSTACK,a7
                movem.l d0-d2/a0,-(a7)
                .if     PROFILE
                move.w  INT1,d0
                btst    #3,d0
                beq.s   .nopit
                movea.l isr_sp.w,a0
                move.l  2(a0),d1                ; interrupted PC
                sub.l   #$4000,d1
                bcs.s   .pa
                cmp.l   #PROF_SPAN,d1
                bcc.s   .pa
                lsr.l   #2,d1
                bclr    #0,d1
                lea     PROFBUF,a0
                addq.w  #1,(a0,d1.l)
.pa:            move.w  #C_VIDENA|C_PITENA|C_PITCLR,INT1
                move.w  #0,INT2
                btst    #0,d0
                bne.s   .nopit
                movem.l (a7)+,d0-d2/a0
                movea.l isr_sp.w,a7
                rte
.nopit:
                .endif
                moveq   #0,d0                   ; the frame the GPU published last (1-3: FB0-FB2,
                move.w  G_DISP+2,d0             ; one word: never torn)
                beq.s   .nd
                move.w  d0,G_SHOWN+2            ; (from now on the OP shows it: the GPU keeps off)
                addi.w  #$11,d0
                swap    d0
                move.l  d0,disp_fb.w
.nd:            bsr     build_op
                bsr     read_pad
                move.l  joy_raw.w,d0            ; keypad *: 10:9 picture / full width
                move.l  key_prev.w,d1
                move.l  d0,key_prev.w
                not.l   d1
                and.l   d1,d0
                btst    #KEY_STAR,d0
                beq.s   .nk
                not.b   scr_wide.w
                bsr     scr_calc
.nk:            btst    #KEY_HASH,d0            ; keypad #: whole height / TV safe area
                beq.s   .nh
                not.b   scr_safe.w
                bsr     scr_calc
.nh:
                .if     HUD
                bsr     hud_tick
                .endif
                addq.l  #1,vbl_count.w
                .if     PROFILE
                move.w  #C_VIDCLR|C_VIDENA|C_PITENA,INT1
                .else
                move.w  #C_VIDCLR|C_VIDENA,INT1
                .endif
                move.w  #0,INT2
                movem.l (a7)+,d0-d2/a0
                movea.l isr_sp.w,a7
                rte

; joypad 1 -> joy_dir / joy_btn (GB bits, active high)
read_pad:
                move.l  #$f0fffffc,d1
                moveq   #-1,d2
                move.w  #$81fe,JOYSTICK
                move.l  JOYSTICK,d0
                or.l    d1,d0
                ror.l   #4,d0
                and.l   d0,d2
                move.w  #$81fd,JOYSTICK
                move.l  JOYSTICK,d0
                or.l    d1,d0
                ror.l   #8,d0
                and.l   d0,d2
                move.w  #$81fb,JOYSTICK
                move.l  JOYSTICK,d0
                or.l    d1,d0
                rol.l   #6,d0
                rol.l   #6,d0
                and.l   d0,d2
                move.w  #$81f7,JOYSTICK
                move.l  JOYSTICK,d0
                or.l    d1,d0
                rol.l   #8,d0
                and.l   d0,d2
                not.l   d2
                move.l  d2,joy_raw.w
                moveq   #0,d0
                btst    #JOY_RIGHT,d2
                beq.s   .1
                bset    #0,d0
.1:             btst    #JOY_LEFT,d2
                beq.s   .2
                bset    #1,d0
.2:             btst    #JOY_UP,d2
                beq.s   .3
                bset    #2,d0
.3:             btst    #JOY_DOWN,d2
                beq.s   .4
                bset    #3,d0
.4:
                .if     ALLDRAW=3               ; (tests: scheduled joypad, see frame_end)
                rts
                .endif
                move.b  d0,joy_dir.w
                moveq   #0,d0
                btst    #FIRE_B,d2              ; GB A = Jaguar B or C
                bne.s   .a
                btst    #FIRE_C,d2
                beq.s   .5
.a:             bset    #0,d0
.5:             btst    #FIRE_A,d2              ; GB B = Jaguar A
                beq.s   .6
                bset    #1,d0
.6:             btst    #OPTION,d2              ; select
                beq.s   .7
                bset    #2,d0
.7:             btst    #PAUSE,d2               ; start
                beq.s   .8
                bset    #3,d0
.8:             move.b  d0,joy_btn.w
                rts

; ---------------------------------------------------------------------------
; GPU: copy the renderer into GPU RAM and start it
; ---------------------------------------------------------------------------
init_gpu:
                lea     gpu_code,a0
                lea     G_RAM,a1
                move.w  #(gpu_code_end-gpu_code)/4,d0
.c:             move.l  (a0)+,(a1)+
                dbra    d0,.c
                lea     TBASE,a1                ; GPU tables (see gpu.s)
                move.w  #(TEND-TBASE)/4-1,d0
.ct:            clr.l   (a1)+
                dbra    d0,.ct
                lea     KMASK,a1                ; pixel pair (a, b): what an OBJ keeps of the
                moveq   #-1,d0                  ; picture (colour 0 = transparent)
                move.l  d0,(a1)+
                move.l  #$ffff0000,d0
                move.l  d0,(a1)+
                move.l  d0,(a1)+
                move.l  d0,(a1)+
                moveq   #2,d0
.km:            move.l  #$0000ffff,(a1)+
                clr.l   (a1)+
                clr.l   (a1)+
                clr.l   (a1)+
                dbra    d0,.km
                move.l  #SPL,SPEND
                move.l  #1,SPDIRTY
                clr.l   G_HEAD
                clr.l   G_TAIL
                clr.l   G_DISP
                clr.l   G_FRAMES
                move.l  #1,G_SHOWN              ; (FB0 is shown at boot)
                move.l  #gpu_start,G_PC
                move.l  #RISCGO,G_CTRL
                rts

; ===========================================================================
; control flow
; ===========================================================================
; ret: pop a GB address and jump to its translation (flags preserved)
gb_ret::
                move    sr,d6
                moveq   #0,d7
                move.w  (a7)+,d7
                bra.s   disp
; jump to the GB address in a0.w (flags preserved)
gb_jump::
                move    sr,d6
                moveq   #0,d7
                move.w  a0,d7
disp:           move.w  d7,last_target.w
                cmp.w   #$4000,d7
                bcc.s   .hi
                add.w   d7,d7
                add.w   d7,d7
                lea     dtab_00,a0
                movea.l (a0,d7.l),a0
                move    d6,ccr
                jmp     (a0)
.hi:            cmp.w   #$8000,d7
                bcc.s   ram_jump
                add.l   d7,d7
                add.l   d7,d7
                movea.l cur_dtab.w,a0
                movea.l (a0,d7.l),a0
                move    d6,ccr
                jmp     (a0)
; jump into GB RAM: sentinel (back to the HAL) or "jp nnnn" stubs ($c1a4, $c6af...)
ram_jump:
                cmp.w   #SENTINEL,d7
                bne.s   .code
                move    d6,ccr
                rts
.code:          lea     (a5,d7.w),a0
                cmpi.b  #$c3,(a0)
                bne.s   .bad
                moveq   #0,d7
                move.b  2(a0),d7
                lsl.w   #8,d7
                move.b  1(a0),d7
                bra     disp
.bad:           move.l  #$badc0de0,d6
                bra     panic

; call GB code at a0.w from the HAL; returns when it executes ret to SENTINEL
call_gb::
                move.w  #SENTINEL,-(a7)
                bra     gb_jump

gb_bad_target::
                move.l  #$badc0de1,d6
                bra     panic
gb_bad_static::
                move.l  #$badc0de2,d6
                bra     panic
gb_panic::
                move.l  #$badc0de3,d6
panic:
                move.w  #$2700,sr
                move.l  d6,dbg_buf.w
                move.w  last_target.w,dbg_buf+4.w
                move.l  (a7),dbg_buf+8.w        ; caller (jsr gb_panic)
                move.b  cur_bank.w,dbg_buf+12.w
                move.l  a7,dbg_buf+16.w
                move.w  #$f800,BG               ; red background
.lp:             bra.s   .lp

; ===========================================================================
; memory banking
; ===========================================================================
; MBC5 ROM bank (d7.b)
mbc_bank::
                andi.w  #$3f,d7
                cmp.b   cur_bank.w,d7
                beq.s   .same
                move.b  d7,cur_bank.w
                add.w   d7,d7
                add.w   d7,d7
                lea     bank_dtab,a0
                move.l  (a0,d7.w),cur_dtab.w
                lea     bank_base.w,a0
                movea.l (a0,d7.w),a4
.same:          rts

io_w_svbk::
                move.b  d7,IO+$70(a5)
                andi.w  #7,d7
                bne.s   .n0
                moveq   #1,d7
.n0:            move.b  d7,svbk_cur.w
                moveq   #12,d6
                lsl.w   d6,d7
                lea     WRAMX+$3000,a3
                adda.w  d7,a3
                rts
io_r_svbk::
                move.b  IO+$70(a5),d7
                ori.b   #$f8,d7
                rts

io_w_vbk::
                andi.b  #1,d7
                move.b  d7,vbk_cur.w
                move.b  d7,IO+$4f(a5)
                ori.b   #$fe,IO+$4f(a5)
                lea     VRAM68+$8000,a2
                tst.b   d7
                beq.s   .z
                lea     VRAM68+$a000,a2
.z:             rts
io_r_vbk::
                move.b  IO+$4f(a5),d7
                rts

; ===========================================================================
; generic memory access: d6.w = GB address, d7.b = value
; ===========================================================================
gb_rd::
                move.w  d6,d7
                lsr.w   #8,d7
                lsr.w   #2,d7
                andi.w  #$3c,d7
                lea     .t(pc),a0
                movea.l (a0,d7.w),a0
                jmp     (a0)
.t:             dc.l    rd_f,rd_f,rd_f,rd_f,rd_x,rd_x,rd_x,rd_x
                dc.l    rd_v,rd_v,rd_s,rd_s,rd_f,rd_w,rd_e,rd_ff
rd_f:           move.b  (a5,d6.w),d7
                rts
rd_x:           move.b  (a4,d6.w),d7
                rts
rd_v:           move.b  (a2,d6.w),d7
                rts
rd_s:           st      d7
                rts
rd_w:           move.b  (a3,d6.w),d7
                rts
rd_e:           subi.w  #$2000,d6
                bra     gb_rd
rd_ff:          cmp.w   #$fe00,d6
                bcs.s   rd_e
                cmp.w   #$ff00,d6
                bcs.s   rd_f
                cmp.w   #$ff80,d6
                bcc.s   rd_f
                bra     io_rd

gb_wr::
                move.l  d6,-(a7)
                lsr.w   #8,d6
                lsr.w   #2,d6
                andi.w  #$3c,d6
                lea     .t(pc),a0
                movea.l (a0,d6.w),a0
                move.l  (a7)+,d6
                jmp     (a0)
.t:             dc.l    wr_n,wr_n,mbc_bank,wr_n,wr_n,wr_n,wr_n,wr_n
                dc.l    vram_wr,vram_wr,wr_n,wr_n,wr_f,wr_w,wr_e,wr_ff
wr_n:           rts
wr_f:           move.b  d7,(a5,d6.w)
                rts
wr_w:           move.b  d7,(a3,d6.w)
                rts
wr_e:           subi.w  #$2000,d6
                bra     gb_wr
wr_ff:          cmp.w   #$fe00,d6
                bcs.s   wr_e
                cmp.w   #$fea0,d6
                bcs.s   oam_wr
                cmp.w   #$ff00,d6
                bcs.s   wr_f
                cmp.w   #$ff80,d6
                bcc.s   wr_f
                bra     io_wr

; VRAM byte write: 68k copy + log (maps: the byte; tile data: its aligned long as a
; block, which the GPU converts to its chunky rows)
vram_wr::
                move.b  d7,(a2,d6.w)
                cmp.w   #$9800,d6
                bcc.s   .map
                move.b  #LC_BLOCK,(a6)+
                move.b  vbk_cur.w,(a6)+
                andi.w  #$fffc,d6
                move.w  d6,(a6)+
                moveq   #4,d7
                move.l  d7,(a6)+
                move.l  (a2,d6.w),(a6)+
                bra.s   .ck
.map:           move.b  vbk_cur.w,(a6)+
                move.b  d7,(a6)+
                move.w  d6,(a6)+
.ck:            cmpa.l  log_limit.w,a6
                bcc     log_slow
                rts

; OAM byte write: the whole entry is sent
oam_wr::
                move.b  d7,(a5,d6.w)
                andi.w  #$fffc,d6
                move.b  #LC_OAM,(a6)+
                clr.b   (a6)+
                move.w  d6,(a6)
                subi.w  #$fe00,(a6)+
                move.l  (a5,d6.w),(a6)+
                cmpa.l  log_limit.w,a6
                bcc     log_slow
                rts

; generic IO: d6.w = $ffxx
io_rd::
                cmp.w   #$ff80,d6
                bcc.s   .f
                move.w  d6,d7
                andi.w  #$7f,d7
                add.w   d7,d7
                add.w   d7,d7
                lea     io_rtab,a0
                movea.l (a0,d7.w),a0
                jmp     (a0)
.f:             move.b  (a5,d6.w),d7
                rts
io_wr::
                cmp.w   #$ff80,d6
                bcc.s   .f
                move.l  d6,-(a7)
                andi.w  #$7f,d6
                add.w   d6,d6
                add.w   d6,d6
                lea     io_wtab,a0
                movea.l (a0,d6.w),a0
                move.l  (a7)+,d6
                jmp     (a0)
.f:             move.b  d7,(a5,d6.w)
                rts
io_r_flat::
                move.b  (a5,d6.w),d7
                rts
io_w_flat::
                move.b  d7,(a5,d6.w)
                rts

; ===========================================================================
; PPU command log
; ===========================================================================
; REG write: d6.w address, d7.b value (shadow + log)
log_reg:
                move.b  d7,(a5,d6.w)
                move.b  #LC_REG,(a6)+
                move.b  d7,(a6)+
                move.w  d6,(a6)+
                cmpa.l  log_limit.w,a6
                bcc.s   log_slow
                rts

; a6 reached log_limit: publish, wrap, wait for the GPU as needed
log_slow::
                movem.l d0-d1,-(a7)
.again:         PUBLISH d0
                moveq   #0,d0
                move.w  G_TAIL+2,d0
                lsl.l   #2,d0
                add.l   #LOGBUF,d0
                cmpa.l  d0,a6
                bcc.s   .behind
                ; reader ahead of the writer (same lap)
                sub.l   a6,d0
                cmp.l   #2*LOG_MARGIN,d0
                bcs.s   .wg                     ; wait for the GPU
                add.l   a6,d0
                sub.l   #LOG_MARGIN,d0
                move.l  d0,log_limit.w
                movem.l (a7)+,d0-d1
                rts
.behind:        ; reader at or behind the writer
                move.l  #LOGEND,d1
                sub.l   a6,d1
                cmp.l   #2*LOG_MARGIN,d1
                bcs.s   .wrap
                move.l  #LOGEND-LOG_MARGIN,log_limit.w
                movem.l (a7)+,d0-d1
                rts
.wrap:          sub.l   #LOGBUF,d0
                cmp.l   #2*LOG_MARGIN,d0
                bcs.s   .wg                     ; GPU still at the start: wait
                move.l  #LC_WRAP<<24,(a6)
                lea     LOGBUF,a6
                bra.s   .again
.wg:            addq.l  #1,wait_gpu.w
                bra.s   .again

; ===========================================================================
; IO registers (d6.w = address, d7.b = value)
; ===========================================================================
io_w_lcdc::
                move.b  R_LCDC(a5),d6
                eor.b   d7,d6
                bpl.s   .same                   ; bit 7 unchanged
                clr.b   v_ly.w
                move.b  #2,v_phase.w
                sf      hdma_on.w
.same:          move.w  #$ff40,d6
                bra     log_reg
io_w_scy::
io_w_scx::
io_w_wy::
io_w_wx::
                bra     log_reg
io_w_stat::
                andi.b  #$78,d7
                andi.b  #$87,R_STAT(a5)
                or.b    d7,R_STAT(a5)
                rts
io_w_lyc::
                move.b  d7,R_LYC(a5)
                rts
io_w_div::
                clr.w   div_cnt.w
                rts
io_r_div::
                addq.w  #3,div_cnt.w
                move.b  div_cnt.w,d7
                rts
io_r_key1::
                move.b  #$80,d7
                rts
io_w_snd::
                move.w  d6,-(a7)
                tst.b   snd_inst.w
                bne.s   .ib
                move.b  d7,(a5,d6.w)
                tst.b   snds_tail.w             ; a music note on a channel where an effect
                beq.s   .ia                     ; still sounds: the music takes it back
                bsr     snd_take
.ia:            andi.l  #$ff,d6                 ; queue reg<<8 | value for the DSP
                bra.s   .iq
.ib:            andi.l  #$ff,d6                 ; sound effects instance (snd_fx, hle.s):
                lea     SNDB-$10,a0             ; its own registers, the second set of
                move.b  d7,(a0,d6.w)            ; channels of the DSP (bit 15)
                bset    #7,d6
.iq:            lsl.w   #8,d6
                move.b  d7,d6
                lea     DQ,a0
                moveq   #0,d7
                move.b  dq_head.w,d7
                add.w   d7,d7
                add.w   d7,d7
                move.l  d6,(a0,d7.w)
                addq.b  #1,dq_head.w
                moveq   #0,d7
                move.b  dq_head.w,d7
                move.l  d7,DQHEAD
                move.w  (a7)+,d6
                rts
; sound register read: write-only bits read as 1
io_r_snd::
                move.w  d6,-(a7)
                tst.b   snd_inst.w
                bne.s   .rb
                move.b  (a5,d6.w),d7
                bra.s   .rm
.rb:            andi.w  #$ff,d6
                lea     SNDB-$10,a0
                move.b  (a0,d6.w),d7
.rm:            andi.w  #$1f,d6
                lea     snd_rmask(pc),a0
                or.b    (a0,d6.w),d7
                move.w  (a7)+,d6
                rts
snd_rmask:      dc.b    $ff,$00,$00,$bf,$00,$00,$70,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff   ; $20-$2f
                dc.b    $80,$3f,$00,$ff,$bf,$ff,$3f,$00,$ff,$bf,$7f,$ff,$9f,$ff,$bf,$ff   ; $10-$1f
                .even
io_r_nr52::
                move.l  a0,-(a7)
                movea.l #DSTATUS,a0
                move.b  IO+$26(a5),d7
                tst.b   snd_inst.w
                beq.s   .a
                move.b  SNDB+$16-$10.w,d7
                addq.l  #4,a0                   ; (DSTATUSB)
.a:             andi.b  #$80,d7
                ori.b   #$70,d7
                or.b    3(a0),d7
                movea.l (a7)+,a0
                rts

; ---------------------------------------------------------------------------
; DSP: GB sound synthesis (hal/dsp.s) at the I2S rate
; ---------------------------------------------------------------------------
init_dsp:
                move.l  #0,D_CTRL
                lea     D_RAM,a0
                move.w  #8192/4-1,d0
.cl:            clr.l   (a0)+
                dbra    d0,.cl
                lea     dsp_code,a0
                lea     D_RAM,a1
                move.w  #(dsp_code_end-dsp_code)/4,d0
.cp:            move.l  (a0)+,(a1)+
                dbra    d0,.cp
                move.l  #19,SCLK                ; 26.59 MHz / 40 / 32 = 20.8 kHz
                move.l  #$15,SMODE
                move.l  #dsp_start,D_PC
                move.l  #DSPGO,D_CTRL
                rts

io_r_p1::
                move.b  R_P1(a5),d7
                andi.b  #$30,d7
                move.l  d5,-(a7)
                moveq   #$0f,d6
                btst    #4,d7
                bne.s   .nd
                move.b  joy_dir.w,d5
                not.b   d5
                and.b   d5,d6
.nd:            btst    #5,d7
                bne.s   .nb
                move.b  joy_btn.w,d5
                not.b   d5
                and.b   d5,d6
.nb:            andi.b  #$0f,d6
                or.b    d6,d7
                ori.b   #$c0,d7
                move.l  (a7)+,d5
                rts

; palettes
io_w_bcps::
io_w_ocps::
                move.b  d7,(a5,d6.w)
                rts
; palette data byte: raw copy, then the whole colour to the GPU
io_w_bcpd::
                st      grad_last.w
                moveq   #$3f,d6
                and.b   R_BCPS(a5),d6
                lea     bgpal_raw.w,a0
                move.b  d7,(a0,d6.w)
                move.b  #LC_BGCOL,(a6)+
                move.w  d6,d7
                lsr.w   #1,d7
                move.b  d7,(a6)+                ; colour index
                add.w   d7,d7
                move.b  1(a0,d7.w),(a6)+        ; GB colour (high, low)
                move.b  (a0,d7.w),(a6)+
                tst.b   R_BCPS(a5)
                bpl.s   .n
                addq.b  #1,d6
                andi.b  #$3f,d6
                ori.b   #$80,d6
                move.b  d6,R_BCPS(a5)
.n:             cmpa.l  log_limit.w,a6
                bcc     log_slow
                rts
io_w_ocpd::
                moveq   #$3f,d6
                and.b   R_OCPS(a5),d6
                lea     obpal_raw.w,a0
                cmp.b   (a0,d6.w),d7            ; same value (the game rewrites its palettes
                beq.s   .same                   ; every frame): the GPU already has it
                move.b  d7,(a0,d6.w)
                move.b  #LC_OBCOL,(a6)+
                move.w  d6,d7
                lsr.w   #1,d7
                move.b  d7,(a6)+
                add.w   d7,d7
                move.b  1(a0,d7.w),(a6)+
                move.b  (a0,d7.w),(a6)+
.same:          tst.b   R_OCPS(a5)
                bpl.s   .n
                addq.b  #1,d6
                andi.b  #$3f,d6
                ori.b   #$80,d6
                move.b  d6,R_OCPS(a5)
.n:             cmpa.l  log_limit.w,a6
                bcc     log_slow
                rts
io_r_bcpd::
                move.b  R_BCPS(a5),d7
                andi.w  #$3f,d7
                lea     bgpal_raw.w,a0
                move.b  (a0,d7.w),d7
                rts
io_r_ocpd::
                move.b  R_OCPS(a5),d7
                andi.w  #$3f,d7
                lea     obpal_raw.w,a0
                move.b  (a0,d7.w),d7
                rts

; ---------------------------------------------------------------------------
; DMA
; ---------------------------------------------------------------------------
; a0 <- 68k pointer for GB source address d7.w (ROM, WRAM, VRAM)
src_ptr:
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
.xx:             lea     (a4,d7.w),a0
                rts
.v:             lea     (a2,d7.w),a0
                rts
.wt:             lea     (a3,d7.w),a0
                rts

; OAM DMA from page d7.b
io_w_dma::
                move.b  d7,IO+$46(a5)
oam_dma:
                andi.w  #$ff,d7
                lsl.w   #8,d7
                bsr.s   src_ptr
                lea     -$200(a5),a1            ; $fe00
                move.l  #LC_OAMALL<<24,(a6)+
                moveq   #160/4-1,d6
.c:             move.l  (a0),(a1)+
                move.l  (a0)+,(a6)+
                dbra    d6,.c
                cmpa.l  log_limit.w,a6
                bcc     log_slow
                rts
; "call $ff80": the HRAM routine ld a,XX / ldh ($46),a / wait
hal_oam_dma::
                move.b  $ff81-$10000(a5),d7
                bra.s   oam_dma
hal_oam_dma_a::
                move.b  d0,d7
                bra.s   oam_dma

; copy d7.w bytes (multiple of 16, <= 512) from a0 to VRAM GB address d6.w + log
vram_block:
                move.l  d5,-(a7)
                move.b  #LC_BLOCK,(a6)+
                move.b  vbk_cur.w,(a6)+
                move.w  d6,(a6)+
                andi.l  #$fff0,d7
                move.l  d7,(a6)+
                lea     (a2,d6.w),a1
                lsr.w   #2,d7
                subq.w  #1,d7
.c:             move.l  (a0)+,d5
                move.l  d5,(a1)+
                move.l  d5,(a6)+
                dbra    d7,.c
                move.l  (a7)+,d5
                cmpa.l  log_limit.w,a6
                bcc     log_slow
                rts

io_w_hdma5::
                move.b  d7,R_HDMA5(a5)
                btst    #7,d7
                bne     .hb
                tst.b   hdma_on.w
                beq.s   .gdma
                sf      hdma_on.w               ; stop a running HBlank DMA
                rts
.gdma:          movem.l d0-d1,-(a7)
                moveq   #0,d0
                move.b  d7,d0
                andi.w  #$7f,d0
                addq.w  #1,d0
                lsl.w   #4,d0                   ; bytes
                bsr     hdma_regs               ; d7 = src, d6 = dst
                ; tile data from the ROM: the GPU reads it itself (it skips what does not
                ; change: the game sends the same animation frames again and again). The
                ; 68k copy of VRAM is not updated for these.
                cmp.w   #$8000,d7
                bcc.s   .g
                move.w  d7,d1
                add.w   d0,d1
                cmp.w   #$8001,d1
                bcc.s   .g
                move.w  d6,d1
                add.w   d0,d1
                cmp.w   #$9801,d1
                bcc.s   .g
                bsr     src_ptr
                move.b  #LC_BLKP,(a6)+
                move.w  d0,d1
                lsr.w   #4,d1
                subq.w  #1,d1
                add.w   d1,d1
                or.b    vbk_cur.w,d1
                move.b  d1,(a6)+
                move.w  d6,(a6)+
                move.l  a0,(a6)+
                add.w   d0,d7
                add.w   d0,d6
                cmpa.l  log_limit.w,a6
                bcs.s   .gx
                bsr     log_slow
                bra.s   .gx
.g:             move.w  d0,d1                   ; chunks of up to 512 bytes
                cmp.w   #512,d1
                bls.s   .c
                move.w  #512,d1
.c:             movem.l d0-d1/d6-d7,-(a7)
                bsr     src_ptr
                move.w  d1,d7
                bsr     vram_block
                movem.l (a7)+,d0-d1/d6-d7
                add.w   d1,d7
                add.w   d1,d6
                sub.w   d1,d0
                bne.s   .g
.gx:            move.w  d7,hdma_src.w
                move.w  d6,hdma_dst.w
                bsr     hdma_wback
                move.b  #$ff,R_HDMA5(a5)
                movem.l (a7)+,d0-d1
                rts
.hb:            andi.b  #$7f,d7
                addq.b  #1,d7
                move.b  d7,hdma_len.w
                movem.l d6-d7,-(a7)
                bsr     hdma_regs
                move.w  d7,hdma_src.w
                move.w  d6,hdma_dst.w
                movem.l (a7)+,d6-d7
                st      hdma_on.w
                rts
; d7.w = source, d6.w = destination (from HDMA1-4)
hdma_regs:
                move.b  R_HDMA1(a5),d7
                lsl.w   #8,d7
                move.b  R_HDMA2(a5),d7
                andi.w  #$fff0,d7
                move.b  R_HDMA3(a5),d6
                lsl.w   #8,d6
                move.b  R_HDMA4(a5),d6
                andi.w  #$1ff0,d6
                ori.w   #$8000,d6
                rts
; the source/destination counters continue from where a transfer stopped: keep HDMA1-4 in step
hdma_wback:
                move.w  hdma_src.w,d7
                move.b  d7,R_HDMA2(a5)
                lsr.w   #8,d7
                move.b  d7,R_HDMA1(a5)
                move.w  hdma_dst.w,d7
                move.b  d7,R_HDMA4(a5)
                lsr.w   #8,d7
                andi.b  #$1f,d7
                move.b  d7,R_HDMA3(a5)
                rts
; one HBlank block
hdma_step::
                movem.l d6-d7,-(a7)
                move.w  hdma_src.w,d7
                bsr     src_ptr
                move.w  hdma_dst.w,d6
                cmp.w   #$8000,d7
                bcc.s   .ram
                cmp.w   #$97f1,d6
                bcc.s   .cp
                move.b  #LC_BLKP,(a6)+          ; tile data from the ROM: read by the GPU
                move.b  vbk_cur.w,(a6)+
                move.w  d6,(a6)+
                move.l  a0,(a6)+
                cmpa.l  log_limit.w,a6
                bcs.s   .same
                bsr     log_slow
                bra.s   .same
.cp:            moveq   #16,d7                  ; (the GPU skips what does not change)
                bsr     vram_block
                bra.s   .same
.ram:           move.b  #LC_BLOCK,(a6)+         ; from RAM: the data
                move.b  vbk_cur.w,(a6)+
                move.w  d6,(a6)+
                moveq   #16,d7
                move.l  d7,(a6)+
                lea     (a2,d6.w),a1
                move.l  (a0),(a1)+
                move.l  (a0)+,(a6)+
                move.l  (a0),(a1)+
                move.l  (a0)+,(a6)+
                move.l  (a0),(a1)+
                move.l  (a0)+,(a6)+
                move.l  (a0),(a1)+
                move.l  (a0)+,(a6)+
                cmpa.l  log_limit.w,a6
                bcs.s   .same
                bsr     log_slow
.same:          addi.w  #16,hdma_src.w
                addi.w  #16,hdma_dst.w
                bsr     hdma_wback
                subq.b  #1,hdma_len.w
                bne.s   .n
                sf      hdma_on.w
.n:             movem.l (a7)+,d6-d7
                rts
io_r_hdma5::
                tst.b   hdma_on.w
                bne.s   .on
                st      d7
                rts
.on:            move.b  hdma_len.w,d7
                subq.b  #1,d7
                andi.b  #$7f,d7
                rts

; ===========================================================================
; virtual PPU time
; ===========================================================================
; LY: a line just started (phase 2) is returned as is, else the next line is
; started first; either way the line is left in mode 3, so a game that waits for
; LY == n and then for the HBlank still gets the HBlank of line n
io_r_ly::
                btst    #7,R_LCDC(a5)
                beq.s   .off
                cmpi.b  #2,v_phase.w
                beq.s   .fresh
                bsr     vadvance_line
.fresh:         move.b  #3,v_phase.w
                move.b  v_ly.w,d7
                rts
.off:           moveq   #0,d7
                rts

; STAT: return mode/coincidence, then advance one phase (2 -> 3 -> 0 -> next line)
io_r_stat::
                btst    #7,R_LCDC(a5)
                beq.s   .off
                move.b  R_STAT(a5),d7
                andi.b  #$78,d7
                ori.b   #$80,d7
                move.b  v_ly.w,d6
                cmp.b   R_LYC(a5),d6
                bne.s   .nc
                bset    #2,d7
.nc:            cmp.b   #144,d6
                bcs.s   .vis
                ori.b   #1,d7
                move.b  d7,-(a7)
                bsr     vadvance_line
                move.b  (a7)+,d7
                rts
.vis:           move.b  v_phase.w,d6
                or.b    d6,d7
                cmp.b   #2,d6
                bne.s   .p3
                move.b  #3,v_phase.w
                rts
.p3:            cmp.b   #3,d6
                bne.s   .p0
                clr.b   v_phase.w
                rts
.p0:            move.b  d7,-(a7)
                bsr     vadvance_line
                move.b  (a7)+,d7
                rts
.off:           move.b  R_STAT(a5),d7
                andi.b  #$78,d7
                ori.b   #$80,d7
                rts

hal_halt::
                bra     vadvance_line

; 0:3E58 (menus: before VRAM / palette writes): wait STAT mode != 0, then mode 0.
; Same STAT reads as the GB loops; returns A = 0, Z set, no carry.
; With the io_r_stat phase model the net effect is known: in VBlank, lines up to line 0
; then one line; in a visible line, one line (two if already in HBlank: phase 0).
hal_wait_hbl::
                btst    #7,R_LCDC(a5)
                beq.s   .off
.vb:            cmpi.b  #144,v_ly.w
                bcs.s   .vis
                bsr     vadvance_line
                bra.s   .vb
.vis:           tst.b   v_phase.w
                bne.s   .one
                bsr.s   .adv                    ; (in HBlank: that line ends first)
.one:           bsr.s   .adv
.off:           moveq   #0,d7
                move.b  d7,d0                   ; (Z, no carry)
                rts
.adv:           bsr     fast_line
                beq.s   .ax
                bsr     vadvance_line
.ax:            rts

; wait for LY == $91 (0:3e9f): the GB loop reads LY until it sees $91
hal_wait_ly91::
                btst    #7,R_LCDC(a5)
                beq.s   .off
.lp:            cmpi.b  #$91,v_ly.w
                beq.s   .ok
                bsr     grad_batch
                bsr     fast_line
                beq.s   .lp
                bsr     vadvance_line
                bra.s   .lp
.ok:            bsr     vadvance_line
.r:             move.b  #$91,d0
                cmp.b   #$91,d0
                rts
.off:           bsr     frame_wait
                bra.s   .r

; wait for LY == d7.b (GB loop "ldh a,(LY) / cp n / jr nz,self" inlined by recomp68):
; same line timing as repeated io_r_ly reads, lines advanced by fast_line when possible
hal_wait_lyn::
                btst    #7,R_LCDC(a5)
                beq.s   .off
                move.l  d5,-(a7)
                move.b  d7,d5
.lp:            cmpi.b  #2,v_phase.w
                beq.s   .fresh
                move.b  v_ly.w,-(a7)
                bsr     fast_to                 ; (batch of lines up to the target)
                move.b  (a7)+,d7
                cmp.b   v_ly.w,d7
                bne.s   .fresh
                bsr     vadvance_line
.fresh:         move.b  #3,v_phase.w
                cmp.b   v_ly.w,d5
                bne.s   .lp
                move.b  d5,d7
                move.l  (a7)+,d5
                rts
.off:           tst.b   d7                      ; LY reads 0 with the LCD off
                beq.s   .r
                move.l  d7,-(a7)
                bsr     frame_wait
                move.l  (a7)+,d7
.r:             rts

; advance the virtual PPU by one line (keeps all registers but d6/d7/a0/a1/a6)
vadvance_line::
                moveq   #0,d7
                move.b  v_ly.w,d7
                cmp.b   #144,d7
                bcc.s   .novis
                tst.b   rnd.w
                beq.s   .lk
                ; line d7 is drawn now
                move.l  #LC_LINE<<24,d6
                move.w  d7,d6
                move.l  d6,(a6)+
                moveq   #3,d6
                and.b   d7,d6
                bne.s   .np
                PUBLISH d6
.np:
                cmpa.l  log_limit.w,a6
                bcs.s   .lk
                bsr     log_slow
.lk:            tst.b   hdma_on.w
                beq.s   .nohd
                bsr     hdma_step
.nohd:          btst    #3,R_STAT(a5)           ; HBlank interrupt
                beq.s   .nohb
                moveq   #2,d6
                bsr     irq_req
.nohb:          move.b  v_ly.w,d7
.novis:         addq.b  #1,d7
                cmp.b   #154,d7
                bcs.s   .nw
                moveq   #0,d7
.nw:            move.b  d7,v_ly.w
                move.b  #2,v_phase.w
                addq.w  #4,div_cnt.w
                cmp.b   #144,d7
                bne.s   .nvb
                bsr     frame_end
                btst    #4,R_STAT(a5)           ; STAT VBlank
                beq.s   .nsv
                moveq   #2,d6
                bsr     irq_req
.nsv:           moveq   #1,d6                   ; VBlank interrupt
                bsr     irq_req
                bra.s   .lyc
.nvb:           bcc.s   .lyc
                btst    #5,R_STAT(a5)           ; OAM interrupt
                beq.s   .lyc
                moveq   #2,d6
                bsr     irq_req
.lyc:           btst    #6,R_STAT(a5)
                beq.s   .xx
                move.b  v_ly.w,d7
                cmp.b   R_LYC(a5),d7
                bne.s   .xx
                moveq   #2,d6
                bsr     irq_req
.xx:             rts

; request interrupt d6 (1 = VBlank $40, 2 = STAT $48): dispatched now if enabled
; An interrupt that cannot be taken (IME off, inside a handler, masked by IE) stays
; pending in if_pend (the GB IF register): taken by EI (hal_ei) or after the handler's RETI.
irq_req::
                tst.b   gb_ime.w
                beq.s   .pend
                tst.b   v_inirq.w
                bne.s   .pend
                move.b  R_IE(a5),d7
                and.b   d6,d7
                beq.s   .pend
                not.b   d6
                and.b   d6,if_pend.w
                not.b   d6
                sf      gb_ime.w
                cmp.b   #2,d6
                bne.s   .gen
                cmpi.b  #$c3,$c1a4+G(a5)
                bne.s   .gen
                move.b  $c1a6+G(a5),d7
                lsl.w   #8,d7
                move.b  $c1a5+G(a5),d7
                bsr     stat_native
                beq.s   .no
.gen:           st      v_inirq.w
                movem.l d4-d5/a0,-(a7)
                movea.w #$48,a0
                cmp.b   #2,d6
                beq.s   .st
                movea.w #$40,a0
.st:            jsr     call_gb
                movem.l (a7)+,d4-d5/a0
                sf      v_inirq.w
                bra.s   irq_pending             ; (raised during the handler: after its RETI)
.pend:          or.b    d6,if_pend.w
.no:            rts
; take a pending interrupt if IME is on (VBlank first)
irq_pending::
                tst.b   gb_ime.w
                beq.s   .r
                move.b  if_pend.w,d6
                beq.s   .r
                and.b   R_IE(a5),d6
                beq.s   .r
                lsr.b   #1,d6
                bcs.s   .vb
                moveq   #2,d6
                bra     irq_req
.vb:            moveq   #1,d6
                bra     irq_req
.r:             rts
; EI (recomp68): IME on, then any pending interrupt is taken at once
hal_ei::
                st      gb_ime.w
                tst.b   v_inirq.w
                beq     irq_pending
                rts
; IF ($FF0F): the pending VBlank / STAT bits
io_w_if::
                move.b  d7,(a5,d6.w)
                andi.b  #3,d7
                move.b  d7,if_pend.w
                rts
io_r_if::
                move.b  if_pend.w,d7
                ori.b   #$e0,d7
                rts
; LY reached 144: end of the GB frame
frame_end::
                .if     ALLDRAW=3               ; (tests: one frame per VBlank at most)
                move.l  d0,-(a7)
                move.l  vbl_count.w,d0
.sy2:           cmp.l   fe_vbl.w,d0
                bne.s   .sy3
                move.l  vbl_count.w,d0
                bra.s   .sy2
.sy3:           move.l  d0,fe_vbl.w
                move.l  (a7)+,d0
                .endif
                tst.b   rnd.w
                beq.s   .k
                addq.l  #1,fsent.w
                move.l  #LC_FRAME<<24,(a6)+
                PUBLISH d6
                cmpa.l  log_limit.w,a6
                bcs.s   .k
                bsr     log_slow
.k:
                .if     ALLDRAW=3               ; (tests: every frame drawn and finished by the
                move.l  d0,-(a7)                ;  GPU before the next starts: GPU frame N is
.sy1:           move.w  fsent+2.w,d0            ;  GB frame N whatever the speed of either side;
                cmp.w   G_FRAMES+2,d0           ;  the joypad follows the schedule at SCHED,
                bne.s   .sy1                    ;  by GB frame: see test/probe.lua)
                addq.l  #1,frames.w
                move.l  frames.w,d0
                move.l  sched_ptr.w,d6
                bne.s   .sy4
                move.l  #SCHED,d6
.sy4:           movea.l d6,a0
.sy5:           cmp.l   (a0),d0
                bcs.s   .sy6
                move.b  4(a0),joy_dir.w
                move.b  5(a0),joy_btn.w
                addq.l  #8,a0
                bra.s   .sy5
.sy6:           move.l  a0,sched_ptr.w
                move.l  (a7)+,d0
                st      rnd.w
                st      strm.w
                clr.b   skipn.w
                rts
                .endif
                addq.l  #1,frames.w
                .if     ALLDRAW=1
                st      rnd.w
                st      strm.w
                clr.b   skipn.w
                rts
                .endif
                .if     ALLDRAW=2                ; (measurement: never draw)
                sf      rnd.w
                sf      strm.w
                rts
                .endif
                ; pacing: one GB frame per VBlank (fe_vbl = VBlank count at which this
                ; frame should end). Early: wait. Late: a drawn frame is followed by an
                ; undrawn one (which streams the object tiles, so that the next can be
                ; drawn): drawn / undrawn alternate when drawing costs more than a VBlank.
                move.l  d0,-(a7)
                addq.l  #1,fe_vbl.w
                move.l  vbl_count.w,d0
                sub.l   fe_vbl.w,d0             ; VBlanks late (< 0: early)
                sgt     d6
                bgt.s   .late
                bsr.s   .want
.wt:            move.l  vbl_count.w,d0          ; early or on time: wait
                cmp.l   fe_vbl.w,d0
                bcc.s   .fw
                addq.l  #1,wait_vbl.w
                bra.s   .wt
.late:          cmp.l   #4,d0                   ; (skipping cannot catch up a slower screen)
                bcs.s   .l1
                move.l  vbl_count.w,fe_vbl.w    ; far behind: accept the slowdown
                moveq   #0,d0
.l1:            cmp.l   #2,d0
                ble.s   .draw                   ; up to 2 VBlanks late: every frame is drawn
                tst.b   rnd.w
                bne.s   .skip                   ; later: a drawn frame is followed by an undrawn one
                cmp.l   #3,d0
                ble.s   .draw                   ; undrawn, at most 3 VBlanks late: draw;
                cmpi.b  #3,skipn.w              ; else skip to catch up (up to 3 in a row)
                bcc.s   .draw
.skip:          sf      rnd.w
                addq.b  #1,skipn.w
                bra.s   .fw
.draw:          bsr.s   .want
.fw:            st      strm.w                  ; (object tiles are always streamed: cheap now)
                move.l  (a7)+,d0
                rts
; draw the next frame, if its object tiles were streamed in this one and the GPU has
; finished the frames already sent (else the 68k would stall on a full log)
.want:          tst.b   strm.w
                beq.s   .nos
                move.w  fsent+2.w,d7
                sub.w   G_FRAMES+2,d7           ; frames sent, not finished
                cmp.w   #2,d7
                bcc.s   .nos
                st      rnd.w
                clr.b   skipn.w
                rts
.nos:           sf      rnd.w
                addq.b  #1,skipn.w
                rts
; wait for the next VBlank (LCD off)
frame_wait::
                move.l  d0,-(a7)
                move.l  vbl_count.w,d0
.wv:            cmp.l   vbl_count.w,d0
                beq.s   .wv
                move.l  (a7)+,d0
                rts
; flag conversion tables for push af / pop af
f_of_ccr::      dc.b    $00,$10,$00,$00,$80,$90,$00,$00
ccr_of_f::      dc.b    $00,$11,$00,$11,$00,$11,$00,$11,$04,$15,$04,$15,$04,$15,$04,$15
                .even










