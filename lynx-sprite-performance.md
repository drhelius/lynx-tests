# Lynx Sprite Performance Guide

This guide explains how to organize Atari Lynx sprite work for maximum real-hardware performance. It combines Atari's documented Suzy architecture with focused measurements from original Lynx I and Lynx II systems. The purpose is not merely to list which benchmark was faster, but to explain which internal process became the bottleneck and how a developer can change that process deliberately.

Projects referenced by this guide:

- [Gearlynx](https://github.com/drhelius/Gearlynx) is the Atari Lynx emulator whose accurate renderer implements the observation-driven FSM and timing model discussed below.
- [lynx-tests](https://github.com/drhelius/lynx-tests) contains the public hardware test ROMs, including the `sprites1` through `sprites5` suites used throughout this guide.

The detailed timing model described here is necessarily an approximation. Atari documented the major storage elements, buses, and rendering operations, but not a complete cycle-by-cycle state diagram of the production silicon. Gearlynx reconstructs that missing behavior from the hardware documentation, logic-analyzer captures, controlled test ROMs, and complete game workloads. Its accurate renderer is an explicit finite-state machine whose timing rules are continuously checked against real hardware. It is not claimed to be a transistor-level representation of Suzy, and some internal overlap is represented by measured readiness frontiers rather than by simulating every physical latch. The recommendations in this guide are based on the real-hardware observations behind that model, not on values tuned only to make Gearlynx faster or slower.

All timings are system ticks or microseconds unless explicitly labeled otherwise. Suzy runs from the 16 MHz system clock, so one microsecond is 16 ticks. Absolute microsecond totals include a small benchmark harness cost; comparisons within the same table are the useful part.

### Evidence and scope

This guide uses three distinct kinds of evidence:

- **Official behavior** comes from the bundled Atari hardware and programming documents. It defines registers, SCB fields, source records, operation semantics, FIFO sizes, bus priorities, and required software protocols.
- **Measured behavior** comes from controlled real-Lynx test ROMs. These measurements identify timing slopes, overlap, tails, and practical optimization effects that Atari did not document cycle by cycle.
- **Gearlynx model details** explain how the accurate renderer approximates those observations. They are useful for understanding and profiling, but they are not assertions that production silicon contains identical software-visible phases or counters.

## The rule that matters most

Suzy is a pipeline. A row does not take the sum of every source, scaling, video, and collision cost. Those processes overlap, and the row completes when the slowest exposed path completes:

```text
row time ~= max(source/decode, pixel builder, RAM bus, collision)
           + operation-specific downstream work
           + exposed row-end work
           + exposed LCD arbitration
```

A **frontier** is the earliest tick at which one path has finished everything the row needs from it. Suppose source/decode becomes ready at tick 394 while the video merger becomes ready at tick 250. The row waits until tick 394; it does not take `394 + 250` ticks because both paths were working at the same time. Reducing merger work from 250 to 200 changes nothing. Reducing source work below 250 makes the merger the new bottleneck. Only work that must happen after that race, such as XOR processing or an exposed row tail, is added afterward.

Optimization therefore means reducing the dominant frontier:

- Reducing source bytes helps a source-bound row.
- Reducing output pixels helps a video-merger-bound row.
- Disabling collision helps a collision-bound row.
- Shortening one path does nothing if another path is already slower.
- A smaller encoded sprite is not necessarily a faster sprite.

This explains many results that otherwise look contradictory. A 161-pen 4-bpp source downscaled to 20, 40, 60, or 80 outputs stayed near 394 ticks per warm row because source processing dominated all four widths. A one-pen source expanded to many outputs followed a very different path, close to `72 + 2 * outputs` ticks per warm row, because almost all source work disappeared and the output path became dominant.

XOR is the clearest exception to a pure maximum-frontier model. Its destination-dependent byte operation runs downstream of the normal source/video/collision frontier, so its measured form is approximately:

```text
xor row time ~= max(bus, source, collision)
                 + 2 * ceil(outputs / 2)
                 + optional complete-byte terminal work
```

## Inside Suzy

To render a list, the CPU gives Suzy the video-buffer address and the address of the first Sprite Control Block, starts the sprite process through `SPRGO`, and sleeps. The previous Suzy wakeup must also be acknowledged through `SDONEACK`. Atari's earlier launch list places this write after `SPRGO`, while its later Common Errors section requires acknowledgement before running the engine, including first use. The conservative protocol is described under correctness requirements below. Sleeping is essential: Suzy shares system RAM with the CPU and Mikey, and it cannot make normal progress while the CPU retains the bus. An interrupt may wake the CPU before Suzy is finished; in that case software services the interrupt and sleeps again until the active bit in `SPRSYS` clears.

Suzy begins by reading the first five bytes of the SCB: the two control bytes, collision control, and the link to the next SCB. The skip decision is made after those reads. For an active sprite, Suzy continues through the source pointer and position fields, conditionally reloads size, stretch, and tilt, and may load the eight-byte pen-index palette. These values define how source data is interpreted, where the reference point lies, which quadrant is visited first, and which direction each quadrant paints.

The source pointer addresses a sequence of records. Each record starts with a byte offset to the next record: zero ends the sprite, one changes quadrant, and larger values delimit a source row. For a drawable row, vertical scaling determines how many destination rows are generated. Suzy then fetches source bytes, decodes source indices, maps them through the SCB palette, applies horizontal scaling, and sends generated pens toward the framebuffer and collision machinery. A source pen can produce no output when downscaled, one output at normal scale, or many outputs when expanded. At the end of each generated row, Suzy advances vertical position and the stretch and tilt accumulators before continuing the same source record, fetching the next record, changing quadrant, or completing the sprite.

Video output is not written as an isolated CPU-style store for every pixel. Suzy assembles 4-bit pens into destination bytes and buffers words before the merger accesses RAM. The selected operation type and pen decide whether existing video must be read, whether new video is written, and whether collision RAM is preserved, cleared, or read/compared/written. Consequently, two sprites with identical dimensions can have very different costs: an opaque `BACKNONCOLL` row may be write-only, a mixed transparent row may require video reads and writes, and a `NORMAL` row can add collision detect/write traffic over the same pixels.

These activities are performed by cooperating hardware stages:

1. The address unit fetches the SCB and source data.
2. Source data enters an 8-byte FIFO in 4-byte chunks.
3. A 12-bit shift register unpacks literal indices or packed packets.
4. The pen-index palette maps each source index to a 4-bit display pen.
5. Horizontal and vertical accumulators generate destination pixels and rows.
6. The pixel byte builder combines two 4-bit destination pixels per byte.
7. An 8-word pixel FIFO buffers generated output.
8. The video merger reads, writes, or read-modify-writes framebuffer RAM.
9. The collision unit reads, compares, preserves, or writes collision RAM.
10. Mikey display DMA periodically takes ownership of RAM while Suzy can continue only work that does not require the bus.

The stages are interleaved rather than executed as ten serialized steps. While one source chunk is being unpacked, earlier pens can be scaled and assembled; while the builder continues, a previous group can use the RAM bus. A source refill can therefore be completely hidden behind merger work, or it can become visible when the source path is already the slowest path. Mikey display DMA introduces another dependency: Suzy may continue internal work already resident in its FIFOs while Mikey owns RAM, but source fetches and destination accesses must wait.

Think of the FIFOs as reservoirs of work. While the merger drains an earlier batch of destination bytes, the unpacker can consume source bytes already waiting in the source FIFO and the builder can place later pixels into the pixel FIFO. Crossing an eight-byte source boundary or filling eight pixel-FIFO words is therefore not automatically a pause. The cost becomes visible only when the next stage needs data before a refill arrives, or when buffered output cannot advance until RAM becomes available.

### Gearlynx's FSM approximation

Gearlynx represents the externally observable rendering sequence as this finite-state machine:

```text
IDLE
    -> SCB_FETCH -> SCB_RELOAD -> PALETTE -> QUAD_INIT
    -> LINE_FETCH -> ROW_BEGIN -> ROW_PAINT -> ROW_END
    -> QUAD_END -> SPR_END -> SCB_NEXT
    -> next SCB or IDLE
```

`SCB_FETCH`, `SCB_RELOAD`, and `PALETTE` model list traversal and the conditional SCB fields. `QUAD_INIT` and `LINE_FETCH` model reference-point geometry and source control records. `ROW_BEGIN`, `ROW_PAINT`, and `ROW_END` retain enough state to stop at modeled safe process boundaries, process clipping and packed/literal decoding incrementally, arbitrate pending LCD requests, and resume in the same place. `QUAD_END`, `SPR_END`, and `SCB_NEXT` apply transform, collision-depository, control-record, and linked-list completion behavior. When the final link is reached, Gearlynx clears sprite busy and wakes the emulated CPU.

The FSM does not assert that the real chip contains a register named for each of these software phases. They are an implementation framework for events the hardware exposes. Within a row, Gearlynx tracks separate source/internal and RAM-bus readiness frontiers, row-local FIFO occupancy and merger groups, collision groups, packed decoder state, transform state, and pending Mikey ownership. Elapsed time advances to the furthest ready frontier, preserving the overlap observed on hardware. Rules are treated as established where controlled and withheld hardware coverage exists. General LCD overlap, some mixed packed readiness, and isolated EOF/clipping tails remain approximations with narrower evidence.

Gearlynx currently starts the accurate FSM when `SPRGO.B0` is written with `SUZYBUSEN.B0` set, and advances it while the CPU is halted. It stores `SDONEACK` but does not currently model acknowledgement as a launch or sleep gate. Real software must still follow Atari's acknowledgement protocol; successful execution in Gearlynx is not evidence that omitting it is hardware-safe.

This accurate path is distinct from Gearlynx's optional fast renderer. The fast renderer draws a list in bulk and presents an approximate busy delay; it intentionally does not model the incremental FSM, FIFO readiness, clipping cadence, or LCD grant boundaries. It is useful when speed matters more than timing fidelity, but it must not be used to derive real-hardware optimization advice or benchmark results.

### Cold and warm work

Project measurements and the Gearlynx model distinguish cold and warm work. The first active row after setup is cold. Later rows can reuse filled pipeline state and overlap work more effectively. A new linked SCB retains more useful pipeline state than a new independent `SPRGO`, while a skipped SCB or a new list can make later work cold again. Atari documents the pipeline structures, but not this measured cycle-level classification.

For repeated work, always measure one row and many rows. The useful steady-state cost is:

```text
warm row ticks = (raw_us_many - raw_us_one) * 16 / (rows_many - 1)
```

For example, the measured W8 one-pen expansion took 65 us for one row and 626 us for 102 rows. The later-row average is `(626 - 65) * 16 / 101 = 88.9` ticks, close to the measured `72 + 2 * 8 = 88`-tick expansion rule. Subtracting the one-row result removes most list startup and first-row work. It produces a steady-state average; it does not mean every later row necessarily completes on the identical tick.

## SCB and list organization

Every SCB begins with a five-byte header that Suzy must read even when the skip bit is set:

| SCB part | Bytes | Notes |
|---|---:|---|
| `SPRCTL0`, `SPRCTL1`, `SPRCOLL`, link | 5 | Always fetched before the skip decision |
| Source pointer, HPOS, VPOS | 6 | Fetched by every active SCB |
| HSIZE, VSIZE | 4 | Reload depth 1 or greater |
| STRETCH | 2 | Reload depth 2 or greater |
| TILT | 2 | Reload depth 3 |
| Pen-index palette | 8 | Reloaded independently when `SPRCTL1.B3=0` |

In the project timing model, each additional active linked SCB in the measured chains exposes an internal startup process of about 35 ticks. Hardware measurements show about eight ticks for the H/V reload block and about eight ticks for the palette block. These processes can overlap other setup, so the total SCB difference is not always their simple sum. Atari documents the reload blocks, not these fitted cycle-level processes.

### Link sprites instead of launching separate lists

Use one linked painter's-order list when the render pass can be expressed that way. A linked full-reload SCB costs about 82-84 ticks more than another warm row of the same work. Separate `SPRGO` calls also repeat CPU-side pointer writes, `SPRGO`, `SDONEACK`, `SPRSYS` polling, `CPUSLEEP`, wakeup, and list termination.

Practical rules:

- Link sprites that belong to the same pass.
- Do not split a sprite merely to obtain another engine launch.
- Split only when clipping, source reduction, collision reduction, or overdraw savings repay the extra SCB.
- Unlink persistently inactive sprites when list maintenance is already available or amortized. A skipped SCB still costs its five-byte header and can break warm overlap, but transient software culling can cost more CPU time than `SKIP` or super-clipping.
- Keep one-row glyphs, particles, and HUD elements in one list rather than issuing one `SPRGO` per object.

### Reuse H/V size and palette state

HSIZE, VSIZE, and the pen-index palette persist after a list finishes and can be reused by later SCBs or independent launches. Lynx II DMA-off minimum-of-three measurements with `CHK=0000` over 31 additional launches showed additive savings from reusing H/V and palette data.

Use the shortest valid SCB:

- Set reload depth 0 when the previous HSIZE/VSIZE values are correct.
- Set palette reuse when the previous 16-entry pen map is correct.
- Group sprites that share size and palette only within painter-order-equivalent runs.
- Put a full seed SCB before short followers when state cannot be guaranteed from an earlier pass.

Never reorder overlapping transparent, XOR, or collidable sprites solely for state reuse. Video read/modify/write behavior and collision detection depend on what was painted earlier. Preserve painter order and reload state when ordering must remain fixed.

STRETCH and TILT modifications are enabled only when included by the selected reload depth. Do not omit them expecting an earlier transform to remain active. Gearlynx currently clears its modeled STRETCH/TILT values when omitted, but the developer-facing requirement is the documented reload-depth gate.

### Palette placement bug

Never place the first byte of an eight-byte SCB pen palette at address `xxFA`. A real Suzy page-crossing bug leaves the final two palette bytes unloaded, so indices C-F retain values from the previous SCB.

## Choose the lowest useful source depth

These recommendations assume normal color operation with `DISPCTL.FOURBIT=1`, where the build buffer stores two 4-bit pens per byte. Source depth changes the number of bits Suzy must fetch and unpack, not the final framebuffer traffic. The measurements in this guide do not characterize the legacy 2-bit display mode.

Use:

- 1 bpp for two source indices.
- 2 bpp for four source indices.
- 3 bpp for eight source indices.
- 4 bpp only when sixteen source indices are required.

The public Lynx I full-width literal tests measured:

| Source depth | Time | Saving versus 4 bpp |
|---:|---:|---:|
| 1 bpp | 2529 us | 17.9% |
| 2 bpp | 2586 us | 16.1% |
| 3 bpp | 2760 us | 10.4% |
| 4 bpp | 3081 us | baseline |

Lower depth is not two or four times faster because the destination still contains the same number of 4-bit pixels. Once framebuffer or collision traffic dominates, reducing source depth produces little additional speed.

Use the sprite's 16-entry pen-index palette to map a small set of source indices to any required display pens. Reusing a color in the image does not require retaining a higher source depth.

## Crop source imagery before encoding

Crop empty borders and unused rows in source space. This reduces source fetching and unpacking even when transparent output would avoid writes.

Cropping is most valuable when it removes:

- Complete source pens before scaling.
- Transparent prefixes that must be decoded before reaching the screen.
- Entire source rows or quadrants.
- Packed packets and their headers.
- Collision groups that would otherwise be touched by sparse collidable pixels.

Do not crop only by changing the visible framebuffer rectangle while leaving the same source row. Suzy still decodes hidden source pens when drawing toward the display.

## Totally literal and packed source data

`SPRCTL1.B7=1` selects totally literal rows. `B7=0` selects packed rows containing literal and RLE packets.

### Totally literal rows

Totally literal encoding has no packet headers or packet mode transitions. Suzy consumes source indices until it reaches the byte offset for the next row.

Prefer it for:

- Detailed imagery with short or irregular color runs.
- Rows where packed data would contain many small literal packets.
- Source-bound art where packet commands would become the bottleneck.

The remaining bits in the final literal byte are decoded as pixels. Generate the row with a format-aware encoder; do not assume unused trailing bits are ignored.

### Packed rows

A packed packet starts with a five-bit header:

- Header bit 4 is 1 for literal mode and 0 for RLE mode.
- Header bits 3-0 encode `count - 1`.
- One packet contains 1-16 source pens.
- Header `00000` terminates a packed row.

The one-byte line offset is an unsigned distance from its own address to the next row or control byte. Values 0 and 1 are control records, so an ordinary row can contain at most 254 following source bytes. Keep a valid offset boundary even when using `00000`: Atari documents it as the packed end-of-line marker but also flags uncertainty around that hardware behavior.

The five-bit mode/count layout above is the source format used by the project tools and validated by the hardware packet tests; the bundled Atari prose describes packed/literal rows and the special zero header but does not spell out this header layout.

As a concrete 4-bpp example, an RLE packet containing sixteen copies of source index 3 begins with `01111` and carries one `0011` index: nine useful bits before termination and padding. A literal-16 packet begins with `11111` and carries sixteen four-bit indices: 69 useful bits. RLE is decisively smaller and lighter for that flat run. If the colors change frequently, however, short runs repeatedly pay five-bit headers and packed data can become slower than one totally literal stream.

Prefer packed data for long flat runs and repeated pens. Merge adjacent compatible packets and use the longest legal packet.

Measured packet-size results for identical output show why packet count matters:

| Encoding | Packet size | Time |
|---|---:|---:|
| RLE | 2 | 3142 us |
| RLE | 3 | 2701 us |
| RLE | 4 | 2506 us |
| RLE | 8 | 2171 us |
| RLE | 16 | 2017 us |
| Literal packets | 1 | 4436 us |
| Literal packets | 2 | 3142 us |
| Literal packets | 4 | 2507 us |
| Literal packets | 8 | 2311 us |
| Literal packets | 16 | 2236 us |

RLE-16 took less than half the time of literal-1 for the same output. Packet headers and mode transitions are real pipeline work.

These packet-grid values are an early real-hardware page with DMA off and CAL 10. The page records one attempt per case and has no complete framebuffer/collision oracle, so use the large monotonic packet-size trend rather than treating one-microsecond differences as acceptance limits. The hardware model was not recorded.

### Smaller packed data can be slower

One measured title image produced these real-hardware totals with display DMA active:

| Encoding | Time |
|---|---:|
| 4-bpp totally literal | 3445 us |
| 4-bpp packed | 3606 us |
| 2-bpp totally literal | 2864 us |
| 1-bpp totally literal | 2818 us |
| 4-bpp packed and scaled | 3176 us |

The packed image used fewer bytes but more packet work and was slower than the literal image. The scaled packed version reduced source work enough to become faster.

This is an early single-attempt source page with CAL 12 and no complete semantic oracle; the hardware model was not recorded. The same imagery and source layouts were subsequently exercised by guarded focused tests, but these absolute title totals should be read as comparative evidence.

Choose encoding per asset from render time, not ROM or RAM size alone.

### Do not align packet headers by padding

Controlled hardware tests moved identical packet headers across byte boundaries and source FIFO refill phases. The spread was below one tick per warm row and did not reveal a consistently faster phase.

Do not:

- Insert packets only to align later headers.
- Pad source solely to avoid a four-byte fetch boundary.
- Reorder image content into grouped runs unless it reduces packet count or source work.

Long packets are useful. Header bit alignment is not a practical optimization target.

### End-of-row hardware bug

If the last meaningful bit of a source packet lands in bit 0 of a byte, append a zero byte and include it in the row offset. This is a documented Suzy hardware bug.

For packed rows, the zero header in the pad byte terminates decoding. Totally literal rows do not recognize that terminator: Atari says decoding continues to the row-byte boundary and leftover bits are painted. Project hardware tests and the current decoder observe 7/3/2/1 additional zero indices at 1/2/3/4 bpp for the affected pad-byte case, but those exact counts are not specified in the bundled Atari prose. Make the outputs harmless through palette mapping, sprite type, or clipping, or redesign the row. Always validate the resulting video and collision footprint.

Packed empty rows use offset 2 followed by a zero byte; offset 1 means end of quadrant instead.

## Scaling, zoom, stretch, and tilt

Project measurements and Gearlynx model HSIZE and VSIZE as 8.8 size increments applied to separate fractional accumulators. For each source pen or source row, Suzy adds the corresponding size increment to its accumulator, emits the integer carry as an output count, and retains the fraction. This interpretation matches the tested scaling behavior but is more detailed than the bundled Atari prose. It has two important consequences:

1. Downscaling still decodes the discarded source pens.
2. Upscaling a tiny source can eliminate most source work while retaining only required output work.

In 8.8 notation, `$0100` means one output unit and `$0080` means one half. With rightward traversal and the standard `HSIZOFF=$007F`, adding `HSIZE=$0080` for the first source pen changes the accumulator from `$007F` to `$00FF`, so it emits nothing. The second pen changes it to `$017F`, emits one destination pixel, and retains the `$7F` fraction. Two source pens therefore produce one output pixel. `HSIZE=$0200` produces two outputs per source pen. Left/up traversal starts from zero as Atari specifies, changing the initial phase but not the long-run ratio.

### Horizontal downscaling

Downscaling a large source does not automatically save time. A fixed 161-pen 4-bpp row measured approximately:

| Outputs | Ticks per warm row |
|---:|---:|
| 20 | 394.61 |
| 40 | 393.66 |
| 60 | 395.56 |
| 80 | 393.82 |
| 120 | 429.62 |
| 140 | 455.13 |
| 160 | about 480-482 |

At 20-80 outputs the same source decode frontier dominates, so reducing output width produces no useful gain. To make a downscaled object faster, reduce source pens as well as destination width.

This DMA-off page uses paired one-row/102-row minimum-of-three measurements with framebuffer and guard validation (`CHK=0000`, CAL 11). The hardware model was not recorded.

### Horizontal expansion

Expansion is ideal for flat fills, bars, repeated columns, large pixels, and simple backgrounds. A one-pen literal source measured:

| Output width | One row | 102 rows |
|---:|---:|---:|
| 1 | 64 us | 549 us |
| 4 | 64 us | 569 us |
| 8 | 65 us | 626 us |
| 16 | 65 us | 726 us |
| 32 | 68 us | 929 us |
| 64 | 71 us | 1336 us |

The warm expansion path is close to `72 + 2 * outputs` ticks per row. Source cost is almost constant; framebuffer work grows with output width.

This DMA-off page uses minimum-of-three one-row/102-row measurements. The hardware model was not recorded, and the original page does not contain a complete runtime semantic oracle; later guarded DMA and width pages validate the same expansion behavior.

### Fast full-screen fill

For the measured 160x102 solid-fill recipe:

- Use a one-pen totally literal source row.
- Map that pen to the required display color.
- Use `BACKNONCOLL` when collision RAM need not change.
- Use right/down traversal without flips, set `HPOS=0`, `VPOS=0`, the standard `HSIZOFF=$007F` and `VSIZOFF=$007F`, `HSIZE=$A000`, and `VSIZE=$6600`. Atari forces the corresponding left/up initial offsets to zero.

Use `BACKGROUND` only when the same pass must initialize collision RAM. It adds collision-buffer traffic for every touched group.

### Vertical scaling

Vertical scaling saves source storage but does not make repeated output rows free. Suzy processes the source record again for every generated destination row. A vertically repeated wide line therefore stays close to the cost of drawing all generated rows.

Use vertical scaling when:

- Repeating a simple source row saves memory.
- Horizontal source work is already small.
- The same row pattern is genuinely required.

Do not use it as a substitute for culling destination rows that should not be drawn.

### Stretch and tilt

STRETCH modifies HSIZE after every generated row. TILT accumulates into HPOS after every generated row. When VSTRETCH is enabled, Atari specifies that STRETCH is added to VSIZE after every generated destination row; the updated VSIZE takes effect when the next source line is fetched. Gearlynx currently accumulates the equivalent `STRETCH * generated_rows` update at the end of the source record.

Focused hardware controls identify these visible-row stages:

- Stretch update: about 8 ticks per generated row.
- Tilt/HPOS update: about 18 ticks per generated row.
- A display-DMA ownership interval can hide the tilt stage when it overlaps other work.
- A source record that generates zero rows pays a two-tick offset read plus an observed 18-tick reject stage, but generates no row and therefore does not advance row transforms.

The public transform totals are Lynx I minimum-of-three CRC-checked cases. The private stage controls that isolate the 8/18/20-tick processes did not record the hardware model.

Recommendations:

- Use static pre-transformed source data only when reduced transform work outweighs its added source/decode work and the underlying geometry is reusable.
- Use hardware stretch/tilt when dynamic geometry or source-memory savings repay the per-row stages.
- Crop trailing transformed rows in source space. Do not simply remove leading transformed rows: Gearlynx resets its internal TILT accumulator at initial sprite quadrant setup, and the removed rows would also have advanced VPOS, HSIZE, HPOS, and possibly VSIZE. Regenerate source and initial SCB geometry so the first retained row starts at the same state; if fractional phase cannot be represented by SCB fields, retain dummy leading rows.
- Do not assume clipped rows freeze STRETCH, TILT, HSIZE, or HPOS state.
- Use reload depth 2 only when STRETCH is needed and depth 3 only when TILT is needed.

Keep the three vertical rejection paths distinct:

- Zero-height scaling consumes the source-record offset and reject stage but generates no row transform.
- A quadrant already outside the display and moving farther away advances the required row geometry without visible transform timing.
- An offscreen row moving toward the display follows the measured clipped-row cadence and advances normal row geometry until it can enter the window.

For a transform example, start with `HSIZE=$0100`, `STRETCH=$0040`, `TILT=$0080`, and a zero tilt fraction. After the first generated row, HSIZE becomes `$0140` and tilt retains a `$80` fraction. After the second, HSIZE becomes `$0180`; the tilt sum reaches `$0100`, moves HPOS by one pixel, and returns its fraction to zero. Removing those two leading rows without rebuilding the initial state would make the first retained row narrower and one pixel left of its original position. Clipping those rows does not automatically erase the state advances.

The public transform probes validate zoom-out, asymmetric zoom, positive and negative stretch, positive and negative tilt, and combined stretch/tilt. Their short totals are useful correctness checks, not universal per-sprite costs.

## Framebuffer traffic and transparency

The framebuffer stores two 4-bit pixels per byte. The video merger distinguishes three useful group classes:

- Opaque-only: write destination data.
- Transparent-only: read and preserve destination data.
- Mixed transparent/opaque: read and write destination data.

Transparent pixels are not free. A transparent group still consumes video RAM bandwidth. A mixed group exposes both operations and is more expensive than a pure read-only or write-only group.

Consider a 16-pixel `NONCOLL` row containing eight opaque pen-1 pixels and eight transparent pen-0 pixels. Arranged as `11111111 00000000`, it forms one opaque write-only group and one transparent read-only group. Rearranged as `10101010 10101010`, both groups are mixed and must preserve old pixels as well as write new ones. The visible color counts are identical, but the second arrangement exposes more merger work.

Even a background operation is not always write-only at its edges. Atari specifies that a partially used first or last destination byte must preserve the untouched nibble through read-modify-write. Full opaque destination bytes can remain write-only.

### Group art by operation

Arrange imagery so groups are operationally uniform when possible:

- Keep opaque runs together.
- Keep transparent holes together.
- Avoid alternating opaque and transparent pens inside every group.
- Crop fully transparent edge groups.
- Use an opaque background operation for layers that replace all pixels.

Do not distort visible art or add output pixels merely to force alignment. The extra source/output work can exceed the saved tail transaction.

### Video groups are not generally screen-aligned

There is no universal even-X or absolute 8-pixel alignment rule for framebuffer performance.

- Packed and 1-bpp video timing primarily follows row-local groups.
- Totally literal 2-4-bpp rows use destination-word slots.
- Moving the same 23-pixel video row through X0-X7 showed no absolute 8-pixel screen-boundary penalty.
- Odd X can still change first/last partial-byte work, but it is a row-tail issue rather than a blanket alignment rule.

Choose X for game geometry first. Optimize alignment only after measuring the exact operation.

### Destination-word and row-tail costs

Project timing measurements for totally literal 2-4-bpp rows expose a four-slot `4,2,2,2`-tick destination-word pattern. A read/write merge adds about two ticks per occupied word. Atari documents the builder, FIFO, merger, and interleaving, but not this fitted slot cadence. Partial final bytes and FIFO occupancy can add small terminal work.

Here, a **destination word** is one pixel-FIFO entry produced by the byte builder. In four-bit display mode it represents one destination byte, or two pixels, together with the state needed by the merger. An aligned eight-pixel span fills four words and exposes `4 + 2 + 2 + 2 = 10` ticks. If all four words need both a read and a write, the measured paired merge adds about `2 * 4 = 8` ticks. Six pixels fill three complete words. A seventh pixel starts a fourth destination byte whose untouched nibble must be preserved; that incomplete final byte is the **row tail**.

Practical rules:

- End on complete destination bytes when it is naturally convenient.
- Avoid one-pixel transparent or opaque tails if cropping can remove them.
- Do not append visible padding only to avoid a tail; drawing the padding usually costs more.
- Mirrored regular clipping is symmetric in the measured controls, so optimize generated outputs rather than absolute screen-byte parity there. A **natural EOF** row ends because its source bytes are exhausted rather than because drawing crossed a clip edge. Natural-EOF 1-bpp rows are an exception to the symmetry rule: reverse traversal can be about six ticks per warm row faster because its terminal byte-builder slot is traversal-relative.

## Collision performance

Collision work can dominate an otherwise fast sprite. Atari documents collision reads in eight-pixel bursts. Project measurements show that collision RAM transactions are screen-addressed, while Gearlynx's accurate-pipeline readiness/detect groups are row-local; row-end logic reconciles the two and may expose a partial terminal transaction.

For example, eight generated collidable pixels drawn at X1-X8 form one row-local eight-output group. Their collision addresses, however, cross the fixed X0-X7 and X8-X15 screen regions, so collision RAM touches two screen groups. Row-local groups describe how far the internal pipeline has progressed; screen groups describe the RAM transactions actually required. If one screen group has no matching complete row-local group, part of its work can remain exposed at row end.

The basic collision operations are:

| Operation | Nominal measured transaction budget |
|---|---:|
| Write/clear only | about 10 ticks |
| Read/preserve only | about 10 ticks |
| Read plus write/merge | about 18 ticks |
| Detect, compare, and write | about 18 ticks |

Full-screen tests found background collision clear about 40% slower than the same non-colliding background, and normal collision detect/read/write about 74% slower than the same non-colliding video operation.

The 10/18-tick values are process budgets, not guaranteed additions to wall time. FIFO overlap and partial transactions can hide part of them; packed X1 controls, for example, expose roughly 8-9 collision ticks rather than a complete extra transaction. The 40%/74% totals come from an early single-attempt DMA-on page with CAL 10 and no complete semantic oracle; the hardware model was not recorded. Later guarded burst and type matrices confirm the ordering and large collision penalty.

### Choose the appropriate collision-disable mechanism

- Use `BACKNONCOLL` or `NONCOLL` when that sprite never needs collision.
- Set `SPRCOLL.B5` for individual non-colliding SCBs when the type has useful collision semantics elsewhere.
- Set global `SPRSYS.B5` for complete passes that use otherwise collidable types but do not need collision.

The global bit is especially useful for visual-only passes because it removes collision activity without changing every collidable SCB. It adds nothing for types 1 and 5, which are already non-colliding. Maintain a software shadow when writing `SPRSYS`; read bit 5 reports the last carry state, not the written global don't-collide value.

### Minimize screen collision groups

Collision groups follow fixed screen regions X0-X7, X8-X15, and so on. An unaligned collidable span can touch one extra group even when video work is unchanged.

Recommendations:

- Keep narrow collision shapes within as few 8-pixel screen groups as possible.
- Separate visual width from collision width when the game design permits it.
- Align pen-E preserve regions and write regions to group boundaries.
- Crop transparent-but-collidable pen-F borders.

A compact two-times-expanded 1-bpp glyph provided one narrower exception worth measuring: with ten collidable outputs, even-X starts were about 12 ticks per warm row faster than odd-X starts. This is a lower-depth expansion/collision phase result, not a general rule for all sprites.

### Collision depository and Everon

Types 2, 3, 4, 6, and 7 can write the highest previous collision value to the SCB collision depository. `SPRGO.B2` separately enables Everon status in depository bit 7. With Everon enabled, bit 7 is 1 only when the sprite was never on-screen; it is 0 when the sprite was ever on-screen.

- Disable collision when the depository result is not consumed.
- No isolated hardware timing page establishes an incremental Everon cost, and Gearlynx currently does not charge one. Enable it only when its result is useful rather than assuming either that it is free on silicon or that it is expensive.
- `COLLOFF` is one signed 16-bit offset shared by all SCBs and may locate the depository before or after the SCB. Keep that location valid for every SCB layout.

## Choose the operation type deliberately

The eight operation types are not cosmetic. They select different framebuffer and collision processes.

### Pen behavior by type

`T` means transparent video, `O` means opaque video, `X` means XOR video, `P` means preserve existing collision data, and `D/W` means detect previous collision then write this sprite's collision ID.

| Type | Name | Pen 0 | Pen E | Pen F | Other pens |
|---:|---|---|---|---|---|
| 0 | `BACKGROUND` | O, write ID | O, P | O, write ID | O, write ID |
| 1 | `BACKNONCOLL` | O, no collision | O, no collision | O, no collision | O, no collision |
| 2 | `BOUNDARY-SHADOW` | T, none | O, P | T, D/W | O, D/W |
| 3 | `BOUNDARY` | T, none | O, D/W | T, D/W | O, D/W |
| 4 | `NORMAL` | T, none | O, D/W | O, D/W | O, D/W |
| 5 | `NONCOLL` | T, none | O, none | O, none | O, none |
| 6 | `XOR` | T, none | X, P | X, D/W | X, D/W |
| 7 | `SHADOW` | T, none | O, P | O, D/W | O, D/W |

Special pens are operation-dependent. Pen E is not generally transparent or free, and pen F is not generally opaque.

### Type 0: BACKGROUND

Use for opaque layers that must also replace or preserve collision data.

- Every pen writes video.
- Pen E preserves existing collision data.
- Other pens replace the collision nibble with this sprite's collision ID.
- Keep E-only and write-only regions in separate 8-pixel collision groups.

Do not use `BACKGROUND` for an ordinary visual clear when collision RAM does not need initialization; `BACKNONCOLL` avoids an entire bus frontier.

### Type 1: BACKNONCOLL

This is the fastest general opaque replacement operation.

Use for:

- Screen clears and solid fills.
- Opaque tile layers.
- Background images that do not construct collision RAM.
- Scaled one-pen rectangles and bars.

All pens are opaque and collision RAM is untouched. Transparent source art is not possible with this type.

### Type 2: BOUNDARY-SHADOW

Use when pen F must be invisible in video but still participate in collision, while pen E is visible and preserves collision.

- Pen 0: transparent and non-colliding.
- Pen E: opaque collision-preserving shadow operation.
- Pen F: transparent but collision-detecting/writing.
- Other pens: opaque and collidable.

This can encode a visual object and a different boundary shape in one source, but transparent pen-F collision still costs collision RAM traffic. Crop and group the hidden boundary carefully.

### Type 3: BOUNDARY

Use when pens 0 and F are video-transparent but F remains collidable.

Pen E does not preserve collision for this type; it follows the normal opaque detect/write path. Use `BOUNDARY-SHADOW` instead when E must preserve collision.

### Type 4: NORMAL

Use for ordinary transparent collidable actors.

- Pen 0 is transparent and non-colliding.
- Every nonzero pen is opaque and collision-detecting/writing.
- Pen E and F have no preserve/transparency shortcut here.

Normal is expensive for broad objects because each touched collision group performs detect/read/write work. Use a smaller collision sprite or `NONCOLL` visual sprite when full visual geometry is not required for collision.

### Type 5: NONCOLL

Use for ordinary transparent visual sprites that do not need collision.

- Pen 0 is transparent.
- Every nonzero pen is opaque.
- Collision RAM is not used. With Everon disabled, the collision depository is not used either.

This should be the default for particles, visual effects, HUD glyphs, and decorative actors without hardware collision. With Everon disabled, collision RAM and the depository are untouched. With Everon enabled, the depository's bit 7 still records whether the sprite was ever on-screen.

### Type 6: XOR

Use only when the destination-dependent XOR effect is required.

Project timing measurements show XOR running after the normal source/video/collision frontier and adding about two ticks per generated destination byte, plus a small complete-byte terminal stage on some natural rows. Lynx II packed W64 hardware tests measured:

| XOR source pen | 102-row time | Meaning |
|---|---:|---|
| Pen E | 2054 us | XOR video, preserve collision |
| Pen F or ordinary collidable pen | 2486-2487 us | XOR video plus collision detect/write |

Keep XOR spans narrow, crop zero borders, and disable collision unless the XOR object genuinely needs it. A precomputed replacement may be faster only under the destination/source constraints described in the operation recipe below.

### Type 7: SHADOW

Use for opaque shadow semantics with pen-E collision preservation.

- Pen 0 is transparent.
- Pen E is opaque and preserves collision.
- Other nonzero pens are opaque and detect/write collision.

As with `BOUNDARY-SHADOW`, align E preserve areas separately from collidable areas to avoid mixed collision groups.

### Matched type costs

The public Lynx I mixed-pen test draws the same packed 64-pixel rows using pens 0, E, F, and 1:

| Type | Time |
|---|---:|
| BACKGROUND | 1603 us |
| BACKNONCOLL | 1391 us |
| BOUNDARY-SHADOW | 1797 us |
| BOUNDARY | 1906 us |
| NORMAL | 1906 us |
| NONCOLL | 1391 us |
| XOR | 2121 us |
| SHADOW | 1796 us |

The type choice changes the dominant operation even when source data and geometry are identical.

## Clipping and reference-point strategy

### Cull fully invisible objects in software

Hardware clipping saves pixel work but not every cost. A listed object still requires at least its SCB header, and some clipped paths must walk source-row offsets or advance transform state.

Unlink an object once its complete geometry cannot affect video or collision output and the CPU/list-maintenance cost is justified. For transient objects near an edge, compare software culling against `SKIP` or hardware super-clipping.

### Regular horizontal clipping

When drawing leaves the display window, Suzy processes the first generated off-window output, performs no video or collision access for it, then stops that source row.

Exploit this by arranging traversal so visible content is decoded first and the hidden suffix lies beyond the outgoing edge:

- Near the right edge, draw right when possible.
- Near the left edge, draw left when possible.
- Place the reference point and quadrant order so the useful side is visited first.

The opposite arrangement is expensive: a sprite starting offscreen and drawing toward the display must decode the hidden prefix before reaching visible pixels.

### Super-clipping

When the reference point is outside the display window, quadrants directed farther away can skip pixel data and walk only row/control information. Proper reference-point placement can let Suzy reject three quadrants of a large offscreen-centered object.

Super-clipping is not free:

- Repeated fully rejected horizontal rows measured about 46.5 ticks per row.
- Position, size, stretch, tilt, and quadrant state still advance where required.
- A vertically rejected quadrant moving farther away can skip its remaining scaled rows more aggressively.

Use super-clipping for objects crossing an edge, but remove them from the list once no quadrant can return to the window.

### Reference points and quadrants

Corner references often require fewer quadrant transitions and control records than centered references. Use a corner reference when it gives equally convenient positioning and clipping.

Centered or multi-quadrant data remains useful for rotation, mirroring, and symmetric clipping. The recommendation is not "never center"; it is "do not pay quadrant control work without using its benefits."

## Display DMA and render scheduling

Mikey and Suzy share RAM. Atari documents bus priority as video, refresh, CPU, then Suzy. Suzy yields only at suitable process cycles, with a documented maximum request-to-grant latency of 40 ticks.

During active display, Gearlynx models:

- Ten scheduled display bursts per visible line plus a frame-start prefetch.
- Eight RAM bytes per burst.
- About 192 ticks between requests.
- About 28 ticks of RAM ownership per granted burst.
- About 10 ticks of request/grant handshake can become visible at a cold safe boundary.

Gearlynx also models standalone four-tick refresh ownership every 256 ticks when display DMA is disabled or the LCD is in VBlank; visible display DMA coalesces that refresh work. These placements approximate measured ownership and overlap.

Real-hardware measurements show that Suzy can overlap some internal unpacker, scaling, and builder work with Mikey ownership, while RAM-dependent source and destination work is delayed. Gearlynx represents this with pending requests and modeled safe readiness grants rather than literal per-access bus stalls. The resulting penalty depends on width, current pipeline state, and request phase; there is no valid fixed "DMA percentage."

In practical terms, if Mikey requests RAM while Suzy still has source and destination data buffered, Suzy can keep unpacking, scaling, and building until it reaches a safe handoff point. If Suzy's next required action is a source refill or a destination merge, it waits instead. The same Mikey ownership interval can therefore be mostly hidden in one row and mostly exposed in another.

Recommendations:

- Profile complete frames with display DMA enabled.
- If the display schedule allows it, render heavy passes during VBlank or while display DMA is disabled.
- Start one linked list rather than many short lists at unrelated raster phases.
- Do not add idle delays solely to chase a favorable DMA phase; the phase benefit is workload-dependent and fragile.
- Optimize source and collision pressure even with DMA active. Internal work can hide part of a burst, but RAM-heavy rows cannot.

Hardware phase tests show a common downstream grant process for 1-bpp and 4-bpp cold rows despite a fourfold source-depth difference. This is another reason not to model DMA as a source-byte surcharge.

## Operation-oriented recipes

### Clear only the framebuffer

1. Use `BACKNONCOLL`.
2. Use a one-pen totally literal source.
3. Expand it to the required rectangle.
4. Reuse H/V size and palette if later fills match.

### Clear framebuffer and collision RAM

1. Use `BACKGROUND`.
2. Ensure `SPRCOLL.B5` and the global `SPRSYS.B5` write setting are both clear; either collision-disable bit prevents the collision update.
3. Use one non-E source pen so every collision group is replaced.
4. Expand a tiny source when the clear color and collision ID are uniform.
5. Do not mix pen E into the clear unless selected regions must preserve old collision data.

### Draw an opaque tile or background layer

1. Use `BACKNONCOLL` unless collision data is being constructed.
2. Use the lowest source depth that represents the tile palette.
3. Use RLE-16 packets for long repeated runs; use totally literal data for detailed rows.
4. Group painter-order-independent tiles by palette and size to shorten SCBs.
5. Link the complete layer under one `SPRGO`.

### Draw a transparent visual object without collision

1. Use `NONCOLL`.
2. Crop pen-0 borders.
3. Group transparent and opaque regions rather than alternating them.
4. Use the lowest source depth.
5. Avoid splitting unless it removes substantial transparent source or overdraw.

### Draw a collidable actor

1. Use `NORMAL` only for the region whose nonzero pens must collide.
2. Keep the collision footprint within few screen-aligned 8-pixel groups.
3. Consider a small invisible boundary sprite plus a larger `NONCOLL` visual sprite when that reduces total collision traffic.
4. Link the boundary and visual SCBs.
5. Read the collision depository only when gameplay needs it.

The two-sprite approach is beneficial only if collision groups saved by the smaller boundary repay the extra SCB and any visual overdraw.

### Preserve selected collision data

1. Choose a type whose pen E has preserve semantics: `BACKGROUND`, `BOUNDARY-SHADOW`, `XOR`, or `SHADOW`.
2. Keep E runs in complete collision groups.
3. Avoid alternating E and write pens inside each group.
4. Use long RLE packets for solid E masks.

### Draw collision-only boundaries

Use pen F with `BOUNDARY` or `BOUNDARY-SHADOW` when video must remain transparent but collision must be detected/written. Crop this data to the smallest gameplay-relevant shape because invisible collision still consumes collision RAM bandwidth.

### Draw HUD glyphs and particles

1. Prefer 1 bpp or 2 bpp.
2. Use `NONCOLL` unless the HUD is part of gameplay collision.
3. Reuse one palette across the batch.
4. Link all glyph SCBs under one launch.
5. Use one source row with vertical scaling only for genuinely repeated row patterns.
6. Consider expanded one-pen sources for bars, cursors, and separators.

### Draw XOR or shadow effects

1. Keep the affected span small.
2. Use pen E when collision must be preserved.
3. Disable collision globally if no collision result is needed.
4. A precomputed normal result can be faster only when the underlying destination is known and unchanged and the replacement asset has comparable source depth, bytes, and packets. Otherwise it either cannot reproduce XOR semantics or can become source-bound; benchmark it.

## Correctness requirements that affect performance work

An invalid sprite is not an optimization. Preserve these hardware requirements:

- Set `SPRCTL1.B6=0`; the alternate sizing algorithm is documented as broken.
- Initialize `SPRINIT=$F3` at least 100 ms after power-up and before drawing.
- Before the first list, initialize legitimate values for `SPRSYS`, `SPRINIT`, `HOFF`, `VOFF`, `COLLBASE`, `COLLOFF`, `HSIZOFF`, `VSIZOFF`, and `SUZYBUSEN`.
- Initialize `HSIZOFF=$007F` and `VSIZOFF=$007F` for the standard sizing setup and include them in exact scale/output calculations. Atari specifies that right/down accumulation uses these programmed offsets while left/up is forced to zero.
- Keep `SUZYBUSEN.B0=1` for ordinary rendering.
- Do not read or write unsafe Suzy SCB registers while sprite or math hardware is active.
- Before every launch, write `VIDBASE` and `SCBNEXT` and ensure the previous Suzy wakeup has been acknowledged through `SDONEACK`. Then write `SPRGO` and execute `CPUSLEEP`. Atari's earlier launch list places `SDONEACK` after `SPRGO`, but its later Common Errors section requires acknowledgement before running the engine; the conservative sequence here follows the later warning. If an unrelated interrupt wakes the CPU while `SPRSYS.B0` still reports sprite work, sleep again. Acknowledge completion before any later sleep or launch.
- Clear or mask unintended Mikey interrupts that would prevent the CPU from sleeping and Suzy from owning the bus.
- Do not perform immediately consecutive CPU accesses to any Suzy address.
- Atari's documents conflict on whether the cartridge guard begins when the write starts or completes. Conservatively, do not access Suzy for 12 ticks after the blind cartridge-write cycle completes.
- Never start an eight-byte SCB palette at `xxFA`.
- Pen-index 0 is stored in the upper nibble of the first palette byte.
- Apply the source-row bit-0 padding rule and update row offsets.
- Use offset 0 for end of sprite, offset 1 for end of quadrant, and offset greater than 1 for a source row.
- Keep SCBs and source data in system RAM. Active SCBs cannot reside in page zero because list termination uses a zero link high byte.
- Keep each source row within the 254-byte payload limit imposed by its one-byte offset.
- In four-bit mode, allocate display and collision buffers at four-byte-aligned addresses and reserve 8,160 bytes (`$1FE0`) for each.
- Quadrant changes proceed counter-clockwise. Changing the starting quadrant changes positioning, and flips pivot around the reference point; regenerate and validate geometry when changing either.
- Atari's documents conflict between a conceptual 64K-by-64K display world and a 512-by-512/nine-significant-bit programming model. Always initialize complete signed 16-bit position fields and do not reuse upper bits.
- Do not overlap Suzy math with sprite processing. Stopping the sprite engine does not preserve a resumable midpoint; restarting begins a new sprite process.

## Measure the real workload

### Count the right things

For each hot sprite or row, record:

- Active SCBs and independent `SPRGO` launches.
- Reloaded size/stretch/tilt/palette bytes.
- Source bytes and accepted source pens.
- Packed packet count, modes, and run lengths.
- Generated output pixels.
- Opaque-only, transparent-only, and mixed video groups.
- Collision read, write, preserve, and detect groups.
- Partial destination-byte tails.
- Clipped prefixes/suffixes and rejected rows.
- Display-DMA state and raster phase.

Then identify which frontier is likely dominant and make one change that should affect it. A source rewrite that leaves a collision-bound row unchanged is expected, not a failed measurement.

For example, a 161-pen 4-bpp source downscaled to 20 visible outputs still consumes about 81 source-data bytes but touches only a few video groups and no collision groups. That row is likely source-bound, so reducing visible width again will not help; crop the source or reduce its depth. Conversely, expanding one source pen to 64 collidable outputs makes source work tiny while video and collision traffic grow. In that case, disabling collision or using a narrower collision boundary is the useful change.

### Use paired and withheld tests

For a proposed optimization:

1. Measure one row and many rows.
2. Hold source and output constant while changing one property.
3. Include a withheld width, alignment, or type not used to form the hypothesis.
4. Validate framebuffer, collision buffer, depository, and guard bytes.
5. Recheck with display DMA enabled.

### Timer 1/3 measurement protocol

For new microsecond measurements on hardware:

1. Stop Timer 1 and Timer 3.
2. Clear both CTLB registers.
3. Program reload and count values.
4. Synchronize to the desired raster phase.
5. Clear both CTLB registers again immediately before enable.
6. Enable Timer 3 linked and Timer 1 at 1 us.
7. Run the sprite operation.
8. Stop both timers before reading them.
9. Keep the minimum of at least three complete attempts and validate video, collision, depository, and guard outputs.

In this project's hardware harness, the second CTLB clear is required. Without it, observed stale dynamic borrow state can produce apparent 256-us timing jumps. A few early comparative tables in this guide predate the minimum-of-three and complete-oracle standard; their provenance is stated beside them.

## Public hardware reference matrix

The `sprites1` through `sprites5` public tests are compact Lynx I examples. Each result is a minimum-of-three microsecond measurement with exact video/collision CRC validation. Expected windows are centered on these hardware values with a tolerance of 16 us:

| Suite | Operations | Hardware centers in test order |
|---|---|---|
| `sprites1` | Literal 1/2/3/4-bpp full, 1/4-bpp W20, expansion W8/W64 | `2529, 2586, 2760, 3081, 2587, 2538, 590, 1300` |
| `sprites2` | Alignment, mirrored clipping, super/vertical clipping, Alpine flip | `803, 764, 784, 473, 473, 319, 32, 48` |
| `sprites3` | Eight operation types with mixed pens 0/E/F/1 | `1603, 1391, 1797, 1906, 1906, 1391, 2121, 1796` |
| `sprites4` | Packed RLE/literal, pen E, XOR F, linked SCBs, DMA expansion | `930, 1391, 1507, 1602, 2450, 55, 92, 834` |
| `sprites5` | Zoom, positive/negative stretch, tilt, combined transform | `88, 75, 73, 75, 83, 82, 82, 84` |

Use these tests to validate broad behavior. Use focused row-paired tests for optimization decisions because an aggregate total can hide cancellation between pipeline stages.

## Optimization checklist

Before shipping a render pass, ask:

- Is every listed SCB potentially visible or collision-relevant?
- Can the pass use one linked list instead of multiple launches?
- Can followers reuse H/V size or palette?
- Is every sprite using the lowest sufficient source depth?
- Are transparent source borders cropped?
- Do packed rows use long packets and merged runs?
- Is packed encoding actually faster for this asset?
- Can a tiny source be expanded instead of storing repeated pixels?
- Are collision and Everon disabled where unused?
- Are collision shapes confined to few screen groups?
- Are pen-E preserve and write regions separated by group?
- Does clipping discard a suffix rather than decode a hidden prefix?
- Are stretch and tilt worth their per-row work?
- Has the complete pass been measured with display DMA enabled?
- Were output, collision, depository, and guard bytes validated?
