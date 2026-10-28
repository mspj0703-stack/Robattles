"""P1-A regression/structural checks for the Studio-only renderer.

These tests do not replace Luau CLI or Roblox Studio runtime verification.
"""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PLAYER = ROOT / 'src/client/EffectPlayer.luau'
MODEL = ROOT / 'src/client/Logic/EffectsModel.luau'
CATALOG = ROOT / 'src/shared/Data/EffectCatalog.luau'
BASE = '39c42fc50da26e63b98524aaf00d63a659f29143'


def baseline(rel):
    return subprocess.check_output(['git', 'show', f'{BASE}:{rel}'], cwd=ROOT).decode()


def keys(s):
    return re.findall(r'\["([a-zA-Z0-9_.]+)"\]\s*=\s*\{\s*style\s*=', s)


def test_all_effect_cue_names_and_styles_preserved():
    before = baseline('src/shared/Data/EffectCatalog.luau')
    after = CATALOG.read_text()
    original = dict(re.findall(r'\["([a-zA-Z0-9_.]+)"\]\s*=\s*\{\s*style\s*=\s*"([A-Za-z]+)"', before))
    current = dict(re.findall(r'\["([a-zA-Z0-9_.]+)"\]\s*=\s*\{\s*style\s*=\s*"([A-Za-z]+)"', after))
    assert original == current
    assert len(original) == 73


def test_damage_event_mapping_unchanged():
    assert MODEL.read_text() == baseline('src/client/Logic/EffectsModel.luau')
    body = MODEL.read_text()
    damaged = body.split('elseif t == "Damaged" then', 1)[1].split('elseif t == "Dodge" then', 1)[0]
    assert 'hit.flash' in damaged and 'hit.impact' in damaged
    swing = body.split('if t == "Swing" then', 1)[1].split('elseif t == "SwordSkill" then', 1)[0]
    assert 'hit.impact' not in swing


def test_no_gameplay_or_animation_source_changed():
    changed = subprocess.check_output(['git', 'diff', '--name-only', BASE], cwd=ROOT, text=True).splitlines()
    assert all(x in {
        'src/client/EffectPlayer.luau',
        'src/shared/Data/EffectCatalog.luau',
        'tests_py/test_vfx_p1a_contract.py',
    } for x in changed), changed
    assert not any(x.startswith(('src/server/', 'src/shared/Combat/', 'src/client/CharacterAnimator', 'src/client/SwordAnimator')) for x in changed)


def test_effects_are_visual_noncolliding_and_shortlived():
    body = PLAYER.read_text()
    for token in ['p.Anchored = true', 'p.CanCollide = false', 'p.CanQuery = false', 'p.CanTouch = false']:
        assert token in body
    for routine in ['_hitImpact', '_slashArc', '_burst']:
        assert 'function EffectPlayer:' + routine in body
    assert 'self:_fade(core' in body
    assert 'self:_fade(ray' in body
    assert 'self:_fade(stroke' in body
    assert 'Debris:AddItem(part, lifetime + 0.1)' in body


def test_camera_lod_and_hit_distinction():
    body = PLAYER.read_text()
    assert 'visibleAt(point, cue.mine, 105)' in body
    assert 'visibleAt(root.Position, cue.mine, 55)' in body
    assert 'elseif name == "hit.impact" then' in body
    assert 'self:_hitImpact(cue, def, col)' in body
    assert 'h.DepthMode = Enum.HighlightDepthMode.Occluded' in body


def test_legacy_remote_contract_untouched():
    path = 'src/shared/Data/RemoteSpec.luau'
    if (ROOT / path).exists():
        assert (ROOT / path).read_text() == baseline(path)
