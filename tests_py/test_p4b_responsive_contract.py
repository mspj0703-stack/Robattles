"""P4-B static responsive UI contracts (NOT Roblox rendering or device tests)."""
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
P4='5f3c7c5'
ALLOWED={
    'src/client/UI/Responsive.luau',
    'src/client/UI/App.luau',
    'src/client/HudView.luau',
    'src/client/SettingsView.luau',
    'src/client/ScoreboardView.luau',
}

def code(path): return (ROOT/path).read_text(encoding='utf8')

def test_p4b_only_presentation_sources():
    tracked=set(subprocess.check_output(['git','diff','--name-only',P4,'--','src'],cwd=ROOT,text=True).splitlines())
    assert tracked<=ALLOWED
    assert 'src/client/UI/Responsive.luau' in ALLOWED
    for critical in ['src/client/Main.client.luau', 'src/client/CharacterAnimator.luau',
                     'src/client/SwordAnimator.luau', 'src/shared/Data/Characters.luau',
                     'src/shared/RemoteSpec.luau', 'src/client/Logic/HudModel.luau']:
        before=subprocess.check_output(['git','show',f'{P4}:{critical}'],cwd=ROOT,text=True)
        assert before==code(critical),critical
    assert not subprocess.check_output(['git','diff','--name-only',P4,'--','src/server'],cwd=ROOT,text=True).strip()

def test_three_profile_layout_and_safearea():
    r=code('src/client/UI/Responsive.luau')
    a=code('src/client/UI/App.luau')
    for token in ['desktop = Vector2.new(1280, 720)', 'compact = Vector2.new(1024, 576)',
                  'portrait = Vector2.new(720, 1180)', 'function Responsive.choose(width, height)',
                  'function Responsive.fit(width, height, preferred, profile)',
                  'math.clamp(preferred or 1, 0.75, 1.25)']:
        assert token in r
    for token in ['Enum.ScreenInsets.DeviceSafeInsets', 'IgnoreGuiInset=false',
                  'function App:layoutPortrait()', 'function App:layoutCompact()',
                  'function App:restoreGeometry()', 'self:restoreGeometry()',
                  'self.canvas.Size=UDim2.fromOffset(reference.X,reference.Y)',
                  'self.scale.Scale=Responsive.fit(']:
        assert token in a

def test_hud_and_menu_interaction_retained():
    a=code('src/client/UI/App.luau')
    h=code('src/client/HudView.luau')
    for token in ['self:requestSelection()', 'self.settings=Settings.new(',
                  'self.menuButton=C.button(', 'self:open(',
                  'self.state:status(now)', 'self:updateVisibility()']:
        assert token in a
    for token in ['self.hud:applyLayout("portrait")','self.hud:applyLayout("compact")']:
        assert token in a
    for token in ['function Hud:applyLayout(profile)',
                  'function Hud:showDamage(amount,now)', 'self.damageHits += 1',
                  'function Hud:showKO(healed,now)', 'C.set(self.health,m.healthText)',
                  'self.ultBar.Size=UDim2.fromScale(u and u.frac or 0,1)']:
        assert token in h
    assert 'slot.icon.Visible=false' not in h  # should not stick hidden after orientation change

def test_scroll_and_scoreboard_keep_data_contract():
    a=code('src/client/UI/App.luau')
    s=code('src/client/SettingsView.luau')
    b=code('src/client/ScoreboardView.luau')
    assert 'self.settings:applyLayout("portrait")' in a
    assert 'self.board:applyLayout("portrait")' in a
    assert 'self.resultBoard:applyLayout("portrait")' in a
    assert 'self.list=C.scroll' not in s
    assert 'self.list=list' in s
    assert 'function Settings:handleInput(obj)' in s
    assert 'if ok and self.onChanged then self.onChanged(self.settings.binds) end' in s
    assert 'C.set(cell.kills,tostring(r.kills))' in b
    assert 'C.set(cell.rank,tostring(r.rank or i))' in b
    assert 'function Board:applyLayout(profile)' in b

def test_reference_canvas_major_panels_fit():
    # Dimensions here are the explicitly authored profiles, not measured device geometry.
    portrait=[(25,92,670,965),(12,42,696,1096),(15,68,690,1010),
              (13,72,694,976),(12,25,160,54),(14,896,402,164),
              (430,896,275,164),(12+4*141,1075,132,92)]
    compact=[(20,12,984,552),(12,10,1000,556),(52,12,920,552),
             (162,12,700,552),(832,420,182,146),(248+4*116,470,109,94)]
    for x,y,w,h in portrait:
        assert 0<=x and 0<=y and w>0 and h>0 and x+w<=720 and y+h<=1180,(x,y,w,h)
    for x,y,w,h in compact:
        assert 0<=x and 0<=y and w>0 and h>0 and x+w<=1024 and y+h<=576,(x,y,w,h)
