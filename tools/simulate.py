#!/usr/bin/env python3
"""Run real HDL testbenches; absence of a simulator is an error, never a pass."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def simulate_bench(bench, dest, output):
    executable = dest / bench.stem
    sources = [str(p) for p in sorted((ROOT / "src/core").glob("*.v"))]
    sources += [str(p) for p in sorted((ROOT / "tests").glob("*_model.v"))]
    warnings = ["-Wall"]
    if bench.stem == "tb_bridge":
        # Quartus accepts procedural inout regs; Icarus requires explicit
        # output drivers on nets. Adapt declarations only, not bus logic.
        source = (ROOT / "src/apf/io_bridge_peripheral.v").read_text()
        source = source.replace("inout   reg", "inout   wire")
        declarations = []
        for name in ("phy_spimosi", "phy_spimiso", "phy_spiclk"):
            declarations.append(f"reg {name}_drive; assign {name}={name}_drive;")
            source = source.replace(f"{name} <=", f"{name}_drive <=")
        for name in ("rx_byte", "rx_byte_done"):
            source, count = re.subn(
                r"^\s*reg\s+(?:\[7:0\]\s+)?" + name + r";[^\n]*", "", source, flags=re.MULTILINE
            )
            if count != 1:
                raise ValueError(f"Cannot adapt APF declaration: {name}")
        declarations += ["reg [7:0] rx_byte; reg rx_byte_done;"]
        source = source.replace(");", ");\n" + "\n".join(declarations), 1)
        peripheral = dest / "io_bridge_peripheral.v"
        peripheral.write_text(source)
        sources += [str(ROOT / "src/apf/common.v"), str(peripheral)]
        # Preserve vendor sources, which do not declare their timescale.
        warnings += ["-Wno-timescale"]
    subprocess.run(
        ["iverilog", "-g2012"]
        + warnings
        + ["-s", bench.stem, "-o", str(executable), str(bench)]
        + sources,
        check=True,
        stdout=output,
        stderr=subprocess.STDOUT,
    )
    subprocess.run(
        ["vvp", str(executable)],
        check=True,
        stdout=output,
        stderr=subprocess.STDOUT,
        timeout=(900 if bench.stem.startswith("tb_utility_") else 120),
    )


def run_bench(bench, dest):
    start = time.monotonic()
    passed = True
    with tempfile.TemporaryFile(mode="w+") as output:
        try:
            simulate_bench(bench, dest, output)
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            passed = False
            print(f"HDL verification failed: {error}", file=output)
        output.seek(0)
        log = output.read()
    return passed, time.monotonic() - start, log


def run_benches(benches, dest, jobs):
    start = time.monotonic()
    failures = []
    with ThreadPoolExecutor(max_workers=jobs) as executor:
        futures = {executor.submit(run_bench, bench, dest): bench for bench in benches}
        for future in as_completed(futures):
            bench = futures[future]
            passed, seconds, output = future.result()
            status = "PASS" if passed else "FAIL"
            print(f"{status} {bench.stem} ({seconds:.2f}s)\n{output}", end="", flush=True)
            if not passed:
                failures.append(bench.stem)
    print(
        f"HDL suite: {len(benches)} benches, {jobs} worker(s), {time.monotonic() - start:.2f}s",
        flush=True,
    )
    if failures:
        raise ValueError("Failed HDL benches: " + ", ".join(sorted(failures)))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--jobs", "-j", type=int, default=1, help="number of parallel HDL benches (default: 1)"
    )
    args = parser.parse_args(argv)
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")
    if not shutil.which("iverilog") or not shutil.which("vvp"):
        sys.exit(
            "HDL simulation requires Icarus Verilog (iverilog and vvp). Run: devenv shell -- make test-hdl"
        )
    dest = ROOT / "build/sim"
    dest.mkdir(parents=True, exist_ok=True)
    run_benches(sorted((ROOT / "tests").glob("tb_*.sv")), dest, args.jobs)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(f"HDL verification failed: {error}")
