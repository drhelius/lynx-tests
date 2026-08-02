# Atari Lynx CPU Page Mode Guide

This guide explains CPU page mode on the Atari Lynx and how Gearlynx models it.

With page mode enabled, an eligible instruction-byte fetch takes four system ticks instead of five. Opcode bytes and encoded operand bytes both count as instruction bytes. Reads and writes performed by the instruction use normal cycles and interrupt the sequential fetch stream.

## Evidence and scope

Atari's hardware documentation describes the underlying DRAM page mode and the CPU's opcode-decoded optimization. It says that:

- A normal RAM or ROM access takes five ticks.
- A page-mode RAM or ROM read takes four ticks.
- The CPU uses page mode for opcode reads.
- Writes and data reads always use normal cycles.
- The hardware predicts opportunities from the current opcode rather than comparing every complete address.

The official description is useful but not precise enough to implement every boundary and interruption rule. Gearlynx fills those gaps with observations from original hardware.

The main capture is [`lynx2-mikey-page_mode.dsl`](https://github.com/drhelius/Gearlynx/blob/main/tests/logic-analyzer/lynx2-mikey-page_mode.dsl), recorded from a Lynx II with a DSLogic analyzer at 100 MHz. It contains RAS, CAS, the multiplexed address lines A0-A7, system clocks, synchronization signals, and a software-controlled trigger.

Controlled test ROMs complement the capture by changing one property at a time: instruction width, data access, branch direction, target, and operand order. Together they establish the 16-byte boundary, the one-tick saving, and the CPU-side stream interruption rules used by Gearlynx. These are hardware-observed rules. Gearlynx's `stream_open` flag is only a compact software representation of sequential CPU fetching; it does not represent the physical DRAM row.

### Why page mode is faster

Lynx RAM uses multiplexed addresses. A normal access presents the row address with RAS and the column address with CAS. When another access can reuse the open row, the RAM keeps RAS active and cycles CAS for the new column. Avoiding another complete row setup shortens the CPU memory cycle from five ticks to four.

This electrical DRAM page is broader than the set of opportunities the CPU actually uses. Mikey's small opcode-decoded controller deliberately recognizes only safe sequential cases. The sections below describe those observed CPU rules.

## The core rule

Gearlynx treats each opcode or encoded operand fetch as eligible when all three conditions are true:

```text
sequential mode is enabled in MAPCTL
and the instruction stream is already open
and address & $000F is not zero
```

These conditions describe Gearlynx's logical CPU-stream model. Physically, the RAM row must also still be selected. An intervening display DMA or refresh access replaces that row, so the next CPU memory access must use the normal RAS+CAS path.

An eligible fetch saves one tick:

```text
eligible instruction fetch = 4 ticks
normal CPU memory cycle    = 5 ticks
```

At the instruction level, Gearlynx calculates:

```text
CPU ticks = 5 * base CPU cycles - eligible instruction-byte fetches
```

Hardware wait states and bus stalls are added separately. They can make an instruction take longer, but they do not turn data cycles into page-mode cycles.

## What "page" means here

The DRAM documentation discusses a 256-address memory page. The CPU does not exploit every theoretically possible access within that page. Logic-analyzer observations show a narrower pattern for sequential instruction fetching: every 16-byte boundary forces a normal fetch.

```text
Address range       Observed fetch opportunity                Ticks
$2000               normal boundary fetch                     5
$2001-$200F         page mode if the stream is open           4 each
$2010               normal boundary fetch                     5
$2011-$201F         page mode if the stream is open           4 each
```

The boundary fetch does not close the stream. It simply receives no one-tick saving. The following byte can use page mode again.

### Reading the logic-analyzer pattern

The original January 2026 capture notes can be summarized as follows:

- A sequential series of one-byte `$03` NOPs uses the four-tick path for each eligible opcode byte. Each NOP therefore takes 4 ticks, versus 5 ticks with page mode disabled. The first access establishes RAS and takes 5 ticks; subsequent bytes use CAS while the stream remains in the same 16-byte block.
- A sequential series of two-byte instructions such as `LDX #$00` behaves the same way. Both the opcode and its immediate operand are instruction-stream bytes, so the instruction takes `4 + 4 = 8` ticks. It takes 9 ticks if its first byte opens a closed stream or either byte is at `$xxx0`, and 10 ticks with page mode disabled.
- A low-nibble wrap, such as `$043F -> $0440`, requires another RAS access and adds one tick. With an open stream, bytes `$043F`, `$0440`, and `$0441` take `4 + 5 + 4 = 13` ticks. Without the boundary they would take 12 ticks; with page mode disabled they take 15 ticks.

In this context, saying that a sequential series is "always page mode" means every eligible byte after the stream has been opened. The first fetch after an interruption and every address whose low nibble is zero use the normal five-tick path.

## Enabling page mode

`MAPCTL` at `$FFF9` controls the feature:

- Bit 7 clear: sequential page-mode cycles are enabled.
- Bit 7 set: sequential cycles are disabled; no instruction fetch receives the one-tick page-mode saving.

Writes have the same meaning on Lynx I and Lynx II. Reads do not. Both Mikey and Suzy receive writes to `$FFF9`, but only Mikey responds to reads.

### Lynx I and Lynx II readback

Lynx I returns the value written to `MAPCTL`. Lynx II preserves mapping bits 0-3, forces unused bits 4-6 high, and returns bit 7 inverted:

```text
read_value = (written_value | $70) ^ $80
```

Hardware observations give Lynx II `$03 -> $F3` and `$83 -> $73`, while Lynx I returns `$83 -> $83`. Thus written bit 7 is `SEQUENTIAL DISABLE`, but Lynx II read bit 7 behaves as the opposite `HIGH SPEED` status. Why Atari changed the readback is undocumented.

Do not use read-modify-write instructions on `MAPCTL`. On Lynx II the read value has the opposite bit 7, so writing it back can toggle page mode; hardware `TSB` tests exposed exactly this difference. Maintain a software shadow and write the complete intended value.

```asm
; Enable sequential page mode.
lda mapctl_shadow
and #$7f
sta mapctl_shadow
sta MAPCTL

; Disable sequential page mode.
lda mapctl_shadow
ora #$80
sta mapctl_shadow
sta MAPCTL
```

The `MAPCTL` read or write itself is a normal 5-tick data cycle. With `mapctl_shadow` in zero page, no `$xxx0` instruction byte, and no bus stalls, the enable sequence takes 60 ticks from disabled mode; the disable sequence takes 53 ticks from enabled mode with an open stream. `LDA $FFF9` or `STA $FFF9` alone takes 17 ticks with an open stream, 18 with a closed stream, and 20 with page mode disabled.

Writing `MAPCTL` is itself a data write, so the first following instruction fetch is normal. That fetch opens a new instruction stream.

## What contributes to page mode

The CPU can use the faster cycle for bytes fetched from the instruction stream:

- Opcode bytes.
- Immediate values such as the `$AA` in `LDX #$AA`.
- Zero-page address operands.
- The low and high address bytes of absolute operands.
- Relative branch displacements.
- Bytes belonging to consecutive instructions when no intervening operation closes the stream.

The stream persists across instruction boundaries. Gearlynx does not reset page-mode state at the beginning of every instruction.

For example, assume the stream is already open:

```text
$200D  A2   LDX opcode       4 ticks
$200E  AA   immediate value  4 ticks
$200F  A2   LDX opcode       4 ticks
$2010  BB   immediate value  5 ticks: 16-byte boundary
$2011  A2   LDX opcode       4 ticks
$2012  CC   immediate value  4 ticks
```

The three `LDX` instructions take 8, 9, and 8 ticks respectively, or 25 ticks total. With page mode disabled they take 10 ticks each, or 30 ticks total. The boundary at `$2010` costs one extra tick but does not prevent `$2011` from being fast.

## What does not contribute

Page mode does not reduce the cost of:

- Data reads from RAM.
- Data writes to RAM.
- Hardware-register reads or writes.
- Stack reads or writes.
- Indirect pointer reads.
- Read-modify-write data cycles.
- Internal CPU cycles with no instruction-byte fetch.
- Extra cycles charged for a taken branch or a page-crossing branch.
- Mikey display DMA, refresh ownership, or hardware wait states.
- Suzy's own SCB, source, video, or collision memory traffic.

Only CPU instruction-stream fetches receive the one-tick discount. Suzy is a separate bus master and has its own timing rules.

## What interrupts the stream

Gearlynx uses a small `stream_open` state to represent the observed sequence. The following table summarizes when that state is preserved or cleared.

| Event | Effect on the next code fetch | Tick consequence |
|---|---|---|
| First fetch after reset or a closed stream | Normal; opens the stream | Fetch takes 5 ticks |
| Sequential opcode or operand fetch | Preserves the stream | Fetch takes 4 ticks unless at `$xxx0` |
| Fetch at address `$xxx0` | Normal; preserves the stream | Fetch takes 5 ticks |
| CPU data read | Closes the stream | Data read and next code fetch each take 5 ticks |
| CPU data write | Closes the stream | Data write and next code fetch each take 5 ticks |
| Stack read or write | Closes the stream | Each stack access and the next code fetch take 5 ticks |
| Indirect pointer read | Closes the stream | Each pointer read and the next code fetch take 5 ticks |
| Untaken relative branch | Preserves the stream | 8 ticks when both instruction bytes are eligible |
| Taken relative branch with displacement zero | Preserves the stream | 13 ticks when both instruction bytes are eligible |
| Taken relative branch to another address | Closes the stream after fetching the displacement | 13 ticks, or 18 if it crosses a 256-byte CPU page; target fetch takes 5 |
| IRQ or BRK entry | Stack and vector accesses close the stream | Each stack/vector access and first handler fetch take 5 ticks |
| JSR, RTS, or RTI | Stack accesses close the stream | Each stack access and following code fetch take 5 ticks |
| Indirect JMP | Pointer reads close the stream | Each pointer read and target fetch take 5 ticks |
| Direct absolute JMP | Performs no data access; the observed opcode-decoded stream remains open | Three eligible instruction bytes cost 12 ticks within the full instruction |
| Display DMA or refresh access | CPU code path remains logically sequential, but the physical DRAM page is lost | Adds arbitration time; next CPU memory access requires RAS+CAS and takes 5 ticks |

### Data access example

Consider repeated absolute loads:

```asm
lda $2acc                  ; 18 ticks normally, 19 at an operand boundary
lda $2acc                  ; 18 ticks normally, 19 at an operand boundary
lda $2acc                  ; 18 ticks normally, 19 at an operand boundary
```

Each instruction contains four CPU memory cycles:

1. Fetch the `LDA` opcode.
2. Fetch the low address byte `$CC`.
3. Fetch the high address byte `$2A`.
4. Read data from `$2ACC`.

The preceding data read closes the stream, so each opcode takes 5 ticks. Away from a boundary, the two address operands take 4 ticks each and the data read takes 5: `5 + 4 + 4 + 5 = 18` ticks per instruction. An operand at `$xxx0` raises that instruction to 19 ticks. With page mode disabled, all four cycles take 5 ticks and each instruction takes 20 ticks.

Away from a boundary, page mode saves two ticks per repeated `LDA absolute`, not four.

### Branch examples

A branch always fetches its displacement as an instruction byte, even when the branch is not taken.

```asm
bcc skip_load               ; 8 ticks when not taken, 13 when taken
ldx #$11                    ; 8 ticks when the branch is not taken
skip_load:
nop                         ; 4 ticks after fall-through, 5 after taken branch
```

These counts assume an open stream and no instruction byte at `$xxx0`. If `BCC` is not taken, its opcode and displacement cost `4 + 4 = 8` ticks. The following `LDX #$11` and `NOP` remain sequential and cost 8 and 4 ticks, for 20 ticks total.

If `BCC` is taken to the different target, the branch adds one normal 5-tick CPU cycle and takes 13 ticks. Gearlynx then closes the stream, so the target `NOP` takes 5 ticks, for 18 ticks total. A branch crossing a 256-byte CPU page adds another 5 ticks. A `$xxx0` opcode or displacement adds one tick, while page mode disabled gives 10 ticks not taken or 15 ticks taken before any CPU-page-crossing penalty.

There is one useful edge case:

```asm
bcs immediately_after       ; 13 ticks when taken
immediately_after:
nop                         ; 4 ticks because the stream remains open
```

This encodes a displacement of zero. If taken, the branch costs `4 + 4 + 5 = 13` ticks: two instruction fetches and the extra taken-branch cycle. The next `NOP` remains sequential and takes 4 ticks, for 17 ticks total. With page mode disabled the pair takes `15 + 5 = 20` ticks.

On Lynx II, bit branches such as `BBR` and `BBS` have an additional 5-tick data read from zero page. That read closes the stream before the relative displacement is fetched, so the displacement fetch is also 5 ticks and reopens it. With an open initial stream and no boundary, a bit branch takes 23 ticks not taken, 28 ticks taken, or 33 ticks when taken across a 256-byte CPU page. With page mode disabled those totals are 25, 30, and 35 ticks.

## Public test ROM example

The public [`page-mode`](https://github.com/drhelius/lynx-tests/tree/main/page-mode) test performs three matched page-on/page-off measurements. The `CPU ticks per instruction` column below gives system ticks from the CPU timing model. The hexadecimal `Result` columns are Timer 6 counter results from the complete test harness, not system-tick totals. Timer setup and loop alignment add a small common cost, so those result bytes are best used as complete test oracles.

| Workload | CPU ticks per instruction | Result on | Result off | What it demonstrates |
|---|---|---:|---:|---|
| 200 one-byte NOPs | 4 eligible, 5 first/boundary; 5 disabled | `$35` | `$41` | Consecutive opcode bytes use the fast stream except at 16-byte boundaries. |
| 200 `LDX #imm` instructions | 8 eligible, 9 first/boundary; 10 disabled | `$69` | `$81` | Immediate operands participate just like opcode bytes. |
| 100 `LDA absolute` instructions | 18 normally, 19 operand boundary; 20 disabled | `$74-$75` | `$81` | Address operands participate, but each data read is normal and closes the stream. |

The test uses one-byte reserved NOP opcode `$03`, immediate `LDX`, and absolute `LDA`. This combination separates three common mistakes: discounting only opcodes, discounting data reads, and resetting the stream at every instruction boundary.

## How Gearlynx represents the hardware

The complete model is intentionally small:

1. [`Memory::SetMapCtl`](https://github.com/drhelius/Gearlynx/blob/main/src/memory_inline.h) converts `MAPCTL.B7` into a zero- or one-tick discount.
2. [`FetchOpcode8`, `FetchOperand8`, and `FetchOperand16`](https://github.com/drhelius/Gearlynx/blob/main/src/m6502_inline.h) test the open stream and the 16-byte boundary.
3. [`MemRead8` and `MemWrite8`](https://github.com/drhelius/Gearlynx/blob/main/src/m6502_inline.h) close the stream for CPU data traffic.
4. [`OPcodes_Branch`](https://github.com/drhelius/Gearlynx/blob/main/src/m6502_opcodes_inline.h) preserves sequential branch paths and closes nonsequential taken paths.
5. [`RunInstruction`](https://github.com/drhelius/Gearlynx/blob/main/src/m6502_inline.h) subtracts the accumulated discounts from the instruction's normal five-tick CPU cycles.

In simplified pseudocode:

```text
fetch_instruction_byte(address):
    fast = stream_open && ((address & 15) != 0)
    value = read_memory(address)
    stream_open = true
    if sequential_enabled && fast:
        instruction_ticks -= 1
    return value

read_data(address):
    stream_open = false
    return read_memory(address)  // 5-tick CPU data cycle

write_data(address, value):
    stream_open = false
    write_memory(address, value) // 5-tick CPU data cycle
```
