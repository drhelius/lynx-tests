; Shared Suzy benchmark runner
; Each logical test publishes: 16-bit 1-us timing, video CRC8, collision CRC8.

.export _run_tests
.export _g_results

.segment "ZEROPAGE"
    test_index:       .res 1
    result_offset:    .res 1
    descriptor_off:   .res 1
    scb_ptr:          .res 2
    block_ptr:        .res 2
    block_length:     .res 2
    fill_value:       .res 1
    measured_time:    .res 2
    minimum_time:     .res 2
    retry_count:      .res 1
    crc_value:        .res 1
    current_sprsys:   .res 1
    current_dispctl:  .res 1

.segment "BSS"
    _g_results: .res TEST_COUNT * 4

.segment "RODATA"
    CrcTable:
        .byte $00, $07, $0E, $09, $1C, $1B, $12, $15, $38, $3F, $36, $31, $24, $23, $2A, $2D
        .byte $70, $77, $7E, $79, $6C, $6B, $62, $65, $48, $4F, $46, $41, $54, $53, $5A, $5D
        .byte $E0, $E7, $EE, $E9, $FC, $FB, $F2, $F5, $D8, $DF, $D6, $D1, $C4, $C3, $CA, $CD
        .byte $90, $97, $9E, $99, $8C, $8B, $82, $85, $A8, $AF, $A6, $A1, $B4, $B3, $BA, $BD
        .byte $C7, $C0, $C9, $CE, $DB, $DC, $D5, $D2, $FF, $F8, $F1, $F6, $E3, $E4, $ED, $EA
        .byte $B7, $B0, $B9, $BE, $AB, $AC, $A5, $A2, $8F, $88, $81, $86, $93, $94, $9D, $9A
        .byte $27, $20, $29, $2E, $3B, $3C, $35, $32, $1F, $18, $11, $16, $03, $04, $0D, $0A
        .byte $57, $50, $59, $5E, $4B, $4C, $45, $42, $6F, $68, $61, $66, $73, $74, $7D, $7A
        .byte $89, $8E, $87, $80, $95, $92, $9B, $9C, $B1, $B6, $BF, $B8, $AD, $AA, $A3, $A4
        .byte $F9, $FE, $F7, $F0, $E5, $E2, $EB, $EC, $C1, $C6, $CF, $C8, $DD, $DA, $D3, $D4
        .byte $69, $6E, $67, $60, $75, $72, $7B, $7C, $51, $56, $5F, $58, $4D, $4A, $43, $44
        .byte $19, $1E, $17, $10, $05, $02, $0B, $0C, $21, $26, $2F, $28, $3D, $3A, $33, $34
        .byte $4E, $49, $40, $47, $52, $55, $5C, $5B, $76, $71, $78, $7F, $6A, $6D, $64, $63
        .byte $3E, $39, $30, $37, $22, $25, $2C, $2B, $06, $01, $08, $0F, $1A, $1D, $14, $13
        .byte $AE, $A9, $A0, $A7, $B2, $B5, $BC, $BB, $96, $91, $98, $9F, $8A, $8D, $84, $83
        .byte $DE, $D9, $D0, $D7, $C2, $C5, $CC, $CB, $E6, $E1, $E8, $EF, $FA, $FD, $F4, $F3

.segment "CODE"

;===================================================================
; Initialize the Suzy registers shared by every suite.
;===================================================================
.proc InitSuzy
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

    lda #<DISPLAY_BASE
    sta DISPADRL
    lda #>DISPLAY_BASE
    sta DISPADRH
    lda #DISPLAY_DMA_OFF
    sta DISPCTL

    lda #<DISPLAY_BASE
    sta block_ptr
    lda #>DISPLAY_BASE
    sta block_ptr + 1
    stz fill_value
    jsr FillBuffer
    rts
.endproc

;===================================================================
; Fill BUFFER_BYTES bytes at block_ptr with fill_value.
;===================================================================
.proc FillBuffer
    lda #>BUFFER_BYTES
    tax
    ldy #0

@page:
    lda fill_value
@page_byte:
    sta (block_ptr),y
    iny
    bne @page_byte
    inc block_ptr + 1
    dex
    bne @page

@tail:
    cpy #<BUFFER_BYTES
    beq @done
    lda fill_value
    sta (block_ptr),y
    iny
    bne @tail

@done:
    rts
.endproc

;===================================================================
; Reset video and collision buffers before each timed draw.
;===================================================================
.proc ResetBuffers
    lda #<VIDEO_BASE
    sta block_ptr
    lda #>VIDEO_BASE
    sta block_ptr + 1
    lda #$A5
    sta fill_value
    jsr FillBuffer

    lda #<COLLISION_BASE
    sta block_ptr
    lda #>COLLISION_BASE
    sta block_ptr + 1
    lda #$5A
    sta fill_value
    jsr FillBuffer
    rts
.endproc

;===================================================================
; Wait for a fresh raster-96 boundary.
;===================================================================
.proc WaitRaster96
@leave:
    lda TIM2CNT
    cmp #96
    beq @leave
@wait:
    lda TIM2CNT
    cmp #96
    bne @wait
    rts
.endproc

;===================================================================
; Prepare a 16-bit microsecond counter using Timer 1 and linked Timer 3.
;===================================================================
.proc PrepareTimer
    stz TIM1CTLA
    stz TIM3CTLA
    stz TIM1CTLB
    stz TIM3CTLB
    lda #$FF
    sta TIM1BKUP
    sta TIM1CNT
    sta TIM3BKUP
    sta TIM3CNT
    rts
.endproc

;===================================================================
; Start one SCB and sleep until Suzy releases the CPU.
;===================================================================
.proc DrawSprites
    lda scb_ptr
    sta SCBNEXTL
    lda scb_ptr + 1
    sta SCBNEXTH

    lda #SPRITE_GO
    sta SPRGO
    stz SDONEACK

@wait:
    stz CPUSLEEP
    lda SPRSYS
    and #SPRITEWORKING
    bne @wait

    stz SDONEACK
    rts
.endproc

;===================================================================
; Run one timed attempt. Stores elapsed microseconds in measured_time.
;===================================================================
.proc MeasureOnce
    jsr ResetBuffers

    ldy #SCB_COLL_RESULT
    lda #0
    sta (scb_ptr),y

    lda current_sprsys
    sta SPRSYS
    ; Select DMA before raster synchronization so its bus phase is deliberate.
    lda current_dispctl
    sta DISPCTL

    jsr PrepareTimer
    jsr WaitRaster96

    ; Hardware needs a second status clear immediately before enable.
    stz TIM1CTLB
    stz TIM3CTLB
    lda #(ENABLE_COUNT | 7)
    sta TIM3CTLA
    lda #(ENABLE_RELOAD | ENABLE_COUNT | AUD_1)
    sta TIM1CTLA
    jsr DrawSprites
    stz TIM1CTLA
    stz TIM3CTLA

    sec
    lda #$FF
    sbc TIM1CNT
    sta measured_time
    sec
    lda #$FF
    sbc TIM3CNT
    sta measured_time + 1
    rts
.endproc

;===================================================================
; Keep the minimum of three complete attempts.
;===================================================================
.proc MeasureMinimum
    lda #$FF
    sta minimum_time
    sta minimum_time + 1
    lda #3
    sta retry_count

@retry:
    jsr MeasureOnce
    lda measured_time + 1
    cmp minimum_time + 1
    bcc @save
    bne @next
    lda measured_time
    cmp minimum_time
    bcs @next
@save:
    lda measured_time
    sta minimum_time
    lda measured_time + 1
    sta minimum_time + 1
@next:
    dec retry_count
    bne @retry

    lda minimum_time
    rts
.endproc

;===================================================================
; Draw one clean, untimed reference image for semantic CRCs.
;===================================================================
.proc DrawSemantic
    jsr ResetBuffers

    ldy #SCB_COLL_RESULT
    lda #0
    sta (scb_ptr),y

    lda current_sprsys
    sta SPRSYS
    lda current_dispctl
    sta DISPCTL
    jsr DrawSprites
    rts
.endproc

;===================================================================
; Continue CRC8 (polynomial $07) over BUFFER_BYTES at block_ptr.
;===================================================================
.proc CrcBuffer
    lda #<BUFFER_BYTES
    sta block_length
    lda #>BUFFER_BYTES
    sta block_length + 1
    ldy #0

@byte:
    lda (block_ptr),y
    eor crc_value
    tax
    lda CrcTable,x
    sta crc_value

    inc block_ptr
    bne @count
    inc block_ptr + 1
@count:
    lda block_length
    bne @low
    dec block_length + 1
@low:
    dec block_length
    lda block_length
    ora block_length + 1
    bne @byte

    lda crc_value
    rts
.endproc

;===================================================================
; CRC the complete video buffer and its guard bytes.
;===================================================================
.proc ComputeVideoCrc
    stz crc_value
    lda #<VIDEO_BASE
    sta block_ptr
    lda #>VIDEO_BASE
    sta block_ptr + 1
    jmp CrcBuffer
.endproc

;===================================================================
; CRC the complete collision buffer and its guard bytes.
;===================================================================
.proc ComputeCollisionCrc
    stz crc_value
    lda #<COLLISION_BASE
    sta block_ptr
    lda #>COLLISION_BASE
    sta block_ptr + 1
    jsr CrcBuffer

    ldy #SCB_COLL_RESULT
    lda (scb_ptr),y
    eor crc_value
    tax
    lda CrcTable,x
    sta crc_value
    rts
.endproc

;===================================================================
; Main runner: descriptor = SCB pointer, SPRSYS, DISPCTL.
;===================================================================
_run_tests:
    sei
    jsr InitSuzy
    stz test_index
    stz result_offset

@test:
    lda test_index
    asl
    asl
    sta descriptor_off
    tax

    lda TestDescriptors,x
    sta scb_ptr
    lda TestDescriptors + 1,x
    sta scb_ptr + 1
    lda TestDescriptors + 2,x
    sta current_sprsys
    lda TestDescriptors + 3,x
    sta current_dispctl

    jsr PrepareTest

    jsr MeasureMinimum
    ldx result_offset
    lda minimum_time
    sta _g_results,x
    lda minimum_time + 1
    sta _g_results + 1,x

    jsr DrawSemantic

    jsr ComputeVideoCrc
    ldx result_offset
    sta _g_results + 2,x

    jsr ComputeCollisionCrc
    ldx result_offset
    sta _g_results + 3,x

    inc result_offset
    inc result_offset
    inc result_offset
    inc result_offset
    inc test_index
    lda test_index
    cmp #TEST_COUNT
    bne @test

    stz TIM1CTLA
    stz TIM1CTLB
    stz TIM3CTLA
    stz TIM3CTLB
    lda #DISPLAY_DMA_ON
    sta DISPCTL
    cli
    rts
