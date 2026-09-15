import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


class PrintXCResultFailuresTests(unittest.TestCase):
    def run_report(self, summary, legacy):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "result.xcresult").mkdir()
            (root / "summary.json").write_text(json.dumps(summary))
            (root / "legacy.json").write_text(json.dumps(legacy))
            xcrun = root / "xcrun"
            xcrun.write_text(
                '#!/bin/sh\ncase "$*" in\n'
                '  *"get object"*) cat "$FIXTURE_ROOT/legacy.json" ;;\n'
                '  *) cat "$FIXTURE_ROOT/summary.json" ;;\nesac\n'
            )
            xcrun.chmod(0o755)
            environment = os.environ.copy()
            environment.update(PATH=f"{root}:{environment['PATH']}", FIXTURE_ROOT=str(root))
            result = subprocess.run(
                ["bash", "scripts/print-xcresult-failures.sh", str(root / "result.xcresult")],
                env=environment, capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout

    def test_reports_first_failure_when_retry_summary_passes(self):
        output = self.run_report(
            {"failedTests": 0},
            {"issues": {"testFailureSummaries": {"_values": [{
                "testCaseName": {"_value": "PairingTests.retry()"},
                "message": {"_value": "Timed out: Host listener"},
            }]}}},
        )
        self.assertIn("PairingTests.retry()", output)
        self.assertIn("Timed out: Host listener", output)

    def test_preserves_current_summary_failure(self):
        output = self.run_report(
            {"failedTests": 1, "testFailures": [{
                "testName": "retry()", "failureText": "Authentication failed",
            }]}, {},
        )
        self.assertIn("Authentication failed", output)

    def test_clean_result_has_no_failure(self):
        output = self.run_report({"failedTests": 0}, {"issues": {}})
        self.assertIn("No failed tests found", output)


if __name__ == "__main__":
    unittest.main()
