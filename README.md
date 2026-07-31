# Lynx Hardware Tests

[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/drhelius/lynx-tests/build.yml)](https://github.com/drhelius/lynx-tests/actions/workflows/build.yml)
[![GitHub Releases](https://img.shields.io/github/v/tag/drhelius/lynx-tests?label=version)](https://github.com/drhelius/lynx-tests/releases)
[![License](https://img.shields.io/github/license/drhelius/lynx-tests)](https://github.com/drhelius/lynx-tests/blob/main/LICENSE)
[![Twitter Follow](https://img.shields.io/twitter/follow/drhelius)](https://x.com/drhelius)

Hardware tests for the Atari Lynx made by analyzing actual hardware.

<img width="500" src="https://github.com/user-attachments/assets/fe0bf130-8203-4683-a1a1-6675abadccfd" />

## Test Suites

Except for `refresh-rate/`, each suite runs its fixed tests once at startup and displays an abbreviated test name followed by `PASS` or a numeric failure diagnostic. Raw hexadecimal results are shown below the test list.

### audio/
**Audio Channel Basic Functionality Tests**

Tests the Atari Lynx audio channels (Channel 0 and Channel 1) focusing on core timer, LFSR (Linear Feedback Shift Register), and integrator behavior.

- **Test 1 – CTLB RD/WR**: With CH0 CNT=$40, write CTLB=$0A and expect CTLB=$08 and CNT=$3F; clear CTLB and expect $00.
- **Test 2 – ONESHOT**: Run CH0 one-shot at prescaler 6 with VOL=$7F, taps=$00, LFSR=$101, and BKUP/CNT=$F0; poll DONE and expect CTLB=$08, CNT=$00, and OUT=$7F.
- **Test 3 – INTEGRATE**: Run CH0 reload+integrate at prescaler 6 with VOL=$FF, taps=$00, LFSR=$101, and BKUP/CNT=$F0; expect the first three OUT values $FF/$FE/$FD and final LFSR=$80F.
- **Test 4 – MAX LENGTH**: Run CH0 reload at prescaler 6 with taps=$95, seed=$AB3, VOL=$7F, and BKUP/CNT=$04; reject an early seed repeat across 48 borrows and expect final LFSR=$1ED and OUT=$7F.
- **Test 5 – CLIPPING**: Run CH0 reload+integrate at prescaler 6 with VOL=$1F and BKUP/CNT=$01; force positive steps to the high clamp and negative steps to the low clamp, then expect final OUT=$80.
- **Test 6 – LONG TEST**: Run CH0 reload at prescaler 6 with feedback bit 7, VOL=$3F, taps=$95, seed=$D3A, and BKUP/CNT=$00; require CNT=$00 on all 4096 DONE events and expect final LFSR=$4EB and OUT=$3F.

---

### audio2/
**Audio Channel Linking and Hot-Switching Tests**

Tests audio channel linking functionality and dynamic parameter changes without stopping the audio.

- **Test 1 – LNK CH3 > T1**: CH3 reload at prescaler 6 with BKUP/CNT=$00 clocks linked Timer 1 with BKUP/CNT=$09; Timer 1 DONE must remain clear for nine CH3 DONE events and set on the tenth.
- **Test 2 – LNK T7 > CH0**: Timer 7 reload at prescaler 6 with BKUP/CNT=$00 clocks linked CH0 with BKUP/CNT=$09, VOL=$70, taps=$FF, and seed=$BAA; CH0 DONE must set only on the tenth Timer 7 DONE and OUT must change to $70.
- **Test 3 – LINK CHAIN**: CH0 reload at prescaler 6 clocks linked CH1→CH2→CH3; CH0–CH2 use BKUP/CNT=$00 and CH3 uses $09, so CH3 DONE and OUT=$10 are expected on the tenth CH0 DONE.
- **Test 4 – SPEED CHANGE**: CH0 starts in reload+integrate mode at prescaler 6 with VOL=$03, taps=$FF, seed=$B5A, and BKUP/CNT=$00; after 50 DONE events OUT must be $00, then CTLA switches to reload mode at prescaler 5, disabling integration, and OUT must be $FD after one DONE event.
- **Test 5 – FEEDB CHANGE**: CH0 reload+integrate at prescaler 6 with VOL=$03, seed=$944, taps=$77, and BKUP/CNT=$00; after 50 DONE events OUT must be $EE, then taps change to $55 with feedback bit 7 enabled and OUT must be $EB after one DONE event.
- **Test 6 – LFSR CHANGE**: CH0 reload+integrate at prescaler 6 with VOL=$03, taps=$11, seed=$944, and BKUP/CNT=$00; after 50 DONE events OUT must be $D0, then the LFSR changes to $611 and OUT must be $D3 after one DONE event.
- **Test 7 – VOLUME $00**: CH0 reload+integrate at prescaler 6 with VOL=$00, taps=$B4, seed=$7A5, and BKUP/CNT=$00; OUT must remain $00 across 16 DONE events and the final LFSR low byte must be $2B.

---

### cpu/
**65C02/65SC02 CPU Tests**

Tests some 65C02-specific behaviors and 65SC02 extensions.

- **Test 1 – SEI/CLI**: With a Timer 6 IRQ pending, CLI must execute the following INC before entering the handler; expect the zero-page value to become $01, at least one IRQ, and result $00.
- **Test 2 – D FLAG IRQ**: Enter a Timer 6 IRQ with the decimal flag set; expect D clear inside the handler, restored after RTI, and result $00.
- **Test 3 – BCD MATH**: Expect $29+$23=$52, $29-$23=$06, carry set after $85+$25=$10, zero set after $99+$01=$00, and negative set after $40+$41=$81.
- **Test 4 – BRK 2 BYTES**: Execute BRK,$EA and expect the $EA signature byte to be skipped, producing result $02. The companion $30 B/unused-bit result is hardcoded and does not inspect the pushed status.
- **Test 5 – JMP IND FIX**: JMP ($30FF) must use the low byte at $30FF and high byte at $3100 to reach $3200; expect $BB rather than the NMOS-wrapped $66 target from $3000/$3300.
- **Test 6 – UNDOC NOPS**: Reserved opcodes $5B, $44 $00, and $5C $FF $FF must act as 1-, 2-, and 3-byte NOPs, preserving A/X/Y and all status bits except masked B/unused bits; expect progress $03 and error $00.
- **Test 7 – RMB/SMB/BBx**: RMB0 changes $FF→$FE, SMB0 changes $00→$01, BBR0 branches for $FE, and BBS0 branches for $01; expect $FE/$01/$01/$01.
- **Test 8 – UNDC NOP IRQ**: Execute each of the 32 reserved $x3/$xB one-byte NOPs five times with an IRQ pending and require servicing only after the following INX; as a control, require an IRQ within 100 official $EA NOPs. Expect results $00/$00.

---

### math/
**Hardware Math Coprocessor Tests**

Tests the Atari Lynx hardware multiplier and divider including edge cases and timing.

- **Test 1 – SIMPLE MUL**: Unsigned $0002×$00FF must produce EFGH=$000001FE and SPRSYS & $64=$04 (unsafe set, no overflow/carry).
- **Test 2 – ACCUM MUL**: Multiply $0010×$0010=$00000100 and add it to JKLM=$FFFFFFF0; expect $000000F0, status $64 with overflow/last-carry/unsafe set, then $24 after clearing overflow.
- **Test 3 – SIGNED MUL**: Expect signed $FFFD×$0005=$FFFFFFF1; then write only MATHD and multiply $0003×$0005, expecting the stale negative CD-sign latch to preserve $FFFFFFF1, with initial status $24.
- **Test 4 – MUL $8000 BUG**: Signed $8000×$0002 must reproduce the hardware bug, yielding positive EFGH=$00010000 instead of -$10000, with SPRSYS & $64=$04.
- **Test 5 – SIMPLE DIV**: Divide $00010000 by $000A; expect quotient ABCD=$00001999 and status $24. The remainder bytes J/K/L are checked as $00; MATHM reads $06, but its comparison is disabled.
- **Test 6 – NO REM DIV**: Divide $0000FFFF by $00FF; expect quotient ABCD=$00000101, remainder JKLM=$00000000, and SPRSYS & $64=$04.
- **Test 7 – DIV BY ZERO**: Divide $00001234 by $0000; expect quotient ABCD=$FFFFFFFF with divide-by-zero/last-carry/unsafe status $64.
- **Test 8 – TIMING**: Timer 6 must measure 5–7 ticks for $0002×$FFFF and exactly 16 ticks for $12345678/$1234.

---

### memio/
**Memory-Mapped I/O Register Tests**

Tests read/write functionality of Mikey and Suzy chip registers.

- **Test 1 – MIKEY COLORS**: Across all 16 offsets, Blue/Red $FDB0-$FDBF must round-trip $00/$FF/$55/$AA, increment $0F→$10, and wrap $FF→$00; 4-bit Green $FDA0-$FDAF must read $00/$0F/$05/$0A and wrap $0F→$00.
- **Test 2 – SUZY SPR REGS**: All 48 Suzy registers at $FC00-$FC2F must round-trip $00/$FF/$55/$AA at every offset, then be reset to $00.

---

### refresh-rate/
**Interactive LCD Timing Configuration**

This is a single interactive utility, not a numbered pass/fail test suite. It displays a checkerboard while allowing the LCD timing registers to be changed.

- **Controls**:
  - **A/B buttons**: Increase/decrease Timer 0 backup (0-255). Changing Timer 0 recalculates PBKUP automatically.
  - **Up/down buttons**: Increase/decrease PBKUP directly (0-255). This manual value remains until Timer 0 is changed again.
  - **Left/right buttons**: Decrease/increase Timer 2 backup (0-255), changing the linked vertical period.
  - **Option 1**: Restore T0=158, PBKUP=41, and T2=104.
- **Display**: The first row shows the unlabeled T0 and PBKUP decimal values; the second row shows T2. The utility does not display a calculated refresh rate or a pass/fail result.

---

### page-mode/
**CPU Page Mode Timing Tests**

Tests the effect of MAPCTL page mode (bit 7) on CPU instruction timing.

- **Test 1 – NOP PM ON**: With MAPCTL bit 7 clear (page mode on), execute 200 one-byte $03 NOPs; expect Timer 6 elapsed count $35.
- **Test 2 – NOP PM OFF**: With MAPCTL bit 7 set (page mode off), execute 200 one-byte $03 NOPs; expect Timer 6 elapsed count $41.
- **Test 3 – LDX PM ON**: With page mode on, execute LDX #$AA 200 times; expect Timer 6 elapsed count $69.
- **Test 4 – LDX PM OFF**: With page mode off, execute LDX #$EE 200 times; expect Timer 6 elapsed count $81.
- **Test 5 – MEM PM ON**: With page mode on, execute LDA $2ACC 100 times; expect Timer 6 elapsed count $74 or $75.
- **Test 6 – MEM PM OFF**: With page mode off, execute LDA $2ECC 100 times; expect Timer 6 elapsed count $81.

---

### sprites1/
**Suzy Literal Source and Scaling Timing Tests**

Tests literal sprite timing across source depths and horizontal scaling.

- **Test 1 – LIT 1B FULL**: Draw a literal 1-bpp background non-collidable sprite containing 167 pen-1 source pixels at (0,0), HSIZE=$0100 and VSIZE=$6600; the first 160 pixels are visible. Collisions are disabled.
- **Test 2 – LIT 2B FULL**: Draw a literal 2-bpp background non-collidable sprite containing 163 pen-3 source pixels at (0,0), HSIZE=$0100 and VSIZE=$6600; 160 pixels are visible.
- **Test 3 – LIT 3B FULL**: Draw a literal 3-bpp background non-collidable sprite containing 162 pen-7 source pixels at (0,0), HSIZE=$0100 and VSIZE=$6600; 160 pixels are visible.
- **Test 4 – LIT 4B FULL**: Draw a literal 4-bpp background non-collidable sprite containing 161 pen-1 source pixels at (0,0), HSIZE=$0100 and VSIZE=$6600; 160 pixels are visible.
- **Test 5 – LIT 1B W20**: Downscale the 167-pixel literal 1-bpp source at (0,0) with HSIZE=$0020 and VSIZE=$6600 to 20 visible pixels.
- **Test 6 – LIT 4B W20**: Downscale the 161-pixel literal 4-bpp source at (0,0) with HSIZE=$0020 and VSIZE=$6600 to 20 visible pixels.
- **Test 7 – EXPAND W8**: Expand one literal 4-bpp source pixel at (0,0), HSIZE=$0800 and VSIZE=$6600, to 8 pixels.
- **Test 8 – EXPAND W64**: Expand one literal 4-bpp source pixel at (0,0), HSIZE=$4000 and VSIZE=$6600, to 64 pixels.

---

### sprites2/
**Suzy Alignment, Clipping, and Alpine Protection Tests**

Tests timing and output at horizontal alignment and clipping boundaries.

- **Test 1 – ALIGN 1B X0**: Draw a 23-pixel literal 1-bpp background non-collidable sprite at X=0, HSIZE=$0100 and VSIZE=$6600. Collisions are disabled.
- **Test 2 – ALIGN 1B X1**: Draw the same 23-pixel literal 1-bpp sprite at X=1.
- **Test 3 – ALIGN 4B X1**: Draw a 23-pixel literal 4-bpp background non-collidable sprite at X=1, HSIZE=$0100 and VSIZE=$6600.
- **Test 4 – CLIP RIGHT**: Draw a 159-pixel literal 1-bpp sprite at X=159 so only its first pixel remains visible at X=159.
- **Test 5 – CLIP LEFT**: Draw an HFLIP 159-pixel literal 1-bpp sprite at X=0 so only its first pixel remains visible at X=0.
- **Test 6 – SUPER CLIP**: Start a 159-pixel literal 1-bpp sprite at X=160 so it is fully horizontally super-clipped.
- **Test 7 – VCLIP DOWN**: Draw a 15-pixel literal 1-bpp row at (0,101), HSIZE=$0100 and VSIZE=$0400, expanding downward to four rows; only Y=101 remains visible.
- **Test 8 – ALPINE FLIP**: Run Alpine Games' literal 1-bpp HFLIP non-collidable protection SCB at X=163 with HSIZE=$00FF, VSIZE=$0300, and HSIZOFF=$007F; the third pen-1 pixel must map to color 5 at X=159.

---

### sprites3/
**Suzy Sprite Operation Type Tests**

Runs the same packed 4-bpp, 64-pixel sprite at (0,0), HSIZE=$0100 and VSIZE=$6600, collision number 5, collisions enabled, and depository at SCB+$17 through all eight Suzy operation types. Before every draw, the runner fills the video buffer with $A5 and the collision buffer with $5A. The sprite contains four 16-pixel runs using pens 0, E, F, and 1, so the CRCs verify transparent pixels, shadow pixels, boundary pixels, ordinary pixels, modified data, and preserved data.

- **Test 1 – TYPE BG**: All pens overwrite video; pens 0, F, and 1 replace collision cells while pen E preserves them.
- **Test 2 – TYPE BGNC**: All pens overwrite video and the complete collision buffer remains unchanged.
- **Test 3 – TYPE BSHD**: Pens 0/F are transparent, pen E is opaque but non-collidable, and pens F/1 update collisions.
- **Test 4 – TYPE BNDY**: Pens 0/F are transparent while pens E/F/1 update collisions.
- **Test 5 – TYPE NORM**: Pen 0 is transparent and pens E/F/1 overwrite video and update collisions.
- **Test 6 – TYPE NCOL**: Pen 0 is transparent, pens E/F/1 overwrite video, and collisions remain unchanged.
- **Test 7 – TYPE XOR**: Pens E/F/1 XOR the existing video, pen E preserves collision cells, and pens F/1 update collisions.
- **Test 8 – TYPE SHDW**: Pen 0 is transparent, pen E is opaque but non-collidable, and pens F/1 overwrite video and update collisions.

---

### sprites4/
**Suzy Packed, Linked, and Display-DMA Timing Tests**

Tests representative packed-data and sprite-list workloads.

- **Test 1 – PACK RLE W32**: Draw a packed 4-bpp background non-collidable sprite with two 16-pixel RLE packets, producing 32 pixels at (0,0), HSIZE=$0100 and VSIZE=$6600. Collisions are disabled.
- **Test 2 – PACK RLE W64**: Draw four 16-pixel RLE packets, producing 64 pixels.
- **Test 3 – PACK LIT W64**: Draw four 16-pixel literal packets in packed mode, producing 64 pixels.
- **Test 4 – PACK PEN E**: Draw four 16-pixel pen-E RLE packets as a background-operation sprite with collision number 5 and collisions/depository enabled.
- **Test 5 – PACK XOR F**: Draw four 16-pixel collidable pen-F RLE packets as an XOR sprite with collision number 5 and collisions/depository enabled.
- **Test 6 – LINK 2 SCB**: Draw two linked packed 4-bpp, 64-pixel background non-collidable SCBs at Y=0 and Y=1, each HSIZE/VSIZE=$0100.
- **Test 7 – LINK 4 SCB**: Draw four equivalent linked SCBs at Y=0–3.
- **Test 8 – DMA EXP W24**: Expand one literal 4-bpp source pixel at (0,0), HSIZE=$1800 and VSIZE=$6600, to 24 pixels while display DMA is enabled.

---

### sprites5/
**Suzy Zoom, Stretch, and Tilt Tests**

Transforms literal 4-bpp background non-collidable sprites with collisions disabled and the depository at SCB+$1B.

- **Test 1 – ZOOM OUT .5**: Draw a patterned 17×16 source at (76,47), HSIZE=VSIZE=$0080, producing an 8×8 half-scale result.
- **Test 2 – ZOOM 16X8**: Expand one source pixel at (72,47), HSIZE=$1000 and VSIZE=$0800, into a 16×8 rectangle.
- **Test 3 – STRETCH +.5**: Draw a one-pixel source at (68,47), initial HSIZE/VSIZE=$0800, with horizontal stretch +$0080 per row.
- **Test 4 – STRETCH -1**: Draw a one-pixel source at (68,47), initial HSIZE=$0F00 and VSIZE=$0800, with horizontal stretch -$0100 per row.
- **Test 5 – TILT +.5**: Draw a one-pixel source at (72,47), HSIZE/VSIZE=$0800, zero stretch, and tilt +$0080 per row.
- **Test 6 – TILT +1**: Use the same source and size with tilt +$0100 per row.
- **Test 7 – TILT -1**: Use the same source and size with tilt -$0100 per row.
- **Test 8 – BOTH +1**: Draw a one-pixel source at (68,47), initial HSIZE/VSIZE=$0800, with stretch +$0100 and tilt +$0100 per row.

---

### timers/
**Hardware Timer Tests**

Tests the Atari Lynx hardware timers including interrupt generation and linking.

- **Test 1 – CTLB RD/WR**: With Timer 3 CNT=$80, write CTLB=$0A and expect low CTLB=$08 and CNT=$7F; clear CTLB and expect $00.
- **Test 2 – ONESHOT**: Run Timer 3 one-shot at prescaler 6 with BKUP/CNT=$F0 and interrupts disabled; poll DONE and expect CTLB=$08 with INTSET=$00.
- **Test 3 – ONESHOT+IRQ**: Run Timer 3 one-shot at prescaler 1 with BKUP/CNT=$05 and interrupts enabled; expect exactly one IRQ, DONE=$08, and CNT=$00.
- **Test 4 – RESET-DONE**: Run Timer 3 one-shot at prescaler 2 with interrupts and RESET_DONE enabled; clear repeated IRQs, remove RESET_DONE after four IRQs, and expect 4–5 total IRQs, DONE=$08, explicit CTLB clearing to $00, and timeout remainder $35–$37.
- **Test 5 – TDONE BIT**: Pre-set Timer 3 DONE with BKUP/CNT=$05, interrupts enabled, and prescaler 2; expect no IRQ while DONE is set and one IRQ after clearing DONE.
- **Test 6 – ONESHOT+LINK**: Timer 3 reloads from $10 at prescaler 2 and clocks linked Timer 5 with BKUP/CNT=$00, RESET_DONE, and interrupts enabled; expect 13 Timer 5 IRQs during $C0 poll iterations.
- **Test 7 – TDONE RELOAD**: Run Timer 3 reload mode at prescaler 4 with BKUP/CNT=$FF and interrupts enabled; on the first reload IRQ, expect DONE=$08.

---

### uart/
**UART Transmission Timing Tests**

Tests UART transmission timing in source order at 9600, 2400, 1200, and 62500 bps using Timer 4 backup values 12, 51, 103, and 1; Timer 6 measures 64 µs ticks.

- **Test 1 – TXEMPTY IDLE**: From an idle SERDAT=$A5 write, measure until TXEMPTY after the 11-bit frame; expect Timer 6 ticks $14–$15/$53–$54/$A9–$AA/$03–$04.
- **Test 2 – TXRDY IDLE**: From an idle SERDAT=$A5 write, measure until TXRDY indicates that the holding register is ready; expect $02–$04/$0D–$0E/$1A–$1B/$01–$02.
- **Test 3 – TXEMPTY FULL**: After eight TXRDY-paced warm-up bytes, time a ninth SERDAT=$A5 write until TXEMPTY; expect $24–$25/$8F–$90/$1E–$1F/$06–$07.
- **Test 4 – TXRDY FULL**: After eight TXRDY-paced warm-up bytes, time a ninth write until TXRDY; expect $12–$13/$48–$49/$8F–$90/$03–$04.
- **Test 5 – TIME TO IRQ**: With TXINTEN set, after eight warm-up bytes clear INT4 after the ninth write and time until the next TXRDY interrupt; expect $12–$13/$48/$8F–$90/$03–$04.
- **Test 6 – TXBRK→TXRDY**: Hold SERDAT=$A5 while TXBRK is set, release TXBRK, and time until TXRDY; expect $02–$04/$46–$47/$8F–$90/$03–$04.

---

### uart2/
**UART Advanced Functionality Tests**

Tests UART parity, error handling, and edge cases.

- **Test 1 – OVERRUN ERR**: At 9600-bps internal loopback, send two bytes without reading and expect RXRDY=1 with OVRERR=0; repeat with three bytes and expect RXRDY=1 with OVRERR=1.
- **Test 2 – PARITY**: At 9600-bps loopback, verify PAREN=1 even/odd parity using $55 and $01 with the correct PARBIT and no PARERR; with PAREN=0, verify that the ninth bit equals PAREVEN for 0 and 1 and validate mismatch PARERR behavior.
- **Test 3 – SERCTL CHANGE**: At 9600-bps loopback, verify PAREVEN 1→0 and PAREN 1→0 changes between frames, then repeat both changes while TXBRK holds a byte; the released frame must use the new setting, with no premature RXRDY, correct PARBIT, and no spurious PARERR.
- **Test 4 – HOLDING FULL**: At 9600-bps loopback, transmit $11, then write $22 and $33 while the holding register is occupied; $33 must replace $22, exactly $11/$33 must be received, RXRDY must clear after draining, and TXEMPTY/TXRDY must finish set.
- **Test 5 – IRQ LEVEL**: At 9600 bps with TXINTEN enabled and idle TXRDY=1, verify that INT4 immediately relatches after INTRST, remains pending when transmission starts and ends and SERDAT is read, and clears through INTRST while TXRDY=0.

---

## Building

Each test directory contains its own Makefile. To build a specific test:

```bash
cd <test-directory>
make
```

The build system uses the [cc65](https://github.com/cc65/cc65) C and 65C02 assembly toolchain and produces `.lnx` executable files for the Atari Lynx.

Set `CC65_HOME` to the cc65 installation or source-tree root and ensure `$CC65_HOME/bin` is present in `PATH`.
