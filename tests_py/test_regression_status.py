"""Regression runner output must not conflate skipped checks with success."""
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("run_match_checks", ROOT / "tools" / "run_match_checks.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RegressionStatusTests(unittest.TestCase):
    def test_historical_zip_replay_reported_skipped(self):
        status = module.classify_group("sim_legacy_at_d1f03e6", 0, "SIM LEGACY @ d1f03e6: SKIPPED - no Git history")
        self.assertTrue(status.startswith("SKIPPED"))

    def test_legacy_known_failures_are_not_pass(self):
        status = module.classify_group("sim_legacy", 0, "SIM LEGACY: ran 25, failed 4")
        self.assertTrue(status.startswith("NO-NEW-FAILURES"))

    def test_clean_legacy_replay_is_pass(self):
        self.assertEqual(module.classify_group("sim_legacy", 0, "ran 25, failed 0 []"), "PASS")

    def test_unexpected_historical_failure_is_failure(self):
        self.assertEqual(module.classify_group("sim_legacy_at_d1f03e6", 1, "failed 2"), "FAIL")

    def test_current_suite_success(self):
        self.assertEqual(module.classify_group("sim_current", 0, "PASS"), "PASS")

    def test_current_suite_failure(self):
        self.assertEqual(module.classify_group("sim_current", 1, "ERROR"), "FAIL")


if __name__ == "__main__":
    unittest.main()
