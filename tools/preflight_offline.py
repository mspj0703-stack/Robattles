#!/usr/bin/env python3
"""Offline source preflight for ZIP handoffs (not a substitute for Luau CLI or Studio).

Usage:
  python3 tools/preflight_offline.py
  python3 tools/preflight_offline.py --luau /path/luau --compiler /path/luau-compile

All checks run against the current local source tree. No network or Git auth needed.
Known failures in the *preserved* legacy simulation are reported distinctly.
"""
import argparse
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

def run(label, argv):
    p = subprocess.run(argv, cwd=ROOT, text=True, capture_output=True)
    print(f"[{label}] rc={p.returncode}")
    # Keep output useful, including expected legacy failures and full errors.
    for line in (p.stdout + p.stderr).splitlines():
        if label != "legacy" or line.startswith(("SIM LEGACY", "  known stale", "  NEW failures", "FAILED", "Ran ")):
            print("  " + line)
    return p.returncode

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--luau", help="absolute path to Luau interpreter")
    ap.add_argument("--compiler", help="absolute path to luau-compile")
    args = ap.parse_args()
    py = sys.executable
    suites = [
        ("projects", [py, str(ROOT / "tools/check_projects.py")]),
        ("remotes", [py, str(ROOT / "tools/check_remotes.py")]),
        ("requires", [py, str(ROOT / "tools/check_requires.py")]),
        ("requires_selftest", [py, "-m", "unittest", "discover", "-s", "tests_py"]),
        ("sim_current", [py, str(ROOT / "tools/run_sim.py"), "current"]),
        ("legacy", [py, str(ROOT / "tools/run_sim.py"), "legacy"]),
    ]
    results = [(name, run(name, cmd)) for name, cmd in suites]
    if args.luau and args.compiler:
        if not all(pathlib.Path(x).is_file() for x in (args.luau, args.compiler)):
            print("[Luau] FAIL: supplied executable path does not exist")
            return 2
        results.append(("full_luau", run("full_luau", [py, str(ROOT / "tools/run_match_checks.py"), "--luau", args.luau, "--compiler", args.compiler])))
    elif args.luau or args.compiler:
        print("[Luau] FAIL: provide both --luau and --compiler, or neither")
        return 2
    else:
        print("[Luau] NOT RUN: requires luau and luau-compile binaries")

    git = shutil.which("git")
    if git and (ROOT / ".git").exists():
        p = subprocess.run([git, "cat-file", "-e", "ac6d48f^{commit}"], cwd=ROOT, capture_output=True)
        if p.returncode == 0:
            results.append(("anim_scope", run("anim_scope", [py, str(ROOT / "tools/check_anim.py")])))
        else:
            print("[anim_scope] NOT RUN: comparison commit ac6d48f absent; cannot claim PASS")
    else:
        print("[anim_scope] NOT RUN: ZIP without Git history; cannot claim forbidden-change verification")
    print("[Studio] NOT RUN: Roblox Studio required")
    failed = [name for name, rc in results if rc]
    print("[RESULT] " + ("SOURCE PREFLIGHT PASS (Luau/Studio limitations above)" if not failed else "FAIL: " + ", ".join(failed)))
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
