"""Run the directed RTL regression and, optionally, the cocotb test."""

import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def run_command(label, command, cwd, env=None):
    print(f"\n== {label} ==", flush=True)
    print(" ".join(str(part) for part in command), flush=True)
    result = subprocess.run(command, cwd=cwd, env=env, check=False)
    if result.returncode != 0:
        print(f"{label} failed with exit code {result.returncode}.", file=sys.stderr)
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--all",
        action="store_true",
        help="run the directed Icarus suite and the cocotb reference-model test",
    )
    args = parser.parse_args()

    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if not iverilog or not vvp:
        print(
            "Icarus Verilog is required. Install iverilog and vvp, then ensure "
            "both commands are on PATH.",
            file=sys.stderr,
        )
        return 2

    if args.all and importlib.util.find_spec("cocotb") is None:
        print(
            "The cocotb test requires the test dependencies. Install them with "
            "python -m pip install -r test/requirements-test.txt.",
            file=sys.stderr,
        )
        return 2

    with tempfile.TemporaryDirectory(prefix="protocol_engine_tests_") as temp_dir:
        build_dir = Path(temp_dir)
        simulation = build_dir / "sim.vvp"
        compile_result = run_command(
            "Directed regression: compile",
            [
                iverilog,
                "-g2012",
                "-o",
                str(simulation),
                str(ROOT / "src" / "tt_um_protocol_engine.v"),
                str(ROOT / "test" / "tb.v"),
            ],
            build_dir,
        )
        if compile_result != 0:
            return compile_result

        directed_result = run_command(
            "Directed regression: simulate", [vvp, str(simulation)], build_dir
        )
        if directed_result != 0:
            return directed_result

        if args.all:
            env = os.environ.copy()
            env["PESM_COCOTB_BUILD_DIR"] = str(build_dir / "cocotb")
            crv_result = run_command(
                "Cocotb reference-model test",
                [sys.executable, str(ROOT / "test" / "test_crv.py")],
                ROOT,
                env,
            )
            if crv_result != 0:
                return crv_result

    print("\nAll requested tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())