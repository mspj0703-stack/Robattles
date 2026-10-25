--!nonstrict
-- Pure presentation state; no damage, cooldown, rank or respawn decisions.
local State = {}
State.__index = State
function State.new(myId, respawnSeconds)
	return setmetatable({myId=myId,respawnSeconds=respawnSeconds,page="Menu",rows={},feed={},lastTime=-math.huge,
		lastLifeTime=-math.huge,preferences={sensitivity=1,scale=1,sfx=1,music=0.6,damageNumbers=true,shake=true}},State)
end
function State:snapshot(snap, receivedAt)
	if type(snap)~="table" or type(snap.t)~="number" or snap.t<self.lastTime or snap.t<self.lastLifeTime then return false end
	local changed = self.snap and (self.snap.characterId~=snap.characterId or self.snap.alive~=snap.alive)
	if changed then
		self.combo=nil; self.duelist=nil
		if snap.alive or self.snap.characterId~=snap.characterId then self.lastDamage=nil end
	end
	if snap.alive then self.deathAt=nil; self.killer=nil; self.lastAliveTime=snap.t end
	self.snap=snap; self.lastTime=snap.t; self.receivedAt=receivedAt
	if self.requested and snap.t>=self.requestAt and (snap.pendingCharacterId==self.requested or (snap.characterId==self.requested and snap.pendingCharacterId==nil)) then
		self.selectionMessage=snap.pendingCharacterId and "예약 완료 · 다음 리스폰에 적용" or "서버 적용 완료"
		self.requested=nil
	end
	-- Canonical server match data is snap.match (MatchSession:augmentSnapshot). The older snap.ui.match envelope is a fallback.
	local ui=snap.ui
	local m=type(snap.match)=="table" and snap.match or (type(ui)=="table" and ui.version==1 and ui.match or nil)
	if type(m)=="table" and m.phase=="Results" then m=setmetatable({phase="RESULTS"},{__index=m}) end -- legacy spelling
	self.match=m
	return true
end
function State:request(id, now)
	if self.requested then return false end
	self.requested=id; self.requestAt=now; self.selectionMessage="서버 확인 중…"
	return true
end
function State:tick(now)
	if self.requested and now-self.requestAt>=5 then
		self.requested=nil; self.selectionMessage="응답 지연 · 현재 예약 확인 후 다시 선택"
	end
	while self.feed[1] and now-self.feed[1].receivedAt>8 do table.remove(self.feed,1) end
end
function State:feedback(e, now)
	if type(e)~="table" then return end
	if e.type=="Rejected" and e.remote=="SelectCharacter" and self.requested then
		self.requested=nil; self.selectionMessage="서버가 선택을 거부했습니다"
	elseif e.type=="KillConfirmed" then
		-- Server-confirmed kill credit. Upgrade the matching "Died" line (same victim, same moment) instead of duplicating it.
		if type(e.targetId)~="number" or type(e.attackerId)~="number" then return end
		local entry
		for _,f in self.feed do
			if f.id==e.targetId and not f.attackerId and math.abs(f.receivedAt-now)<1 then entry=f break end
		end
		if entry then entry.attackerId=e.attackerId else
			table.insert(self.feed,{id=e.targetId,attackerId=e.attackerId,time=e.time,receivedAt=now})
			if #self.feed>5 then table.remove(self.feed,1) end
		end
		if e.targetId==self.myId then self.killer={attackerId=e.attackerId,kind=e.kind,receivedAt=now} end
		if e.attackerId==self.myId then self.lastKillAt=now end
	elseif e.type=="Died" then
		if type(e.time)~="number" then return end
		local dup=false
		for _,f in self.feed do
			if f.id==e.playerId and (f.time==e.time or math.abs(f.receivedAt-now)<1) then dup=true break end
		end
		if not dup then
			table.insert(self.feed,{id=e.playerId,time=e.time,receivedAt=now})
			if #self.feed>5 then table.remove(self.feed,1) end
		end
		if e.playerId==self.myId and e.time>self.lastLifeTime and e.time>=(self.lastAliveTime or -math.huge) then
			self.lastLifeTime=e.time; self.deathAt=e.time; self.combo=nil; self.duelist=nil
			-- Died carries no killer. The killer comes only from a server KillConfirmed; never infer it from the last hit.
			if self.killer and now-self.killer.receivedAt>1 then self.killer=nil end
		end
	elseif e.type=="Respawned" and e.playerId==self.myId and type(e.time)=="number" and e.time>self.lastLifeTime and e.time>=self.lastTime then
		self.lastLifeTime=e.time; self.deathAt=nil; self.lastDamage=nil; self.combo=nil; self.duelist=nil
	elseif e.type=="Damaged" and e.targetId==self.myId then
		self.lastDamage={attackerId=e.attackerId,amount=e.amount,kind=e.kind,receivedAt=now}
	elseif e.type=="Swing" and e.playerId==self.myId and type(e.time)=="number" and e.time>=self.lastLifeTime and self.snap and self.snap.alive and not self.deathAt then
		self.combo=e.swingIndex and {value=e.swingIndex,at=e.time} or nil
	elseif e.type=="DuelistProc" and e.playerId==self.myId and type(e.time)=="number" and e.time>=self.lastLifeTime and self.snap and self.snap.alive and not self.deathAt then
		self.duelist={bonus=e.bonus,at=e.time}
	end
end
function State:setRows(rows)
	if type(rows)~="table" then return end
	self.rows={}
	for _,r in ipairs(rows) do
		if type(r)=="table" and type(r.id)=="number" and type(r.kills)=="number" and type(r.deaths)=="number" then
			-- rank / connected come from the server (ties share a rank). Never recompute ranking here.
			table.insert(self.rows,{id=r.id,name=tostring(r.name),kills=r.kills,deaths=r.deaths,rank=type(r.rank)=="number" and r.rank or nil,connected=r.connected~=false})
		end
	end
end
function State:removePlayer(id)
	for i=#self.rows,1,-1 do if self.rows[i].id==id then table.remove(self.rows,i) end end
end
function State:phase()
	local m=self.match
	return m and m.phase or nil
end
-- Connecting / Stale / Results / Menu (no character chosen) / Spawning (chosen, not yet in the arena) / Dead / Alive.
-- "Menu" is deliberately distinct from "Dead": a player who has not picked a character has no avatar and is not knocked out.
function State:status(now)
	if not self.snap then return "Connecting" end
	if self.receivedAt and now-self.receivedAt>3 then return "Stale" end
	local m=self.match
	if m and m.phase=="RESULTS" then return "Results" end
	local p=m and m.player
	if p then
		if p.state=="Menu" then return "Menu" end
		if p.state=="Dead" then return "Dead" end
		if self.snap.alive and not self.deathAt then return "Alive" end
		return self.deathAt and "Dead" or "Spawning"
	end
	if self.deathAt or not self.snap.alive then return "Dead" end
	return "Alive"
end
function State:spawnStatus()
	local p=self.match and self.match.player
	return p and p.spawnStatus or nil
end
function State:respawnText(now)
	local p=self.match and self.match.player
	local at=p and p.respawnAt or (self.deathAt and self.deathAt+self.respawnSeconds) or nil
	if not at then return "서버 부활 정보 대기" end
	local remaining=math.ceil(at-now)
	if remaining>0 then return tostring(remaining).."초 후 부활" end
	local st=self:spawnStatus()
	if st=="Failed" then return "캐릭터 로드 실패 · 캐릭터를 다시 선택하면 재시도합니다" end
	if st=="Hung" then return "캐릭터 로드 지연 · 서버 재시도 대기" end
	return "서버가 캐릭터를 불러오는 중…"
end
-- rank and kills come from the server row (shared ranks on ties). Falls back to the match.player copy.
function State:myScore()
	local p=self.match and self.match.player
	for _,r in self.rows do if r.id==self.myId then return r.rank or (p and p.rank),r.kills end end
	if p and p.rank then return p.rank,p.kills end
	return nil,nil
end
-- One compact status line per character, built from the HudModel the combat HUD already computes (server snapshot only).
function State:characterLines(model)
	if not model then return "서버 상태 대기" end
	local parts={}
	if model.combo then table.insert(parts,model.combo.text) end
	if model.passive then table.insert(parts,model.passive.text) end
	if model.ammo and model.ammo.reloading then table.insert(parts,"재장전 중") end
	return #parts>0 and table.concat(parts,"  ·  ") or "—"
end
function State.fit(width,height,preferred)
	return math.min(math.clamp(preferred or 1,0.75,1.25),math.max(1,width-24)/1280,math.max(1,height-24)/720)
end
return State
