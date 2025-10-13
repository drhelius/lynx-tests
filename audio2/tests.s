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

    stz ch3_iter

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

    lda ch3_iter
    sta _g_results + 0      ; #1: how many CH3 DONEs we counted (expect 10)
    lda TIM1CTLB
    sta _g_results + 1      ; #2: Timer1 CTLB
    lda AUD3CTLB
    sta _g_results + 2      ; #3: CH3 CTLB
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
; Test 2: Timer7 -> link to Audio CH0
; Every 10 TIM7 DONE events should trigger CH0 DONE.
; Results at _g_results + 3..6:
;===================================================================
.proc Test2
.segment "ZEROPAGE"
    t7_iter:    .res 1
    t7_ctla:    .res 1
    ch0_ctla:   .res 1
    ch0_out0:   .res 1

.segment "CODE"
    jsr ResetTimers

    stz t7_iter

    lda #$70
    sta AUD0VOL

    lda #$AA
    sta AUD0SHIFT           ; shifter low bits = %10101010
    lda #%10110000
    sta AUD0CTLB            ; shifter bits 11..8 = %1011
    lda #$FF
    sta AUD0FEED            ; enable many feedback taps

    ; BKUP=9 -> 10 inbound ticks to borrow
    lda #$09
    sta AUD0BKUP
    sta AUD0CNT

    ; linked mode: TIM7 -> CH0
    lda #(ENABLE_RELOAD | ENABLE_COUNT | 7)
    sta ch0_ctla
    sta AUD0CTLA

    ; snapshot initial CH0 OUT so we can verify it changes later
    lda AUD0OUT
    sta ch0_out0

    ; BKUP=0 -> immediate borrow on first tick
    lda #$00
    sta TIM7BKUP
    sta TIM7CNT

    lda #(ENABLE_RELOAD | ENABLE_COUNT | $06)
    sta t7_ctla
    sta TIM7CTLA

@wait_t7_done:
    ; Wait for TIM7 DONE
    lda TIM7CTLB
    and #$08
    beq @wait_t7_done

    inc t7_iter

    ; For the first 9 TIM7 DONEs, CH0 DONE must still be clear
    lda t7_iter
    cmp #10
    beq @after_nine

    lda AUD0CTLB
    and #$08                ; DONE bit
    bne @fail               ; If set too early -> fail

@after_nine:
    ; Reset TIM7 Timer DONE
    lda t7_ctla
    ora #RESET_DONE
    sta TIM7CTLA
    lda t7_ctla
    sta TIM7CTLA

    ; Loop until 10 events
    lda t7_iter
    cmp #10
    bcc @wait_t7_done

    ; At this point CH0 DONE must be set
    lda AUD0CTLB
    and #$08
    beq @fail

    ; Verify CH0 OUT changed
    lda AUD0OUT
    cmp ch0_out0
    beq @fail

    lda t7_iter
    sta _g_results + 3  ; #1: number of TIM7 DONEs we counted (expect 10)
    lda TIM7CTLB
    and #$0F        ; mask out unused bits (they are LFSR btw)
    sta _g_results + 4  ; #2: TIM7 CTLB
    lda AUD0CTLB
    sta _g_results + 5  ; #3: CH0 CTLB
    lda AUD0OUT
    sta _g_results + 6  ; #4: CH0 OUT
    rts

@fail:
    ; On failure, store 0xFF
    lda #$FF
    sta _g_results + 3
    sta _g_results + 4
    sta _g_results + 5
    sta _g_results + 6
    rts
.endproc

;===================================================================
; Main test runner function
;===================================================================
_run_tests:
    sei                 ; Disable interrupts during testing
    jsr Test1
    jsr Test2
    jsr ResetTimers
    cli                 ; Re-enable interrupts
    rts