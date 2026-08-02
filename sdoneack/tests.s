.setcpu "65C02"

.include "lynx.inc"
.include "../shared/sprites.inc"

.export _run_tests
.export _g_results

.segment "BSS"
    _g_results: .res 20

.segment "ZEROPAGE"
    irq_count:      .res 1
    irq_status:     .res 1
    observed_busy:  .res 1
    test_flags:     .res 1
    test_irqs:      .res 1
    setup_failed:   .res 1
    saved_irq_lo:   .res 1
    saved_irq_hi:   .res 1
    saved_tim2_ctla: .res 1
    saved_tim6_ctla: .res 1
    saved_tim6_bkup: .res 1
    saved_tim6_cnt:  .res 1
    saved_tim6_ctlb: .res 1

.segment "RODATA"

Literal4OnePen:
    .byte 2, $22, 0

.segment "DATA"

DEFINE_SCB ScbProbe, BPP_4 | TYPE_BACKNONCOLL, REHV | LITERAL, 0, 0, Literal4OnePen, 0, 0, $0800, $6600

.segment "CODE"

.proc InstallIrqHandler
    sei
    lda INTVECTL
    sta saved_irq_lo
    lda INTVECTH
    sta saved_irq_hi
    lda #<IrqHandler
    sta INTVECTL
    lda #>IrqHandler
    sta INTVECTH
    rts
.endproc

.proc RestoreIrqHandler
    sei
    lda saved_irq_lo
    sta INTVECTL
    lda saved_irq_hi
    sta INTVECTH
    cli
    rts
.endproc

.proc IrqHandler
    pha

    lda INTSET
    sta irq_status
    sta INTRST
    and #TIMER6_INTERRUPT
    beq @done
    inc irq_count

@done:
    pla
    rti
.endproc

.proc IsolateTimers
    lda TIM2CTLA
    sta saved_tim2_ctla
    and #$7F
    sta TIM2CTLA

    lda TIM6CTLA
    sta saved_tim6_ctla
    lda TIM6BKUP
    sta saved_tim6_bkup
    lda TIM6CNT
    sta saved_tim6_cnt
    lda TIM6CTLB
    sta saved_tim6_ctlb
    stz TIM6CTLA
    lda #$FF
    sta INTRST
    rts
.endproc

.proc RestoreTimers
    stz TIM6CTLA
    lda saved_tim6_bkup
    sta TIM6BKUP
    lda saved_tim6_cnt
    sta TIM6CNT
    lda saved_tim6_ctlb
    sta TIM6CTLB
    lda #$FF
    sta INTRST

    lda saved_tim6_ctla
    sta TIM6CTLA
    lda saved_tim2_ctla
    sta TIM2CTLA
    rts
.endproc

.proc StartWatchdog
    stz TIM6CTLA
    stz TIM6CTLB
    stz irq_count
    lda #TIMER6_INTERRUPT
    sta INTRST
    lda #$FF
    sta TIM6BKUP
    sta TIM6CNT
    lda #(ENABLE_INT | ENABLE_COUNT | 6)
    sta TIM6CTLA
    rts
.endproc

.proc StartEarlyWake
    stz TIM6CTLA
    stz TIM6CTLB
    stz irq_count
    lda #TIMER6_INTERRUPT
    sta INTRST
    lda #3
    sta TIM6BKUP
    sta TIM6CNT
    lda #(ENABLE_INT | ENABLE_COUNT | 6)
    sta TIM6CTLA
    rts
.endproc

.proc SetTimer6Pending
    stz TIM6CTLA
    stz TIM6CTLB
    stz irq_count
    lda #TIMER6_INTERRUPT
    sta INTRST
    stz TIM6BKUP
    stz TIM6CNT
    lda #(ENABLE_INT | ENABLE_COUNT | 6)
    sta TIM6CTLA

@wait:
    lda INTSET
    and #TIMER6_INTERRUPT
    beq @wait
    rts
.endproc

.proc StopWatchdog
    stz TIM6CTLA
    lda #TIMER6_INTERRUPT
    sta INTRST
    rts
.endproc

.proc InitTestHardware
    jsr IsolateTimers
    stz DISPCTL
    stz HOFFL
    stz HOFFH
    stz VOFFL
    stz VOFFH

    lda #<VIDEO_BASE
    sta VIDBASL
    lda #>VIDEO_BASE
    sta VIDBASH
    lda #<COLLISION_BASE
    sta COLLBASL
    lda #>COLLISION_BASE
    sta COLLBASH
    lda #SCB_COLL_RESULT
    sta COLLOFFL
    stz COLLOFFH
    stz HSIZOFFL
    stz HSIZOFFH
    stz VSIZOFFL
    stz VSIZOFFH

    lda #$F3
    sta SPRINIT
    lda #1
    sta SUZYBUSEN
    lda #NO_COLLIDE
    sta SPRSYS
    rts
.endproc

.proc StartProbeSprite
    lda #<ScbProbe
    sta SCBNEXTL
    lda #>ScbProbe
    sta SCBNEXTH
    lda #SPRITE_GO
    sta SPRGO
    rts
.endproc

.proc ObserveSleep
    jsr StartWatchdog
    cli
    stz CPUSLEEP
    sei
    lda SPRSYS
    and #SPRITEWORKING
    sta observed_busy
    jsr StopWatchdog
    rts
.endproc

.proc EstablishDonePending
    stz setup_failed
    stz SDONEACK
    jsr StartProbeSprite
    jsr ObserveSleep
    lda observed_busy
    ora irq_count
    beq @done
    lda #$80
    sta setup_failed
    stz SPRGO
    stz SDONEACK

@done:
    rts
.endproc

.proc StoreResult0
    lda observed_busy
    sta _g_results + 0
    lda irq_count
    sta _g_results + 1
    rts
.endproc

.proc StoreResult1
    lda observed_busy
    sta _g_results + 2
    lda irq_count
    sta _g_results + 3
    rts
.endproc

.proc StoreResult2
    lda observed_busy
    sta _g_results + 4
    lda irq_count
    sta _g_results + 5
    rts
.endproc

.proc StoreResult3
    lda observed_busy
    sta _g_results + 6
    lda irq_count
    sta _g_results + 7
    rts
.endproc

.proc StoreResult4
    lda observed_busy
    sta _g_results + 8
    lda irq_count
    sta _g_results + 9
    rts
.endproc

.proc StoreResult5
    lda observed_busy
    sta _g_results + 10
    lda irq_count
    sta _g_results + 11
    rts
.endproc

.proc StoreResult6
    lda observed_busy
    sta _g_results + 12
    lda irq_count
    sta _g_results + 13
    rts
.endproc

.proc StoreResult7
    lda observed_busy
    sta _g_results + 14
    lda irq_count
    sta _g_results + 15
    rts
.endproc

.proc StoreResult8
    lda observed_busy
    sta _g_results + 16
    lda irq_count
    sta _g_results + 17
    rts
.endproc

.proc StoreResult9
    lda observed_busy
    sta _g_results + 18
    lda irq_count
    sta _g_results + 19
    rts
.endproc

.proc RecoverAndAcknowledge
    stz SDONEACK
    jsr ObserveSleep
    lda observed_busy
    beq @acknowledge
    stz SPRGO

@acknowledge:
    stz SDONEACK
    rts
.endproc

.proc _run_tests
    jsr InstallIrqHandler
    jsr InitTestHardware

    ; ACK before SPRGO: start busy, then complete without watchdog recovery.
    stz SDONEACK
    jsr StartProbeSprite
    lda SPRSYS
    and #SPRITEWORKING
    sta test_flags
    jsr ObserveSleep
    lda observed_busy
    beq @ack_before_store
    lda test_flags
    ora #$02
    sta test_flags
@ack_before_store:
    lda test_flags
    sta observed_busy
    jsr StoreResult0

    ; ACK after SPRGO: launch while done is pending, then acknowledge and sleep.
    jsr EstablishDonePending
    jsr StartProbeSprite
    lda SPRSYS
    and #SPRITEWORKING
    ora setup_failed
    sta test_flags
    stz SDONEACK
    jsr ObserveSleep
    lda observed_busy
    beq @ack_after_store
    lda test_flags
    ora #$02
    sta test_flags
@ack_after_store:
    lda test_flags
    sta observed_busy
    jsr StoreResult1

    ; One unacknowledged completion must make the next sleep return busy.
    jsr EstablishDonePending
    jsr StartProbeSprite
    jsr ObserveSleep
    lda observed_busy
    ora setup_failed
    sta observed_busy
    jsr StoreResult2
    jsr RecoverAndAcknowledge

    ; The pending done condition must survive repeated CPUSLEEP writes.
    jsr EstablishDonePending
    jsr StartProbeSprite
    lda setup_failed
    sta test_flags
    stz test_irqs

    jsr ObserveSleep
    lda observed_busy
    beq @sticky_second
    lda test_flags
    ora #$01
    sta test_flags
    lda test_irqs
    clc
    adc irq_count
    sta test_irqs

@sticky_second:
    jsr ObserveSleep
    lda observed_busy
    beq @sticky_third
    lda test_flags
    ora #$02
    sta test_flags
    lda test_irqs
    clc
    adc irq_count
    sta test_irqs

@sticky_third:
    jsr ObserveSleep
    lda observed_busy
    beq @sticky_store
    lda test_flags
    ora #$04
    sta test_flags
    lda test_irqs
    clc
    adc irq_count
    sta test_irqs

@sticky_store:
    lda test_flags
    sta observed_busy
    lda test_irqs
    sta irq_count
    jsr StoreResult3
    jsr RecoverAndAcknowledge

    ; Any write value must clear done and release the already-started sprite.
    jsr EstablishDonePending
    jsr StartProbeSprite
    jsr ObserveSleep
    lda observed_busy
    ora setup_failed
    sta test_flags
    lda irq_count
    sta test_irqs
    lda #$A5
    sta SDONEACK
    jsr ObserveSleep
    lda observed_busy
    beq @ack_value_irqs
    lda test_flags
    ora #$02
    sta test_flags
@ack_value_irqs:
    lda test_irqs
    clc
    adc irq_count
    sta irq_count
    lda test_flags
    sta observed_busy
    jsr StoreResult4
    jsr RecoverAndAcknowledge

    ; A timer IRQ may wake the CPU mid-sprite; sleeping again needs no SDONEACK.
    stz SDONEACK
    jsr StartProbeSprite
    jsr StartEarlyWake
    cli
    stz CPUSLEEP
    sei
    stz test_flags
    lda SPRSYS
    and #SPRITEWORKING
    beq @irq_resleep_count
    lda #$01
    sta test_flags
@irq_resleep_count:
    lda irq_count
    sta test_irqs
    jsr StopWatchdog
    jsr ObserveSleep
    lda observed_busy
    beq @irq_resleep_watchdog
    lda test_flags
    ora #$02
    sta test_flags
@irq_resleep_watchdog:
    lda irq_count
    beq @irq_resleep_store
    lda test_flags
    ora #$80
    sta test_flags
@irq_resleep_store:
    lda test_flags
    sta observed_busy
    lda test_irqs
    sta irq_count
    jsr StoreResult5

    ; An already-pending Mikey IRQ prevents sleep even with the CPU I flag set.
    stz SDONEACK
    jsr StartProbeSprite
    sei
    jsr SetTimer6Pending
    stz CPUSLEEP
    stz test_flags
    lda SPRSYS
    and #SPRITEWORKING
    beq @pending_clear
    lda #$01
    sta test_flags
@pending_clear:
    stz TIM6CTLA
    lda #TIMER6_INTERRUPT
    sta INTRST
    jsr ObserveSleep
    lda observed_busy
    beq @pending_store
    lda test_flags
    ora #$02
    sta test_flags
@pending_store:
    lda test_flags
    sta observed_busy
    jsr StoreResult6

    ; Mikey's broken idle sleep must continue immediately without a watchdog.
    stz SDONEACK
    jsr ObserveSleep
    jsr StoreResult7

    ; SPRGO starts the engine with its bus disabled; enabling it later resumes.
    stz SDONEACK
    stz SUZYBUSEN
    jsr StartProbeSprite
    stz test_flags
    lda SPRSYS
    and #SPRITEWORKING
    beq @bus_enable
    lda #$01
    sta test_flags
@bus_enable:
    lda #1
    sta SUZYBUSEN
    jsr ObserveSleep
    lda observed_busy
    beq @bus_store
    lda test_flags
    ora #$02
    sta test_flags
@bus_store:
    lda test_flags
    sta observed_busy
    jsr StoreResult8
    stz SDONEACK

    ; Removing Suzy's bus after launch must inhibit sleep without clearing busy.
    lda #1
    sta SUZYBUSEN
    stz SDONEACK
    jsr StartProbeSprite
    stz SUZYBUSEN
    jsr ObserveSleep
    jsr StoreResult9
    lda #1
    sta SUZYBUSEN
    stz SDONEACK
    jsr ObserveSleep
    stz SDONEACK

    jsr RestoreTimers
    lda #DISPLAY_DMA_ON
    sta DISPCTL
    jsr RestoreIrqHandler
    rts
.endproc