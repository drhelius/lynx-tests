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
.segment "RODATA"
    baud_backup:   .byte 12, 51, 103, 1

;-------------------------------------------------------------------
.segment "CODE"

;===================================================================
; Reset all timers except TIMER 0 and TIMER 2
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
    cpx #$1C
    bne @loop
    rts
.endproc

;-------------------------------------------------------------------
; UART Test 1: Idle -> measure until TXEMPTY
;   - Measure from the write to SERDAT until SERCTL.TXEMPTY=1
;   - Results in _g_results + 0..3
;-------------------------------------------------------------------
.proc Test1
.segment "ZEROPAGE"
    idx:        .res 1
    t6_ticks:   .res 1
    t6_ctla:    .res 1
    tmp:        .res 1

.segment "CODE"

    jsr ResetTimers

    lda #%00000100         ; TXOPEN=1
    sta SERCTL

    ldx #$00

@loop_speed:
    lda baud_backup,x
    sta TIM4BKUP
    sta TIM4CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $00)
    sta TIM4CTLA

    ; Wait until TX is completely idle (TXEMPTY=1)
@wait_empty_idle:
    lda SERCTL
    and #$20               ; B5 = TXEMPTY
    beq @wait_empty_idle

    ; Wait until holding register is ready (TXRDY=1)
@wait_txrdy:
    lda SERCTL
    and #$80               ; B7 = TXRDY
    beq @wait_txrdy

    ;----------------------------------------------------------------
    ; Start TIMER6 stopwatch = 64us, BKUP=0 (1 tick = 64us)
    ;----------------------------------------------------------------
    stz TIM6BKUP
    stz TIM6CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $06)
    sta t6_ctla
    sta TIM6CTLA

    ; Count TIMER6 ticks until TXEMPTY=1
    stz t6_ticks

    ; Start transmission (11 bits)
    lda #$A5
    sta SERDAT

@count_loop:
    ; Has TX finished?
    lda SERCTL
    and #$20               ; TXEMPTY
    bne @done_one_speed

    ; Has a 64us tick arrived?
    lda TIM6CTLB
    and #$08               ; DONE
    beq @count_loop

    ; +1 tick and clear DONE
    inc t6_ticks
    lda t6_ctla
    ora #RESET_DONE
    sta TIM6CTLA
    lda t6_ctla
    sta TIM6CTLA
    bra @count_loop

@done_one_speed:
    ; Store ticks (64us) in _g_results + 0..3
    lda t6_ticks
    sta _g_results + 0,x

    ; Next speed
    inx
    cpx #4
    bne @loop_speed

    rts
.endproc

;-------------------------------------------------------------------
; UART Test 2: Idle -> measure until TXREADY
;   - Measure from the write to SERDAT until SERCTL.TXREADY=1
;   - Results in _g_results + 4..7
;-------------------------------------------------------------------
.proc Test2
.segment "ZEROPAGE"
    idx:        .res 1
    t6_ticks:   .res 1
    t6_ctla:    .res 1
    tmp:        .res 1

.segment "CODE"

    jsr ResetTimers

    lda #%00000100         ; TXOPEN=1
    sta SERCTL

    ldx #$00

@loop_speed:
    lda baud_backup,x
    sta TIM4BKUP
    sta TIM4CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $00)
    sta TIM4CTLA

    ; Wait until TX is completely idle (TXEMPTY=1)
@wait_empty_idle:
    lda SERCTL
    and #$20               ; B5 = TXEMPTY
    beq @wait_empty_idle

    ; Wait until holding register is ready (TXRDY=1)
@wait_txrdy:
    lda SERCTL
    and #$80               ; B7 = TXRDY
    beq @wait_txrdy

    stz TIM6BKUP
    stz TIM6CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $06)
    sta t6_ctla
    sta TIM6CTLA

    ; Count TIMER6 ticks until TXEMPTY=1
    stz t6_ticks

    ; Start transmission (11 bits)
    lda #$A5
    sta SERDAT

@count_loop:
    ; Has TX finished?
    lda SERCTL
    and #$80               ; TXREADY
    bne @done_one_speed

    ; Has a 64us tick arrived?
    lda TIM6CTLB
    and #$08               ; DONE
    beq @count_loop

    ; +1 tick and clear DONE
    inc t6_ticks
    lda t6_ctla
    ora #RESET_DONE
    sta TIM6CTLA
    lda t6_ctla
    sta TIM6CTLA
    bra @count_loop

@done_one_speed:
    ; Store ticks (64us) in _g_results + 0..3
    lda t6_ticks
    sta _g_results + 4,x

    ; Next speed
    inx
    cpx #4
    bne @loop_speed

    rts
.endproc

;-------------------------------------------------------------------
; UART Test 3: Streaming -> measure until TXEMPTY
;   - Same as Test1, but in streaming mode: warm up with 8 bytes paced by TXRDY
;   - The last frame is measured until TXEMPTY=1
;   - Results in _g_results + 8..11
;-------------------------------------------------------------------
.proc Test3
.segment "ZEROPAGE"
    idx:        .res 1
    t6_ticks:   .res 1
    t6_ctla:    .res 1
    warmup:     .res 1

.segment "CODE"

    jsr ResetTimers

    lda #%00000100         ; TXOPEN=1
    sta SERCTL

    ldx #$00

@loop_speed:
    lda baud_backup,x
    sta TIM4BKUP
    sta TIM4CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $00)
    sta TIM4CTLA

    ; Wait until TX is completely idle (TXEMPTY=1)
@wait_empty_idle:
    lda SERCTL
    and #$20               ; B5 = TXEMPTY
    beq @wait_empty_idle

    ;----------------------------------------------------------------
    ; Warm-up phase: send 8 bytes paced by TXRDY
    ;----------------------------------------------------------------
    lda #8
    sta warmup

@warmup_loop:
    ; Wait until holding register is ready (TXRDY=1)
    lda SERCTL
    and #$80               ; B7 = TXRDY
    beq @warmup_loop

    lda #$A5
    sta SERDAT

    ; Continue until all warm-up bytes are sent
    dec warmup
    bne @warmup_loop

    ;----------------------------------------------------------------
    ; Wait for holding register to be ready before final measurement
    ;----------------------------------------------------------------
@wait_txrdy_before:
    lda SERCTL
    and #$80               ; B7 = TXRDY
    beq @wait_txrdy_before

    stz TIM6BKUP
    stz TIM6CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $06)
    sta t6_ctla
    sta TIM6CTLA

    ; Count TIMER6 ticks until TXEMPTY=1
    stz t6_ticks

    ; Start measured transmission
    lda #$A5
    sta SERDAT

@count_loop:
    ; Has TX finished?
    lda SERCTL
    and #$20               ; TXEMPTY
    bne @done_one_speed

    ; Has a 64us tick arrived?
    lda TIM6CTLB
    and #$08               ; DONE
    beq @count_loop

    ; +1 tick and clear DONE
    inc t6_ticks
    lda t6_ctla
    ora #RESET_DONE
    sta TIM6CTLA
    lda t6_ctla
    sta TIM6CTLA
    bra @count_loop

@done_one_speed:
    ; Store ticks (64us) in _g_results + 8..11
    lda t6_ticks
    sta _g_results + 8,x

    ; Next speed
    inx
    cpx #4
    bne @loop_speed

    rts
.endproc

;-------------------------------------------------------------------
; UART Test 4: Streaming -> measure until TXRDY
;   - Same as Test2, but in streaming mode: warm up with 8 bytes paced by TXRDY
;   - The last frame is measured until TXRDY=1
;   - Results in _g_results + 12..15
;-------------------------------------------------------------------
.proc Test4
.segment "ZEROPAGE"
    idx:        .res 1
    t6_ticks:   .res 1
    t6_ctla:    .res 1
    warmup:     .res 1

.segment "CODE"

    jsr ResetTimers

    lda #%00000100         ; TXOPEN=1
    sta SERCTL

    ldx #$00

@loop_speed:
    lda baud_backup,x
    sta TIM4BKUP
    sta TIM4CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $00)
    sta TIM4CTLA

    ; Wait until TX is completely idle (TXEMPTY=1)
@wait_empty_idle:
    lda SERCTL
    and #$20               ; B5 = TXEMPTY
    beq @wait_empty_idle

    ;----------------------------------------------------------------
    ; Warm-up phase: send 8 bytes paced by TXRDY
    ;----------------------------------------------------------------
    lda #8
    sta warmup

@warmup_loop:
    ; Wait until holding register is ready (TXRDY=1)
    lda SERCTL
    and #$80               ; B7 = TXRDY
    beq @warmup_loop

    lda #$A5
    sta SERDAT

    ; Continue until all warm-up bytes are sent
    dec warmup
    bne @warmup_loop

    ;----------------------------------------------------------------
    ; Wait for holding register to be ready before final measurement
    ;----------------------------------------------------------------
@wait_txrdy_before:
    lda SERCTL
    and #$80               ; B7 = TXRDY
    beq @wait_txrdy_before

    stz TIM6BKUP
    stz TIM6CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $06)
    sta t6_ctla
    sta TIM6CTLA

    ; Count TIMER6 ticks until TXRDY=1
    stz t6_ticks

    ; Start measured transmission
    lda #$A5
    sta SERDAT

@count_loop:
    ; Has TX finished?
    lda SERCTL
    and #$80               ; TXREADY
    bne @done_one_speed

    ; Has a 64us tick arrived?
    lda TIM6CTLB
    and #$08               ; DONE
    beq @count_loop

    ; +1 tick and clear DONE
    inc t6_ticks
    lda t6_ctla
    ora #RESET_DONE
    sta TIM6CTLA
    lda t6_ctla
    sta TIM6CTLA
    bra @count_loop

@done_one_speed:
    ; Store ticks (64us) in _g_results + 12..15
    lda t6_ticks
    sta _g_results + 12,x

    ; Next speed
    inx
    cpx #4
    bne @loop_speed

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
    jsr ResetTimers
    cli                 ; Re-enable interrupts
    rts