;===============================================================================
; Alpine Games Copy Protection Test - Assembly Tests
;
; Replicates EXACT conditions from Alpine Games:
; - COLLBAS = $0000, VIDBAS = $0210 (overlapping buffers)  
; - Off-screen sprite with HFLIP at HPOS=163
; - 1BPP literal, HSIZ=$00FF, palette $05
; - Check value at $025F (the copy protection check address)
;
; Each test stores 16 bytes of results at RESULTS_ADDR + (test_num * 16)
;===============================================================================

.setcpu "65C02"
.include "lynx.inc"

.export _run_sprite_tests

;-------------------------------------------------------------------------------
; Constants  
;-------------------------------------------------------------------------------
RESULTS_ADDR    = $B000         ; Where we store test results

; NOTE: We use buffer addresses at $C000+ to avoid code segment at $0200-$0A90
; Alpine Games uses COLLBAS=$0000, VIDBAS=$0210, TARGET=$025F
; We use COLLBAS=$C000, VIDBAS=$C210, TARGET=$C25F (same offset, safe RAM)
BUFFER_BASE     = $C000         ; Base of our test buffers
TARGET_ADDR     = $C25F         ; Same offset as Alpine: base+$025F

; Suzy registers
SUZY_TMPADRL    = $FC00
SUZY_HOFFL      = $FC04
SUZY_HOFFH      = $FC05
SUZY_VOFFL      = $FC06
SUZY_VOFFH      = $FC07
SUZY_VIDBASL    = $FC08
SUZY_VIDBASH    = $FC09
SUZY_COLLBASL   = $FC0A
SUZY_COLLBASH   = $FC0B
SUZY_SCBNEXTL   = $FC10
SUZY_SCBNEXTH   = $FC11
SUZY_COLLOFFL   = $FC24
SUZY_COLLOFFH   = $FC25
SUZY_HSIZOFFL   = $FC28
SUZY_HSIZOFFH   = $FC29
SUZY_VSIZOFFL   = $FC2A
SUZY_VSIZOFFH   = $FC2B
SUZY_SPRINIT    = $FC83
SUZY_SUZYBUSEN  = $FC90
SUZY_SPRGO      = $FC91
SUZY_SPRSYS     = $FC92

; Mikey registers
MIKEY_SDONEACK  = $FD90
MIKEY_CPUSLEEP  = $FD91

; Sprite control values
SPRCTL0_1BPP    = $00
SPRCTL0_HFLIP   = $20
SPRCTL0_VFLIP   = $10
SPR_NOCOLL      = $05
SPR_NORMAL      = $04
SPR_BG          = $00

SPRCTL1_LITERAL = $80
SPRCTL1_RELOAD_HV = $10

;-------------------------------------------------------------------------------
; Zero page variables
;-------------------------------------------------------------------------------
.segment "ZEROPAGE"
test_num:       .res 1
result_ptr:     .res 2
temp:           .res 2

;-------------------------------------------------------------------------------
; DATA segment - SCBs and sprite data
;-------------------------------------------------------------------------------
.segment "RODATA"

; Sprite data for 1BPP - pattern $A8 = 10101000 (first pixel = pen1)
sprite_data_A8:
    .byte $02           ; offset to next line (2 bytes)
    .byte $A8           ; pixel data: 10101000
    .byte $00           ; end of sprite

; Sprite data - all 1s
sprite_data_FF:
    .byte $02
    .byte $FF           ; 11111111
    .byte $00

; Sprite data - single pixel
sprite_data_80:
    .byte $02
    .byte $80           ; 10000000
    .byte $00

;-------------------------------------------------------------------------------
; BSS segment - SCB template (will be copied to RAM and modified)
;-------------------------------------------------------------------------------
.segment "BSS"

; SCB structure for 1BPP sprite (16 bytes)
scb:
scb_sprctl0:    .res 1  ; +0
scb_sprctl1:    .res 1  ; +1
scb_sprcoll:    .res 1  ; +2
scb_next_lo:    .res 1  ; +3
scb_next_hi:    .res 1  ; +4
scb_data_lo:    .res 1  ; +5
scb_data_hi:    .res 1  ; +6
scb_hpos_lo:    .res 1  ; +7
scb_hpos_hi:    .res 1  ; +8
scb_vpos_lo:    .res 1  ; +9
scb_vpos_hi:    .res 1  ; +10
scb_hsiz_lo:    .res 1  ; +11
scb_hsiz_hi:    .res 1  ; +12
scb_vsiz_lo:    .res 1  ; +13
scb_vsiz_hi:    .res 1  ; +14
scb_palette:    .res 1  ; +15 (pen0=hi nibble, pen1=lo nibble for 1BPP)
scb_colldep:    .res 1  ; +16 collision depository

;-------------------------------------------------------------------------------
; CODE segment
;-------------------------------------------------------------------------------
.segment "CODE"

;===============================================================================
; Main test entry point - called from C
;===============================================================================
.proc _run_sprite_tests
    sei
    
    ; Initialize Suzy
    jsr init_suzy
    
    ; Clear results area
    jsr clear_results
    
    ; Initialize test counter
    stz test_num
    
    ;-------------------------------------------------------------------
    ; TEST 1: Alpine Games EXACT conditions
    ; COLLBAS=$0000, VIDBAS=$0210, HPOS=163, HFLIP, HSIZ=$00FF
    ; Check: $025F should contain pen 5 in some nibble
    ;-------------------------------------------------------------------
    inc test_num
    
    ; Clear target area
    jsr clear_target_area
    
    ; Setup buffer configuration (same offsets as Alpine Games, safe RAM)
    ; Alpine uses COLLBAS=$0000, VIDBAS=$0210
    ; We use COLLBAS=$C000, VIDBAS=$C210
    lda #<BUFFER_BASE       ; COLLBAS = $C000
    sta SUZY_COLLBASL       
    lda #>BUFFER_BASE
    sta SUZY_COLLBASH
    lda #$10
    sta SUZY_VIDBASL        ; VIDBAS = $C210
    lda #$C2
    sta SUZY_VIDBASH
    
    ; Setup SCB
    lda #(SPRCTL0_1BPP | SPRCTL0_HFLIP | SPR_NOCOLL)  ; $25
    sta scb_sprctl0
    lda #(SPRCTL1_LITERAL | SPRCTL1_RELOAD_HV)          ; $90
    sta scb_sprctl1
    stz scb_sprcoll
    stz scb_next_lo
    stz scb_next_hi
    lda #<sprite_data_A8
    sta scb_data_lo
    lda #>sprite_data_A8
    sta scb_data_hi
    lda #163                ; HPOS = 163 (off screen right)
    sta scb_hpos_lo
    stz scb_hpos_hi
    stz scb_vpos_lo         ; VPOS = 0
    stz scb_vpos_hi
    lda #$FF                ; HSIZ = $00FF
    sta scb_hsiz_lo
    stz scb_hsiz_hi
    stz scb_vsiz_lo         ; VSIZ = $0100
    lda #$01
    sta scb_vsiz_hi
    lda #$05                ; Palette: pen0=0, pen1=5
    sta scb_palette
    lda #$FF
    sta scb_colldep
    
    jsr run_sprite
    jsr record_result
    
    ;-------------------------------------------------------------------
    ; TEST 2: Same but VIDBAS=$0000 (complete overlap with COLLBAS)
    ;-------------------------------------------------------------------
    inc test_num
    jsr clear_target_area
    
    lda #<BUFFER_BASE
    sta SUZY_COLLBASL
    lda #>BUFFER_BASE
    sta SUZY_COLLBASH
    lda #<BUFFER_BASE       ; VIDBAS = $C000 (same as COLLBAS)
    sta SUZY_VIDBASL
    lda #>BUFFER_BASE
    sta SUZY_VIDBASH
    
    jsr run_sprite
    jsr record_result
    
    ;-------------------------------------------------------------------
    ; TEST 3: HSIZ = $0100 (256) instead of $00FF
    ;-------------------------------------------------------------------
    inc test_num
    jsr clear_target_area
    
    ; Restore buffer config
    lda #<BUFFER_BASE
    sta SUZY_COLLBASL
    lda #>BUFFER_BASE
    sta SUZY_COLLBASH
    lda #$10
    sta SUZY_VIDBASL
    lda #$C2
    sta SUZY_VIDBASH
    
    stz scb_hsiz_lo         ; HSIZ = $0100
    lda #$01
    sta scb_hsiz_hi
    
    jsr run_sprite
    jsr record_result
    
    ;-------------------------------------------------------------------
    ; TEST 4: HSIZ = $0101 (257)
    ;-------------------------------------------------------------------
    inc test_num
    jsr clear_target_area
    
    lda #$01
    sta scb_hsiz_lo         ; HSIZ = $0101
    sta scb_hsiz_hi
    
    jsr run_sprite
    jsr record_result
    
    ;-------------------------------------------------------------------
    ; TEST 5: HPOS = 160 (exactly at screen edge)
    ;-------------------------------------------------------------------
    inc test_num
    jsr clear_target_area
    
    lda #$FF                ; Restore HSIZ = $00FF
    sta scb_hsiz_lo
    stz scb_hsiz_hi
    
    lda #160                ; HPOS = 160
    sta scb_hpos_lo
    
    jsr run_sprite
    jsr record_result
    
    ;-------------------------------------------------------------------
    ; TEST 6: HPOS = 159 (last on-screen pixel)
    ;-------------------------------------------------------------------
    inc test_num
    jsr clear_target_area
    
    lda #159                ; HPOS = 159
    sta scb_hpos_lo
    
    jsr run_sprite
    jsr record_result
    
    ;-------------------------------------------------------------------
    ; TEST 7: HPOS = 164
    ;-------------------------------------------------------------------
    inc test_num
    jsr clear_target_area
    
    lda #164                ; HPOS = 164
    sta scb_hpos_lo
    
    jsr run_sprite
    jsr record_result
    
    ;-------------------------------------------------------------------
    ; TEST 8: No HFLIP, HPOS = 0 (normal left-to-right)
    ;-------------------------------------------------------------------
    inc test_num
    jsr clear_target_area
    
    lda #(SPRCTL0_1BPP | SPR_NOCOLL)  ; No HFLIP
    sta scb_sprctl0
    stz scb_hpos_lo         ; HPOS = 0
    
    jsr run_sprite
    jsr record_result
    
    ;-------------------------------------------------------------------
    ; TEST 9: sprite_data_FF (all pixels = pen1)
    ;-------------------------------------------------------------------
    inc test_num
    jsr clear_target_area
    
    lda #(SPRCTL0_1BPP | SPRCTL0_HFLIP | SPR_NOCOLL)
    sta scb_sprctl0
    lda #163
    sta scb_hpos_lo
    
    lda #<sprite_data_FF
    sta scb_data_lo
    lda #>sprite_data_FF
    sta scb_data_hi
    
    jsr run_sprite
    jsr record_result
    
    ;-------------------------------------------------------------------
    ; TEST 10: sprite_data_80 (only first pixel = pen1)
    ;-------------------------------------------------------------------
    inc test_num
    jsr clear_target_area
    
    lda #<sprite_data_80
    sta scb_data_lo
    lda #>sprite_data_80
    sta scb_data_hi
    
    jsr run_sprite
    jsr record_result
    
    ;-------------------------------------------------------------------
    ; TEST 11: NORMAL sprite type (collidable) 
    ;-------------------------------------------------------------------
    inc test_num
    jsr clear_target_area
    
    lda #<sprite_data_A8    ; Restore A8 pattern
    sta scb_data_lo
    lda #>sprite_data_A8
    sta scb_data_hi
    
    lda #(SPRCTL0_1BPP | SPRCTL0_HFLIP | SPR_NORMAL)  
    sta scb_sprctl0
    lda #$05
    sta scb_sprcoll         ; Collision ID = 5
    
    jsr run_sprite
    jsr record_result
    
    ;-------------------------------------------------------------------
    ; TEST 12: BACKGROUND sprite type
    ;-------------------------------------------------------------------
    inc test_num
    jsr clear_target_area
    
    lda #(SPRCTL0_1BPP | SPRCTL0_HFLIP | SPR_BG)
    sta scb_sprctl0
    
    jsr run_sprite
    jsr record_result
    
    ;-------------------------------------------------------------------
    ; TEST 13: With VFLIP added
    ;-------------------------------------------------------------------
    inc test_num
    jsr clear_target_area
    
    lda #(SPRCTL0_1BPP | SPRCTL0_HFLIP | SPRCTL0_VFLIP | SPR_NOCOLL)
    sta scb_sprctl0
    stz scb_sprcoll
    
    jsr run_sprite
    jsr record_result
    
    ;-------------------------------------------------------------------
    ; TEST 14: HSIZ = $0080 (128 = half size)
    ;-------------------------------------------------------------------
    inc test_num
    jsr clear_target_area
    
    lda #(SPRCTL0_1BPP | SPRCTL0_HFLIP | SPR_NOCOLL)
    sta scb_sprctl0
    
    lda #$80                ; HSIZ = $0080
    sta scb_hsiz_lo
    stz scb_hsiz_hi
    
    jsr run_sprite
    jsr record_result
    
    ;-------------------------------------------------------------------
    ; TEST 15: Check different target - offset 79 (pixel 158-159, line 0)
    ;-------------------------------------------------------------------
    inc test_num
    jsr clear_target_area
    
    lda #$FF                ; Restore HSIZ
    sta scb_hsiz_lo
    
    ; This test checks a different address
    ; Result will read from $004F instead of $025F
    
    jsr run_sprite
    jsr record_result_alt79
    
    cli
    rts
.endproc

;===============================================================================
; Initialize Suzy for sprite operations
;===============================================================================
.proc init_suzy
    ; Wait a bit for stabilization
    ldx #0
    ldy #10
@wait:
    dex
    bne @wait
    dey
    bne @wait
    
    ; Initialize Suzy
    lda #$F3
    sta SUZY_SPRINIT
    
    ; Clear offsets
    stz SUZY_HOFFL
    stz SUZY_HOFFH
    stz SUZY_VOFFL
    stz SUZY_VOFFH
    
    ; Collision offset (offset to collision_dep in SCB = 16)
    lda #16
    sta SUZY_COLLOFFL
    stz SUZY_COLLOFFH
    
    ; Size offsets - standard values
    lda #$7F
    sta SUZY_HSIZOFFL
    stz SUZY_HSIZOFFH
    lda #$7F
    sta SUZY_VSIZOFFL
    stz SUZY_VSIZOFFH
    
    ; Enable Suzy bus
    lda #$01
    sta SUZY_SUZYBUSEN
    
    rts
.endproc

;===============================================================================
; Clear the target area at $C000-$CFFF (safe RAM, 4KB buffer)
;===============================================================================
.proc clear_target_area
    ldx #0
    lda #0
@clear:
    sta BUFFER_BASE,x
    sta BUFFER_BASE+$100,x
    sta BUFFER_BASE+$200,x
    sta BUFFER_BASE+$300,x
    sta BUFFER_BASE+$400,x
    sta BUFFER_BASE+$500,x
    sta BUFFER_BASE+$600,x
    sta BUFFER_BASE+$700,x
    dex
    bne @clear
    rts
.endproc

;===============================================================================
; Clear results area
;===============================================================================
.proc clear_results
    ldx #0
    lda #0
@clear:
    sta RESULTS_ADDR,x
    sta RESULTS_ADDR+$100,x
    dex
    bne @clear
    rts
.endproc

;===============================================================================
; Run sprite engine
;===============================================================================
.proc run_sprite
    ; Set SCB address
    lda #<scb
    sta SUZY_SCBNEXTL
    lda #>scb
    sta SUZY_SCBNEXTH
    
    ; Start sprite engine with everon detection
    lda #$05
    sta SUZY_SPRGO
    
    ; Acknowledge and sleep
    stz MIKEY_SDONEACK
    stz MIKEY_CPUSLEEP
    
    ; Wait for completion
@wait:
    lda SUZY_SPRSYS
    and #$01
    bne @wait
    
    rts
.endproc

;===============================================================================
; Record test result (checks $025F)
; Format: 16 bytes per test
;  0: test_id
;  1: target_addr_lo
;  2: target_addr_hi
;  3: value_at_target (THE IMPORTANT ONE)
;  4: collision_depository
;  5: sprctl0
;  6: hpos_lo
;  7: hpos_hi  
;  8: hsiz_lo
;  9: hsiz_hi
; 10: value_at_0000 (collision buffer start)
; 11: value_at_0210 (video buffer start if VIDBAS=$0210)
; 12: value_at_004F (line 0, pixels 158-159)
; 13-15: reserved
;===============================================================================
.proc record_result
    ; Calculate result pointer: RESULTS_ADDR + (test_num-1) * 16
    lda test_num
    sec
    sbc #1
    asl             ; *2
    asl             ; *4
    asl             ; *8
    asl             ; *16
    clc
    adc #<RESULTS_ADDR
    sta result_ptr
    lda #>RESULTS_ADDR
    adc #0
    sta result_ptr+1
    
    ; Store test results
    ldy #0
    lda test_num
    sta (result_ptr),y      ; 0: test_id
    
    iny
    lda #<TARGET_ADDR
    sta (result_ptr),y      ; 1: target_addr_lo
    
    iny
    lda #>TARGET_ADDR
    sta (result_ptr),y      ; 2: target_addr_hi
    
    iny
    lda TARGET_ADDR
    sta (result_ptr),y      ; 3: value_at_target (THE KEY RESULT!)
    
    iny
    lda scb_colldep
    sta (result_ptr),y      ; 4: collision_depository
    
    iny
    lda scb_sprctl0
    sta (result_ptr),y      ; 5: sprctl0
    
    iny
    lda scb_hpos_lo
    sta (result_ptr),y      ; 6: hpos_lo
    
    iny
    lda scb_hpos_hi
    sta (result_ptr),y      ; 7: hpos_hi
    
    iny
    lda scb_hsiz_lo
    sta (result_ptr),y      ; 8: hsiz_lo
    
    iny
    lda scb_hsiz_hi
    sta (result_ptr),y      ; 9: hsiz_hi
    
    iny
    lda BUFFER_BASE
    sta (result_ptr),y      ; 10: value_at_buffer_base
    
    iny
    lda BUFFER_BASE+$210
    sta (result_ptr),y      ; 11: value_at_vidbas
    
    iny
    lda BUFFER_BASE+$4F
    sta (result_ptr),y      ; 12: value_at_buffer+$4F
    
    rts
.endproc

;===============================================================================
; Record result with alternate target ($004F = line 0, pixel 158-159)
;===============================================================================
.proc record_result_alt79
    ; Calculate result pointer
    lda test_num
    sec
    sbc #1
    asl
    asl
    asl
    asl
    clc
    adc #<RESULTS_ADDR
    sta result_ptr
    lda #>RESULTS_ADDR
    adc #0
    sta result_ptr+1
    
    ldy #0
    lda test_num
    sta (result_ptr),y
    
    iny
    lda #<(BUFFER_BASE+$4F) ; Target = buffer+$4F
    sta (result_ptr),y
    
    iny
    lda #>(BUFFER_BASE+$4F)
    sta (result_ptr),y
    
    iny
    lda BUFFER_BASE+$4F     ; Read from buffer+$4F instead
    sta (result_ptr),y
    
    iny
    lda scb_colldep
    sta (result_ptr),y
    
    iny
    lda scb_sprctl0
    sta (result_ptr),y
    
    iny
    lda scb_hpos_lo
    sta (result_ptr),y
    
    iny
    lda scb_hpos_hi
    sta (result_ptr),y
    
    iny
    lda scb_hsiz_lo
    sta (result_ptr),y
    
    iny
    lda scb_hsiz_hi
    sta (result_ptr),y
    
    iny
    lda BUFFER_BASE
    sta (result_ptr),y
    
    iny
    lda BUFFER_BASE+$210
    sta (result_ptr),y
    
    iny
    lda TARGET_ADDR         ; Also record the standard target
    sta (result_ptr),y
    
    rts
.endproc
