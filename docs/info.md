## How it works

The **Protocol Engine State Machine (PESM)** is a small, reprogrammable protocol
engine. It is not a fixed UART/SPI/I2C peripheral, and it is not a
general-purpose CPU. It is a 16-bit-instruction machine whose ISA is built
around the primitives that bit-banging a serial protocol actually needs:
reading pins, writing pins, shifting bits, waiting on edges, counting cycles,
and moving bytes through FIFOs.

### Core blocks

- **Instruction memory** — 32 × 16-bit words, loaded by the host after reset.
- **PESM core** — a three-state FSM (`S_FETCH`, `S_EXEC`, `S_DELAY`) driving
  the program counter, X/Y scratch registers, an 8-bit `pin_out` latch, an
  8-bit `pin_oe` latch, and 32-bit OSR/ISR shift registers.
- **Fractional clock divider** — 16-bit integer + 8-bit fraction (16.8
  fixed-point) producing a one-cycle `tick` that gates the FSM. At 50 MHz,
  `cfg_clkdiv_int = 2604` and `cfg_clkdiv_frac = 43` approximate a 9600-baud
  bit period when each `OUT` is two ticks apart.
- **TX / RX FIFOs** — two 8 × 8-bit queues with autopull and autopush
  thresholds. `PULL`/autopull refills the OSR from TX; `PUSH`/autopush drains
  the ISR into RX.
- **Host loader / host FIFO interface** — a 4-wire serial port on `uio[3:0]`
  used both to load instructions and config bytes before execution, and (in
  run mode) to read/write the FIFOs from an external host.

### Instruction summary

| Opcode | Mnemonic | Purpose                                                  |
| ------ | -------- | -------------------------------------------------------- |
| `0x0`  | `NOP`    | Do nothing                                               |
| `0x1`  | `JMP`    | Unconditional or conditional (`X--`, `Y--`, `!X`, `!Y`)  |
| `0x2`  | `WAIT`   | Level or edge wait on any of the 8 logical protocol pins |
| `0x3`  | `IN`     | Shift a selected logical input bit into the ISR          |
| `0x4`  | `OUT`    | Shift one OSR bit to a pin; open-drain OE mode           |
| `0x5`  | `PUSH`   | Move `ISR[7:0]` to RX FIFO                               |
| `0x6`  | `PULL`   | Move TX FIFO into OSR                                    |
| `0x7`  | `MOV`    | Register ↔ OSR/ISR/`pin_out` transfers                   |
| `0x8`  | `SET`    | Set `pin_out`, `pin_oe`, X, or Y from `side_set`         |
| `0x9`  | `IRQ`    | Set the sticky IRQ-pending latch                         |
| `0xA`  | `DELAY`  | Wait `{X, Y}` ticks                                      |
| `0xB`  | `TOGGLE` | XOR `pin_out[3:0]` with `side_set`                       |
| `0xC`  | `SAMPLE` | Atomically capture all 8 logical inputs into the ISR     |
| `0xF`  | `HALT`   | Stop execution                                           |

Each instruction carries a 4-bit `side_set` field (driven on pins 0–3 in
parallel, suppressible via `cfg_side_count`/`cfg_side_oe`) and a 4-bit
per-instruction `delay`. For `JMP`, the 5-bit target is
`{operand[3], side_set}`.

### Pin mapping

| Signal         | Direction | Purpose                                                        |
| -------------- | --------- | -------------------------------------------------------------- |
| `ui_in[3:0]`   | in        | Logical protocol inputs 4–7                                    |
| `ui_in[7:4]`   | in        | Host TX data byte when the loader/FIFO host writes             |
| `uo_out[7:0]`  | out       | `pin_out[7:0]`, or the host RX byte when a host read is active |
| `uio_in[0]`    | in        | `HOST_DATA` / `LOAD_DIN`                                       |
| `uio_in[1]`    | in        | `HOST_CLK` / `LOAD_CLK`                                        |
| `uio_in[2]`    | in        | `HOST_MODE` / `LOAD_SEL` (0 = imem, 1 = config)                |
| `uio_in[3]`    | in        | `LOAD_EN` (high = loader active, low = run)                    |
| `uio_in[7:4]`  | in        | Logical protocol inputs 0–3                                    |
| `uio_out[7:4]` | out       | Output values for logical protocol pins 0–3                    |
| `uio_oe[7:4]`  | out       | Output enables for logical protocol pins 0–3 (1 = drive)       |
| `uio[3:0]`     | —         | Host loader / host FIFO control pins                           |

## How to test

### Directed regression (no external tools beyond Icarus)

```bash
iverilog -g2012 -o sim.vvp src/tt_um_protocol_engine.v test/tb.v
vvp sim.vvp
```
