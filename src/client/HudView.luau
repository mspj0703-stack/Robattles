--!nonstrict
local C = require(script.Parent.UI.Components)
local T = require(script.Parent.UI.Tokens)
local Crosshairs = require(script.Parent.Logic.Crosshairs)
local Link = require(script.Parent.Link)
local Characters = Link.shared("Data/Characters")
local DEFAULT_TITLES = {"기본 공격","보조 공격","스킬 1","스킬 2","스킬 3"}
local Hud = {}; Hud.__index=Hud
function Hud.new(parent)
	local root=C.new("Frame",parent,{Name="BattleHUD",Size=UDim2.fromScale(1,1),BackgroundTransparency=1})
	local self=setmetatable({root=root,toastUntil=0,slots={}},Hud)
	local top=C.panel(root,"Match",385,44,510,60)
	self.top=C.text(top,"MatchText","TIME —   RANK —   KO —   PLAYERS —",12,5,486,50,20)
	self.top.TextXAlignment=Enum.TextXAlignment.Center
	self.phaseHint=C.text(root,"PhaseHint","",200,8,880,30,18,T.Action)
	self.phaseHint.TextXAlignment=Enum.TextXAlignment.Center; self.phaseHint.Visible=false
	local hp=C.panel(root,"Health",12,540,294,168)
	self.character=C.text(hp,"Character","CONNECTING",14,6,266,28,24,T.Action)
	self.health=C.text(hp,"HealthText","— / —",14,35,266,25,20)
	self.bar=C.bar(hp,"HealthBar",14,66,266,17,T.Health)
	self.dodge=C.text(hp,"Dodge","회피 —",14,91,266,24,17)
	self.passive=C.text(hp,"Passive","서버 상태 대기",14,118,266,44,14)
	for i,key in {"LMB","RMB","1","2","3"} do
		local p=C.panel(root,"Slot"..i,328+(i-1)*139,613,128,95,T.Secondary)
		local k=C.text(p,"Key",key,8,4,112,22,18,T.Action)
		local title=C.text(p,"Skill",({"기본 공격","보조 공격","스킬 1","스킬 2","스킬 3"})[i],8,27,112,24,16)
		local status=C.text(p,"Status","—",8,55,112,30,16)
		local icon=C.new("ImageLabel",p,{Name="SkillIcon",Position=UDim2.fromOffset(100,5),Size=UDim2.fromOffset(20,20),BackgroundTransparency=1,Visible=false})
		self.slots[i]={panel=p,key=k,title=title,status=status,icon=icon}
	end
	local ult=C.panel(root,"Ultimate",1045,540,223,168)
	self.ultKey=C.text(ult,"Key","[F] ULTIMATE",12,8,199,28,20,T.Action)
	self.ultimate=C.text(ult,"Status","—",12,41,199,62,24)
	self.ultBar=C.bar(ult,"Gauge",12,119,199,18,T.Action)
	self.ultHint=C.text(ult,"Hint","서버 판정 기준",12,142,199,20,12,T.Muted)
	self.ammo=C.text(root,"Ammo","",345,558,665,42,20,T.Action)
	self.ammo.TextXAlignment=Enum.TextXAlignment.Center
	self.protect=C.text(root,"Protection","",430,485,420,35,20,T.Health)
	self.protect.TextXAlignment=Enum.TextXAlignment.Center
	self.toast=C.text(root,"Toast","",390,120,500,50,24,T.Action)
	self.toast.TextXAlignment=Enum.TextXAlignment.Center
	self.feed=C.text(root,"KillFeed","",965,120,300,190,17)
	self.feed.TextYAlignment=Enum.TextYAlignment.Top
	self.feed.TextXAlignment=Enum.TextXAlignment.Right
	self.cross=C.text(root,"Crosshair","+",620,340,40,40,26)
	self.cross.TextXAlignment=Enum.TextXAlignment.Center
	self.hit=C.text(root,"HitMarker","×",618,338,44,44,42,T.Danger)
	self.hit.TextXAlignment=Enum.TextXAlignment.Center; self.hit.Visible=false
	self.damage=C.text(root,"DamageNumber","",666,309,140,35,24,T.Action)
	self.lowHealth=C.new("UIStroke",root,{Color=T.Danger,Thickness=5,Enabled=false})
	return self
end
function Hud:setCrosshair(id,visible)
	local d=Crosshairs.get(id)
	if self.characterId~=id then
		self.characterId=id
		for i,slot in self.slots do
			local asset=T.Assets.Skills[id.."/"..({"Primary","Secondary","Skill1","Skill2","Skill3"})[i]]
			slot.icon.Image=asset or ""; slot.icon.Visible=asset~=nil and asset~=""
		end
	end
	self.cross.Visible=visible==true
	self.cross.Text=d.style=="Ring" and "○" or d.style=="Dot" and "•" or "+"
	self.cross.TextSize=math.clamp(math.floor(d.size*1.5)+8,20,44)
end
function Hud:setBindings(binds)
	for i,a in {"Primary","Secondary","Skill1","Skill2","Skill3"} do
		self.slots[i].key.Text=({MouseButton1="LMB",MouseButton2="RMB"})[binds[a]] or binds[a]
	end
	self.ultKey.Text="["..binds.Ultimate.."] ULTIMATE"
end
function Hud:render(m,now)
	if not m then return end
	C.set(self.character,m.characterId or "—"); self.character.TextColor3=T.Themes[m.characterId] or T.Action
	C.set(self.health,m.healthText); self.bar.Size=UDim2.fromScale(m.healthFrac,1)
	self.bar.BackgroundColor3=m.healthFrac<0.25 and T.Danger or T.Health
	self.lowHealth.Enabled=m.alive and m.healthFrac<0.25
	C.set(self.ammo,m.ammo and (m.ammo.reloading and "RELOADING…" or "AMMO "..m.ammo.text) or "")
	C.set(self.dodge,m.dodge and string.format("회피 %d / %d%s",m.dodge.charges,m.dodge.max,m.dodge.nextIn and string.format(" · %.1fs",m.dodge.nextIn) or "") or "회피 —")
	for i,slot in self.slots do
		local s=i==1 and m.primary or i==2 and m.secondary or m.skills[i-2]
		local def=Characters[m.characterId]
		local clientAim=i==2 and def~=nil and def.secondary~=nil and def.secondary.clientOnly==true
		local text="미구현"
		local title=DEFAULT_TITLES[i]
		if i>=3 and s and s.implemented and s.name then title=s.name end
		if clientAim then title=def.secondary.name or "Aim Mode" end
		C.set(slot.title,title)
		if clientAim then
			text=(not m.alive or not m.canAct) and "사용 불가" or "RMB 조준"
		elseif s and (i<=2 or s.implemented) then
			if not m.alive or not m.canAct then text="사용 불가"
			elseif i>=3 and s.label and s.label~="" then text=s.label -- 서버 스냅샷의 단계/충전/설치 상태가 담긴 라벨
			elseif i==1 and m.ammo and m.ammo.reloading then text="장전 중"
			elseif i==1 and m.ammo and m.ammo.empty then text="탄약 없음"
			elseif s.remaining==nil then text="상태 연동 대기"
			elseif s.remaining>0 then text=string.format("%.1fs",s.remaining)
			else text="READY" end
		end
		if i==2 and m.parryActive then text="PARRY!" end
		C.set(slot.status,text); slot.status.TextColor3=(text=="READY" or (i>=3 and s and s.ready)) and T.Health or T.Muted
	end
	local u=m.ultimate
	C.set(self.ultimate,u and (string.format("%d%%",math.floor(u.frac*100)).."\n"..(not u.implemented and "미구현" or u.active and (u.windup and "전조" or "발동 중") or (not m.alive or not m.canAct) and "사용 불가" or u.ready and "READY!" or "충전 중")) or "—")
	self.ultBar.Size=UDim2.fromScale(u and u.frac or 0,1)
	self.protect.Visible=m.protection~=nil
	if m.protection then C.set(self.protect,string.format("SPAWN SHIELD · %.1fs",m.protection.remaining)) end
	self.toast.Visible=now<self.toastUntil
	self.hit.Visible=self.hitUntil~=nil and now<self.hitUntil
	self.damage.Visible=self.damageUntil~=nil and now<self.damageUntil
	self.cross.Visible=m.alive
	if self.shakeUntil and now<self.shakeUntil then
		self.root.Position=UDim2.fromOffset(math.sin(now*90)*3,math.cos(now*70)*2)
	else self.root.Position=UDim2.new() end
end
function Hud:showHitMarker(now) self.hitUntil=now+0.15 end
function Hud:showDamage(amount,now) self.damage.Text=tostring(amount); self.damageUntil=now+0.55 end
function Hud:shake(now) self.shakeUntil=now+0.16 end
function Hud:showToast(text,now,seconds) self.toast.Text=text; self.toastUntil=now+(seconds or 2) end
function Hud:clearTransient()
	self.toastUntil=0; self.hitUntil=nil; self.damageUntil=nil; self.shakeUntil=nil
	self.hit.Visible=false; self.damage.Visible=false; self.toast.Visible=false; self.root.Position=UDim2.new()
end
return Hud
