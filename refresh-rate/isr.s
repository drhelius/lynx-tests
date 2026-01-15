.setcpu "65C02"

.include "lynx.inc"

.export _install_isrs
.export _remove_isrs
.export _init_display

;-------------------------------------------------------------------
.segment "ZEROPAGE"
    saved_irq_lo:   .res 1
    saved_irq_hi:   .res 1
    isr_zp:         .res 1

;-------------------------------------------------------------------
.segment "CODE"

;===================================================================
; Simple ISR - handles both Timer 0 and Timer 2 interrupts
;===================================================================
.proc SimpleISR
    pha
    phx

    ; --- 1-byte instructions ---
    nop
    tax
    inx

    ; --- 2-byte instructions ---
    lda isr_zp                  ; read from ZP (RAM $00xx)
    ldx #$00                    ; load immediate
    sta isr_zp                  ; store to ZP

    ; --- 3-byte instructions ---
    ; Normal RAM read
    lda $2FCC                   ; read from RAM

    ; Mikey register reads
    lda $FD00                   ; read timer
    lda $FD20                   ; read audio
    lda $FDA0                   ; read color
    lda $FD8C                   ; read SERCTL

    ; Suzy register reads
    lda $FC00                   ; read TMPADRL
    lda $FC92                   ; read SPRSYS
    lda $FCB0                   ; read JOYSTICK

    ; Acknowledge both Timer 0 and Timer 2 interrupts
    lda #(TIMER0_INTERRUPT | TIMER2_INTERRUPT)
    sta INTRST

    plx
    pla
    rti
.endproc

;===================================================================
; Install ISRs
;===================================================================
_install_isrs:
    sei

    ; Save original IRQ vector
    lda INTVECTL
    sta saved_irq_lo
    lda INTVECTH
    sta saved_irq_hi

    ; Install the ISR
    lda #<SimpleISR
    sta INTVECTL
    lda #>SimpleISR
    sta INTVECTH

    ; Enable Timer 0 and Timer 2 interrupts
    lda #(TIMER0_INTERRUPT | TIMER2_INTERRUPT)
    sta INTSET

    cli
    rts

;===================================================================
; Remove ISRs
;===================================================================
_remove_isrs:
    sei

    ; Disable Timer 0 and Timer 2 interrupts
    lda #(TIMER0_INTERRUPT | TIMER2_INTERRUPT)
    sta INTRST

    ; Restore original IRQ vector
    lda saved_irq_lo
    sta INTVECTL
    lda saved_irq_hi
    sta INTVECTH

    cli
    rts

;===================================================================
; Initialize display hardware using table-driven approach
;===================================================================
_init_display:
    stz isr_zp

    ; Initialize Mikey registers from table
    ldx #14
@mloop:
    ldy MikeyInitReg,x
    lda MikeyInitData,x
    sta $fd00,y
    dex
    bpl @mloop

    ; Enable Suzy
    lda #$01
    sta SUZYBUSEN

    ; Set framebuffer address ($A000)
    lda #<$A000
    sta DISPADRL
    lda #>$A000
    sta DISPADRH

    ; Clear any pending interrupts
    lda #$FF
    sta INTRST

    rts

;-------------------------------------------------------------------
.segment "RODATA"

; Mikey register offsets (from $FD00)
MikeyInitReg:
    .byte $00       ; TIM0BKUP
    .byte $01       ; TIM0CTLA
    .byte $08       ; TIM2BKUP
    .byte $09       ; TIM2CTLA
    .byte $20       ; AUD0VOL
    .byte $28       ; AUD1VOL
    .byte $30       ; AUD2VOL
    .byte $38       ; AUD3VOL
    .byte $44       ; MSTEREO
    .byte $50       ; INTRST
    .byte $8a       ; IODIR
    .byte $8b       ; IODAT
    .byte $8c       ; SERCTL
    .byte $92       ; DISPCTL
    .byte $93       ; PBKUP

; Mikey register values
MikeyInitData:
    .byte $9e       ; TIM0BKUP = 158
    .byte $98       ; TIM0CTLA = enable int + reload + count
    .byte $68       ; TIM2BKUP = 104
    .byte $9f       ; TIM2CTLA = enable int + reload + count + link to T0
    .byte $00       ; AUD0VOL
    .byte $00       ; AUD1VOL
    .byte $00       ; AUD2VOL
    .byte $00       ; AUD3VOL
    .byte $00       ; MSTEREO
    .byte $ff       ; INTRST
    .byte $1a       ; IODIR
    .byte $0b       ; IODAT
    .byte $04       ; SERCTL
    .byte $0d       ; DISPCTL
    .byte $29       ; PBKUP
