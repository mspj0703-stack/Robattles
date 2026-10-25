--!nonstrict
local Link=require(script.Parent.Link)
local Keybinds=Link.shared("Keybinds")
local C=require(script.Parent.UI.Components)
local T=require(script.Parent.UI.Tokens)
local Settings={}; Settings.__index=Settings
local LABELS={CameraToggle="시점 전환",RunToggle="달리기",Dodge="회피",Ultimate="궁극기",Primary="기본 공격",Secondary="보조 공격",Reload="장전",FreeLook="자유 시점 회전",Skill1="스킬 1",Skill2="스킬 2",Skill3="스킬 3",Scoreboard="스코어보드"}
function Settings.new(settings,onChanged,onToggle,parent,preferences,onPreference)
	local root=C.panel(parent,"Settings",205,48,870,624)
	local self=setmetatable({root=root,settings=settings,onChanged=onChanged,onToggle=onToggle,buttons={},values={},preferences=preferences,onPreference=onPreference},Settings)
	C.text(root,"Title","SETTINGS",24,12,680,45,32,T.Action)
	C.button(root,"Close","닫기",738,18,100,36,function() self:setOpen(false) end)
	self.msg=C.text(root,"Message","이 설정은 현재 접속 동안 유지됩니다.",24,65,820,34,16,T.Muted)
	local list=C.scroll(root,"Options",20,110,830,486)
	local specs={{"sensitivity","마우스 감도",0.25,2,0.25},{"scale","UI 크기",0.75,1.25,0.05},{"sfx","효과음",0,1,0.1},{"music","음악",0,1,0.1}}
	for i,s in specs do
		local y=(i-1)*48
		C.text(list,s[1].."Label",s[2],6,y,420,40,19)
		local value=C.text(list,s[1].."Value","",520,y,160,40,19,T.Action); self.values[s[1]]=value
		local function adjust(delta)
			preferences[s[1]]=math.clamp(math.round((preferences[s[1]]+delta)*100)/100,s[3],s[4]); self:refresh()
			if onPreference then onPreference(s[1],preferences[s[1]]) end
		end
		C.button(list,s[1].."Minus","−",462,y+3,45,34,function() adjust(-s[5]) end)
		C.button(list,s[1].."Plus","+",730,y+3,45,34,function() adjust(s[5]) end)
	end
	for i,s in {{"damageNumbers","피해 숫자"},{"shake","피격 시 HUD 흔들림"}} do
		local y=196+(i-1)*48
		C.text(list,s[1].."Label",s[2],6,y,500,40,19)
		self.values[s[1]]=C.button(list,s[1],"",585,y+3,190,34,function()
			preferences[s[1]]=not preferences[s[1]]; self:refresh()
			if onPreference then onPreference(s[1],preferences[s[1]]) end
		end)
	end
	C.text(list,"AudioNote","음악·효과음은 등록된 오디오가 있을 때 재생됩니다.",6,293,790,33,14,T.Muted)
	C.text(list,"KeyHeader","KEY BINDINGS · 클릭 후 새 키 입력",6,336,790,34,22,T.Action)
	for i,action in Keybinds.Actions do
		self.buttons[action]=C.button(list,action,"",6,380+(i-1)*45,770,36,function()
			self.waiting=action; self.msg.Text=(LABELS[action] or action)..": 새 키 입력 (Esc 취소)"
		end,T.Secondary)
		self.buttons[action].TextColor3=T.Text
	end
	C.text(list,"Bottom","F10: 설정 열기/닫기 · F9: 메뉴 · 이동 WASD / 점프 Space",6,930,790,44,16,T.Muted)
	root.Visible=false; self:refresh(); return self
end
function Settings:refresh()
	for action,b in self.buttons do b.Text=(LABELS[action] or action).." : "..self.settings.binds[action] end
	for key,l in self.values do
		local v=self.preferences[key]
		l.Text=type(v)=="boolean" and (v and "ON" or "OFF") or string.format("%.2f",v)
	end
end
function Settings:setOpen(open)
	self.root.Visible=open; self.waiting=nil
	if self.onToggle then self.onToggle(open) end
end
function Settings:isOpen() return self.root.Visible end
function Settings:handleInput(obj)
	if not self.waiting then return false end
	local name=obj.KeyCode~=Enum.KeyCode.Unknown and obj.KeyCode.Name or obj.UserInputType.Name
	if name=="Escape" then self.waiting=nil; self.msg.Text="취소됨"; return true end
	if obj.UserInputType~=Enum.UserInputType.Keyboard and obj.UserInputType~=Enum.UserInputType.MouseButton1 and obj.UserInputType~=Enum.UserInputType.MouseButton2 and obj.UserInputType~=Enum.UserInputType.MouseButton3 then return true end
	if name=="F9" or name=="F10" then self.msg.Text="F9 / F10은 UI 예약 키입니다"; self.waiting=nil; return true end
	local ok,err=self.settings:set(self.waiting,name)
	self.msg.Text=ok and "변경됨" or ("거부: "..tostring(err)); self.waiting=nil
	if ok and self.onChanged then self.onChanged(self.settings.binds) end
	self:refresh(); return true
end
return Settings
