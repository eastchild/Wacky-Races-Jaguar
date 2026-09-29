; ---------------------------------------------------------------------------
; Wacky Races (Jaguar) - memory map and shared constants
; ---------------------------------------------------------------------------

; ---- low RAM (abs.w addressable) ----
VARS            equ     $1000           ; HAL variables (see below)
OPLIST          equ     $3000           ; object list (phrase aligned)
BOOTSTACK       equ     $3ff0

; ---- big buffers ----
FLAT            equ     $100000         ; 64KB GB image, rotated: GB $8000-$FFFF then $0000-$7FFF
FLAT_MID        equ     FLAT+$8000      ; GB address g is at FLAT_MID + int16(g)
VRAM68          equ     $110000         ; 68k copy of VRAM: bank 0, bank 1 (+$2000)
WRAMX           equ     $114000         ; 8 x 4KB WRAM banks (index 1-7 used)
GVRAM           equ     $11c000         ; GPU copy of VRAM (bank 0, bank 1)
FB0             equ     $120000         ; framebuffers 160x144 RGB16
FB1             equ     $130000
LOGBUF          equ     $140000         ; PPU command log (ring)
LOGEND          equ     $180000
LOG_MARGIN      equ     1024

PROFBUF         equ     $180000         ; profiler histogram (word per 4 code bytes)
PROF_SPAN       equ     $40000
HUDBUF          equ     $0f8000         ; debug HUD bitmap 64x12 RGB16
                .if     ^^defined HUD
                .else
HUD             equ     0
                .endif
                .if     ^^defined PROFILE
                .else
PROFILE         equ     0
                .endif

FB_W            equ     160
FB_H            equ     144

; ---- log commands (byte 0 of each long) ----
LC_VRAM0        equ     0               ; b1 value, w2 address
LC_VRAM1        equ     1
LC_REG          equ     2               ; b1 value, w2 address ($ff40..)
LC_BGPAL        equ     3               ; b1 value, w2 index 0-63
LC_OBPAL        equ     4
LC_OAM          equ     5               ; b1 value, w2 offset
LC_BLOCK        equ     6               ; b1 bank, w2 address ; long count ; data
LC_OAMALL       equ     7               ; 160 bytes follow
LC_LINE         equ     8               ; w2 line
LC_FRAME        equ     9
LC_WRAP         equ     10
LC_BGCOL        equ     11              ; b1 colour index 0-31, w2 GB colour
LC_OBCOL        equ     12
LC_GRAD3        equ     14              ; w2 = colour 0 of BG palettes 0-2
LC_PAL          equ     13
LC_SCROLL       equ     15              ; b1 SCY, b3 SCX
LC_ROADLN       equ     16              ; b1 SCY, b3 SCX ; long: address of BG palette 0 bytes              ; b1 palette 0-7 BG / 8-15 OBJ ; 8 raw bytes follow

; ---- GPU shared variables (GPU local RAM, see gpu.s) ----
G_HEAD          equ     $f03fe0         ; written by the 68k: log write pointer
G_TAIL          equ     $f03fe4         ; written by the GPU: log read pointer
G_DISP          equ     $f03fe8         ; written by the GPU: framebuffer to display
G_FRAMES        equ     $f03fec         ; frames completed by the GPU
G_LINES         equ     $f03ff0         ; lines rendered (debug)

G               equ     -$10000         ; (a5) offset of a GB address >= $8000
DQ              equ     $f1c800         ; DSP sound queue (256 longs), see dsp.s
DQHEAD          equ     $f1cc00
DQTAIL          equ     $f1cc04
DSTATUS         equ     $f1cc08
; publish the log write pointer to the GPU as a 16-bit long index (a 68k long write is two word writes)
                .macro  PUBLISH r
                move.l  a6,\r
                sub.l   #LOGBUF,\r
                lsr.l   #2,\r
                move.w  \r,G_HEAD+2
                .endm
SENTINEL        equ     $fff0           ; GB return address meaning "back to the HAL"

; ---- HAL variables ----
                .abs    VARS
gb_ime:         ds.b    1
cur_bank:       ds.b    1
v_ly:           ds.b    1
v_phase:        ds.b    1
v_inirq:        ds.b    1
vbk_cur:        ds.b    1
svbk_cur:       ds.b    1
hdma_on:        ds.b    1
hdma_len:       ds.b    1
joy_dir:        ds.b    1               ; GB bits active high: 0 right 1 left 2 up 3 down
joy_btn:        ds.b    1               ; 0 A 1 B 2 select 3 start
pad_b:          ds.b    1
                .even
hdma_src:       ds.w    1
hdma_dst:       ds.w    1
last_target:    ds.w    1
div_cnt:        ds.w    1
                .long
cur_dtab:       ds.l    1
log_limit:      ds.l    1
vbl_count:      ds.l    1
frame_vbl:      ds.l    1
frames:         ds.l    1
disp_fb:        ds.l    1
joy_raw:        ds.l    1
panic_pc:       ds.l    1
bgpal_raw:      ds.b    64
obpal_raw:      ds.b    64
dbg_buf:        ds.b    64
a_vdb:          ds.w    1
a_vde:          ds.w    1
a_height:       ds.w    1
ntsc:           ds.w    1
wait_gpu:       ds.l    1
wait_vbl:       ds.l    1
sc_ptr:         ds.l    1
fe_vbl:         ds.l    1
rnd:            ds.b    1               ; this GB frame is rendered (else: logic only)
in_road:        ds.b    1
dq_head:        ds.b    1
rh_valid:       ds.b    1               ; road HDMA: rh_ptr valid
                .even
rh_src:         ds.w    1
rh_dst:         ds.w    1
rh_ptr:         ds.l    1
grad_last:      ds.l    1
rl_pal:         ds.l    1
skipn:          ds.b    1               ; undrawn frames in a row
strm:           ds.b    1
                .even
fsent:          ds.l    1               ; frames sent to the GPU
hud_f0:         ds.l    1
hud_s0:         ds.l    1
hud_cnt:        ds.w    1               ; stream road object tiles this frame
                .even               ; last LC_GRAD3 sent (mask<<16 | colour)
                .even
bank_base:      ds.l    64              ; ROMX base register value per bank
ft_rout:        ds.l    1               ; fast_to: native HBlank handler (0: none)
if_pend:        ds.b    1               ; pending interrupts (GB IF: 1 VBlank, 2 STAT)
                .even
                .even
                .text




















