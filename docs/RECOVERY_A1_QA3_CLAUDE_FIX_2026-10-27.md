# RoBattles! Alpha 1.0 — Recovery A1 QA3, Claude Luau feedback fixes

Date: 2026-10-27. Base: `RoBattles_Alpha1_Recovery_A1_QA2_2026-10-27.zip` (standalone ZIP, no Git ancestry).

## Addressed Claude's three failures

1. `tests/Recovery.spec.luau`: add `return true`, as ModuleScript specs loaded by `tests/run_all.luau` must return one value.
2. `tests/AnimFiveChars.spec.luau`: close the 600-random-events `T.it` callback using `end)` rather than `end` (located near line 243).
3. `src/client/UI/App.luau`: PLAY callback uses `self:open("Characters")` before assigning `self.returnPage="Battle"`. Previously `App:open` overwrote the intended Battle return page with Menu; existing `tests_ui/views.spec.luau` line ~122 checks this.

Only those **three files** changed in the game/source/test tree; no combat, damage, heal, remote, character balance, or S5-R1 rules modified.

## Direct GPT verification

- `python tools/preflight_offline.py`: **SOURCE PREFLIGHT PASS** (project/Remote/require references, Python inspector unit tests 16/16, current simulation 27/27).
- Legacy suite at current branch: four known-stale Phase 1 assertion failures, no new failures, as reported by preflight.
- Diff against QA2 ZIP: exactly 3 changed files; no missing baseline files.
- **Luau tests and analyzer NOT RUN in GPT environment**, since `luau`, `luau-compile`, `luau-analyze` executables unavailable. Roblox Studio NOT RUN.

## Claude verification request

Unzip QA3 into a clean new directory (do not overwrite `phase2/integration` / `a598bcb`). Execute actual Luau compiler + analyzer and full regression using available binaries; run UI state/UI mock and map checks. Record exact pass/fail counts and attach stack traces for any new failures. Do not treat a test blocked before collection as a pass. Then run Studio 2-player and 12-player checks separately (Studio results must not be inferred from CLI).
