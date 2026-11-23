import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import pocketflash as p


class WriteToolsTests(unittest.TestCase):
    def test_inspection_reports_raw_and_padded_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "target.gba"
            image.write_bytes(b"\x12" * 192)
            expected = b"\x12" * 192 + b"\xff" * (p.ROM_SIZE - 192)
            report = p.inspect_rom(image)
            self.assertEqual(report["bytes"], 192)
            self.assertEqual(report["padded_bytes"], 33554432)
            self.assertEqual(report["program_buffers"], 1)
            self.assertEqual(report["crc32"], f"{zlib.crc32(image.read_bytes()):08x}")
            self.assertEqual(report["padded_crc32"], f"{zlib.crc32(expected):08x}")
            self.assertEqual(report["padded_sha256"], hashlib.sha256(expected).hexdigest())
            output = subprocess.check_output(
                [sys.executable, "tools/pocketflash.py", "inspect-rom", str(image)], text=True
            )
            self.assertEqual(json.loads(output), report)
            image.write_bytes(b"x" * 193)
            with self.assertRaises(ValueError):
                p.inspect_rom(image)

    def test_verified_export_requires_flags3_and_matches_every_padded_byte(self):
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "target.gba"
            image.write_bytes(b"\x34" * 192)
            dump = Path(directory) / "dump.gba"
            data = image.read_bytes() + b"\xff" * (p.ROM_SIZE - 192)
            dump.write_bytes(data)

            def record(flags):
                dump.with_suffix(".pfr").write_bytes(
                    struct.pack("<4sIII", b"PFR1", p.ROM_SIZE, zlib.crc32(dump.read_bytes()), flags)
                )

            record(1)
            with self.assertRaisesRegex(ValueError, "readback"):
                p.verify_write(image, dump)
            record(3)
            self.assertEqual(
                p.verify_write(image, dump)["backup"]["sha256"], hashlib.sha256(data).hexdigest()
            )
            with dump.open("r+b") as stream:
                stream.seek(192)
                stream.write(b"\x00")
            record(3)
            with self.assertRaisesRegex(ValueError, "000000C0"):
                p.verify_write(image, dump)
