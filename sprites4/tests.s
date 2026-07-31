.setcpu "65C02"

.include "lynx.inc"
.include "../shared/sprites.inc"

TEST_COUNT = 8

.segment "RODATA"

; Two 16-pen RLE packets, 32 opaque pen-1 outputs.
PackedRleW32:
    .byte $04, $78, $BC, $40, 0

; Four 16-pen RLE packets, 64 opaque pen-1 outputs.
PackedRleW64:
    .byte $07, $78, $BC, $5E, $2F, $10, 0, 0

; Four 16-pen literal packets, 64 opaque pen-1 outputs.
PackedLiteralW64:
    .byte $25
    .byte $F8, $88, $88, $88, $88, $88, $88, $88, $8F
    .byte $C4, $44, $44, $44, $44, $44, $44, $44, $7E
    .byte $22, $22, $22, $22, $22, $22, $22, $22, $23
    .byte $F1, $11, $11, $11, $11, $11, $11, $11, $10
    .byte 0, 0

; Four 16-pen RLE packets using special pen E.
PackedRlePenE:
    .byte $07, $7F, $3F, $9F, $CF, $E0, 0, 0

; Four 16-pen RLE packets using collidable pen F.
PackedRlePenF:
    .byte $07, $7F, $BF, $DF, $EF, $F0, 0, 0

; One accepted literal 4-bpp pen for display-DMA expansion.
Literal4OnePen:
    .byte 2, $22, 0

.segment "DATA"

DEFINE_SCB ScbPackedRleW32, BPP_4 | TYPE_BACKNONCOLL, REHV | PACKED, 5, 0, PackedRleW32, 0, 0, $0100, $6600
DEFINE_SCB ScbPackedRleW64, BPP_4 | TYPE_BACKNONCOLL, REHV | PACKED, 5, 0, PackedRleW64, 0, 0, $0100, $6600
DEFINE_SCB ScbPackedLiteralW64, BPP_4 | TYPE_BACKNONCOLL, REHV | PACKED, 5, 0, PackedLiteralW64, 0, 0, $0100, $6600
DEFINE_SCB ScbPackedPenE, BPP_4 | TYPE_BACKGROUND, REHV | PACKED, 5, 0, PackedRlePenE, 0, 0, $0100, $6600
DEFINE_SCB ScbPackedXorF, BPP_4 | TYPE_XOR, REHV | PACKED, 5, 0, PackedRlePenF, 0, 0, $0100, $6600

DEFINE_SCB ScbLink2A, BPP_4 | TYPE_BACKNONCOLL, REHV | PACKED, 5, ScbLink2B, PackedRleW64, 0, 0, $0100, $0100
DEFINE_SCB ScbLink2B, BPP_4 | TYPE_BACKNONCOLL, REHV | PACKED, 5, 0, PackedRleW64, 0, 1, $0100, $0100

DEFINE_SCB ScbLink4A, BPP_4 | TYPE_BACKNONCOLL, REHV | PACKED, 5, ScbLink4B, PackedRleW64, 0, 0, $0100, $0100
DEFINE_SCB ScbLink4B, BPP_4 | TYPE_BACKNONCOLL, REHV | PACKED, 5, ScbLink4C, PackedRleW64, 0, 1, $0100, $0100
DEFINE_SCB ScbLink4C, BPP_4 | TYPE_BACKNONCOLL, REHV | PACKED, 5, ScbLink4D, PackedRleW64, 0, 2, $0100, $0100
DEFINE_SCB ScbLink4D, BPP_4 | TYPE_BACKNONCOLL, REHV | PACKED, 5, 0, PackedRleW64, 0, 3, $0100, $0100

DEFINE_SCB ScbDmaW24, BPP_4 | TYPE_BACKNONCOLL, REHV | LITERAL, 5, 0, Literal4OnePen, 0, 0, $1800, $6600

.segment "RODATA"

TestDescriptors:
    ; Display DMA is isolated to the final contention check.
    TEST_DESCRIPTOR ScbPackedRleW32, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbPackedRleW64, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbPackedLiteralW64, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbPackedPenE, 0, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbPackedXorF, 0, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbLink2A, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbLink4A, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbDmaW24, NO_COLLIDE, DISPLAY_DMA_ON

.segment "CODE"

.proc PrepareTest
    rts
.endproc

.include "../shared/sprite-runner.inc"
