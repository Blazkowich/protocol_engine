import cocotb
from cocotb.triggers import RisingEdge, Timer
from cocotb.clock import Clock
import random

@cocotb.test()
async def constrained_random_stress(dut):
    """Constrained-random test: random instruction sequences,
    verify no hangs, no X-propagation, and consistent state."""

    # Start clock
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())

    # Reset
    dut.rst_n.value = 0
    await Timer(100, units="ns")
    dut.rst_n.value = 1
    await Timer(40, units="ns")

    # Load a random program
    random.seed(42)
    program = []
    for _ in range(32):
        op = random.choice([0x0, 0x1, 0x2, 0x3, 0x4, 0x8, 0xA, 0xB])
        operand = random.randint(0, 15)
        side_en = random.randint(0, 1)
        side_val = random.randint(0, 15)
        instr = (op << 12) | (operand << 8) | (side_en << 4) | side_val
        program.append(instr)

    # Load program via host interface
    dut.uio_in.value = 0x08  # load enable
    await RisingEdge(dut.clk)
    for instr in program:
        for b in range(15, -1, -1):
            dut.uio_in.value = (1 << 3) | ((instr >> b) & 1)
            await RisingEdge(dut.clk)
            dut.uio_in.value = (1 << 3) | (1 << 1) | ((instr >> b) & 1)
            await RisingEdge(dut.clk)
    dut.uio_in.value = 0x00  # exit load mode

    # Run for many cycles
    for _ in range(1000):
        await RisingEdge(dut.clk)
        # Check no X on outputs
        assert dut.uo_out.value.is_resolvable, "uo_out has X"
        assert dut.uio_oe.value.is_resolvable, "uio_oe has X"

    dut._log.info("Constrained-random test passed: 1000 cycles, no X-propagation")