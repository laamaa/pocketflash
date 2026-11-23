import hashlib
import json
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

ROOT = Path(__file__).resolve().parents[1]


sys.path.insert(0, str(ROOT / "tools"))
import build as builder
from build_inputs import source_hashes
import package as packager
from build import mode_macros
import pocketflash as helpers


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.block = bytes(range(256)) * 256
        self.crc = 0
        for _ in range(512):
            self.crc = zlib.crc32(self.block, self.crc)

    def tearDown(self):
        self.temp.cleanup()

    def dump(self, name):
        path = self.root / name
        with path.open("wb") as f:
            for _ in range(512):
                f.write(self.block)
        path.with_suffix(".pfr").write_bytes(
            struct.pack("<4sIII", b"PFR1", helpers.ROM_SIZE, self.crc, 1)
        )
        return path

    def test_three_independent_backups_require_matching_data_and_completion(self):
        paths = [self.dump(f"dump{i}.gba") for i in (1, 2, 3)]
        result = helpers.verify_backups(paths)
        self.assertEqual(len({b["sha256"] for b in result["backups"]}), 1)
        with self.assertRaises(ValueError):
            helpers.verify_backups([paths[0]] * 3)
        paths[1].with_suffix(".pfr").unlink()
        with self.assertRaises(OSError):
            helpers.verify_backups(paths)

    def test_rejects_corruption_even_when_preallocated_size_is_correct(self):
        path = self.dump("dump1.gba")
        with path.open("r+b") as f:
            f.seek(0x1000000)
            f.write(b"\xff")
        with self.assertRaisesRegex(ValueError, "incomplete or corrupt"):
            helpers.inspect_backup(path)

    def test_rejects_partial_file_and_invalid_marker(self):
        path = self.dump("dump1.gba")
        with path.open("r+b") as f:
            f.truncate(65536)
        with self.assertRaises(ValueError):
            helpers.inspect_backup(path)
        path.with_suffix(".pfr").write_bytes(b"bad")
        with self.assertRaises(ValueError):
            helpers.inspect_backup(path)

    def test_readback_marker_and_unknown_flags(self):
        path = self.dump("readback.gba")
        record = path.with_suffix(".pfr")
        record.write_bytes(struct.pack("<4sIII", b"PFR1", helpers.ROM_SIZE, self.crc, 3))
        self.assertEqual(helpers.inspect_backup(path)["completion"], "readback verified")
        record.write_bytes(struct.pack("<4sIII", b"PFR1", helpers.ROM_SIZE, self.crc, 5))
        with self.assertRaises(ValueError):
            helpers.inspect_backup(path)

    def test_compare_pads_tail_and_reports_first_mismatch(self):
        image = self.root / "small.gba"
        image.write_bytes(self.block)
        target = self.root / "readback.gba"
        with target.open("wb") as f:
            f.write(self.block)
            for _ in range(511):
                f.write(b"\xff" * 65536)
        helpers.compare_rom(image, target)
        with target.open("r+b") as f:
            f.seek(0x1000000)
            f.write(b"\x00")
        with self.assertRaisesRegex(ValueError, "0x01000000"):
            helpers.compare_rom(image, target)

    def test_rom_size_boundaries(self):
        for n in (192, 65536, helpers.ROM_SIZE):
            helpers.check_rom_size(n)
        for n in (0, 191, 193, helpers.ROM_SIZE + 4):
            with self.assertRaises(ValueError):
                helpers.check_rom_size(n)


class PackageTests(unittest.TestCase):
    def test_refuses_unbuilt_or_stale_sources_and_reverses_actual_bits(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            core = root / "pkg/Cores/PocketFlash.PocketFlash"
            shutil.copytree(ROOT / "pkg", root / "pkg")
            shutil.copytree(ROOT / "docs", root / "docs")
            shutil.copytree(ROOT / "config", root / "config")
            for name in ("LICENSE", "NOTICE.md"):
                shutil.copy2(ROOT / name, root / name)
            with self.assertRaises(OSError):
                packager.package(root, "utility")
            output = root / "build/utility/src/output_files"
            output.mkdir(parents=True)
            bitstream = bytes(range(256)) * 8
            (output / "pocketflash.rbf").write_bytes(bitstream)
            src = root / "src/example.v"
            src.parent.mkdir()
            src.write_text("module example; endmodule\n")
            manifest = {
                "mode": "utility",
                "timing_checked": True,
                "rbf_sha256": hashlib.sha256(bitstream).hexdigest(),
                "source_sha256": source_hashes(root),
                "persistent_operations": True,
                "write_scope": "full-ROM",
                "verilog_macros": mode_macros("utility"),
            }
            (root / "build/utility/build.json").write_text(json.dumps(manifest))
            packager.package(root, "utility")
            installed = root / "dist/utility/Cores/PocketFlash.PocketFlash"
            filename = json.loads((installed / "core.json").read_text())["core"]["cores"][0][
                "filename"
            ]
            data = (installed / filename).read_bytes()
            self.assertEqual(data[1], 128)
            self.assertEqual(data[128], 1)
            for name in packager.REQUIRED_DEFINITIONS:
                self.assertTrue((installed / f"{name}.json").is_file())
            variants = core / "variants.json"
            variants.unlink()
            with self.assertRaisesRegex(
                ValueError, "Missing required core definition: variants.json"
            ):
                packager.validate_definitions(core)
            shutil.copyfile(ROOT / "pkg/Cores/PocketFlash.PocketFlash/variants.json", variants)
            definition = json.loads((core / "core.json").read_text())
            definition["core"]["cores"][0]["filename"] = "pocketflash.rbf_r"
            (core / "core.json").write_text(json.dumps(definition))
            with self.assertRaisesRegex(ValueError, "at most 15 characters"):
                packager.validate_definitions(core)
            shutil.copyfile(
                ROOT / "pkg/Cores/PocketFlash.PocketFlash/core.json", core / "core.json"
            )
            added = src.with_name("added.v")
            added.write_text("added source")
            with self.assertRaisesRegex(ValueError, "Source changed"):
                packager.package(root, "utility")
            added.unlink()
            src.write_text("changed")
            with self.assertRaisesRegex(ValueError, "Source changed"):
                packager.package(root, "utility")

    def test_build_rejects_edits_during_compile_and_removes_stale_staged_sources(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "src").mkdir()
            (root / "pkg").mkdir()
            src = root / "src/example.v"
            src.write_text("original")
            (root / "src/pocketflash.qsf").write_text("")
            lock = root / "image.lock"
            lock.write_text(json.dumps({"reference": "fixture", "quartus_version": "fixture"}))
            stale = root / "build/utility/src/deleted.v"
            stale.parent.mkdir(parents=True)
            stale.write_text("stale source")
            output = stale.parent / "output_files"
            output.mkdir()
            (output / "pocketflash.rbf").write_bytes(b"old bitstream" * 128)
            (root / "build/utility/build.json").write_text("old manifest")

            def compile_fixture(reference, command, **kwargs):
                if command == ["quartus_sh", "--version"]:
                    return builder.subprocess.CompletedProcess(command, 0, stdout="fixture")
                if command[0] == "quartus_sta":
                    return
                self.assertFalse(stale.exists())
                self.assertEqual((root / "build/utility/src/example.v").read_text(), "original")
                self.assertFalse((output / "pocketflash.rbf").exists())
                output.mkdir(exist_ok=True)
                (output / "pocketflash.rbf").write_bytes(b"compiled" * 256)
                src.write_text("edited while Quartus ran")

            with (
                patch.object(builder, "ROOT", root),
                patch.object(builder, "LOCK", lock),
                patch.object(builder, "container", side_effect=compile_fixture),
                patch.object(builder, "run") as run,
            ):
                with self.assertRaisesRegex(ValueError, "Sources changed during compilation"):
                    builder.build("utility")
                run.assert_not_called()
            self.assertFalse((root / "build/utility/build.json").exists())
            self.assertFalse((root / "dist/utility").exists())


if __name__ == "__main__":
    unittest.main()
