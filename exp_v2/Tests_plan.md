# Protocol Engine End-to-End Verification Plan

## Goal

Establish evidence that the programmable protocol engine correctly implements its documented RTL behavior, accepts programs and configuration through the external host interface, and can execute a declared set of protocol firmware profiles. Verification progresses from RTL simulation through digital gate-level simulation when a suitable netlist and cell models are available.

This plan does not claim that simulation proves FPGA operation, IHP CMOS5L area or timing, place-and-route, GDS readiness, or fabricated-silicon behavior. Those remain separate future signoff activities.

## Scope and Baseline

The system under test is the `protocol_engine` top module from `src/protocol_engine.v`, selected by `info.yaml`. Do not compile `src/protocol_engine_ge.v` together with it; that file also defines a module named `protocol_engine`.

The existing baseline is 24 directed test groups and 77 checks in `test/tb.v`. The cocotb reference model in `test/test_crv.py` covers terminating `NOP`, `SET`, and `TOGGLE` programs only. The properties in `formal/` currently prove standalone models, not the RTL DUT. Existing UART/SPI/I2C demonstrations are selected firmware examples, not complete protocol-stack verification.

## Completion Criteria

The emulation verification effort is complete when all of the following are true:

- Every documented instruction, configuration field, external interface behavior, and supported protocol-profile requirement maps to one or more executable tests or to an explicit unsupported status.
- Directed tests pass with no unknown or high-impedance values on outputs that are required to be driven.
- The reference-model regression is deterministic, reports its seed, and covers the mandatory opcode and interaction bins listed below.
- RTL-bound formal properties pass under documented assumptions; standalone properties are not counted as DUT proof.
- Digital gate-level checks pass when a usable synthesized netlist and functional cell models are available. If unavailable, record the blocker and do not claim that gate-level verification is complete.
- Logs identify the RTL revision, simulator/tool versions, seed, test results, and any excluded/unsupported behavior.
- FPGA and ASIC physical/silicon signoff are reported separately from this emulation completion status.

## Stage 0: Freeze the Behavioral Contract

Before adding expectations, compare `README.md` with `src/protocol_engine.v`, `info.yaml`, and the current testbench. Create a requirements matrix with a test ID and expected observable result for every supported behavior.

Resolve these ambiguities explicitly before treating them as pass/fail requirements:

- Reserved/unused opcode behavior and invalid operand encodings.
- Instruction and configuration loader address rollover at the end of the 32-word memory or 12 configuration registers.
- Partial instruction/configuration transfers, mode changes mid-transfer, and reset during a transfer.
- Exact effects of reset versus leaving loader mode. Loader exit restarts PC/FSM and clears OSR/ISR counts, but is not a full reset.
- Timing points for fetch, execute, tick, immediate delay, wide delay, stalls, and wrap correction.
- FIFO behavior when host and engine request transfers on the same clock edge.
- Which UART, SPI, and I2C variants and error/recovery behaviors are part of the supported firmware profile.

Resolve the instruction-memory reset description against implementation: uninitialized/invalid words must be observed as HALT after reset, including after partial program loads.

## Stage 1: Build, Elaboration, and Static Checks

- Compile the canonical RTL and directed testbench with Icarus Verilog; compile failures are immediate test failures.
- Elaborate each supported top-level configuration and verify the expected top module and port widths.
- Run available lint checks and review inferred latches, undriven signals, width truncation, and multiple drivers. Waivers must name the signal, reason, and owner.
- Check the documented source list; never include both files that define `protocol_engine` in one build.
- Run synthesis and record module/cell statistics as a structural check only. Synthesis statistics do not establish target-PDK area, timing, routing, or GDS readiness.

## Stage 2: Reset, Clock Divider, and Instruction Memory

### Reset

- Assert active-low reset between clock edges and verify asynchronous reset effects where specified.
- Verify initial output values, output enables, FSM state, PC, configuration defaults, counters, pointers, and pending edge/IRQ state.
- Reset during fetch, execute, delay, level/edge wait, loader transfer, and FIFO activity; verify the documented reset state and no stale pending events.
- Verify reset release and first instruction execution timing.
- Verify invalid/unwritten instruction words execute as HALT and partially loaded programs leave untouched addresses at HALT behavior.
- Verify FIFO storage contents are not relied on after reset when occupancy/pointers mark them empty.

### Divider

- Test integer divisors 0, 1, 2, maximum, and representative interior values.
- Test fractional values 0, 1, 127, 128, and 255, including reset/restart during a fractional sequence.
- Check exact tick pulse width, interval sequence, carry handling, long-run pulse count, and average period against an independent arithmetic model.
- Verify reconfiguration takes effect according to the documented cycle semantics; check for missing, repeated, or multi-cycle ticks.

### Instruction Memory

- Through the serial loader, write and read back representative words at address 0, interior addresses, and address 31.
- Verify MSB-first order, exactly 16 rising host-clock edges per word, address advancement, start/reset behavior, and consecutive writes.
- Verify partial words do not corrupt a completed neighboring word and determine/document overflow behavior after 32 words.

## Stage 3: External Host Loader and Configuration Interface

Use only top-level ports for these tests; internal hierarchical register pokes do not count as interface evidence.

- Load programs using `uio_in[0]` DATA, `uio_in[1]` CLK, `uio_in[2]` MODE, and `uio_in[3]` ENABLE. Verify MSB-first capture and edge qualification.
- Exercise all 12 configuration addresses in documented order, with boundary and alternating-bit values that reveal field width, byte order, and truncation errors.
- Read back configuration through behavior wherever possible (for example, divider timing, wrap, shift direction, side-set, thresholds); do not assume internal values are externally readable.
- Verify first/last config address, repeated config writes, incomplete bytes, switching MODE mid-byte, clock held high/low, and ENABLE transitions.
- Verify host loader entry, active loading, loader exit, PC/FSM restart, count clearing, and retained state that is not reset by loader exit.
- Verify external FIFO mode selection and that controls are level-sensitive while selected: a sustained read/write request may transfer on each eligible system-clock edge.
- Verify output mux selection: host RX data appears on `uo_out` only under the documented FIFO read condition; otherwise protocol output is visible.

## Stage 4: Complete ISA and FSM Directed Coverage

For each test, check the relevant externally observable result and, when useful, internal state using a separate internal-unit test. Keep interface tests independent of hierarchical probes.

| Instruction      | Required cases                                                                                                                                                                                             |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `NOP`            | Advance, side-set interaction, immediate delay, wrap boundary.                                                                                                                                             |
| `JMP`            | Unconditional targets 0 and 31; X-- and Y--; `!X` and `!Y`; zero/nonzero conditions; fall-through; wrap interaction.                                                                                       |
| `WAIT`           | Low/high waits on all eight logical inputs; release and remain stalled; rising/falling edge waits on all inputs; pulse shorter than tick; edge event retained/consumed once; edge and level mode encoding. |
| `IN`             | Every input index; repeated shifts; count behavior; both shift-register boundaries; interaction with autopush threshold.                                                                                   |
| `OUT`            | Every output index; LSB-first/MSB-first; OSR shifting/count behavior; open-drain mode and output-enable transitions; side-set conflict rules; autopull before output.                                      |
| `PUSH`           | Successful transfer; full FIFO stall; simultaneous host dequeue; ISR value/count behavior.                                                                                                                 |
| `PULL`           | Successful transfer; empty FIFO stall; simultaneous host enqueue; OSR placement for both shift directions.                                                                                                 |
| `MOV`            | All eight documented variants; source/destination values and untouched bits.                                                                                                                               |
| `SET`            | Every valid target; low/high pin groups; X/Y; output enable; side-set suppression; invalid target behavior.                                                                                                |
| `IRQ`            | Pending flag sets once and remains sticky until reset; no unintended external pin effect.                                                                                                                  |
| `DELAY`          | Zero count, one tick, representative count, maximum 16-bit count, and interruption/reset behavior.                                                                                                         |
| `TOGGLE`         | Zero/all-bit masks, repeated toggles, upper/lower pin behavior, side-set suppression.                                                                                                                      |
| `SAMPLE`         | Atomic capture of all eight logical inputs; mapping across `uio_in[7:4]` and `ui_in[3:0]`; ISR count and following instruction.                                                                            |
| `HALT`           | PC/FSM remains halted across many ticks; outputs and flags remain stable unless separately specified host behavior changes them.                                                                           |
| Reserved opcodes | Verify only after the contract defines expected handling.                                                                                                                                                  |

For each opcode, also cover delay nibble values 0, 1, and 15 where applicable, and ensure the instruction retires exactly once unless it is specified to stall or halt.

## Stage 5: Pins, Side-Set, Open-Drain, and Integration

- Exhaustively verify the logical input map: pins 0–3 from `uio_in[7:4]`, pins 4–7 from `ui_in[3:0]`.
- Verify output value and enable routing to `uio_out[7:4]` and `uio_oe[7:4]`; verify unused `uio[3:0]` output bits remain as documented.
- Test side-set counts 0 through 4, value and output-enable destinations, masking, and suppression on `SET`, `TOGGLE`, and `WAIT`.
- Model external pull-ups and wired-AND for open-drain pins. Verify release reads high, low drive reads low, and no instruction drives a shared open-drain line high.
- Check same-cycle side-set plus `IN`/`OUT`/`MOV` behavior, including documented side-set conflict restrictions.
- Exercise `ena` at both values and confirm it has no unintended behavior if the design contract continues to treat it as unused.
- Test reset, loader entry/exit, and host FIFO mode while pins are active; verify no unintended glitches, stale output enables, or output-mux leakage.

## Stage 6: FIFO and Host/Engine Concurrency

Test TX and RX independently and together:

- Empty, one element, full, and all occupancy transitions.
- Pointer wraparound through all eight entries; FIFO ordering across multiple wraps.
- Enqueue while empty, dequeue while one element, rejected enqueue at full, and rejected dequeue at empty.
- Simultaneous host enqueue/engine dequeue and engine enqueue/host dequeue, both with space and at full capacity.
- Sustained level-sensitive host controls over multiple cycles, including mode changes while asserted.
- Verify count/pointer conservation and that a rejected/stalled operation neither loses nor duplicates data.
- Verify explicit `PULL` stalls on empty and `PUSH` stalls on full; verify autopull/autopush gating, threshold boundaries, and same-cycle host replacement cases.
- Check host read data timing and `uo_out` mux behavior at request assertion/deassertion.

## Stage 7: End-to-End Protocol Firmware

Drive every protocol example through the external host loader and host FIFO, then observe pins with reusable protocol monitors and target models. Avoid hierarchical setup in these tests.

- **UART:** Supported baud/divider range, start/data/stop timing, LSB-first byte values `0x00`, `0xFF`, `0x55`, and `0xA5`; receive path if claimed; back-to-back bytes and spacing; malformed start/stop and reset/abort cases if receive is supported.
- **SPI:** For each claimed mode, validate clock polarity/phase, bit order, MOSI and MISO paths, chip-select assertion/deassertion, setup/hold timing, back-to-back transfers, and transfer boundaries. Do not claim untested modes.
- **I2C:** Open-drain START, address/data bit order, ACK and NACK, repeated START, STOP, read/write paths, and line release. Clock stretching, arbitration, and retry behavior are out of scope unless explicitly added to the supported profile.
- Include long transfers and FIFO refill/drain during traffic, divider changes only where allowed, and reset/loader interruption recovery.
- Define each profile's legal program, configuration, expected trace, timing tolerance, and unsupported cases beside its test.

## Stage 8: Constrained-Random and Coverage Closure

- Extend `test/test_crv.py` or add focused cocotb suites to generate legal programs across the full documented ISA, with bounded termination or explicit stall/halt expectations.
- Use an independent cycle/tick-aware reference model. Compare outputs, output enables, transaction traces, and selected architectural state; fail on unexpected X/Z values.
- Randomize legal host loading, configuration, input-pin transitions, host FIFO traffic, and asynchronous reset timing under reproducible constraints.
- Print and retain random seeds; minimize failures and convert them to directed regressions.
- Maintain functional coverage bins for opcode/variant, all input/output pins, shift direction, side-set count/destination, WAIT mode/result, divider integer/fraction boundary, FIFO occupancy and simultaneous-operation pair, loader mode/partial transfer, and protocol outcomes.
- Require all mandatory bins and agreed high-risk cross-bins to hit. Any unreachable bin must have a documented reason and approved exclusion.
- Make build paths portable; the current CRV runner uses `/tmp/pesm_cocotb_build`, which must be addressed for Windows CI.

## Stage 9: Formal Verification Bound to the DUT

Create a formal harness around `protocol_engine` or bind properties directly to it. The current standalone `delay_props.sv` and `wait_props.sv` are examples only and do not prove RTL behavior.

Candidate safety properties:

- Reset establishes documented state and outputs; no unknown architectural outputs after reset release under legal inputs.
- PC and wrap behavior stay within the 0–31 address space.
- Divider tick is one cycle wide and obeys the specified integer/fraction interval rules.
- FIFO counts remain in 0–8; pointers advance only on accepted transfers; accepted enqueue/dequeue conserves data/order under the chosen abstraction.
- Stalled `WAIT`, `PUSH`, and `PULL` do not retire or mutate unrelated architectural state.
- Autopull/autopush occur only for their specified opcodes and threshold/space conditions.
- Open-drain outputs never actively drive high; output-enable/pin mapping obeys the contract.
- Loader-exit effects match the documented partial restart and do not silently become a full reset.

Document clock/reset/input assumptions, proof depth/engine, covers for progress, and any unsupported liveness claims. Prove safety first; add liveness only with explicit fairness assumptions.

## Stage 10: Gate-Level Regression and Automation

- Produce a digital synthesized netlist from the canonical RTL with the exact synthesis flow recorded.
- Run reset, loader/config, representative ISA, FIFO, pin, and protocol smoke tests on the netlist with compatible functional cell models.
- Check output X/Z, reset recovery, timing-sensitive handshakes, and observable equivalence against RTL traces where equivalence is defined.
- Automate separate jobs for RTL directed tests, CRV, formal, lint/elaboration, synthesis statistics, and gate-level tests. Preserve logs, seeds, netlist/tool versions, and pass/fail summaries.
- Keep simulation build outputs out of tracked source directories or clean only artifacts produced by the current run.
- A missing PDK/library/netlist model is a documented blocker, not a passing gate.

## Stage 11: Separate Hardware Signoff

These are not part of the RTL/gate-level emulation-complete claim:

- FPGA prototype validation, if selected as an intermediate target.
- IHP CMOS5L mapped synthesis, area with margin, timing constraints and reports.
- Floorplan, placement, clock tree, routing, DRC/LVS, GDS generation, and shuttle/template integration.
- Post-silicon reset, loader, pin electrical behavior, divider timing, and protocol measurements on fabricated hardware.

Track these in a separate ASIC/board signoff checklist with tool versions, reports, waivers, and measured evidence. Never infer these results from RTL simulation.

## Execution Order and Deliverables

1. Freeze the behavior matrix and settle open specification questions.
2. Add external-interface reset/loader/config tests and memory/divider/FIFO unit tests.
3. Complete directed ISA, pin, integration, and protocol-monitor tests.
4. Expand the independent CRV model and close mandatory coverage bins.
5. Bind and run DUT formal properties.
6. Add automated lint, synthesis, and gate-level gates as tool support permits.
7. Publish a verification summary listing passed gates, excluded features, residual risks, seeds, and blocked hardware signoff.

Keep RTL tests under `test/`, formal collateral under `formal/`, and this roadmap in `exp_v2/`. Update `README.md` whenever supported behavior or verification status changes.

## Current Commands and Evidence

Directed Icarus regression:

```powershell
iverilog -g2012 -o sim.vvp src/protocol_engine.v test/tb.v
vvp sim.vvp
```

Constrained-random regression, after making its build directory portable:

```powershell
python3 test/test_crv.py
```

Current evidence is the README's 77 directed checks plus the constrained `NOP`/`SET`/`TOGGLE` cocotb model. Do not describe the current state as full-ISA randomized verification, DUT formal verification, gate-level verification, FPGA validation, or ASIC signoff until those respective gates have passing evidence.
