.setcpu "65C02"

.include "lynx.inc"

.export _run_tests
.export _g_results
.export _g_debug_results

TEST_COUNT = 10
PHASE_SAMPLES = 4
ORDER_SAMPLES = 16

;-------------------------------------------------------------------
.segment "BSS"
    ; One byte per displayed test: 0=PASS, otherwise failing sample
    _g_results: .res TEST_COUNT

    ; Last raw measurement produced by each test
    _g_debug_results: .res TEST_COUNT

    ; Ordinary RAM location used by the generic access benchmark
    scratch: .res 1

;-------------------------------------------------------------------
.segment "RODATA"
    ; Instruction delays sample different positions in the free-running phase
    delay_counts: .byte 0, 7, 15, 31

;-------------------------------------------------------------------
.segment "ZEROPAGE"
    ; Display timer state preserved while timing noise is disabled
    saved_t0_backup: .res 1
    saved_t0_control: .res 1
    saved_t0_count: .res 1
    saved_t2_backup: .res 1
    saved_t2_control: .res 1
    saved_t2_count: .res 1

.segment "CODE"

;===================================================================
; Record the first failing sub-sample for a displayed test
;===================================================================
.macro RecordFailure test, code
    .local done
    lda _g_results + test
    bne done
    lda #code
    sta _g_results + test
done:
.endmacro

;===================================================================
; Measure 64 reads from one timer register
; Hardware result for every timer is $83 or $84 elapsed 1 us ticks
;===================================================================
.macro MeasureRead address, test, sample
    .local valid
    jsr BeginMeasure
    .repeat 64
        lda address
    .endrepeat
    stz TIM3CTLA
    lda TIM3CNT
    eor #$FF
    sta _g_debug_results + test
    cmp #$83
    beq valid
    cmp #$84
    beq valid
    RecordFailure test, sample
valid:
.endmacro

;===================================================================
; Measure 64 writes to one timer register
; Hardware result is $83/$84 for timers 0-1 and $84 for timers 2-7
;===================================================================
.macro MeasureWrite address, expected, sample
    .local valid
    jsr BeginMeasure
    .repeat 64
        sta address
    .endrepeat
    stz TIM3CTLA
    lda TIM3CNT
    eor #$FF
    sta _g_debug_results + 7
    cmp #expected
    beq valid
    cmp #$84
    beq valid
    RecordFailure 7, sample
valid:
.endmacro

;===================================================================
; Measure 64 ordinary or generic Mikey reads
; Hardware result is $4F or $50 elapsed 1 us ticks
;===================================================================
.macro MeasureGenericRead address, sample
    .local valid
    jsr BeginMeasure
    .repeat 64
        lda address
    .endrepeat
    jsr FinishMeasure
    sta _g_debug_results + 8
    cmp #$4F
    beq valid
    cmp #$50
    beq valid
    RecordFailure 8, sample
valid:
.endmacro

;===================================================================
; Measure 64 ordinary or generic Mikey writes
; Hardware result is $4F or $50 elapsed 1 us ticks
;===================================================================
.macro MeasureGenericWrite address, sample
    .local valid
    jsr BeginMeasure
    .repeat 64
        sta address
    .endrepeat
    jsr FinishMeasure
    sta _g_debug_results + 8
    cmp #$4F
    beq valid
    cmp #$50
    beq valid
    RecordFailure 8, sample
valid:
.endmacro

;===================================================================
; Disable display, serial, audio, and unrelated timer activity
; Save display timers so the C result frontend can be restored later
;===================================================================
.proc DisableNoise
    lda TIM0BKUP
    sta saved_t0_backup
    lda TIM0CTLA
    sta saved_t0_control
    lda TIM0CNT
    sta saved_t0_count
    lda TIM2BKUP
    sta saved_t2_backup
    lda TIM2CTLA
    sta saved_t2_control
    lda TIM2CNT
    sta saved_t2_count

    stz DISPCTL
    stz TIM0CTLA
    stz TIM1CTLA
    stz TIM2CTLA
    stz TIM4CTLA
    stz TIM5CTLA
    stz TIM6CTLA
    stz TIM7CTLA
    stz AUD0CTLA
    stz AUD1CTLA
    stz AUD2CTLA
    stz AUD3CTLA
    stz SERCTL
    lda #$FF
    sta INTRST
    rts
.endproc

;===================================================================
; Restore display timing for the C result frontend
;===================================================================
.proc RestoreDisplay
    stz SERCTL

    lda saved_t2_backup
    sta TIM2BKUP
    lda saved_t2_count
    sta TIM2CNT
    lda saved_t2_control
    sta TIM2CTLA

    lda saved_t0_backup
    sta TIM0BKUP
    lda saved_t0_count
    sta TIM0CNT
    lda saved_t0_control
    sta TIM0CTLA

    lda #$0D
    sta DISPCTL
    rts
.endproc

;===================================================================
; Reset all timers used by this suite and acknowledge their IRQs
;===================================================================
.proc ResetTimers
    stz TIM3CTLA
    stz TIM3BKUP
    stz TIM3CNT
    stz TIM3CTLB
    stz TIM4CTLA
    stz TIM4BKUP
    stz TIM4CNT
    stz TIM4CTLB
    stz TIM5CTLA
    stz TIM5BKUP
    stz TIM5CNT
    stz TIM5CTLB
    stz TIM6CTLA
    stz TIM6BKUP
    stz TIM6CNT
    stz TIM6CTLB
    lda #(TIMER3_INTERRUPT | TIMER5_INTERRUPT | TIMER6_INTERRUPT)
    sta INTRST
    rts
.endproc

;===================================================================
; Delay by X loop iterations to sample the shared hardware phase
;===================================================================
.proc SampleDelay
    txa
    tay
    beq done
loop:
    nop
    dey
    bne loop
done:
    rts
.endproc

;===================================================================
; Delay according to delay_counts[X]
;===================================================================
.proc PhaseDelay
    lda delay_counts,x
    tay
    beq done
loop:
    nop
    dey
    bne loop
done:
    rts
.endproc

;===================================================================
; Start Timer 3 as a 1 us aggregate stopwatch and return A=$55
;===================================================================
.proc BeginMeasure
    stz TIM3CTLA
    stz TIM3CTLB
    lda #$FF
    sta TIM3BKUP
    sta TIM3CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | 0)
    sta TIM3CTLA
    lda #$55
    rts
.endproc

;===================================================================
; Stop Timer 3 and return elapsed 1 us ticks in A
;===================================================================
.proc FinishMeasure
    stz TIM3CTLA
    lda TIM3CNT
    eor #$FF
    rts
.endproc

;===================================================================
; Start Timer 3 as a 1 us phase stopwatch
;===================================================================
.proc StartStopwatch
    stz TIM3CTLA
    stz TIM3CTLB
    lda #$FF
    sta TIM3BKUP
    sta TIM3CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | 0)
    sta TIM3CTLA
    rts
.endproc

;===================================================================
; Wait for the Timer 6 interrupt pending bit
;===================================================================
.proc WaitTimer6IRQ
loop:
    lda INTSET
    and #TIMER6_INTERRUPT
    beq loop
    rts
.endproc

;===================================================================
; Wait for Timer 4 DONE
;===================================================================
.proc WaitTimer4
loop:
    lda TIM4CTLB
    and #TIMER_DONE
    beq loop
    rts
.endproc

;===================================================================
; Validate a phase sample without requiring one fixed reset phase
; $A0-$FE proves that a 1 us source clock was observed before timeout
;===================================================================
.proc ValidatePhase
    cmp #$A0
    bcc fail
    cmp #$FF
    bcs fail
    clc
    rts
fail:
    sec
    rts
.endproc

;===================================================================
; Test 1: Shared 4 us source, Timer 3 enabled before Timer 6
; The first observed IRQ may be Timer 3 alone ($08) or both ($48)
; Timer 6 alone would violate enable ordering
;===================================================================
.proc TestOrder36
    ldx #0
sample:
    jsr ResetTimers
    jsr SampleDelay
    stz TIM3CNT
    stz TIM6CNT
    lda #(ENABLE_INT | ENABLE_COUNT | 2)
    sta TIM3CTLA
    sta TIM6CTLA
wait:
    lda INTSET
    and #(TIMER3_INTERRUPT | TIMER6_INTERRUPT)
    beq wait
    sta _g_debug_results + 0
    cmp #TIMER3_INTERRUPT
    beq valid
    cmp #(TIMER3_INTERRUPT | TIMER6_INTERRUPT)
    beq valid
    txa
    inc a
    sta _g_results + 0
    rts
valid:
    inx
    cpx #ORDER_SAMPLES
    bne sample
    rts
.endproc

;===================================================================
; Test 2: Shared 4 us source, Timer 6 enabled before Timer 3
; The first observed IRQ may be Timer 6 alone ($40) or both ($48)
; Timer 3 alone would violate enable ordering
;===================================================================
.proc TestOrder63
    ldx #0
sample:
    jsr ResetTimers
    jsr SampleDelay
    stz TIM3CNT
    stz TIM6CNT
    lda #(ENABLE_INT | ENABLE_COUNT | 2)
    sta TIM6CTLA
    sta TIM3CTLA
wait:
    lda INTSET
    and #(TIMER3_INTERRUPT | TIMER6_INTERRUPT)
    beq wait
    sta _g_debug_results + 1
    cmp #TIMER6_INTERRUPT
    beq valid
    cmp #(TIMER3_INTERRUPT | TIMER6_INTERRUPT)
    beq valid
    txa
    inc a
    sta _g_results + 1
    rts
valid:
    inx
    cpx #ORDER_SAMPLES
    bne sample
    rts
.endproc

;===================================================================
; Test 3: First 64 us edge after enabling Timer 6
; Timer 3 measures elapsed 1 us clocks at four free-running phases
;===================================================================
.proc TestEnablePhase
    ldx #0
sample:
    jsr ResetTimers
    jsr StartStopwatch
    jsr PhaseDelay
    lda #$FF
    sta TIM3CNT
    stz TIM6CNT
    lda #(ENABLE_INT | ENABLE_COUNT | 6)
    sta TIM6CTLA
    jsr WaitTimer6IRQ
    lda TIM3CNT
    sta _g_debug_results + 2
    jsr ValidatePhase
    bcc valid
    txa
    inc a
    sta _g_results + 2
    rts
valid:
    inx
    cpx #PHASE_SAMPLES
    bne sample
    rts
.endproc

;===================================================================
; Test 4: CNT writes preserve the free-running 64 us source phase
; Rewriting Timer 6 CNT must not restart its prescaler
;===================================================================
.proc TestCountPhase
    jsr ResetTimers
    jsr StartStopwatch
    lda #$FF
    sta TIM6CNT
    lda #(ENABLE_INT | ENABLE_COUNT | 6)
    sta TIM6CTLA
    ldx #0
sample:
    lda #$FF
    sta TIM6CNT
    stz TIM6CTLB
    lda #TIMER6_INTERRUPT
    sta INTRST
    jsr PhaseDelay
    lda #$FF
    sta TIM3CNT
    stz TIM6CNT
    jsr WaitTimer6IRQ
    lda TIM3CNT
    sta _g_debug_results + 3
    jsr ValidatePhase
    bcc valid
    txa
    inc a
    sta _g_results + 3
    rts
valid:
    inx
    cpx #PHASE_SAMPLES
    bne sample
    rts
.endproc

;===================================================================
; Test 5: Changing an enabled timer from 32 us to 64 us
; The new selector samples the shared divider instead of restarting it
;===================================================================
.proc TestPrescalerPhase
    ldx #0
sample:
    jsr ResetTimers
    jsr StartStopwatch
    lda #$FF
    sta TIM6CNT
    lda #(ENABLE_INT | ENABLE_COUNT | 5)
    sta TIM6CTLA
    jsr PhaseDelay
    lda #$FF
    sta TIM3CNT
    stz TIM6CNT
    lda #(ENABLE_INT | ENABLE_COUNT | 6)
    sta TIM6CTLA
    jsr WaitTimer6IRQ
    lda TIM3CNT
    sta _g_debug_results + 4
    jsr ValidatePhase
    bcc valid
    txa
    inc a
    sta _g_results + 4
    rts
valid:
    inx
    cpx #PHASE_SAMPLES
    bne sample
    rts
.endproc

;===================================================================
; Test 6: Timer 4 observes the same shared 64 us source phase
; Timer 3 measures elapsed 1 us clocks until Timer 4 DONE
;===================================================================
.proc TestTimer4Phase
    ldx #0
sample:
    jsr ResetTimers
    jsr StartStopwatch
    jsr PhaseDelay
    lda #$FF
    sta TIM3CNT
    stz TIM4CNT
    lda #(ENABLE_COUNT | 6)
    sta TIM4CTLA
    jsr WaitTimer4
    lda TIM3CNT
    sta _g_debug_results + 5
    jsr ValidatePhase
    bcc valid
    txa
    inc a
    sta _g_results + 5
    rts
valid:
    inx
    cpx #PHASE_SAMPLES
    bne sample
    rts
.endproc

;===================================================================
; Test 7: Timer register read arbitration
; Each row performs 64 reads; hardware requires $83/$84 elapsed ticks
;===================================================================
.proc TestTimerReads
    jsr ResetTimers
    MeasureRead TIM0BKUP, 6, 1
    MeasureRead TIM1BKUP, 6, 2
    MeasureRead TIM2BKUP, 6, 3
    MeasureRead TIM3BKUP, 6, 4
    MeasureRead TIM4BKUP, 6, 5
    MeasureRead TIM5BKUP, 6, 6
    MeasureRead TIM6BKUP, 6, 7
    MeasureRead TIM7BKUP, 6, 8
    rts
.endproc

;===================================================================
; Test 8: Timer register write arbitration
; Timers 0-1 allow $83/$84; timers 2-7 require the $84 endpoint
;===================================================================
.proc TestTimerWrites
    jsr ResetTimers
    MeasureWrite TIM0BKUP, $83, 1
    MeasureWrite TIM1BKUP, $83, 2
    MeasureWrite TIM2BKUP, $84, 3
    MeasureWrite TIM3BKUP, $84, 4
    MeasureWrite TIM4BKUP, $84, 5
    MeasureWrite TIM5BKUP, $84, 6
    MeasureWrite TIM6BKUP, $84, 7
    MeasureWrite TIM7BKUP, $84, 8
    rts
.endproc

;===================================================================
; Test 9: Generic Mikey register access timing
; RAM, INTSET/INTRST, and SERCTL loops must each measure $4F/$50
;===================================================================
.proc TestMikeyAccess
    jsr ResetTimers
    MeasureGenericRead scratch, 1
    MeasureGenericWrite scratch, 2
    MeasureGenericRead INTSET, 3
    MeasureGenericWrite INTRST, 4
    MeasureGenericRead SERCTL, 5
    MeasureGenericWrite SERCTL, 6
    rts
.endproc

;===================================================================
; Test 10: Linked Timer 3 -> Timer 5 cascade
; Three software clocks must produce CNT 2->1->0, then DONE and IRQ
; Polling allows Timer 5 to take its round-robin hardware turn
;===================================================================
.proc TestLinkCascade
    jsr ResetTimers
    stz TIM5BKUP
    lda #$02
    sta TIM5CNT
    lda #(ENABLE_INT | ENABLE_COUNT | 7)
    sta TIM5CTLA

    lda #$02
    sta TIM3CTLB
    ldy #$40
wait_first:
    lda TIM5CNT
    cmp #$01
    beq second
    dey
    bne wait_first
    lda #$01
    sta _g_results + 9
    rts

second:
    lda #$02
    sta TIM3CTLB
    ldy #$40
wait_second:
    lda TIM5CNT
    beq third
    dey
    bne wait_second
    lda #$02
    sta _g_results + 9
    rts

third:
    lda #$02
    sta TIM3CTLB
    ldy #$40
wait_done:
    lda TIM5CTLB
    and #$08
    sta _g_debug_results + 9
    bne irq
    dey
    bne wait_done
    lda #$03
    sta _g_results + 9
    rts

irq:
    lda INTSET
    and #TIMER5_INTERRUPT
    bne done
    lda #$04
    sta _g_results + 9
done:
    rts
.endproc

;===================================================================
; Main test runner
;===================================================================
_run_tests:
    sei
    jsr DisableNoise
    jsr TestOrder36
    jsr TestOrder63
    jsr TestEnablePhase
    jsr TestCountPhase
    jsr TestPrescalerPhase
    jsr TestTimer4Phase
    jsr TestTimerReads
    jsr TestTimerWrites
    jsr TestMikeyAccess
    jsr TestLinkCascade
    jsr ResetTimers
    jsr RestoreDisplay
    cli
    rts
