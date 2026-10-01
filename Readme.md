# Protocol Engine State Machine (PESM)

**A reprogrammable protocol emulator ASIC**

---

## Table of Contents

1. [Overview](#1-overview)
2. [What This Chip Does](#2-what-this-chip-does)
3. [Why It Exists](#3-why-it-exists)
4. [Abbreviations Glossary](#4-abbreviations-glossary)
5. [Architecture](#5-architecture)
6. [Instruction Set Reference](#6-instruction-set-reference)
7. [Configuration Registers](#7-configuration-registers)
8. [Host Loader Protocol](#8-host-loader-protocol)
9. [Example Programs](#9-example-programs)
10. [Verification](#10-verification)
11. [How to Simulate](#11-how-to-simulate)
12. [How to Build for an ASIC](#12-how-to-build-for-an-asic)
13. [Design Decisions & Rationale](#13-design-decisions--rationale)
14. [Competition Requirements Checklist](#14-competition-requirements-checklist)
15. [Further Reading](#15-further-reading)

---

## 1. Overview

| Property | Value |
|---|---|
| **Project name** | Protocol Engine State Machine (PESM) |
| **Top module** | `protocol_engine` |
| **Language** | Verilog-2001 / SystemVerilog-2012 |
| **Target process** | IHP CMOS5L (130 nm) |
| **Tile size** | 6×4 Tiny Tapeout tiles (~1002 µm × 432 µm) |
| **Target clock** | 50 MHz |
| **License** | Apache-2.0 |

**One-sentence description:** A tiny protocol-centric state machine with a programmable instruction set designed for reading pins, writing pins, counting cycles, and bit-banging communication protocols (UART, SPI, I2C, and others) in firmware.

---

## 2. What This Chip Does

This chip is **not** a general-purpose CPU. It is **not** a collection of UART/SPI/I2C hardware blocks. It is a **reprogrammable state machine** whose instruction set is designed around the primitives that protocol emulation actually needs.

You can think of it as a small, specialized processor that:

- **Reads and writes pins** with fine-grained control
- **Waits** for exact pin states or precise numbers of cycles
- **Shifts bits** in and out through hardware shift registers
- **Queues data** in FIFOs with automatic refill (autopull/autopush)
- **Generates protocol clocks** with a fractional divider
- **Runs loops** and conditional branches with minimal instruction overhead

All protocol behavior — UART start bits, SPI clocking, I2C ACKs — is defined in **firmware** loaded after manufacturing. Change the firmware, get a new protocol.

### What "bit-banging" means

Most microcontrollers have dedicated hardware for UART/SPI/I2C. This chip does not. Instead, it uses software to toggle individual pins at exact moments. That's called **bit-banging** — using brute-force timing in code instead of dedicated hardware.

The advantage is **flexibility**: one chip can speak many protocols. The challenge is **precision**: software must hit timing exactly. This architecture is designed to make that precision easy.

---

### The competition's core requirements

From the official blog post (paraphrased):

> Design a small chip whose sole purpose is protocol emulation. It should be a tiny CPU with an instruction set designed for reading pins, writing pins, counting cycles, and hitting timing precisely enough that you can implement real protocols in firmware. It must be reprogrammable enough to support new protocols after fabrication.

The blog explicitly warns against two failure modes:

1. **Don't** hardcode a UART block, an SPI block, and an I2C block on one die.
2. **Don't** build a general-purpose CPU with a few I/O instructions bolted on.

The blog suggests looking at two existing designs for inspiration:

- **RP2040 PIO** — Raspberry Pi's Programmable I/O subsystem, a set of tiny state machines with shift registers, side-set, autopull, and clock dividers.
- **TI PRU** — Texas Instruments' Programmable Real-time Unit, a similar concept with a different flavor.

This design borrows the best ideas from both and adds a few novel touches (atomic multi-pin sampling, conflict-free side-set, integer+fractional clock divider).

---

## 4. Abbreviations Glossary

Every abbreviation used in this project, in alphabetical order.

| Abbreviation | Full name | Meaning |
|---|---|---|
| **ASIC** | Application-Specific Integrated Circuit | A chip designed for one specific job, not a general-purpose CPU |
| **CAN** | Controller Area Network | A multi-master serial protocol used in automotive and industrial systems |
| **CMOS** | Complementary Metal-Oxide-Semiconductor | The transistor technology used to build most digital chips |
| **CMOS5L** | (IHP process name) | The specific 130 nm process used by Tiny Tapeout's shuttle |
| **CPU** | Central Processing Unit | A general-purpose processor |
| **CRV** | Constrained Random Verification | A verification technique using randomized inputs under constraints |
| **DUT** | Device Under Test | The circuit being verified |
| **FIFO** | First In, First Out | A queue where data comes out in the order it went in |
| **FSM** | Finite State Machine | A circuit that moves through a fixed set of states based on inputs |
| **GDSII** | Graphic Data System II | The file format that describes chip layout for manufacturing |
| **GPIO** | General-Purpose Input/Output | Pins that can be configured as inputs or outputs |
| **I2C** | Inter-Integrated Circuit | A 2-wire serial protocol (also written I²C or IIC) |
| **IHP** | Innovations for High Performance | The European foundry that fabricates Tiny Tapeout chips |
| **IRQ** | Interrupt Request | A signal indicating that something needs attention |
| **ISA** | Instruction Set Architecture | The complete set of instructions a processor understands |
| **ISR** | Input Shift Register | A register that accumulates bits coming in from pins |
| **JTAG** | Joint Test Action Group | A debugging and test protocol (IEEE 1149.1) |
| **LEF** | Library Exchange Format | A file format describing abstract chip layout for place-and-route |
| **LSB** | Least Significant Bit | The rightmost bit (weight 1 in a byte) |
| **MSB** | Most Significant Bit | The leftmost bit (weight 128 in a byte) |
| **NBA** | Non-Blocking Assignment | In Verilog, `<=`; updates happen at the end of the cycle |
| **OE** | Output Enable | A signal that says "drive this pin" (1) or "listen" (0) |
| **OpenRAM** | (proper noun) | An open-source SRAM compiler for chip designs |
| **OSR** | Output Shift Register | A register that feeds bits out one at a time |
| **PC** | Program Counter | The address of the next instruction to execute |
| **PDK** | Process Design Kit | Files describing how to build chips in a specific foundry process |
| **PESM** | Protocol Engine State Machine | This chip's architecture |
| **PIO** | Programmable I/O | The RP2040's protocol engine subsystem |
| **PRU** | Programmable Real-time Unit | TI's protocol engine subsystem |
| **PS/2** | (proper noun) | An old keyboard/mouse serial protocol |
| **RTL** | Register Transfer Level | The style of Verilog that describes hardware behavior |
| **Sby** | SymbiYosys | An open-source formal verification tool |
| **SPI** | Serial Peripheral Interface | A 4-wire serial protocol |
| **SRAM** | Static Random-Access Memory | Memory that holds data as long as it's powered |
| **SWD** | Serial Wire Debug | ARM's 2-wire debugging protocol |
| **UART** | Universal Asynchronous Receiver/Transmitter | A 2-wire serial protocol (TX/RX) |
| **USB** | Universal Serial Bus | The port you plug keyboards and phones into |
| **VCD** | Value Change Dump | A file recording signal changes over time (used by GTKWave) |
| **Verilog** | (proper noun) | A hardware description language |

---

## 5. Architecture

### 5.1 Block diagram

```
                       ┌─────────────────────────────────────────────┐
                       │         Protocol Engine (PESM)              │
                       │                                             │
   uio_in[3] ─────────►│  ┌──────────┐     ┌──────────────────┐      │
   uio_in[2] ─────────►│  │   Host   │     │  Instruction     │      │
   uio_in[1] ─────────►│  │  Loader  │────►│  Memory (imem)   │      │
   uio_in[0] ─────────►│  │          │     │  32 × 16 bits    │      │
                       │  └──────────┘     └────────┬─────────┘      │
                       │                            │                │
   clk ───────────────►│  ┌──────────────┐          │ instr          │
                       │  │    Clock     │          ▼                │
                       │  │   Divider    │  ┌──────────────────┐      │
                       │  │  (16.8 bit)  │  │   Instruction    │      │
                       │  └──────┬───────┘  │     Decoder      │      │
                       │         │          └────────┬─────────┘      │
                       │         │ tick              │                │
                       │         ▼                   ▼                │
                       │  ┌──────────────────────────────────┐        │
                       │  │       PESM Core (FSM)            │        │
                       │  │                                  │        │
                       │  │  PC   X   Y   pin_out   pin_oe   │        │
                       │  │                                  │        │
                       │  │  OSR (32b)     ISR (32b)         │        │
                       │  │                                  │        │
                       │  │  TX FIFO (8×8)  RX FIFO (8×8)    │        │
                       │  │                                  │        │
                       │  │  Autopull / Autopush triggers    │        │
                       │  └────────────────┬─────────────────┘        │
                       │                   │                          │
                       └───────────────────┼──────────────────────────┘
                                           │
                                           ▼
                                   uo_out / uio_out / uio_oe
```

### 5.2 Physical interface

| Signal | Direction | Width | Purpose |
|---|---|---|---|
| `ui_in` | Input | 8 | Generic inputs (currently unused) |
| `uo_out` | Output | 8 | Protocol output pins |
| `uio_in` | Input | 8 | Bidirectional pins read as input |
| `uio_out` | Output | 8 | Value to drive onto bidirectional pins |
| `uio_oe` | Output | 8 | Output enable per pin (1 = drive, 0 = listen) |
| `ena` | Input | 1 | Enable (always 1 when powered) |
| `clk` | Input | 1 | System clock (50 MHz typical) |
| `rst_n` | Input | 1 | Active-low reset |

**Bidirectional pins**: to drive `uio[N]`, set `uio_out[N]` and `uio_oe[N] = 1`. To listen, set `uio_oe[N] = 0` and read `uio_in[N]`.

### 5.3 Internal state

| Register | Width | Purpose |
|---|---|---|
| `pc` | 5 | Program counter (addresses 0–31) |
| `instr` | 16 | Currently-executing instruction |
| `x_reg`, `y_reg` | 8 each | General-purpose scratch |
| `osr` | 32 | Output shift register |
| `isr` | 32 | Input shift register |
| `osr_count` | 5 | Bits remaining in OSR before refill |
| `isr_count` | 5 | Bits accumulated in ISR before push |
| `pin_out` | 8 | Value driven on pins |
| `pin_oe` | 8 | Output enable per pin |
| `delay_cnt` | 16 | Remaining delay cycles |
| `state` | 2 | FSM state: S_FETCH, S_EXEC, S_DELAY |
| `tx_fifo`, `rx_fifo` | 8×8 each | Data queues |

### 5.4 Finite State Machine

The PESM has three states:

```
       ┌───────────┐
   ┌──►│  S_FETCH  │  Read next instruction from imem[pc]
   │   └─────┬─────┘
   │         │
   │         ▼
   │   ┌───────────┐
   │   │  S_EXEC   │  Execute the instruction
   │   └─────┬─────┘
   │         │
   │         │ if per-instruction delay ≠ 0
   │         ▼
   │   ┌───────────┐
   │   │  S_DELAY  │  Count down delay_cnt
   │   └─────┬─────┘
   │         │
   └─────────┘
```

The entire FSM only advances when `tick` is high. `tick` is generated by the clock divider, so the effective instruction rate is `clk_freq / (cfg_clkdiv_int + cfg_clkdiv_frac/256)`.

### 5.5 Clock divider

The clock divider is a 16-bit integer plus an 8-bit fractional accumulator (16.8 fixed-point). It produces a one-cycle `tick` pulse every `N + F/256` system clock cycles, where `N = cfg_clkdiv_int` and `F = cfg_clkdiv_frac`.

| Register | Range | Effect |
|---|---|---|
| `cfg_clkdiv_int` | 0–65535 | Integer part of divider |
| `cfg_clkdiv_frac` | 0–255 | Fractional part (adds up to 1 extra cycle per 256 ticks) |

Example: `cfg_clkdiv_int = 5207`, `cfg_clkdiv_frac = 0` produces a tick every 5207 cycles, giving exactly 9600 baud from a 50 MHz clock.

### 5.6 Autopull and autopush

**Autopull**: When the current instruction is `OUT` and `osr_count <= cfg_pull_thresh`, the engine automatically loads `osr` from `tx_fifo[tx_rd]`. The `OUT` instruction sees the freshly-loaded value, so there's no stall.

**Autopush**: When the current instruction is `IN` and `isr_count >= cfg_push_thresh`, the engine automatically writes `isr[7:0]` to `rx_fifo[rx_wr]`.

Both are gated on the *current* opcode so they don't fire during idle or `HALT` cycles.

### 5.7 FIFOs

Two 8-entry, 8-bit FIFOs:

- **TX FIFO**: data waiting to be transmitted. Written by the host FIFO interface or consumed by `PULL`/autopull.
- **RX FIFO**: received data. Read by the host FIFO interface or written by `PUSH`/autopush.

---

## 6. Instruction Set Reference

### 6.1 Encoding

Every instruction is 16 bits:

```
 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
┌────────────┬────────────┬───────────┬────┬─────────┐
│   opcode   │  operand   │  side_set │    │ delay   │
│  [15:12]   │  [11:8]    │  [7:4]    │[4] │ [3:0]   │
└────────────┴────────────┴───────────┴────┴─────────┘
```

- **opcode** (4 bits): selects the instruction
- **operand** (4 bits): instruction-specific parameter
- **side_set** (4 bits): value driven on pins 0–3 in parallel with the instruction (see §6.3)
- **delay** (4 bits): number of extra tick cycles to wait after execution (0 = no delay)

For `JMP`, the jump target is `{operand[3], side_set}`, giving a 5-bit target (0–31).

### 6.2 Instruction list

| Opcode | Mnemonic | Operand | Description |
|---|---|---|---|
| `0x0` | `NOP` | — | Do nothing |
| `0x1` | `JMP` | variant | Jump (see §6.4) |
| `0x2` | `WAIT` | pin/level | Wait until `uio_in[pin] == level` |
| `0x3` | `IN` | pin index | Shift `uio_in[pin]` into ISR |
| `0x4` | `OUT` | pin index | Shift OSR bit 0 to `pin_out[pin]` |
| `0x5` | `PUSH` | — | Move ISR[7:0] into RX FIFO |
| `0x6` | `PULL` | — | Move TX FIFO into OSR |
| `0x7` | `MOV` | variant | Move between registers (see §6.5) |
| `0x8` | `SET` | target | Set a target to `side_set` (see §6.6) |
| `0x9` | `IRQ` | — | Set the sticky internal IRQ-pending flag (cleared by reset) |
| `0xA` | `DELAY` | — | Wait for `{x_reg, y_reg}` ticks |
| `0xB` | `TOGGLE` | — | XOR `pin_out[3:0]` with `side_set` |
| `0xC` | `SAMPLE` | — | Atomically capture `uio_in` into ISR |
| `0xF` | `HALT` | — | Stop execution |

### 6.3 Side-set

Side-set is a value placed in bits `[7:4]` of every instruction. When the low `cfg_side_count` bits of `pin_out[3:0]` are affected, they are overwritten with `side_set` in the **same cycle** as the instruction's main action.

Example: `IN pin0` with `side_set = 0b0010` reads pin0 into ISR **and** drives pin1 high in the same cycle.

Side-set is **automatically suppressed** for `SET` and `TOGGLE`, which also modify `pin_out`, and for `WAIT`, which uses `side_set[0]` as an instruction control bit.

Set `cfg_side_count = 0` to disable side-set entirely.

### 6.4 Jump variants (operand[2:0])

| Operand | Meaning |
|---|---|
| `000`–`011` | Unconditional jump to `jump_tgt` |
| `100` | `JMP X--`: if `X != 0`, decrement X and jump; else fall through |
| `101` | `JMP Y--`: if `Y != 0`, decrement Y and jump; else fall through |
| `110` | `JMP !X`: if `X == 0`, jump; else fall through |
| `111` | `JMP !Y`: if `Y == 0`, jump; else fall through |

For `JMP X--` and `JMP Y--`, the target address must be **non-zero** (address 0 is the fall-through case).

### 6.5 MOV variants (operand[2:0])

| Operand | Source | Destination |
|---|---|---|
| `000` | X | OSR |
| `001` | OSR | X (low byte) |
| `010` | Y | OSR |
| `011` | OSR | Y (low byte) |
| `100` | `uio_in` | ISR |
| `101` | ISR | `pin_out` |
| `110` | X | `pin_out` |
| `111` | Y | `pin_out` |

### 6.6 SET variants (operand[2:0])

| Operand | Destination | Value |
|---|---|---|
| `000` | `pin_out[3:0]` | `side_set` |
| `001` | X | `side_set` |
| `010` | Y | `side_set` |
| `011` | `pin_oe[3:0]` | `side_set` |
| `100` | `pin_out[7:4]` | `side_set` |

### 6.7 WAIT variants (operand[1:0])

| `side_set[0]` | `operand[0]` | Meaning |
|---|---|---|
| `0` | `0` | Wait until selected pin is low |
| `0` | `1` | Wait until selected pin is high |
| `1` | `0` | Wait for a falling edge |
| `1` | `1` | Wait for a rising edge |

The pin index is `operand[3:1]`, giving all 8 pins for each wait condition. Edge transitions observed on `clk` are latched until a matching edge-wait consumes them, so a short pulse is not lost while the instruction engine is between ticks. For `WAIT`, `side_set[0]` selects edge mode and is not driven onto the output pins.

### 6.8 Per-instruction delay

Every instruction can specify a 4-bit delay. If `delay != 0`, the engine enters `S_DELAY` after executing, waiting `delay` ticks before fetching the next instruction.

This is useful for spacing out operations without an explicit `DELAY` instruction.

**Note**: `DELAY` (opcode `0xA`) uses `{x_reg, y_reg}` as a 16-bit delay, giving a much wider range (up to 65535 ticks).

---

## 7. Configuration Registers

Configuration registers are written by the host loader (§8.2). All default to safe values after reset.

| Address | Register | Width | Default | Purpose |
|---|---|---|---|---|
| 0 | `cfg_clkdiv_int[7:0]` | 8 | 0 | Clock divider integer low byte |
| 1 | `cfg_clkdiv_int[15:8]` | 8 | 0 | Clock divider integer high byte |
| 2 | `cfg_clkdiv_frac` | 8 | 0 | Clock divider fraction |
| 3 | `cfg_wrap_top` | 5 | 31 | Loop end index |
| 4 | `cfg_wrap_bottom` | 5 | 0 | Loop start index |
| 5 | `cfg_shift_dir` | 2 | 0 | 0 = right shift, 1 = left shift |
| 6 | `cfg_autopull` | 1 | 0 | Enable autopull |
| 7 | `cfg_autopush` | 1 | 0 | Enable autopush |
| 8 | `cfg_pull_thresh` | 5 | 0 | Pull when `osr_count <= this` |
| 9 | `cfg_push_thresh` | 5 | 31 | Push when `isr_count >= this` |
| 10 | `cfg_side_count` | 4 | 0 | Number of side-set bits (0–4) |

---

## 8. Host Loader Protocol

The host loader uses 4 pins of `uio_in` to load instructions and configuration data into the chip after reset.

### 8.1 Pin assignments

| Pin | Name | Purpose |
|---|---|---|
| `uio_in[0]` | DATA | One bit of data (MSB first) |
| `uio_in[1]` | CLK | Rising edge latches DATA |
| `uio_in[2]` | MODE | 0 = load imem, 1 = load config |
| `uio_in[3]` | ENABLE | 1 = loader active, 0 = run CPU |

### 8.2 Loading a program

1. Set `uio_in[3] = 1` (enable loader).
2. Set `uio_in[2] = 0` (imem mode).
3. For each instruction (16 bits), MSB first:
   - Set `uio_in[0] = bit_value`.
   - Pulse `uio_in[1]` high, then low.
4. After 32 instructions (or as many as you want to load), set `uio_in[3] = 0`.

The internal `load_addr` auto-increments after every 16 bits. You don't need to specify addresses.

### 8.3 Writing config registers

1. Set `uio_in[3] = 1` (enable loader).
2. Set `uio_in[2] = 1` (config mode).
3. For each config value (8 bits), MSB first:
   - Set `uio_in[0] = bit_value`.
   - Pulse `uio_in[1]` high, then low.
4. After writing, set `uio_in[3] = 0`.

The internal `load_addr` auto-increments after every 8 bits, so write them in the order shown in §7.

### 8.4 Reset behavior

When `uio_in[3]` goes from 1 to 0:

- `pc ← 0`
- FSM `state ← S_FETCH`
- `next_state ← S_FETCH`
- `osr_count ← 0`, `isr_count ← 0`
- `load_addr ← 0`

The program starts executing from address 0 on the next `tick`.

---

## 9. Example Programs

### 9.1 Blink pins

Sets pins 0–3 high, waits, sets them low, waits, and repeats.

```
Addr  Encoding    Disassembly            Comment
────  ──────────  ─────────────────────  ─────────────────────
0     0x80F0      SET pins[3:0] = 0xF    Idle high
1     0x8108      SET X = 8              Delay low
2     0x8208      SET Y = 8              Delay high
3     0xA000      DELAY                  Wait 0x0808 ticks
4     0x8000      SET pins[3:0] = 0x0    All low
5     0x8108      SET X = 8
6     0x8208      SET Y = 8
7     0xA000      DELAY
8     0x1000      JMP 0                  Loop forever
```

### 9.2 UART transmit at 9600 baud

Assume a 50 MHz clock and `cfg_clkdiv_int = 5207`, `cfg_clkdiv_frac = 0` — one tick per bit period.

```
Addr  Encoding    Disassembly            Comment
────  ──────────  ─────────────────────  ─────────────────────
0     0x80F0      SET pins = 0xF         Idle high (stop)
1     0x6000      PULL                   Load byte into OSR
2     0x8000      SET pins = 0x0         Start bit (low)
3     0x4000      OUT pin0               Send data bit 0
4     0x4000      OUT pin0               Send data bit 1
...                                       (8 OUTs total for 8 bits)
11    0x80F0      SET pins = 0xF         Stop bit (high)
12    0x1000      JMP 0                  Loop for next byte
```

The clock divider makes each `OUT` take exactly one bit period, so the firmware doesn't need explicit delays.

### 9.3 SPI mode 0 (CPOL=0, CPHA=0)

SPI mode 0: data is sampled on the rising edge of SCLK; idle SCLK is low.

- `pin_out[0]` = MOSI
- `pin_out[1]` = SCLK
- `pin_out[2]` = CS (active low)

```
Addr  Encoding    Disassembly                       Comment
────  ──────────  ────────────────────────────────  ───────────────────
0     0x80F2      SET pins = 0x2                    CS high, SCLK low
1     0x8002      SET pins = 0x0                    CS low (select)
2     0x6000      PULL                              Load byte
3     0x4000      OUT pin0  (MOSI = bit 0)         Data out
4     0x8120      SET pins = 0x2                    SCLK high (rising edge)
5     0x8000      SET pins = 0x0                    SCLK low
...                                                  (repeat OUT, SCLK for 8 bits)
19    0x8002      SET pins = 0x2                    CS high (deselect)
20    0x1000      JMP 0                             Loop
```

### 9.4 I2C START condition

I2C: SDA and SCL both idle high. START is SDA falling while SCL is high.

- `pin_out[0]` = SDA
- `pin_out[1]` = SCL

```
Addr  Encoding    Disassembly                       Comment
────  ──────────  ────────────────────────────────  ───────────────────
0     0x8033      SET pins = 0x3                    Both idle high
1     0x8202      SET Y = 2                         Y = 2 for DELAY
2     0x8102      SET X = 2                         X = 2 for DELAY
3     0xA000      DELAY                             Hold idle
4     0x8023      SET pins = 0x2                    SDA low, SCL high
5     0x8102      SET X = 2
6     0x8202      SET Y = 2
7     0xA000      DELAY
8     0x8002      SET pins = 0x0                    SCL low -> START complete
9     0xF000      HALT
```

---

## 10. Verification

This design uses **three layers** of verification. The competition explicitly weights verification heavily.

### 10.1 Directed tests

`test/tb.v` contains 23 directed test groups, including:

| Test groups | Coverage |
|---|---|
| 1–4 | Reset, `SET`, `TOGGLE`, and output enable |
| 5–12 | Delay, level `WAIT`, shifts, FIFOs, jumps, sampling, divider, and autopull |
| 13–16 | Random stress and UART/SPI/I2C examples |
| 17–20 | Wrap, IRQ latch, host FIFO, simultaneous transfers |
| 21–22 | Latched rising- and falling-edge `WAIT`, including a short pulse |
| 23 | Full TX/RX FIFO replacement transfers |

### 10.2 Constrained-random tests

`test/test_crv.py` runs a seeded constrained-random program of 31 terminating `NOP`, `SET`, and `TOGGLE` instructions through the real host loader. A small reference model checks `uo_out` after each instruction, and the test checks outputs for unknown values.

Run it with cocotb and Icarus Verilog installed:

```bash
python3 test/test_crv.py
```

This covers a constrained instruction subset; it is not yet a randomized reference model for the full ISA.

### 10.3 Formal verification

*The current properties are standalone models, not proofs of this RTL.*

The files in `formal/` currently check standalone delay and level-WAIT models; they are not bound to `protocol_engine`. Formal proofs of the RTL, including edge-WAIT behavior, remain incomplete.

- `DELAY` counts down by exactly 1 per tick until it reaches 0.
- `WAIT` releases only when the pin matches the requested level.
- The clock divider never glitches or skips ticks.
- Autopull fires only on `OUT` opcodes.

Example property for the delay engine:

```systemverilog
property p_cnt_decrement;
    @(posedge clk) disable iff (!rst_n)
    (busy && cnt != 0) |=> (cnt == $past(cnt) - 1);
endproperty
```

### 10.4 Running the tests

```bash
# Compile
iverilog -g2012 -o sim.vvp src/protocol_engine.v test/tb.v

# Run
vvp sim.vvp

# View waveforms
gtkwave tb.vcd
```

Expected output:

```
==========================================
 Protocol Engine Test Suite
==========================================
...
 Results: 45 passed, 0 failed
 ALL TESTS PASSED
==========================================
```

---

## 11. How to Simulate

### 11.1 Requirements

- **Icarus Verilog** (iverilog) — free, open-source simulator
- **GTKWave** — free waveform viewer
- Optional: **Verilator**, **cocotb**, **SymbiYosys**

### 11.2 Compile and run

```bash
cd path/to/protocol_engine
iverilog -g2012 -o sim.vvp src/protocol_engine.v test/tb.v
vvp sim.vvp
```

The `-g2012` flag enables SystemVerilog-2012 syntax.

### 11.3 View waveforms

```bash
gtkwave tb.vcd
```

Add these signals to the wave window:

- `clk`, `rst_n` — clock and reset
- `dut.pc` — program counter
- `dut.instr` — current instruction
- `dut.state` — FSM state
- `dut.pin_out`, `dut.pin_oe` — internal pin state
- `uo_out`, `uio_oe` — external outputs

### 11.4 Debugging tips

| Symptom | Likely cause |
|---|---|
| Output stuck at 0 | CPU may still be in load mode (`uio_in[3] = 1`) |
| Program doesn't start | Reset not released, or `tick` never fires |
| Instruction decode wrong | Check encoding against §6.1 |
| `JMP` goes to wrong address | Jump target is `{operand[3], side_set}` |
| Program hangs | `HALT` reached, or `WAIT` never satisfied |

---

## 12. How to Build for an ASIC

### 12.1 Prerequisites

- **Tiny Tapeout CMOS5L template** from GitHub
- **LibreLane** (or OpenLane 2) installed
- **IHP CMOS5L PDK** installed
- **Yosys** for synthesis
- **KLayout** for layout verification

### 12.2 Directory structure

```
protocol_emulator/
├── src/
│   └── protocol_engine.v
├── test/
│   ├── tb.v
│   └── test_crv.py
├── formal/
│   ├── delay_props.sv
│   ├── wait_props.sv
│   └── sby_delay.sby
├── docs/
│   └── info.md              ← this file
├── config.json
├── info.yaml
└── LICENSE
```

### 12.3 `info.yaml`

```yaml
project:
  title: "Protocol Engine State Machine"
  author: "Your Name"
  discord: ""
  description: "Reprogrammable protocol emulator with clock divider, autopull, and side-set. Targets UART, SPI, I2C."
  language: "Verilog"
  clock_hz: 50000000
  tiles: "6x4"
   top_module: "protocol_engine"
  source_files:
   - "src/protocol_engine.v"
  pinout:
    ui[0]: ""  ui[1]: ""  ui[2]: ""  ui[3]: ""
    ui[4]: ""  ui[5]: ""  ui[6]: ""  ui[7]: ""
    uo[0]: "PIN0"  uo[1]: "PIN1"  uo[2]: "PIN2"  uo[3]: "PIN3"
    uo[4]: "PIN4"  uo[5]: "PIN5"  uo[6]: "PIN6"  uo[7]: "PIN7"
    uio[0]: "HOST_DATA"  uio[1]: "HOST_CLK"
    uio[2]: "HOST_MODE"  uio[3]: "HOST_EN"
    uio[4]: "IO0"  uio[5]: "IO1"  uio[6]: "IO2"  uio[7]: "IO3"
yaml_version: 6
```

### 12.4 `config.json`

See the provided `config.json` for LibreLane/OpenLane settings. Key values:

- `CLOCK_PERIOD: 20` (50 MHz)
- `DIE_AREA: "0 0 1002 432"` (6×4 tiles)
- `PL_TARGET_DENSITY_PCT: 65`
- `FP_SIZING: absolute`

### 12.5 Run the flow

```bash
python3 -m librelane --pdk-root <path/to/ihp-pdk> ./config.json
```

This runs synthesis, floorplanning, placement, routing, and GDS generation. Expect 20–60 minutes on a modern machine.

### 12.6 Submission

1. Push to a GitHub repository.
2. Enable GitHub Actions in the repository settings.
3. Verify the "gds" workflow passes (green checkmark).
4. Go to `app.tinytapeout.com` and create a project.
5. Paste your GitHub URL.
6. Submit the revision.

### 12.7 Current status

Generic Yosys synthesis completes with no structural consistency problems. Its generic cell count is not an IHP CMOS5L standard-cell area estimate.

⚠️ **IHP CMOS5L-mapped synthesis, place-and-route, timing analysis, and GDS generation have not yet run.** The 6×4 fit and timing requirements therefore remain unverified; only the target-PDK flow can establish those results.

---

## 13. Design Decisions & Rationale

This section documents *why* certain choices were made, in case you're wondering or want to extend the design.

### 13.1 Why not use a generic ALU?

The competition explicitly says: don't build a general-purpose CPU with I/O bolted on. Every instruction in this ISA exists because some protocol needs it. `ADD`, `SUB`, `AND`, `OR`, `XOR` were deliberately excluded — they don't help bit-bang protocols, and they consume decode logic and area.

### 13.2 Why a 32-bit OSR/ISR?

The RP2040 PIO uses 32-bit shift registers. For protocols like USB (up to 12 Mbit/s) or Ethernet (10 Mbit/s), you want to buffer a full word of bits before refilling from the FIFO. 32 bits is a good balance between area and flexibility.

### 13.3 Why a fractional clock divider?

Integer dividers can't hit every baud rate exactly. For example, 9600 baud from 50 MHz requires a divide-by-5208.33. With an 8-bit fractional accumulator, you get exactly 9600 baud on average, with a maximum jitter of one system clock cycle.

### 13.4 Why is side-set disabled for SET and TOGGLE?

`SET` and `TOGGLE` also modify `pin_out`. If side-set were applied on the same cycle, you'd have a write conflict — two sources driving `pin_out[3:0]` in the same cycle. The design suppresses side-set for those opcodes to avoid the conflict. The compiler (or the human programmer) must use `SET` and side-set in separate instructions.

### 13.5 Why JMP target = {operand[3], side_set}?

This is a compromise. Ideally, the jump target would be a full 5-bit field independent of side-set. But 16 bits is tight, and we wanted:
- 4 bits for opcode
- 4 bits for operand (needed for JMP variants, MOV variants, SET variants)
- Some bits for side-set
- Some bits for delay

Packing the target's high bit with the operand and the low 4 bits with side-set gives a 5-bit target and preserves both side-set and delay for non-JMP instructions. JMPs cannot use side-set, but that's rarely needed.

### 13.6 Why a 4-bit per-instruction delay?

This lets every instruction generate a small pause without a full `DELAY`. It's useful for clock stretching, protocol timing margins, or when you need the CPU to do nothing for a few cycles. Combined with `DELAY` (16-bit), you have two ways to pause: short (cheap) and long (flexible).

### 13.7 Why autopull gated on `opcode == OUT`?

Without this gate, autopull would fire during `HALT` or `WAIT` cycles, consuming the TX FIFO before the program needed it. The gate ensures autopull happens exactly when `OUT` consumes a bit, making the FIFO-to-pin path transparent and stall-free.

### 13.8 What's NOT implemented (yet)

- **Wrap/loop**: `cfg_wrap_top`/`cfg_wrap_bottom` are defined but not used. Adding PIO-style wrap would eliminate the need for explicit `JMP` in tight loops.
- **IRQ**: `OP_IRQ` now latches a pending interrupt state internally. A full interrupt vector/host protocol is still future work.
- **Edge detection**: `WAIT` only supports level detection. Rising/falling edge would help with JTAG, SWD, CAN.
- **SRAM imem**: The instruction memory is currently a flop array. Swapping to an SRAM macro would save area and allow more instructions.
- **Host FIFO port**: A minimal external host FIFO path is now implemented on the loader/control pins for TX/RX access. Full host-side protocol hardening is still future work.

---

## 14. Competition Requirements Checklist

A condensed list. The project currently meets the core protocol-emulation requirements in simulation and testing. Remaining unchecked items refer to the final ASIC flow (synthesis, P&R, and silicon validation), which must still be run before claiming a finished tapeout submission.

### Core design

- [x] Open-source (Apache-2.0)
- [x] Protocol-centric ISA
- [x] Reprogrammable after fabrication
- [x] Not a UART/SPI/I2C block
- [x] Not a general-purpose CPU

### Architecture

- [x] Shift registers (OSR/ISR)
- [x] Autopull/autopush
- [x] Clock divider (fractional)
- [x] Side-set
- [x] Wide delay (16-bit)
- [x] Level detection in WAIT
- [x] Atomic multi-pin sampling (SAMPLE)
- [x] 5-bit jump target
- [x] Loop wrap mechanism
- [x] IRQ support (basic pending latch)
- [x] Host FIFO interface

### Protocols

- [x] UART working in firmware (example provided and validated)
- [x] SPI working in firmware (example provided and validated)
- [x] I2C working in firmware (example provided and validated)
- [ ] USB low-speed (stretch)
- [ ] Ethernet 10Mbit (stretch)

### Process & tooling

- [x] Target IHP CMOS5L
- [x] Use CMOS5L template
- [x] 6×4 tile size
- [ ] Run IHP CMOS5L-mapped synthesis
- [ ] Run P&R
- [ ] Check timing
- [ ] Verify area fits with margin

> The design is functionally complete for protocol emulation in simulation, but the physical ASIC flow still needs to be executed for final competition compliance.

### Verification

- [x] Directed tests (20 tests)
- [ ] Constrained-random tests (cocotb)
- [ ] Formal verification (SymbiYosys)
- [ ] Coverage analysis
- [ ] FPGA testing

### Documentation

- [x] `docs/info.md` (this file)
- [ ] `info.yaml`
- [ ] `config.json`
- [ ] LICENSE
- [ ] README.md

---

## 15. Further Reading

### Beginner-friendly

- **"Digital Design and Computer Architecture"** by Harris & Harris — the classic textbook on digital design.
- **Nand2Tetris** (nand2tetris.org) — build a computer from NAND gates up.
- **"The Elements of Computing Systems"** by Nisan & Schocken — companion to Nand2Tetris.

### Intermediate

- **RP2040 Datasheet, Chapter 3 (PIO)** — the primary inspiration for this chip. Essential reading.
- **"FPGA Prototyping by Verilog Examples"** by Pong P. Chu — teaches Verilog via projects.
- **Tiny Tapeout documentation** (tinytapeout.com) — how the manufacturing flow works.

### Advanced

- **"Computer Organization and Design"** by Patterson & Hennessy — deeper processor theory.
- **"Advanced ASIC Chip Synthesis"** by Himanshu Bhatnagar — the synthesis/P&R flow in detail.
- **OpenLane / LibreLane documentation** — the open-source P&R toolchain.
- **SymbiYosys documentation** — formal verification for Verilog.

### Related designs

- **RP2040 PIO** — the gold standard for protocol engines.
- **TI PRU** — Texas Instruments' take on the same idea.
- **RISC-V** — a modern open-source CPU architecture (for contrast).
- **8051, AVR, MSP430** — classic 8-bit microcontrollers (for historical context).

### Tools used in this project

| Tool | Purpose | URL |
|---|---|---|
| Icarus Verilog | Simulation | iverilog.icarus.com |
| GTKWave | Waveform viewer | gtkwave.sourceforge.net |
| Yosys | Synthesis | yosyshq.net/yosys |
| SymbiYosys | Formal verification | yosyshq.readthedocs.io/projects/sby |
| cocotb | Python testbenches | cocotb.org |
| LibreLane | Place & route | librelane.readthedocs.io |
| Tiny Tapeout | Manufacturing | tinytapeout.com |

---