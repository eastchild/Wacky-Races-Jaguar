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
FB0             equ     $120000         ; framebuffers 176x144 RGB16 (8 hidden pixels each side):
FB1             equ     $130000         ;   three (the GPU never draws into the one shown, nor
FB2             equ     $140000         ;   into the one just published); FBn = (n + $12) << 16
FB_PITCH        equ     352
FB_LEFT         equ     16              ; bytes before the first visible pixel
LOGBUF          equ     $180000         ; PPU command log (ring)
LOGEND          equ     $1c0000
LOG_MARGIN      equ     1024

PROFBUF         equ     $150000         ; profiler histogram (word per 4 code bytes)
PROF_SPAN       equ     $30000
; ---- GPU data (see gpu.s) ----
GRAW            equ     $1c0000         ; raw copy of VRAM: bank 0, bank 1 (+$2000)
GCHK            equ     $1d0000         ; tile data as chunky rows (same layout), mirrored at +$8000
DMAP            equ     $1e0000         ; decoded maps: 4 tables (map, LCDC.4) x 32 rows x 64 cells
CTAB            equ     $1f0000         ; GB colour -> RGB16 (32768 words)
RAMEND          equ     $200000
SEL             equ     $32c0           ; up to 10 sprites of the line
SCR             equ     $32f0           ; scratch long (VRAM byte writes)
OAMX            equ     $3300           ; copy of OAM (40 longs)
HUDBUF          equ     $0f8000         ; debug HUD bitmap 64x12 RGB16
ISRSTACK        equ     $3e00           ; VBlank ISR stack (top; a7 is the GB stack otherwise)
SCHED           equ     $0f9000         ; (sync test build) joypad schedule written by the test
                                        ;   script: long GB frame, byte dir, byte buttons, word 0
                .if     ^^defined HUD
                .else
HUD             equ     0
                .endif
                .if     ^^defined PROFILE
                .else
PROFILE         equ     0
                .endif
                .if     ^^defined NOGPULINE     ; measurement: the GPU renders no line
                .else
NOGPULINE       equ     0
                .endif
                .if     ^^defined ALLDRAW       ; measurement: draw every frame, no pacing
                .else
ALLDRAW         equ     0
                .endif

FB_W            equ     160
FB_H            equ     144

; ---- log commands (byte 0 of each long) ----
LC_VRAM0        equ     0               ; b1 value, w2 address
LC_VRAM1        equ     1
LC_REG          equ     2               ; b1 value, w2 address ($ff40..)
LC_BLKP         equ     3               ; b1 (16-byte blocks - 1) << 1 | bank, w2 address ; long: source
LC_NOP          equ     4               ; (with the flags: a line / a stream block)
LC_OAM          equ     5               ; b1 value, w2 offset
LC_BLOCK        equ     6               ; b1 bank, w2 address ; long count ; data
LC_OAMALL       equ     7               ; 160 bytes follow
LC_LINE         equ     8               ; w2 line
LC_FRAME        equ     9
LC_WRAP         equ     10
LC_BGCOL        equ     11              ; b1 colour index 0-31, w2 GB colour
LC_OBCOL        equ     12
LC_GRAD3        equ     14              ; w2 = colour 0 of BG palettes 0-2
LC_SCROLL       equ     15              ; b1 SCY, b3 SCX
LC_ROADLN       equ     16              ; b1 SCY, b2 SCX ; long: address of BG palette 0 bytes
; flags in byte 0 of any command, applied after it
LF_LINE         equ     $80             ; render the line after the last one rendered

; ---- GPU shared variables (GPU local RAM, see gpu.s) ----
G_HEAD          equ     $f03fe0         ; written by the 68k: log write pointer
G_TAIL          equ     $f03fe4         ; written by the GPU: log read pointer
G_DISP          equ     $f03fe8         ; written by the GPU: framebuffer to display (1-3: FB0-FB2)
G_FRAMES        equ     $f03fec         ; frames completed by the GPU
G_SHOWN         equ     $f03ff0         ; written by the 68k (VBlank): framebuffer shown (1-3)

G               equ     -$10000         ; (a5) offset of a GB address >= $8000
DQ              equ     $f1c800         ; DSP sound queue (256 longs), see dsp.s
DQHEAD          equ     $f1cc00
DQTAIL          equ     $f1cc04
DSTATUS         equ     $f1cc08         ; channels on (NR52 bits 0-3): music instance
DSTATUSB        equ     $f1cc0c         ;   sound effects instance
SDRV            equ     $3400           ; sound effects instance: the engine RAM C200-C2AF,
                                        ;   C300-C33F (at +$b0) while the music's is in place
SNDB            equ     $3500           ;   its sound registers $ff10-$ff3f
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
isr_sp:         ds.l    1               ; GB stack pointer saved by the VBlank ISR
rl_tbl:         ds.l    1               ; road (drawn frame): 68k address of the palette pointer
                                        ;   table (FF99:FF98) in WRAM0, 0: generic path
rl_pbase:       ds.l    1               ; road: ROM base of bank (FF9A) (bank_base entry)
if_pend:        ds.b    1               ; pending interrupts (GB IF: 1 VBlank, 2 STAT)
rl_rend:        ds.b    1               ; road: next line already rendered by LC_ROADLN
                .even
sched_ptr:      ds.l    1               ; (sync test build) next joypad schedule entry
rd_a2:          ds.l    1               ; road fast loop: a2 / a3 of the GB code (VRAM bank,
rd_a3:          ds.l    1               ;   WRAM bank)
hl_buf:         ds.b    12              ; 35:61C0 / 35:61E9: one palette ; 6:4298: a map row
a_width:        ds.w    1               ; visible pixels per line (PWIDTH2)
scr_x:          ds.w    1               ; picture object: x (pixels), y (half-lines)
scr_y:          ds.w    1
scr_hs:         ds.b    1               ; picture scale (3.5 fixed point)
scr_vs:         ds.b    1
scr_wide:       ds.b    1               ; 0: 10:9 picture, else stretched to the full width
scr_safe:       ds.b    1               ; 0: whole height (overscan), else TV safe area
                .even
key_prev:       ds.l    1               ; joypad bits of the last VBlank (keypad edges)
snd_save:       ds.l    4               ; GB registers across the second engine update
snd_inst:       ds.b    1               ; 0: music engine RAM / sound registers, 1: effects
snds_on:        ds.b    1               ; the effects instance has something to play
snds_act:       ds.b    1               ; its channels in use by an effect (bits 0-3)
snds_tail:      ds.b    1               ; its channels whose effect is over but still sounds
                                        ;   (until the music plays a note there, as on the GB)
                .even
                .even
                .text




















