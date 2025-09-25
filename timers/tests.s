
.setcpu "65C02"

.include "lynx.inc"

.import _set_irq
.import _get_irq

.export _run_tests
.export _g_results

.segment "ZEROPAGE"

iterations: .res 1


.segment "BSS"

_g_results: .res 20


.segment "CODE"

.proc reset_timer
    stz TIM3CTLA
    stz TIM3BKUP
    stz TIM3CNT
    stz TIM3CTLB
    rts
.endproc

; Test 1: Write and read back values to TIM3CTLB
.proc test_1
    lda TIM3CTLB
    sta _g_results+0    ; $00

    lda #$FF
    sta TIM3CTLB
    lda TIM3CTLB
    sta _g_results+1    ; $E9

    lda #$00
    sta TIM3CTLB
    lda TIM3CTLB
    sta _g_results+2    ; $00

    rts
.endproc

; Test 2: Start one-shot timer, wait for it to set DONE bit
; store CTLB and INTSET
; no interrupts must signaled
.proc test_2
    lda #$FF
    sta INTRST

    lda #$F0
    sta TIM3BKUP
    sta TIM3CNT

    lda #(ENABLE_COUNT | 6)
    sta TIM3CTLA

@wait_done:

    lda TIM3CTLB
    sta _g_results+3    ; $0C
    and #$08
    beq @wait_done

    nop
    nop
    lda INTSET
    sta _g_results+4    ; $00

    rts
.endproc

; Test 3: Start one-shot timer with interrupts enabled
; wait for IRQ, count IRQs, store CTLB and CNT
; exactly one IRQ must be signaled
.proc test_3

    ldx #$00
    ldy #$40

    lda #$FF
    sta INTRST

    lda #$05
    sta TIM3BKUP
    sta TIM3CNT

    lda #(ENABLE_INT | ENABLE_COUNT | 1)
    sta TIM3CTLA

@wait_irq:
    dey
    beq @done

    lda INTSET
    and #TIMER3_INTERRUPT
    beq @wait_irq

    lda #TIMER3_INTERRUPT
    sta INTRST
    inx
    jmp @wait_irq
@done:
    stx _g_results+5    ; $01

    lda TIM3CTLB
    sta _g_results+6    ; $0C
    lda TIM3CNT
    sta _g_results+7    ; $00
    rts
.endproc

; Test 4: Start one-shot timer with interrupts and RESET_DONE enabled
; wait for IRQ, count IRQs, store CTLB and number of IRQs
; reste done is level triggered so will keep it generating IRQs
; exactly 4 IRQs must be signaled with 39 iterations left
.proc test_4

    ldx #$00
    ldy #$40

    lda #$FF
    sta INTRST

    lda #$05
    sta TIM3BKUP
    sta TIM3CNT

    lda #(ENABLE_INT | RESET_DONE | ENABLE_COUNT | 1)
    sta TIM3CTLA

@wait_irq:
    dey
    beq @done

    lda INTSET
    and #TIMER3_INTERRUPT
    beq @wait_irq

    lda #TIMER3_INTERRUPT
    sta INTRST
    inx

    cpx #$04
    beq @remove_reset_done

    jmp @wait_irq
@remove_reset_done:
    sty iterations
    lda #(ENABLE_INT | ENABLE_COUNT | 1)
    sta TIM3CTLA
    nop
    nop
    lda #TIMER3_INTERRUPT
    sta INTRST
    jmp @wait_irq
@done:
    stx _g_results+8    ; $04

    lda TIM3CTLB
    sta _g_results+9    ; $FC

    lda iterations
    sta _g_results+10   ; $39
    rts
.endproc

; Test 5: Start one-shot timer with interrupts enabled an timer done set
; wait for IRQ, count IRQs, store number of IRQs
; timer should keep stopped and no IRQs should be signaled
.proc test_5

    ldx #$00
    ldy #$40

    lda #$FF
    sta INTRST

    lda #$05
    sta TIM3BKUP
    sta TIM3CNT

    lda #TIMER_DONE
    sta TIM3CTLB

    lda #(ENABLE_INT | ENABLE_COUNT | 2)
    sta TIM3CTLA

@wait_stopped:
    dey
    beq @run

    lda INTSET
    and #TIMER3_INTERRUPT
    beq @wait_stopped

    lda #TIMER3_INTERRUPT
    sta INTRST
    inx
    jmp @wait_stopped
@run:
    stx _g_results+11    ; $00

    ldx #$00
    ldy #$40

    lda #00
    sta TIM3CTLB

@wait_running:
    dey
    beq @end

    lda INTSET
    and #TIMER3_INTERRUPT
    beq @wait_running

    lda #TIMER3_INTERRUPT
    sta INTRST
    inx
    jmp @wait_running
@end:
    stx _g_results+12    ; $ 01

    rts
.endproc

_run_tests:
    sei
    jsr reset_timer
    jsr test_1
    jsr reset_timer
    jsr test_2
    jsr reset_timer
    jsr test_3
    jsr reset_timer
    jsr test_4
    jsr reset_timer
    jsr test_5

    rts