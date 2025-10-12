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
; Reset both Channel 0 and Channel 1 to a known state
;===================================================================
.proc ResetChannels
    ; Reset Channel 0 registers
    stz AUD0VOL
    stz AUD0FEED
    stz AUD0OUT
    stz AUD0SHIFT
    stz AUD0BKUP
    stz AUD0CTLA
    stz AUD0CNT
    stz AUD0CTLB

    ; Reset Channel 1 registers
    stz AUD1VOL
    stz AUD1FEED
    stz AUD1OUT
    stz AUD1SHIFT
    stz AUD1BKUP
    stz AUD1CTLA
    stz AUD1CNT
    stz AUD1CTLB

    rts
.endproc

;===================================================================
; Test 1: CTLB Read/Write
; Verify AUD0 CTLB initial state, DONE flag and counter decrement.
; Results at _g_results + 0..2.
;===================================================================
.proc Test1
    jsr ResetChannels

    ; Read initial CTLB value (should be $00)
    ldx #$01
    lda AUD0CTLB
    cmp #$00
    bne @fail

    lda #$40
    sta AUD0CNT           ; Set counter to non-zero

    ; Write timer done and borrow in (this will clock the timer)
    lda #$0A
    sta AUD0CTLB
    lda AUD0CTLB
    sta _g_results + 0    ; #2 Expected: $08

    lda AUD0CNT
    sta _g_results + 1    ; #2 Expected: $3F (counter decremented)

    ; Clear register and verify
    lda #$00
    sta AUD0CTLB
    lda AUD0CTLB
    sta _g_results + 2    ; #3 Expected: $00

    jmp @end

@fail:
    txa
    sta _g_results + 0    ; CTLB not zero at start

@end:
    rts
.endproc

;===================================================================
; Test 2: One-shot countdown on CH0
; Wait for DONE, record CTLB,CNT,OUT.
; Results at _g_results + 3..5.
;===================================================================
.proc Test2
    jsr ResetChannels

    lda #$7F
    sta AUD0VOL

    lda #$00
    sta AUD0FEED       ; taps = 0 => parity=0 => data_in=1
    lda #$01
    sta AUD0SHIFT      ; low 8 bits = $01
    lda #$10
    sta AUD0CTLB       ; high nibble = 1 

    ; Set timer to count down from $F0
    lda #$F0
    sta AUD0BKUP    ; Backup/reload value
    sta AUD0CNT     ; Initial counter value

    ; Start one-shot timer (clock divider = 6)
    lda #(ENABLE_COUNT | 6)
    sta AUD0CTLA

@wait_done:
    ; Poll for DONE bit (bit 3) in CTLB
    lda AUD0CTLB
    and #$08
    beq @wait_done

    sta _g_results + 3    ; #1 Expected: $08 (DONE bit set)

    lda AUD0CNT
    sta _g_results + 4    ; #2 Expected: $00 (counter should be zero)

    lda AUD0OUT
    sta _g_results + 5    ; #3 Expected: $00

    rts
.endproc

;===================================================================
; Test 3: CH0 reload+integrate LFSR run
; Capture first 3 AUD0OUTs and final LFSR state.
; Results at _g_results + 6..10.
;===================================================================
.proc Test3
.segment "ZEROPAGE"
    t3_base_ctla: .res 1
    t3_iter:      .res 1

.segment "CODE"
    jsr ResetChannels

    lda #$FF
    sta AUD0VOL

    ; - Taps = $00
    ; - LFSR = 0x101
    lda #$00
    sta AUD0FEED
    lda #$01
    sta AUD0SHIFT
    lda #$10
    sta AUD0CTLB

    lda #$F0
    sta AUD0BKUP
    sta AUD0CNT

    lda #(ENABLE_COUNT | ENABLE_RELOAD | ENABLE_INTEGRATE | 6)
    sta t3_base_ctla
    sta AUD0CTLA

    lda #$00
    sta t3_iter

@wait_done:
    lda AUD0CTLB
    and #$08
    beq @wait_done

    lda AUD0OUT
    ldx t3_iter
    sta _g_results + 6,x ; Expected: $FF, $FE, $FD

    ; Clean Timer DONE flag using CTLA (level-triggered)
    ; It can also be cleared by writing $00 to CTLB
    lda t3_base_ctla
    ora #$40
    sta AUD0CTLA          ; Reset Timer DONE
    lda t3_base_ctla
    sta AUD0CTLA          ; restore CTLA

    inc t3_iter
    lda t3_iter
    cmp #3
    bcc @wait_done

    lda AUD0SHIFT
    sta _g_results + 9   ; Expected: $0F

    lda AUD0CTLB
    and #$F0
    sta _g_results + 10   ; Expected: $80

    rts
.endproc

;===================================================================
; Test 4: CH0 maximal-length taps with non-trivial seed
; Run borrows, ensure no short period.
; Results at _g_results + 11..13 (3 bytes max):
;===================================================================
.proc Test4
.segment "ZEROPAGE"
    t4_base_ctla: .res 1
    t4_iter:      .res 1
    t4_seed_lo:   .res 1
    t4_seed_hi:   .res 1
    t4_outlast:   .res 1
.segment "CODE"
    jsr ResetChannels

    lda #$7F
    sta AUD0VOL

    ; Mask = %1001_0101 = $95
    lda #$95
    sta AUD0FEED

    ; Seed = 0xAB3
    lda #$B3
    sta AUD0SHIFT
    lda #$A0            ; upper nibble = $A
    sta AUD0CTLB

    lda AUD0SHIFT       ; remember initial seed to detect early repeats
    sta t4_seed_lo
    lda AUD0CTLB
    and #$F0
    sta t4_seed_hi

    ;----- generate many borrows quickly
    lda #$04
    sta AUD0BKUP
    sta AUD0CNT

    lda #(ENABLE_COUNT | ENABLE_RELOAD | 6)
    sta t4_base_ctla
    sta AUD0CTLA

    stz t4_iter
@loop_wait_done:
    ; Poll DONE in CTLB
    lda AUD0CTLB
    and #$08
    beq @loop_wait_done

    ; Latch latest OUT
    lda AUD0OUT
    sta t4_outlast

    ; Early period check: compare current LFSR to initial seed
    lda AUD0SHIFT
    cmp t4_seed_lo
    bne @not_repeat
    lda AUD0CTLB
    and #$F0
    cmp t4_seed_hi
    bne @not_repeat

    ; If we hit the seed again too early (short period), flag failure
    lda #$EE
    sta _g_results + 11
    sta _g_results + 12
    sta _g_results + 13
    rts

@not_repeat:
    ; Pulse reset-done via CTLA (level-triggered)
    lda t4_base_ctla
    ora #$40
    sta AUD0CTLA
    lda t4_base_ctla
    sta AUD0CTLA

    ; Repeat for ~48 borrows
    inc t4_iter
    lda t4_iter
    cmp #48
    bcc @loop_wait_done

    ; Capture final 12-bit LFSR and last OUT sample
    lda AUD0SHIFT
    sta _g_results + 11
    lda AUD0CTLB
    and #$F0
    sta _g_results + 12
    lda t4_outlast
    sta _g_results + 13
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
    jsr ResetChannels
    cli                 ; Re-enable interrupts
    rts