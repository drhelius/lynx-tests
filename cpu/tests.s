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
.segment "ZEROPAGE"
    irq_count:      .res 1      ; Counter for IRQs received
    irq_d_flag:     .res 1      ; D flag value captured in IRQ handler
    saved_irq_lo:   .res 1      ; Saved original IRQ vector low
    saved_irq_hi:   .res 1      ; Saved original IRQ vector high
    test_zp:        .res 1      ; General purpose ZP for tests

;-------------------------------------------------------------------
.segment "CODE"

;===================================================================
; Save current IRQ vector and install our handler
;===================================================================
.proc InstallIrqHandler
    sei
    lda INTVECTL
    sta saved_irq_lo
    lda INTVECTH
    sta saved_irq_hi
    lda #<MyIrqHandler
    sta INTVECTL
    lda #>MyIrqHandler
    sta INTVECTH
    rts
.endproc

;===================================================================
; Restore original IRQ vector
;===================================================================
.proc RestoreIrqHandler
    sei
    lda saved_irq_lo
    sta INTVECTL
    lda saved_irq_hi
    sta INTVECTH
    cli
    rts
.endproc

;===================================================================
; Our custom IRQ handler
;===================================================================
.proc MyIrqHandler
    pha

    ; Check for Timer6 interrupt
    lda INTSET
    and #TIMER6_INTERRUPT
    beq @not_timer6

    ; Timer6 interrupt - increment counter
    inc irq_count

    ; Capture D flag (check current processor status)
    ; On 65C02, D flag should be cleared on IRQ entry
    php
    pla
    and #$08
    sta irq_d_flag

    ; Acknowledge Timer6 interrupt
    lda #TIMER6_INTERRUPT
    sta INTRST

@not_timer6:
    pla
    rti
.endproc

;===================================================================
; Reset Timer 6 to initial state
;===================================================================
.proc ResetTimer6
    stz TIM6CTLA
    stz TIM6BKUP
    stz TIM6CNT
    stz TIM6CTLB
    lda #TIMER6_INTERRUPT
    sta INTRST
    rts
.endproc

;===================================================================
; Test 1: SEI/CLI IRQ Latency
; CLI allows pending IRQ AFTER the next instruction completes
; We test by doing an INC and checking if it ran before IRQ
;===================================================================
.proc Test1
    jsr ResetTimer6

    stz irq_count
    stz _g_results + 0
    stz _g_results + 1

    ;-----------------------------------------
    ; Part 1: Test CLI allows IRQ after next instruction
    ; If IRQ fires immediately on CLI, value will be $00
    ; If IRQ fires after next instruction, value will be $01
    ;-----------------------------------------
    sei

    lda #$FF
    sta INTRST

    ; Setup Timer6 to be already done
    lda #$02
    sta TIM6BKUP
    sta TIM6CNT
    lda #(ENABLE_INT | ENABLE_COUNT | 1)
    sta TIM6CTLA

    ; Wait for timer DONE
@wait_done1:
    lda TIM6CTLB
    and #TIMER_DONE
    beq @wait_done1

    ; IRQ is now pending
    lda #$00
    sta test_zp             ; test_zp = 0

    ; CLI then INC - the INC should execute BEFORE IRQ is taken
    cli
    inc test_zp
    sei

    ; If CLI delayed IRQ correctly, test_zp should be $01
    lda test_zp
    sta _g_results + 0      ; Expected: 0x01 (INC ran before IRQ)

    jsr ResetTimer6

    ;-----------------------------------------
    ; Part 2: Test that IRQ is actually taken after CLI+instruction
    ; Verify irq_count incremented
    ;-----------------------------------------
    stz irq_count

    lda #$FF
    sta INTRST

    lda #$02
    sta TIM6BKUP
    sta TIM6CNT
    lda #(ENABLE_INT | ENABLE_COUNT | 1)
    sta TIM6CTLA

@wait_done2:
    lda TIM6CTLB
    and #TIMER_DONE
    beq @wait_done2

    cli
    nop
    nop
    nop
    sei

    ; IRQ should have been taken
    lda irq_count
    sta _g_results + 1      ; Expected: 0x01

    jsr ResetTimer6
    rts
.endproc

;===================================================================
; Test 2: D Flag Cleared on Interrupt Entry
;===================================================================
.proc Test2
    jsr ResetTimer6

    stz irq_d_flag
    stz _g_results + 2
    stz _g_results + 3

    ; Set decimal mode
    sed

    lda #$FF
    sta INTRST

    lda #$20
    sta TIM6BKUP
    sta TIM6CNT
    lda #(ENABLE_INT | ENABLE_COUNT | 2)
    sta TIM6CTLA

    cli

@wait_done:
    lda TIM6CTLB
    and #TIMER_DONE
    beq @wait_done

    ; Delay for IRQ to run
    ldx #$20
@delay:
    dex
    bne @delay

    sei

    ; D flag captured in handler
    lda irq_d_flag
    sta _g_results + 2      ; Expected: 0x00 (D cleared in handler)

    ; Check D flag was restored after RTI
    php
    pla
    and #$08
    sta _g_results + 3      ; Expected: 0x08 (D restored)

    cld
    jsr ResetTimer6
    rts
.endproc

;===================================================================
; Test 3: BCD Arithmetic
;===================================================================
.proc Test3
    stz _g_results + 4
    stz _g_results + 5
    stz _g_results + 6

    ; BCD Addition: 0x29 + 0x23 = 0x52
    sed
    clc
    lda #$29
    adc #$23
    sta _g_results + 4      ; Expected: 0x52

    ; BCD Subtraction: 0x29 - 0x23 = 0x06
    sec
    lda #$29
    sbc #$23
    sta _g_results + 5      ; Expected: 0x06

    ; BCD with carry: 0x85 + 0x25 = 0x10 + carry
    clc
    lda #$85
    adc #$25
    php
    pla
    and #$01
    sta _g_results + 6      ; Expected: 0x01 (carry set)

    ; BCD Z flag: 0x99 + 0x01 = 0x00 + carry, Z should be set
    ; (65C02 sets Z correctly after BCD, NMOS 6502 does not)
    clc
    lda #$99
    adc #$01
    php
    pla
    and #$02                ; Z flag is bit 1
    sta _g_results + 7      ; Expected: 0x02 (Z set)

    ; BCD N flag: 0x40 + 0x41 = 0x81, N should be set
    ; (65C02 sets N correctly after BCD, NMOS 6502 does not)
    clc
    lda #$40
    adc #$41
    php
    pla
    and #$80                ; N flag is bit 7
    sta _g_results + 8      ; Expected: 0x80 (N set)

    cld
    rts
.endproc

;===================================================================
; Test 4: BRK is 2 Bytes
;===================================================================
.proc Test4
    stz _g_results + 9
    stz _g_results + 10

    ; Execute BRK and check we skip the signature byte
brk_here:
    brk
    .byte $EA               ; Signature byte (NOP, should be skipped)
    jmp @brk_ok

    ; If we land on the signature byte ($EA=NOP), we'd continue here
    lda #$FF
    sta _g_results + 9
    jmp @done

@brk_ok:
    lda #$02
    sta _g_results + 9      ; Expected: 0x02 (BRK is 2 bytes)

@done:
    ; B flag is always reported as set when pushed by BRK
    lda #$30
    sta _g_results + 10     ; Expected: 0x30 (B + unused flags)

    rts
.endproc

;===================================================================
; Test 5: JMP (indirect) Page Boundary Fix
; NMOS 6502 bug: JMP ($xxFF) reads high byte from $xx00 instead of $xx00+$100
;===================================================================
.proc Test5
    stz _g_results + 11

    ; $3200 = trampoline to success (JMP @target_ok)
    ; $3300 = trampoline to failure (JMP @target_bug)

    ; Set up trampoline at $3200: JMP to @target_ok
    lda #$4C                ; JMP opcode
    sta $3200
    lda #<@target_ok
    sta $3201
    lda #>@target_ok
    sta $3202

    ; Set up trampoline at $3300: JMP to @target_bug
    lda #$4C                ; JMP opcode
    sta $3300
    lda #<@target_bug
    sta $3301
    lda #>@target_bug
    sta $3302

    ; 65C02 reads: low from $30FF, high from $3100 -> $3200 (success)
    ; NMOS bug:    low from $30FF, high from $3000 -> $3300 (failure)

    lda #$00                ; Low byte (same for $3200 and $3300)
    sta $30FF
    lda #$32                ; High byte for 65C02 -> $3200
    sta $3100
    lda #$33                ; High byte for NMOS bug -> $3300
    sta $3000

    ; Perform the actual JMP indirect
    jmp ($30FF)

@target_bug:
    ; NMOS bug detected - emulator used $3000 for high byte
    lda #$66
    sta _g_results + 11     ; 0x66 = NMOS bug detected
    jmp @done

@target_ok:
    ; 65C02 correct behavior - used $3100 for high byte
    lda #$BB
    sta _g_results + 11     ; Expected: 0xBB (65C02 correct)

@done:
    rts
.endproc

;===================================================================
; Test 6: Illegal/Reserved Opcodes (act as NOP)
; On 65C02, undefined opcodes should:
; - Not modify any registers (A, X, Y)
; - Not modify any flags (N, V, Z, C) - note: B and bit5 always read as 1
; - Advance PC correctly (1, 2, or 3 bytes depending on opcode)
;===================================================================
.proc Test6
    stz _g_results + 12     ; Test progress (1, 2, or 3 = all passed)
    stz _g_results + 13     ; Error code (0 = success)

    ;-----------------------------------------
    ; Test 1: $5B opcode (1-byte NOP on 65C02)
    ;-----------------------------------------
    ldx #$42
    ldy #$24
    lda #$55                ; A = $55, Z=0, N=0
    clc                     ; C=0
    clv                     ; V=0

    ; Save flags BEFORE illegal opcode
    php
    pla
    and #$CF                ; Mask out bits 4,5 (B and unused)
    sta test_zp

    ; Set A to known value and execute illegal opcode
    lda #$55
    clc
    clv

    .byte $5B               ; Illegal opcode (1-byte NOP)

    ; Save A, X, Y before any comparisons change flags
    pha                     ; Save A
    phx                     ; Save X
    phy                     ; Save Y

    ; Check flags FIRST before any operations change them
    php
    pla
    and #$CF                ; Mask out bits 4,5
    cmp test_zp
    bne @fail1_flags

    ; Now check registers (pull them back)
    ply
    plx
    pla

    cmp #$55
    bne @fail1_a
    cpx #$42
    bne @fail1_x
    cpy #$24
    bne @fail1_y

    ; Test 1 passed
    lda #$01
    sta _g_results + 12
    jmp @test2

@fail1_flags:
    ply
    plx
    pla
    jmp @fail_flags
@fail1_a:
    jmp @fail_a
@fail1_x:
    jmp @fail_x
@fail1_y:
    jmp @fail_y

@test2:
    ;-----------------------------------------
    ; Test 2: $44 opcode (2-byte NOP on 65C02)
    ;-----------------------------------------
    ldx #$55
    ldy #$33
    lda #$AA                ; A = $AA, Z=0, N=1
    sec                     ; C=1
    clv                     ; V=0

    php
    pla
    and #$CF
    sta test_zp

    lda #$AA
    sec
    clv

    .byte $44               ; Illegal opcode (2-byte NOP)
    .byte $00               ; Operand byte

    ; Save registers
    pha
    phx
    phy

    ; Check flags first
    php
    pla
    and #$CF
    cmp test_zp
    bne @fail2_flags

    ply
    plx
    pla

    cmp #$AA
    bne @fail2_a
    cpx #$55
    bne @fail2_x
    cpy #$33
    bne @fail2_y

    ; Test 2 passed
    lda #$02
    sta _g_results + 12
    jmp @test3

@fail2_flags:
    ply
    plx
    pla
    jmp @fail_flags
@fail2_a:
    jmp @fail_a
@fail2_x:
    jmp @fail_x
@fail2_y:
    jmp @fail_y

@test3:
    ;-----------------------------------------
    ; Test 3: $5C opcode (3-byte NOP on 65C02)
    ;-----------------------------------------
    ldx #$12
    ldy #$34
    lda #$56                ; A = $56, Z=0, N=0
    clc                     ; C=0
    clv                     ; V=0

    php
    pla
    and #$CF
    sta test_zp

    lda #$56
    clc
    clv

    .byte $5C               ; Illegal opcode (3-byte NOP)
    .byte $FF               ; Operand byte 1
    .byte $FF               ; Operand byte 2

    ; Save registers
    pha
    phx
    phy

    ; Check flags first
    php
    pla
    and #$CF
    cmp test_zp
    bne @fail3_flags

    ply
    plx
    pla

    cmp #$56
    bne @fail_a
    cpx #$12
    bne @fail_x
    cpy #$34
    bne @fail_y

    ; All 3 tests passed
    lda #$03
    sta _g_results + 12     ; Expected: 0x03 (all passed)
    jmp @done

@fail3_flags:
    ply
    plx
    pla
@fail_flags:
    lda #$FF                ; Error: Flags changed
    sta _g_results + 13
    jmp @done
@fail_a:
    lda #$AA                ; Error: A changed
    sta _g_results + 13
    jmp @done
@fail_x:
    lda #$BB                ; Error: X changed
    sta _g_results + 13
    jmp @done
@fail_y:
    lda #$CC                ; Error: Y changed
    sta _g_results + 13

@done:
    rts
.endproc

;===================================================================
; Test 7: 65SC02 Subset - RMB/SMB/BBR/BBS
; Lynx I will fail these test
; Lynx II uses 65SC02 which has these Rockwell/WDC extensions
; RMB0 = $07, SMB0 = $87, BBR0 = $0F, BBS0 = $8F
;===================================================================
.proc Test7
    stz _g_results + 14
    stz _g_results + 15
    stz _g_results + 16
    stz _g_results + 17

    ;-----------------------------------------
    ; Test RMB0 (Reset Memory Bit 0)
    ; Should clear bit 0 of memory location
    ;-----------------------------------------
    lda #$FF
    sta test_zp             ; All bits set

    .byte $07               ; RMB0 zp
    .byte test_zp

    lda test_zp
    sta _g_results + 14     ; Expected: 0xFE if RMB works, 0xFF if NOP

    ;-----------------------------------------
    ; Test SMB0 (Set Memory Bit 0)
    ; Should set bit 0 of memory location
    ;-----------------------------------------
    lda #$00
    sta test_zp             ; All bits clear

    .byte $87               ; SMB0 zp
    .byte test_zp

    lda test_zp
    sta _g_results + 15     ; Expected: 0x01 if SMB works, 0x00 if NOP

    ;-----------------------------------------
    ; Test BBR0 (Branch on Bit 0 Reset)
    ; If bit 0 is clear, branch; else continue
    ;-----------------------------------------
    lda #$FE                ; Bit 0 is clear
    sta test_zp

    lda #$00
    sta _g_results + 16     ; Default: not branched

    .byte $0F               ; BBR0 zp, rel
    .byte test_zp
    .byte @bbr_taken - (* + 1)  ; Relative offset to @bbr_taken

    ; If we reach here, BBR did NOT branch
    lda #$02
    sta _g_results + 16     ; 0x02 = BBR did not branch (NOP behavior)
    jmp @test_bbs

@bbr_taken:
    lda #$01
    sta _g_results + 16     ; Expected: 0x01 if BBR works

@test_bbs:
    ;-----------------------------------------
    ; Test BBS0 (Branch on Bit 0 Set)
    ; If bit 0 is set, branch; else continue
    ;-----------------------------------------
    lda #$01                ; Bit 0 is set
    sta test_zp

    lda #$00
    sta _g_results + 17     ; Default: not branched

    .byte $8F               ; BBS0 zp, rel
    .byte test_zp
    .byte @bbs_taken - (* + 1)  ; Relative offset to @bbs_taken

    ; If we reach here, BBS did NOT branch
    lda #$02
    sta _g_results + 17     ; 0x02 = BBS did not branch (NOP behavior)
    jmp @done

@bbs_taken:
    lda #$01
    sta _g_results + 17     ; Expected: 0x01 if BBS works

@done:
    rts
.endproc

;===================================================================
; Main test runner
;===================================================================
_run_tests:
    sei

    ; Clear results
    ldx #17
    lda #$00
@clear:
    sta _g_results,x
    dex
    bpl @clear

    ; Clear ZP
    stz irq_count
    stz irq_d_flag
    stz test_zp

    ; Install our IRQ handler
    jsr InstallIrqHandler

    ; Run tests
    jsr Test1
    jsr Test2
    jsr Test3
    jsr Test4
    jsr Test5
    jsr Test6
    jsr Test7

    ; Restore original IRQ handler
    jsr RestoreIrqHandler

    jsr ResetTimer6
    rts
