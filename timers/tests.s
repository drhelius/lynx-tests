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
; Reset both Timer 3 and Timer 5 to initial state
; Clears all control registers, backup values, and counters
;===================================================================
.proc ResetTimers
    ; Reset Timer 3 registers
    stz TIM3CTLA    ; Disable timer 3
    stz TIM3BKUP    ; Clear backup/reload value
    stz TIM3CNT     ; Clear current counter
    stz TIM3CTLB    ; Clear control/status register

    ; Reset Timer 5 registers
    stz TIM5CTLA    ; Disable timer 5
    stz TIM5BKUP    ; Clear backup/reload value
    stz TIM5CNT     ; Clear current counter
    stz TIM5CTLB    ; Clear control/status register
    rts
.endproc

;===================================================================
; Test 1: 
;===================================================================
.proc Test1
    jsr ResetTimers

    ; Read initial CTLB value (should be $00)
    ldx #$01
    lda TIM3CTLB
    cmp #$00
    bne @fail

    lda #$80
    sta TIM3CNT           ; Set counter to non-zero

    ; write timer done and borrow in (this will clock the timer)
    lda #$0A
    sta TIM3CTLB
    lda TIM3CTLB
    and #$0F              ; Mask off upper bits (undocumented)
    sta _g_results + 0    ; #1 Expected: $08 (will leave timer done)

    lda TIM3CNT
    sta _g_results + 1    ; #2 Expected: $7F (counter decremented)

    ; Clear register and verify
    lda #$00
    sta TIM3CTLB
    lda TIM3CTLB
    sta _g_results + 2    ; #3 Expected: $00

    jmp @end

@fail:
    txa
    sta _g_results + 0    ; CTLB not zero at start

@end:
    rts
.endproc

;===================================================================
; Test 2: One-shot timer operation without interrupts
; Starts timer and polls for DONE bit, verifies no IRQ is generated
; Tests basic timer countdown and completion detection
;===================================================================
.proc Test2
    jsr ResetTimers

    ; Clear any pending interrupts
    lda #$FF
    sta INTRST

    ; Set timer to count down from $F0
    lda #$F0
    sta TIM3BKUP    ; Backup/reload value
    sta TIM3CNT     ; Initial counter value

    ; Start one-shot timer (clock divider = 6)
    lda #(ENABLE_COUNT | 6)
    sta TIM3CTLA

@wait_done:
    ; Poll for DONE bit (bit 3) in CTLB
    lda TIM3CTLB
    and #$08
    beq @wait_done

    sta _g_results + 3    ; #1 Expected: $08 (DONE bit set)

    ; Verify no interrupt was generated
    lda INTSET
    sta _g_results + 4    ; #2 Expected: $00 (no IRQ)

    rts
.endproc

;===================================================================
; Test 3: One-shot timer with interrupt generation
; Enables timer interrupts and counts IRQ occurrences
; Verifies single IRQ generation for one-shot mode
;===================================================================
.proc Test3
    jsr ResetTimers

    ldx #$00    ; IRQ counter
    ldy #$40    ; Timeout counter

    ; Clear pending interrupts
    lda #$FF
    sta INTRST

    ; Set short timer value for quick completion
    lda #$05
    sta TIM3BKUP
    sta TIM3CNT

    ; Enable timer with interrupts (clock divider = 1)
    lda #(ENABLE_INT | ENABLE_COUNT | 1)
    sta TIM3CTLA

@wait_irq:
    dey
    beq @done

    ; Check for Timer 3 interrupt
    lda INTSET
    and #TIMER3_INTERRUPT
    beq @wait_irq

    ; Clear interrupt and increment counter
    lda #TIMER3_INTERRUPT
    sta INTRST
    inx
    jmp @wait_irq

@done:
    stx _g_results + 5    ; #1 Expected: $01 (exactly one IRQ)

    ; Verify timer completed (DONE bit set)
    lda TIM3CTLB
    and #$08
    sta _g_results + 6    ; #2 Expected: $08

    ; Counter should be zero after completion
    lda TIM3CNT
    sta _g_results + 7    ; #3 Expected: $00
    rts
.endproc

;===================================================================
; Test 4: Timer with RESET_DONE functionality
; Tests level-triggered interrupt behavior with RESET_DONE
; Demonstrates continuous IRQ generation until RESET_DONE is cleared
;===================================================================
.proc Test4

.segment "ZEROPAGE"
    iterations: .res 1

.segment "CODE"
    jsr ResetTimers

    ldx #$00    ; IRQ counter
    ldy #$40    ; Timeout counter

    ; Clear pending interrupts
    lda #$FF
    sta INTRST

    lda #$05
    sta TIM3BKUP
    sta TIM3CNT

    ; Enable timer with interrupts and RESET_DONE (clock divider = 2)
    lda #(ENABLE_INT | RESET_DONE | ENABLE_COUNT | 2)
    sta TIM3CTLA

@wait_irq:
    dey
    beq @done

    ; Check for Timer 3 interrupt
    lda INTSET
    and #TIMER3_INTERRUPT
    beq @wait_irq

    ; Clear interrupt and increment counter
    lda #TIMER3_INTERRUPT
    sta INTRST
    inx

    ; After 4 IRQs, disable RESET_DONE to stop continuous interrupts
    cpx #$04
    beq @remove_reset_done

    jmp @wait_irq

@remove_reset_done:
    sty iterations      ; Save remaining iterations
    ; Disable RESET_DONE while keeping other settings
    lda #(ENABLE_INT | ENABLE_COUNT | 2)
    sta TIM3CTLA
    nop                 ; Allow register update
    nop
    nop
    ; Clear final interrupt
    lda #TIMER3_INTERRUPT
    sta INTRST
    jmp @wait_irq

@done:
    stx _g_results + 8    ; #1 Expected: $04 or $05

    ; DONE bit should still be set
    lda TIM3CTLB
    and #$08
    sta _g_results + 9    ; #2 Expected: $08

    ; Disable timer and clear DONE bit
    stz TIM3CTLA
    stz TIM3CTLB
    lda TIM3CTLB
    and #$08
    sta _g_results + 10   ; #3 Expected: $00 (DONE cleared)

    ; Store remaining iterations when RESET_DONE was disabled
    lda iterations
    sta _g_results + 11   ; #4 Expected: $35, $36, or $37
    rts
.endproc

;===================================================================
; Test 5: Timer behavior with pre-set DONE bit
; Verifies that setting DONE bit prevents timer from running
; Then tests normal operation after clearing DONE bit
;===================================================================
.proc Test5
    jsr ResetTimers

    ldx #$00    ; IRQ counter for stopped timer
    ldy #$40    ; Timeout counter

    ; Clear pending interrupts
    lda #$FF
    sta INTRST

    lda #$05
    sta TIM3BKUP
    sta TIM3CNT

    ; Pre-set DONE bit to prevent timer operation
    lda #TIMER_DONE
    sta TIM3CTLB

    ; Try to start timer (should remain stopped due to DONE bit)
    lda #(ENABLE_INT | ENABLE_COUNT | 2)
    sta TIM3CTLA

@wait_stopped:
    dey
    beq @run

    ; Check if any interrupts occur (shouldn't happen)
    lda INTSET
    and #TIMER3_INTERRUPT
    beq @wait_stopped

    ; Count unexpected interrupts
    lda #TIMER3_INTERRUPT
    sta INTRST
    inx
    jmp @wait_stopped

@run:
    stx _g_results + 12    ; #1 Expected: $00 (no IRQs while stopped)

    ldx #$00    ; Reset IRQ counter
    ldy #$40    ; Reset timeout

    ; Clear DONE bit to allow normal operation
    lda #00
    sta TIM3CTLB

@wait_running:
    dey
    beq @end

    ; Now timer should run and generate interrupt
    lda INTSET
    and #TIMER3_INTERRUPT
    beq @wait_running

    lda #TIMER3_INTERRUPT
    sta INTRST
    inx
    jmp @wait_running

@end:
    stx _g_results + 13    ; #2 Expected: $01 (one IRQ after clearing DONE)

    rts
.endproc

;===================================================================
; Test 6: Timer linking functionality
; Timer 5 (with RESET_DONE) linked to Timer 3 (with reload)
; Tests cascade timing and interrupt generation from linked timers
;===================================================================
.proc Test6

.segment "ZEROPAGE"
    t5_count: .res 1    ; Counter for Timer 5 interrupts

.segment "CODE"
    jsr ResetTimers

    ; Clear pending interrupts
    lda #$FF
    sta INTRST

    ; Set Timer 5 to count from 0 (will increment on Timer 3 overflow)
    lda #$00
    sta TIM5BKUP
    sta TIM5CNT

    ; Configure Timer 5: interrupts enabled, reset done, linked to Timer 3 (source 7)
    lda #(ENABLE_INT | RESET_DONE | ENABLE_COUNT | 7)
    sta TIM5CTLA

    ldx #$C0    ; Main loop counter

    ; Set Timer 3 with reload capability
    lda #$10
    sta TIM3BKUP    ; Will reload with $10 each time
    sta TIM3CNT

    ; Configure Timer 3: interrupts, reload enabled, clock divider 2
    lda #(ENABLE_INT | ENABLE_RELOAD | ENABLE_COUNT | 2)
    sta TIM3CTLA

@poll_t5:
    ; Check for Timer 5 interrupts (occurs when Timer 3 overflows)
    lda INTSET
    and #TIMER5_INTERRUPT
    beq @no_t5_irq

    ; Clear Timer 5 interrupt and increment counter
    lda #TIMER5_INTERRUPT
    sta INTRST
    inc t5_count

@no_t5_irq:
    dex
    bne @poll_t5

    ; Store total Timer 5 interrupt count
    lda t5_count
    sta _g_results + 14   ; #1 Expected: $0D (13 Timer 5 interrupts)
    rts

.endproc

;===================================================================
; Test 7: Timer reload mode with DONE bit behavior
; Verifies that timers with reload enabled still set DONE bit
; and generate interrupts upon completion/reload
;===================================================================
.proc Test7
    jsr ResetTimers

    ; Clear pending interrupts
    lda #$FF
    sta INTRST

    ; Set timer to maximum value for longer operation
    lda #$FF
    sta TIM3BKUP    ; Reload value
    sta TIM3CNT     ; Initial counter

    ; Enable timer with reload, interrupts, and clock divider 4
    lda #(ENABLE_INT | ENABLE_RELOAD | ENABLE_COUNT | 4)
    sta TIM3CTLA

@poll_t3:
    ; Wait for first timer completion/reload interrupt
    lda INTSET
    and #TIMER3_INTERRUPT
    beq @poll_t3

    ; Check if DONE bit is set even in reload mode
    lda TIM3CTLB
    and #$08
    sta _g_results + 15   ; #1 Expected: $08 (DONE bit set)

    ; Stop timer
    stz TIM3CTLA
    rts
.endproc

;===================================================================
; Main test runner function
;===================================================================
_run_tests:
    sei                 ; Disable interrupts during testing
    jsr Test1           ; Basic register read/write test
    jsr Test2           ; One-shot timer without interrupts
    jsr Test3           ; One-shot timer with interrupts
    jsr Test4           ; RESET_DONE functionality test
    jsr Test5           ; Pre-set DONE bit behavior test
    jsr Test6           ; Timer linking test
    jsr Test7           ; Reload mode DONE bit test
    jsr ResetTimers     ; Clean up timer state
    cli                 ; Re-enable interrupts
    rts