import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

spec = importlib.util.spec_from_file_location(
    "pf", Path(__file__).resolve().parents[1] / "tools/pocketflash.py"
)
pf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pf)


class SaveTools(unittest.TestCase):
    def test_save_record(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "save0001.sav"
            data = bytes(range(256)) * 512
            p.write_bytes(data)
            p.with_suffix(".pfs").write_bytes(
                struct.pack("<4sIII", b"PFS1", len(data), zlib.crc32(data), 3)
            )
            self.assertEqual(pf.inspect_save(p)["bytes"], 131072)
            p.write_bytes(data[:-1] + b"\x00")
            with self.assertRaises(ValueError):
                pf.inspect_save(p)

    def test_diagnostic(self):
        data = pf.diagnostic_rom()
        self.assertEqual(len(data), 33554432)
        self.assertEqual(
            sum(data[n : n + 512] != b"\xff" * 512 for n in range(0, len(data), 512)), 510
        )
        self.assertEqual(data[64 * 131072 : 65 * 131072], b"\xff" * 131072)
        self.assertNotEqual(
            data[127 * 131072 : 127 * 131072 + 512], data[128 * 131072 : 128 * 131072 + 512]
        )
