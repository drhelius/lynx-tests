# Lynx Hardware Tests

[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/drhelius/lynx-tests/build.yml)](https://github.com/drhelius/lynx-tests/actions/workflows/build.yml)
[![GitHub Releases)](https://img.shields.io/github/v/tag/drhelius/lynx-tests?label=version)](https://github.com/drhelius/lynx-tests/releases)
[![License](https://img.shields.io/github/license/drhelius/lynx-tests)](https://github.com/drhelius/lynx-tests/blob/main/LICENSE)
[![Twitter Follow](https://img.shields.io/twitter/follow/drhelius)](https://x.com/drhelius)

Hardware tests for the Atari Lynx.

## Test Suites

### audio/
**Audio Channel Basic Functionality Tests**

Tests the Atari Lynx audio channels (Channel 0 and Channel 1) focusing on core timer, LFSR (Linear Feedback Shift Register), and integrator behavior.

- **Test 1**: CTLB register read/write and timer decrement behavior
- **Test 2**: One-shot countdown mode with DONE flag polling
- **Test 3**: Reload + integrate mode with LFSR running (captures first 3 outputs and final LFSR state)
- **Test 4**: Maximal-length LFSR taps with non-trivial seed (48 borrows to ensure no short period)
- **Test 5**: Integrator saturation and clipping (ramps to +rail and -rail)
- **Test 6**: Long run with BKUP=$00/CNT=$00 and reload (4096 borrows, dense flow)

### audio2/
**Audio Channel Linking and Hot-Switching Tests**

Tests audio channel linking functionality and dynamic parameter changes without stopping the audio.

- **Test 1**: Audio CH3 → Timer1 link (10 CH3 DONE events should trigger Timer1 DONE)
- **Test 2**: Timer7 → Audio CH0 link (10 Timer7 DONE events should trigger CH0 DONE)
- **Test 3**: Audio chain CH0→CH1→CH2→CH3 propagation (cascading borrows)
- **Test 4**: CH0 free-run prescaler hot-switch (switch from prescaler 6 to 5 on-the-fly)
- **Test 5**: CH0 free-run hot-switch feedback taps (change LFSR taps dynamically)
- **Test 6**: CH0 free-run hot-switch LFSR state (change LFSR value dynamically)
- **Test 7**: CH0 VOL=0 with LFSR active (verify OUT stays at 0 while LFSR advances)

### cpu/
**65C02/65SC02 CPU Tests**

Tests some 65C02-specific behaviors and 65SC02 extensions.

- **Test 1**: SEI/CLI IRQ latency (CLI allows pending IRQ after next instruction completes)
- **Test 2**: D flag cleared on interrupt entry (65C02 behavior, restored after RTI)
- **Test 3**: BCD arithmetic and flags (N/Z flags correct on 65C02, unlike NMOS 6502)
- **Test 4**: BRK is 2 bytes (PC increments by 2, skipping signature byte)
- **Test 5**: JMP (indirect) page boundary fix (65C02 corrects NMOS $xxFF bug)
- **Test 6**: Illegal/reserved opcodes behave as NOP (tests 1-byte, 2-byte, and 3-byte NOPs)
- **Test 7**: 65SC02 RMB/SMB/BBR/BBS instructions (Rockwell/WDC bit manipulation extensions)

### math/
**Hardware Math Coprocessor Tests**

Tests the Atari Lynx hardware multiplier and divider including edge cases and timing.

- **Test 1**: Basic multiplication 
- **Test 2**: Accumulator + overflow multiplication (tests JKLM accumulator with carry)
- **Test 3**: Signed multiplication
- **Test 4**: $8000 multiplication bug test (known hardware bug with sign bit)
- **Test 5**: Simple division with remainder (remainder is broken)
- **Test 6**: Simple division with no remainder
- **Test 7**: Division by zero (should return $FFFFFFFF)
- **Test 8**: Timing tests (measures multiplication and division cycle counts)

### memio/
**Memory-Mapped I/O Register Tests**

Tests read/write functionality of Mikey and Suzy chip registers.

- **Test 1**: Mikey color registers at $FDB0-$FDBF (write/read patterns: $00, $FF, $55, $AA)
- **Test 2**: Suzy registers at $FC00-$FC2F (write/read patterns: $00, $FF, $55, $AA)

### timers/
**Hardware Timer Tests**

Tests the Atari Lynx hardware timers including interrupt generation and linking.

- **Test 1**: CTLB register read/write and timer decrement
- **Test 2**: One-shot timer without interrupts (polls DONE bit)
- **Test 3**: One-shot timer with interrupt generation (counts IRQs)
- **Test 4**: RESET_DONE functionality (level-triggered interrupt behavior)
- **Test 5**: Pre-set DONE bit behavior (prevents timer operation)
- **Test 6**: Timer linking (Timer 5 linked to Timer 3)
- **Test 7**: Reload mode DONE bit behavior

### uart/
**UART Transmission Timing Tests**

Tests UART transmission timing at various baud rates using Timer6 to measure bit timings.

- **Test 1**: Idle → measure until TXEMPTY (11-bit frame transmission time)
- **Test 2**: Idle → measure until TXREADY (holding register ready time)
- **Test 3**: Streaming → measure until TXEMPTY (after warm-up with 8 bytes)
- **Test 4**: Streaming → measure until TXREADY (after warm-up with 8 bytes)
- **Test 5**: Streaming → measure until INT4 (TXRDY IRQ timing)
- **Test 6**: TXBRK → measure until TXREADY when releasing break

Tests at 4 baud rates: 1200, 2400, 9600 and 62500 bps.

### uart2/
**UART Advanced Functionality Tests**

Tests UART parity, error handling, and edge cases.

- **Test 1**: RX overrun detection (2 vs 3 consecutive bytes without reading)
- **Test 2**: Parity modes (PAREN=1 even/odd, PAREN=0 with 9th bit)
- **Test 3**: Dynamic parity changes between frames and during BREAK
- **Test 4**: SERDAT holding register overflow (3 consecutive writes)
- **Test 5**: Interrupt pending behavior (level-triggered + latched)

## Building

Each test directory contains its own Makefile. To build a specific test:

```bash
cd <test-directory>
make
```

The build system uses the [cc65](https://github.com/cc65/cc65) toolchain for 65C02 assembly and produces `.lnx` executable files for the Atari Lynx.

Makefiles need `$CC65_HOME` var already defined in your environment.
