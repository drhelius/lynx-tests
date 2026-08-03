# Atari Lynx Timer Guide

Mikey contains eight 8-bit countdown timers. They provide general timing, frame and line timing, UART baud generation, interrupts, and links into the four audio channels.

This guide combines the Epyx/Atari hardware documentation with measurements from the hardware tests in this repository.

## How one timer works

A timer consumes input clocks:

```text
if CNT > 0:
    CNT = CNT - 1
else:
    terminal borrow
```

A starting count of `N` therefore needs `N + 1` input clocks to borrow. Starting at `$02`, the first two clocks produce `$01` and `$00`; the third clock produces the terminal borrow. Zero is a valid count for one complete source period.

At terminal borrow, a timer can:

- Set `DONE`.
- Reload `CNT` from `BKUP`.
- Clock a linked successor.
- Set a pending interrupt bit.
- Trigger timer-specific display or UART work.

Clock selectors 0-6 provide periods of 1, 2, 4, 8, 16, 32, and 64 us. Selector 7 uses the fixed linked predecessor instead.

For a reloading timer with backup `N` and source selector `s`:

$$
T = (N+1)2^s\ \mu s
$$

The longest direct period is `(255 + 1) * 64 us = 16.384 ms`.

The first interval is not perfectly phase-aligned with the CPU. The hardware documentation says first use can take between `N` and `N + 1` source periods. Reloaded intervals take the full `N + 1` periods.

## Timers and links

Each timer occupies four bytes from `$FD00` through `$FD1F`:

| Timer | Address | Linked source | Linked destination | Main use |
|---:|---|---|---|---|
| 0 | `$FD00-$FD03` | None | Timer 2 | Display line timing |
| 1 | `$FD04-$FD07` | Audio 3 | Timer 3 | General timing |
| 2 | `$FD08-$FD0B` | Timer 0 | Timer 4 | Display frame timing |
| 3 | `$FD0C-$FD0F` | Timer 1 | Timer 5 | General timing |
| 4 | `$FD10-$FD13` | Timer 2 | None | UART baud timing |
| 5 | `$FD14-$FD17` | Timer 3 | Timer 7 | General timing |
| 6 | `$FD18-$FD1B` | None | None | Isolated general timer |
| 7 | `$FD1C-$FD1F` | Timer 5 | Audio 0 | General/audio timing |

The complete link chains are:

```text
Timer 0 -> Timer 2 -> Timer 4

Timer 1 -> Timer 3 -> Timer 5 -> Timer 7
    ^                                      |
    |                                      v
Audio 3 <- Audio 2 <- Audio 1 <- Audio 0
```

Timer 0 and Timer 6 have no linked input. Timer 4 and Timer 6 have no linked output.

## The four registers

For timer `n`, the base address is `$FD00 + 4*n`:

| Offset | Register | Purpose |
|---:|---|---|
| `+0` | `TIMnBKUP` | Value loaded after a reload-enabled borrow |
| `+1` | `TIMnCTLA` | Enable, reload, interrupt, reset-done, and source control |
| `+2` | `TIMnCNT` | Current down-counter |
| `+3` | `TIMnCTLB` | Dynamic status and software borrow input |

`BKUP` and `CNT` are independent. Writing `BKUP` does not initialize the current count, so normal setup writes both.

### CTLA: static control

| Bit | Mask | Meaning |
|---:|---:|---|
| 7 | `$80` | Enable this timer's interrupt; Timer 4 is the exception |
| 6 | `$40` | `RESET_DONE`, a level-sensitive DONE clear |
| 5 | `$20` | Legacy `MAGMODE` on odd timers; unused on even timers |
| 4 | `$10` | Reload `CNT` from `BKUP` after borrow |
| 3 | `$08` | Enable counting |
| 2-0 | `$07` | Source selector: 0-6 prescaled, 7 linked |

Do not use bit 5 as spare storage. It belongs to the abandoned magnetic-tape functions on Timers 1, 3, 5, and 7.

### CTLB: dynamic control

| Bit | Mask | Meaning |
|---:|---:|---|
| 3 | `$08` | Sticky `DONE` state |
| 2 | `$04` | Last source-clock state |
| 1 | `$02` | Borrow in / software input clock |
| 0 | `$01` | Borrow out |

The upper nibble is undocumented for ordinary timers and software must not depend on it. Audio CTLB is different; its upper nibble contains the upper LFSR bits.

Writing CTLB bit 1 can inject one input clock. The `CTLB RD/WR` test starts at `CNT=$80`, writes `$0A` (`DONE | BORROW_IN`), and observes `CTLB=$08` and `CNT=$7F`. Bit 1 clocks once but does not remain set.

Avoid read-modify-write instructions on CTLB. Bits 0-2 are hardware-controlled, and writing back a sampled `BORROW_IN=1` can clock the timer. Write a complete `$00` byte when clearing DONE without a software clock.

## Modes and hardware defects

### One-shot

One-shot mode enables count but not reload. After terminal borrow, `CNT` remains zero, `DONE` becomes set, and one interrupt is requested if enabled.

Mikey has an important defect: a non-reloading timer does not count while `DONE` is already set. Always clear CTLB before starting or restarting a one-shot.

To restart safely:

1. Stop the timer.
2. Clear CTLB.
3. Clear its pending interrupt in `INTRST`.
4. Rewrite `BKUP` and `CNT`.
5. Enable the timer.

Clearing DONE while an enabled one-shot remains at zero rearms terminal borrow and can request another interrupt.

### Reload

Reload mode copies `BKUP` to `CNT` after every borrow and continues. `DONE` still becomes set and remains sticky, but it does not stop a reloading timer.

For periodic work, use the interrupt pending bit as the event indicator. `DONE` does not become a new edge unless software clears it after each period.

### RESET_DONE

`CTLA.B6` was intended as a pulse but is implemented as a level. Leaving it high continuously clears DONE. A non-reloading zero-count timer can then attempt borrow and request an interrupt on every source clock.

The preferred DONE clear is a full-byte zero write to CTLB. If `RESET_DONE` must be used, pulse it high and then low. The official safe sequence disables interrupt enable during the high part and restores it when lowering `RESET_DONE`.

### DONE and interrupt pending are separate

CTLB `DONE`, the `INTSET`/`INTRST` pending bit, and CTLA interrupt enable are independent:

- Writing `INTRST` acknowledges the IRQ but does not clear DONE.
- Writing CTLB zero clears DONE but does not acknowledge an IRQ.
- Clearing interrupt enable masks the source but does not erase an existing pending bit.

## Linked timers

A linked timer uses source selector 7 and consumes clocks from its fixed predecessor. The official documentation describes a predecessor reload clocking the successor; current source-side tests also use reload-enabled predecessors.

For two reloading stages with backups `A` and `B` and source period `P`:

$$
T_{linked} = (A+1)(B+1)P
$$

Configure a chain from downstream to upstream:

1. Stop both stages and clear both CTLB registers.
2. Write each `BKUP` and `CNT`.
3. Enable the linked high stage.
4. Enable the free-running source last.

Starting the source last prevents an early borrow before the linked stage is ready.

### 16-bit microsecond counter

Timer 1 can be the low byte and Timer 3 the linked high byte:

```asm
stz TIM1CTLA
stz TIM3CTLA
stz TIM1CTLB
stz TIM3CTLB

lda #$ff
sta TIM1BKUP
sta TIM1CNT
sta TIM3BKUP
sta TIM3CNT

lda #(ENABLE_RELOAD | ENABLE_COUNT | $07)
sta TIM3CTLA
lda #(ENABLE_RELOAD | ENABLE_COUNT | $00)
sta TIM1CTLA
```

This wraps every 65,536 us. Stop Timer 1 before reading both bytes. Elapsed microseconds modulo 65,536 are:

```text
$FFFF - (TIM3CNT << 8 | TIM1CNT)
```

The audio channels use the same basic counter, reload, DONE, and borrow machinery. Audio 3 can clock Timer 1, and Timer 7 can clock Audio 0, completing the second link ring.

## Interrupts

Mikey interrupt bits 7 through 0 are:

```text
Timer 7, Timer 6, Timer 5, UART, Timer 3, Timer 2, Timer 1, Timer 0
```

Timer 4 does not generate a normal timer interrupt. Bit 4 belongs to UART transmit/receive status and is controlled through `SERCTL`.

Read `INTSET` or `INTRST` to poll pending sources. Write ones to `INTRST` to clear selected bits. Writing a sampled mask back to `INTRST` preserves other source bits that arrived later, but pending bits are not counters: repeated events from an already-set source can coalesce.

The timer requests an interrupt when it is already at zero and attempts the next borrow, not when a decrement first reaches zero.

An enabled pending Mikey interrupt wakes or prevents `CPUSLEEP` even when the CPU processor-status interrupt-disable flag is set. The CPU still completes its current cycle before interrupt entry, and a timer interrupt may have to request the bus from Suzy.

## Special timer roles

### Timer 0 and Timer 2: display

The documented setup uses Timer 0 at 1 us with backup 158, linked Timer 2 with backup 104, and `PBKUP=41`. It produces 159 us lines, 102 visible lines, three VBlank lines, and approximately 59.90 FPS.

Timer 0's terminal borrow and interrupt request mark the start of the line, before the leading horizontal non-active interval and active LCD transfer.

Changing Timer 2 changes visible/VBlank lines and FPS. Shortening Timer 0 can recover FPS by trading horizontal non-active time for vertical blank time. See the [Atari Lynx Video Timing Guide](https://github.com/drhelius/lynx-tests/blob/main/lynx-video-timing.md) for LCD transfer, display DMA, PBKUP/P4-H timing, and refresh-rate tuning.

### Timer 4: UART

Timer 4 feeds an additional divide-by-eight UART clock:

$$
baud = \frac{f_{source}}{(BKUP+1)8}
$$

Here, `f_source` is the frequency selected by Timer 4's source bits. Use reload mode and write the same value to `TIM4BKUP` and `TIM4CNT`. With the 1 us source, backups 1, 12, 51, and 103 produce approximately 62500, 9600, 2400, and 1200 baud.

UART interrupts are level-sensitive. Service or disable the UART condition before expecting `INTRST` to remain clear. Before physical REDEYE use, set `SERCTL.TXOPEN=1`; Mikey powers up driving TTL high instead of the required open-collector state.

### Timer 6: isolated timing

Timer 6 has no linked predecessor or successor, so it is the safest general-purpose stopwatch or watchdog. Its longest direct interval is 16.384 ms. For longer delays, count reload interrupts in software or use a linked chain.

## Safe setup recipes

### One-shot Timer 6

This example requests one interrupt after six 4 us periods, subject to initial source phase:

```asm
stz TIM6CTLA
stz TIM6CTLB
lda #TIMER6_INTERRUPT
sta INTRST

lda #$05
sta TIM6BKUP
sta TIM6CNT

lda #(ENABLE_INT | ENABLE_COUNT | $02)
sta TIM6CTLA
```

### Periodic Timer 6

This example produces a steady 1 ms period:

```asm
stz TIM6CTLA
stz TIM6CTLB
lda #TIMER6_INTERRUPT
sta INTRST

lda #249
sta TIM6BKUP
sta TIM6CNT

lda #(ENABLE_INT | ENABLE_RELOAD | ENABLE_COUNT | $02)
sta TIM6CTLA
```

DONE becomes set after the first period and stays set. Acknowledge each observed pending interrupt through `INTRST`.
