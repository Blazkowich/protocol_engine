# Repository Guidance

- Read [README.md](README.md) for the architecture, ISA, configuration/host interfaces, and ASIC-flow details; use it as the project reference rather than duplicating it here.
- The top-level module is `protocol_engine` in `src/protocol_engine.v`. Keep the design a programmable, protocol-centric engine; do not replace that flexibility with fixed UART/SPI/I2C blocks or turn it into a general-purpose CPU.
- `src/protocol_engine.v` is the canonical RTL used by `info.yaml` and the tests. `src/protocol_engine_ge.v` also defines `protocol_engine`; do not compile both files together.
- Keep the named divider, instruction-memory, and FIFO-storage submodules hierarchical for TeroHDL schematics. Its `proc; opt` schematic shows generic Yosys cells such as `$adffe-bus`; changing RTL signal names does not rename those primitive labels.
- RTL lives in `src/`; keep directed and cocotb tests in `test/`.
- For RTL changes, run the directed regression with Icarus Verilog: `iverilog -g2012 -o sim.vvp src/protocol_engine.v test/tb.v`, then `vvp sim.vvp`. The testbench writes `tb.vcd` in the current directory; when isolating outputs in a temporary build directory, compile using absolute paths to both source files.
- `python3 test/test_crv.py` runs the cocotb constrained-random test when cocotb and Icarus are installed. Its reference model covers only terminating `NOP`, `SET`, and `TOGGLE` programs; it is not full-ISA coverage.
- Some directed tests configure internal registers hierarchically for convenience. Do not treat those checks as validation of the external configuration interface; use the host-loader tests or add an interface-level test when changing that path.
- Host FIFO read/write controls are level-sensitive while FIFO mode is selected. Leaving loader mode restarts the PC/FSM and clears OSR/ISR counts, but is not a full reset; preserve these distinctions when changing host behavior.
- The files in `formal/` prove standalone delay/WAIT models, not properties of the RTL. Do not claim RTL formal verification without binding properties to the DUT.
- Keep verification claims evidence-based: simulation results do not establish IHP CMOS5L area, timing, place-and-route, or GDS readiness. See the README's current ASIC-flow status before making such claims.
- When changing instruction behavior, host loading, pin behavior, or configuration, update the focused testbench coverage and relevant README reference material.
