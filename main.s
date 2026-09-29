; Wacky Races - Atari Jaguar port: program image (linked at $4000, data in ROM)
                .include "jaguar.inc"
                .include "hal/defs.inc"
                .text
                .68000
                .include "hal/hal.s"
                .include "hal/hle.s"
                .include "gen/scdata.s"
                .include "hal/gpu.s"
                .include "hal/dsp.s"
                .include "gen/iotab.s"
                .include "gen/code.s"

                .data
                .include "gen/tables.s"
                .long
gbrom::         .incbin "build/gbrom.bin"


