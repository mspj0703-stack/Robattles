"""P2-B/P3 source and data boundary checks (not Roblox execution tests)."""
from pathlib import Path
import subprocess
import json
import re

ROOT=Path(__file__).resolve().parents[1]
BASE='39ab7b9'


def src(path):
    return (ROOT/path).read_text(encoding='utf-8')


def base(path):
    return subprocess.check_output(['git','show',f'{BASE}:{path}'],cwd=ROOT,text=True)


def test_gameplay_server_animation_characters_unchanged():
    protected=['src/server/Main.server.luau', 'src/client/CharacterAnimator.luau',
               'src/client/SwordAnimator.luau', 'src/shared/Data/Characters.luau',
               'src/shared/Data/EffectCatalog.luau', 'src/client/Logic/EffectsModel.luau',
               'src/client/UI/State.luau']
    for file in protected:
        assert src(file)==base(file),file


def test_remote_project_configuration_unchanged():
    for file in ['default.project.json','integrated.project.json','src/shared/RemoteSpec.luau']:
        assert src(file)==base(file),file


def test_audio_no_fake_asset_ids():
    s=src('src/shared/Data/SfxProfiles.luau')
    assert 'local cueMix = {' in s
    assert 'SoundId = "rbxassetid://' not in s
    assert 'No Roblox SoundId is assigned here' in s
    for cue in ['sword.slash','skill.storm.finish','parry.success','paint.fire',
                'paint.explosion','ball.bounce','ball.throw.charged','bomb.explosion',
                'sling.fire','sling.ult.precise','hit.impact']:
        assert f'["{cue}"]' in s


def test_audio_fallback_still_exists_and_group_volume_still_applies():
    p=src('src/client/EffectPlayer.luau')
    assert p==base('src/client/EffectPlayer.luau')
    assert 'soundAssets:FindFirstChild(cueName or "")' in p
    assert 'override:IsA("Sound")' in p
    assert 'fallback.id' in p
    assert 'sound.SoundGroup = SoundService:FindFirstChild("RoBattlesSFX")' in p
    a=src('src/client/UI/App.luau')
    assert 'if group then group.Volume=value end' in a


def test_only_server_confirmed_positive_hit_causes_visual_marker():
    f=src('src/client/Main.client.luau')
    assert 'fx.kind == "HitMarker" and type(fx.amount) == "number" and fx.amount > 0' in f
    assert 'hud:showHitMarker(now())' in f
    assert 'hud:showToast(string.format("-%d"' not in f
    t=src('src/client/Logic/FeedbackModel.luau')
    assert 'event.targetId ~= myId and type(event.amount) == "number" and event.amount > 0' in t


def test_hud_damage_stacking_and_reset_bounded():
    h=src('src/client/HudView.luau')
    for token in ['function Hud:showDamage(amount,now)', 'now + 0.16',
                  'self.damageTotal += amount', 'self.damageHits += 1',
                  'self.damageUntil = now + 0.55',
                  'function Hud:clearTransient()', 'self.damageWindowEnd=nil',
                  'self.damageTotal=nil']:
        assert token in h


def test_ko_is_server_state_and_separate_from_toast():
    h=src('src/client/HudView.luau')
    a=src('src/client/UI/App.luau')
    assert 'function Hud:showKO(healed,now)' in h
    assert 'self.ko=C.text(root,"KONotice"' in h
    assert 'self.hud:showKO(healed,now)' in a
    assert 'oldMatchId~=nextMatchId' in a
    assert 'self.shownKillAt=nil' in a
    assert 'if self.state.lastKillAt and self.state.lastKillAt~=self.shownKillAt then' in a
    assert 'self:showToast(' in h


def test_incoming_damage_not_ko_toast():
    a=src('src/client/UI/App.luau')
    h=src('src/client/HudView.luau')
    assert 'self.hud:showTakenDamage(event.amount,now)' in a
    assert 'self.hud:shake(now)' in a
    assert 'function Hud:showTakenDamage(amount,now)' in h
    assert 'self.taken.Visible=false' in h


def test_no_unexpected_source_modifications():
    changed=set(subprocess.check_output(['git','diff','--name-only',BASE],cwd=ROOT,text=True).splitlines())
    allowed={'src/shared/Data/SfxProfiles.luau','src/client/HudView.luau',
             'src/client/UI/App.luau','src/client/Main.client.luau',
             'src/client/Logic/FeedbackModel.luau',
             'tests_py/test_p2b_p3_contract.py','docs/P2B_P3_IMPLEMENTATION_REPORT.md',
             'docs/P2B_AUDIO_ASSET_INSTALLATION.md'}
    assert changed <= allowed,changed-allowed
