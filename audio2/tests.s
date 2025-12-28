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
    sta _g_results + 0      ; #1: how many CH3 DONEs we counted (expect 10) Expected: $0A
    lda TIM1CTLB
    sta _g_results + 1      ; #2: Timer1 CTLB Expected: $08
    lda AUD3CTLB
    sta _g_results + 2      ; #3: CH3 CTLB Expected: $34
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
    sta _g_results + 3  ; #1: number of TIM7 DONEs we counted (expect 10) Expected: $0A
    lda TIM7CTLB
    and #$0F        ; mask out unused bits (they are LFSR btw)
    sta _g_results + 4  ; #2: TIM7 CTLB Expected: $04
    lda AUD0CTLB
    sta _g_results + 5  ; #3: CH0 CTLB Expected: $78
    lda AUD0OUT
    sta _g_results + 6  ; #4: CH0 OUT Expected: $70
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
; Test 3: Audio chain CH0 -> CH1 -> CH2 -> CH3 (propagation)
; Each CH0 borrow propagates a borrow through CH1 and CH2 to CH3
; Results at _g_results + 7..10:
;===================================================================
.proc Test3
.segment "ZEROPAGE"
    ch0_iter:   .res 1
    ch0_ctla:   .res 1
    ch3_out0:   .res 1

.segment "CODE"
    jsr ResetTimers

    stz ch0_iter

    lda #$10
    sta AUD0VOL
    sta AUD1VOL
    sta AUD2VOL
    sta AUD3VOL

    lda #$55
    sta AUD3SHIFT           ; shifter low bits = %01010101
    lda #%01010000
    sta AUD3CTLB            ; shifter bits 11..8 = %0101
    lda #$FF
    sta AUD3FEED            ; enable many feedback taps

    ; snapshot initial CH0 OUT so we can verify it changes later
    lda AUD3OUT
    sta ch3_out0

    ; CH0 free-run: BKUP=0 -> immediate borrow on first tick
    lda #$00
    sta AUD0BKUP
    sta AUD0CNT
    ; CH1 pass-through on first inbound tick
    sta AUD1BKUP
    sta AUD1CNT
    ; CH2 pass-through on first inbound tick
    sta AUD2BKUP
    sta AUD2CNT
    ; CH3 requires 10 inbound ticks to borrow out
    lda #$09
    sta AUD3BKUP
    sta AUD3CNT

    lda #(ENABLE_RELOAD | ENABLE_COUNT | $07)
    sta AUD1CTLA
    sta AUD2CTLA
    sta AUD3CTLA

    lda #(ENABLE_RELOAD | ENABLE_COUNT | $06)
    sta ch0_ctla
    sta AUD0CTLA

@wait_ch0_done:
    ; Wait for CH0 DONE
    lda AUD0CTLB
    and #$08
    beq @wait_ch0_done

    ; One CH0 DONE observed -> should have clocked CH1->CH2->CH3
    inc ch0_iter

    ; For the first 9 CH0 DONEs, CH3 must NOT have borrowed out yet
    lda ch0_iter
    cmp #10
    beq @after_nine

    lda AUD3CTLB
    and #$08                ; CH3 timer done
    bne @fail               ; If set too early -> fail

@after_nine:
    ; Reset CH0 Timer DONE
    lda ch0_ctla
    ora #RESET_DONE
    sta AUD0CTLA
    lda ch0_ctla
    sta AUD0CTLA

    ; Loop until 10 events
    lda ch0_iter
    cmp #10
    bcc @wait_ch0_done

    ; At this point CH3 DONE must be set
    lda AUD3CTLB
    and #$08
    beq @fail

    ; Verify CH3 OUT changed
    lda AUD3OUT
    cmp ch3_out0
    beq @fail

    lda ch0_iter
    sta _g_results + 7      ; #1: CH0 DONEs counted (expect 10) Expected: $0A
    lda AUD3CTLB
    sta _g_results + 8      ; #2: CH3 CTLB Expected: $A8
    lda AUD0CTLB
    sta _g_results + 9      ; #3: CH0 CTLB Expected: $30 or $34
    lda AUD3OUT
    sta _g_results + 10     ; #4: CH3 OUT Expected: $10
    rts

@fail:
    ; On failure, store 0xFF
    lda #$FF
    sta _g_results + 7
    sta _g_results + 8
    sta _g_results + 9
    sta _g_results + 10
    rts
.endproc

;===================================================================
; Test 4: CH0 free-run prescaler hot-switch (6 -> 5)
; Run CH0 for 50 iterations (DONE events) at prescaler $6, then switch
; CTRLA prescaler to $5 on-the-fly and run 50 more iterations.
; Results at _g_results + 11..12:
;===================================================================
.proc Test4
.segment "ZEROPAGE"
    pre_iter:   .res 1
    post_iter:  .res 1
    ch0_ctla:   .res 1

.segment "CODE"
    jsr ResetTimers

    stz pre_iter
    stz post_iter

    lda #$03
    sta AUD0VOL

    lda #$5A
    sta AUD0SHIFT
    lda #%10110000
    sta AUD0CTLB
    lda #$FF
    sta AUD0FEED

    lda #$00
    sta AUD0BKUP
    sta AUD0CNT

    lda #(ENABLE_RELOAD | ENABLE_COUNT | ENABLE_INTEGRATE | $06)
    sta ch0_ctla
    sta AUD0CTLA

    ; -------- Phase 1: 50 iterations at prescaler $6 --------
@loop_pre:
    ; wait for CH0 DONE
    lda AUD0CTLB
    and #$08
    beq @loop_pre

    inc pre_iter

    ; clear DONE
    lda ch0_ctla
    ora #RESET_DONE
    sta AUD0CTLA
    lda ch0_ctla
    sta AUD0CTLA

    ; reached 50?
    lda pre_iter
    cmp #50
    bcc @loop_pre

    ; capture OUT just before the prescaler change
    lda AUD0OUT
    sta _g_results + 11     ; Expected: $00

    ; set prescaler to $5
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $05)
    sta ch0_ctla
    sta AUD0CTLA

    ; -------- Phase 2: capture one iteration after the switch --------
@wait_first_post:
    lda AUD0CTLB
    and #$08
    beq @wait_first_post

    ; clear DONE
    lda ch0_ctla
    ora #RESET_DONE
    sta AUD0CTLA
    lda ch0_ctla
    sta AUD0CTLA

    lda AUD0OUT
    sta _g_results + 12     ; Expected: $FD
    rts
.endproc

;===================================================================
; Test 5: CH0 free-run, hot-switch FEEDBACK TAPS (no prescaler change)
; Run 50 iterations with initial taps, capture OUT; switch taps on-the-fly;
; Results at _g_results + 13..14:
;===================================================================
.proc Test5
.segment "ZEROPAGE"
    pre_iter:  .res 1
    post_iter: .res 1
    ch0_ctla:  .res 1

.segment "CODE"
    jsr ResetTimers

    stz pre_iter
    stz post_iter

    lda #$03
    sta AUD0VOL

    lda #$44
    sta AUD0SHIFT
    lda #%10010000
    sta AUD0CTLB
    lda #$77
    sta AUD0FEED

    lda #$00
    sta AUD0BKUP
    sta AUD0CNT

    lda #(ENABLE_RELOAD | ENABLE_COUNT | ENABLE_INTEGRATE | $06)
    sta ch0_ctla
    sta AUD0CTLA

    ; -------- Phase 1: 50 iterations with initial feedback --------
@loop_pre:
    ; wait for CH0 DONE
    lda AUD0CTLB
    and #$08
    beq @loop_pre

    inc pre_iter

    ; clear DONE
    lda ch0_ctla
    ora #RESET_DONE
    sta AUD0CTLA
    lda ch0_ctla
    sta AUD0CTLA

    lda pre_iter
    cmp #50
    bcc @loop_pre

    ; capture OUT just before changing feedback taps
    lda AUD0OUT
    sta _g_results + 13     ; Expected: $EE

    ; -------- change feedback taps --------
    lda #$55
    sta AUD0FEED
    lda ch0_ctla
    ora #%10000000
    sta ch0_ctla
    sta AUD0CTLA

    ; -------- Capture one iteration after the switch --------
@wait_first_post:
    lda AUD0CTLB
    and #$08
    beq @wait_first_post

    ; clear DONE
    lda ch0_ctla
    ora #RESET_DONE
    sta AUD0CTLA
    lda ch0_ctla
    sta AUD0CTLA

    lda AUD0OUT
    sta _g_results + 14     ; Expected: $EB
    rts
.endproc

;===================================================================
; Test 6: CH0 free-run, hot-switch LFSR state
; Run 50 iterations with initial LFSR, capture OUT; switch LFSR on-the-fly;
; Results at _g_results + 15..16:
;===================================================================
.proc Test6
.segment "ZEROPAGE"
    pre_iter:  .res 1
    post_iter: .res 1
    ch0_ctla:  .res 1

.segment "CODE"
    jsr ResetTimers

    stz pre_iter
    stz post_iter

    lda #$03
    sta AUD0VOL

    lda #$44
    sta AUD0SHIFT
    lda #%10010000
    sta AUD0CTLB
    lda #$11
    sta AUD0FEED

    lda #$00
    sta AUD0BKUP
    sta AUD0CNT

    lda #(ENABLE_RELOAD | ENABLE_COUNT | ENABLE_INTEGRATE | $06)
    sta ch0_ctla
    sta AUD0CTLA

    ; -------- Phase 1: 50 iterations with initial LFSR --------
@loop_pre:
    ; wait for CH0 DONE
    lda AUD0CTLB
    and #$08
    beq @loop_pre

    inc pre_iter

    ; clear DONE
    lda ch0_ctla
    ora #RESET_DONE
    sta AUD0CTLA
    lda ch0_ctla
    sta AUD0CTLA

    lda pre_iter
    cmp #50
    bcc @loop_pre

    ; capture OUT just before changing LFSR
    lda AUD0OUT
    sta _g_results + 15     ; Expected: $D0

    ; -------- change LFSR state --------
    lda #$11
    sta AUD0SHIFT
    lda #%01100000
    sta AUD0CTLB

    ; -------- Capture one iteration after the switch --------
@wait_first_post:
    lda AUD0CTLB
    and #$08
    beq @wait_first_post

    ; clear DONE
    lda ch0_ctla
    ora #RESET_DONE
    sta AUD0CTLA
    lda ch0_ctla
    sta AUD0CTLA

    lda AUD0OUT
    sta _g_results + 16     ; Expected: $D3
    rts
.endproc

;===================================================================
; Test 7: CH0 VOL=0 with LFSR active
; Run several borrows; verify AUD0OUT stays at 0 while LFSR advances
; Result at _g_results + 17
;===================================================================
.proc Test7
.segment "ZEROPAGE"
    iter7:    .res 1
    ch0_ctla: .res 1
    init_lfsr:.res 1

.segment "CODE"
    jsr ResetTimers

    stz iter7

    lda #$00
    sta AUD0VOL

    lda #$B4            ; %1011_0100 -> taps at 11,10,5,4
    sta AUD0FEED

    lda #$A5
    sta AUD0SHIFT
    lda #%01110000
    sta AUD0CTLB

    lda #$00
    sta AUD0BKUP
    sta AUD0CNT

    lda #(ENABLE_RELOAD | ENABLE_COUNT | ENABLE_INTEGRATE | $06)
    sta ch0_ctla
    sta AUD0CTLA

    ; Remember initial lower 8 bits of LFSR for comparison
    lda AUD0SHIFT
    sta init_lfsr

@loop_7:
    ; Wait for CH0 DONE
    lda AUD0CTLB
    and #$08
    beq @loop_7

    ; On each DONE, OUT must still be 0 when VOL=0
    lda AUD0OUT
    bne @fail_7

    ; Clear DONE
    lda ch0_ctla
    ora #RESET_DONE
    sta AUD0CTLA
    lda ch0_ctla
    sta AUD0CTLA

    ; Iterate 16 DONEs to give time for LFSR to evolve
    inc iter7
    lda iter7
    cmp #16
    bcc @loop_7

    lda AUD0SHIFT
    sta _g_results + 17
    rts

@fail_7:
    lda #$FF
    sta _g_results + 17     ; Expected: $2B (or $FF on failure)
    rts
.endproc

;===================================================================
; Main test runner function
;===================================================================
_run_tests:
    sei                 ; Disable interrupts during testing
    jsr Test1
    jsr Test2
    jsr Test3
    jsr Test4
    jsr Test5
    jsr Test6
    jsr Test7
    jsr ResetTimers
    cli                 ; Re-enable interrupts
    rts