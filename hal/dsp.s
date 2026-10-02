; ---------------------------------------------------------------------------
; DSP program: two GB APUs (4 channels each) synthesised at the I2S rate
; (~20.8 kHz) and mixed: instance A plays the music, instance B the sound
; effects (the game's sound engine runs twice, see snd_* in hal/hle.s), so a
; sound effect no longer takes a channel from the music.
; The 68k queues sound register writes (bit 15 = instance B | reg<<8 | value,
; one long each) into DQ; everything runs in the I2S interrupt (register bank
; 0, which the idle main loop never uses). The current instance's channel state
; is in r0-r13, r16, r17 and in its memory block (base r14, wave samples r15);
; the other instance's registers wait in its block (O_CTX).
; Loaded at $F1B000 by init_dsp.
; ---------------------------------------------------------------------------
SVA             equ     $f1c000         ; instance A: 4 channel blocks of 64 bytes, ...
SVB             equ     $f1c200         ; instance B
O_IVOL          equ     256             ; 4 longs: initial volume (NRx2) per channel
O_WAVE          equ     320             ; 32 longs: wave samples, signed (s-8)*2
O_CTX           equ     448             ; 16 longs: r0-r13, r16, r17 while not current
SVX             equ     $f1c400         ; frame sequencer step
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

; rN := address of field X of the current instance
                .macro  SVR ofs,dst
                movei   #\ofs,\dst
                add     r14,\dst
                .endm
; the instance registers to / from the area at r20
                .macro  CTXSTORE
                store   r0,(r20)
                addqt   #4,r20
                store   r1,(r20)
                addqt   #4,r20
                store   r2,(r20)
                addqt   #4,r20
                store   r3,(r20)
                addqt   #4,r20
                store   r4,(r20)
                addqt   #4,r20
                store   r5,(r20)
                addqt   #4,r20
                store   r6,(r20)
                addqt   #4,r20
                store   r7,(r20)
                addqt   #4,r20
                store   r8,(r20)
                addqt   #4,r20
                store   r9,(r20)
                addqt   #4,r20
                store   r10,(r20)
                addqt   #4,r20
                store   r11,(r20)
                addqt   #4,r20
                store   r12,(r20)
                addqt   #4,r20
                store   r13,(r20)
                addqt   #4,r20
                store   r16,(r20)
                addqt   #4,r20
                store   r17,(r20)
                .endm
                .macro  CTXLOAD
                load    (r20),r0
                addqt   #4,r20
                load    (r20),r1
                addqt   #4,r20
                load    (r20),r2
                addqt   #4,r20
                load    (r20),r3
                addqt   #4,r20
                load    (r20),r4
                addqt   #4,r20
                load    (r20),r5
                addqt   #4,r20
                load    (r20),r6
                addqt   #4,r20
                load    (r20),r7
                addqt   #4,r20
                load    (r20),r8
                addqt   #4,r20
                load    (r20),r9
                addqt   #4,r20
                load    (r20),r10
                addqt   #4,r20
                load    (r20),r11
                addqt   #4,r20
                load    (r20),r12
                addqt   #4,r20
                load    (r20),r13
                addqt   #4,r20
                load    (r20),r16
                addqt   #4,r20
                load    (r20),r17
                .endm

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
                movei   #SVB+O_CTX,r20          ; (instance B starts in the same state)
                CTXSTORE
                movei   #SVA,r14
                movei   #SVA+O_WAVE,r15
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

; ---- instance switches: return through r21, use r20
to_b:           movei   #SVA+O_CTX,r20
                CTXSTORE
                movei   #SVB+O_CTX,r20
                CTXLOAD
                movei   #SVB,r14
                movei   #SVB+O_WAVE,r15
                jump    t,(r21)
                nop
to_a:           movei   #SVB+O_CTX,r20
                CTXSTORE
                movei   #SVA+O_CTX,r20
                CTXLOAD
                movei   #SVA,r14
                movei   #SVA+O_WAVE,r15
                jump    t,(r21)
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
                load    (r23),r25               ; B << 15 | reg << 8 | value
                addq    #1,r22
                movei   #$ff,r24
                and     r24,r22
                store   r22,(r20)
                move    r25,r24
                shrq    #8,r24                  ; B << 7 | reg ($10-$3f)
                movei   #$ff,r23
                and     r23,r25                 ; value
                movei   #no_cmd,r27             ; handlers return through r27
                btst    #7,r24
                jr      eq,cmd_d
                nop
                bclr    #7,r24                  ; instance B: switch, then back after it
                movei   #cmd_b,r21
                movei   #to_b,r23
                jump    t,(r23)
                nop
cmd_b:          movei   #cmd_ba,r27
cmd_d:          subq    #16,r24
                movei   #48,r23
                cmp     r23,r24
                jump    cc,(r27)                ; not a sound register
                nop
                shlq    #2,r24
                movei   #rtab,r23
                add     r24,r23
                load    (r23),r23
                jump    t,(r23)
                nop
cmd_ba:         movei   #no_cmd,r21
                movei   #to_a,r23
                jump    t,(r23)
                nop
no_cmd:
                ; ---- frame sequencer (512 Hz), for A then for B if it plays
                movei   #FS_SEQ,r20
                add     r20,r18
                move    r18,r20
                shrq    #16,r20
                movei   #synth_ab,r23
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
                movei   #tk_a,r19
                movei   #ticks,r23
                jump    t,(r23)
                nop
tk_a:           movei   #DSTATUSB,r20
                load    (r20),r20
                cmpq    #0,r20
                movei   #synth_ab,r23
                jump    eq,(r23)
                nop
                movei   #tk_b0,r21
                movei   #to_b,r23
                jump    t,(r23)
                nop
tk_b0:          movei   #tk_b,r19
                movei   #ticks,r23
                jump    t,(r23)
                nop
tk_b:           movei   #synth_ab,r21
                movei   #to_a,r23
                jump    t,(r23)
                nop

; ---- length / sweep / envelope ticks of the current instance; return through r19
ticks:
                movei   #SVX,r20
                load    (r20),r21
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
                jump    ne,(r19)
                nop
                move    r19,r27
                movei   #env_tick,r23
                jump    t,(r23)
                nop

; ---- synthesis of A, plus B when it plays, saturated, to the DAC
synth_ab:
                movei   #sy_a,r30
                movei   #synth,r23
                jump    t,(r23)
                nop
sy_a:           move    r22,r19                 ; (A: left, right)
                move    r23,r27
                movei   #DSTATUSB,r20
                load    (r20),r20
                cmpq    #0,r20
                movei   #sy_out,r23
                jump    eq,(r23)
                nop
                movei   #sy_b0,r21
                movei   #to_b,r23
                jump    t,(r23)
                nop
sy_b0:          movei   #sy_b,r30
                movei   #synth,r23
                jump    t,(r23)
                nop
sy_b:           add     r22,r19
                add     r23,r27
                movei   #sy_out,r21
                movei   #to_a,r23
                jump    t,(r23)
                nop
sy_out:         shlq    #6,r19
                shlq    #6,r27
                sat16s  r19
                sat16s  r27
                movei   #L_I2S,r20
                store   r19,(r20)
                addqt   #4,r20
                store   r27,(r20)
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

; ---- one sample of the current instance: r22 = left, r23 = right (NR50 applied);
;      return through r30
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
s4c:            SVR     192+C_DUTY,r26
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
s4r:            ; master volume (NR50)
                move    r17,r20
                shrq    #4,r20
                moveq   #7,r21
                and     r21,r20
                addq    #1,r20
                imult   r20,r22
                move    r17,r20
                and     r21,r20
                addq    #1,r20
                jump    t,(r30)
                imult   r20,r23

; ---------------------------------------------------------------------------
; register write handlers (current instance): r25 = value; return through r27;
; temps r20-r26
; ---------------------------------------------------------------------------
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

w_nr10:         SVR     C_SWPER,r26
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
w_nr11:         move    r14,r26
                moveq   #0,r21
                jr      t,w_dl
                nop
w_nr21:         SVR     64,r26
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
w_nr12:         move    r14,r26
                jr      t,w_env
                nop
w_nr22:         SVR     64,r26
                jr      t,w_env
                nop
w_nr42:         SVR     192,r26
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
                SVR     O_IVOL,r22              ; initial volume (used at the trigger)
                move    r26,r23
                sub     r14,r23
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
w_nr13:         move    r14,r26
                jr      t,w_fl
                nop
w_nr23:         SVR     64,r26
                jr      t,w_fl
                nop
w_nr33:         SVR     128,r26
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
w_nr14:         move    r14,r26
                jr      t,w_fh
                nop
w_nr24:         SVR     64,r26
                jr      t,w_fh
                nop
w_nr34:         SVR     128,r26
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
w_nr44:         SVR     192,r26
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
w_nr30:         SVR     128+C_DAC,r22
                move    r25,r20
                shrq    #7,r20
                store   r20,(r22)
                cmpq    #0,r20
                jr      ne,w_n30x
                nop
                SVR     128,r26
                moveq   #0,r20
                store   r20,(r26)
                movei   #amp_upd,r23
                jump    t,(r23)
                nop
w_n30x:         jump    t,(r27)
                nop
w_nr31:         movei   #256,r20
                sub     r25,r20
                SVR     128+C_LEN,r22
                store   r20,(r22)
                jump    t,(r27)
                nop
w_nr32:         move    r25,r20
                shrq    #5,r20
                moveq   #3,r21
                and     r21,r20
                SVR     128+C_DUTY,r22
                store   r20,(r22)
                SVR     128,r26
                movei   #amp_upd,r23
                jump    t,(r23)
                nop

; ch4
w_nr41:         moveq   #31,r20
                addq    #31,r20
                addq    #2,r20
                moveq   #31,r22
                addq    #32,r22
                and     r25,r22
                sub     r22,r20
                SVR     192+C_LEN,r22
                store   r20,(r22)
                jump    t,(r27)
                nop
w_nr43:         SVR     192+C_DUTY,r22
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
                SVR     192,r26
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
                store   r20,(r14)
                SVR     64,r22
                store   r20,(r22)
                SVR     128,r22
                store   r20,(r22)
                SVR     192,r22
                store   r20,(r22)
                moveq   #0,r9
                moveq   #0,r10
                moveq   #4,r11
                moveq   #0,r12
                movei   #amp_upd,r23            ; (status)
                jump    t,(r23)
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
                SVR     128,r21
                cmp     r21,r26
                jr      ne,wt_l0
                nop
                movei   #256,r20
wt_l0:          store   r20,(r22)
wt_l:           ; initial volume and envelope counter
                SVR     O_IVOL,r22
                move    r26,r23
                sub     r14,r23
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
                SVR     128,r21
                cmp     r21,r26
                jr      ne,wt_n3
                nop
                moveq   #0,r4                   ; wave restarts
                movei   #wt_x,r23
                jump    t,(r23)
                nop
wt_n3:          SVR     192,r21
                cmp     r21,r26
                jr      ne,wt_n4
                nop
                movei   #$7fff,r6
                movei   #wt_x,r23
                jump    t,(r23)
                nop
wt_n4:          cmp     r14,r26
                movei   #wt_x,r23
                jump    ne,(r23)
                nop
                SVR     C_FREQ,r22              ; ch1 sweep
                load    (r22),r20
                SVR     C_SHADOW,r22
                store   r20,(r22)
                SVR     C_SWPER,r22
                load    (r22),r20
                cmpq    #0,r20
                jr      ne,wt_sp
                nop
                moveq   #8,r20
wt_sp:          SVR     C_SWCNT,r22
                store   r20,(r22)
                SVR     C_SWPER,r22
                load    (r22),r20
                SVR     C_SWSH,r22
                load    (r22),r21
                or      r21,r20
                SVR     C_SWEN,r22
                store   r20,(r22)
wt_x:           movei   #inc_upd,r23
                jump    t,(r23)
                nop

; ---- recompute the phase increment of channel r26, then amplitudes
inc_upd:
                SVR     192,r21
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
                SVR     128,r21
                cmp     r21,r26
                movei   #iu_w,r23
                jump    eq,(r23)
                nop
                shlq    #8,r20
                cmp     r14,r26
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
iu_noise:       SVR     192+C_SWPER,r22
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
                load    (r14),r20
                moveq   #0,r9
                cmpq    #0,r20
                jr      eq,au1
                nop
                SVR     C_VOL,r22
                load    (r22),r9
au1:            SVR     64,r22
                load    (r22),r20
                moveq   #0,r10
                cmpq    #0,r20
                jr      eq,au2
                nop
                addqt   #C_VOL,r22
                load    (r22),r10
au2:            SVR     128,r22
                load    (r22),r20
                moveq   #4,r11                  ; muted
                cmpq    #0,r20
                jr      eq,au3
                nop
                SVR     128+C_DUTY,r22
                load    (r22),r20               ; volume code 0 mute, 1 100%, 2 50%, 3 25%
                cmpq    #0,r20
                jr      eq,au3
                nop
                subq    #1,r20
                move    r20,r11
au3:            SVR     192,r22
                load    (r22),r20
                moveq   #0,r12
                cmpq    #0,r20
                jr      eq,au4
                nop
                addqt   #C_VOL,r22
                load    (r22),r12
au4:            ; NR52 status bits (DSTATUS: A, DSTATUSB: B)
                load    (r14),r21
                SVR     64,r22
                load    (r22),r20
                shlq    #1,r20
                or      r20,r21
                SVR     128,r22
                load    (r22),r20
                shlq    #2,r20
                or      r20,r21
                SVR     192,r22
                load    (r22),r20
                shlq    #3,r20
                or      r20,r21
                movei   #DSTATUS,r22
                btst    #9,r14                  ; (SVB)
                jr      eq,au5
                nop
                addqt   #4,r22
au5:            store   r21,(r22)
                jump    t,(r27)
                nop

; ---- length counters (256 Hz)
len_tick:
                move    r14,r26
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
                move    r14,r26
                movei   #et_ret1,r24
                movei   #et_ch,r23
                jump    t,(r23)
                nop
et_ret1:        SVR     64,r26
                movei   #et_ret2,r24
                movei   #et_ch,r23
                jump    t,(r23)
                nop
et_ret2:        SVR     192,r26
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
                SVR     C_SWEN,r22
                load    (r22),r20
                cmpq    #0,r20
                movei   #sw_x,r23
                jump    eq,(r23)
                nop
                SVR     C_SWCNT,r22
                load    (r22),r21
                subq    #1,r21
                jr      eq,sw_do
                nop
                store   r21,(r22)
                jump    t,(r23)
                nop
sw_do:          SVR     C_SWPER,r24
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
                SVR     C_SHADOW,r22
                load    (r22),r20
                SVR     C_SWSH,r24
                load    (r24),r21
                move    r20,r25
                sh      r21,r25                 ; shadow >> shift
                SVR     C_SWNEG,r24
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
                store   r21,(r14)
                move    r14,r26
                movei   #amp_upd,r23
                jump    t,(r23)
                nop
sw_ok:          SVR     C_SWSH,r24
                load    (r24),r21
                cmpq    #0,r21
                jump    eq,(r23)
                nop
                SVR     C_SHADOW,r22
                store   r20,(r22)
                SVR     C_FREQ,r22
                store   r20,(r22)
                move    r14,r26
                movei   #inc_upd,r23
                jump    t,(r23)
                nop
sw_x:           jump    t,(r27)
                nop

                .long
dutytab:        dc.l    $01,$81,$87,$7e
dsp_end_addr:
                .if     dsp_end_addr > SVA
                .error  "DSP code too long"
                .endif
                .68000
                .phrase
dsp_code_end::
