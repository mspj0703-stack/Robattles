# RoBattles! Alpha 1.0 — Recovery A1 QA2 (2026-10-27)

**Source base:** `RoBattles_Alpha1_Recovery_A1_2026-10-27.zip` (ZIP handoff, no Git ancestry). Supersedes base ZIP; does not require Git login.

## Actual changes

1. `src/server/RecoveryService.luau`: prevent accumulated inactive-time regeneration from being paid out on a resumed tick. `MatchSession` already resets recovery on phase boundary; this also hardens service-level behavior.
2. `src/server/Main.server.luau`: add `healed` to existing authoritative `KillConfirmed` feedback. No new Remote; all hit damage, score, skill rules unchanged.
3. `src/client/UI/State.luau`: associate KO healing feedback with the same round-scoped kill event; stale or future events retain existing filtering and bounded queue; discard heal when the match changes.
4. `src/client/UI/App.luau`: show `KO! +N HP` when a scored KO healed the current player; continue to show `KO!` when no heal was awarded. No duplicate independent toast.
5. `tests/Recovery.spec.luau`: added boundary tests for 1.5s KO throttle, attack/damage regen delay, inactive-time guard, dead/spawn/reset, 5s fall credit and disconnect.
6. `tests/MatchSession.spec.luau`: use production-matching activity hook in test router; add scored KO + regen integration and environment credited KO integration cases.
7. `tests_ui/state.spec.luau`: matching-round, stale-round, future-round and malformed-heal payload tests.

## Verification genuinely executed here

- `python tools/preflight_offline.py`: **PASS**, including project, remotes, requires and 16 Python unit tests.
- `python tools/run_sim.py current`: **27/27 PASS**.
- `python tools/run_sim.py legacy`: **21/25 effective**, four previously-known historical mismatches, no newly reported failures; legacy runner returns exit 0 as expected.
- Full Luau tests, Luau analyzer/compiler: **NOT RUN** (binaries unavailable in execution environment). Added Luau test cases are unverified.
- Roblox Studio client/server tests: **NOT RUN**.

## Required Studio checks

1. Two Roblox Studio clients, select SWORD, wait for ACTIVE. Wound attacker, score KO, verify health mirror/HUD and combined `KO! +20 HP`.
2. Score KO at nearly full HP; confirm server clamps recovery and UI displays only actually regained amount.
3. KO twice inside 1.5s; no second heal. Repeat at exactly 1.5s; heals again if HP missing.
4. Take damage / use a skill / fire and miss, confirm regeneration delay resets to 6 seconds; no passive regen in RESULTS/WAITING.
5. Hit victim then force fall within 5s; KO credited to latest damaging enemy, heal only if attacker alive and scored. >5s: no credited KO.
6. Round rollover with late KillConfirmed/Healed: no old KO health toast in the new round.

**Not release-certified** until real Luau and Studio tests pass. The additions to server KillConfirmed are additive; clients using the old event contract still work.
