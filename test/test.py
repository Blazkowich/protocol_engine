"""Cocotb test that works for both the RTL and gate-level flows.

Works under either HDL top:
  * `tb` (the tt-gds-action template; tb.v does NOT generate clk, so the
    test must drive it) — used by `make` / gl_test.
  * `tt_um_protocol_engine` (DUT as top) — used by run_tests.py --all.

In both cases this test owns the clock.

Includes:
  * A 1 ns settle after every RisingEdge before reading DUT outputs, so
    Icarus has time to propagate non-blocking assignments in the GL netlist.
  * Extra margin after leaving load mode, so the FSM can fall through
    load_mode -> S_FETCH -> S_EXEC before the first instruction retires.
"""
import os
import random
import tempfile
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer


async def _reset_dut(dut):
    """Start the clock (tb.v does not provide one), then release reset."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.ena.value    = 1
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.rst_n.value  = 0

    # Hold reset across several full clock periods (10 ns half-period here).
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")


@cocotb.test()
async def constrained_random_stress(dut):
    """Compare random terminating pin operations with a golden model."""
    await _reset_dut(dut)

    rng = random.Random(42)
    program = []
    expected_trace = []
    expected_pin_out = 0
    for _ in range(31):
        opcode = rng.choice((0x0, 0x8, 0xB))
        value = rng.randrange(16)
        if opcode == 0x8:
            instruction = (opcode << 12) | (value << 4)
            expected_pin_out = value
        elif opcode == 0xB:
            instruction = (opcode << 12) | (value << 4)
            expected_pin_out ^= value
        else:
            instruction = 0
        program.append(instruction)
        expected_trace.append(expected_pin_out)
    program.append(0xF000)

    # ---- Load the program through the real host-loader protocol ------------
    # Enter load mode (uio[3]=1) with imem selected (uio[2]=0).
    await FallingEdge(dut.clk)
    dut.uio_in.value = 0x08
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    for instr in program:
        for b in range(15, -1, -1):
            bit = (instr >> b) & 1
            await FallingEdge(dut.clk)
            dut.uio_in.value = 0x08 | bit      # data bit, LOAD_CLK low
            await RisingEdge(dut.clk)
            await Timer(1, unit="ns")
            await FallingEdge(dut.clk)
            dut.uio_in.value = 0x0A | bit      # LOAD_CLK high latches the bit
            await RisingEdge(dut.clk)
            await Timer(1, unit="ns")
            await FallingEdge(dut.clk)
            dut.uio_in.value = 0x08 | bit      # LOAD_CLK low for next bit

    # ---- Leave load mode; CPU resets PC and starts executing ---------------
    await FallingEdge(dut.clk)
    dut.uio_in.value = 0x00
    # Alignment: edge 1 clears load_mode, edge 2 is FETCH, edge 3 is EXEC of
    # instr 0 (pin_out updates). Each later instruction takes 2 cycles. The
    # compare loop below waits 2 cycles per instruction, so only 2 cycles of
    # margin go here; any more and the check samples instr k+1's result.
    for _ in range(2):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

    # ---- Compare each instruction's effect on uo_out against the model -----
    for _, expected_output in zip(program[:-1], expected_trace):
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")
        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")

        assert dut.uo_out.value.is_resolvable, (
            f"uo_out has X (expected 0x{expected_output:02X})"
        )
        assert dut.uio_oe.value.is_resolvable, "uio_oe has X"
        assert int(dut.uo_out.value) == expected_output, (
            f"expected 0x{expected_output:02X}, got "
            f"0x{int(dut.uo_out.value):02X}"
        )
        assert int(dut.uio_oe.value) == 0

    dut._log.info("Constrained-random test passed: 31 modeled instructions")


def run():
    """Standalone entry point used by run_tests.py --all.

    Builds the DUT as the HDL top (no tb.v), then invokes this module as
    the cocotb test module. The clock is started inside the test itself.
    """
    from cocotb_tools.runner import get_runner

    project_dir = Path(__file__).resolve().parents[1]
    test_dir = Path(__file__).resolve().parent

    def run_in_build_dir(build_dir):
        build_dir.mkdir(parents=True, exist_ok=True)
        runner = get_runner("icarus")
        runner.build(
            sources=[project_dir / "src" / "tt_um_protocol_engine.v"],
            hdl_toplevel="tt_um_protocol_engine",
            build_dir=build_dir,
            always=True,
        )
        runner.test(
            hdl_toplevel="tt_um_protocol_engine",
            test_module=Path(__file__).stem,
            test_dir=test_dir,
            build_dir=build_dir,
            results_xml=str(build_dir / "results.xml"),
            extra_env={"PYTHONDONTWRITEBYTECODE": "1"},
        )

    configured_build_dir = os.environ.get("PESM_COCOTB_BUILD_DIR")
    if configured_build_dir:
        run_in_build_dir(Path(configured_build_dir))
    else:
        with tempfile.TemporaryDirectory(prefix="protocol_engine_cocotb_") as temp_dir:
            run_in_build_dir(Path(temp_dir))


if __name__ == "__main__":
    run()