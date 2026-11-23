#!/usr/bin/env python3
"""Build PocketFlash in the pinned amd64 Quartus image; never replace a VM."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from build_inputs import source_hashes

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "config/quartus-image.lock"
TAG = "docker.io/raetro/quartus:pocket"


def run(args, *, capture=False, env=None):
    print("+", " ".join(map(str, args)), flush=True)
    return subprocess.run(
        list(map(str, args)),
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        env=env,
    )


def runtime():
    selected = os.environ.get("CONTAINER_RUNTIME") or (
        "container" if sys.platform == "darwin" else "podman"
    )
    if selected not in ("container", "podman"):
        raise ValueError("CONTAINER_RUNTIME must be container or podman")
    return selected


def connection():
    explicit = os.environ.get("PODMAN_CONNECTION", "")
    if explicit:
        return explicit
    if sys.platform != "darwin":
        return ""
    connections = json.loads(
        run(["podman", "system", "connection", "list", "--format", "json"], capture=True).stdout
    )
    candidates = [
        c["Name"] for c in connections if "apple" in c["Name"] or "pocketflash" in c["Name"]
    ]
    if not candidates:
        raise ValueError(
            "No AppleHV build connection found. Run make setup-podman, or set PODMAN_CONNECTION."
        )
    # Use a named connection, leaving Podman's global default alone.
    return next((n for n in candidates if n.endswith("-root")), candidates[0])


def podman():
    name = connection()
    return ["podman", "--connection", name] if name else ["podman"]


def setup():
    if runtime() == "container":
        run(["container", "system", "start"])
        return
    if sys.platform != "darwin":
        run(["podman", "info"])
        return
    try:
        name = connection().removesuffix("-root")
    except ValueError:
        name = "pocketflash-build"
        env = dict(os.environ, CONTAINERS_MACHINE_PROVIDER="applehv")
        run(
            [
                "podman",
                "machine",
                "init",
                "--cpus",
                "8",
                "--memory",
                "12288",
                "--disk-size",
                "64",
                name,
            ],
            env=env,
        )
    config = Path.home() / ".config/containers/podman/machine/applehv" / f"{name}.json"
    if not config.exists():
        raise ValueError(
            f"{name} is not an AppleHV machine; select an AppleHV connection explicitly."
        )
    machine = json.loads(config.read_text())
    nested = machine.get("AppleHypervisor", {}).get("Vfkit", {}).get("Rosetta", False)
    if not (nested or machine.get("Rosetta", False)):
        raise ValueError(
            f"Rosetta is disabled on {name}. Enable it in Podman Desktop for this machine."
        )
    env = dict(os.environ, CONTAINERS_MACHINE_PROVIDER="applehv")
    info = json.loads(run(["podman", "machine", "inspect", name], capture=True, env=env).stdout)[0]
    if info.get("State") != "running":
        run(["podman", "machine", "start", name], env=env)
    print(
        f"Using {name}; AppleHV and Rosetta configured. Run make toolchain to verify Quartus execution."
    )


def container(reference, command, *, workdir="/build", capture=False):
    if runtime() == "container":
        # Apple has no --pull=never flag. Require an already cached image first.
        run(["container", "image", "inspect", reference], capture=True)
        return run(
            [
                "container",
                "run",
                "--rm",
                "--platform",
                "linux/amd64",
                "--cpus",
                "8",
                "--memory",
                "12G",
                "--network",
                "none",
                "--volume",
                f"{ROOT}:/build:rw",
                "--workdir",
                workdir,
                reference,
            ]
            + command,
            capture=capture,
        )
    return run(
        podman()
        + [
            "run",
            "--rm",
            "--platform",
            "linux/amd64",
            "--pull=never",
            "--network",
            "none",
            "--volume",
            f"{ROOT}:/build:rw",
            "--workdir",
            workdir,
            reference,
        ]
        + command,
        capture=capture,
    )


def toolchain():
    apple = runtime() == "container"
    engine = ["container"] if apple else podman()
    if not apple:
        run(engine + ["info"], capture=True)
    if LOCK.exists():
        locked = json.loads(LOCK.read_text())
        if not re.fullmatch(r"docker\.io/raetro/quartus@sha256:[0-9a-f]{64}", locked["reference"]):
            raise ValueError("Invalid image lock reference")
        reference = locked["reference"]
        # Pull by digest, so a changed registry tag cannot change this toolchain.
        pull = ["image", "pull"] if apple else ["pull"]
        run(engine + pull + ["--platform", "linux/amd64", reference])
    else:
        if apple:
            raise ValueError("Restore config/quartus-image.lock before using Apple container")
        run(engine + ["pull", "--platform", "linux/amd64", TAG])
        inspected = json.loads(run(engine + ["image", "inspect", TAG], capture=True).stdout)[0]
        if inspected["Architecture"] != "amd64" or inspected["Os"] != "linux":
            raise ValueError("Expected linux/amd64 Quartus image")
        digest = inspected.get("Digest", "")
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
            raise ValueError("Podman did not return an immutable image digest")
        reference = "docker.io/raetro/quartus@" + digest
    version = container(reference, ["quartus_sh", "--version"], capture=True).stdout.strip()
    if "Quartus" not in version:
        raise ValueError("Quartus executable did not report a version")
    LOCK.write_text(
        json.dumps(
            {
                "reference": reference,
                "source_tag": TAG,
                "architecture": "linux/amd64",
                "quartus_version": version,
            },
            indent=2,
        )
        + "\n"
    )
    print(version)
    return json.loads(LOCK.read_text())


def mode_macros(mode):
    if mode != "utility":
        raise ValueError(f"Unsupported build mode: {mode}; use utility")
    return {"POCKETFLASH_UTILITY": 1}


def build(mode):
    macros = mode_macros(mode)
    target = ROOT / "build" / mode
    # An unsuccessful attempt must not leave an old SD package looking current.
    (ROOT / "dist/pocketflash-0.2.0-beta.1-candidate.zip").unlink(missing_ok=True)
    (target / "build.json").unlink(missing_ok=True)
    shutil.rmtree(ROOT / "dist" / mode, ignore_errors=True)
    if not LOCK.exists():
        locked = toolchain()
    else:
        locked = json.loads(LOCK.read_text())
    staged = target / "src"
    snapshot = source_hashes(ROOT)
    shutil.rmtree(staged, ignore_errors=True)
    shutil.copytree(
        ROOT / "src",
        staged,
        ignore=shutil.ignore_patterns("db", "incremental_db", "output_files", "*.qws"),
    )
    for name, digest in snapshot.items():
        if (
            name.startswith("src/")
            and hashlib.sha256((target / name).read_bytes()).hexdigest() != digest
        ):
            raise ValueError(f"Source changed while staging: {name}")
    with (staged / "pocketflash.qsf").open("a") as f:
        for name, value in macros.items():
            f.write(f'\nset_global_assignment -name VERILOG_MACRO "{name}={value}"\n')
    workdir = f"/build/build/{mode}/src"
    # Remove old success manifests before starting; failed builds cannot package stale outputs.
    manifest = target / "build.json"
    version = container(
        locked["reference"], ["quartus_sh", "--version"], capture=True
    ).stdout.strip()
    if version != locked["quartus_version"]:
        raise ValueError("Quartus version differs from the recorded toolchain")
    container(
        locked["reference"], ["quartus_sh", "--flow", "compile", "pocketflash"], workdir=workdir
    )
    container(
        locked["reference"],
        ["quartus_sta", "-t", "/build/tools/check_timing.tcl", "pocketflash"],
        workdir=workdir,
    )
    rbf = staged / "output_files/pocketflash.rbf"
    if not rbf.exists() or rbf.stat().st_size < 1024:
        raise ValueError("Quartus did not produce a valid RBF")
    if source_hashes(ROOT) != snapshot:
        raise ValueError("Sources changed during compilation; rebuild before packaging")
    manifest.write_text(
        json.dumps(
            {
                "mode": mode,
                "toolchain": locked,
                "container_runtime": runtime(),
                "rbf_sha256": hashlib.sha256(rbf.read_bytes()).hexdigest(),
                "timing_checked": True,
                "hardware_tested": False,
                "persistent_operations": True,
                "write_scope": "full-ROM",
                "verilog_macros": macros,
                "source_sha256": snapshot,
            },
            indent=2,
        )
        + "\n"
    )
    run([sys.executable, ROOT / "tools/package.py", "--mode", mode])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["setup", "toolchain", "build", "clean"])
    parser.add_argument("--mode", choices=["utility"], default="utility")
    parser.add_argument("--runtime", choices=["container", "podman"])
    args = parser.parse_args()
    if args.runtime:
        os.environ["CONTAINER_RUNTIME"] = args.runtime
    if args.action == "setup":
        setup()
    elif args.action == "toolchain":
        toolchain()
    elif args.action == "build":
        build(args.mode)
    else:
        for name in ("build", "dist"):
            shutil.rmtree(ROOT / name, ignore_errors=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"Build stopped: {error}")
