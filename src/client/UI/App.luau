--!nonstrict
local Players=game:GetService("Players")
local StarterGui=game:GetService("StarterGui")
local SoundService=game:GetService("SoundService")
local ContextActionService=game:GetService("ContextActionService")
local Link=require(script.Parent.Parent.Link)
local Config=Link.shared("Config")
local Characters=Link.shared("Data/Characters")
local RemoteSpec=Link.shared("RemoteSpec")
local C=require(script.Parent.Components)
local T=require(script.Parent.Tokens)
local Catalog=require(script.Parent.Catalog)
local Preview=require(script.Parent.Preview)
local State=require(script.Parent.State)
local Hud=require(script.Parent.Parent.HudView)
local Board=require(script.Parent.Parent.ScoreboardView)
local Settings=require(script.Parent.Parent.SettingsView)
local App={}; App.__index=App
function App.new(settings,onBindings)
	local pg=Players.LocalPlayer:WaitForChild("PlayerGui")
	-- Main has a singleton guard. Remove only legacy views owned by this client.
	for _,name in {"RoBattlesHud","RoBattlesScoreboard","RoBattlesSettings"} do
		local old=pg:FindFirstChild(name); if old then old:Destroy() end
	end
	local gui=C.new("ScreenGui",pg,{Name="RoBattlesUI",ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=20,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
	local bounds=C.new("Frame",gui,{Name="Bounds",Size=UDim2.fromScale(1,1),BackgroundTransparency=1})
	local canvas=C.new("Frame",bounds,{Name="Canvas",AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(1280,720),BackgroundTransparency=1})
	local scale=C.new("UIScale",canvas,{Scale=1})
	local self=setmetatable({gui=gui,bounds=bounds,canvas=canvas,scale=scale,state=State.new(Players.LocalPlayer.UserId,Config.Match.RespawnSeconds),connections={},selected="SWORD",callbacks={},lastBlocking=nil},App)
	self.hud=Hud.new(canvas)
	self.hud:setBindings(settings.binds)
	self.menuButton=C.button(canvas,"MenuButton","MENU · F9",12,44,164,40,function() self:open("Menu") end)
	self.menu=C.panel(canvas,"MainMenu",75,62,1130,596)
	self.menuLogo=C.text(self.menu,"Logo","RoBattles!",36,26,610,100,76,T.Action); self.menuLogo.Font=T.Font; self.menuLogo.Rotation=-3
	if T.Assets.Logo~="" then
		self.menuLogo.Visible=false
		C.new("ImageLabel",self.menu,{Name="LogoArt",Image=T.Assets.Logo,BackgroundTransparency=1,Position=self.menuLogo.Position,Size=self.menuLogo.Size,ScaleType=Enum.ScaleType.Fit})
	end
	C.text(self.menu,"Subtitle","ALPHA 1.0  /  BRICKYARD",40,136,600,40,24,T.Muted)
	Preview.new(self.menu,590,198,498,346,"SWORD")
	C.text(self.menu,"SceneNote","BLOCK ARENA · 임시 3D 장면",609,551,470,26,14,T.Muted)
	for i,item in {{"PLAY","Battle"},{"CHARACTERS","Characters"},{"HOW TO PLAY","Help"},{"SETTINGS","Settings"}} do
		C.button(self.menu,item[1],item[1],42,212+(i-1)*80,493,60,function()
			-- PLAY with no server-confirmed selection sends the player to the character page instead of an empty arena.
			if item[2]=="Battle" and self.state:status(workspace:GetServerTimeNow())=="Menu" then self.returnPage="Battle"; self:open("Characters")
			else self:open(item[2]) end
		end,i==1 and T.Action or T.Secondary).TextColor3=i==1 and T.Outline or T.Text
	end
	self.menuNote=C.text(self.menu,"MenuNote","메뉴를 열어도 서버 경기는 계속됩니다.",42,540,500,36,14,T.Muted)
	self.characterPage=C.panel(canvas,"Characters",65,40,1150,640)
	C.text(self.characterPage,"Title","CHOOSE YOUR FIGHTER",24,14,950,42,32,T.Action)
	C.button(self.characterPage,"Back","닫기",1014,16,108,38,function() self:open(self.returnPage or "Menu") end)
	self.characterButtons={}
	for i,id in Catalog.Order do
		self.characterButtons[id]=C.button(self.characterPage,id,id,22,82+(i-1)*86,240,64,function() self:selectPreview(id) end,T.Themes[id])
	end
	self.preview=Preview.new(self.characterPage,285,82,310,315,"SWORD")
	self.portrait=C.new("ImageLabel",self.characterPage,{Name="PortraitArt",Position=UDim2.fromOffset(285,82),Size=UDim2.fromOffset(310,315),BackgroundTransparency=1,Visible=false,ScaleType=Enum.ScaleType.Fit})
	self.characterInfo=C.text(self.characterPage,"Info","",285,408,310,154,18)
	local detail=C.scroll(self.characterPage,"Details",624,82,497,466)
	self.skillLabels={}
	for i,key in {"LMB","RMB","1","2","3","F"} do
		self.skillLabels[i]=C.text(detail,"Skill"..i,"",10,(i-1)*63,465,58,17)
	end
	self.passiveInfo=C.text(detail,"Passive","",10,383,465,105,17,T.Health)
	self.selectButton=C.button(self.characterPage,"Select","다음 리스폰에 선택",626,553,493,52,function() self:requestSelection() end)
	self.selectionStatus=C.text(self.characterPage,"SelectionStatus","",285,562,310,58,15,T.Muted)
	self.help=C.panel(canvas,"HowToPlay",225,65,830,590)
	C.text(self.help,"Title","HOW TO PLAY",25,16,650,45,32,T.Action)
	C.button(self.help,"Close","닫기",688,18,110,38,function() self:open(self.returnPage or "Menu") end)
	self.helpText=C.text(self.help,"Controls","",28,90,775,455,21)
	self.settings=Settings.new(settings,function(binds)
		onBindings(binds); self.hud:setBindings(binds); self:refreshHelp(binds)
	end,function(open)
		if open then
			if self.state.page~="Settings" then self.settingsReturn=self.state.page end
			self.state.page="Settings"
		elseif self.state.page=="Settings" then self.state.page=self.settingsReturn or "Menu" end
		self:updateVisibility()
	end,canvas,self.state.preferences,function(key,value) self:applyPreference(key,value) end)
	self:refreshHelp(settings.binds)
	self.death=C.panel(canvas,"Death",390,215,500,275)
	C.text(self.death,"Title","KNOCKED OUT!",22,14,456,45,34,T.Danger)
	self.deathInfo=C.text(self.death,"Info","처치자 · 공격 정보: 서버 연동 대기",22,64,456,68,18)
	self.countdown=C.text(self.death,"Countdown","",22,137,456,38,26,T.Action)
	C.button(self.death,"ChangeCharacter","다음 캐릭터 변경",22,201,456,48,function() self.returnPage="Battle"; self:open("Characters") end)
	self.board=Board.new(canvas)
	self.results=C.new("Frame",canvas,{Name="Results",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false})
	self.resultBoard=Board.new(self.results)
	self.resultBoard.title.Text="MATCH RESULTS"
	self.resultNext=C.text(self.results,"NextMatch","다음 경기 · 서버 안내 대기",300,664,680,35,20,T.Action)
	self.resultNext.TextXAlignment=Enum.TextXAlignment.Center
	self.connection=C.panel(canvas,"Connection",400,68,480,44,T.Danger)
	self.connectionText=C.text(self.connection,"Text","서버 연결 중…",10,3,460,38,18,T.Outline)
	self.connectionText.TextXAlignment=Enum.TextXAlignment.Center
	self:selectPreview("SWORD")
	table.insert(self.connections,bounds:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:resize() end))
	table.insert(self.connections,Players.PlayerRemoving:Connect(function(p)
		self.state:removePlayer(p.UserId); self.board:setRows(self.state.rows)
	end))
	pcall(function() self.previousPlayerList=StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList); StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,false) end)
	for _,name in {"RoBattlesSFX","RoBattlesMusic"} do
		local group=SoundService:FindFirstChild(name)
		if not group then group=C.new("SoundGroup",SoundService,{Name=name}) end
	end
	self:applyPreference("sfx",self.state.preferences.sfx); self:applyPreference("music",self.state.preferences.music)
	self:resize(); self:updateVisibility(); return self
end
function App:resize()
	local size=self.bounds.AbsoluteSize
	self.scale.Scale=State.fit(size.X,size.Y,self.state.preferences.scale)
end
function App:applyPreference(key,value)
	if key=="shake" and not value then self.hud.shakeUntil=nil
	elseif key=="damageNumbers" and not value then self.hud.damageUntil=nil
	elseif key=="scale" then self:resize()
	elseif key=="sfx" or key=="music" then
		local group=SoundService:FindFirstChild(key=="sfx" and "RoBattlesSFX" or "RoBattlesMusic")
		if group then group.Volume=value end
	end
end
function App:refreshHelp(b)
	self.helpText.Text="WASD  이동    /    Space  점프\n\n"..b.Primary.."  기본 공격    /    "..b.Secondary.."  보조 공격\n"..b.Skill1.." · "..b.Skill2.." · "..b.Skill3.."  일반 스킬\n"..b.Ultimate.."  궁극기    /    "..b.Reload.."  장전\n"..b.Dodge.."  회피    /    "..b.RunToggle.."  달리기 토글\n"..b.CameraToggle.."  시점 전환    /    "..b.FreeLook.."  자유 시점 회전\n"..b.Scoreboard.."  스코어보드 (누르고 있기)\n\nF9  메뉴    /    F10  설정\n캐릭터를 처음 고르면 서버가 스폰하고, 사망 중·경기 중 변경은 다음 리스폰부터 적용됩니다.\n경기는 2명 이상 준비되면 카운트다운 후 시작합니다.\n메뉴는 경기를 일시정지하지 않습니다."
end
function App:open(page)
	if page=="Characters" or page=="Help" then
		if self.state.page~="Characters" and self.state.page~="Help" then self.returnPage=self.state.page end
	end
	if page=="Settings" then self.settingsReturn=self.state.page end
	self.state.page=page
	self.settings.root.Visible=page=="Settings"; self.settings.waiting=nil
	self:updateVisibility()
end
function App:toggleMenu()
	self:open(self.state.page=="Menu" and "Battle" or "Menu")
end
function App:isBlocking()
	return self.state.page~="Battle" or self.state:status(workspace:GetServerTimeNow())~="Alive"
end
-- RESULTS must be seen even if a menu/settings/character page is open when the round ends: close it (remembering where the
-- player was) and show the results. When the results phase ends, return to the remembered page if the player did not navigate.
function App:syncResultsPage(status)
	local entering=status=="Results" and self.prevStatus~="Results"
	self.prevStatus=status
	if status=="Results" then
		if entering and self.state.page~="Battle" and not self.pageBeforeResults then
			self.pageBeforeResults=self.state.page
			self.settings.root.Visible=false; self.settings.waiting=nil
			self.state.page="Battle"
			self.autoClosedForResults=true
		end
	elseif self.pageBeforeResults then
		local back=self.pageBeforeResults
		self.pageBeforeResults=nil
		if self.autoClosedForResults and self.state.page=="Battle" and status~="Menu" then
			self.state.page=back
			self.settings.root.Visible=back=="Settings"
		end
		self.autoClosedForResults=false
	end
end
function App:updateVisibility()
	local now=workspace:GetServerTimeNow()
	local status=self.state:status(now)
	self:syncResultsPage(status)
	local page=self.state.page
	self.menu.Visible=page=="Menu"
	self.characterPage.Visible=page=="Characters"
	self.help.Visible=page=="Help"
	self.settings.root.Visible=page=="Settings"
	self.hud.root.Visible=page=="Battle" and status~="Results"
	self.hud.cross.Visible=page=="Battle" and status=="Alive"
	self.death.Visible=page=="Battle" and status=="Dead"
	self.results.Visible=page=="Battle" and status=="Results"
	self.resultBoard:setVisible(self.results.Visible)
	self.menuButton.Visible=page=="Battle" and status~="Results"
	self.connection.Visible=page=="Battle" and (status=="Stale" or status=="Connecting" or status=="Menu" or status=="Spawning")
	if status=="Stale" then self.connectionText.Text="서버 응답 지연 · 상태 갱신 대기"
	elseif status=="Menu" then self.connectionText.Text="캐릭터를 선택하세요 (MENU → CHARACTERS)"
	elseif status=="Spawning" then
		local st=self.state:spawnStatus()
		self.connectionText.Text=st=="Failed" and "스폰 실패 · 캐릭터를 다시 선택해 재시도" or st=="Hung" and "스폰 지연 · 서버 재시도 중" or "캐릭터를 불러오는 중…"
	else self.connectionText.Text="서버 연결 중…" end
	local blocking=self:isBlocking()
	if blocking~=self.lastBlocking then
		self.lastBlocking=blocking
		if blocking then
			self.board:setVisible(false)
			ContextActionService:BindActionAtPriority("RoBattlesUIModal",function() return Enum.ContextActionResult.Sink end,false,3000,Enum.KeyCode.Space,Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D)
		else ContextActionService:UnbindAction("RoBattlesUIModal") end
		if self.callbacks.blocking then self.callbacks.blocking(blocking) end
	end
end
function App:setCallbacks(callbacks)
	self.callbacks=callbacks; self.lastBlocking=nil; self:updateVisibility()
end
function App:selectPreview(id)
	self.selected=id; self.preview:setCharacter(id)
	local portrait=T.Assets.Portraits[id]
	self.portrait.Image=portrait or ""; self.portrait.Visible=portrait~=nil and portrait~=""
	self.preview.root.Visible=not self.portrait.Visible
	local item=Catalog.Items[id]
	local matchPlayer=self.state.match and self.state.match.player
	local full=matchPlayer~=nil and matchPlayer.characterSelectionAllowed==false
	local allowed=Characters[id]~=nil and RemoteSpec.validate("SelectCharacter",{characterId=id})==true and not full
	self.selectable=allowed
	local first=matchPlayer==nil or matchPlayer.selected~=true
	self.characterInfo.Text=id.."\n"..item.tag.."\nHP "..(Characters[id] and tostring(Characters[id].maxHealth) or "—").."\n"..(full and "경기 정원이 가득 찼습니다" or allowed and (first and "선택하면 서버가 스폰합니다" or "다음 리스폰부터 적용") or "현재 서버에서 선택 불가")
	for i,l in self.skillLabels do l.Text=({"[LMB] ","[RMB] ","[1] ","[2] ","[3] ","[F] "})[i]..item.skills[i] end
	self.passiveInfo.Text="PASSIVE\n"..item.passive
	self.selectButton.Text=allowed and (first and "이 캐릭터로 시작" or "다음 리스폰에 선택") or (full and "정원 초과" or "선택 불가")
	self.selectButton.BackgroundColor3=allowed and T.Action or T.Secondary
	self.selectButton.TextColor3=allowed and T.Outline or T.Muted
	for cid,b in self.characterButtons do b.Text=(cid==id and "▶ " or "")..cid end
end
function App:requestSelection()
	if not self.selectable or not self.callbacks.select then return end
	local now=workspace:GetServerTimeNow()
	local status=self.state:status(now)
	if status=="Connecting" or status=="Stale" then self.state.selectionMessage="서버 연결을 기다려주세요"; return end
	if self.state:request(self.selected,now) then self.callbacks.select(self.selected) end
end
function App:awaitSnapshot()
	self.state.snap=nil; self.state.receivedAt=nil; self.state.combo=nil; self.state.duelist=nil
	self.hud:clearTransient(); self:updateVisibility()
end
function App:setSnapshot(snap,now)
	local old=self.state.snap
	local oldStatus=old and self.state:status(now)
	local oldKey=self.selectionKey
	if not self.state:snapshot(snap,now) then return false end
	if old and (old.characterId~=snap.characterId or old.alive~=snap.alive) then self.hud:clearTransient() end
	-- Refresh the character page when the server's selection/capacity state changes (first pick, match full).
	local mp=self.state.match and self.state.match.player
	self.selectionKey=mp and (tostring(mp.selected)..tostring(mp.characterSelectionAllowed)) or ""
	if self.selectionKey~=oldKey then self:selectPreview(self.selected) end
	-- First server-confirmed selection from the menu: leave the picker and show the battle view.
	if oldStatus=="Menu" and self.state:status(now)~="Menu" and self.state.page=="Characters" and self.returnPage=="Battle" then self:open("Battle") end
	self:updateVisibility(); return true
end
function App:setRows(rows)
	self.state:setRows(rows); self.board:setRows(self.state.rows)
end
function App:onFeedback(event,now)
	self.state:feedback(event,now)
	if event.type=="Died" and event.playerId==Players.LocalPlayer.UserId or event.type=="Respawned" and event.playerId==Players.LocalPlayer.UserId then self.hud:clearTransient() end
	if event.type=="Damaged" then
		if event.attackerId==Players.LocalPlayer.UserId and self.state.preferences.damageNumbers then self.hud:showDamage(event.amount,now) end
		if event.targetId==Players.LocalPlayer.UserId and self.state.preferences.shake then self.hud:shake(now) end
	end
	self:updateVisibility()
end
function App:render(model,now)
	self.state:tick(now)
	if model and self.state.snap then
		model.alive=self.state:status(now)=="Alive"
		if model.ammo and self.state.snap.ammo then model.ammo.empty=self.state.snap.ammo.cur<=0 end
		-- Optional per-skill readyAt extension; no local cooldown estimation.
		for i,s in model.skills do
			local raw=self.state.snap.skills and self.state.snap.skills[i]
			if s.implemented and raw and type(raw.readyAt)=="number" then s.remaining=math.max(0,raw.readyAt-now) end
		end
		self.hud:render(model,now)
	end
	local rank,kills=self.state:myScore()
	local match=self.state.match
	local phase=match and match.phase
	local function mmss(n) n=math.max(0,math.ceil(n)); return string.format("%02d:%02d",math.floor(n/60),n%60) end
	local playerCount=match and match.participantCount or #Players:GetPlayers()
	if phase=="WAITING" then
		self.hud.top.Text=string.format("대기 중   준비 %d / 최소 %d명   정원 %d",playerCount,Config.Match.MinPlayers,match.maxPlayers or Config.Match.MaxPlayers)
	elseif phase=="COUNTDOWN" then
		self.hud.top.Text=string.format("경기 시작 %d   준비 %d명",math.max(0,math.ceil((match.countdownEndsAt or now)-now)),playerCount)
	else
		local time=match and type(match.endsAt)=="number" and mmss(match.endsAt-now) or "—"
		self.hud.top.Text="TIME "..time.."   RANK "..(rank or "—").."   KO "..(kills or "—").."   PLAYERS "..playerCount
		if match and type(match.lowPopulationEndsAt)=="number" then
			self.hud.top.Text..="   인원 부족 "..math.max(0,math.ceil(match.lowPopulationEndsAt-now)).."s"
		end
	end
	self.hud.passive.Text=self.state:characterLines(model)
	local function nameOf(id) local p=Players:GetPlayerByUserId(id); return p and p.DisplayName or ("Player "..tostring(id)) end
	local feed={}
	for i=#self.state.feed,1,-1 do
		local f=self.state.feed[i]
		table.insert(feed,f.attackerId and (nameOf(f.attackerId).."  ▶  "..nameOf(f.id)) or (nameOf(f.id).."  ·  OUT"))
	end
	self.hud.feed.Text=table.concat(feed,"\n")
	self.countdown.Text=self.state:respawnText(now)
	local damage=self.state.lastDamage
	local killer=self.state.killer
	self.deathInfo.Text="처치자: "..(killer and nameOf(killer.attackerId) or "환경 / 정보 없음").."\n"..(damage and ("최근 피격: "..tostring(damage.amount).." · "..tostring(damage.kind or "공격 정보 없음")) or "공격 정보 없음")
	self.selectionStatus.Text=(self.state.snap and self.state.snap.pendingCharacterId and ("예약: "..self.state.snap.pendingCharacterId.."\n") or "")..(self.state.selectionMessage or "다음 리스폰에 적용")
	if self.state.snap and self.state.snap.pendingCharacterId then
		self.countdown.Text..="\nNEXT · "..self.state.snap.pendingCharacterId
	end
	if phase=="RESULTS" then
		if self.lastResults~=match.results or match.results==nil then self.resultBoard:setRows(type(match.results)=="table" and match.results or {}); self.lastResults=match.results end
		local nextAt=match.resultsEndsAt or match.nextStartsAt
		self.resultNext.Text=(match.cancelled and "인원 부족으로 종료 · " or "")..(type(nextAt)=="number" and ("다음 경기까지 "..math.max(0,math.ceil(nextAt-now)).."초") or "다음 경기 · 서버 안내 대기")
	end
	self:updateVisibility()
end
function App:destroy()
	ContextActionService:UnbindAction("RoBattlesUIModal")
	for _,c in self.connections do c:Disconnect() end
	if self.previousPlayerList~=nil then pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,self.previousPlayerList) end) end
	self.gui:Destroy()
end
return App
