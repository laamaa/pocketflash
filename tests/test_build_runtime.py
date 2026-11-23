import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import build as builder


class RuntimeTests(unittest.TestCase):
    def test_public_commands_default_to_utility(self):
        with (
            patch.object(sys, "argv", ["build.py", "build"]),
            patch.object(builder, "build") as build,
        ):
            builder.main()
        build.assert_called_once_with("utility")
        for target in ("rom", "rom-podman", "package"):
            command = subprocess.check_output(["make", "-n", target], cwd=builder.ROOT, text=True)
            self.assertIn("--mode utility", command)

    def test_retired_build_modes_are_rejected(self):
        self.assertEqual(builder.mode_macros("utility"), {"POCKETFLASH_UTILITY": 1})
        for mode in ("boot", "read", "query", "sector", "write", "invalid"):
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                builder.mode_macros(mode)

    def test_mac_defaults_to_apple_and_allows_explicit_podman(self):
        with patch.object(sys, "platform", "darwin"), patch.dict(os.environ, {}, clear=True):
            self.assertEqual(builder.runtime(), "container")
            os.environ["CONTAINER_RUNTIME"] = "podman"
            self.assertEqual(builder.runtime(), "podman")
            os.environ["CONTAINER_RUNTIME"] = "invalid"
            with self.assertRaises(ValueError):
                builder.runtime()

    def test_apple_build_requires_local_image_and_isolates_guest_network(self):
        with (
            patch.dict(os.environ, {"CONTAINER_RUNTIME": "container"}),
            patch.object(builder, "run") as run,
        ):
            builder.container(
                "pinned-image", ["quartus_sh", "--version"], workdir="/build/build/utility/src"
            )
            calls = [call.args[0] for call in run.call_args_list]
        self.assertEqual(calls[0], ["container", "image", "inspect", "pinned-image"])
        command = calls[1]
        self.assertEqual(command[:3], ["container", "run", "--rm"])
        for flag, value in (
            ("--platform", "linux/amd64"),
            ("--network", "none"),
            ("--memory", "12G"),
            ("--workdir", "/build/build/utility/src"),
        ):
            self.assertEqual(command[command.index(flag) + 1], value)
        self.assertEqual(command[command.index("--volume") + 1], f"{builder.ROOT}:/build:rw")
        self.assertEqual(command[-3:], ["pinned-image", "quartus_sh", "--version"])

    def test_missing_apple_image_stops_before_starting_guest(self):
        with (
            patch.dict(os.environ, {"CONTAINER_RUNTIME": "container"}),
            patch.object(
                builder, "run", side_effect=subprocess.CalledProcessError(1, "inspect")
            ) as run,
        ):
            with self.assertRaises(subprocess.CalledProcessError):
                builder.container("missing-image", ["quartus_sh", "--version"])
            self.assertEqual(run.call_count, 1)
            self.assertEqual(
                run.call_args.args[0], ["container", "image", "inspect", "missing-image"]
            )
