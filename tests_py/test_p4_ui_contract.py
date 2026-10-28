"""P4 source contracts: presentation-only UI changes (not Roblox rendering tests)."""
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
BASE='8c7f75b'
UI={
    'src/client/HudView.luau',
    'src/client/ScoreboardView.luau',
    'src/client/SettingsView.luau',
    'src/client/UI/App.luau',
    'src/client/UI/Components.luau',
    'src/client/UI/Tokens.luau',
}

def source(path):
    return (ROOT / path).read_text(encoding='utf-8')

def base(path):
    return subprocess.check_output(['git','show',f'{BASE}:{path}'],cwd=ROOT,text=True)


def test_only_ui_presentation_files_changed_since_p3():
    actual=set(subprocess.check_output(['git','diff','--name-only',BASE,'--','src'],cwd=ROOT,text=True).splitlines())
    assert actual==UI


def test_combat_animation_logic_remote_assets_unchanged():
    paths=[
        'src/shared/Data/Characters.luau',
        'src/shared/RemoteSpec.luau',
        'src/client/Main.client.luau',
        'src/client/CharacterAnimator.luau',
        'src/client/SwordAnimator.luau',
        'src/client/Logic/FeedbackModel.luau',
        'src/client/Logic/HudModel.luau',
        'src/client/UI/State.luau',
        'src/client/EffectPlayer.luau',
        'src/shared/Data/SfxProfiles.luau',
    ]
    assert all(source(p)==base(p) for p in paths)
    changed=subprocess.check_output(['git','diff','--name-only',BASE,'--','src/server'],cwd=ROOT,text=True).strip()
    assert not changed


def test_one_gui_and_page_flow_kept():
    a=source('src/client/UI/App.luau')
    for key in ['Name="RoBattlesUI"','Name="Canvas"','self.hud=Hud.new(canvas)',
                'self.menu=C.panel(', 'self.characterPage=C.panel(',
                'self.settings=Settings.new(', 'self.results=C.new(',
                'self:requestSelection()', 'self.state:myScore()',
                'self.state:status(now)', 'self:updateVisibility()']:
        assert key in a


def test_theme_and_button_palette_present():
    tokens=source('src/client/UI/Tokens.luau')
    for name in ['Panel','Secondary','Surface','SurfaceRaised','Action','Health','Danger','Text','Muted','Outline','Themes']:
        assert re.search(r'\b'+name+r'\s*=',tokens)
    for cid in ['SWORD','PAINTBALL','SUPERBALL','TIMEBOMB','SLINGSHOT']:
        assert re.search(r'\b'+cid+r'\s*=',tokens)
    components=source('src/client/UI/Components.luau')
    for key in ['function C.button(', 'b.Activated:Connect(callback)',
                'function C.scroll(', 'function C.bar(', 'UIStroke','UICorner']:
        assert key in components


def test_character_selection_highlight_is_cosmetic():
    a=source('src/client/UI/App.luau')
    assert 'b.BackgroundColor3=cid==id and T.Themes[cid] or T.Secondary' in a
    assert 'b.TextColor3=cid==id and T.Outline or T.Text' in a
    assert 'RemoteSpec.validate("SelectCharacter",{characterId=id})' in a
    assert 'self.callbacks.select(self.selected)' in a
    assert 'selectionPending(now)' in a


def test_hud_status_data_server_authoritative():
    h=source('src/client/HudView.luau')
    a=source('src/client/UI/App.luau')
    for token in ['C.set(self.health,m.healthText)', 'self.bar.Size=UDim2.fromScale(m.healthFrac,1)',
                  'self.ultBar.Size=UDim2.fromScale(u and u.frac or 0,1)',
                  'function Hud:showDamage(amount,now)', 'self.damageHits += 1',
                  'function Hud:showKO(healed,now)', 'function Hud:clearTransient()']:
        assert token in h
    assert 'self.state.lastKillAt and self.state.lastKillAt~=self.shownKillAt' in a
    assert 'self.hud:showTakenDamage(event.amount,now)' in a


def test_hud_slots_and_bottom_panels_fit_reference_canvas():
    h=source('src/client/HudView.luau')
    assert 'local hp=C.panel(root,"Health",12,562,294,146)' in h
    assert 'local p=C.panel(root,"Slot"..i,325+(i-1)*140,608,130,100,T.Secondary)' in h
    assert 'local ult=C.panel(root,"Ultimate",1045,562,223,146)' in h
    # last slot (i=5) and ultimate fit 1280x720 reference resolution
    assert 325+4*140+130 < 1045
    assert 1045+223<=1280 and 562+146<=720 and 608+100<=720


def test_rank_scores_are_server_driven():
    b=source('src/client/ScoreboardView.luau')
    for token in ['C.set(cell.rank,tostring(r.rank or i))',
                  'C.set(cell.kills,tostring(r.kills))',
                  'C.set(cell.deaths,tostring(r.deaths))',
                  'cell.root.BackgroundColor3=mine and T.Action']:
        assert token in b


def test_sound_settings_callbacks_kept():
    a=source('src/client/UI/App.luau')
    s=source('src/client/SettingsView.luau')
    assert 'if group then group.Volume=value end' in a
    assert 'onBindings(binds); self.hud:setBindings(binds)' in a
    assert 'function Settings:handleInput(obj)' in s
    assert 'if ok and self.onChanged then self.onChanged(self.settings.binds) end' in s


def test_no_fabricated_assets_and_no_gameplay_constants_added():
    t=source('src/client/UI/Tokens.luau')
    assert 'Logo = ""' in t and 'Portraits = {}' in t and 'Skills = {}' in t
    for file in UI:
        s=source(file)
        assert 'rbxassetid://' not in s


def test_no_source_changes_outside_p4_scope():
    actual=set(subprocess.check_output(['git','diff','--name-only',BASE,'--','src'],cwd=ROOT,text=True).splitlines())
    assert actual<=UI
