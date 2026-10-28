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
        'tests_py/test_vfx_p1d_contract.py',
        'src/client/Main.client.luau', # P1-D cosmetic lifetime reset only
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

# P1-B SWORD specialization source-scope checks. Studio-only visual result is not asserted.
def test_p1b_sword_effect_cues_remain_same_as_p1a():
    from subprocess import check_output
    previous = check_output(['git', 'show', '9585841:src/shared/Data/EffectCatalog.luau'], cwd=ROOT, text=True)
    assert CATALOG.read_text() == previous
    assert MODEL.read_text() == baseline('src/client/Logic/EffectsModel.luau')


def test_p1b_distinct_sword_attack_variants():
    b = PLAYER.read_text()
    assert 'SWORD_ARC_VARIANTS' in b
    for cue in ('sword.slash3', 'skill.triple1', 'skill.triple2', 'skill.triple3'):
        assert f'["{cue}"]' in b
    assert 'cue.step == 2' in b  # second basic slash reverses direction
    assert 'self:_swordArc(cue, def, root, color)' in b
    assert 'self:_slashArc(cue, def, root, col)' in b  # unchanged fallback


def test_p1b_parry_and_lunge_differentiated():
    b = PLAYER.read_text()
    assert 'function EffectPlayer:_swordParry' in b
    assert 'name == "parry.start" or name == "parry.success" or name == "parry.blocked"' in b
    assert 'function EffectPlayer:_swordLunge' in b
    assert 'swordHand(root)' in b
    assert 'self:_swordLunge(cue, def, root, color)' in b
    assert 'if type(cue.dir) == "table"' in b
    assert 'distance = math.clamp' in b


def test_p1b_wave_and_storm_phase_specific():
    b = PLAYER.read_text()
    assert 'function EffectPlayer:_swordWave' in b
    assert 'math.min(cue.range, 14)' in b
    assert 'function EffectPlayer:_swordStorm' in b
    assert 'index % 4' in b
    assert 'skill.storm.finish' in b and 'duelist.proc' in b


def test_p1b_effects_visual_only_and_cleanup():
    b = PLAYER.read_text()
    assert 'function EffectPlayer:_playSword' in b
    assert 'if self:_playSword(cue, def, root, col) then' in b
    assert b.index('if override and def.style ~= "Highlight" then') < b.index('if self:_playSword(cue, def, root, col) then')
    assert 'emitLine(self._folder, self,' in b
    assert 'line.Parent = folder' in b
    assert 'owner:_fade(line, life)' in b
    for tok in ('p.CanCollide = false', 'p.CanTouch = false', 'p.CanQuery = false', 'Debris:AddItem(part, lifetime + 0.1)'):
        assert tok in b


def test_p1b_scope_changed_only_vfx_and_tests():
    changed = subprocess.check_output(['git', 'diff', '--name-only', BASE], cwd=ROOT, text=True).splitlines()
    assert set(changed) <= {'src/client/EffectPlayer.luau', 'src/shared/Data/EffectCatalog.luau', 'tests_py/test_vfx_p1a_contract.py',
        'tests_py/test_vfx_p1d_contract.py', 'src/client/Main.client.luau'}

# P1-C: client-only animation-independent VFX variants for four Alpha characters.

def test_p1c_four_character_cues_have_dedicated_handlers():
    b = PLAYER.read_text()
    assert 'function EffectPlayer:_playP1C' in b
    for prefix in ('"paint."', '"ball."', '"bomb."', '"sling."'):
        assert prefix in b
    assert 'self:_playP1C(cue, def, root, col)' in b


def test_p1c_paint_spots_are_not_generated_for_other_projectiles():
    b = PLAYER.read_text()
    assert 'self._paintEnds[cue.projectileId]' in b
    assert 'string.sub(p.cue.cue, 1, 6) == "paint."' in b
    assert 'if not ended or not ended.paint then return end' in b
    assert 'if name == "paint.splat"' in b
    assert 'self._paintEnds[id] = nil' in b


def test_p1c_ball_and_bomb_events_are_visually_distinct():
    b = PLAYER.read_text()
    for name in ('ball.bounce','ball.cyclone.start','ball.dash','bomb.explosion',
                 'bomb.detonate','bomb.bigbang','paint.explosion'):
        assert f'name == "{name}"' in b
    assert 'cue.radius' in b
    assert 'self:_p1cRing(point, cap * 0.94' in b


def test_p1c_sling_marks_and_ultimate_not_misrepresented():
    b = PLAYER.read_text()
    for name in ('sling.snare.mark','sling.mark','sling.mark.proc',
                 'sling.ult.windup','sling.ult.fire','sling.ult.hit','sling.ult.precise'):
        assert f'"{name}"' in b
    assert 'if not self:_p1cBeam(cue, def, color) then return false end' in b
    assert 'if not a or not b then return false end' in b


def test_p1c_projectiles_preserve_original_movement_and_bound_lod():
    b = PLAYER.read_text()
    assert 'EffectsModel.ballPosition(p.cue, t' in b
    assert 'EffectsModel.projectilePosition(p.cue, t)' in b
    assert 'visibleAt(nextPos, p.cue.mine, 62)' in b
    assert 'if since >= 0.085' in b
    assert 'self:_fade(' in b and 'Debris:AddItem' in b


def test_p1c_no_attacks_or_real_collisions_from_visuals():
    b = PLAYER.read_text()
    for flag in ('p.CanCollide = false', 'p.CanTouch = false',
                 'p.CanQuery = false', 'p.Anchored = true'):
        assert flag in b
    assert 'function EffectPlayer:_p1cSound' in b
    assert 'self:_p1cSound(def.sound' in b


def test_p1c_change_scope_and_cue_contract():
    changed = subprocess.check_output(['git', 'diff', '--name-only', BASE], cwd=ROOT, text=True).splitlines()
    assert set(changed) <= {
        'src/client/EffectPlayer.luau',
        'src/shared/Data/EffectCatalog.luau',
        'tests_py/test_vfx_p1a_contract.py',
        'tests_py/test_vfx_p1d_contract.py',
        'src/client/Main.client.luau', # P1-D one-line visual cleanup at match reset
    }, changed
    assert MODEL.read_text() == baseline('src/client/Logic/EffectsModel.luau')
