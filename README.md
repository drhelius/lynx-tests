# Lynx Hardware Tests

[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/drhelius/lynx-tests/build.yml)](https://github.com/drhelius/lynx-tests/actions/workflows/build.yml)
[![GitHub Releases](https://img.shields.io/github/v/tag/drhelius/lynx-tests?label=version)](https://github.com/drhelius/lynx-tests/releases)
[![License](https://img.shields.io/github/license/drhelius/lynx-tests)](https://github.com/drhelius/lynx-tests/blob/main/LICENSE)
[![Twitter Follow](https://img.shields.io/twitter/follow/drhelius)](https://x.com/drhelius)

Hardware tests for the Atari Lynx made by analyzing actual hardware.

<img width="500" src="https://github.com/user-attachments/assets/fe0bf130-8203-4683-a1a1-6675abadccfd" />

## Test Suites

Except for `refresh-rate/`, each suite runs its fixed tests once at startup and displays an abbreviated test name followed by its status. Raw diagnostic bytes are shown below the test list.

### audio/
**Audio Channel Basic Functionality Tests**

Tests Atari Lynx Channel 0 timer, LFSR (Linear Feedback Shift Register), and integrator behavior.

- **Test 1 – CTLB RD/WR**: Exercises audio CTLB writes, DONE-bit clearing, and the associated countdown behavior on Channel 0.
- **Test 2 – ONESHOT**: Runs Channel 0 in one-shot mode and checks channel completion, counter termination, and output generation.
- **Test 3 – INTEGRATE**: Runs Channel 0 in reload and integrate mode to track output integration and LFSR progression across successive borrows.
- **Test 4 – MAX LENGTH**: Runs a maximal-length Channel 0 LFSR configuration while tracking sequence progression and repeat detection.
- **Test 5 – CLIPPING**: Drives the Channel 0 integrator toward both limits to observe clipping and recovery behavior.
- **Test 6 – LONG TEST**: Stress-tests Channel 0 over 4096 borrow events while checking counter reload, LFSR evolution, and output consistency.

---

### audio2/
**Audio Channel Linking and Hot-Switching Tests**

Tests audio channel linking functionality and dynamic parameter changes without stopping the audio.

- **Test 1 – LNK CH3 > T1**: Clocks linked Timer 1 from Channel 3 to verify audio-to-timer borrow propagation and countdown cadence.
- **Test 2 – LNK T7 > CH0**: Clocks linked Channel 0 from Timer 7 to verify timer-to-audio borrow propagation and channel updates.
- **Test 3 – LINK CHAIN**: Cascades borrows through Channel 0→Channel 1→Channel 2→Channel 3 to verify a complete linked audio chain.
- **Test 4 – SPEED CHANGE**: Changes the Channel 0 prescaler and integration mode while running to verify a live CTLA reconfiguration.
- **Test 5 – FEEDB CHANGE**: Changes Channel 0 feedback taps and feedback mode while running to verify that subsequent LFSR steps use the new configuration.
- **Test 6 – LFSR CHANGE**: Replaces the Channel 0 LFSR state during operation and checks that waveform generation continues from the new state.
- **Test 7 – VOLUME $00**: Runs Channel 0 with zero volume while tracking output, LFSR, and timer state.

---

### cpu/
**65C02/65SC02 CPU Tests**

Tests some 65C02-specific behaviors and 65SC02 extensions.

- **Test 1 – SEI/CLI**: Makes a Timer 6 IRQ pending while masked, executes CLI, and checks the 65C02 interrupt-entry delay relative to the following instruction.
- **Test 2 – D FLAG IRQ**: Enters a Timer 6 IRQ in decimal mode and checks how the decimal flag is handled on interrupt entry and restored by RTI.
- **Test 3 – BCD MATH**: Exercises decimal-mode addition and subtraction, including carry, zero, and negative flag behavior.
- **Test 4 – BRK 2 BYTES**: Executes BRK followed by a signature byte to examine interrupt return-address handling.
- **Test 5 – JMP IND FIX**: Places an indirect JMP pointer across a page boundary to examine 65C02 high-byte fetch behavior.
- **Test 6 – UNDOC NOPS**: Executes representative one-, two-, and three-byte reserved NOPs and checks PC advancement, registers, and status preservation.
- **Test 7 – RMB/SMB/BBx**: Exercises RMB0, SMB0, BBR0, and BBS0 to characterize their model-specific behavior on Lynx I and Lynx II.
- **Test 8 – UNDC NOP IRQ**: Runs every reserved `$x3` and `$xB` one-byte NOP with an IRQ pending, then compares interrupt timing against a block of official NOPs.

---

### math/
**Hardware Math Coprocessor Tests**

Tests the Atari Lynx hardware multiplier and divider including edge cases and timing.

- **Test 1 – SIMPLE MUL**: Performs an unsigned multiplication and checks the product registers and multiplication status flags.
- **Test 2 – ACCUM MUL**: Accumulates a multiplication near the accumulator rollover boundary and exercises overflow, carry, unsafe, and status-clearing behavior.
- **Test 3 – SIGNED MUL**: Performs signed multiplication followed by a partial operand rewrite to probe the retained CD sign latch.
- **Test 4 – MUL $8000 BUG**: Probes the Suzy multiplier's signed `$8000` edge case.
- **Test 5 – SIMPLE DIV**: Performs an unsigned division and checks quotient, remainder, and divider status handling.
- **Test 6 – NO REM DIV**: Performs an exact unsigned division to exercise the zero-remainder path.
- **Test 7 – DIV BY ZERO**: Starts a division with a zero divisor to exercise divide-by-zero quotient and status behavior.
- **Test 8 – TIMING**: Uses Timer 6 to measure Suzy multiplication and division latency.

---

### memio/
**Memory-Mapped I/O Register Tests**

Tests read/write functionality of Mikey and Suzy chip registers.

- **Test 1 – MIKEY COLORS**: Writes multiple bit patterns across every Mikey color-register offset and exercises blue/red byte width, green nibble width, incrementing, and wraparound.
- **Test 2 – SUZY SPR REGS**: Writes multiple bit patterns across all 48 Suzy sprite registers to verify readback and clearing behavior.

---

### refresh-rate/
**Interactive LCD Timing Configuration**

This is a single interactive utility, not a numbered pass/fail test suite. It displays a checkerboard pattern for checking the display signal bits with a logic analyzer while allowing the LCD timing registers to be changed.

- **Controls**:
  - **A/B buttons**: Increase/decrease Timer 0 backup (0-255). Changing Timer 0 recalculates PBKUP automatically.
  - **Up/down buttons**: Increase/decrease PBKUP directly (0-255). This manual value remains until Timer 0 is changed again.
  - **Left/right buttons**: Decrease/increase Timer 2 backup (0-255), changing the linked vertical period.
  - **Option 1**: Restore T0=158, PBKUP=41, and T2=104.
- **Display**: The first row shows the unlabeled T0 and PBKUP decimal values; the second row shows T2. The utility does not calculate a refresh rate or report pass/fail status.

---

### page-mode/
**CPU Page Mode Timing Tests**

Tests the effect of MAPCTL page mode (bit 7) on CPU instruction timing.

- **Test 1 – NOP PM ON**: Uses Timer 6 to measure a block of one-byte reserved NOPs with page mode enabled.
- **Test 2 – NOP PM OFF**: Repeats the reserved-NOP timing measurement with page mode disabled.
- **Test 3 – LDX PM ON**: Measures repeated immediate loads with page mode enabled.
- **Test 4 – LDX PM OFF**: Repeats the immediate-load timing measurement with page mode disabled.
- **Test 5 – MEM PM ON**: Measures repeated absolute memory reads with page mode enabled.
- **Test 6 – MEM PM OFF**: Repeats the absolute-memory timing measurement with page mode disabled.

---

### sprites1/
**Suzy Literal Source and Scaling Timing Tests**

Tests literal sprite timing across source depths and horizontal scaling.

- **Test 1 – LIT 1B FULL**: Draws an oversized literal 1-bpp background sprite at full horizontal scale to exercise source decoding and right-edge clipping.
- **Test 2 – LIT 2B FULL**: Repeats the full-scale literal sprite test with 2-bpp source data.
- **Test 3 – LIT 3B FULL**: Repeats the full-scale literal sprite test with 3-bpp source data.
- **Test 4 – LIT 4B FULL**: Repeats the full-scale literal sprite test with 4-bpp source data.
- **Test 5 – LIT 1B W20**: Heavily downscales a literal 1-bpp source to exercise fractional horizontal scaling.
- **Test 6 – LIT 4B W20**: Repeats the fractional downscaling test with 4-bpp source data.
- **Test 7 – EXPAND W8**: Expands a single literal 4-bpp source pixel to exercise large horizontal scaling.
- **Test 8 – EXPAND W64**: Repeats the single-pixel expansion with a much larger horizontal scale factor.

---

### sprites2/
**Suzy Alignment, Clipping, and Alpine Protection Tests**

Tests timing and output at horizontal alignment and clipping boundaries.

- **Test 1 – ALIGN 1B X0**: Draws a literal 1-bpp sprite at the left origin to establish baseline source alignment.
- **Test 2 – ALIGN 1B X1**: Moves the same 1-bpp sprite one pixel right to exercise odd horizontal alignment.
- **Test 3 – ALIGN 4B X1**: Repeats odd horizontal alignment with literal 4-bpp source data.
- **Test 4 – CLIP RIGHT**: Places a long sprite at the rightmost visible coordinate to exercise right-edge clipping.
- **Test 5 – CLIP LEFT**: Draws a horizontally flipped long sprite at the left edge to exercise flipped left-edge clipping.
- **Test 6 – SUPER CLIP**: Starts a sprite beyond the right edge to exercise Suzy's horizontal super-clipping path.
- **Test 7 – VCLIP DOWN**: Vertically expands a sprite row at the bottom of the display to exercise downward clipping.
- **Test 8 – ALPINE FLIP**: Runs the Alpine Games protection SCB to exercise fractional horizontal flip mapping at the right edge.

---

### sprites3/
**Suzy Sprite Operation Type Tests**

Runs the same packed 4-bpp, 64-pixel sprite at (0,0), HSIZE=$0100 and VSIZE=$6600, collision number 5, collisions enabled, and depository at SCB+$17 through all eight Suzy operation types. Before every draw, the runner fills the video buffer with $A5 and the collision buffer with $5A. The sprite contains four 16-pixel runs using pens 0, E, F, and 1, so the CRCs verify transparent pixels, shadow pixels, boundary pixels, ordinary pixels, modified data, and preserved data.

- **Test 1 – TYPE BG**: Exercises background operation pen handling and collision replacement.
- **Test 2 – TYPE BGNC**: Exercises non-collidable background operation and collision-buffer preservation.
- **Test 3 – TYPE BSHD**: Exercises boundary-shadow transparency, opaque shadow pens, and collision handling.
- **Test 4 – TYPE BNDY**: Exercises boundary operation transparency and collidable pen handling.
- **Test 5 – TYPE NORM**: Exercises normal sprite transparency, video writes, and collision updates.
- **Test 6 – TYPE NCOL**: Exercises non-collidable sprite drawing and collision-buffer preservation.
- **Test 7 – TYPE XOR**: Exercises XOR video writes together with pen-specific collision handling.
- **Test 8 – TYPE SHDW**: Exercises shadow operation transparency, opaque shadow pens, and collision updates.

---

### sprites4/
**Suzy Packed, Linked, and Display-DMA Timing Tests**

Tests representative packed-data and sprite-list workloads.

- **Test 1 – PACK RLE W32**: Draws two packed 4-bpp RLE packets to exercise short run-length decoding.
- **Test 2 – PACK RLE W64**: Extends the packed RLE workload across four packets to exercise a longer decode path.
- **Test 3 – PACK LIT W64**: Replaces the runs with literal packets to exercise packed literal decoding over the same span.
- **Test 4 – PACK PEN E**: Draws packed pen-E runs with collisions enabled to exercise background-operation collision semantics and the collision depository.
- **Test 5 – PACK XOR F**: Draws packed pen-F runs as an XOR sprite to exercise video XOR, collision writes, and the collision depository.
- **Test 6 – LINK 2 SCB**: Draws two linked packed SCBs to exercise sprite-list traversal and consecutive lines.
- **Test 7 – LINK 4 SCB**: Extends the linked sprite list to four SCBs to exercise longer traversal.
- **Test 8 – DMA EXP W24**: Expands a single literal source pixel while display DMA is active to exercise scaling under bus contention.

---

### sprites5/
**Suzy Zoom, Stretch, and Tilt Tests**

Transforms literal 4-bpp background non-collidable sprites with collisions disabled and the depository at SCB+$1B.

- **Test 1 – ZOOM OUT .5**: Downscales a patterned source in both axes to exercise fractional zoom and source stepping.
- **Test 2 – ZOOM 16X8**: Applies different horizontal and vertical scale factors to one source pixel to exercise asymmetric expansion.
- **Test 3 – STRETCH +.5**: Increases horizontal size on each row to exercise positive fractional stretch accumulation.
- **Test 4 – STRETCH -1**: Decreases horizontal size on each row to exercise negative stretch accumulation.
- **Test 5 – TILT +.5**: Applies positive fractional tilt with no stretch to exercise horizontal row displacement.
- **Test 6 – TILT +1**: Repeats positive tilt with a full-pixel row increment.
- **Test 7 – TILT -1**: Applies negative full-pixel tilt to exercise displacement in the opposite direction.
- **Test 8 – BOTH +1**: Combines positive stretch and tilt to exercise both accumulators together.

---

### timers/
**Hardware Timer Tests**

Tests the Atari Lynx hardware timers including interrupt generation and linking.

- **Test 1 – CTLB RD/WR**: Exercises Timer 3 CTLB writes, DONE-bit clearing, and the associated countdown behavior.
- **Test 2 – ONESHOT**: Runs Timer 3 in one-shot mode without interrupts and checks completion and interrupt isolation.
- **Test 3 – ONESHOT+IRQ**: Runs an interrupt-enabled Timer 3 one-shot and checks its completion interrupt and terminal counter state.
- **Test 4 – RESET-DONE**: Toggles RESET_DONE during repeated Timer 3 interrupts to exercise automatic DONE clearing and transition back to normal one-shot behavior.
- **Test 5 – TDONE BIT**: Starts Timer 3 with DONE pre-set to determine how the bit gates counting and interrupt delivery until cleared.
- **Test 6 – ONESHOT+LINK**: Uses Timer 3 to clock linked Timer 5 and checks borrow propagation into repeated linked interrupts.
- **Test 7 – TDONE RELOAD**: Runs Timer 3 in reload mode and inspects DONE behavior at the first reload interrupt.

---

### uart/
**UART Transmission Timing Tests**

Tests UART transmission timing in source order at 9600, 2400, 1200, and 62500 bps using Timer 4 backup values 12, 51, 103, and 1; Timer 6 measures 64 µs ticks.

- **Test 1 – TXEMPTY IDLE**: Uses Timer 6 to measure a complete UART frame from an idle transmitter until TXEMPTY.
- **Test 2 – TXRDY IDLE**: Measures how soon the UART holding register becomes ready after a write to an idle transmitter.
- **Test 3 – TXEMPTY FULL**: Warms up the transmitter, queues another byte, and measures completion with the transmit pipeline occupied.
- **Test 4 – TXRDY FULL**: Measures holding-register readiness while the transmit pipeline is occupied.
- **Test 5 – TIME TO IRQ**: Enables transmit interrupts and measures TXRDY interrupt latency after clearing the pending interrupt during continuous transmission.
- **Test 6 – TXBRK→TXRDY**: Holds a byte with TXBRK, releases the break condition, and measures the transition back to TXRDY.

---

### uart2/
**UART Advanced Functionality Tests**

Tests UART parity, error handling, and edge cases.

- **Test 1 – OVERRUN ERR**: Uses internal loopback to fill and overflow the receive path, exercising RXRDY and overrun-error behavior.
- **Test 2 – PARITY**: Uses internal loopback to exercise even and odd parity generation, ninth-bit operation without parity, and parity-error detection.
- **Test 3 – SERCTL CHANGE**: Changes parity controls between frames and while TXBRK holds a byte to determine when live SERCTL changes take effect.
- **Test 4 – HOLDING FULL**: Writes multiple bytes while the UART holding register is occupied to exercise its replacement policy and ready/empty transitions while the pipeline drains.
- **Test 5 – IRQ LEVEL**: Manipulates TXINTEN, INTRST, TXRDY, and transmission state to characterize the level-sensitive transmit interrupt.

---

## Building

Each test directory contains its own Makefile. To build a specific test:

```bash
cd <test-directory>
make
```

The build system uses the [cc65](https://github.com/cc65/cc65) C and 65C02 assembly toolchain and produces `.lnx` executable files for the Atari Lynx.

Set `CC65_HOME` to the cc65 installation or source-tree root and ensure `$CC65_HOME/bin` is present in `PATH`.
