; Shared Suzy sprite-test constants and data macros

VIDEO_BASE       = $9000
DISPLAY_BASE     = $B000
COLLISION_BASE   = $D000
SCREEN_BYTES     = $1FE0
GUARD_BYTES      = 8
BUFFER_BYTES     = SCREEN_BYTES + GUARD_BYTES
SCB_COLL_RESULT  = 23

DISPLAY_DMA_OFF  = $0C
DISPLAY_DMA_ON   = $0D

.macro DEFINE_SCB name, control0, control1, collision, next, data, hpos, vpos, hsize, vsize
name:
    .byte control0
    .byte control1
    .byte collision
    .word next
    .word data
    .word hpos
    .word vpos
    .word hsize
    .word vsize
    .byte $01, $23, $45, $67, $89, $AB, $CD, $EF
    .byte 0
.endmacro

.macro TEST_DESCRIPTOR scb, sprsys, dispctl
    .word scb
    .byte sprsys
    .byte dispctl
.endmacro
