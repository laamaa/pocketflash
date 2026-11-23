#!/usr/bin/env python3
"""Prepare a curated local source snapshot. Never initializes/publishes a repository."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
INVENTORY = ROOT / "config/public-files.json"
FILES = frozenset(json.loads(INVENTORY.read_text())["files"])


def allowed(name):
    p = PurePosixPath(name)
    return not p.is_absolute() and ".." not in p.parts and name in FILES


def prepare(root=ROOT):
    status = subprocess.check_output(
        ["git", "status", "--porcelain", "--untracked-files=normal"], cwd=root, text=True
    )
    if status.strip():
        raise ValueError("Commit the tested source before preparing a public snapshot")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    tracked = set(
        filter(
            None, subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
        )
    )
    missing = FILES - tracked
    if missing:
        raise ValueError(
            "Release inventory contains untracked or missing files: " + ", ".join(sorted(missing))
        )
    # Validate the entire input before replacing a previous usable snapshot.
    # Iterating only tracked files used to silently skip missing inventory entries.
    for name in FILES:
        if not allowed(name):
            raise ValueError("Unsafe release inventory path: " + name)
        source = root / name
        if source.is_symlink():
            raise ValueError("Public snapshot excludes symlinks: " + name)
        if not source.is_file():
            raise ValueError("Release inventory file is missing: " + name)
    destination = root / "dist/public-source"
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    hashes = {}
    for name in sorted(FILES):
        source = root / name
        dest = destination / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, dest)
        hashes[name] = hashlib.sha256(dest.read_bytes()).hexdigest()
    (destination / "TESTED-SOURCE.json").write_text(
        json.dumps(
            {
                "source_commit": commit,
                "sha256": hashes,
            },
            indent=2,
        )
        + "\n"
    )
    shutil.make_archive(
        str(root / "dist/pocketflash-public-source-candidate"), "gztar", destination
    )
    print(destination)
    return destination


if __name__ == "__main__":
    argparse.ArgumentParser(description=__doc__).parse_args()
    try:
        prepare()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
