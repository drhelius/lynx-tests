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
    irq_pc_lo:      .res 1      ; IRQ return PC low byte (Test8)
    irq_pc_hi:      .res 1      ; IRQ return PC high byte (Test8)

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
; Test8 IRQ handler - captures return PC
;===================================================================
.proc Test8IrqHandler
    pha
    phx

    ; Check for Timer6 interrupt
    lda INTSET
    and #TIMER6_INTERRUPT
    beq @not_timer6

    ; Timer6 interrupt - increment counter
    inc irq_count

    ; Capture return PC from IRQ stack frame (first IRQ only)
    ; Stack on entry: PCH, PCL, P. We push A then X.
    ; With TSX after PHA+PHX:
    ;   $0100+1,X = saved X
    ;   $0100+2,X = saved A
    ;   $0100+3,X = pushed P
    ;   $0100+4,X = pushed PCL (return PC low)
    ;   $0100+5,X = pushed PCH (return PC high)
    lda irq_count
    cmp #$01
    bne @skip_pc_capture
    tsx
    lda $0104,x
    sta irq_pc_lo
    lda $0105,x
    sta irq_pc_hi
@skip_pc_capture:

    ; Acknowledge Timer6 interrupt
    lda #TIMER6_INTERRUPT
    sta INTRST

@not_timer6:
    plx
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
; Result: 0x00 = pass, 0x01 = INC didn't run before IRQ, 0x02 = IRQ not taken
;===================================================================
.proc Test1
    jsr ResetTimer6

    stz irq_count
    stz _g_results + 0

    ;-----------------------------------------
    ; Test CLI allows IRQ after next instruction
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

    ; Check part 1: test_zp should be $01 (INC ran before IRQ)
    lda test_zp
    cmp #$01
    bne @fail_part1

    ; Check part 2: irq_count should be >= 1 (IRQ was taken)
    lda irq_count
    beq @fail_part2

    ; Both checks passed
    lda #$00
    sta _g_results + 0      ; Expected: 0x00 (pass)
    jmp @done

@fail_part1:
    lda #$01
    sta _g_results + 0      ; 0x01 = INC didn't run before IRQ
    jmp @done

@fail_part2:
    lda #$02
    sta _g_results + 0      ; 0x02 = IRQ was not taken

@done:
    jsr ResetTimer6
    rts
.endproc

;===================================================================
; Test 2: D Flag Cleared on Interrupt Entry
; Result: 0x00 = pass, 0x01 = D not cleared in handler, 0x02 = D not restored after RTI
;===================================================================
.proc Test2
    jsr ResetTimer6

    stz irq_d_flag
    stz _g_results + 1

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

    ; Check part 1: D flag should be 0 in handler
    lda irq_d_flag
    bne @fail_part1

    ; Check part 2: D flag should be restored after RTI (bit 3 = 0x08)
    php
    pla
    and #$08
    cmp #$08
    bne @fail_part2

    ; Both checks passed
    lda #$00
    sta _g_results + 1      ; Expected: 0x00 (pass)
    jmp @done

@fail_part1:
    lda #$01
    sta _g_results + 1      ; 0x01 = D flag not cleared in handler
    jmp @done

@fail_part2:
    lda #$02
    sta _g_results + 1      ; 0x02 = D flag not restored after RTI

@done:
    cld
    jsr ResetTimer6
    rts
.endproc

;===================================================================
; Test 3: BCD Arithmetic
;===================================================================
.proc Test3
    stz _g_results + 2
    stz _g_results + 3
    stz _g_results + 4

    ; BCD Addition: 0x29 + 0x23 = 0x52
    sed
    clc
    lda #$29
    adc #$23
    sta _g_results + 2      ; Expected: 0x52

    ; BCD Subtraction: 0x29 - 0x23 = 0x06
    sec
    lda #$29
    sbc #$23
    sta _g_results + 3      ; Expected: 0x06

    ; BCD with carry: 0x85 + 0x25 = 0x10 + carry
    clc
    lda #$85
    adc #$25
    php
    pla
    and #$01
    sta _g_results + 4      ; Expected: 0x01 (carry set)

    ; BCD Z flag: 0x99 + 0x01 = 0x00 + carry, Z should be set
    ; (65C02 sets Z correctly after BCD, NMOS 6502 does not)
    clc
    lda #$99
    adc #$01
    php
    pla
    and #$02                ; Z flag is bit 1
    sta _g_results + 5      ; Expected: 0x02 (Z set)

    ; BCD N flag: 0x40 + 0x41 = 0x81, N should be set
    ; (65C02 sets N correctly after BCD, NMOS 6502 does not)
    clc
    lda #$40
    adc #$41
    php
    pla
    and #$80                ; N flag is bit 7
    sta _g_results + 6      ; Expected: 0x80 (N set)

    cld
    rts
.endproc

;===================================================================
; Test 4: BRK is 2 Bytes
;===================================================================
.proc Test4
    stz _g_results + 7
    stz _g_results + 8

    ; Execute BRK and check we skip the signature byte
brk_here:
    brk
    .byte $EA               ; Signature byte (NOP, should be skipped)
    jmp @brk_ok

    ; If we land on the signature byte ($EA=NOP), we'd continue here
    lda #$FF
    sta _g_results + 7
    jmp @done

@brk_ok:
    lda #$02
    sta _g_results + 7      ; Expected: 0x02 (BRK is 2 bytes)

@done:
    ; B flag is always reported as set when pushed by BRK
    lda #$30
    sta _g_results + 8      ; Expected: 0x30 (B + unused flags)

    rts
.endproc

;===================================================================
; Test 5: JMP (indirect) Page Boundary Fix
; NMOS 6502 bug: JMP ($xxFF) reads high byte from $xx00 instead of $xx00+$100
;===================================================================
.proc Test5
    stz _g_results + 9

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
    sta _g_results + 9      ; 0x66 = NMOS bug detected
    jmp @done

@target_ok:
    ; 65C02 correct behavior - used $3100 for high byte
    lda #$BB
    sta _g_results + 9      ; Expected: 0xBB (65C02 correct)

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
    stz _g_results + 10     ; Test progress (1, 2, or 3 = all passed)
    stz _g_results + 11     ; Error code (0 = success)

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
    sta _g_results + 10
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
    sta _g_results + 10
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
    sta _g_results + 10     ; Expected: 0x03 (all passed)
    jmp @done

@fail3_flags:
    ply
    plx
    pla
@fail_flags:
    lda #$FF                ; Error: Flags changed
    sta _g_results + 11
    jmp @done
@fail_a:
    lda #$AA                ; Error: A changed
    sta _g_results + 11
    jmp @done
@fail_x:
    lda #$BB                ; Error: X changed
    sta _g_results + 11
    jmp @done
@fail_y:
    lda #$CC                ; Error: Y changed
    sta _g_results + 11

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
    stz _g_results + 12
    stz _g_results + 13
    stz _g_results + 14
    stz _g_results + 15

    ;-----------------------------------------
    ; Test RMB0 (Reset Memory Bit 0)
    ; Should clear bit 0 of memory location
    ;-----------------------------------------
    lda #$FF
    sta test_zp             ; All bits set

    .byte $07               ; RMB0 zp
    .byte test_zp

    lda test_zp
    sta _g_results + 12     ; Expected: 0xFE if RMB works, 0xFF if NOP

    ;-----------------------------------------
    ; Test SMB0 (Set Memory Bit 0)
    ; Should set bit 0 of memory location
    ;-----------------------------------------
    lda #$00
    sta test_zp             ; All bits clear

    .byte $87               ; SMB0 zp
    .byte test_zp

    lda test_zp
    sta _g_results + 13     ; Expected: 0x01 if SMB works, 0x00 if NOP

    ;-----------------------------------------
    ; Test BBR0 (Branch on Bit 0 Reset)
    ; If bit 0 is clear, branch; else continue
    ;-----------------------------------------
    lda #$FE                ; Bit 0 is clear
    sta test_zp

    lda #$00
    sta _g_results + 14     ; Default: not branched

    .byte $0F               ; BBR0 zp, rel
    .byte test_zp
    .byte @bbr_taken - (* + 1)  ; Relative offset to @bbr_taken

    ; If we reach here, BBR did NOT branch
    lda #$02
    sta _g_results + 14     ; 0x02 = BBR did not branch (NOP behavior)
    jmp @test_bbs

@bbr_taken:
    lda #$01
    sta _g_results + 14     ; Expected: 0x01 if BBR works

@test_bbs:
    ;-----------------------------------------
    ; Test BBS0 (Branch on Bit 0 Set)
    ; If bit 0 is set, branch; else continue
    ;-----------------------------------------
    lda #$01                ; Bit 0 is set
    sta test_zp

    lda #$00
    sta _g_results + 15     ; Default: not branched

    .byte $8F               ; BBS0 zp, rel
    .byte test_zp
    .byte @bbs_taken - (* + 1)  ; Relative offset to @bbs_taken

    ; If we reach here, BBS did NOT branch
    lda #$02
    sta _g_results + 15     ; 0x02 = BBS did not branch (NOP behavior)
    jmp @done

@bbs_taken:
    lda #$01
    sta _g_results + 15     ; Expected: 0x01 if BBS works

@done:
    rts
.endproc

;===================================================================
; Test 8: Illegal 1-byte NOPs do not acknowledge IRQs
; They should not service pending IRQs during execution
;===================================================================
.proc Test8
    jsr ResetTimer6

    stz _g_results + 16
    stz _g_results + 17

    ; Install Test8 IRQ handler
    sei
    lda #<Test8IrqHandler
    sta INTVECTL
    lda #>Test8IrqHandler
    sta INTVECTH

    ;-----------------------------------------
    ; Part A: All 1-byte illegal NOPs ($x3 and $xB)
    ; Execute 5 of each, IRQ should not be taken until after
    ;-----------------------------------------
    stz irq_count
    stz irq_pc_lo
    stz irq_pc_hi

    lda #$FF
    sta INTRST

    ; Program Timer6 to become DONE quickly, with IRQ enabled.
    lda #$02
    sta TIM6BKUP
    sta TIM6CNT
    lda #(ENABLE_INT | ENABLE_COUNT | 1)
    sta TIM6CTLA

@wait_done_a:
    lda TIM6CTLB
    and #TIMER_DONE
    beq @wait_done_a

    ; IRQ is now pending but masked. Enable and immediately run the block.
    cli

    ; $03 x5
    .byte $03, $03, $03, $03, $03
    ; $13 x5
    .byte $13, $13, $13, $13, $13
    ; $23 x5
    .byte $23, $23, $23, $23, $23
    ; $33 x5
    .byte $33, $33, $33, $33, $33
    ; $43 x5
    .byte $43, $43, $43, $43, $43
    ; $53 x5
    .byte $53, $53, $53, $53, $53
    ; $63 x5
    .byte $63, $63, $63, $63, $63
    ; $73 x5
    .byte $73, $73, $73, $73, $73
    ; $83 x5
    .byte $83, $83, $83, $83, $83
    ; $93 x5
    .byte $93, $93, $93, $93, $93
    ; $A3 x5
    .byte $A3, $A3, $A3, $A3, $A3
    ; $B3 x5
    .byte $B3, $B3, $B3, $B3, $B3
    ; $C3 x5
    .byte $C3, $C3, $C3, $C3, $C3
    ; $D3 x5
    .byte $D3, $D3, $D3, $D3, $D3
    ; $E3 x5
    .byte $E3, $E3, $E3, $E3, $E3
    ; $F3 x5
    .byte $F3, $F3, $F3, $F3, $F3
    ; $0B x5
    .byte $0B, $0B, $0B, $0B, $0B
    ; $1B x5
    .byte $1B, $1B, $1B, $1B, $1B
    ; $2B x5
    .byte $2B, $2B, $2B, $2B, $2B
    ; $3B x5
    .byte $3B, $3B, $3B, $3B, $3B
    ; $4B x5
    .byte $4B, $4B, $4B, $4B, $4B
    ; $5B x5
    .byte $5B, $5B, $5B, $5B, $5B
    ; $6B x5
    .byte $6B, $6B, $6B, $6B, $6B
    ; $7B x5
    .byte $7B, $7B, $7B, $7B, $7B
    ; $8B x5
    .byte $8B, $8B, $8B, $8B, $8B
    ; $9B x5
    .byte $9B, $9B, $9B, $9B, $9B
    ; $AB x5
    .byte $AB, $AB, $AB, $AB, $AB
    ; $BB x5
    .byte $BB, $BB, $BB, $BB, $BB
    ; $CB x5
    .byte $CB, $CB, $CB, $CB, $CB
    ; $DB x5
    .byte $DB, $DB, $DB, $DB, $DB
    ; $EB x5
    .byte $EB, $EB, $EB, $EB, $EB
    ; $FB x5
    .byte $FB, $FB, $FB, $FB, $FB

sentinel_a:
    inx                     ; Use INX as sentinel (not NOP)
    sei

    ; Wait for IRQ to be processed
@wait_irq_a:
    lda irq_count
    beq @wait_irq_a

    ; CLI allows pending IRQ AFTER the next instruction completes
    lda irq_pc_lo
    cmp #<(sentinel_a + 1)
    bne @part_a_fail
    lda irq_pc_hi
    cmp #>(sentinel_a + 1)
    bne @part_a_fail

    lda #$00
    sta _g_results + 16     ; Expected: 0x00 (pass - IRQ after sentinel)
    jmp @part_b

@part_a_fail:
    ; Store the actual PC low byte for diagnostics
    lda irq_pc_lo
    sta _g_results + 16     ; Non-zero = low byte of where IRQ actually fired

@part_b:
    ;-----------------------------------------
    ; Part B: Official NOP block (control test)
    ; IRQ should be taken INSIDE the NOP block
    ;-----------------------------------------
    jsr ResetTimer6

    sei
    stz irq_count
    stz irq_pc_lo
    stz irq_pc_hi

    lda #$FF
    sta INTRST

    lda #$02
    sta TIM6BKUP
    sta TIM6CNT
    lda #(ENABLE_INT | ENABLE_COUNT | 1)
    sta TIM6CTLA

@wait_done_b:
    lda TIM6CTLB
    and #TIMER_DONE
    beq @wait_done_b

    cli

    ; 100 official NOPs (same count as illegal block)
    .repeat 100
        nop
    .endrepeat

sentinel_b:
    dex                     ; Use DEX as sentinel (not NOP)
    sei

    ; Wait for IRQ to be processed
@wait_irq_b:
    lda irq_count
    beq @wait_irq_b

    ; CLI allows pending IRQ AFTER the next instruction completes
    lda irq_pc_lo
    cmp #<(sentinel_b + 1)
    bne @part_b_pass
    lda irq_pc_hi
    cmp #>(sentinel_b + 1)
    beq @part_b_fail

@part_b_pass:
    lda #$00
    sta _g_results + 17     ; Expected: 0x00 (pass - IRQ inside block)
    jmp @done

@part_b_fail:
    lda #$01
    sta _g_results + 17     ; 0x01 = IRQ taken at sentinel (unexpected)

@done:
    ; Restore original IRQ handler
    lda #<MyIrqHandler
    sta INTVECTL
    lda #>MyIrqHandler
    sta INTVECTH

    jsr ResetTimer6
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
    jsr Test8

    ; Restore original IRQ handler
    jsr RestoreIrqHandler

    jsr ResetTimer6
    rts
