"""Source-only tests for local runner; do not require Luau binaries."""
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("full_local", ROOT / "tools" / "run_full_local.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

class TestFullLocal(unittest.TestCase):
    def test_explicit_bin_dir_finds_three(self):
        with tempfile.TemporaryDirectory() as td:
            folder = Path(td)
            for name in runner.NAMES:
                (folder / name).write_text("placeholder")
            found, missing = runner.toolset(folder)
            self.assertEqual(missing, [])
            self.assertEqual(set(found), set(runner.NAMES))

    def test_explicit_bin_dir_prevents_path_fallback(self):
        with tempfile.TemporaryDirectory() as td:
            with patch.object(runner.shutil, "which", return_value="/some/luau") as fallback:
                self.assertIsNone(runner.locate("luau", Path(td)))
                fallback.assert_not_called()

    def test_missing_luau_never_returns_full_pass(self):
        with patch.object(runner, "run_group", return_value=0), patch.object(runner, "toolset", return_value=({}, list(runner.NAMES))):
            self.assertEqual(runner.main([]), 2)

    def test_offline_only_is_explicit(self):
        with patch.object(runner, "run_group", return_value=0):
            self.assertEqual(runner.main(["--offline-only"]), 0)

    def test_full_run_calls_tests_and_analyzer(self):
        with tempfile.TemporaryDirectory() as td:
            folder = Path(td)
            tools = {name: folder/name for name in runner.NAMES}
            with patch.object(runner, "run_group", side_effect=[0, 0, 0]) as group, patch.object(runner, "toolset", return_value=(tools, [])):
                self.assertEqual(runner.main([]), 0)
                self.assertEqual(group.call_count, 3)
                self.assertIn("LUAU_ANALYZE", group.call_args.kwargs["env"])

    def test_luau_test_failure_propagates(self):
        with tempfile.TemporaryDirectory() as td:
            tools = {name: Path(td)/name for name in runner.NAMES}
            with patch.object(runner, "run_group", side_effect=[0, 1, 0]), patch.object(runner, "toolset", return_value=(tools, [])):
                self.assertEqual(runner.main([]), 1)

if __name__ == '__main__':
    unittest.main()
