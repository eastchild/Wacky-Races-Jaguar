; ---------------------------------------------------------------------------
; DSP program: GB APU (4 channels) synthesised at the I2S rate (~20.8 kHz).
; The 68k queues sound register writes (reg<<8 | value, one long each) into
; DQ; everything runs in the I2S interrupt (register bank 0, which the idle
; main loop never uses: bank 0 registers keep the channel state).
; Loaded at $F1B000 by init_dsp.
; ---------------------------------------------------------------------------
SV              equ     $f1c000         ; channel blocks, 64 bytes each
WAVE            equ     $f1c100         ; 32 longs: wave samples, signed (s-8)*2
SVX             equ     $f1c180         ; misc: +0 seq step, +4 power
DSTACK          equ     $f1cff0
FS_SEQ          equ     1615            ; 512 Hz in 16.16 per sample (20774 Hz)
SQ_K            equ     105857390       ; 2^41 / fs
NZ_K            equ     13232173        ; 2^38 / fs

; channel block offsets
C_ON            equ     0
C_FREQ          equ     4
C_VOL           equ     8
C_ENVDIR        equ     12
C_ENVPER        equ     16
C_ENVCNT        equ     20
C_LEN           equ     24
C_LENEN         equ     28
C_DAC           equ     32
C_DUTY          equ     36              ; ch3: shift code, ch4: width7
C_SWPER         equ     40              ; ch4: divisor code
C_SWNEG         equ     44              ; ch4: clock shift
C_SWSH          equ     48
C_SWCNT         equ     52
C_SWEN          equ     56
C_SHADOW        equ     60
; raw register copies for triggers: NRx2 at SV+256+... -> kept in C_ENV* fields directly

                .phrase
dsp_code::
                .dsp
                .org    $f1b000
; interrupt vectors (16 bytes each): 0 CPU, 1 I2S
dsp_v0:         movei   #dsp_idle,r30
                jump    t,(r30)
                nop
                nop
                nop
                nop
dsp_v1:         movei   #snd_isr,r30
                jump    t,(r30)
                nop
                nop
                nop
                nop

dsp_start::
                movei   #DSTACK,r31
                moveq   #0,r0
                moveq   #0,r1
                moveq   #0,r2
                moveq   #0,r3
                moveq   #0,r4
                moveq   #0,r5
                movei   #$7fff,r6
                moveq   #0,r7
                moveq   #0,r8
                moveq   #0,r9
                moveq   #0,r10
                moveq   #4,r11
                moveq   #0,r12
                moveq   #0,r13
                movei   #$ff,r16
                movei   #$77,r17
                moveq   #0,r18
                movei   #FS_SEQ,r19
                movei   #SV,r14
                movei   #WAVE,r15
                movei   #D_DIVCTRL,r20
                moveq   #0,r21
                store   r21,(r20)
                ; I2S interrupt on, main code in register bank 1
                movei   #D_FLAGS,r20
                load    (r20),r21
                movei   #D_I2SENA|REGPAGE,r22
                or      r22,r21
                store   r21,(r20)
                nop
                nop
dsp_idle:       jr      t,dsp_idle
                nop

; ---------------------------------------------------------------------------
snd_isr:
                ; ---- one queued register write per sample
                movei   #DQHEAD,r20
                load    (r20),r21
                addqt   #4,r20
                load    (r20),r22               ; tail
                cmp     r21,r22
                movei   #no_cmd,r23
                jump    eq,(r23)
                nop
                move    r22,r23
                shlq    #2,r23
                movei   #DQ,r24
                add     r24,r23
                load    (r23),r25               ; reg<<8 | value
                addq    #1,r22
                movei   #$ff,r24
                and     r24,r22
                store   r22,(r20)
                move    r25,r24
                shrq    #8,r24                  ; reg ($10-$3f)
                movei   #$ff,r23
                and     r23,r25                 ; value
                subq    #16,r24
                movei   #48,r23
                cmp     r23,r24
                movei   #no_cmd,r23
                jump    cc,(r23)                ; not a sound register
                nop
                shlq    #2,r24
                movei   #rtab,r23
                add     r24,r23
                load    (r23),r23
                movei   #no_cmd,r27             ; handlers return through r27
                jump    t,(r23)
                nop
no_cmd:
                ; ---- frame sequencer (512 Hz)
                add     r19,r18
                move    r18,r20
                shrq    #16,r20
                movei   #synth,r23
                jump    eq,(r23)
                nop
                movei   #$ffff,r20
                and     r20,r18
                movei   #SVX,r20
                load    (r20),r21
                addq    #1,r21
                moveq   #7,r22
                and     r22,r21
                store   r21,(r20)
                btst    #0,r21
                movei   #seq_nolen,r23
                jump    ne,(r23)
                nop
                movei   #seq_nolen,r27
                movei   #len_tick,r23
                jump    t,(r23)
                nop
seq_nolen:      movei   #SVX,r20
                load    (r20),r21
                cmpq    #2,r21
                jr      eq,seq_sw
                nop
                cmpq    #6,r21
                jr      ne,seq_nosw
                nop
seq_sw:         movei   #seq_nosw,r27
                movei   #sweep_tick,r23
                jump    t,(r23)
                nop
seq_nosw:       movei   #SVX,r20
                load    (r20),r21
                cmpq    #7,r21
                movei   #synth,r23
                jump    ne,(r23)
                nop
                movei   #synth,r27
                movei   #env_tick,r23
                jump    t,(r23)
                nop

; ---- synthesis: r22 = left, r23 = right
synth:
                moveq   #0,r22
                moveq   #0,r23
                ; ch1 square
                add     r1,r0
                move    r0,r20
                shrq    #29,r20
                move    r13,r21
                sh      r20,r21
                move    r9,r24
                btst    #0,r21
                jr      ne,s1p
                nop
                neg     r24
s1p:            btst    #4,r16
                jr      eq,s1l
                nop
                add     r24,r22
s1l:            btst    #0,r16
                jr      eq,s1r
                nop
                add     r24,r23
s1r:            ; ch2 square
                add     r3,r2
                move    r2,r20
                shrq    #29,r20
                move    r13,r21
                shrq    #8,r21
                sh      r20,r21
                move    r10,r24
                btst    #0,r21
                jr      ne,s2p
                nop
                neg     r24
s2p:            btst    #5,r16
                jr      eq,s2l
                nop
                add     r24,r22
s2l:            btst    #1,r16
                jr      eq,s2r
                nop
                add     r24,r23
s2r:            ; ch3 wave
                add     r5,r4
                cmpq    #4,r11
                jr      eq,s3r
                nop
                move    r4,r20
                shrq    #27,r20
                shlq    #2,r20
                load    (r15+r20),r24
                sha     r11,r24
                btst    #6,r16
                jr      eq,s3l
                nop
                add     r24,r22
s3l:            btst    #2,r16
                jr      eq,s3r
                nop
                add     r24,r23
s3r:            ; ch4 noise
                add     r8,r7
                move    r7,r20
                shrq    #16,r20                 ; LFSR clocks this sample
                movei   #$ffff,r21
                and     r21,r7
                cmpq    #0,r20
                movei   #s4o,r25
                jump    eq,(r25)
                nop
                cmpq    #8,r20
                jr      mi,s4c
                nop
                moveq   #8,r20
s4c:            movei   #SV+192+C_DUTY,r26
                load    (r26),r26               ; width 7
                movei   #s4l,r25
s4l:            move    r6,r21
                move    r6,r24
                shrq    #1,r24
                xor     r24,r21
                moveq   #1,r24
                and     r24,r21                 ; feedback bit
                shrq    #1,r6
                move    r21,r24
                shlq    #14,r24
                or      r24,r6
                cmpq    #0,r26
                jr      eq,s4n
                nop
                bclr    #6,r6
                shlq    #6,r21
                or      r21,r6
s4n:            subq    #1,r20
                jump    ne,(r25)
                nop
s4o:            move    r12,r24
                btst    #0,r6
                jr      eq,s4p
                nop
                neg     r24
s4p:            btst    #7,r16
                jr      eq,s4lf
                nop
                add     r24,r22
s4lf:           btst    #3,r16
                jr      eq,s4r
                nop
                add     r24,r23
s4r:            ; master volume (NR50) and output
                move    r17,r20
                shrq    #4,r20
                moveq   #7,r21
                and     r21,r20
                addq    #1,r20
                imult   r20,r22
                move    r17,r20
                and     r21,r20
                addq    #1,r20
                imult   r20,r23
                shlq    #6,r22
                shlq    #6,r23
                movei   #L_I2S,r20
                store   r22,(r20)
                addqt   #4,r20
                store   r23,(r20)
                ; ---- return from interrupt
                movei   #D_FLAGS,r30
                load    (r30),r29
                bclr    #3,r29
                bset    #10,r29                 ; clear the I2S latch
                load    (r31),r28
                addq    #2,r28
                addq    #4,r31
                jump    t,(r28)
                store   r29,(r30)

; ---------------------------------------------------------------------------
; register write handlers: r25 = value; return through r27; temps r20-r26
; ---------------------------------------------------------------------------
; channel c base (SV + 64c) -> r26
                .long
rtab:           dc.l    w_nr10,w_nr11,w_nr12,w_nr13,w_nr14
                dc.l    w_none,w_nr21,w_nr22,w_nr23,w_nr24
                dc.l    w_nr30,w_nr31,w_nr32,w_nr33,w_nr34
                dc.l    w_none,w_nr41,w_nr42,w_nr43,w_nr44
                dc.l    w_nr50,w_nr51,w_nr52,w_none,w_none,w_none,w_none,w_none,w_none,w_none,w_none,w_none
                dc.l    w_wave,w_wave,w_wave,w_wave,w_wave,w_wave,w_wave,w_wave
                dc.l    w_wave,w_wave,w_wave,w_wave,w_wave,w_wave,w_wave,w_wave

w_none:         jump    t,(r27)
                nop

w_nr10:         movei   #SV+C_SWPER,r26
                move    r25,r20
                shrq    #4,r20
                moveq   #7,r21
                and     r21,r20
                store   r20,(r26)
                addqt   #4,r26
                move    r25,r20
                shrq    #3,r20
                moveq   #1,r21
                and     r21,r20
                store   r20,(r26)               ; SWNEG
                addqt   #4,r26
                move    r25,r20
                moveq   #7,r21
                and     r21,r20
                store   r20,(r26)               ; SWSH
                jump    t,(r27)
                nop

; NRx1 duty/length for ch1 (r21 = shift of the pattern in r13: 0 or 8)
w_nr11:         movei   #SV,r26
                moveq   #0,r21
                jr      t,w_dl
                nop
w_nr21:         movei   #SV+64,r26
                moveq   #8,r21
w_dl:           move    r25,r20
                shrq    #6,r20
                shlq    #2,r20
                movei   #dutytab,r22
                add     r20,r22
                load    (r22),r22               ; duty pattern
                movei   #$ff,r24
                cmpq    #0,r21
                jr      eq,w_dl0
                nop
                shlq    #8,r22
                shlq    #8,r24
w_dl0:          not     r24
                and     r24,r13
                or      r22,r13
                moveq   #31,r22                 ; length = 64 - (v & 63)
                addq    #32,r22
                and     r25,r22
                movei   #64,r20
                sub     r22,r20
                move    r26,r22
                addq    #C_LEN,r22
                store   r20,(r22)
                jump    t,(r27)
                nop
; NRx2 envelope (ch1, ch2, ch4)
w_nr12:         movei   #SV,r26
                jr      t,w_env
                nop
w_nr22:         movei   #SV+64,r26
                jr      t,w_env
                nop
w_nr42:         movei   #SV+192,r26
w_env:          move    r26,r22
                addq    #C_ENVDIR,r22
                move    r25,r20
                shrq    #3,r20
                moveq   #1,r21
                and     r21,r20
                store   r20,(r22)               ; direction
                addqt   #4,r22
                moveq   #7,r20
                and     r25,r20
                store   r20,(r22)               ; period
                movei   #INITVOL,r22            ; initial volume (used at the trigger)
                move    r26,r23
                movei   #SV,r24
                sub     r24,r23
                shrq    #4,r23
                add     r23,r22
                move    r25,r20
                shrq    #4,r20
                store   r20,(r22)
                move    r26,r22
                addq    #C_DAC,r22
                movei   #$f8,r20
                and     r25,r20
                moveq   #0,r21
                cmpq    #0,r20
                jr      eq,w_env0
                nop
                moveq   #1,r21
w_env0:         store   r21,(r22)
                cmpq    #0,r21
                jr      ne,w_envx
                nop
                moveq   #0,r20                  ; DAC off: channel off
                store   r20,(r26)
                movei   #amp_upd,r23
                jump    t,(r23)
                nop
w_envx:         jump    t,(r27)
                nop
; NRx3 frequency low
w_nr13:         movei   #SV,r26
                jr      t,w_fl
                nop
w_nr23:         movei   #SV+64,r26
                jr      t,w_fl
                nop
w_nr33:         movei   #SV+128,r26
w_fl:           move    r26,r22
                addq    #C_FREQ,r22
                load    (r22),r20
                movei   #$700,r21
                and     r21,r20
                or      r25,r20
                store   r20,(r22)
                movei   #inc_upd,r23
                jump    t,(r23)
                nop

; NRx4 frequency high / length enable / trigger
w_nr14:         movei   #SV,r26
                jr      t,w_fh
                nop
w_nr24:         movei   #SV+64,r26
                jr      t,w_fh
                nop
w_nr34:         movei   #SV+128,r26
w_fh:           move    r26,r22
                addq    #C_FREQ,r22
                load    (r22),r20
                movei   #$ff,r21
                and     r21,r20
                moveq   #7,r21
                and     r25,r21
                shlq    #8,r21
                or      r21,r20
                store   r20,(r22)
                move    r26,r22
                addq    #C_LENEN,r22
                move    r25,r20
                shrq    #6,r20
                moveq   #1,r21
                and     r21,r20
                store   r20,(r22)
                btst    #7,r25
                movei   #inc_upd,r23
                jump    eq,(r23)
                nop
                movei   #w_trig,r23
                jump    t,(r23)
                nop
w_nr44:         movei   #SV+192,r26
                move    r26,r22
                addq    #C_LENEN,r22
                move    r25,r20
                shrq    #6,r20
                moveq   #1,r21
                and     r21,r20
                store   r20,(r22)
                btst    #7,r25
                movei   #w_trig,r23
                jump    ne,(r23)
                nop
                jump    t,(r27)
                nop

; ch3
w_nr30:         movei   #SV+128+C_DAC,r22
                move    r25,r20
                shrq    #7,r20
                store   r20,(r22)
                cmpq    #0,r20
                jr      ne,w_n30x
                nop
                movei   #SV+128,r26
                moveq   #0,r20
                store   r20,(r26)
                movei   #amp_upd,r23
                jump    t,(r23)
                nop
w_n30x:         jump    t,(r27)
                nop
w_nr31:         movei   #256,r20
                sub     r25,r20
                movei   #SV+128+C_LEN,r22
                store   r20,(r22)
                jump    t,(r27)
                nop
w_nr32:         move    r25,r20
                shrq    #5,r20
                moveq   #3,r21
                and     r21,r20
                movei   #SV+128+C_DUTY,r22
                store   r20,(r22)
                movei   #SV+128,r26
                movei   #amp_upd,r23
                jump    t,(r23)
                nop

; ch4
w_nr41:         movei   #SV+192,r26
                moveq   #31,r20
                addq    #31,r20
                addq    #2,r20
                moveq   #31,r22
                addq    #32,r22
                and     r25,r22
                sub     r22,r20
                movei   #SV+192+C_LEN,r22
                store   r20,(r22)
                jump    t,(r27)
                nop
w_nr43:         movei   #SV+192+C_DUTY,r22
                move    r25,r20
                shrq    #3,r20
                moveq   #1,r21
                and     r21,r20
                store   r20,(r22)               ; width 7
                addqt   #4,r22
                moveq   #7,r20
                and     r25,r20
                store   r20,(r22)               ; divisor code
                addqt   #4,r22
                move    r25,r20
                shrq    #4,r20
                store   r20,(r22)               ; clock shift
                movei   #SV+192,r26
                movei   #inc_upd,r23
                jump    t,(r23)
                nop

w_nr50:         move    r25,r17
                jump    t,(r27)
                nop
w_nr51:         move    r25,r16
                jump    t,(r27)
                nop
w_nr52:         btst    #7,r25
                jump    ne,(r27)
                nop
                moveq   #0,r20                  ; power off: all channels off
                movei   #SV,r22
                store   r20,(r22)
                movei   #SV+64,r22
                store   r20,(r22)
                movei   #SV+128,r22
                store   r20,(r22)
                movei   #SV+192,r22
                store   r20,(r22)
                moveq   #0,r9
                moveq   #0,r10
                moveq   #4,r11
                moveq   #0,r12
                movei   #DSTATUS,r22
                store   r20,(r22)
w_n52x:         jump    t,(r27)
                nop

; wave RAM byte: two signed samples
w_wave:         move    r24,r20                 ; (reg-16)*4
                subq    #32,r20
                subq    #32,r20                 ; (reg-$30)*4
                shlq    #1,r20                  ; sample index * 4
                add     r15,r20
                move    r25,r21
                shrq    #4,r21
                subq    #8,r21
                shlq    #1,r21
                store   r21,(r20)
                addqt   #4,r20
                moveq   #15,r21
                and     r25,r21
                subq    #8,r21
                shlq    #1,r21
                store   r21,(r20)
                jump    t,(r27)
                nop

; ---- trigger channel r26
w_trig:
                move    r26,r22
                addq    #C_DAC,r22
                load    (r22),r20
                store   r20,(r26)               ; on = DAC
                move    r26,r22                 ; length 0 -> full
                addq    #C_LEN,r22
                load    (r22),r20
                cmpq    #0,r20
                jr      ne,wt_l
                nop
                movei   #64,r20
                movei   #SV+128,r21
                cmp     r21,r26
                jr      ne,wt_l0
                nop
                movei   #256,r20
wt_l0:          store   r20,(r22)
wt_l:           ; initial volume and envelope counter
                movei   #INITVOL,r22
                move    r26,r23
                movei   #SV,r24
                sub     r24,r23
                shrq    #4,r23
                add     r23,r22
                load    (r22),r20
                move    r26,r22
                addq    #C_VOL,r22
                store   r20,(r22)
                move    r26,r22
                addq    #C_ENVPER,r22
                load    (r22),r20
                addqt   #4,r22
                store   r20,(r22)               ; ENVCNT = ENVPER
                ; per channel
                movei   #SV+128,r21
                cmp     r21,r26
                jr      ne,wt_n3
                nop
                moveq   #0,r4                   ; wave restarts
                movei   #wt_x,r23
                jump    t,(r23)
                nop
wt_n3:          movei   #SV+192,r21
                cmp     r21,r26
                jr      ne,wt_n4
                nop
                movei   #$7fff,r6
                movei   #wt_x,r23
                jump    t,(r23)
                nop
wt_n4:          movei   #SV,r21
                cmp     r21,r26
                movei   #wt_x,r23
                jump    ne,(r23)
                nop
                movei   #SV+C_FREQ,r22          ; ch1 sweep
                load    (r22),r20
                movei   #SV+C_SHADOW,r22
                store   r20,(r22)
                movei   #SV+C_SWPER,r22
                load    (r22),r20
                cmpq    #0,r20
                jr      ne,wt_sp
                nop
                moveq   #8,r20
wt_sp:          movei   #SV+C_SWCNT,r22
                store   r20,(r22)
                movei   #SV+C_SWPER,r22
                load    (r22),r20
                movei   #SV+C_SWSH,r22
                load    (r22),r21
                or      r21,r20
                movei   #SV+C_SWEN,r22
                store   r20,(r22)
wt_x:           movei   #inc_upd,r23
                jump    t,(r23)
                nop

; ---- recompute the phase increment of channel r26, then amplitudes
inc_upd:
                movei   #SV+192,r21
                cmp     r21,r26
                movei   #iu_noise,r23
                jump    eq,(r23)
                nop
                move    r26,r22
                addq    #C_FREQ,r22
                load    (r22),r20
                movei   #2048,r21
                sub     r20,r21                 ; 2048 - f
                cmpq    #8,r21
                jr      cc,iu_ok
                nop
                moveq   #8,r21
iu_ok:          movei   #SQ_K,r20
                div     r21,r20
                movei   #SV+128,r21
                cmp     r21,r26
                movei   #iu_w,r23
                jump    eq,(r23)
                nop
                shlq    #8,r20
                movei   #SV,r21
                cmp     r21,r26
                jr      ne,iu_2
                nop
                move    r20,r1
                movei   #amp_upd,r23
                jump    t,(r23)
                nop
iu_2:           move    r20,r3
                movei   #amp_upd,r23
                jump    t,(r23)
                nop
iu_w:           shlq    #7,r20
                move    r20,r5
                movei   #amp_upd,r23
                jump    t,(r23)
                nop
iu_noise:       movei   #SV+192+C_SWPER,r22
                load    (r22),r20               ; divisor code r
                shlq    #4,r20
                cmpq    #0,r20
                jr      ne,iu_r
                nop
                moveq   #8,r20
iu_r:           addqt   #4,r22
                load    (r22),r21               ; clock shift s
                neg     r21
                sh      r21,r20                 ; divisor << s
                movei   #NZ_K,r21
                div     r20,r21
                move    r21,r8
                ; fall through
; ---- amplitude registers from channel state; channel-on status for NR52
amp_upd:
                movei   #SV,r22
                load    (r22),r20
                moveq   #0,r9
                cmpq    #0,r20
                jr      eq,au1
                nop
                addqt   #C_VOL,r22
                load    (r22),r9
au1:            movei   #SV+64,r22
                load    (r22),r20
                moveq   #0,r10
                cmpq    #0,r20
                jr      eq,au2
                nop
                addqt   #C_VOL,r22
                load    (r22),r10
au2:            movei   #SV+128,r22
                load    (r22),r20
                moveq   #4,r11                  ; muted
                cmpq    #0,r20
                jr      eq,au3
                nop
                movei   #SV+128+C_DUTY,r22
                load    (r22),r20               ; volume code 0 mute, 1 100%, 2 50%, 3 25%
                cmpq    #0,r20
                jr      eq,au3
                nop
                subq    #1,r20
                move    r20,r11
au3:            movei   #SV+192,r22
                load    (r22),r20
                moveq   #0,r12
                cmpq    #0,r20
                jr      eq,au4
                nop
                addqt   #C_VOL,r22
                load    (r22),r12
au4:            ; NR52 status bits
                moveq   #0,r21
                movei   #SV,r22
                load    (r22),r20
                or      r20,r21
                movei   #SV+64,r22
                load    (r22),r20
                shlq    #1,r20
                or      r20,r21
                movei   #SV+128,r22
                load    (r22),r20
                shlq    #2,r20
                or      r20,r21
                movei   #SV+192,r22
                load    (r22),r20
                shlq    #3,r20
                or      r20,r21
                movei   #DSTATUS,r22
                store   r21,(r22)
                jump    t,(r27)
                nop

; ---- length counters (256 Hz)
len_tick:
                movei   #SV,r26
                moveq   #4,r25
lt_l:           move    r26,r22
                addq    #C_LENEN,r22
                load    (r22),r20
                cmpq    #0,r20
                jr      eq,lt_n
                nop
                move    r26,r22
                addq    #C_LEN,r22
                load    (r22),r20
                cmpq    #0,r20
                jr      eq,lt_n
                nop
                subq    #1,r20
                store   r20,(r22)
                jr      ne,lt_n
                nop
                store   r20,(r26)               ; expired: off
lt_n:           movei   #64,r20
                add     r20,r26
                subq    #1,r25
                movei   #lt_l,r23
                jump    ne,(r23)
                nop
                movei   #amp_upd,r23
                jump    t,(r23)
                nop

; ---- envelopes (64 Hz): channels 1, 2, 4
env_tick:
                movei   #SV,r26
                movei   #et_ret1,r24
                jr      t,et_ch
                nop
et_ret1:        movei   #SV+64,r26
                movei   #et_ret2,r24
                jr      t,et_ch
                nop
et_ret2:        movei   #SV+192,r26
                movei   #amp_upd,r24
et_ch:          move    r26,r22
                addq    #C_ENVPER,r22
                load    (r22),r20
                cmpq    #0,r20
                jump    eq,(r24)                ; envelope off
                nop
                addqt   #4,r22
                load    (r22),r21               ; count
                subq    #1,r21
                movei   #et_s,r23
                jump    ne,(r23)
                nop
                move    r20,r21                 ; reload
                store   r21,(r22)
                move    r26,r22
                addq    #C_ENVDIR,r22
                load    (r22),r20
                move    r26,r22
                addq    #C_VOL,r22
                load    (r22),r21
                cmpq    #0,r20
                jr      eq,et_dn
                nop
                cmpq    #15,r21
                jr      eq,et_x
                nop
                addq    #1,r21
                store   r21,(r22)
                jr      t,et_x
                nop
et_dn:          cmpq    #0,r21
                jr      eq,et_x
                nop
                subq    #1,r21
                store   r21,(r22)
                jr      t,et_x
                nop
et_s:           store   r21,(r22)
et_x:           jump    t,(r24)
                nop

; ---- sweep (128 Hz): channel 1
sweep_tick:
                movei   #SV+C_SWEN,r22
                load    (r22),r20
                cmpq    #0,r20
                movei   #sw_x,r23
                jump    eq,(r23)
                nop
                movei   #SV+C_SWCNT,r22
                load    (r22),r21
                subq    #1,r21
                jr      eq,sw_do
                nop
                store   r21,(r22)
                jump    t,(r23)
                nop
sw_do:          movei   #SV+C_SWPER,r24
                load    (r24),r20
                cmpq    #0,r20
                jr      ne,sw_p
                nop
                moveq   #8,r20
sw_p:           store   r20,(r22)
                load    (r24),r20
                cmpq    #0,r20
                jump    eq,(r23)
                nop
                movei   #SV+C_SHADOW,r22
                load    (r22),r20
                movei   #SV+C_SWSH,r24
                load    (r24),r21
                move    r20,r25
                sh      r21,r25                 ; shadow >> shift
                movei   #SV+C_SWNEG,r24
                load    (r24),r21
                cmpq    #0,r21
                jr      eq,sw_add
                nop
                sub     r25,r20
                jr      t,sw_chk
                nop
sw_add:         add     r25,r20
sw_chk:         movei   #2047,r21
                cmp     r20,r21                 ; 2047 - new
                jr      cc,sw_ok                ; no borrow: new <= 2047
                nop
                moveq   #0,r21                  ; overflow: channel off
                movei   #SV,r22
                store   r21,(r22)
                movei   #SV,r26
                movei   #amp_upd,r23
                jump    t,(r23)
                nop
sw_ok:          movei   #SV+C_SWSH,r24
                load    (r24),r21
                cmpq    #0,r21
                jump    eq,(r23)
                nop
                movei   #SV+C_SHADOW,r22
                store   r20,(r22)
                movei   #SV+C_FREQ,r22
                store   r20,(r22)
                movei   #SV,r26
                movei   #inc_upd,r23
                jump    t,(r23)
                nop
sw_x:           jump    t,(r27)
                nop

                .long
dutytab:        dc.l    $01,$81,$87,$7e
INITVOL:        dc.l    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
dsp_end_addr:
                .68000
                .phrase
dsp_code_end::





