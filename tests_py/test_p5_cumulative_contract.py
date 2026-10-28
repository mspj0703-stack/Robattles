"""P5 source-level cumulative regression guards (not Luau/Studio runtime tests).

Earlier phase-specific scope tests are historical snapshots; these cumulative
checks compare the current build against the QA4 baseline instead.
"""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "39c42fc"
EXPECTED_PRESENTATION_FILES = {
    "src/client/EffectPlayer.luau",
    "src/client/HudView.luau",
    "src/client/Logic/FeedbackModel.luau",
    "src/client/Main.client.luau",  # cosmetic event dispatch only
    "src/client/ScoreboardView.luau",
    "src/client/SettingsView.luau",
    "src/client/UI/App.luau",
    "src/client/UI/Components.luau",
    "src/client/UI/Responsive.luau",
    "src/client/UI/Tokens.luau",
    "src/shared/Data/EffectCatalog.luau",
    "src/shared/Data/SfxProfiles.luau",
}


def source(path):
    return (ROOT / path).read_text(encoding="utf8")


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def test_qa4_combat_animation_and_character_data_immutable():
    # A stricter cumulative guard than a short list of known critical files.
    changes = set(filter(None, git("diff", "--name-only", f"{BASELINE}..HEAD", "--", "src").splitlines()))
    assert changes <= EXPECTED_PRESENTATION_FILES, sorted(changes - EXPECTED_PRESENTATION_FILES)
    for path in [
        "src/shared/Data/Characters.luau", "src/shared/RemoteSpec.luau",
        "src/client/CharacterAnimator.luau", "src/client/SwordAnimator.luau",
        "src/client/Logic/InputState.luau", "src/client/Logic/HudModel.luau",
    ]:
        assert git("show", f"{BASELINE}:{path}") == source(path).strip(), path
    assert not git("diff", "--name-only", f"{BASELINE}..HEAD", "--", "src/server", "src/map")


def test_current_client_visual_files_and_responsive_profiles_present():
    for name in EXPECTED_PRESENTATION_FILES:
        assert (ROOT / name).is_file(), name
    responsive = source("src/client/UI/Responsive.luau")
    for token in ['desktop = Vector2.new(1280, 720)', 'compact = Vector2.new(1024, 576)',
                  'portrait = Vector2.new(720, 1180)', 'function Responsive.choose(',
                  'function Responsive.fit(']:
        assert token in responsive
    app = source("src/client/UI/App.luau")
    for token in ["function App:restoreGeometry()", "function App:layoutPortrait()",
                  "function App:layoutCompact()", "function App:resize()",
                  "self.hud:applyLayout(\"portrait\")"]:
        assert token in app


def test_hit_and_ko_ui_remain_server_authoritative():
    app = source("src/client/UI/App.luau")
    hud = source("src/client/HudView.luau")
    feedback = source("src/client/Logic/FeedbackModel.luau")
    main = source("src/client/Main.client.luau")
    assert 'if event.type=="Damaged" then' in app
    assert 'event.attackerId==Players.LocalPlayer.UserId' in app
    assert 'self.hud:showDamage(event.amount,now)' in app
    assert 'self.hud:showTakenDamage(event.amount,now)' in app
    assert 'self.state.lastKillAt' in app
    assert 'self.hud:showKO(healed,now)' in app
    assert 'self.damageHits += 1' in hud
    assert 'function Hud:clearTransient()' in hud
    assert 'fx.amount > 0' in main
    assert 't == "Damaged"' in feedback


def test_sound_fallback_and_ten_plus_named_mix_profiles_remain():
    sound = source("src/client/EffectPlayer.luau")
    profiles = source("src/shared/Data/SfxProfiles.luau")
    assert 'Assets.Sounds' in sound
    assert 'override:IsA("Sound")' in sound
    assert 'fallback.id' in sound
    assert 'RoBattlesSFX' in sound
    assert 'SoundGroup' in sound
    mixes = set(re.findall(r'\["([^"\n]+)"\] = \{ speed =', profiles))
    assert len(mixes) == 11, sorted(mixes)
    assert 'No Roblox SoundId is assigned here' in profiles


def test_vfx_fallback_and_cleanup_retained():
    fx = source("src/client/EffectPlayer.luau")
    assert 'using fallback' in fx
    assert 'ParticleEmitter' in fx
    assert 'function EffectPlayer:clear()' in fx
    assert 'function EffectPlayer:setQuality(' in fx
    assert 'function EffectPlayer:_burst(' in fx


def test_live_match_contract_still_preserved_in_source():
    character = source("src/shared/Data/Characters.luau")
    assert all(name in character for name in ["SWORD", "PAINTBALL", "SUPERBALL", "TIMEBOMB", "SLINGSHOT"])
    assert (ROOT / "src/server/Main.server.luau").is_file()
    assert (ROOT / "src/shared/RemoteSpec.luau").is_file()


def test_combat_touch_support_not_misrepresented():
    # P4-B is responsive presentation only, not a touchscreen control rollout.
    report = source("docs/P4B_RESPONSIVE_UI_REPORT_2026-10-28.md")
    assert "터치" in report and ("미구현" in report or "포함하지 않음" in report)
