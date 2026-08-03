# Atari Lynx Video Timing Guide

The Lynx display is driven by three pieces of timing:

1. **Timer 0** defines one horizontal line.
2. **Timer 2** counts lines and defines the frame and VBlank.
3. **PBKUP** positions the physical `P4/H` pulse used by the LCD drivers.

During each visible line, display DMA fetches pen indices into Mikey. Three sequential driver-clock phases then transfer the left, center, and right parts of the line to three driver ICs on the LCD ribbon.

This guide combines the bundled Epyx/Atari documentation, Lynx II logic-analyzer captures, the [`refresh-rate`](https://github.com/drhelius/lynx-tests/tree/main/refresh-rate) hardware utility, and the timing model in [Gearlynx](https://github.com/drhelius/Gearlynx).

## The standard frame

The normal configuration is:

```text
Timer 0: source = 1 us, backup = 158, reload enabled
Timer 2: source = Timer 0, backup = 104, reload enabled
PBKUP  : 41
```

Timer 0 counts for `158 + 1 = 159 us`, so one line lasts 159 us. Timer 2 counts `104 + 1 = 105` lines, so one frame lasts:

$$
105 \cdot 159\ \mu s = 16.695\ ms
$$

This is approximately 59.90 FPS. The frame contains 102 visible lines and three VBlank lines.

Timer 2 requests the usual frame/VBlank interrupt when it borrows at zero. Visible line 0 begins three complete Timer 0 periods later.

During those three VBlank lines:

1. The first line begins VBlank after visible line 101.
2. The second line continues blanking.
3. The third line latches `DISPADR` into the active display address.
4. The following line begins visible line 0.

The hardware masks the low two bits of `DISPADR`, so software must use a four-byte-aligned display buffer.

REST is high except during the final two VBlank lines and the first visible line. To pass REST to the LCD, configure `IODIR.B3` as an output and set `IODAT.B3=1`.

## One visible line

At the standard setting, one line is 2544 system ticks:

```text
| approximately 39 us non-active | 120 us active LCD transfer |
|----------- 624 ticks ----------|--------- 1920 ticks --------|
|----------------------------- 159 us / 2544 ticks ------------|
```

The active transfer is fixed at 1920 ticks and occurs at the end of the line. Hardware divides it into ten groups of 192 ticks. Each group contains 16 pen indices:

```text
10 groups * 192 ticks = 1920 ticks
10 groups * 16 pens  = 160 pens
```

The leading approximately 39 us interval, the fixed 1920-tick transfer, and the ten 192-tick groups are observed hardware behavior.

This guide calls the leading interval **horizontal non-active time**.

## Display DMA

One display line occupies 80 bytes in RAM. Every byte contains two 4-bit pen indices.

Mikey performs ten display-DMA fetches per visible line. Each fetch reads eight bytes, or 16 pens, into its display buffer. The fetch opportunities are 192 ticks, or 12 us, apart.

```text
10 fetches * 8 bytes = 80 bytes
10 fetches * 16 pens = 160 pens
```

Video has the highest documented bus priority. A display fetch can pause the CPU or request the bus from Suzy. Suzy may continue internal work that does not need RAM.

Fetching pens and transferring them to the LCD are separate but overlapping operations. Each DMA burst fills the next 16-pen group while the LCD clocks consume a group already in Mikey's buffer. Hardware observations place the DMA burst approximately 8-12 ticks after the corresponding pixel-transfer group begins. A framebuffer write affects the line only if it reaches RAM before DMA fetches that group.

LCD transfer begins before the first regular DMA burst of a line. Later visible lines already have their first 16 pens because the preceding line's final DMA opportunity prefetched them. Visible line 0 has no preceding visible line, so hardware performs a one-off fetch at the Timer 0 borrow that starts that line. This hardcoded line-0 fetch loads the first 16 pens before LCD transfer and is not repeated at the start of other visible lines.

## From pens to the LCD

The LCD transfer spans 480 physical triads. Its ribbon carries three driver ICs, each responsible for one spatial block of 160 triads: left, center, then right.

The relevant Mikey pins are:

| Signals | Pins | Purpose |
|---|---|---|
| `P1`, `P2`, `P3`, `P4/H` | 68, 66, 64, 67 | LCD P timing; `P4` is H to the drivers |
| `CLK1`, `CLK2`, `CLK3` | 13, 15, 16 | Left, center, and right driver clocks |
| `D0`, `D1`, `D2`, `D3` | 47, 46, 45, 44 | Four-bit LCD data |

Board hardware duplicates and inverts `CLK1-CLK3`. This produces six complementary waveforms, captured as `CLK A/B1`, `CLK A/B2`, and `CLK A/B3`.

The three phases run sequentially across the line. `CLK1` and its inverted copy transfer the leftmost 160 triads, `CLK2` and its inverted copy transfer the center 160, and `CLK3` and its inverted copy transfer the rightmost 160.

Mikey reads the required pen and palette data shortly before placing each four-bit value on `D0-D3`. After all three phases, the three drivers hold the complete 480-triad line.

## PBKUP and P4/H

Timer 0 fixes the line length. `PBKUP` does not change the line length, active-transfer duration, pixel cadence, or horizontal non-active time. It positions the physical `P4/H` pulse inside that existing line.

The official Epyx formula is:

```text
PBKUP = INT((((line time - 0.5 us) / 15 us) * 4) - 1)
```

Each term has a specific purpose:

- `line time` is the complete Timer 0 period.
- `- 0.5 us` applies the fixed P-timing phase offset. At 16 MHz, this is eight system ticks.
- `/ 15 us * 4` converts the adjusted line time into slots of `15 / 4 = 3.75 us`, or 60 system ticks.
- `- 1` converts the number of slots into an 8-bit backup value because a counter loaded with `N` lasts `N + 1` clocks.
- `INT` discards the fractional part, so PBKUP selects the nearest lower 3.75 us slot rather than representing the line time exactly.

The same calculation is easier to use in system ticks:

```text
P count = floor((line ticks - 8) / 60)
PBKUP  = P count - 1
```

Here, `P count` is `PBKUP + 1`. The quantization remainder is:

```text
remainder = (line ticks - 8) - (P count * 60)
```

It is always between 0 and 59 ticks. The actual Timer 0 line keeps this remainder; only the P4/H timing is placed on the 60-tick grid.

To compare P timing with LCD transfer:

1. Calculate `P count * 60` to obtain the quantized P span.
2. Subtract the fixed 1920-tick active transfer.
3. Compare that result with the actual transfer start, `line ticks - 1920`.

| Rate | Line ticks | `PBKUP` | Quantized pre-transfer timing | Actual transfer start |
|---:|---:|---:|---:|---:|
| 60 Hz | 2544 | 41 | `42 * 60 - 1920 = 600` | 624 ticks |
| 50 Hz | 3040 | 49 | `50 * 60 - 1920 = 1080` | 1120 ticks |
| 75 Hz | 2032 | 32 | `33 * 60 - 1920 = 60` | 112 ticks |

The difference between the last two columns is always:

```text
8-tick phase adjustment + quantization remainder
```

For 60 Hz, the remainder is 16 ticks, so `8 + 16 = 24`: P timing gives 600 ticks and LCD transfer starts at 624. The corresponding differences are 40 ticks at 50 Hz and 52 ticks at 75 Hz.

Changing PBKUP by one changes the P4/H-to-`CLK1` gap by one 60-tick step. Captures measured about 5.41 us and 1.67 us for two adjacent settings; their 3.74 us difference matches the expected 3.75 us step.

PBKUP has a usable window:

- If it is too high, P4/H falls beyond the end of the Timer 0 line and the LCD appears black.
- If it is too low, the P4/H-to-`CLK1` gap becomes too small and visible desynchronization artifacts appear.

The captures do not identify whether the first low-value failure is relative to display DMA, the driver clocks, or internal LCD-driver timing.

The LCD captures also contain a separate board/LCD-side probe labeled `HSYNC`. Mikey has no separate `HSYNC` output pin. In this guide, **H** always means Mikey's physical `P4` pin.

The P signals are electrical LCD-driver timing. They may be related to LCD bias, viewing angle, or contrast, but the available documentation and digital captures do not establish that exact purpose.

## Raster effects and Timer 0

The Timer 0 terminal borrow marks the beginning of the new line and can request the Timer 0 interrupt. The observed order is:

```text
Timer 0 borrow / IRQ request -> horizontal non-active interval -> active LCD transfer
```

At the standard line rate, the interrupt request occurs before the approximately 39 us leading gap. This makes Timer 0 a useful line-start or HBlank-style interrupt source.

The handler does not begin on the exact borrow tick. The CPU finishes its current cycle first, and if Suzy owns the bus, Mikey must request it before CPU interrupt entry. The documented Suzy grant latency can consume up to 40 ticks, or 2.5 us. Interrupt overhead and handler work consume the remaining horizontal non-active time, so software must not assume that all 624 ticks are available.

The active interval is not a hard deadline. Software may continue modifying pixels later in the same line as long as it writes each RAM byte before display DMA fetches the 8-byte group containing it. Once a group is in Mikey's pen buffer, later framebuffer writes cannot change those 16 pens, but they can still affect groups that DMA has not reached.

This makes it possible to race the display: update early groups before active transfer begins, then modify later groups while earlier groups are already being sent to the LCD. Code must remain ahead of the next DMA fetch rather than merely finish before the next Timer 0 borrow.

For reliable raster effects, count from Timer 0 interrupt entry to the first affected DMA or LCD event. Include interrupt and possible bus-grant latency, keep the handler bounded, and validate with display DMA enabled on real hardware.

### LCD and DMA race timeline

Divide the line into ten groups, `G0-G9`, of 16 pixels each. The LCD displays one group while DMA fetches the next one:

```text
Before active transfer:
	G0 is already prefetched.

Start G0:
	LCD displays pixels 0-15.
	8-12 ticks later, DMA fetches G1 (pixels 16-31).

Start G1, 192 ticks after G0:
	LCD displays pixels 16-31.
	8-12 ticks later, DMA fetches G2 (pixels 32-47).

...

Start G9:
	LCD displays pixels 144-159.
	8-12 ticks later, DMA fetches G0 for the next line.
```

The regular DMA burst starts approximately 8-12 ticks after its current LCD group begins. Its data is not used until the following group, almost 192 ticks later.

| LCD currently displays | DMA fetches | Pixels affected by that fetch | Framebuffer deadline |
|---|---|---|---|
| Leading gap | `G0` | 0-15 | Before the line-0 special fetch or previous line's final burst |
| `G0` (pixels 0-15) | `G1` | 16-31 | Before the DMA burst during `G0` |
| `G1` (pixels 16-31) | `G2` | 32-47 | Before the DMA burst during `G1` |
| ... | ... | ... | ... |
| `G8` (pixels 128-143) | `G9` | 144-159 | Before the DMA burst during `G8` |
| `G9` (pixels 144-159) | Next line `G0` | Next line 0-15 | Before the final burst during `G9` |

Visible line 0 gets `G0` from the special Timer 0-borrow fetch. Every later line gets `G0` from the preceding line's final burst.

### Debugging the race in Gearlynx

Gearlynx's debugger includes the **LCD / Video DMA** window for observing this timing. It shows:

- Current frame line, line type, and cycle within the line.
- Number of pixels already transferred.
- Next buffered pen, palette color, pixel cycle, and cycles remaining.
- DMA group count, next RAM address, next DMA cycle, and cycles remaining.

Pause or step the emulator to see which groups have entered Mikey's buffer and how far LCD transfer has advanced. This is useful for checking whether a raster routine writes a group before DMA reaches it.

## Changing VBlank and FPS

Timer 2 backup controls the number of lines in a frame. Three VBlank lines are the minimum for normal visible output. Backups 0-2 do not produce a normal visible frame; backup 3 is the smallest value with one visible line.

- Values above 104 preserve 102 visible lines and add VBlank lines.
- Lower usable values retain three VBlank lines and reduce visible height.

For usable visible configurations with `TIM2BKUP >= 3`:

```text
total lines   = TIM2BKUP + 1
visible lines = min(102, TIM2BKUP - 2)
VBlank lines  = total lines - visible lines
```

This relationship applies across the Timer 2 range.

Adding VBlank lines lengthens the frame and lowers FPS unless Timer 0 is shortened. For example, changing Timer 2 from 104 to 110 creates 111 total lines: 102 visible and nine VBlank.

If the standard 159 us line is retained:

```text
111 lines * 159 us = 17.649 ms = 56.66 FPS
```

You can recover most of the frame rate by shortening Timer 0:

```text
Timer 0 backup = 151  -> 152 us per line
Timer 2 backup = 110  -> 111 lines: 102 visible + 9 VBlank
PBKUP          = 39

111 * 152 us = 16.872 ms = 59.27 FPS
```

This trades horizontal non-active time for vertical blank time. The fixed 120 us active transfer is unchanged; horizontal non-active time falls from 39 us to 32 us.

For a closer 60 Hz result with 111 lines, Timer 0 backup 149 gives 150 us lines and approximately 60.06 FPS. Its matching PBKUP value is 38.

There is a practical limit to this trade: Timer 0 cannot be shortened below the fixed active transfer plus the horizontal timing margin needed by P4/H and the LCD drivers.
