"""P1-D static renderer contracts; no claims about Roblox/Studio runtime behavior."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PLAYER = (ROOT / 'src/client/EffectPlayer.luau').read_text()
MAIN = (ROOT / 'src/client/Main.client.luau').read_text()


def test_p1c_whole_model_survives_projectile_spawn_and_motion():
    assert 'part = part.PrimaryPart or part:FindFirstChildWhichIsA' not in PLAYER
    assert 'part = self:_spawnAsset(name, CFrame.new(point), def.lifetime, true)' in PLAYER
    assert 'if p.part:IsA("Model") then' in PLAYER
    assert 'p.part:PivotTo(CFrame.new(nextPos))' in PLAYER
    assert 'EffectsModel.projectilePosition(p.cue, t)' in PLAYER
    assert 'EffectsModel.ballPosition(p.cue, t,' in PLAYER


def test_particle_and_sound_override_support():
    for token in ['clone:IsA("Attachment")', 'clone:IsA("ParticleEmitter")',
                  'obj:Emit(', 'obj.Enabled = false', 'SoundService:FindFirstChild("RoBattlesSFX")',
                  'clone:PivotTo(at)', 'obj.SoundGroup', 'Debris:AddItem(placed,']:
        assert token in PLAYER, token


def test_safe_fallback_noncollision_and_cleanup():
    for token in ['return nil, false', 'visualPart(obj)', 'p.CanTouch = false',
                  'p.CanQuery = false', 'p.CanCollide = false',
                  'function EffectPlayer:clear()', 'self._folder:ClearAllChildren()',
                  'table.clear(self._projectiles)', 'table.clear(self._paintEnds)']:
        assert token in PLAYER, token
    assert 'effects:clear() -- P1-D' in MAIN
    assert MAIN.count('effects:clear() -- P1-D') == 1


def test_only_one_line_in_main_from_p1c_and_combat_contract_preserved():
    before = subprocess.check_output(['git', 'show', '4fe2575:src/client/Main.client.luau'],cwd=ROOT,text=True)
    assert MAIN.replace('            effects:clear() -- P1-D: remove prior-round visual projectiles/particles only\n','') == before
    changed = subprocess.check_output(['git', 'diff', '--name-only', '4fe2575'], cwd=ROOT,text=True).splitlines()
    assert set(changed) <= {'src/client/EffectPlayer.luau', 'src/client/Main.client.luau',
                            'tests_py/test_vfx_p1a_contract.py', 'tests_py/test_vfx_p1d_contract.py',
                            'src/shared/Data/SfxProfiles.luau', 'default.project.json',
                            'integrated.project.json', 'tests_py/test_sfx_p2a_contract.py', 'docs/P1E_P2A_IMPLEMENTATION_REPORT.md'}
    for f in ['src/client/CharacterAnimator.luau','src/client/SwordAnimator.luau',
              'src/shared/Data/Characters.luau','src/shared/Data/EffectCatalog.luau',
              'src/client/Logic/EffectsModel.luau']:
        assert (ROOT/f).read_text() == subprocess.check_output(['git', 'show', f'4fe2575:{f}'],cwd=ROOT,text=True)


def test_quality_levels_only_affect_visuals():
    assert 'function EffectPlayer:setQuality(level)' in PLAYER
    assert 'self._quality ~= "low"' in PLAYER
    assert 'self._quality == "low"' in PLAYER
    assert 'function EffectPlayer:_playP1C(' in PLAYER
    assert 'function EffectPlayer:_hitImpact(' in PLAYER
