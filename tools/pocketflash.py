#!/usr/bin/env python3
"""Validate PocketFlash backups and prepare deterministic experiment images."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib

ROM_SIZE = 32 * 1024 * 1024
SECTOR_SIZE = 128 * 1024


def check_rom_size(size):
    if size < 192 or size > ROM_SIZE or size % 4:
        raise ValueError("ROM must be 192 bytes..32 MiB and a multiple of four bytes")


def inspect_backup(path):
    path = Path(path)
    record = path.with_suffix(".pfr").read_bytes()
    if len(record) != 16:
        raise ValueError(f"{path}: invalid completion record length")
    magic, size, expected_crc, flags = struct.unpack("<4sIII", record)
    if magic != b"PFR1" or flags not in (1, 3) or size != ROM_SIZE:
        raise ValueError(f"{path}: invalid completion record")
    digest = hashlib.sha256()
    crc = 0
    length = 0
    with path.open("rb") as stream:
        while chunk := stream.read(65536):
            digest.update(chunk)
            crc = zlib.crc32(chunk, crc)
            length += len(chunk)
    if length != size or crc != expected_crc:
        raise ValueError(f"{path}: incomplete or corrupt dump (size={length}, CRC32={crc:08X})")
    return {
        "path": str(path),
        "bytes": length,
        "crc32": f"{crc:08x}",
        "sha256": digest.hexdigest(),
        "completion": "readback verified" if flags == 3 else "legacy completion",
    }


def inspect_save(path):
    path = Path(path)
    record = path.with_suffix(".pfs").read_bytes()
    if len(record) != 16:
        raise ValueError("Invalid save completion record length")
    magic, size, crc, flags = struct.unpack("<4sIII", record)
    data = path.read_bytes()
    if (
        magic != b"PFS1"
        or size != 131072
        or flags != 3
        or len(data) != size
        or zlib.crc32(data) != crc
    ):
        raise ValueError("Incomplete or corrupt save backup")
    return {
        "path": str(path),
        "bytes": size,
        "crc32": f"{crc:08x}",
        "sha256": hashlib.sha256(data).hexdigest(),
        "completion": "readback verified",
    }


def diagnostic_rom():
    # Address-dependent first/last 512-byte pages, except all-FF sector 64.
    # Private acceptance input, deliberately not a bootable game.
    data = bytearray(b"\xff" * ROM_SIZE)
    for sector in range(256):
        if sector == 64:
            continue
        for offset in (sector * SECTOR_SIZE, (sector + 1) * SECTOR_SIZE - 512):
            for n in range(0, 512, 2):
                address = offset + n
                struct.pack_into("<H", data, address, (address ^ (address >> 16) ^ 0x5AA5) & 65535)
    return bytes(data)


def verify_backups(paths):
    if len(paths) != 3 or len({Path(p).resolve() for p in paths}) != 3:
        raise ValueError("Supply three distinct complete backup files")
    records = [inspect_backup(p) for p in paths]
    if len({r["sha256"] for r in records}) != 1:
        raise ValueError("Backups differ; do not proceed to cartridge writes")
    return {"result": "three identical complete backups", "backups": records}


def compare_rom(image, dump):
    image, dump = Path(image), Path(dump)
    check_rom_size(image.stat().st_size)
    if dump.stat().st_size != ROM_SIZE:
        raise ValueError("Readback must cover the entire 32 MiB cartridge")
    offset = 0
    with image.open("rb") as source, dump.open("rb") as target:
        while actual := target.read(65536):
            expected = source.read(len(actual)).ljust(len(actual), b"\xff")
            if expected != actual:
                pos = next(i for i, (a, b) in enumerate(zip(expected, actual)) if a != b)
                raise ValueError(
                    f"Mismatch at byte 0x{offset+pos:08X}: expected {expected[pos]:02X}, read {actual[pos]:02X}"
                )
            offset += len(actual)
    return {"result": "full cartridge matches ROM plus FF padding", "bytes": offset}


def inspect_rom(path):
    path = Path(path)
    size = path.stat().st_size
    check_rom_size(size)
    raw_sha, padded_sha = hashlib.sha256(), hashlib.sha256()
    raw_crc = padded_crc = program_buffers = 0
    header = b""
    with path.open("rb") as stream:
        for offset in range(0, ROM_SIZE, 65536):
            length = min(65536, max(0, size - offset))
            data = stream.read(length)
            if len(data) != length:
                raise ValueError("ROM changed while inspecting")
            if offset == 0:
                header = data[:192]
            raw_sha.update(data)
            raw_crc = zlib.crc32(data, raw_crc)
            padded = data.ljust(65536, b"\xff")
            padded_sha.update(padded)
            padded_crc = zlib.crc32(padded, padded_crc)
            program_buffers += sum(
                padded[n : n + 512] != b"\xff" * 512 for n in range(0, 65536, 512)
            )
        if stream.read(1):
            raise ValueError("ROM changed while inspecting")
    return {
        "path": str(path),
        "bytes": size,
        "padded_bytes": ROM_SIZE,
        "title": header[0xA0:0xAC].rstrip(b"\0").decode("ascii", "replace"),
        "header_valid": header[0xB2] == 0x96 and ((sum(header[0xA0:0xBE]) + 0x19) & 255) == 0,
        "crc32": f"{raw_crc:08x}",
        "sha256": raw_sha.hexdigest(),
        "padded_crc32": f"{padded_crc:08x}",
        "padded_sha256": padded_sha.hexdigest(),
        "program_buffers": program_buffers,
    }


def verify_write(image, dump):
    backup = inspect_backup(dump)
    if backup["completion"] != "readback verified":
        raise ValueError("Write acceptance requires SD readback verified completion (flags 3)")
    comparison = compare_rom(image, dump)
    return {"result": "verified full-ROM export", "backup": backup, "comparison": comparison}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    save = commands.add_parser("inspect-save")
    save.add_argument("path", type=Path)
    diagnostic = commands.add_parser("diagnostic-rom")
    diagnostic.add_argument("output", type=Path)
    inspect = commands.add_parser("inspect-rom")
    inspect.add_argument("image", type=Path)
    written = commands.add_parser("verify-write")
    written.add_argument("image", type=Path)
    written.add_argument("dump", type=Path)
    verify = commands.add_parser("verify-backups")
    verify.add_argument("paths", nargs=3, type=Path)
    compare = commands.add_parser("compare-rom")
    compare.add_argument("image", type=Path)
    compare.add_argument("dump", type=Path)
    args = parser.parse_args()
    if args.command == "inspect-save":
        result = inspect_save(args.path)
    elif args.command == "diagnostic-rom":
        with args.output.open("xb") as stream:
            stream.write(diagnostic_rom())
        result = inspect_rom(args.output)
    elif args.command == "inspect-rom":
        result = inspect_rom(args.image)
    elif args.command == "verify-write":
        result = verify_write(args.image, args.dump)
    elif args.command == "verify-backups":
        result = verify_backups(args.paths)
    elif args.command == "compare-rom":
        result = compare_rom(args.image, args.dump)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        sys.exit(f"Verification failed: {error}")
