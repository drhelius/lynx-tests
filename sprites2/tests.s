.setcpu "65C02"

.include "lynx.inc"
.include "../shared/sprites.inc"

TEST_COUNT = 8
HAS_PREPARE_DRAW = 1

.segment "RODATA"

; 23 accepted 1-bpp pens.
Literal1Align:
    .byte 4, $FF, $FF, 0, 0

; 23 accepted 4-bpp pens.
Literal4Align:
    .byte 13
    .repeat 12
        .byte $11
    .endrepeat
    .byte 0

; 159 accepted 1-bpp pens plus required zero pad.
Literal1Long:
    .byte 22
    .repeat 20
        .byte $FF
    .endrepeat
    .byte 0, 0

; Exact Alpine Games protection source. With HSIZOFF=$007F, the third pen-1
; reaches visible x=159.
Literal1Alpine:
    .byte 2, $A8, 0

; Fifteen 1-bpp pens in one source row, repeated vertically four times.
Literal1Vertical:
    .byte 4, $FF, $FF, 0, 0

.segment "DATA"

DEFINE_SCB ScbAlign1X0, BPP_1 | TYPE_BACKNONCOLL, REHV | LITERAL, 0, 0, Literal1Align, 0, 0, $0100, $6600
DEFINE_SCB ScbAlign1X1, BPP_1 | TYPE_BACKNONCOLL, REHV | LITERAL, 0, 0, Literal1Align, 1, 0, $0100, $6600
DEFINE_SCB ScbAlign4X1, BPP_4 | TYPE_BACKNONCOLL, REHV | LITERAL, 0, 0, Literal4Align, 1, 0, $0100, $6600
DEFINE_SCB ScbClipRight, BPP_1 | TYPE_BACKNONCOLL, REHV | LITERAL, 0, 0, Literal1Long, 159, 0, $0100, $6600
DEFINE_SCB ScbClipLeft, BPP_1 | TYPE_BACKNONCOLL | HFLIP, REHV | LITERAL, 0, 0, Literal1Long, 0, 0, $0100, $6600
DEFINE_SCB ScbSuperClip, BPP_1 | TYPE_BACKNONCOLL, REHV | LITERAL, 0, 0, Literal1Long, 160, 0, $0100, $6600
DEFINE_SCB ScbVerticalDown, BPP_1 | TYPE_BACKNONCOLL, REHV | LITERAL, 0, 0, Literal1Vertical, 0, 101, $0100, $0400

; Alpine Games SCB $59F9: SPRCTL0=$25, SPRCTL1=$90, pen 1 maps to color 5.
ScbAlpine:
    .byte BPP_1 | TYPE_NONCOLL | HFLIP
    .byte REHV | LITERAL
    .byte 0
    .word 0
    .word Literal1Alpine
    .word 163
    .word 0
    .word $00FF
    .word $0300
    .byte $05, $23, $45, $67, $89, $AB, $CD, $EF
    .byte 0

.segment "RODATA"

TestDescriptors:
    TEST_DESCRIPTOR ScbAlign1X0, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbAlign1X1, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbAlign4X1, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbClipRight, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbClipLeft, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbSuperClip, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbVerticalDown, NO_COLLIDE, DISPLAY_DMA_OFF
    TEST_DESCRIPTOR ScbAlpine, NO_COLLIDE, DISPLAY_DMA_OFF

.segment "CODE"

.proc PrepareTest
    stz HSIZOFFL
    stz HSIZOFFH

    lda test_index
    cmp #7
    bne @done

    ; Alpine protection runs with the standard half-pixel size offset.
    lda #$7F
    sta HSIZOFFL
@done:
    rts
.endproc

.proc PrepareDraw
    lda test_index
    cmp #7
    bne @done

    ; The game clears this byte before checking its low nibble for color 5.
    stz VIDEO_BASE + $4F
@done:
    rts
.endproc

.include "../shared/sprite-runner.inc"
