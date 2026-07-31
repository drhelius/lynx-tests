.setcpu "65C02"

.include "lynx.inc"

SCB_COLL_RESULT = 27

.include "../shared/sprites.inc"

TEST_COUNT = 8

.segment "RODATA"

; One opaque 4-bpp pen expanded by Suzy's size accumulators.
Literal4OnePen:
    .byte 2, $22, 0

; Sixteen rows of 17 pens. Each row rotates the 0-F color sequence so both
; horizontal and vertical half-scale source selection are visible.
Literal4ZoomOut:
    .repeat 16, row
        .byte 10
        .repeat 9, column
            .byte ((((row + column * 2) & $0F) << 4) | ((row + column * 2 + 1) & $0F))
        .endrepeat
    .endrepeat
    .byte 0

.segment "DATA"

DEFINE_SCB_HV_PADDED ScbZoomOutHalf, BPP_4 | TYPE_BACKNONCOLL, 0, 0, Literal4ZoomOut, 76, 47, $0080, $0080
DEFINE_SCB_HV_PADDED ScbZoom16x8, BPP_4 | TYPE_BACKNONCOLL, 0, 0, Literal4OnePen, 72, 47, $1000, $0800
DEFINE_SCB_HVS_PADDED ScbStretchHalf, BPP_4 | TYPE_BACKNONCOLL, 0, 0, Literal4OnePen, 68, 47, $0800, $0800, $0080
DEFINE_SCB_HVS_PADDED ScbStretchNegative, BPP_4 | TYPE_BACKNONCOLL, 0, 0, Literal4OnePen, 68, 47, $0F00, $0800, $FF00
DEFINE_SCB_HVST ScbTiltHalf, BPP_4 | TYPE_BACKNONCOLL, 0, 0, Literal4OnePen, 72, 47, $0800, $0800, $0000, $0080
DEFINE_SCB_HVST ScbTiltPositive, BPP_4 | TYPE_BACKNONCOLL, 0, 0, Literal4OnePen, 72, 47, $0800, $0800, $0000, $0100
DEFINE_SCB_HVST ScbTiltNegative, BPP_4 | TYPE_BACKNONCOLL, 0, 0, Literal4OnePen, 72, 47, $0800, $0800, $0000, $FF00
DEFINE_SCB_HVST ScbStretchTilt, BPP_4 | TYPE_BACKNONCOLL, 0, 0, Literal4OnePen, 68, 47, $0800, $0800, $0100, $0100

.segment "RODATA"

TestDescriptors:
    TEST_DESCRIPTOR ScbZoomOutHalf, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbZoom16x8, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbStretchHalf, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbStretchNegative, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbTiltHalf, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbTiltPositive, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbTiltNegative, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbStretchTilt, NO_COLLIDE, DISPLAY_DMA_OFF

.segment "CODE"

.proc PrepareTest
    rts
.endproc

.include "../shared/sprite-runner.inc"
