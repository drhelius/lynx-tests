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
.segment "CODE"

;===================================================================
; Reset all timers and channels except TIMER 0 and TIMER 2
;===================================================================
.proc ResetTimers
    ldx #$00
@loop:
    cpx #$04
    bcc @do_reset      ; x < 4 => reset
    cpx #$08
    bcc @skip_reset    ; 4 <= x < 8 => skip TIMER 2
@do_reset:
    stz $FD04,x
@skip_reset:
    inx
    cpx #$3C
    bne @loop
    rts
.endproc

;===================================================================
; Test 1: Audio CH3 -> link to Timer1
; Every 10 CH3 DONE events should trigger Timer1 DONE.
; Results at _g_results + 0..2.
;===================================================================
.proc Test1
.segment "ZEROPAGE"
    ch3_iter:   .res 1
    ch3_ctla:   .res 1

.segment "CODE"
    jsr ResetTimers

    lda #$00
    sta ch3_iter

    ; BKUP=9 -> 10 inbound ticks to borrow
    lda #$09
    sta TIM1BKUP
    sta TIM1CNT

    ; linked mode: CH3 -> Timer1
    lda #(ENABLE_RELOAD | ENABLE_COUNT | 7)
    sta TIM1CTLA

    ; BKUP=0 -> immediate borrow on first tick
    lda #$00
    sta AUD3BKUP
    sta AUD3CNT

    lda #(ENABLE_RELOAD | ENABLE_COUNT | 6)
    sta ch3_ctla
    sta AUD3CTLA

@wait_done:
    ; Wait for CH3 timer DONE
    lda AUD3CTLB
    and #$08
    beq @wait_done

    inc ch3_iter

    ; For the first 9 CH3 DONEs, TIM1 DONE must still be clear
    lda ch3_iter
    cmp #10
    beq @after_nine
    lda TIM1CTLB
    and #$08            ; DONE bit
    bne @fail           ; if set too early -> fail

@after_nine:
    ; Reset CH3 Timer DONE
    lda ch3_ctla
    ora #RESET_DONE
    sta AUD3CTLA
    lda ch3_ctla
    sta AUD3CTLA

    ; Loop until 10 events
    lda ch3_iter
    cmp #10
    bcc @wait_done

    ; At this point TIM1 DONE must be set
    lda TIM1CTLB
    and #$08
    beq @fail

    ; Byte 0: how many CH3 DONEs we counted (expect 10)
    lda ch3_iter
    sta _g_results + 0

    ; Byte 1: Timer1 CTLB
    lda TIM1CTLB
    sta _g_results + 1

    ; Byte 2: CH3 CTLB
    lda AUD3CTLB
    sta _g_results + 2
    rts

@fail:
    ; On failure, store 0xFF
    lda #$FF
    sta _g_results + 0
    sta _g_results + 1
    sta _g_results + 2
    rts
.endproc

;===================================================================
; Main test runner function
;===================================================================
_run_tests:
    sei                 ; Disable interrupts during testing
    jsr Test1
    jsr ResetTimers
    cli                 ; Re-enable interrupts
    rts