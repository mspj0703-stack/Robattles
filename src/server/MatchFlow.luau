--!nonstrict
-- Map/Roblox-independent authoritative FFA state machine. No UI or skill code.
local Link = require(script.Parent.Link)
local Scoreboard = require(script.Parent.ScoreboardService)
local MatchFlow = {}; MatchFlow.__index = MatchFlow
local function copyRows(rows)
	local out={}; for _,r in rows do table.insert(out,table.clone(r)) end; return out
end
function MatchFlow.new(deps)
	deps=deps or {}
	return setmetatable({_cfg=(deps.config or Link.shared("Config")).Match,phase="WAITING",matchId=0,epoch=0,
		players={},scoreboard=Scoreboard.new(),results={},_nextConnection=0,onTransition=deps.onTransition},MatchFlow)
end
function MatchFlow:register(id,name)
	if self.players[id] then return self.players[id].connection end
	self._nextConnection+=1
	self.players[id]={id=id,name=tostring(name),connection=self._nextConnection,selected=false,ready=false,alive=false,participating=false}
	return self._nextConnection
end
function MatchFlow:selectedCount()
	local n=0; for _,p in self.players do if p.selected then n+=1 end end; return n
end
function MatchFlow:readyCount()
	local n=0; for _,p in self.players do if p.selected and p.ready and p.alive then n+=1 end end; return n
end
function MatchFlow:participantCount()
	local n=0; for _,p in self.players do if p.participating then n+=1 end end; return n
end
function MatchFlow:select(id,characterId,now)
	local p=self.players[id]; if not p then return false,"not_registered" end
	if not p.selected and self:selectedCount()>=self._cfg.MaxPlayers then return false,"match_full" end
	local first=not p.selected
	p.selected=true; p.selectedCharacterId=characterId
	return true,first and "first_selection" or "selected"
end
function MatchFlow:_join(p)
	p.participating=true
	if not self.scoreboard:has(p.id) then self.scoreboard:register(p.id,p.name) end
	self.scoreboard:setConnected(p.id,true,p.name)
end
function MatchFlow:spawned(id,now)
	local p=self.players[id]; if not p or not p.selected then return false end
	p.ready=true; p.alive=true; p.respawnAt=nil
	if self.phase=="ACTIVE" then self:_join(p);self:_population(now) end
	return true
end
function MatchFlow:death(id,now)
	local p=self.players[id]; if not p or not p.selected or not p.alive then return false end
	p.alive=false; p.ready=false; p.respawnAt=now+self._cfg.RespawnSeconds
	return true
end
function MatchFlow:remove(id,now)
	local p=self.players[id]; if not p then return end
	self.players[id]=nil
	self.scoreboard:setConnected(id,false)
	if self.phase=="ACTIVE" then self:_population(now) end
end
function MatchFlow:_population(now)
	if self:participantCount()<self._cfg.MinPlayers then
		if not self.lowPopulationEndsAt then self.lowPopulationEndsAt=now+self._cfg.LowPopulationGraceSeconds end
	else self.lowPopulationEndsAt=nil end
end
function MatchFlow:_transition(phase,now,reason)
	local previous=self.phase
	self.phase=phase;self.phaseStartedAt=now;self.epoch+=1;self.reason=reason
	self.endsAt=nil;self.countdownEndsAt=nil;self.resultsEndsAt=nil;self.lowPopulationEndsAt=nil
	if phase=="COUNTDOWN" then self.countdownEndsAt=now+self._cfg.CountdownSeconds
	elseif phase=="ACTIVE" then
		self.matchId+=1;self.endsAt=now+self._cfg.DurationSeconds;self.scoreboard:reset();self.results={}
		for _,p in self.players do p.participating=false;if p.selected and p.ready and p.alive then self:_join(p) end end
	elseif phase=="RESULTS" then
		self.results=copyRows(self.scoreboard:snapshot());self.resultsEndsAt=now+self._cfg.ResultsSeconds
	elseif phase=="WAITING" then
		self.results={};self.scoreboard:reset()
		for _,p in self.players do p.participating=false end
	end
	if self.onTransition then self.onTransition(previous,phase,now,reason) end
end
function MatchFlow:update(now)
	if self.phase=="WAITING" then
		if self:readyCount()>=self._cfg.MinPlayers then self:_transition("COUNTDOWN",now,"enough_players") end
	elseif self.phase=="COUNTDOWN" then
		if self:readyCount()<self._cfg.MinPlayers then self:_transition("WAITING",now,"countdown_cancelled")
		elseif now>=self.countdownEndsAt then self:_transition("ACTIVE",now,"countdown_complete") end
	elseif self.phase=="ACTIVE" then
		self:_population(now)
		-- Earliest deadline wins even after a long Heartbeat stall. Equality favors round completion.
		if now>=self.endsAt and (not self.lowPopulationEndsAt or self.endsAt<=self.lowPopulationEndsAt) then self:_transition("RESULTS",now,"time_limit")
		elseif self.lowPopulationEndsAt and now>=self.lowPopulationEndsAt then self:_transition("WAITING",now,"insufficient_players") end
	elseif self.phase=="RESULTS" and now>=self.resultsEndsAt then
		self:_transition("WAITING",now,"results_complete")
		if self:readyCount()>=self._cfg.MinPlayers then self:_transition("COUNTDOWN",now,"enough_players") end
	end
end
function MatchFlow:canDamage(attackerId,targetId,now)
	if self.phase~="ACTIVE" or now>=self.endsAt or (self.lowPopulationEndsAt and now>=self.lowPopulationEndsAt) then return false end
	local a,t=self.players[attackerId],self.players[targetId]
	-- Already-fired projectiles can still credit a dead owner in this round, as before.
	return a~=nil and a.participating and t~=nil and t.participating and t.alive and t.ready
end
function MatchFlow:canGain(id)
	local p=self.players[id]
	return self.phase=="ACTIVE" and p~=nil and p.participating and p.alive and p.ready
end
function MatchFlow:canAct(id,remote,payload)
	local p=self.players[id];if not p then return false,"not_registered" end
	if remote=="SelectCharacter" then return true end
	if remote=="SetRun" and payload.enabled==false then return true end
	if not p.selected then return false,"selection_required" end
	if self.phase=="RESULTS" then return false,"match_results" end
	if not p.ready or not p.alive then return false,"not_spawned" end
	if self.phase=="ACTIVE" and not p.participating then return false,"not_participating" end
	return true
end
function MatchFlow:recordKill(e)
	local a,t=self.players[e.attackerId],self.players[e.targetId]
	if self.phase~="ACTIVE" or e.now>=self.endsAt or (self.lowPopulationEndsAt and e.now>=self.lowPopulationEndsAt) or not a or not a.participating or not t or not t.participating or t.lastScoredAt==e.now then return false end
	t.lastScoredAt=e.now
	self.scoreboard:onKill(e.attackerId,e.targetId);return true
end
function MatchFlow:standings()
	if self.phase=="RESULTS" then return copyRows(self.results) end
	if self.phase=="ACTIVE" then return self.scoreboard:snapshot() end
	local board=Scoreboard.new()
	for id,p in self.players do if p.selected then board:register(id,p.name) end end
	return board:snapshot()
end
function MatchFlow:snapshot(id,now)
	local p=self.players[id];local rows=self:standings();local personal
	for _,r in rows do if r.id==id then personal=table.clone(r);break end end
	local playerState="Menu"
	if p and p.selected then
		playerState=p.respawnAt and "Dead" or (p.participating and self.phase=="ACTIVE") and "Participating" or "Selected"
	end
	return {version=1,phase=self.phase,matchId=self.matchId,epoch=self.epoch,serverTime=now,
		endsAt=self.endsAt,countdownEndsAt=self.countdownEndsAt,resultsEndsAt=self.resultsEndsAt,
		lowPopulationEndsAt=self.lowPopulationEndsAt,reason=self.reason,cancelled=self.phase=="WAITING" and self.reason=="insufficient_players",
		remainingSeconds=self.endsAt and math.max(0,self.endsAt-now) or nil,
		countdown=self.countdownEndsAt and math.max(0,math.ceil(self.countdownEndsAt-now)) or nil,
		participantCount=(self.phase=="ACTIVE" or self.phase=="RESULTS") and self:participantCount() or self:readyCount(),selectedCount=self:selectedCount(),maxPlayers=self._cfg.MaxPlayers,
		standings=rows,results=self.phase=="RESULTS" and copyRows(self.results) or nil,
		player={state=playerState,selected=p~=nil and p.selected,participating=p~=nil and p.participating and self.phase=="ACTIVE",
			characterSelectionAllowed=p~=nil and (p.selected or self:selectedCount()<self._cfg.MaxPlayers),
			respawnAt=p and p.respawnAt,respawnRemaining=p and p.respawnAt and math.max(0,p.respawnAt-now) or nil,
			kills=personal and personal.kills or 0,deaths=personal and personal.deaths or 0,rank=personal and personal.rank or nil},
	}
end
return MatchFlow
