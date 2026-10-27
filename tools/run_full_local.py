#!/usr/bin/env python3
"""Run RoBattles source preflight and, when available, ALL Luau CLI checks.

Standalone ZIP-friendly. No GitHub authentication, network access, or git needed.
This script does not silently treat missing Luau binaries as successful regression.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
NAMES = ("luau", "luau-compile", "luau-analyze")


def locate(name: str, bin_dir: Path | None = None, env: dict[str, str] | None = None) -> Path | None:
    """Prefer explicit bin-dir, then project-local bins, then PATH.

    Do not silently use PATH if an explicit bin-dir was requested and incomplete.
    """
    env = os.environ if env is None else env
    suffixes = (".exe", "") if os.name == "nt" else ("", ".exe")
    dirs = [bin_dir] if bin_dir is not None else [ROOT / "tools" / "luau-bin", ROOT.parent / "tools" / "luau-bin"]
    for folder in dirs:
        if folder is None:
            continue
        for suffix in suffixes:
            candidate = (folder / (name + suffix)).resolve()
            if candidate.is_file():
                return candidate
    if bin_dir is not None:
        return None
    found = shutil.which(name, path=env.get("PATH"))
    return Path(found).resolve() if found else None


def toolset(bin_dir: Path | None = None) -> tuple[dict[str, Path], list[str]]:
    result = {name: locate(name, bin_dir) for name in NAMES}
    return {k: v for k, v in result.items() if v is not None}, [k for k, v in result.items() if v is None]


def run_group(label: str, cmd: list[str], env: dict[str, str] | None = None) -> int:
    print(f"\n[{label}] {' '.join(cmd)}", flush=True)
    try:
        p = subprocess.run(cmd, cwd=ROOT, env=env, check=False)
    except (OSError, ValueError) as exc:
        print(f"[{label}] NOT RUN: {exc}", flush=True)
        return 2
    print(f"[{label}] exit={p.returncode}", flush=True)
    return p.returncode


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin-dir", type=Path, help="directory with luau, luau-compile, luau-analyze")
    parser.add_argument("--offline-only", action="store_true", help="only Python preflight; Luau/Studio explicitly NOT RUN")
    args = parser.parse_args(argv)

    preflight = run_group("PYTHON SOURCE PREFLIGHT", [sys.executable, "tools/preflight_offline.py"])
    if args.offline_only:
        print("\n[RESULT] OFFLINE ONLY; full Luau CLI and Studio NOT RUN", flush=True)
        return 1 if preflight else 0

    tools, missing = toolset(args.bin_dir)
    if missing:
        print("\n[MISSING LUAU] " + ", ".join(missing), flush=True)
        print("Place all three Luau executables in RoBattles/tools/luau-bin/ or pass --bin-dir.", flush=True)
        print("Full regression and Luau analysis NOT RUN. See docs/CLI_EXECUTION_HANDOFF.md.", flush=True)
        return 2  # Prevent 'Python-only PASS' from being misread as full PASS.
    if preflight:
        print("\n[RESULT] FAIL: Python source preflight failed; Luau tests not started", flush=True)
        return 1

    tests = run_group("FULL LUAU REGRESSION", [sys.executable, "tools/run_match_checks.py", "--luau", str(tools["luau"]), "--compiler", str(tools["luau-compile"])])
    env = dict(os.environ)
    env["LUAU_ANALYZE"] = str(tools["luau-analyze"])
    analyzer = run_group("LUAU ANALYZER", [sys.executable, "tools/analyze.py"], env=env)
    print(f"\n[RESULT] {'PASS' if tests == 0 and analyzer == 0 else 'FAIL'} — Luau CLI; Studio NOT RUN", flush=True)
    return 0 if tests == 0 and analyzer == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
