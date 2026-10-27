# Alpha 1.0 Recovery A1 implementation — 2026-10-27

Source base: RoBattles_Alpha1_GPT_CLI_LocalRunner_2026-10-26.zip (ZIP handoff, no Git ancestry).

## Rules
- Confirmed and scored KO: +20 HP, max once per 1.5 seconds; never beyond current character MaxHealth; no credit for suicide or dead attacker.
- Fall/environment KO attributed to the most recent damaging enemy within 5 seconds. Otherwise no heal. The same scored-KO gate is used.
- Regen after 6 seconds without attack/skill/reload/ultimate activity or actual damage; 6 HP/sec server authoritative; only in ACTIVE.
- No health packs. Reset tracker on match phase transition, respawn, disconnection.
- Healing is server-owned and reflected to Humanoid mirror/HUD. KO emits `Healed` feedback payload (UI graphic optional).

## Files
- src/server/RecoveryService.luau (new), DamageService.luau, MatchSession.luau, Main.server.luau, ServerRouter.luau
- tests/Recovery.spec.luau (new), tests/run_all.luau

## Validation
- offline project/remote/require validation PASS; Python tool unit 16/16 PASS; current simulation 27/27 PASS.
- Known legacy Phase-1 mismatches 4 unchanged.
- New Luau Recovery spec added to run_all; **NOT EXECUTED**: Luau CLI binary unavailable.
- Studio multiplayer test **NOT EXECUTED**.

## Follow-up manual cases
- KO +20 clamp, near-simultaneous multi-KO throttle, fall credited at 5s vs 5.1s, no heal on self/dead attacker.
- Regen under repeated missed attack, while damaged, during RESULTS, on respawn and active match boundary.
- Confirm Roblox Humanoid mirror health and server-only health policy on Studio two-client run.

Do not treat preflight as proof of successful live Roblox gameplay.
