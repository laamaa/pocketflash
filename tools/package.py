#!/usr/bin/env python3
"""Package a successful, current Quartus build. Never create placeholder bitstreams."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

from build_inputs import source_hashes
from build import mode_macros

ROOT = Path(__file__).resolve().parents[1]
REVERSE = bytes(int(f"{n:08b}"[::-1], 2) for n in range(256))
REQUIRED_DEFINITIONS = ("core", "audio", "data", "input", "interact", "variants", "video")


def validate_definitions(core):
    """Check required APF files and the bitstream filename before packaging."""
    definitions = {}
    for name in REQUIRED_DEFINITIONS:
        path = core / f"{name}.json"
        if not path.is_file():
            raise ValueError(f"Missing required core definition: {path.name}")
        definition = json.loads(path.read_text()).get(name)
        if not isinstance(definition, dict) or definition.get("magic") != "APF_VER_1":
            raise ValueError(f"Invalid APF definition: {path.name}")
        definitions[name] = definition
    variants = definitions["variants"].get("variant_list")
    if not isinstance(variants, list) or len(variants) > 8:
        raise ValueError("variants.json must contain a variant_list array of at most 8 entries")
    bitstreams = definitions["core"].get("cores")
    if not isinstance(bitstreams, list) or len(bitstreams) != 1:
        raise ValueError("PocketFlash requires exactly one bitstream")
    filename = bitstreams[0].get("filename")
    if (
        not isinstance(filename, str)
        or len(filename) > 15
        or not filename.endswith(".rbf_r")
        or "/" in filename
        or "\\" in filename
    ):
        raise ValueError(
            "Bitstream filename must be a basename ending in .rbf_r, at most 15 characters"
        )
    return filename


PACKAGE_FILES = tuple(
    "Cores/PocketFlash.PocketFlash/" + name + ".json" for name in REQUIRED_DEFINITIONS
) + (
    "Assets/pocketflash/common/.gitkeep",
    "Saves/pocketflash/common/.gitkeep",
    "Platforms/pocketflash.json",
)
GUIDE_FILES = (
    "docs/user-guide.md",
    "LICENSE",
    "NOTICE.md",
    "docs/APF-NOTICE.txt",
    "config/apf-provenance.json",
)


def validate_inventory(template):
    actual = {p.relative_to(template).as_posix() for p in template.rglob("*") if p.is_file()}
    if actual != set(PACKAGE_FILES) or any(p.is_symlink() for p in template.rglob("*")):
        raise ValueError("Package inventory differs from explicit template inventory")


def package(root, mode):
    if mode != "utility":
        raise ValueError(f"Unsupported package mode: {mode}; use utility")
    (root / "dist/pocketflash-0.2.0-beta.1-candidate.zip").unlink(missing_ok=True)
    validate_inventory(root / "pkg")
    for name in GUIDE_FILES:
        if not (root / name).is_file() or (root / name).is_symlink():
            raise ValueError("Required guide/provenance file missing: " + name)
    build = root / "build" / mode
    manifest = json.loads((build / "build.json").read_text())
    if manifest["mode"] != mode or not manifest["timing_checked"]:
        raise ValueError("Build is missing timing acceptance")
    if manifest.get("persistent_operations", False) != True:
        raise ValueError("Persistent-operation metadata does not match package mode")
    expected_scope = "full-ROM"
    if manifest.get("write_scope") != expected_scope or manifest.get(
        "verilog_macros"
    ) != mode_macros(mode):
        raise ValueError("Write scope/macros do not match compiled mode")
    if source_hashes(root) != manifest["source_sha256"]:
        raise ValueError("Source changed since compilation; rebuild before packaging")
    rbf = (build / "src/output_files/pocketflash.rbf").read_bytes()
    if len(rbf) < 1024 or hashlib.sha256(rbf).hexdigest() != manifest["rbf_sha256"]:
        raise ValueError("Bitstream does not match the successful build")
    filename = validate_definitions(root / "pkg/Cores/PocketFlash.PocketFlash")
    dest = root / "dist" / mode
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    for name in PACKAGE_FILES:
        target = dest / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / "pkg" / name, target)
    core = dest / "Cores/PocketFlash.PocketFlash"
    (core / filename).write_bytes(rbf.translate(REVERSE))
    (dest / "build.json").write_text(json.dumps(manifest, indent=2) + "\n")
    docs = dest / "PocketFlash Guide"
    docs.mkdir()
    for name in GUIDE_FILES:
        shutil.copyfile(root / name, docs / Path(name).name)
    checksums = {
        p.relative_to(dest).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(dest.rglob("*"))
        if p.is_file()
    }
    (dest / "checksums.json").write_text(json.dumps(checksums, indent=2) + "\n")
    shutil.make_archive(str(root / "dist/pocketflash-0.2.0-beta.1-candidate"), "zip", dest)
    print(f"SD package: {dest} ({mode})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["utility"], default="utility")
    args = parser.parse_args()
    try:
        package(ROOT, args.mode)
    except (OSError, ValueError, KeyError) as error:
        sys.exit(f"Packaging stopped: {error}")
