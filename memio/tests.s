.setcpu "65C02"

.include "lynx.inc"

.import _set_irq
.import _get_irq

.export _run_tests
.export _g_results

;-------------------------------------------------------------------
.segment "BSS"
    _g_results: .res 18

;-------------------------------------------------------------------
.segment "ZEROPAGE"
    stage: .res 1

;-------------------------------------------------------------------
.segment "CODE"

;===================================================================
; Test 1:
;   Write and read back Mikey color registers at $FDB0-$FDBF
;===================================================================
.proc Test1

; Stage 0: Write $00, read back and verify
    ldx #$00
    lda #$00
    sta stage

@loop00:
    lda #$00
    sta $FDB0,x
    lda $FDB0,x
    cmp #$00
    bne @fail
    inx
    cpx #$10
    bne @loop00

; Stage 1: Write $FF, read back and verify
    ldx #$00
    lda #$01
    sta stage

@loopFF:
    lda #$FF
    sta $FDB0,x
    lda $FDB0,x
    cmp #$FF
    bne @fail
    inx
    cpx #$10
    bne @loopFF

; Stage 2: Write $55, read back and verify
    ldx #$00
    lda #$01
    sta stage

@loop55:
    lda #$55
    sta $FDB0,x
    lda $FDB0,x
    cmp #$55
    bne @fail
    inx
    cpx #$10
    bne @loop55

; Stage 3: Write $AA, read back and verify
    ldx #$00
    lda #$01
    sta stage

@loopAA:
    lda #$AA
    sta $FDB0,x
    lda $FDB0,x
    cmp #$AA
    bne @fail
    inx
    cpx #$10
    bne @loopAA

    stz _g_results + 0
    stz _g_results + 1
    stz _g_results + 2
    stz _g_results + 3
    rts

@fail:
    sta _g_results + 3       ; #3 actual read value
    lda #$01
    sta _g_results + 0       ; #1 failure flag = 1
    lda stage
    sta _g_results + 1       ; #2 stage
    txa
    sta _g_results + 2       ; #2 failing offset
    rts

.endproc

;===================================================================
; Test 2:
;   Write and read back Suzy registers at $FC00-$FC2F
;===================================================================
.proc Test2

; Stage 0: Write $00, read back and verify
    ldx #$00
    lda #$00
    sta stage

@loop00:
    lda #$00
    sta $FC00,x
    lda $FC00,x
    cmp #$00
    bne @fail
    inx
    cpx #$30
    bne @loop00

; Stage 1: Write $FF, read back and verify
    ldx #$00
    lda #$01
    sta stage

@loopFF:
    lda #$FF
    sta $FC00,x
    lda $FC00,x
    cmp #$FF
    bne @fail
    inx
    cpx #$30
    bne @loopFF

; Stage 2: Write $55, read back and verify
    ldx #$00
    lda #$01
    sta stage

@loop55:
    lda #$55
    sta $FC00,x
    lda $FC00,x
    cmp #$55
    bne @fail
    inx
    cpx #$30
    bne @loop55

; Stage 3: Write $AA, read back and verify
    ldx #$00
    lda #$01
    sta stage

@loopAA:
    lda #$AA
    sta $FC00,x
    lda $FC00,x
    cmp #$AA
    bne @fail
    inx
    cpx #$30
    bne @loopAA

    stz _g_results + 4
    stz _g_results + 5
    stz _g_results + 6
    stz _g_results + 7
    bra @reset_regs

@fail:
    sta _g_results + 7       ; #3 actual read value
    lda #$01
    sta _g_results + 4       ; #1 failure flag = 1
    lda stage
    sta _g_results + 5       ; #2 stage
    txa
    sta _g_results + 6       ; #2 failing offset

@reset_regs:
    ; Reset Suzy registers to known state
    ldx #$00
    lda #$00
@loop_reset:
    sta $FC00,x
    inx
    cpx #$30
    bne @loop_reset

    rts

.endproc

;===================================================================
; Main test runner function
;===================================================================
_run_tests:
    sei                 ; Disable interrupts during testing
    jsr Test1
    jsr Test2
    cli                 ; Re-enable interrupts
    rts