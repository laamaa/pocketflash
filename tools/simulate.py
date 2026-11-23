#!/usr/bin/env python3
"""Run real HDL testbenches; absence of a simulator is an error, never a pass."""
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    if not shutil.which("iverilog") or not shutil.which("vvp"):
        sys.exit(
            "HDL simulation requires Icarus Verilog (iverilog and vvp). Run: devenv shell -- make test-hdl"
        )
    dest = ROOT / "build/sim"
    dest.mkdir(parents=True, exist_ok=True)
    for bench in sorted((ROOT / "tests").glob("tb_*.sv")):
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
        )
        subprocess.run(
            ["vvp", str(executable)],
            check=True,
            timeout=(900 if bench.stem.startswith("tb_utility_") else 120),
        )


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.SubprocessError) as error:
        sys.exit(f"HDL verification failed: {error}")
