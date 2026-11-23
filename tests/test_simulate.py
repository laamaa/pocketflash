import contextlib
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import simulate


class SimulationRunnerTests(unittest.TestCase):
    def test_two_workers_overlap_and_report_every_bench(self):
        barrier = threading.Barrier(2, timeout=5)

        def bench_worker(bench, dest):
            barrier.wait()
            return True, 0.1, f"output from {bench.stem}\n"

        output = io.StringIO()
        with patch.object(simulate, "run_bench", bench_worker):
            with contextlib.redirect_stdout(output):
                simulate.run_benches([Path("first.sv"), Path("second.sv")], Path("unused"), 2)
        self.assertEqual(output.getvalue().count("output from first"), 1)
        self.assertEqual(output.getvalue().count("output from second"), 1)

    def test_failed_bench_fails_suite_and_other_results_are_reported(self):
        def bench_worker(bench, dest):
            return bench.stem != "broken", 0.1, f"output from {bench.stem}\n"

        output = io.StringIO()
        with patch.object(simulate, "run_bench", bench_worker):
            with contextlib.redirect_stdout(output):
                with self.assertRaisesRegex(ValueError, "broken"):
                    simulate.run_benches([Path("broken.sv"), Path("good.sv")], Path("unused"), 2)
        self.assertIn("output from broken", output.getvalue())
        self.assertIn("output from good", output.getvalue())

    def test_subprocess_failure_keeps_stdout_and_stderr(self):
        def fail(bench, dest, output):
            subprocess.run(
                [
                    sys.executable,
                    "-c",
                    "import sys; print('diagnostic'); print('error', file=sys.stderr); sys.exit(3)",
                ],
                check=True,
                stdout=output,
                stderr=subprocess.STDOUT,
            )

        with patch.object(simulate, "simulate_bench", fail):
            with tempfile.TemporaryDirectory() as directory:
                passed, seconds, output = simulate.run_bench(Path("broken.sv"), Path(directory))
        self.assertFalse(passed)
        self.assertGreaterEqual(seconds, 0)
        self.assertIn("diagnostic", output)
        self.assertIn("error", output)
        self.assertIn("exit status 3", output)

    def test_timeout_is_a_failure(self):
        def timeout(bench, dest, output):
            subprocess.run([sys.executable, "-c", "import time; time.sleep(5)"], timeout=0.05)

        with patch.object(simulate, "simulate_bench", timeout):
            with tempfile.TemporaryDirectory() as directory:
                passed, seconds, output = simulate.run_bench(Path("slow.sv"), Path(directory))
        self.assertFalse(passed)
        self.assertIn("timed out", output)

    def test_worker_count_must_be_positive(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                simulate.main(["--jobs", "0"])
        self.assertEqual(error.exception.code, 2)
