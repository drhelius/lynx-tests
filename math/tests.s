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
    stage: .res 1

;-------------------------------------------------------------------
.segment "CODE"

;===================================================================
; Test 1:
;
;===================================================================
.proc Test1

    stz _g_results + 0
    rts

.endproc

;===================================================================
; Main test runner function
;===================================================================
_run_tests:
    sei                 ; Disable interrupts during testing
    jsr Test1
    cli                 ; Re-enable interrupts
    rts