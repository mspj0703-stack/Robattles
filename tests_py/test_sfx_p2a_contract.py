"""P2-A SFX isolation checks. Source-level only; Studio audio playback remains untested."""
from pathlib import Path
import json, subprocess

ROOT=Path(__file__).resolve().parents[1]
P=(ROOT/'src/client/EffectPlayer.luau').read_text()
S=(ROOT/'src/shared/Data/SfxProfiles.luau').read_text()
BASE='a69519a'

def baseline(f):
    return subprocess.check_output(['git','show',f'{BASE}:{f}'],cwd=ROOT,text=True)

def test_sound_group_preference_unchanged():
    assert (ROOT/'src/client/UI/App.luau').read_text() == baseline('src/client/UI/App.luau')
    assert '"RoBattlesSFX"' in P
    assert 'sound.SoundGroup = SoundService:FindFirstChild("RoBattlesSFX")' in P

def test_audio_definitions_cosmetic_only():
    assert 'function SfxProfiles.forCue(cueName, soundName)' in S
    for family in ['sword','paint','ball','bomb','sling','hit']:
        assert f'{family} = {{' in S
    assert 'Link.shared("Data/SfxProfiles")' in P
    assert 'function EffectPlayer:_sound(soundName, parent, cueName, mine)' in P
    assert 'self:_p1cSound(def.sound, root, pointFor(cue, root, 1.5), cue.cue, cue.mine)' in P

def test_no_fake_hit_or_gameplay_changes():
    for f in ['src/client/Logic/EffectsModel.luau','src/shared/Data/EffectCatalog.luau',
              'src/shared/Data/Characters.luau','src/client/Main.client.luau',
              'src/client/SwordAnimator.luau','src/client/CharacterAnimator.luau',
              'src/client/UI/App.luau']:
        assert (ROOT/f).read_text() == baseline(f), f
    changed = subprocess.check_output(['git','diff','--name-only',BASE],cwd=ROOT,text=True).splitlines()
    assert set(changed) <= {'src/client/EffectPlayer.luau','src/shared/Data/SfxProfiles.luau',
                             'default.project.json','integrated.project.json',
                             'tests_py/test_vfx_p1a_contract.py','tests_py/test_vfx_p1d_contract.py',
                             'tests_py/test_sfx_p2a_contract.py', 'docs/P1E_P2A_IMPLEMENTATION_REPORT.md'}

def test_audio_safe_fallback():
    for token in ['override:IsA("Sound")', 'override.SoundId ~= ""',
                  'fallback.id', 'soundAssets:FindFirstChild(cueName or "")',
                  'soundAssets:FindFirstChild(soundName)', 'sound.PlaybackSpeed = math.clamp(',
                  'sound.Volume = math.clamp(']:
        assert token in P

def test_audio_is_bounded_and_match_cleanup():
    for token in ['voiceCount >= 18', 'profile.minGap', 'self._lastSound[key]',
                  'self._voices[sound] = true', 'sound.Ended:Connect(',
                  'for sound in self._voices do', 'sound:Destroy()',
                  'table.clear(self._lastSound)', 'Debris:AddItem(sound, 4)']:
        assert token in P

def test_project_maps_optional_sound_folder():
    for project in ('default.project.json','integrated.project.json'):
        obj=json.loads((ROOT/project).read_text())
        assert obj['tree']['ReplicatedStorage']['RoBattles']['Assets']['Sounds']['$className']=='Folder'

def test_only_predefined_effect_cues_still_play():
    assert 'local def = Catalog.Cues[name]' in P
    assert 'if not def then' in P
    assert 'function EffectPlayer:play(cue)' in P
