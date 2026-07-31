.setcpu "65C02"

.include "lynx.inc"
.include "../shared/sprites.inc"

TEST_COUNT = 8

.segment "RODATA"

; 167 literal 1-bpp pens (all palette index 1), then source terminator.
Literal1Full:
    .byte $16
    .repeat 21
        .byte $FF
    .endrepeat
    .byte 0

; 163 literal 2-bpp pens (all palette index 3), then source terminator.
Literal2Full:
    .byte $2A
    .repeat 41
        .byte $FF
    .endrepeat
    .byte 0

; 162 literal 3-bpp pens (all palette index 7), then source terminator.
Literal3Full:
    .byte $3E
    .repeat 61
        .byte $FF
    .endrepeat
    .byte 0

; 161 literal 4-bpp pens (all palette index 1), then source terminator.
Literal4Full:
    .byte $52
    .repeat 81
        .byte $11
    .endrepeat
    .byte 0

; One accepted literal 4-bpp pen. The final nibble is the line end bit.
Literal4OnePen:
    .byte 2, $22, 0

.segment "DATA"

DEFINE_SCB ScbLiteral1Full, BPP_1 | TYPE_BACKNONCOLL, REHV | LITERAL, 0, 0, Literal1Full, 0, 0, $0100, $6600
DEFINE_SCB ScbLiteral2Full, BPP_2 | TYPE_BACKNONCOLL, REHV | LITERAL, 0, 0, Literal2Full, 0, 0, $0100, $6600
DEFINE_SCB ScbLiteral3Full, BPP_3 | TYPE_BACKNONCOLL, REHV | LITERAL, 0, 0, Literal3Full, 0, 0, $0100, $6600
DEFINE_SCB ScbLiteral4Full, BPP_4 | TYPE_BACKNONCOLL, REHV | LITERAL, 0, 0, Literal4Full, 0, 0, $0100, $6600
DEFINE_SCB ScbLiteral1Small, BPP_1 | TYPE_BACKNONCOLL, REHV | LITERAL, 0, 0, Literal1Full, 0, 0, $0020, $6600
DEFINE_SCB ScbLiteral4Small, BPP_4 | TYPE_BACKNONCOLL, REHV | LITERAL, 0, 0, Literal4Full, 0, 0, $0020, $6600
DEFINE_SCB ScbExpandW8, BPP_4 | TYPE_BACKNONCOLL, REHV | LITERAL, 0, 0, Literal4OnePen, 0, 0, $0800, $6600
DEFINE_SCB ScbExpandW64, BPP_4 | TYPE_BACKNONCOLL, REHV | LITERAL, 0, 0, Literal4OnePen, 0, 0, $4000, $6600

.segment "RODATA"

TestDescriptors:
    TEST_DESCRIPTOR ScbLiteral1Full, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbLiteral2Full, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbLiteral3Full, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbLiteral4Full, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbLiteral1Small, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbLiteral4Small, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbExpandW8, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbExpandW64, NO_COLLIDE, DISPLAY_DMA_OFF

.proc PrepareTest
    rts
.endproc

.include "../shared/sprite-runner.inc"
