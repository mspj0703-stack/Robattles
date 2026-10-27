#!/usr/bin/env python3
"""Approximate-simulation runner (Python approximations, NOT Luau CLI and NOT Roblox Studio).

  python3 tools/run_sim.py current                 gating suite: tests_sim_current/ against the CURRENT source
  python3 tools/run_sim.py legacy                  preserved Phase 1 suite tests_sim/ against the CURRENT source
  python3 tools/run_sim.py legacy --at d1f03e6     same suite against an older commit (git archive), to reproduce it

`legacy` is reported separately. Its failures are never hidden: they are printed in full. The exit code is 0 only when the
failing set is exactly (a subset of) KNOWN_STALE for the chosen target; any NEW failure exits 1.
See docs/SIM_BASELINES.md.
"""
import argparse, pathlib, re, shutil, subprocess, sys, tempfile
sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parents[1]

# Phase 1 tests whose expectation encodes Phase 1 numbers / frozen file hashes (verified against the current source).
KNOWN_STALE = {
    "current": {
        "test_actors_and_hp", "test_reload_amount", "test_actual_phase1_numbers", "test_phase1_manifest",
    },
    # at d1f03e6 only the frozen-manifest test fails: the manifest is of an earlier, repository-external Phase 1 freeze.
    "d1f03e6": {"test_phase1_manifest"},
}

def unittest_run(cwd, start):
    r = subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", start, "-v"], cwd=cwd, capture_output=True, text=True)
    out = r.stdout + r.stderr
    failed = set(re.findall(r"^(?:FAIL|ERROR): (\w+)", out, re.M))
    ran = re.search(r"Ran (\d+) tests", out)
    return r.returncode, out, failed, int(ran.group(1)) if ran else 0

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("suite", choices=["current", "legacy"])
    ap.add_argument("--at", help="legacy only: git commit to reproduce the preserved suite against")
    a = ap.parse_args()
    if a.suite == "current":
        code, out, failed, ran = unittest_run(ROOT, "tests_sim_current")
        print(out)
        print(f"SIM CURRENT: ran {ran}, failed {len(failed)} {sorted(failed)}")
        return 1 if code else 0
    target, known = "current", KNOWN_STALE["current"]
    cwd = ROOT
    tmp = None
    if a.at:
        tmp = tempfile.mkdtemp()
        arc = subprocess.run(["git", "archive", a.at], cwd=ROOT, capture_output=True)
        if arc.returncode:
            print(f"SIM LEGACY @ {a.at}: SKIPPED - commit not available (no git history here): {arc.stderr.decode().strip()}")
            return 0
        subprocess.run(["tar", "-x", "-C", tmp], input=arc.stdout, check=True)
        for rel in ["tests_sim", "tools/sim_rules.py", "tools/sim_step1.py", "sim_baseline"]:
            src, dst = ROOT / rel, pathlib.Path(tmp) / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(src, dst, dirs_exist_ok=True) if src.is_dir() else shutil.copy(src, dst)
        cwd, target, known = pathlib.Path(tmp), a.at, KNOWN_STALE.get(a.at, set())
    code, out, failed, ran = unittest_run(cwd, "tests_sim")
    print(out)
    new = failed - known
    print(f"SIM LEGACY (Phase 1 suite) @ {target}: ran {ran}, failed {len(failed)} {sorted(failed)}")
    print(f"  known stale: {sorted(failed & known)}   NEW failures: {sorted(new)}")
    if tmp: shutil.rmtree(tmp, ignore_errors=True)
    return 1 if new else 0

if __name__ == "__main__":
    sys.exit(main())
