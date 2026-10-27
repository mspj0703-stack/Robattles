#!/usr/bin/env python3
"""UI regression group: combat/match CLI suite + project/remote checks + UI state spec + GUI-mock smoke.
Usage: python3 tools/run_ui_checks.py [--luau /path/luau]
The GUI mock is NOT Roblox Studio; it only catches construction/callback errors.
"""
import argparse, os, pathlib, shutil, subprocess, sys
sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parents[1]

def main():
    default = shutil.which("luau") or str(ROOT.parent / "tools" / "luau-bin" / "luau")
    ap = argparse.ArgumentParser(); ap.add_argument("--luau", default=default); a = ap.parse_args()
    failed = 0
    failed += subprocess.run([sys.executable, str(ROOT / "tools/run_tests.py"), "--luau", a.luau]).returncode != 0
    for script in ["check_projects.py", "check_remotes.py"]:
        failed += subprocess.run([sys.executable, str(ROOT / "tools" / script)]).returncode != 0
    failed += subprocess.run([a.luau, str(ROOT / "tests_ui/state.spec.luau")], cwd=ROOT).returncode != 0
    failed += subprocess.run([sys.executable, str(ROOT / "tools/run_ui_smoke.py"), "--luau", a.luau]).returncode != 0
    print(f"CHECK GROUP FAILURES: {failed}")
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
