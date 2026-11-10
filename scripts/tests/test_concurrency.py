"""Regression coverage for warning identities across the local and hosted SDKs."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("concurrency", ROOT / "scripts/check-concurrency.py")
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class ConcurrencyGateTests(unittest.TestCase):
    def diagnostic(self, identity, line=1):
        return (f"{ROOT}/Sources/Debagr/MenuBarApplication.swift:{line}:7: warning: "
                f"sending 'self' risks causing data races [#{identity}]\n")

    def test_xcode_diagnostic_namespace_and_source_lines_do_not_change_identity(self):
        local = checker.warnings(self.diagnostic("RegionIsolation::SendingRisksDataRace", 10))
        hosted = checker.warnings(self.diagnostic("SendingRisksDataRace", 90))
        self.assertEqual(local, hosted)
        self.assertEqual(len(hosted), 1)

    def test_different_diagnostic_ids_stay_distinct(self):
        before = checker.warnings(self.diagnostic("SendingRisksDataRace"))
        after = checker.warnings(self.diagnostic("DifferentWarning"))
        self.assertTrue(after - before)

    def test_progress_spliced_into_a_diagnostic_keeps_its_original_identity(self):
        diagnostic = self.diagnostic("SendingRisksDataRace")
        split = len(str(ROOT)) - 2
        interleaved = diagnostic[:split] + "[6\u2009/\u20099] debagr-product\n" + diagnostic[split:]
        self.assertEqual(checker.warnings(interleaved), checker.warnings(diagnostic))
        self.assertEqual(len(checker.warnings(interleaved)), 1)

    def test_unknown_warning_fails_the_real_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "compiler.log"
            log.write_text(self.diagnostic("NewRegression"))
            result = subprocess.run([sys.executable, str(ROOT / "scripts/check-concurrency.py"), str(log)],
                                    capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn("New concurrency warning:", result.stdout)
        self.assertIn("[#NewRegression]", result.stdout)


if __name__ == "__main__":
    unittest.main()
