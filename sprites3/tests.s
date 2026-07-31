.setcpu "65C02"

.include "lynx.inc"
.include "../shared/sprites.inc"

TEST_COUNT = 8

.segment "RODATA"

; Four packed RLE packets, each repeating one pen for 16 pixels.
; Pens 0, E, F, and 1 exercise transparency, shadow, boundary, and ordinary
; color/collision behavior against the prefilled video and collision buffers.
PackedTypePensW64:
    .byte 7, $78, $3F, $9F, $EF, $10, 0, 0

.segment "DATA"

DEFINE_SCB ScbBackground, BPP_4 | TYPE_BACKGROUND, REHV | PACKED, 5, 0, PackedTypePensW64, 0, 0, $0100, $6600
DEFINE_SCB ScbBackNonColl, BPP_4 | TYPE_BACKNONCOLL, REHV | PACKED, 5, 0, PackedTypePensW64, 0, 0, $0100, $6600
DEFINE_SCB ScbBoundaryShadow, BPP_4 | TYPE_BSHADOW, REHV | PACKED, 5, 0, PackedTypePensW64, 0, 0, $0100, $6600
DEFINE_SCB ScbBoundary, BPP_4 | TYPE_BOUNDARY, REHV | PACKED, 5, 0, PackedTypePensW64, 0, 0, $0100, $6600
DEFINE_SCB ScbNormal, BPP_4 | TYPE_NORMAL, REHV | PACKED, 5, 0, PackedTypePensW64, 0, 0, $0100, $6600
DEFINE_SCB ScbNonColl, BPP_4 | TYPE_NONCOLL, REHV | PACKED, 5, 0, PackedTypePensW64, 0, 0, $0100, $6600
DEFINE_SCB ScbXor, BPP_4 | TYPE_XOR, REHV | PACKED, 5, 0, PackedTypePensW64, 0, 0, $0100, $6600
DEFINE_SCB ScbShadow, BPP_4 | TYPE_SHADOW, REHV | PACKED, 5, 0, PackedTypePensW64, 0, 0, $0100, $6600

.segment "RODATA"

TestDescriptors:
    TEST_DESCRIPTOR ScbBackground, 0, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbBackNonColl, 0, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbBoundaryShadow, 0, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbBoundary, 0, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbNormal, 0, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbNonColl, 0, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbXor, 0, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbShadow, 0, DISPLAY_DMA_OFF

.segment "CODE"

.proc PrepareTest
    rts
.endproc

.include "../shared/sprite-runner.inc"
