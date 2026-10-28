#!/usr/bin/env python3
"""RoBattles cumulative P5 offline QA (NOT a Luau/Studio runtime certification).

Historical phase-scoped exact-file assertions are explicitly deselected because
later approved phases necessarily change those same presentation files.
Run `pytest -q tests_py tests_sim_current` separately to inspect all legacy failures.
"""
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
HISTORICAL_PHASE_SCOPE = [
    "tests_py/test_p2b_p3_contract.py::test_no_unexpected_source_modifications",
    "tests_py/test_p4_ui_contract.py::test_only_ui_presentation_files_changed_since_p3",
    "tests_py/test_p4_ui_contract.py::test_no_source_changes_outside_p4_scope",
    "tests_py/test_sfx_p2a_contract.py::test_sound_group_preference_unchanged",
    "tests_py/test_sfx_p2a_contract.py::test_no_fake_hit_or_gameplay_changes",
    "tests_py/test_vfx_p1a_contract.py::test_no_gameplay_or_animation_source_changed",
    "tests_py/test_vfx_p1a_contract.py::test_p1b_scope_changed_only_vfx_and_tests",
    "tests_py/test_vfx_p1a_contract.py::test_p1c_change_scope_and_cue_contract",
    "tests_py/test_vfx_p1d_contract.py::test_only_one_line_in_main_from_p1c_and_combat_contract_preserved",
]


def run(name, cmd):
    print(f"\n[{name}] {' '.join(cmd)}", flush=True)
    p = subprocess.run(cmd, cwd=ROOT)
    print(f"[{name}] exit={p.returncode}", flush=True)
    return p.returncode


def main():
    if not (ROOT / ".git").is_dir():
        print("P5 requires Git history: clone P5 bundle rather than testing ZIP alone.")
        return 2
    cmd = [sys.executable, "-m", "pytest", "-q", "tests_py", "tests_sim_current"]
    for name in HISTORICAL_PHASE_SCOPE:
        cmd.extend(["--deselect", name])
    print(f"Historical scope-only assertions deselected: {len(HISTORICAL_PHASE_SCOPE)}", flush=True)
    tests = run("CUMULATIVE TESTS", cmd)
    preflight = run("SOURCE PREFLIGHT", [sys.executable, "tools/preflight_offline.py"])
    diff = run("DIFF WHITESPACE", ["git", "diff", "--check", "39c42fc..HEAD"])
    missing = [x for x in ("luau", "luau-compile", "luau-analyze") if shutil.which(x) is None]
    if missing:
        print("[LUAU] NOT RUN - missing " + ", ".join(missing))
    else:
        print("[LUAU] binaries present; run tools/run_full_local.py separately")
    print("[STUDIO] NOT RUN - Studio gameplay, visuals, sound and FPS remain unverified")
    print("[AUDIO] new 11 WAV candidates are not uploaded/permission-verified")
    ok = tests == 0 and preflight == 0 and diff == 0
    print("[P5] " + ("OFFLINE CHECKS PASS; RELEASE NOT CERTIFIED" if ok else "OFFLINE CHECKS FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
