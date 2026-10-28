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
	local top=C.panel(root,"Match",385,34,510,78)
    C.new("Frame",top,{Name="TopAccent",Position=UDim2.fromOffset(15,8),Size=UDim2.fromOffset(480,3),BackgroundColor3=T.Action,BorderSizePixel=0})
    local matchLabel=C.text(top,"Label","FREE FOR ALL   /   MATCH STATUS",12,13,486,17,12,T.Muted)
    matchLabel.TextXAlignment=Enum.TextXAlignment.Center
    self.top=C.text(top,"MatchText","TIME —   RANK —   KO —   PLAYERS —",12,30,486,45,19)
	self.top.TextXAlignment=Enum.TextXAlignment.Center
	self.phaseHint=C.text(root,"PhaseHint","",200,8,880,30,18,T.Action)
	self.phaseHint.TextXAlignment=Enum.TextXAlignment.Center; self.phaseHint.Visible=false
	local hp=C.panel(root,"Health",12,562,294,146)
	self.character=C.text(hp,"Character","CONNECTING",14,8,266,28,22,T.Action)
	self.health=C.text(hp,"HealthText","— / —",14,38,266,25,19)
	self.bar=C.bar(hp,"HealthBar",14,65,266,16,T.Health)
	self.dodge=C.text(hp,"Dodge","회피 —",14,84,266,24,16)
	self.passive=C.text(hp,"Passive","서버 상태 대기",14,111,266,32,13)
	for i,key in {"LMB","RMB","1","2","3"} do
		local p=C.panel(root,"Slot"..i,325+(i-1)*140,608,130,100,T.Secondary)
		local k=C.text(p,"Key",key,9,5,111,22,18,T.Action)
		local title=C.text(p,"Skill",({"기본 공격","보조 공격","스킬 1","스킬 2","스킬 3"})[i],9,28,112,30,15)
		local status=C.text(p,"Status","—",9,64,112,28,17)
		local icon=C.new("ImageLabel",p,{Name="SkillIcon",Position=UDim2.fromOffset(102,6),Size=UDim2.fromOffset(20,20),BackgroundTransparency=1,Visible=false})
		self.slots[i]={panel=p,key=k,title=title,status=status,icon=icon}
	end
	local ult=C.panel(root,"Ultimate",1045,562,223,146)
	self.ultKey=C.text(ult,"Key","[F] ULTIMATE",12,10,199,27,19,T.Action)
	self.ultimate=C.text(ult,"Status","—",12,38,199,65,22)
	self.ultBar=C.bar(ult,"Gauge",12,111,199,15,T.Action)
	self.ultHint=C.text(ult,"Hint","서버 판정 기준",12,126,199,17,12,T.Muted)
	self.ammo=C.text(root,"Ammo","",325,566,688,38,19,T.Action)
	self.ammo.TextXAlignment=Enum.TextXAlignment.Center
	self.protect=C.text(root,"Protection","",430,485,420,35,20,T.Health)
	self.protect.TextXAlignment=Enum.TextXAlignment.Center
	-- KO is separate from generic toast and incoming damage so these messages never overwrite each other.
    self.ko=C.text(root,"KONotice","",450,173,380,55,34,T.Action)
    self.ko.TextXAlignment=Enum.TextXAlignment.Center; self.ko.Visible=false
    self.taken=C.text(root,"TakenDamage","",497,410,286,34,21,T.Danger)
    self.taken.TextXAlignment=Enum.TextXAlignment.Center; self.taken.Visible=false
    self.toast=C.text(root,"Toast","",390,120,500,50,24,T.Action)
	self.toast.TextXAlignment=Enum.TextXAlignment.Center
	self.feed=C.text(root,"KillFeed","",956,126,307,181,17)
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
		C.set(slot.status,text)
        local ready=text=="READY" or (i>=3 and s and s.ready)
        slot.status.TextColor3=ready and T.Health or (text=="사용 불가" and T.Danger or T.Muted)
        slot.panel.BackgroundColor3=ready and T.SurfaceRaised or T.Secondary
	end
	local u=m.ultimate
	C.set(self.ultimate,u and (string.format("%d%%",math.floor(u.frac*100)).."\n"..(not u.implemented and "미구현" or u.active and (u.windup and "전조" or "발동 중") or (not m.alive or not m.canAct) and "사용 불가" or u.ready and "READY!" or "충전 중")) or "—")
	self.ultBar.Size=UDim2.fromScale(u and u.frac or 0,1)
	self.protect.Visible=m.protection~=nil
	if m.protection then C.set(self.protect,string.format("SPAWN SHIELD · %.1fs",m.protection.remaining)) end
	self.toast.Visible=now<self.toastUntil
	self.ko.Visible=self.koUntil~=nil and now<self.koUntil
    self.taken.Visible=self.takenUntil~=nil and now<self.takenUntil
    self.hit.Visible=self.hitUntil~=nil and now<self.hitUntil
	self.damage.Visible=self.damageUntil~=nil and now<self.damageUntil
	self.cross.Visible=m.alive
	if self.shakeUntil and now<self.shakeUntil then
		self.root.Position=UDim2.fromOffset(math.sin(now*90)*3,math.cos(now*70)*2)
	else self.root.Position=UDim2.new() end
end
function Hud:showHitMarker(now) self.hitUntil=now+0.15 end
-- Accumulate rapid *server-confirmed* hits into one readable counter; never invent bonus damage.
function Hud:showDamage(amount,now)
    if type(amount) ~= "number" or amount ~= amount or amount <= 0 then return end
    if self.damageWindowEnd and now <= self.damageWindowEnd then
        self.damageTotal += amount
        self.damageHits += 1
    else
        self.damageTotal = amount
        self.damageHits = 1
    end
    self.damageWindowEnd = now + 0.16
    self.damage.Text = string.format("%d%s", math.floor(self.damageTotal + 0.5), self.damageHits > 1 and ("  x" .. self.damageHits) or "")
    self.damageUntil = now + 0.55
end
function Hud:showTakenDamage(amount,now)
    if type(amount) ~= "number" or amount ~= amount or amount <= 0 then return end
    self.taken.Text = string.format("-%d", math.floor(amount + 0.5))
    self.takenUntil = now + 0.35
end
function Hud:showKO(healed,now)
    local heal = type(healed) == "number" and healed == healed and healed > 0 and math.floor(healed+0.5) or 0
    if self.koUntil and now < self.koUntil and self.koLastAt and now - self.koLastAt <= 0.6 then
        self.koCount += 1
    else
        self.koCount = 1
    end
    self.koLastAt = now
    self.ko.Text = "KO!" .. (self.koCount > 1 and (" x" .. self.koCount) or "") .. (heal > 0 and ("  +" .. heal .. " HP") or "")
    self.koUntil = now + 1.1
    -- Keep the old toast for existing UI users and test contracts.
    self:showToast(heal > 0 and string.format("KO!  +%d HP",heal) or "KO!",now,1)
end
function Hud:shake(now) self.shakeUntil=now+0.16 end
function Hud:showToast(text,now,seconds) self.toast.Text=text; self.toastUntil=now+(seconds or 2) end
function Hud:clearTransient()
	self.toastUntil=0; self.hitUntil=nil; self.damageUntil=nil; self.shakeUntil=nil
    self.koUntil=nil; self.koLastAt=nil; self.koCount=nil
    self.takenUntil=nil; self.damageWindowEnd=nil; self.damageHits=nil; self.damageTotal=nil
	self.hit.Visible=false; self.damage.Visible=false; self.toast.Visible=false
    self.ko.Visible=false; self.taken.Visible=false; self.root.Position=UDim2.new()
end
-- Two small-screen profiles adjust geometry only; authority and input bindings stay unchanged.
function Hud:applyLayout(profile)
    if profile=="portrait" then
        self.root:FindFirstChild("Match").Position=UDim2.fromOffset(182,23)
        self.root:FindFirstChild("Match").Size=UDim2.fromOffset(526,88)
        self.root:FindFirstChild("Match"):FindFirstChild("TopAccent").Size=UDim2.fromOffset(498,3)
        self.phaseHint.Position=UDim2.fromOffset(115,124)
        self.phaseHint.Size=UDim2.fromOffset(490,42)
        local hp=self.root:FindFirstChild("Health")
        hp.Position=UDim2.fromOffset(14,896); hp.Size=UDim2.fromOffset(402,164)
        for _,name in {"Character","HealthText","Dodge","Passive"} do
            local obj=hp:FindFirstChild(name)
            if obj then obj.Size=UDim2.fromOffset(366,obj.Size.Y.Offset) end
        end
        hp:FindFirstChild("HealthBar").Position=UDim2.fromOffset(14,65)
        hp:FindFirstChild("HealthBar").Size=UDim2.fromOffset(366,16)
        local ult=self.root:FindFirstChild("Ultimate")
        ult.Position=UDim2.fromOffset(430,896); ult.Size=UDim2.fromOffset(275,164)
        for _,name in {"Key","Status","Gauge","Hint"} do
            local obj=ult:FindFirstChild(name)
            if obj then obj.Size=UDim2.fromOffset(247,obj.Size.Y.Offset) end
        end
        for i,slot in self.slots do
            local x=12+(i-1)*141
            slot.panel.Position=UDim2.fromOffset(x,1075)
            slot.panel.Size=UDim2.fromOffset(132,92)
            slot.title.TextSize=14
            slot.status.TextSize=17
            slot.status.Position=UDim2.fromOffset(9,60)
            slot.status.Size=UDim2.fromOffset(114,27)
        end
        self.ammo.Position=UDim2.fromOffset(100,849); self.ammo.Size=UDim2.fromOffset(520,36)
        self.protect.Position=UDim2.fromOffset(150,802); self.protect.Size=UDim2.fromOffset(420,35)
        self.ko.Position=UDim2.fromOffset(170,222); self.ko.Size=UDim2.fromOffset(380,55)
        self.taken.Position=UDim2.fromOffset(220,674); self.taken.Size=UDim2.fromOffset(280,35)
        self.toast.Position=UDim2.fromOffset(102,151); self.toast.Size=UDim2.fromOffset(516,55)
        self.feed.Position=UDim2.fromOffset(374,294); self.feed.Size=UDim2.fromOffset(328,190)
        self.cross.Position=UDim2.fromOffset(340,565)
        self.hit.Position=UDim2.fromOffset(338,563)
        self.damage.Position=UDim2.fromOffset(386,533)
    elseif profile=="compact" then
        self.root:FindFirstChild("Match").Position=UDim2.fromOffset(258,7)
        self.phaseHint.Position=UDim2.fromOffset(195,3)
        self.phaseHint.Size=UDim2.fromOffset(630,30)
        local hp=self.root:FindFirstChild("Health")
        hp.Position=UDim2.fromOffset(9,420); hp.Size=UDim2.fromOffset(232,146)
        for _,name in {"Character","HealthText","Dodge","Passive"} do
            local obj=hp:FindFirstChild(name)
            if obj then obj.Size=UDim2.fromOffset(205,obj.Size.Y.Offset) end
        end
        hp:FindFirstChild("HealthBar").Size=UDim2.fromOffset(205,16)
        for i,slot in self.slots do
            slot.panel.Position=UDim2.fromOffset(248+(i-1)*116,470)
            slot.panel.Size=UDim2.fromOffset(109,94)
            slot.key.TextSize=16
            slot.title.Size=UDim2.fromOffset(91,30); slot.title.TextSize=13
            slot.status.Position=UDim2.fromOffset(9,60)
            slot.status.Size=UDim2.fromOffset(91,28); slot.status.TextSize=15
        end
        local ult=self.root:FindFirstChild("Ultimate")
        ult.Position=UDim2.fromOffset(832,420); ult.Size=UDim2.fromOffset(182,146)
        for _,name in {"Key","Status","Gauge","Hint"} do
            local obj=ult:FindFirstChild(name)
            if obj then obj.Size=UDim2.fromOffset(156,obj.Size.Y.Offset) end
        end
        self.ultKey.TextSize=16; self.ultimate.TextSize=20
        self.ammo.Position=UDim2.fromOffset(248,427); self.ammo.Size=UDim2.fromOffset(566,32)
        self.protect.Position=UDim2.fromOffset(306,380)
        self.ko.Position=UDim2.fromOffset(322,112)
        self.taken.Position=UDim2.fromOffset(370,308)
        self.toast.Position=UDim2.fromOffset(260,90)
        self.feed.Position=UDim2.fromOffset(756,102); self.feed.Size=UDim2.fromOffset(247,165)
        self.feed.TextSize=14
        self.cross.Position=UDim2.fromOffset(492,268)
        self.hit.Position=UDim2.fromOffset(490,266)
        self.damage.Position=UDim2.fromOffset(536,239)
    end
end

return Hud
