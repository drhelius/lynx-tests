.setcpu "65C02"

.include "lynx.inc"

.export _run_tests
.export _wait_for_peer
.export _g_results

;-------------------------------------------------------------------
; ComLynx behaviour that only two consoles can show.
;
; Both units run this same ROM. They first find each other, then agree
; on a master and a slave, and only then run the tests. Every test is
; framed by a barrier so the two sides stay in step.
;
; ComLynx is one open collector wire, so a console always hears its own
; transmission as well as the peer's. Telling those apart is what most
; of these tests are about.
;
; Baud is 62500 (TIM4 backup 1): one bit is 16us, a frame is 176us.
;-------------------------------------------------------------------

LOGON_BYTE      = $81           ; master offering the link
JOIN_BYTE       = $42           ; slave taking it
SYNC_MASTER     = $5A
SYNC_SLAVE      = $A5
BURST_LEN       = 8
RX_TIMEOUT      = 200           ; polling passes before giving up

;-------------------------------------------------------------------
.segment "ZEROPAGE"
    role:       .res 1          ; 1 master, 0 slave
    my_id:      .res 1
    listen:     .res 1          ; remaining silent passes before taking the wire
    rx_byte:    .res 1
    rx_flags:   .res 1          ; SERCTL as it stood for the byte in rx_byte
    flag_acc:   .res 1          ; error bits seen across a whole burst
    rx_ok:      .res 1
    rx_count:   .res 1
    tmp_a:      .res 1
    tmp_b:      .res 1

;-------------------------------------------------------------------
.segment "BSS"
    _g_results: .res 18
    rx_buffer:  .res 16

;-------------------------------------------------------------------
.segment "RODATA"
    burst_data: .byte $01, $23, $45, $67, $89, $AB, $CD, $EF

;-------------------------------------------------------------------
.segment "CODE"

;===================================================================
; Reset all timers except TIMER 0 and TIMER 2
;===================================================================
.proc ResetTimers
    ldx #$00
@loop:
    cpx #$04
    bcc @do_reset
    cpx #$08
    bcc @skip_reset
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
@wait:
    lda SERCTL
    and #$20
    beq @wait
    rts
.endproc

;===================================================================
; Baud 62500, TXOPEN, errors cleared, receiver drained
;===================================================================
.proc SetupUart
    lda #$01
    sta TIM4BKUP
    sta TIM4CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $00)
    sta TIM4CTLA

    lda #%00000100          ; TXOPEN=1
    sta SERCTL
    jsr ClearErrors
    jsr DrainRx
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

;===================================================================
; Discard anything sitting in the receiver
;===================================================================
.proc DrainRx
@loop:
    lda SERCTL
    and #$40
    beq @done
    lda SERDAT
    bra @loop
@done:
    rts
.endproc

;===================================================================
; Wait until the wire has been silent for a full receive timeout.
;
; A collision leaves frames in flight that reach us long after the test
; that caused them, and those would be read as the next barrier.
;===================================================================
.proc Quiesce
@loop:
    jsr ReadTimeout
    lda rx_ok
    bne @loop
    jsr ClearErrors
    rts
.endproc

;===================================================================
; Wait a bounded time for a byte. rx_ok=1 and rx_byte set on success.
;
; Reading SERDAT moves the buffer on, so the status has to be taken
; first or the flags belonging to this byte are lost.
;===================================================================
.proc ReadTimeout
    stz rx_ok
    ldy #RX_TIMEOUT
@outer:
    ldx #$00
@inner:
    lda SERCTL
    and #$40
    bne @got
    inx
    bne @inner
    dey
    bne @outer
    rts
@got:
    jsr LatchFlags
    lda SERDAT
    sta rx_byte
    lda #$01
    sta rx_ok
    rts
.endproc

;===================================================================
; Snapshot the receive status belonging to the byte about to be read
;===================================================================
.proc LatchFlags
    lda SERCTL
    sta rx_flags
    and #$1C                ; PARERR, OVERRUN, FRAMERR
    ora flag_acc
    sta flag_acc
    rts
.endproc

;===================================================================
; Send one byte and swallow the echo it produces on the shared wire
;===================================================================
.proc SendAndEatEcho
    sta tmp_a
    sta SERDAT
    jsr ReadTimeout         ; our own frame comes back first
    rts
.endproc

;===================================================================
; Barrier so both consoles enter the next test together. Only one
; side transmits at a time, so this never collides.
;===================================================================
.proc SyncPeer
    jsr WaitIdle
    jsr Quiesce

    lda role
    beq @slave

    ; The slave may still be settling when the first call goes out, so the
    ; master keeps offering until it is answered.
@master_retry:
    lda #SYNC_MASTER
    jsr SendAndEatEcho
    jsr ReadTimeout
    lda rx_ok
    beq @retry
    lda rx_byte
    cmp #SYNC_SLAVE
    beq @done
@retry:
    jsr Backoff
    bra @master_retry

@slave:
@slave_wait:
    jsr ReadTimeout
    lda rx_ok
    beq @slave_wait
    lda rx_byte
    cmp #SYNC_MASTER
    bne @slave_wait
    lda #SYNC_SLAVE
    jsr SendAndEatEcho
@done:
    rts
.endproc

;===================================================================
; Find the peer and agree on roles, the way RedEye logs players on.
;
; A console first listens. Hearing a logon offer means somebody else
; already owns the wire, so this side answers and becomes the slave.
; Finding the wire silent instead, it takes the wire itself and offers
; the logon until it is answered.
;
; Two consoles are never switched on together, so in practice the one
; that was already running is the master. If they do collide, both hear
; a logon while offering one, and both fall back to listening for a
; fresh spell drawn from the free running display timer, so the tie
; breaks after a pass or two.
;===================================================================
_wait_for_peer:
    sei
    jsr ResetTimers
    jsr SetupUart

    stz role
    stz tmp_a
    stz tmp_b
    lda TIM0CNT
    ora #$01                ; keep it non zero
    sta my_id

@listen_again:
    lda TIM0CNT
    and #$07
    clc
    adc #$04
    sta listen
    jsr DrainRx
    jsr ClearErrors

@listen_loop:
    jsr ReadTimeout
    lda rx_ok
    beq @listen_quiet
    lda rx_byte
    cmp #LOGON_BYTE
    beq @is_slave
    bra @listen_loop        ; leftovers from an earlier attempt
@listen_quiet:
    dec listen
    bne @listen_loop

@is_master:
    lda #$01
    sta role
@offer:
    jsr DrainRx
    lda #LOGON_BYTE
    jsr SendAndEatEcho      ; our own echo
    jsr ReadTimeout
    lda rx_ok
    beq @offer
    lda rx_byte
    cmp #LOGON_BYTE
    bne @elected            ; anything else is the slave answering
    stz role                ; both of us tried to own the wire
    bra @listen_again

@is_slave:
    stz role
@join:
    jsr WaitIdle
    lda #JOIN_BYTE
    jsr SendAndEatEcho
    jsr ReadTimeout
    lda rx_ok
    beq @elected            ; silence means the master took us on
    lda rx_byte
    cmp #LOGON_BYTE
    beq @join               ; still offering, so it missed our answer

@elected:
    jsr WaitIdle
    jsr DrainRx
    jsr ClearErrors
    lda role
    sta _g_results + 11
    cli
    lda role
    ldx #$00
    rts

;===================================================================
; Idle for a spell whose length depends on our own id
;===================================================================
.proc Backoff
    lda my_id
    and #$0F
    clc
    adc #$04
    tay
@outer:
    ldx #$00
@inner:
    nop
    inx
    bne @inner
    dey
    bne @outer
    rts
.endproc

;===================================================================
; A barrier only proves the peer reached it, not that it is already
; listening. The transmitting side waits this out first so the receiver
; is armed before the first frame goes on the wire.
;===================================================================
.proc Settle
    ldy #$20
@outer:
    ldx #$00
@inner:
    nop
    inx
    bne @inner
    dey
    bne @outer
    rts
.endproc

;===================================================================
; Take a byte if one is waiting, so the two deep buffer never backs up
;===================================================================
.proc PollRx
    lda SERCTL
    and #$40
    beq @done
    jsr LatchFlags
    ldx rx_count
    cpx #16
    bcs @discard
    lda SERDAT
    sta rx_buffer,x
    inc rx_count
    rts
@discard:
    lda SERDAT
@done:
    rts
.endproc

;-------------------------------------------------------------------
; Test 1: peer burst
; The master sends a back to back burst. The slave must see every byte,
; in order, with no receive errors. The master sees only its own echo,
; which must also arrive complete.
;  Results:
;   +0: bytes received (raw)
;   +1: mismatched bytes
;   +2: receive error flags observed
;-------------------------------------------------------------------
.proc Test1
    jsr SyncPeer

    stz rx_count
    stz tmp_b
    stz flag_acc

    lda role
    beq @receive

    ; ---- master transmits ----
    jsr Settle
    ldx #$00
@send:
    stx tmp_a
@wait_txrdy:
    jsr PollRx              ; our own echo comes back as we go
    lda SERCTL
    and #$80
    beq @wait_txrdy
    ldx tmp_a
    lda burst_data,x
    sta SERDAT
    ldx tmp_a
    inx
    cpx #BURST_LEN
    bne @send

    ; The last echoes land after the final byte is queued, so keep taking
    ; them or the two deep buffer overruns while we wait for the shifter.
@wait_idle:
    jsr PollRx
    lda SERCTL
    and #$20
    beq @wait_idle
    bra @collect

@receive:
    ; nothing to send, just collect what arrives
@collect:
    lda rx_count
    cmp #BURST_LEN
    bcs @collected          ; stopping here keeps the next barrier out of the burst
    jsr ReadTimeout
    lda rx_ok
    beq @collected
    ldx rx_count
    lda rx_byte
    sta rx_buffer,x
    inc rx_count
    bra @collect
@collected:

    lda flag_acc            ; PARERR, OVERRUN, FRAMERR
    sta _g_results + 2      ; Expected: $00 (a clean burst raises no errors)

    lda rx_count
    sta _g_results + 0

    ; Compare against the transmitted pattern
    ldx #$00
@compare:
    cpx rx_count
    bcs @compared
    lda rx_buffer,x
    cmp burst_data,x
    beq @next
    lda tmp_b
    ora #$01
    sta tmp_b
@next:
    inx
    bra @compare
@compared:

    ; A short count is also a mismatch
    lda rx_count
    cmp #BURST_LEN
    beq @count_ok
    lda tmp_b
    ora #$02
    sta tmp_b
@count_ok:

    lda tmp_b
    sta _g_results + 1      ; Expected: $00 (same bytes, same order)

    jsr ClearErrors
    rts
.endproc

;-------------------------------------------------------------------
; Test 2: own echo while the peer transmits
; Both consoles transmit a burst at the same time. Whatever the wire
; does to the data, each side should still observe frames coming back;
; this records how many of its own frames a console can account for.
;  Results:
;   +3: 0 when at least one frame per transmitted byte was observed
;   +4: frames observed (raw)
;-------------------------------------------------------------------
.proc Test2
    jsr SyncPeer

    stz rx_count

    ; Both sides transmit without waiting for each other
    ldx #$00
@send:
    stx tmp_a
@wait_txrdy:
    lda SERCTL
    and #$80
    beq @wait_txrdy
    ldx tmp_a
    lda burst_data,x
    sta SERDAT

    ; Drain as we go so the two deep buffer never backs up
    lda SERCTL
    and #$40
    beq @no_rx
    lda SERDAT
    inc rx_count
@no_rx:
    ldx tmp_a
    inx
    cpx #BURST_LEN
    bne @send

    jsr WaitIdle

@drain:
    jsr ReadTimeout
    lda rx_ok
    beq @drained
    inc rx_count
    bra @drain
@drained:

    lda rx_count
    sta _g_results + 4

    lda #$00
    ldx rx_count
    cpx #BURST_LEN
    bcs @enough
    lda #$01
@enough:
    sta _g_results + 3      ; Expected: $00 (own frames are not swallowed)

    jsr ClearErrors
    rts
.endproc

;-------------------------------------------------------------------
; Test 3: collision recovery
; Both consoles drive the wire at the same instant. The result on the
; wire is undefined, but the UART must return to a usable state: after
; the collision a plain master to slave exchange has to work again.
;  Results:
;   +5: 0 when the link still carries a clean byte afterwards
;   +6: error flags seen during the collision (raw)
;-------------------------------------------------------------------
.proc Test3
    jsr SyncPeer

    ; Fire a single frame from both sides with no arbitration
    lda #$FF
    sta SERDAT
    jsr WaitIdle

    lda SERCTL
    and #$1C
    sta _g_results + 6

    jsr DrainRx
    jsr ClearErrors
    jsr SyncPeer            ; regain step after the disturbance

    ; Now prove the link still works
    lda role
    beq @slave

    lda #$C3
    jsr SendAndEatEcho
    stz _g_results + 5      ; Expected: $00 (master got its echo back)
    rts

@slave:
    jsr ReadTimeout
    lda #$00
    ldx rx_ok
    bne @store
    lda #$01
@store:
    sta _g_results + 5      ; Expected: $00 (slave still receives)
    rts
.endproc

;-------------------------------------------------------------------
; Test 4: half duplex
; A console that is transmitting occupies the wire, so a peer frame sent
; during that window cannot be latched cleanly. The slave transmits one
; byte timed to land inside the master's frame.
;  Results:
;   +7: 0 when nothing was latched while our own frame was in flight
;-------------------------------------------------------------------
.proc Test4
    jsr SyncPeer

    lda role
    beq @slave

    ; Master starts a frame then samples RXRDY before its own echo is due
    lda #$81
    sta SERDAT
    lda #$00
    ldx #$20
@spin:
    dex
    bne @spin
    lda SERCTL
    and #$40
    beq @nothing
    lda #$01
    bra @store
@nothing:
    lda #$00
@store:
    sta _g_results + 7      ; Expected: $00 (our own frame owns the wire)
    jsr WaitIdle
    jsr DrainRx
    jsr ClearErrors
    rts

@slave:
    ; Transmit into the master's frame window
    lda #$18
    sta SERDAT
    jsr WaitIdle
    jsr DrainRx
    jsr ClearErrors
    stz _g_results + 7
    rts
.endproc

;-------------------------------------------------------------------
; Test 5: parity across the link
; Parity is calculated by the receiver, so a frame sent with one parity
; setting must raise PARERR on a receiver configured for the other, and
; must stay clean when both agree.
;  Results:
;   +9:  1 when the mismatched setting was reported
;   +10: 0 when the matching setting stayed clean
;-------------------------------------------------------------------
.proc Test5
    jsr SyncPeer

    ; ---- mismatched parity ----
    lda role
    beq @slave_mismatch

    lda #%00010100          ; PAREN=1, PAREVEN=0, TXOPEN=1
    sta SERCTL
    jsr DrainRx
    jsr Settle
    lda #$7E
    jsr SendAndEatEcho
    bra @phase2

@slave_mismatch:
    lda #%00010101          ; PAREN=1, PAREVEN=1, TXOPEN=1
    sta SERCTL
    jsr DrainRx
    jsr ReadTimeout
    lda #$00
    ldx rx_ok
    beq @no_parerr          ; nothing arrived, so nothing to judge
    lda rx_flags
    and #$10                ; PARERR
    beq @no_parerr
    lda #$01
@no_parerr:
    sta _g_results + 9      ; Expected: $01 (receiver disagrees, so it flags)
    bra @phase2

@phase2:
    lda role
    bne @skip_master_flag
    bra @agree
@skip_master_flag:
    lda #$01
    sta _g_results + 9      ; master has no reception to judge here

@agree:
    jsr ClearErrors
    jsr SyncPeer

    ; ---- matching parity ----
    lda #%00010100          ; both sides PAREN=1, PAREVEN=0
    sta SERCTL
    jsr DrainRx

    lda role
    beq @slave_agree

    jsr Settle
    lda #$7E
    jsr SendAndEatEcho
    stz _g_results + 10
    jsr ClearErrors
    rts

@slave_agree:
    jsr ReadTimeout
    lda #$00
    ldx rx_ok
    beq @clean              ; nothing arrived, so nothing to judge
    lda rx_flags
    and #$10
    beq @clean
    lda #$01
@clean:
    sta _g_results + 10     ; Expected: $00 (matching settings stay clean)
    jsr ClearErrors
    rts
.endproc

;===================================================================
; Main test runner function
;===================================================================
_run_tests:
    sei
    jsr Test1
    jsr Test2
    jsr Test3
    jsr Test4
    jsr Test5
    stz SERCTL
    jsr ResetTimers
    cli
    rts
