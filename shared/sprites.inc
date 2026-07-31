; Shared Suzy sprite-test constants and data macros

VIDEO_BASE       = $9000
DISPLAY_BASE     = $B000
COLLISION_BASE   = $D000
SCREEN_BYTES     = $1FE0
GUARD_BYTES      = 8
BUFFER_BYTES     = SCREEN_BYTES + GUARD_BYTES
.ifndef SCB_COLL_RESULT
SCB_COLL_RESULT  = 23
.endif

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

.macro DEFINE_SCB_HVST name, control0, collision, next, data, hpos, vpos, hsize, vsize, stretch, tilt
name:
    .byte control0
    .byte REHVST | LITERAL
    .byte collision
    .word next
    .word data
    .word hpos
    .word vpos
    .word hsize
    .word vsize
    .word stretch
    .word tilt
    .byte $01, $23, $45, $67, $89, $AB, $CD, $EF
    .byte 0
.endmacro

.macro DEFINE_SCB_HV_PADDED name, control0, collision, next, data, hpos, vpos, hsize, vsize
name:
    .byte control0
    .byte REHV | LITERAL
    .byte collision
    .word next
    .word data
    .word hpos
    .word vpos
    .word hsize
    .word vsize
    .byte $01, $23, $45, $67, $89, $AB, $CD, $EF
    .byte 0, 0, 0, 0
    .byte 0
.endmacro

.macro DEFINE_SCB_HVS_PADDED name, control0, collision, next, data, hpos, vpos, hsize, vsize, stretch
name:
    .byte control0
    .byte REHVS | LITERAL
    .byte collision
    .word next
    .word data
    .word hpos
    .word vpos
    .word hsize
    .word vsize
    .word stretch
    .byte $01, $23, $45, $67, $89, $AB, $CD, $EF
    .byte 0, 0
    .byte 0
.endmacro

.macro TEST_DESCRIPTOR scb, sprsys, dispctl
    .word scb
    .byte sprsys
    .byte dispctl
.endmacro
