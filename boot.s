; cartridge entry ($802000): copy the program image (at $802100) to $4000 and run it
                .text
                .68000
boot::
                move.w  #$2700,sr
                lea     $3ff0,a7
                lea     $802100,a0
                lea     $4000,a1
                move.l  img_size(pc),d0
                addq.l  #3,d0
                lsr.l   #2,d0
.c:             move.l  (a0)+,(a1)+
                subq.l  #1,d0
                bne.s   .c
                jmp     $4000
                .long
img_size::      dc.l    0
