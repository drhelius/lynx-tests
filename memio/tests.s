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
;   Write and read back Mikey color registers
;   Green registers at $FDA0-$FDAF
;   Blue/Red registers at $FDB0-$FDBF
;===================================================================
.proc Test1

; Stage 0: Write $00 to Blue/Red, read back and verify
    ldx #$00
    lda #$00
    sta stage

@loop_br_00:
    lda #$00
    sta $FDB0,x
    lda $FDB0,x
    cmp #$00
    beq :+
    jmp @fail
:   inx
    cpx #$10
    bne @loop_br_00

; Stage 1: Write $FF to Blue/Red, read back and verify
    ldx #$00
    lda #$01
    sta stage

@loop_br_FF:
    lda #$FF
    sta $FDB0,x
    lda $FDB0,x
    cmp #$FF
    beq :+
    jmp @fail
:   inx
    cpx #$10
    bne @loop_br_FF

; Stage 2: Write $55 to Blue/Red, read back and verify
    ldx #$00
    lda #$02
    sta stage

@loop_br_55:
    lda #$55
    sta $FDB0,x
    lda $FDB0,x
    cmp #$55
    beq :+
    jmp @fail
:   inx
    cpx #$10
    bne @loop_br_55

; Stage 3: Write $AA to Blue/Red, read back and verify
    ldx #$00
    lda #$03
    sta stage

@loop_br_AA:
    lda #$AA
    sta $FDB0,x
    lda $FDB0,x
    cmp #$AA
    beq :+
    jmp @fail
:   inx
    cpx #$10
    bne @loop_br_AA

; Stage 4: Blue/Red - Write $0F, increment, verify low nibble carry to high nibble
;          Expect: $0F + 1 = $10
    ldx #$00
    lda #$04
    sta stage

@loop_br_inc_lo:
    lda #$0F
    sta $FDB0,x
    inc $FDB0,x
    lda $FDB0,x
    cmp #$10                 ; low nibble F + 1 should carry to high nibble
    beq :+
    jmp @fail
:   inx
    cpx #$10
    bne @loop_br_inc_lo

; Stage 5: Blue/Red - Write $FF, increment, verify full overflow
;          Expect: $FF + 1 = $00
    ldx #$00
    lda #$05
    sta stage

@loop_br_inc_hi:
    lda #$FF
    sta $FDB0,x
    inc $FDB0,x
    lda $FDB0,x
    cmp #$00                 ; $FF + 1 should overflow to $00
    beq :+
    jmp @fail
:   inx
    cpx #$10
    bne @loop_br_inc_hi

; Stage 6: Write $00 to Green, read back and verify (low nibble only)
    ldx #$00
    lda #$06
    sta stage

@loop_gr_00:
    lda #$00
    sta $FDA0,x
    lda $FDA0,x
    cmp #$00                 ; $00 & $0F = $00
    bne @fail
    inx
    cpx #$10
    bne @loop_gr_00

; Stage 7: Write $FF to Green, read back and verify (low nibble only)
    ldx #$00
    lda #$07
    sta stage

@loop_gr_FF:
    lda #$FF
    sta $FDA0,x
    lda $FDA0,x
    cmp #$0F                 ; $FF & $0F = $0F
    bne @fail
    inx
    cpx #$10
    bne @loop_gr_FF

; Stage 8: Write $55 to Green, read back and verify (low nibble only)
    ldx #$00
    lda #$08
    sta stage

@loop_gr_55:
    lda #$55
    sta $FDA0,x
    lda $FDA0,x
    cmp #$05                 ; $55 & $0F = $05
    bne @fail
    inx
    cpx #$10
    bne @loop_gr_55

; Stage 9: Write $AA to Green, read back and verify (low nibble only)
    ldx #$00
    lda #$09
    sta stage

@loop_gr_AA:
    lda #$AA
    sta $FDA0,x
    lda $FDA0,x
    cmp #$0A                 ; $AA & $0F = $0A
    bne @fail
    inx
    cpx #$10
    bne @loop_gr_AA

; Stage 10: Green - Write $0F, increment, verify low nibble overflow
;           Expect: $0F + 1 = $00 (no high nibble, wraps around)
    ldx #$00
    lda #$0A
    sta stage

@loop_gr_inc:
    lda #$0F
    sta $FDA0,x
    inc $FDA0,x
    lda $FDA0,x
    cmp #$00                 ; $0F + 1 should wrap to $00 (no high nibble)
    bne @fail
    inx
    cpx #$10
    bne @loop_gr_inc

    stz _g_results + 0
    stz _g_results + 1
    stz _g_results + 2
    stz _g_results + 3
    rts

@fail:
    sta _g_results + 3       ; #3 actual read value
    lda #$01
    sta _g_results + 0       ; #0 failure flag = 1
    lda stage
    sta _g_results + 1       ; #1 stage (0-5=BlueRed, 6-10=Green)
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