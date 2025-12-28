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

;-------------------------------------------------------------------
; UART Test 1: RX Overrun (loopback, no external equipment)
; With 2 consecutive bytes WITHOUT reading: OVRERR should NOT be set.
; With 3 consecutive bytes WITHOUT reading: OVRERR SHOULD be set.
;  Results:
;   +0: (2 bytes) bit0 OVRERR set (unexpected), bit1 RXRDY missing
;   +1: (3 bytes) bit0 OVRERR missing (expected 1), bit1 RXRDY missing
;-------------------------------------------------------------------
.proc Test1
.segment "ZEROPAGE"
    r0:     .res 1
    r1:     .res 1
    tmp:    .res 1

.segment "CODE"

    jsr ResetTimers

    ; Baud rate: 9600
    lda #12
    sta TIM4BKUP
    sta TIM4CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $00)
    sta TIM4CTLA

    lda #%00000100          ; TXOPEN=1
    sta SERCTL
    lda #%00001100          ; RESETERR=1, TXOPEN=1 (clear errors)
    sta SERCTL
    lda #%00000100          ; leave RESETERR=0, TXOPEN=1
    sta SERCTL

    ; Drain any pending RX (just in case)
@drain_rx:
    lda SERCTL
    and #$40                ; RXRDY?
    beq @rx_drained
    lda SERDAT              ; reading clears RXRDY
    bra @drain_rx
@rx_drained:

    jsr WaitIdle

    ; ==============================================================
    ; PHASE A: 2 bytes -> OVRERR should NOT be set (but RXRDY=1 should)
    ; ==============================================================
    stz r1

    lda #$A5                ; A
    sta SERDAT

@wait_txrdy_1a:
    lda SERCTL
    and #$80                ; TXRDY
    beq @wait_txrdy_1a

    lda #$5A                ; B
    sta SERDAT

@wait_txempty_a:
    lda SERCTL
    and #$20                ; TXEMPTY
    beq @wait_txempty_a

    ; Check "2 bytes"
    lda SERCTL
    and #$08                ; OVRERR?
    beq @ovr_ok_two
    lda r1
    ora #$01                ; b0: OVRERR set (unexpected)
    sta r1
@ovr_ok_two:
    lda SERCTL
    and #$40                ; RXRDY?
    bne @rxrdy_ok_two
    lda r1
    ora #$02                ; b1: RXRDY missing
    sta r1
@rxrdy_ok_two:
    lda r1
    sta _g_results + 0      ; Expected: $00 (no errors with 2 bytes)

    ; Drain RX and clear errors before 3-byte case
@drain_rx_two:
    lda SERCTL
    and #$40
    beq @rx_drained_two
    lda SERDAT
    bra @drain_rx_two
@rx_drained_two:
    lda #%00001100          ; RESETERR=1, TXOPEN=1
    sta SERCTL
    lda #%00000100          ; leave RESETERR=0, TXOPEN=1
    sta SERCTL

    jsr WaitIdle

    ; ==============================================================
    ; PHASE B: 3 bytes -> OVRERR SHOULD be set (and RXRDY=1)
    ; ==============================================================
    lda #$A5                ; A
    sta SERDAT

@wait_txrdy_1:
    lda SERCTL
    and #$80                ; TXRDY
    beq @wait_txrdy_1

    lda #$5A                ; B
    sta SERDAT

@wait_txrdy_2:
    lda SERCTL
    and #$80                ; TXRDY
    beq @wait_txrdy_2

    lda #$3C                ; C
    sta SERDAT

@wait_txempty:
    lda SERCTL
    and #$20                ; TXEMPTY
    beq @wait_txempty

    ; ----------------------------
    ; Check 3 bytes
    ; ----------------------------
    stz r0

    lda SERCTL
    and #$08                ; OVRERR?
    bne @ovr_ok
    lda r0
    ora #$01                ; b0: OVRERR missing
    sta r0
@ovr_ok:

    lda SERCTL
    and #$40                ; RXRDY?
    bne @rxrdy_ok
    lda r0
    ora #$02                ; b1: RXRDY missing
    sta r0
@rxrdy_ok:

    lda r0
    sta _g_results + 1      ; Expected: $00 (no errors with 3 bytes, OVRERR should be set)

    ; drain 1 RX byte to leave clean for subsequent tests
    lda SERCTL
    and #$40
    beq @done
    lda SERDAT

@done:
    rts
.endproc

;-------------------------------------------------------------------
; UART Test 2: Parity (PAREN=1 even/odd) and 9th bit with PAREN=0 + PARERR
;  Results:
;   +2: PAREN=1, PAREVEN=1  (even)
;         b0 incorrect PARBIT
;         b1 spurious PARERR
;         b2 incorrect PARBIT
;         b3 spurious PARERR
;   +3: PAREN=1, PAREVEN=0  (odd)  (same as +0)
;   +4: PAREN=0, PAREVEN=0         b0 PARBIT != 0
;   +5: PAREN=0, PAREVEN=1         b0 PARBIT != 1
;   +6: PAREN=0, PARERR summary    b0 PARERR with PAREVEN=0
;                                  b1 PARERR with PAREVEN=1
;-------------------------------------------------------------------
.proc Test2
.segment "ZEROPAGE"
    r_even:   .res 1
    r_odd:    .res 1
    r_9b0:    .res 1
    r_9b1:    .res 1
    r_9err:   .res 1
    tmp:      .res 1

.segment "RODATA"
    pat_even:  .byte $55       ; 4 ones -> even
    pat_odd:   .byte $01       ; 1 one -> odd

.segment "CODE"

    jsr ResetTimers

    ; 9600 baud
    lda #12
    sta TIM4BKUP
    sta TIM4CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $00)
    sta TIM4CTLA

    lda #%00000100              ; TXOPEN=1
    sta SERCTL
    lda #%00001100              ; RESETERR=1 | TXOPEN=1
    sta SERCTL
    lda #%00000100              ; clear RESETERR, leave TXOPEN=1
    sta SERCTL

    ; Drain RX if there's anything pending
@drain_rx:
    lda SERCTL
    and #$40                    ; RXRDY?
    beq @rx_empty
    lda SERDAT                  ; reading drains RXRDY
    bra @drain_rx
@rx_empty:

    jsr WaitIdle

    ;===============================================================
    ; 1) PAREN=1, PAREVEN=1 (even)
    ;===============================================================
    stz r_even

    ; Configure: parity enabled + even
    lda #%00010101              ; B4=PAREN, B2=TXOPEN, B0=PAREVEN=1
    sta SERCTL
    ; clear errors
    lda #%00011101              ; +RESETERR (B3)
    sta SERCTL
    lda #%00010101
    sta SERCTL

    ; --- Case A: pattern with EVEN #ones (0x55)
    jsr WaitIdle

    lda pat_even
    sta SERDAT

@wait_rx_even_par:
    lda SERCTL
    and #$40                    ; RXRDY?
    beq @wait_rx_even_par

    lda SERCTL
    pha                         ; snapshot with PARBIT/PARERR
    pla
    and #$01                    ; PARBIT
    beq @parbit_ok_e_par
    lda r_even
    ora #$01                    ; b0: incorrect PARBIT for even pattern
    sta r_even
@parbit_ok_e_par:
    lda SERCTL
    and #$10                    ; PARERR?
    beq @parerr_ok_e_par
    lda r_even
    ora #$02                    ; b1: spurious PARERR
    sta r_even
@parerr_ok_e_par:
    lda SERDAT                  ; drain RX

    ; --- Case B: pattern with ODD #ones (0x01)
    jsr WaitIdle

    lda pat_odd
    sta SERDAT

@wait_rx_even_imp:
    lda SERCTL
    and #$40
    beq @wait_rx_even_imp

    lda SERCTL
    pha
    pla
    and #$01
    bne @parbit_ok_e_imp
    lda r_even
    ora #$04                    ; b2: incorrect PARBIT
    sta r_even
@parbit_ok_e_imp:
    lda SERCTL
    and #$10
    beq @parerr_ok_e_imp
    lda r_even
    ora #$08                    ; b3: spurious PARERR
    sta r_even
@parerr_ok_e_imp:
    lda SERDAT

    lda r_even
    sta _g_results + 2

    ;===============================================================
    ; 2) PAREN=1, PAREVEN=0 (odd)
    ;===============================================================
    stz r_odd

    ; Configure: parity enabled + odd
    lda #%00010100              ; B4=PAREN, B2=TXOPEN, B0=0 (odd)
    sta SERCTL
    ; clear errors
    lda #%00011100
    sta SERCTL
    lda #%00010100
    sta SERCTL

    ; --- Case A: EVEN pattern (0x55)
    jsr WaitIdle

    lda pat_even
    sta SERDAT

@wait_rx_odd_par:
    lda SERCTL
    and #$40
    beq @wait_rx_odd_par

    lda SERCTL
    pha
    pla
    and #$01
    bne @parbit_ok_o_par
    lda r_odd
    ora #$01                    ; b0: incorrect PARBIT (even)
    sta r_odd
@parbit_ok_o_par:
    lda SERCTL
    and #$10
    beq @parerr_ok_o_par
    lda r_odd
    ora #$02                    ; b1: spurious PARERR
    sta r_odd
@parerr_ok_o_par:
    lda SERDAT

    ; --- Case B: ODD pattern (0x01)
    jsr WaitIdle

    lda pat_odd
    sta SERDAT

@wait_rx_odd_imp:
    lda SERCTL
    and #$40
    beq @wait_rx_odd_imp

    lda SERCTL
    pha
    pla
    and #$01
    beq @parbit_ok_o_imp
    lda r_odd
    ora #$04                    ; b2: incorrect PARBIT (odd)
    sta r_odd
@parbit_ok_o_imp:
    lda SERCTL
    and #$10
    beq @parerr_ok_o_imp
    lda r_odd
    ora #$08                    ; b3: spurious PARERR
    sta r_odd
@parerr_ok_o_imp:
    lda SERDAT

    ; Store odd result
    lda r_odd
    sta _g_results + 3      ; Expected: $00 (no errors with odd parity)

    ;===============================================================
    ; 3) PAREN=0, 9th bit = PAREVEN, verify PARBIT == PAREVEN
    ;===============================================================

    stz r_9b0
    stz r_9b1
    stz r_9err

    ; --- PAREVEN=0 -> expect PARBIT=0, PARERR=0
    lda #%00000100              ; TXOPEN=1, PAREN=0, PAREVEN=0
    sta SERCTL
    lda #%00001100              ; RESETERR
    sta SERCTL
    lda #%00000100
    sta SERCTL

    jsr WaitIdle

    lda #$A5
    sta SERDAT

@wait_rx_9b0:
    lda SERCTL
    and #$40
    beq @wait_rx_9b0

    ; If PARBIT != 0, also expect PARERR=1
    lda SERCTL
    and #$01                    ; PARBIT
    beq @par9b0_done            ; 0 => match, skip PARERR check

    ; Mismatch: PARBIT != 0
    lda r_9b0
    ora #$01                    ; b0: PARBIT != 0
    sta r_9b0

    ; On mismatch, PARERR should be 1.
    lda SERCTL
    and #$10                    ; PARERR?
    bne @par9b0_done            ; 1 => ok
    lda r_9err
    ora #$01                    ; b0: missing PARERR with PAREVEN=0
    sta r_9err
@par9b0_done:
    lda SERDAT
    lda r_9b0
    sta _g_results + 4      ; Expected: $00 (PARBIT=PAREVEN=0)

    ; --- PAREVEN=1 -> expect PARBIT=1, PARERR=0
    lda #%00000101              ; TXOPEN=1, PAREN=0, PAREVEN=1
    sta SERCTL
    lda #%00001101              ; RESETERR
    sta SERCTL
    lda #%00000101
    sta SERCTL

    jsr WaitIdle

    lda #$5A
    sta SERDAT

@wait_rx_9b1:
    lda SERCTL
    and #$40
    beq @wait_rx_9b1

    ; If PARBIT != 1, also expect PARERR=1
    lda SERCTL
    and #$01
    bne @par9b1_done            ; 1 => match, skip PARERR check

    ; Mismatch: PARBIT != 1
    lda r_9b1
    ora #$01                    ; b0: PARBIT != 1
    sta r_9b1

    ; On mismatch, PARERR should be 1
    lda SERCTL
    and #$10                    ; PARERR?
    bne @par9b1_done            ; 1 => ok
    lda r_9err
    ora #$02                    ; b1: missing PARERR with PAREVEN=1
    sta r_9err
@par9b1_done:
    lda SERDAT
    lda r_9b1
    sta _g_results + 5      ; Expected: $00 (PARBIT=PAREVEN=1)

    ; Store PARERR summary for PAREN=0
    lda r_9err
    sta _g_results + 6      ; Expected: $00 (no PARERR errors in 9-bit mode)

    rts
.endproc

;-------------------------------------------------------------------
; UART Test 3: Changes to PAREN/PAREVEN apply to the NEXT frame
;      changes during BREAK (TXBRK=1) apply after releasing it
; Results:
;   +7:  Change between frames: PAREVEN 1->0 (PAREN=1 always)
;         b0 incorrect PARBIT 1st byte (even)
;         b1 spurious PARERR 1st byte
;         b2 incorrect PARBIT 2nd byte (odd)
;         b3 spurious PARERR 2nd byte
;   +8:  Change between frames: PAREN 1->0 (2nd uses 9th bit=PAREVEN)
;         b0 incorrect PARBIT 1st (even)
;         b1 spurious PARERR 1st
;         b2 PARBIT!=PAREVEN in 2nd (PAREN=0)
;         b3 PARERR in 2nd
;   +9:  Change under BREAK: PAREVEN 1->0 with TXBRK=1 (on release)
;         b0 incorrect PARBIT in 1st frame after release
;         b1 spurious PARERR
;         b2 RXRDY==1 before releasing break (shouldn't)
;   +10: Change under BREAK: PAREN 1->0 with TXBRK=1 (on release)
;         b0 PARBIT!=PAREVEN (with PAREN=0)
;         b1 spurious PARERR
;         b2 RXRDY==1 before releasing break
;-------------------------------------------------------------------
.proc Test3
.segment "ZEROPAGE"
    r0:     .res 1
    r1:     .res 1
    r2:     .res 1
    r3:     .res 1
    tmp:    .res 1

.segment "RODATA"
    pat:    .byte $01          ; 1 bit at '1' (odd) — easy to verify

.segment "CODE"

    ; 9600 baud
    jsr ResetTimers
    lda #12
    sta TIM4BKUP
    sta TIM4CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $00)
    sta TIM4CTLA

    lda #%00000100              ; TXOPEN=1
    sta SERCTL
    lda #%00001100              ; RESETERR=1
    sta SERCTL
    lda #%00000100              ; clear RESETERR
    sta SERCTL

    ; Drain RX if there's anything pending
@drain_rx:
    lda SERCTL
    and #$40
    beq @rx_empty
    lda SERDAT
    bra @drain_rx
@rx_empty:

    jsr WaitIdle

    ;===============================================================
    ; (A) CHANGE BETWEEN FRAMES: PAREVEN 1->0 (PAREN=1)
    ;     1st byte in even, 2nd byte in odd
    ;===============================================================
    stz r0

    ; Configure even: PAREN=1, PAREVEN=1
    lda #%00010101              ; B4=PAREN, B2=TXOPEN, B0=PAREVEN
    sta SERCTL
    lda #%00011101              ; RESETERR
    sta SERCTL
    lda #%00010101
    sta SERCTL

    ; --- 1st byte (even): pat = $01 => expected PARBIT = 1, PARERR=0
    jsr WaitIdle

    lda pat
    sta SERDAT

@wait_rx_even1:
    lda SERCTL
    and #$40
    beq @wait_rx_even1

    lda SERCTL
    pha
    pla
    and #$01                    ; PARBIT
    bne :+
    lda r0
    ora #$01                    ; b0: incorrect PARBIT (even)
    sta r0
:
    lda SERCTL
    and #$10                    ; PARERR
    beq :+
    lda r0
    ora #$02                    ; b1: spurious PARERR (even)
    sta r0
:
    lda SERDAT                  ; drain RX

    ; Change to odd: PAREVEN=0 (PAREN=1)
    lda #%00010100
    sta SERCTL
    lda #%00011100              ; +RESETERR
    sta SERCTL
    lda #%00010100
    sta SERCTL

    ; --- 2nd byte (odd): pat = $01 => expected PARBIT = 0, PARERR=0
    jsr WaitIdle

    lda pat
    sta SERDAT

@wait_rx_odd2:
    lda SERCTL
    and #$40
    beq @wait_rx_odd2

    lda SERCTL
    pha
    pla
    and #$01
    beq :+
    lda r0
    ora #$04                    ; b2: incorrect PARBIT (odd)
    sta r0
:
    lda SERCTL
    and #$10
    beq :+
    lda r0
    ora #$08                    ; b3: spurious PARERR (odd)
    sta r0
:
    lda SERDAT

    lda r0
    sta _g_results + 7      ; Expected: $00 (PAREVEN change applied correctly)

    ;===============================================================
    ; (B) CHANGE BETWEEN FRAMES: PAREN 1->0 (2nd uses 9th bit = PAREVEN)
    ;     1st byte even; 2nd byte with PAREN=0 and PAREVEN=0
    ;===============================================================
    stz r1

    ; 1st: even (PAREN=1, PAREVEN=1)
    lda #%00010101
    sta SERCTL
    lda #%00011101
    sta SERCTL
    lda #%00010101
    sta SERCTL

    jsr WaitIdle

    lda pat
    sta SERDAT

@wait_rx_evenB1:
    lda SERCTL
    and #$40
    beq @wait_rx_evenB1

    lda SERCTL
    pha
    pla
    and #$01                    ; expected 1
    bne :+
    lda r1
    ora #$01                    ; b0: incorrect PARBIT (even)
    sta r1
:
    lda SERCTL
    and #$10
    beq :+
    lda r1
    ora #$02                    ; b1: spurious PARERR (even)
    sta r1
:
    lda SERDAT

    ; 2nd: disable parity (PAREN=0) and set PAREVEN=0
    lda #%00000100              ; TXOPEN=1, PAREN=0, PAREVEN=0
    sta SERCTL
    lda #%00001100              ; +RESETERR
    sta SERCTL
    lda #%00000100
    sta SERCTL

    jsr WaitIdle

    lda #$A5                    ; arbitrary data
    sta SERDAT

@wait_rx_noPar2:
    lda SERCTL
    and #$40
    beq @wait_rx_noPar2

    ; Expected: PARBIT == PAREVEN(0)
    lda SERCTL
    and #$01
    beq @parbit_match_B        ; 0 => match, don't check PARERR

    ; Mismatch: PARBIT != 0
    lda r1
    ora #$04                    ; b2: PARBIT != PAREVEN
    sta r1

    ; On mismatch, PARERR should be 1
    lda SERCTL
    and #$10                    ; PARERR?
    bne @parerr_ok_B            ; 1 => ok
    lda r1
    ora #$08                    ; b3: missing PARERR on mismatch
    sta r1
@parerr_ok_B:
@parbit_match_B:
    lda SERDAT

    lda r1
    sta _g_results + 8      ; Expected: $00 (PAREN change applied correctly)

    ;===============================================================
    ; (C) CHANGE UNDER BREAK: PAREVEN 1->0 with TXBRK=1 (applies on release)
    ;===============================================================
    stz r2

    ; Part 1: ensure idle and then enter BREAK; write held byte
    jsr WaitIdle                ; ensure previous idle

    lda #%00010110              ; PAREN=1, PAREVEN=1, TXOPEN=1, TXBRK=1
    sta SERCTL
    lda #%00011110              ; +RESETERR
    sta SERCTL
    lda #%00010110
    sta SERCTL

    lda #$5A
    sta SERDAT                  ; held by BRK

    ; Change to odd while still in BRK
    lda #%00010110              ; (ensure TXBRK=1)
    and #%11111110              ; B0=0 -> PAREVEN=0 (odd)
    sta SERCTL

    ; Verify there's NO RXRDY before releasing break
    lda SERCTL
    and #$40
    beq :+
    lda r2
    ora #$04                    ; b2: RXRDY active during break
    sta r2
:

    ; Release break: the frame that goes out should use ODD
    lda #%00010100              ; PAREN=1, PAREVEN=0, TXOPEN=1, BRK=0
    sta SERCTL

@wait_rx_breakOdd:
    lda SERCTL
    and #$40
    beq @wait_rx_breakOdd

    ; In ODD and data 0x5A (4 ones -> even), expected PARBIT = 1
    lda SERCTL
    and #$01
    bne @parbit_ok_c            ; 1 => ok
    lda r2
    ora #$01                    ; b0: incorrect PARBIT after break
    sta r2
@parbit_ok_c:

    lda SERCTL
    and #$10
    beq :+
    lda r2
    ora #$02                    ; b1: spurious PARERR
    sta r2
:
    lda SERDAT

    lda r2
    sta _g_results + 9      ; Expected: $00 (PAREVEN change under break applied correctly)

    ;===============================================================
    ; (D) CHANGE UNDER BREAK: PAREN 1->0 (9th=PAREVEN) with TXBRK=1
    ;===============================================================
    stz r3

    ; Ensure idle and enter BREAK with PAREN=1 even; held data
    jsr WaitIdle

    lda #%00010110              ; even + BRK
    sta SERCTL
    lda #%00011110
    sta SERCTL
    lda #%00010110
    sta SERCTL

    lda #$A5
    sta SERDAT                  ; held

    ; Change to PAREN=0 with PAREVEN=1 while BRK=1
    lda #%00000111              ; TXOPEN=1, PAREN=0, PAREVEN=1, BRK=1
    sta SERCTL
    lda #%00001111              ; +RESETERR
    sta SERCTL
    lda #%00000111
    sta SERCTL

    ; Verify there's NO RXRDY before releasing
    lda SERCTL
    and #$40
    beq :+
    lda r3
    ora #$04                    ; b2: RXRDY during break
    sta r3
:

    ; Release break: the frame should use 9th=PAREVEN=1
    lda #%00000101              ; TXOPEN=1, PAREN=0, PAREVEN=1, BRK=0
    sta SERCTL

@wait_rx_breakNoPar:
    lda SERCTL
    and #$40
    beq @wait_rx_breakNoPar

    ; Expected: PAREN=0, PAREVEN=1 => PARBIT=1
    lda SERCTL
    and #$01
    bne @parbit_match_D         ; 1 => match, don't check PARERR
    lda r3
    ora #$01                    ; b0: PARBIT != 1
    sta r3

    ; On mismatch, PARERR should be 1
    lda SERCTL
    and #$10                    ; PARERR?
    bne @parerr_ok_D            ; 1 => ok
    lda r3
    ora #$02                    ; b1: missing PARERR on mismatch
    sta r3
@parerr_ok_D:
@parbit_match_D:
    lda SERDAT

    lda r3
    sta _g_results + 10     ; Expected: $00 (PAREN change under break applied correctly)

    rts
.endproc

;-------------------------------------------------------------------
; UART Test 4: SERDAT with holding full (3rd write with holding occupied)
; Results:
;   +11: 
;        b0: 1st RX byte != A
;        b1: 2nd RX byte != C
;        b2: a 3rd RX byte arrived
;        b3: after draining, RXRDY != 0
;        b4: at end TXEMPTY != 1
;        b5: at end TXRDY  != 1
;-------------------------------------------------------------------
.proc Test4
.segment "ZEROPAGE"
    r:      .res 1
    rx1:    .res 1
    rx2:    .res 1
    tmp:    .res 1

.segment "CODE"

    jsr ResetTimers

    ; 9600 baud
    lda #12
    sta TIM4BKUP
    sta TIM4CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $00)
    sta TIM4CTLA

    lda #%00000100              ; TXOPEN=1, PAREN=0, PAREVEN=0, BRK=0
    sta SERCTL
    lda #%00001100              ; RESETERR=1 to clear previous flags
    sta SERCTL
    lda #%00000100              ; clear RESETERR
    sta SERCTL

    ; Drain any pending RX
@drain_rx:
    lda SERCTL
    and #$40                    ; RXRDY?
    beq @rx_empty
    lda SERDAT                  ; reading drains RXRDY
    bra @drain_rx
@rx_empty:

    jsr WaitIdle

    ;---------------------------------------------------------------
    ; Write three consecutive bytes, ensuring the 2nd is written
    ; while TX is busy (holding fills), and the 3rd overwrites it
    ;---------------------------------------------------------------
    stz r

    lda #$11                    ; A
    sta SERDAT

    ; Ensure A has moved to shifter: wait for TXRDY cycle 1->0->1
@wait_txrdy_fall:
    lda SERCTL
    and #$80                    ; TXRDY
    beq @saw_fall               ; 0 => detected fall
    bra @wait_txrdy_fall
@saw_fall:
@wait_txrdy_rise:
    lda SERCTL
    and #$80                    ; TXRDY
    bne @txrdy_cycle_ok         ; 1 => rose again (holding free)
    bra @wait_txrdy_rise
@txrdy_cycle_ok:

    lda #$22                    ; B (enters holding with TX busy)
    sta SERDAT

    ; Third write with holding already occupied (should overwrite holding)
    lda #$33                    ; C
    sta SERDAT

    ; Wait for all TX to finish and drain RX completely (up to 3 bytes)
    jsr WaitIdle

    stz rx1
    stz rx2

@drain_all:
    lda SERCTL
    and #$40
    beq @done_drain

    lda SERDAT
    sta tmp

    lda rx1
    bne @check_second
    lda tmp
    sta rx1
    bra @drain_all

@check_second:
    lda rx2
    bne @mark_extra
    lda tmp
    sta rx2
    bra @drain_all

@mark_extra:
    ; A 3rd RX byte arrived (not expected)
    lda r
    ora #$04
    sta r
    bra @drain_all

@done_drain:

    ; Data comparisons
    lda rx1
    cmp #$11
    beq @ok_rx1
    lda r
    ora #$01                    ; b0
    sta r
@ok_rx1:
    lda rx2
    cmp #$33
    beq @ok_rx2
    lda r
    ora #$02                    ; b1
    sta r
@ok_rx2:

    ; After draining, RXRDY should be 0
    lda SERCTL
    and #$40
    beq @rx_empty_ok
    lda r
    ora #$08                    ; b3
    sta r
@rx_empty_ok:

    ; At end, TXEMPTY=1 (b4 if not), TXRDY=1
    lda SERCTL
    and #$20
    bne @txempty_ok
    lda r
    ora #$10                    ; b4
    sta r
@txempty_ok:
    lda SERCTL
    and #$80
    bne @txrdy_ok
    lda r
    ora #$20                    ; b5
    sta r
@txrdy_ok:

    lda r
    sta _g_results + 11     ; Expected: $00 (holding register behavior correct)

    rts
.endproc

;-------------------------------------------------------------------
; UART Test 5: Pending only cleared by INTRST
;   - Results:
;       +12:
;         b0: pending did NOT arm at start (expected 1)
;         b1: pending cleared after starting TX (unexpected)
;         b2: pending cleared after end TX / read SERDAT (unexpected)
;         b3: INTRST did NOT clear pending (unexpected)
;-------------------------------------------------------------------
.proc Test5
.segment "ZEROPAGE"
    r:      .res 1
    tmp:    .res 1

.segment "CODE"

    ; Known state: timers, 9600 baud, UART open
    jsr ResetTimers
    lda #12
    sta TIM4BKUP
    sta TIM4CNT
    lda #(ENABLE_RELOAD | ENABLE_COUNT | $00)
    sta TIM4CTLA

    ; UART: TXOPEN=1, clear errors
    lda #%00000100              ; TXOPEN=1
    sta SERCTL
    lda #%00001100              ; +RESETERR
    sta SERCTL
    lda #%00000100
    sta SERCTL

    ; Drain RX
@drain_rx:
    lda SERCTL
    and #$40
    beq @rx_empty
    lda SERDAT
    bra @drain_rx
@rx_empty:

    stz r

    ; Ensure idle
    jsr WaitIdle

    ; Clear INT4 pending just in case
    lda #$10                    ; INT4 mask
    sta INTRST

    ; Enable TXINTEN=1 keeping TXRDY=1 to arm pending
    lda #%10000100              ; TXINTEN=1, TXOPEN=1 (rest 0)
    sta SERCTL

    ; Level + latched: after INTRST, with TXRDY=1 should relatch immediately
    lda #$10                    ; INT4 mask
    sta INTRST

    ; b0: pending should be active now (relatch)
    lda INTSET
    and #$10
    bne @pending_ok0
    lda r
    ora #$01                    ; b0: pending did not arm
    sta r
@pending_ok0:

    ; Start TX (TXRDY falls) — pending should NOT clear
    lda #$A5
    sta SERDAT

    lda INTSET
    and #$10
    bne @pending_ok1
    lda r
    ora #$02                    ; b1: pending cleared on starting TX
    sta r
@pending_ok1:

    ; Wait for end of TX and drain RX
    jsr WaitIdle
@drain_rx2:
    lda SERCTL
    and #$40
    beq @rx_empty2
    lda SERDAT
    bra @drain_rx2
@rx_empty2:

    ; b2: pending should NOT clear due to end TX or reading SERDAT
    lda INTSET
    and #$10
    bne @pending_ok2
    lda r
    ora #$04                    ; b2: pending cleared by internal event
    sta r
@pending_ok2:

    ; Demonstrate that ONLY INTRST clears pending: do it with TXRDY=0
    ; Force TXRDY=0 with a new send
    lda #$5A
    sta SERDAT

    ; Clear pending
    lda #$10
    sta INTRST

    ; b3: pending should be 0 now
    lda INTSET
    and #$10
    beq @pending_cleared
    lda r
    ora #$08                    ; b3: INTRST did not clear pending
    sta r
@pending_cleared:

    ; Leave UART idle and RX drained
    jsr WaitIdle
@drain_rx3:
    lda SERCTL
    and #$40
    beq @done
    lda SERDAT
    bra @drain_rx3
@done:
    lda r
    sta _g_results + 12     ; Expected: $00 (interrupt pending cleared only by INTRST)
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
    stz SERCTL          ; Disable UART
    jsr ResetTimers
    cli                 ; Re-enable interrupts
    rts
