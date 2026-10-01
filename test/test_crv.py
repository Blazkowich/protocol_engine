import random
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

@cocotb.test()
async def constrained_random_stress(dut):
    """Compare random terminating pin operations with a golden model."""
    cocotb.start_soon(Clock(dut.clk, 20, unit="step").start())
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await Timer(100, unit="step")
    dut.rst_n.value = 1
    await Timer(40, unit="step")

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

    await FallingEdge(dut.clk)
    dut.uio_in.value = 0x08
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")
    for instr in program:
        for b in range(15, -1, -1):
            bit = (instr >> b) & 1
            await FallingEdge(dut.clk)
            dut.uio_in.value = 0x08 | bit
            await RisingEdge(dut.clk)
            await Timer(1, unit="step")
            await FallingEdge(dut.clk)
            dut.uio_in.value = 0x0A | bit
            await RisingEdge(dut.clk)
            await Timer(1, unit="step")
            await FallingEdge(dut.clk)
            dut.uio_in.value = 0x08 | bit

    await FallingEdge(dut.clk)
    dut.uio_in.value = 0x00
    await RisingEdge(dut.clk)
    await Timer(1, unit="step")

    for instr, expected_output in zip(program[:-1], expected_trace):
        await RisingEdge(dut.clk)
        await Timer(1, unit="step")
        await RisingEdge(dut.clk)
        await Timer(1, unit="step")
        assert dut.uo_out.value.is_resolvable, "uo_out has X"
        assert dut.uio_oe.value.is_resolvable, "uio_oe has X"
        assert int(dut.uo_out.value) == expected_output
        assert int(dut.uio_oe.value) == 0

    dut._log.info("Constrained-random test passed: 31 modeled instructions")


def run():
    from cocotb_tools.runner import get_runner

    project_dir = Path(__file__).resolve().parents[1]
    test_dir = Path(__file__).resolve().parent
    build_dir = Path("/tmp/pesm_cocotb_build")
    runner = get_runner("icarus")
    runner.build(
        sources=[project_dir / "src" / "protocol_engine.v"],
        hdl_toplevel="protocol_engine",
        build_dir=build_dir,
        always=True,
    )
    runner.test(
        hdl_toplevel="protocol_engine",
        test_module=Path(__file__).stem,
        test_dir=test_dir,
        build_dir=build_dir,
        results_xml=str(build_dir / "results.xml"),
        extra_env={"PYTHONDONTWRITEBYTECODE": "1"},
    )


if __name__ == "__main__":
    run()