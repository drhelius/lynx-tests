.setcpu "65C02"

.include "lynx.inc"

.export _run_tests
.export _g_results

;-------------------------------------------------------------------
; ComLynx loopback fidelity.
;
; The UART transmit and receive pins are the same open collector wire,
; so a Lynx always hears its own transmission. Every test here uses
; that echo, which means none of them need a second console or a cable.
;
; Baud is 62500 (TIM4 backup 1, 1us clock, /8): one bit is 16us and a
; full 11 bit frame is 176us, so a single 1us timer measures a frame
; without needing linked timers.
;-------------------------------------------------------------------

ECHO_MIN        = 150           ; us, one frame at 62500 baud is 176us
ECHO_MAX        = 240           ; the frame start is not locked to the write
BURST_LEN       = 8

;-------------------------------------------------------------------
.segment "ZEROPAGE"
    rx_count:   .res 1          ; shared with StoreByte
    probe_cnt:  .res 1
    probe_first: .res 1

;-------------------------------------------------------------------
.segment "BSS"
    _g_results: .res 27
    rx_buffer:  .res 16

;-------------------------------------------------------------------
.segment "RODATA"
    burst_data: .byte $01, $02, $04, $08, $10, $20, $40, $80

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

;===================================================================
; Wait for TXEMPTY=1
;===================================================================
.proc WaitIdle
@wait_idle:
    lda SERCTL
    and #$20
    beq @wait_idle
    rts
.endproc

;===================================================================
; Baud 62500, TXOPEN, errors cleared, RX drained, TIMER1 free running
; at 1us so elapsed time can be sampled from TIM1CNT.
;===================================================================
.proc SetupUart
    jsr ResetTimers

    lda #$01
    sta TIM4BKUP
    sta TIM4CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $00)
    sta TIM4CTLA

    lda #$FF
    sta TIM1BKUP
    sta TIM1CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $00)
    sta TIM1CTLA

    lda #%00000100          ; TXOPEN=1
    sta SERCTL
    lda #%00001100          ; RESETERR=1, TXOPEN=1
    sta SERCTL
    lda #%00000100          ; RESETERR=0, TXOPEN=1
    sta SERCTL

@drain:
    lda SERCTL
    and #$40                ; RXRDY?
    beq @drained
    lda SERDAT
    bra @drain
@drained:
    jsr WaitIdle
    rts
.endproc

;===================================================================
; Clear receive errors, keeping TXOPEN asserted
;===================================================================
.proc ClearErrors
    lda #%00001100          ; RESETERR=1, TXOPEN=1
    sta SERCTL
    lda #%00000100          ; RESETERR=0, TXOPEN=1
    sta SERCTL
    rts
.endproc

;-------------------------------------------------------------------
; Test 1: echo latency
; Time from writing SERDAT on an idle line until RXRDY reports the
; echoed byte. One frame at 62500 baud is 176us.
;  Results:
;   +0: measured latency in us
;   +1: 0 when the measurement sits inside the expected window
;-------------------------------------------------------------------
.proc Test1
.segment "ZEROPAGE"
    t_start:    .res 1
    t_delta:    .res 1

.segment "CODE"

    jsr SetupUart

    lda TIM1CNT
    sta t_start

    lda #$A5
    sta SERDAT

@wait_rx:
    lda SERCTL
    and #$40                ; RXRDY?
    beq @wait_rx

    ; TIMER1 counts down, so elapsed is start minus current
    lda t_start
    sec
    sbc TIM1CNT
    sta t_delta
    sta _g_results + 0

    lda SERDAT              ; consume the echo

    lda #$00
    ldx t_delta
    cpx #ECHO_MIN
    bcc @out_of_range
    cpx #(ECHO_MAX + 1)
    bcs @out_of_range
    bra @store
@out_of_range:
    lda #$01
@store:
    sta _g_results + 1      ; Expected: $00 (echo lands one frame later)

    jsr WaitIdle
    rts
.endproc

;-------------------------------------------------------------------
; Test 2: echo gap
; Distance between two echoes while transmitting back to back. The
; wire carries one frame at a time, so the gap is also one frame.
;  Results:
;   +2: measured gap in us
;   +3: 0 when the measurement sits inside the expected window
;-------------------------------------------------------------------
.proc Test2
.segment "ZEROPAGE"
    g_start:    .res 1
    g_delta:    .res 1

.segment "CODE"

    jsr SetupUart

    lda #$5A
    sta SERDAT

@wait_txrdy:
    lda SERCTL
    and #$80                ; TXRDY, holding register free
    beq @wait_txrdy

    lda #$3C                ; chain the second frame
    sta SERDAT

@wait_first:
    lda SERCTL
    and #$40
    beq @wait_first

    lda SERDAT              ; consume first echo
    lda TIM1CNT
    sta g_start

@wait_second:
    lda SERCTL
    and #$40
    beq @wait_second

    lda g_start
    sec
    sbc TIM1CNT
    sta g_delta
    sta _g_results + 2

    lda SERDAT              ; consume second echo

    lda #$00
    ldx g_delta
    cpx #ECHO_MIN
    bcc @out_of_range
    cpx #(ECHO_MAX + 1)
    bcs @out_of_range
    bra @store
@out_of_range:
    lda #$01
@store:
    sta _g_results + 3      ; Expected: $00 (chained echoes are one frame apart)

    jsr WaitIdle
    rts
.endproc

;-------------------------------------------------------------------
; Test 3: burst echo
; Transmit BURST_LEN bytes back to back, draining the receiver once per
; TXRDY. The receiver holds a single byte, so the last frame lands on
; top of the one before it while the transmitter is being waited out:
; the burst comes back one byte short, out of step, and with OVERRUN.
;  Results:
;   +4: bytes echoed back
;   +5: bitmask of mismatched positions folded into one byte
;   +6: 1 when OVERRUN was reported
;-------------------------------------------------------------------
.proc Test3
.segment "ZEROPAGE"
    sent:       .res 1
    diff:       .res 1
    first_bad:  .res 1

.segment "CODE"

    jsr SetupUart

    stz sent
    stz rx_count
    stz diff
    lda #$FF
    sta first_bad

@send_loop:
    ldx sent
    cpx #BURST_LEN
    bcs @flush

@wait_txrdy:
    lda SERCTL
    and #$80
    beq @wait_txrdy

    ldx sent
    lda burst_data,x
    sta SERDAT
    inc sent

    ; Drain whatever the receiver has ready so the FIFO never backs up
    lda SERCTL
    and #$40
    beq @send_loop
    jsr StoreByte
    bra @send_loop

@flush:
    lda rx_count
    sta _g_results + 20     ; Informational: how far behind the reader ended up

    jsr WaitIdle

@drain_loop:
    lda SERCTL
    and #$40
    beq @drained
    jsr StoreByte
    bra @drain_loop
@drained:

    lda rx_count
    sta _g_results + 4      ; Expected: BURST_LEN - 1 (one frame is lost)

    ; Compare what came back against what went out
    ldx #$00
@compare:
    cpx rx_count
    bcs @compared
    lda rx_buffer,x
    cmp burst_data,x
    beq @next
    lda diff
    ora #$01
    sta diff
    lda first_bad
    cmp #$FF
    bne @next
    stx first_bad           ; where the stream first diverges
@next:
    inx
    bra @compare
@compared:

    lda rx_buffer + 6
    sta _g_results + 23     ; Informational: what landed where the burst diverged

    lda first_bad
    sta _g_results + 17     ; Informational: $FF when nothing diverged

    lda diff
    sta _g_results + 5      ; Expected: $01 (the tail shifts by one byte)

    lda #$00
    ldx SERCTL
    txa
    and #$08                ; OVERRUN?
    beq @no_overrun
    lda #$01
@no_overrun:
    sta _g_results + 6      ; Expected: $01 (the lost frame is reported)

    jsr ClearErrors
    jsr WaitIdle
    rts
.endproc

;===================================================================
; Append SERDAT to rx_buffer, bounded by the buffer size
;===================================================================
.proc StoreByte
    ldx rx_count
    cpx #16
    bcs @full
    lda SERDAT
    sta rx_buffer,x
    inc rx_count
    rts
@full:
    lda SERDAT
    rts
.endproc

;-------------------------------------------------------------------
; Test 4: echo order
; While chaining frames, the echo of the byte being shifted out must
; not be reported before that frame finishes. TXRDY marks the holding
; register going free, which happens a whole frame before the echo.
;  Results:
;   +7: 0 when RXRDY was still clear at the first TXRDY
;-------------------------------------------------------------------
.proc Test4
.segment "ZEROPAGE"
    flags:      .res 1

.segment "CODE"

    jsr SetupUart

    stz flags

    lda #$96
    sta SERDAT

@wait_txrdy:
    lda SERCTL
    and #$80
    beq @wait_txrdy

    ; The first frame is still on the wire here, so no echo yet
    lda SERCTL
    and #$40
    beq @order_ok
    lda flags
    ora #$01
    sta flags
@order_ok:

    lda flags
    sta _g_results + 7      ; Expected: $00 (echo trails the frame, not TXRDY)

    jsr WaitIdle
@drain:
    lda SERCTL
    and #$40
    beq @drained
    lda SERDAT
    bra @drain
@drained:
    jsr ClearErrors
    rts
.endproc

;-------------------------------------------------------------------
; Test 5: slow reader
; Same burst as test 3 but the receiver is never drained. The two deep
; receive buffer must fill and report an overrun, which is what a game
; sees when it transmits without servicing its own echo.
;  Results:
;   +8: bytes that could still be read afterwards
;   +9: 1 when OVERRUN was reported
;-------------------------------------------------------------------
.proc Test5
.segment "ZEROPAGE"
    sent5:      .res 1
    got5:       .res 1

.segment "CODE"

    jsr SetupUart

    stz sent5
    stz got5

@send_loop:
    ldx sent5
    cpx #BURST_LEN
    bcs @flush

@wait_txrdy:
    lda SERCTL
    and #$80
    beq @wait_txrdy

    ldx sent5
    lda burst_data,x
    sta SERDAT
    inc sent5
    bra @send_loop

@flush:
    jsr WaitIdle

    lda #$00
    ldx SERCTL
    txa
    and #$08                ; OVERRUN?
    beq @no_overrun
    lda #$01
@no_overrun:
    pha

@count_loop:
    lda SERCTL
    and #$40
    beq @counted
    lda SERDAT
    inc got5
    bra @count_loop
@counted:

    lda got5
    sta _g_results + 8      ; Informational: what survived in the buffer

    pla
    sta _g_results + 9      ; Expected: $01 (an unread burst must overrun)

    jsr ClearErrors
    jsr WaitIdle
    rts
.endproc

;-------------------------------------------------------------------
; Test 6: echo parity
; The ninth bit travels with the frame, so the echo reports it back.
; With PAREN set it is a calculated parity bit, with PAREN clear it is
; whatever PAREVEN holds. Note the Lynx parity calculation includes the
; parity bit itself.
;  Results:
;   +10: PAREN=1 PAREVEN=0, echo reported a parity error
;   +11: PAREN=1 PAREVEN=1, echo reported a parity error
;   +12: PAREN=0 PAREVEN=0, ninth bit did not read back as 0
;   +13: PAREN=0 PAREVEN=1, ninth bit did not read back as 1
;-------------------------------------------------------------------
.proc Test6
.segment "ZEROPAGE"
    p_flags:    .res 1

.segment "CODE"

    ; ---- PAREN=1, PAREVEN=0 ----
    jsr SetupUart
    lda #%00010100          ; PAREN=1, TXOPEN=1, PAREVEN=0
    sta SERCTL
    jsr SendProbe
    lda #$00
    ldx SERCTL
    txa
    and #$10                ; PARERR?
    beq @odd_ok
    lda #$01
@odd_ok:
    sta _g_results + 10     ; Expected: $00 (own frame must not fail parity)
    jsr DrainAndClear

    ; ---- PAREN=1, PAREVEN=1 ----
    jsr SetupUart
    lda #%00010101          ; PAREN=1, PAREVEN=1, TXOPEN=1
    sta SERCTL
    jsr SendProbe
    lda #$00
    ldx SERCTL
    txa
    and #$10
    beq @even_ok
    lda #$01
@even_ok:
    sta _g_results + 11     ; Expected: $00 (own frame must not fail parity)
    jsr DrainAndClear

    ; ---- PAREN=0, PAREVEN=0: ninth bit is PAREVEN ----
    jsr SetupUart
    lda #%00000100          ; PAREN=0, PAREVEN=0, TXOPEN=1
    sta SERCTL
    jsr SendProbe
    lda #$00
    ldx SERCTL
    txa
    and #$01                ; PARBIT
    beq @low_ok
    lda #$01
@low_ok:
    sta _g_results + 12     ; Expected: $00 (ninth bit echoes back as 0)
    jsr DrainAndClear

    ; ---- PAREN=0, PAREVEN=1: ninth bit is PAREVEN ----
    jsr SetupUart
    lda #%00000101          ; PAREN=0, PAREVEN=1, TXOPEN=1
    sta SERCTL
    jsr SendProbe
    lda SERCTL
    and #$01                ; PARBIT
    bne @high_ok
    lda #$01
    bra @high_store
@high_ok:
    lda #$00
@high_store:
    sta _g_results + 13     ; Expected: $00 (ninth bit echoes back as 1)
    jsr DrainAndClear

    rts
.endproc

;===================================================================
; Transmit one byte and wait for its echo to be reported
;===================================================================
.proc SendProbe
    lda #$C3
    sta SERDAT
@wait_rx:
    lda SERCTL
    and #$40
    beq @wait_rx
    rts
.endproc

;===================================================================
; Drain the receiver and clear any error left behind
;===================================================================
.proc DrainAndClear
    jsr WaitIdle
@drain:
    lda SERCTL
    and #$40
    beq @drained
    lda SERDAT
    bra @drain
@drained:
    jsr ClearErrors
    rts
.endproc

;-------------------------------------------------------------------
; Test 7: echo against TXEMPTY
; Both TXEMPTY and the echo are reported some time after the frame has
; left the wire, and code that drains right after waiting for an idle
; transmitter depends on which of the two comes first. Measured from
; the write to SERDAT on an idle line.
;  Results:
;   +14: us until TXEMPTY
;   +15: us until RXRDY
;   +16: 1 when the echo was already reported at the first TXEMPTY
;-------------------------------------------------------------------
.proc Test7
.segment "ZEROPAGE"
    e_start:    .res 1
    e_flag:     .res 1

.segment "CODE"

    jsr SetupUart

    lda TIM1CNT
    sta e_start

    lda #$A5
    sta SERDAT

@wait_empty:
    lda SERCTL
    and #$20                ; TXEMPTY?
    beq @wait_empty

    lda e_start
    sec
    sbc TIM1CNT
    sta _g_results + 14     ; Informational: one frame plus the idle delay

    stz e_flag
    lda SERCTL
    and #$40                ; RXRDY already?
    beq @wait_rx
    lda #$01
    sta e_flag

@wait_rx:
    lda SERCTL
    and #$40
    beq @wait_rx

    lda e_start
    sec
    sbc TIM1CNT
    sta _g_results + 15     ; Informational: same figure as test 1

    lda e_flag
    sta _g_results + 16     ; Informational: which of the two came first

    lda SERDAT
    jsr ClearErrors
    jsr WaitIdle
    rts
.endproc

;-------------------------------------------------------------------
; Test 8: how many chained frames the receiver holds, per baud divider
; One byte is written to an idle transmitter and a second goes into the
; holding register, so exactly two frames reach the wire. Nothing is
; read until both have finished. The sweep runs the same sequence at
; four dividers to tell a rate effect from a quirk of the fastest one.
;  Results:
;   +18: 1 when the first echo was already reported at the second TXRDY
;   +19: bytes readable, TIM4 backup 5
;   +21: bytes readable, TIM4 backup 6
;   +23: bytes readable, TIM4 backup 8
;   +24: bytes readable, TIM4 backup 10
;   +22: first byte read at backup 5
;   +25: first byte read at backup 10
;-------------------------------------------------------------------
.proc Test8
.segment "ZEROPAGE"
    c_flag:     .res 1

.segment "CODE"

    jsr SetupUart

    stz c_flag

    lda #$5A
    sta SERDAT

@wait_txrdy1:
    lda SERCTL
    and #$80
    beq @wait_txrdy1

    lda #$3C                ; into the holding register
    sta SERDAT

    ; This TXRDY means the first frame has left the wire
@wait_txrdy2:
    lda SERCTL
    and #$80
    beq @wait_txrdy2

    lda SERCTL
    and #$40                ; echo of the first frame already?
    beq @store_flag
    lda #$01
    sta c_flag
@store_flag:
    lda c_flag
    sta _g_results + 18

    jsr WaitIdle
@drain8:
    lda SERCTL
    and #$40
    beq @drained8
    lda SERDAT
    bra @drain8
@drained8:

    lda #$05
    jsr TwoFrameProbe
    lda probe_cnt
    sta _g_results + 19
    lda probe_first
    sta _g_results + 22

    lda #$06
    jsr TwoFrameProbe
    lda probe_cnt
    sta _g_results + 21

    lda #$08
    jsr TwoFrameProbe
    lda probe_cnt
    sta _g_results + 23

    lda #10
    jsr TwoFrameProbe
    lda probe_cnt
    sta _g_results + 24
    lda probe_first
    sta _g_results + 25

    jsr ClearErrors
    rts
.endproc

;===================================================================
.proc TwoFrameProbe
    sta TIM4BKUP
    sta TIM4CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $00)
    sta TIM4CTLA

    lda #%00000100          ; TXOPEN=1
    sta SERCTL
    jsr ClearErrors
    jsr WaitIdle
@drain:
    lda SERCTL
    and #$40
    beq @drained
    lda SERDAT
    bra @drain
@drained:

    stz probe_cnt
    stz probe_first

    lda #$5A
    sta SERDAT

@wait_txrdy:
    lda SERCTL
    and #$80
    beq @wait_txrdy

    lda #$3C                ; into the holding register
    sta SERDAT

    jsr WaitIdle

@count:
    lda SERCTL
    and #$40
    beq @counted
    lda SERDAT
    ldx probe_cnt
    bne @bump
    sta probe_first
@bump:
    inc probe_cnt
    bra @count
@counted:
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
    jsr Test8

    stz SERCTL          ; Disable UART
    jsr ResetTimers
    cli                 ; Re-enable interrupts
    rts
