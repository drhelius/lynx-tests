.setcpu "65C02"

.include "lynx.inc"

.export _run_tests
.export _g_results

;-------------------------------------------------------------------
.segment "BSS"
    _g_results: .res 6
    saved_mapctl: .res 1        ; Save MAPCTL here
    prev_vcount: .res 1         ; Previous vcount for comparison

;-------------------------------------------------------------------
.segment "CODE"

;===================================================================
; Wait for vertical blank
;===================================================================
.proc WaitVBlank
    ; 1) If already at 0, wait until it reloads
@wait_not0:
    lda TIM2CNT
    beq @wait_not0      ; if at 0, wait until it reloads

    ; 2) Wait for counter to reach 0 (counts down)
@wait_0:
    lda TIM2CNT
    bne @wait_0         ; wait until it reaches 0

    ; 3) Wait for reload (0 -> non-zero = actual VBlank start)
@wait_reload:
    lda TIM2CNT
    beq @wait_reload    ; wait until it reloads to high value
    rts
.endproc

;===================================================================
; Trigger pulse on TXD pin for logic analyzer capture
;===================================================================
.proc TriggerPulse
    lda #%00000110        ; TXOPEN=1 + TXBRK=1 -> TXD goes low
    sta SERCTL

    lda #%00000100        ; TXOPEN=1, TXBRK=0 -> TXD goes high
    sta SERCTL
    rts
.endproc

;===================================================================
; Prepare Timer 6 registers
;===================================================================
.proc PrepareTimer6
    stz TIM6CTLA        ; Disable timer 6
    stz TIM6CTLB        ; Clear control/status register
    lda #$FF
    sta TIM6BKUP        ; Set backup value to 255
    sta TIM6CNT         ; Set counter to 255
    rts
.endproc

;===================================================================
; Test 1: NOP with Page Mode Enabled
;===================================================================
.proc Test1_NOP_PageOn
    ; Setup: prepare timer
    jsr PrepareTimer6
    
    ; Save current MAPCTL and set page mode ON
    lda MAPCTL
    sta saved_mapctl
    and #$7F                    ; Clear bit 7 = page mode ON
    sta MAPCTL

    ; START TIMER (inline, immediately before test)
    lda #ENABLE_COUNT
    sta TIM6CTLA

    ; === TEST INSTRUCTIONS ===
    .repeat 200
        .byte $03       ; 1-byte NOP
    .endrepeat
    ; === END TEST ===

    ; STOP TIMER (inline, immediately after test)
    stz TIM6CTLA

    ; Restore saved MAPCTL
    lda saved_mapctl
    sta MAPCTL

    ; Calculate elapsed ticks: 255 - count
    sec
    lda #$FF
    sbc TIM6CNT
    sta _g_results + 0

    rts
.endproc

;===================================================================
; Test 2: NOP with Page Mode Disabled
;===================================================================
.proc Test2_NOP_PageOff
    ; Setup: prepare timer
    jsr PrepareTimer6
    
    ; Save current MAPCTL and set page mode OFF
    lda MAPCTL
    sta saved_mapctl
    ora #$80                    ; Set bit 7 = page mode OFF
    sta MAPCTL

    ; START TIMER (inline, immediately before test)
    lda #ENABLE_COUNT
    sta TIM6CTLA

    ; === TEST INSTRUCTIONS ===
    .repeat 200
        .byte $03       ; 1-byte NOP
    .endrepeat
    ; === END TEST ===

    ; STOP TIMER (inline, immediately after test)
    stz TIM6CTLA

    ; Restore saved MAPCTL
    lda saved_mapctl
    sta MAPCTL

    ; Calculate elapsed ticks: 255 - count
    sec
    lda #$FF
    sbc TIM6CNT
    sta _g_results + 1

    rts
.endproc

;===================================================================
; Test 3: LDX with Page Mode Enabled
;===================================================================
.proc Test3_LDX_PageOn
    ; Setup: prepare timer
    jsr PrepareTimer6
    
    ; Save current MAPCTL and set page mode ON
    lda MAPCTL
    sta saved_mapctl
    and #$7F                    ; Clear bit 7 = page mode ON
    sta MAPCTL

    ; START TIMER (inline, immediately before test)
    lda #ENABLE_COUNT
    sta TIM6CTLA

    ; === TEST INSTRUCTIONS ===
    .repeat 200
        ldx #$AA
    .endrepeat
    ; === END TEST ===

    ; STOP TIMER (inline, immediately after test)
    stz TIM6CTLA

    ; Restore saved MAPCTL
    lda saved_mapctl
    sta MAPCTL

    ; Calculate elapsed ticks: 255 - count
    sec
    lda #$FF
    sbc TIM6CNT
    sta _g_results + 2

    rts
.endproc

;===================================================================
; Test 4: LDX with Page Mode Disabled
;===================================================================
.proc Test4_LDX_PageOff
    ; Setup: prepare timer
    jsr PrepareTimer6
    
    ; Save current MAPCTL and set page mode OFF
    lda MAPCTL
    sta saved_mapctl
    ora #$80                    ; Set bit 7 = page mode OFF
    sta MAPCTL

    ; START TIMER (inline, immediately before test)
    lda #ENABLE_COUNT
    sta TIM6CTLA

    ; === TEST INSTRUCTIONS ===
    .repeat 200
        ldx #$EE
    .endrepeat
    ; === END TEST ===

    ; STOP TIMER (inline, immediately after test)
    stz TIM6CTLA

    ; Restore saved MAPCTL
    lda saved_mapctl
    sta MAPCTL

    ; Calculate elapsed ticks: 255 - count
    sec
    lda #$FF
    sbc TIM6CNT
    sta _g_results + 3

    rts
.endproc

;===================================================================
; Test 5: Memory Read with Page Mode Enabled
;===================================================================
.proc Test5_MEM_PageOn
    ; Setup: prepare timer
    jsr PrepareTimer6
    
    ; Save current MAPCTL and set page mode ON
    lda MAPCTL
    sta saved_mapctl
    and #$7F                    ; Clear bit 7 = page mode ON
    sta MAPCTL

    ; START TIMER (inline, immediately before test)
    lda #ENABLE_COUNT
    sta TIM6CTLA

    ; === TEST INSTRUCTIONS ===
    .repeat 100
        lda $2ACC
    .endrepeat
    ; === END TEST ===

    ; STOP TIMER (inline, immediately after test)
    stz TIM6CTLA

    ; Restore saved MAPCTL
    lda saved_mapctl
    sta MAPCTL

    ; Calculate elapsed ticks: 255 - count
    sec
    lda #$FF
    sbc TIM6CNT
    sta _g_results + 4

    rts
.endproc

;===================================================================
; Test 6: Memory Read with Page Mode Disabled
;===================================================================
.proc Test6_MEM_PageOff
    ; Setup: prepare timer
    jsr PrepareTimer6
    
    ; Save current MAPCTL and set page mode OFF
    lda MAPCTL
    sta saved_mapctl
    ora #$80                    ; Set bit 7 = page mode OFF
    sta MAPCTL

    ; START TIMER (inline, immediately before test)
    lda #ENABLE_COUNT
    sta TIM6CTLA

    ; === TEST INSTRUCTIONS ===
    .repeat 100
        lda $2ECC
    .endrepeat
    ; === END TEST ===

    ; STOP TIMER (inline, immediately after test)
    stz TIM6CTLA

    ; Restore saved MAPCTL
    lda saved_mapctl
    sta MAPCTL

    ; Calculate elapsed ticks: 255 - count
    sec
    lda #$FF
    sbc TIM6CNT
    sta _g_results + 5

    rts
.endproc

;===================================================================
; Main test runner function
;===================================================================
_run_tests:
    sei                         ; Disable interrupts during testing

    jsr WaitVBlank              ; Sync to vertical blank
    jsr TriggerPulse            ; Trigger pulse for logic analyzer

    jsr Test1_NOP_PageOn        ; NOP with page mode enabled
    jsr Test2_NOP_PageOff       ; NOP with page mode disabled

    jsr WaitVBlank              ; Sync to vertical blank
    jsr TriggerPulse            ; Trigger pulse for logic analyzer

    jsr Test3_LDX_PageOn        ; LDX with page mode enabled
    jsr Test4_LDX_PageOff       ; LDX with page mode disabled

    jsr WaitVBlank              ; Sync to vertical blank
    jsr TriggerPulse            ; Trigger pulse for logic analyzer

    jsr Test5_MEM_PageOn        ; Memory read with page mode enabled
    jsr Test6_MEM_PageOff       ; Memory read with page mode disabled

    cli                         ; Re-enable interrupts
    rts
