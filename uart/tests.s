.setcpu "65C02"

.include "lynx.inc"

.import _set_irq
.import _get_irq

.export _run_tests
.export _g_results

;-------------------------------------------------------------------
.segment "BSS"
    _g_results: .res 27

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

    ; Count TIMER6 ticks until TXEMPTY=1
    stz t6_ticks

    stz TIM6BKUP
    stz TIM6CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $06)
    sta t6_ctla
    sta TIM6CTLA

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
    ; Expected: $14 or $15 for 9600 bps, $53 or $54 for 2400 bps, $A9 or $AA for 1200 bps, $03 or $04 for 62500 bps
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

    ; Count TIMER6 ticks until TXEMPTY=1
    stz t6_ticks

    stz TIM6BKUP
    stz TIM6CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $06)
    sta t6_ctla
    sta TIM6CTLA

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
    ; Store ticks (64us) in _g_results + 4..7
    ; Expected: $02 or $03 or $04 for 9600 bps, $0D or $0E for 2400 bps, $1A or $1B for 1200 bps, $01 or $02 for 62500 bps
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

    ; Count TIMER6 ticks until TXEMPTY=1
    stz t6_ticks

    stz TIM6BKUP
    stz TIM6CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $06)
    sta t6_ctla
    sta TIM6CTLA

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
    ; Expected: $24 or $25 for 9600 bps, $8F or $90 for 2400 bps, $1E or $1F for 1200 bps, $06 or $07 for 62500 bps
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

    ; Count TIMER6 ticks until TXRDY=1
    stz t6_ticks

    stz TIM6BKUP
    stz TIM6CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $06)
    sta t6_ctla
    sta TIM6CTLA

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
    ; Expected: $12 or $13 for 9600 bps, $48 for 2400 bps, $8F or $90 for 1200 bps, $03 or $04 for 62500 bps
    lda t6_ticks
    sta _g_results + 12,x

    ; Next speed
    inx
    cpx #4
    bne @loop_speed

    rts
.endproc

;-------------------------------------------------------------------
; UART Test 5: Streaming -> measure until INT4 (TXRDY IRQ)
;   - Warm up with 8 bytes paced by TXRDY
;   - On the 9th byte: clear INTRST bit4, start TIMER6 (64us) and write SERDAT
;   - Measure until INTRST bit4 (INT4 UART) = 1 => should match Test4
;   - Results in _g_results + 16..19
;-------------------------------------------------------------------
.proc Test5
.segment "ZEROPAGE"
    idx:        .res 1
    t6_ticks:   .res 1
    t6_ctla:    .res 1
    warmup:     .res 1

.segment "CODE"

    jsr ResetTimers

    lda #%10000100         ; TXOPEN=1, TXINTEN=1
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

    ; Count TIMER6 ticks until INT4=1
    stz t6_ticks

    ; Start TIMER6 = 64us/tick
    stz TIM6BKUP
    stz TIM6CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $06)
    sta t6_ctla
    sta TIM6CTLA

    ; Start measured transmission (this pulls TXRDY=0)
    lda #$A5
    sta SERDAT

    ; Now clear pending INT4 so it won't be immediately re-asserted by the
    ; pre-existing TXRDY=1 level. We want to measure until the NEXT TXRDY=1.
    lda #$10
    sta INTRST             ; $FD80

@count_irq:
    ; Is INT4 pending?
    lda INTRST
    and #$10
    bne @done_one

    ; Has a 64us tick arrived?
    lda TIM6CTLB
    and #$08
    beq @count_irq

    ; +1 tick and clear DONE
    inc t6_ticks
    lda t6_ctla
    ora #RESET_DONE
    sta TIM6CTLA
    lda t6_ctla
    sta TIM6CTLA
    bra @count_irq

@done_one:
    ; Store ticks (64us) in _g_results + 16..19
    ; Expected: $12 or $13 for 9600 bps, $48 for 2400 bps, $8F or $90 for 1200 bps, $03 or $04 for 62500 bps
    lda t6_ticks
    sta _g_results + 16,x

    ; Next speed
    inx
    cpx #4
    bne @loop_speed
    rts
.endproc

;-------------------------------------------------------------------
; UART Test 6: TXBRK → measure until TXRDY when releasing break
;   - With TXBRK=1, write SERDAT (data is held)
;   - When releasing TXBRK: start TIMER6 and measure until TXRDY=1
;   - Results in _g_results + 20..23
;-------------------------------------------------------------------
.proc Test6
.segment "ZEROPAGE"
    idx:        .res 1
    t6_ticks:   .res 1
    t6_ctla:    .res 1

.segment "CODE"

    jsr ResetTimers

    ldx #$00

@loop_speed:
    ; Count TIMER6 ticks until TXRDY=1
    stz t6_ticks

    lda baud_backup,x
    sta TIM4BKUP
    sta TIM4CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $00)
    sta TIM4CTLA

    ; Set SERCTL: TXOPEN=1, TXBRK=1, no parity, IRQs off
    lda #%00000000
    sta SERCTL
    lda #%00000110            ; B2=TXOPEN, B1=TXBRK
    sta SERCTL

    ; Write a byte: it will be held while TXBRK=1
    lda #$A5
    sta SERDAT

    ; Release break and start stopwatch
    stz TIM6BKUP
    stz TIM6CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $06)
    sta t6_ctla
    sta TIM6CTLA

    lda #%00000100            ; TXOPEN=1, BRK=0
    sta SERCTL

@count_txrdy:
    ; Has holding register become ready?
    lda SERCTL
    and #$80                  ; TXRDY
    bne @done_one

    ; Has a 64us tick arrived?
    lda TIM6CTLB
    and #$08                  ; DONE
    beq @count_txrdy

    ; +1 tick and clear DONE
    inc t6_ticks
    lda t6_ctla
    ora #RESET_DONE
    sta TIM6CTLA
    lda t6_ctla
    sta TIM6CTLA
    bra @count_txrdy

@done_one:
    ; Store ticks (64us) in _g_results + 20..23
    ; Expected: $07 or $08 for 9600 bps, $46 or $47 for 2400 bps, $8F or $90 for 1200 bps, $03 or $04 for 62500 bps
    lda t6_ticks
    sta _g_results + 20,x

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
    jsr Test5
    jsr Test6
    stz SERCTL          ; Disable UART
    jsr ResetTimers
    cli                 ; Re-enable interrupts
    rts