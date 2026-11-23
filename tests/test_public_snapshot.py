import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "snap", Path(__file__).resolve().parents[1] / "tools/public_snapshot.py"
)
snap = importlib.util.module_from_spec(spec)


class Snapshot(unittest.TestCase):
    def test_missing_inventory_member_cannot_produce_incomplete_release(self):
        spec.loader.exec_module(snap)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "README.md").write_text("release source")
            previous = root / "dist/public-source"
            previous.mkdir(parents=True)
            (previous / "keep.txt").write_text("previous snapshot")
            # Git's external responses are fixed; actual inventory validation and
            # filesystem/export behavior run against this isolated checkout fixture.
            replies = ["", "a" * 40, b"README.md\0"]
            with (
                patch.object(snap, "FILES", frozenset(("README.md", "required.v"))),
                patch.object(snap.subprocess, "check_output", side_effect=replies),
            ):
                with self.assertRaisesRegex(ValueError, "required.v"):
                    snap.prepare(root)
            self.assertEqual((previous / "keep.txt").read_text(), "previous snapshot")

    def test_complete_inventory_is_exported_with_content_hashes(self):
        spec.loader.exec_module(snap)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "README.md").write_text("release source")
            replies = ["", "b" * 40, b"README.md\0"]
            with (
                patch.object(snap, "FILES", frozenset(("README.md",))),
                patch.object(snap.subprocess, "check_output", side_effect=replies),
            ):
                exported = snap.prepare(root)
            self.assertEqual((exported / "README.md").read_text(), "release source")
            import hashlib, json

            manifest = json.loads((exported / "TESTED-SOURCE.json").read_text())
            self.assertEqual(set(manifest), {"source_commit", "sha256"})
            self.assertEqual(
                manifest["sha256"], {"README.md": hashlib.sha256(b"release source").hexdigest()}
            )

    def test_allowlist(self):
        spec.loader.exec_module(snap)
        for path in (
            "src/core/pocketflash_utility.v",
            "tests/tb_save_bus.sv",
            "docs/user-guide.md",
            "config/apf-provenance.json",
            "LICENSE",
        ):
            self.assertTrue(snap.allowed(path), path)
        for path in (
            "tmp/fms.gba",
            "hardware-backups/cart.sav",
            "docs/superpowers/plans/old.md",
            ".git/config",
            "src/output_files/a.rbf",
            "pkg/private.gba",
            "docs/history/experiment-readme.md",
            "docs/candidate-validation.md",
            "docs/candidate-validation.json",
            "docs/hardware-acceptance.md",
            "docs/development/source-audit.md",
            "docs/development/save-bus-audit.md",
            "docs/screenshots/dashboard.png",
            "docs/screenshots/confirm.png",
            "docs/screenshots/backup.png",
            "src/raw.bin",
            "tools/private.zip",
            "docs/screenshots/private.bin",
        ):
            self.assertFalse(snap.allowed(path), path)
