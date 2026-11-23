import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import build
from build_inputs import source_hashes
import package

ROOT = Path(__file__).resolve().parents[1]


class UtilityPackage(unittest.TestCase):
    def test_candidate_metadata_slots_zip_without_internal_validation_notes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(ROOT / "pkg", root / "pkg")
            for name in ("README.md", "LICENSE", "NOTICE.md"):
                if (ROOT / name).exists():
                    shutil.copy(ROOT / name, root / name)
            shutil.copytree(ROOT / "docs", root / "docs")
            shutil.copytree(ROOT / "config", root / "config")
            out = root / "build/utility/src/output_files"
            out.mkdir(parents=True)
            data = bytes(range(256)) * 8
            (out / "pocketflash.rbf").write_bytes(data)
            manifest = {
                "mode": "utility",
                "timing_checked": True,
                "hardware_tested": False,
                "persistent_operations": True,
                "write_scope": "full-ROM",
                "verilog_macros": build.mode_macros("utility"),
                "rbf_sha256": hashlib.sha256(data).hexdigest(),
                "source_sha256": source_hashes(root),
            }
            (root / "build/utility/build.json").write_text(json.dumps(manifest))
            package.package(root, "utility")
            dest = root / "dist/utility"
            core = dest / "Cores/PocketFlash.PocketFlash"
            c = json.loads((core / "core.json").read_text())["core"]
            self.assertEqual(c["metadata"]["version"], "0.2.0-beta.1")
            self.assertEqual(
                c["metadata"]["description"], "ROM and save backup, ROM flashing and verification"
            )
            self.assertTrue((dest / "PocketFlash Guide/user-guide.md").is_file())
            for name in (
                "candidate-validation.md",
                "candidate-validation.json",
                "hardware-acceptance.md",
            ):
                self.assertFalse((dest / "PocketFlash Guide" / name).exists(), name)
            self.assertEqual(
                json.loads((dest / "Platforms/pocketflash.json").read_text())["platform"][
                    "manufacturer"
                ],
                "",
            )
            # Preserve the known-working framework requirement; PocketOS's tested
            # version is documented separately and must not override this field.
            self.assertEqual(c["framework"]["version_required"], "2.3")
            self.assertFalse(c["framework"]["sleep_supported"])
            self.assertEqual(c["metadata"]["author"], "PocketFlash")
            self.assertEqual(core.name, c["metadata"]["author"] + "." + c["metadata"]["shortname"])
            self.assertEqual(c["metadata"]["date_release"], "2026-11-23")
            # APF requires this compatibility field even though Dock is untested.
            self.assertTrue(c["framework"]["dock"]["supported"])
            self.assertEqual(
                json.loads((core / "core.json").read_text()),
                json.loads((ROOT / "pkg/Cores/PocketFlash.PocketFlash/core.json").read_text()),
            )
            mappings = json.loads((core / "input.json").read_text())["input"]["controllers"][0][
                "mappings"
            ]
            self.assertEqual(
                {m["key"]: m["name"] for m in mappings},
                {
                    "pad_btn_a": "Select / confirm",
                    "pad_btn_b": "Back / cancel",
                    "pad_btn_x": "Details",
                },
            )
            slots = json.loads((core / "data.json").read_text())["data"]["data_slots"]
            self.assertEqual({s["id"] for s in slots}, {1, 2, 4, 5, 6})
            self.assertTrue((root / "dist/pocketflash-0.2.0-beta.1-candidate.zip").is_file())
            self.assertFalse((dest / "validation.json").exists())
            self.assertFalse((dest / "PocketFlash Guide/screenshots").exists())
            import zipfile

            with zipfile.ZipFile(root / "dist/pocketflash-0.2.0-beta.1-candidate.zip") as archive:
                self.assertFalse(
                    any(
                        "validation" in name
                        or "hardware-acceptance" in name
                        or "screenshots/" in name
                        for name in archive.namelist()
                    )
                )
            # Internal notes are not required to package a public source checkout.
            for name in (
                "candidate-validation.md",
                "candidate-validation.json",
                "hardware-acceptance.md",
            ):
                (root / "docs" / name).unlink(missing_ok=True)
            shutil.rmtree(root / "docs/screenshots", ignore_errors=True)
            # Retired profiles cannot be packaged or relabeled as the utility.
            path = root / "build/utility/build.json"
            for field, bad in (
                ("persistent_operations", False),
                ("write_scope", "final-sector"),
                ("verilog_macros", {"POCKETFLASH_WRITE": 1}),
            ):
                altered = dict(manifest, **{field: bad})
                path.write_text(json.dumps(altered))
                with self.subTest(field=field), self.assertRaises(ValueError):
                    package.package(root, "utility")
            path.write_text(json.dumps(manifest))
            for mode in ("boot", "read", "query", "sector", "write"):
                with self.subTest(mode=mode), self.assertRaisesRegex(ValueError, "Unsupported"):
                    package.package(root, mode)
            package.package(root, "utility")
            # Exercise the real CLI without --mode in the isolated fixture.
            # It must package utility rather than look for a build/read manifest.
            (root / "tools").mkdir()
            for name in ("package.py", "build.py", "build_inputs.py"):
                shutil.copy2(ROOT / "tools" / name, root / "tools" / name)
            result = subprocess.run(
                [sys.executable, str(root / "tools/package.py")], capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_failed_build_removes_stale_candidate_zip(self):
        from unittest.mock import patch

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "dist").mkdir()
            stale = root / "dist/pocketflash-0.2.0-beta.1-candidate.zip"
            stale.write_bytes(b"old")
            with (
                patch.object(build, "ROOT", root),
                patch.object(build, "LOCK", root / "missing.lock"),
                patch.object(build, "toolchain", side_effect=ValueError("stop")),
            ):
                with self.assertRaises(ValueError):
                    build.build("utility")
            self.assertFalse(stale.exists())

    def test_private_payload_in_template_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(ROOT / "pkg", root / "pkg")
            payload = root / "pkg/Saves/pocketflash/common/private.sav"
            payload.write_bytes(b"private")
            with self.assertRaisesRegex(ValueError, "inventory"):
                package.validate_inventory(root / "pkg")
