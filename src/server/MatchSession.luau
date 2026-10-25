--!nonstrict
-- Orchestrates existing combat/respawn services. Map placement is an injected callback.
local MatchFlow=require(script.Parent.MatchFlow)
local MatchScope=require(script.Parent.MatchScope)
local MatchSession={};MatchSession.__index=MatchSession
function MatchSession.new(deps)
	local self=setmetatable({core=deps.core,controller=deps.controller,projectiles=deps.projectiles,scheduler=deps.scheduler,
		scope=MatchScope.new(),onBoundary=deps.onBoundary,onKill=deps.onKill,onTransition=deps.onTransition},MatchSession)
	self.flow=MatchFlow.new({config=deps.config,onTransition=function(...) self:_transition(...) end})
	self.core.damage:setPolicy(function(req,now) return self.flow:canDamage(req.attackerId,req.targetId,now) end)
	self.core.ultimate:setGainPolicy(function(id) return self.flow:canGain(id) end)
	self.core.ultimate:setPracticePolicy(function(id)
		local p=self.flow.players[id]
		return (self.flow.phase=="WAITING" or self.flow.phase=="COUNTDOWN") and p~=nil and p.selected and p.ready and p.alive
	end)
	self.controller:onFeedback(function(e)
		if e.type=="Died" then
			if self.flow:death(e.playerId,e.time) then self.scheduler:onDeath(e.playerId,e.time) end
		end
	end)
	local function scored(e)
		if self.flow:recordKill(e) and self.onKill then self.onKill(e,self.flow.matchId) end
	end
	-- Credit lethal confirmed damage before the Roblox Humanoid mirror can emit Died.
	self.core.damage:onDamaged(function(e) if e.killed then scored(e) end end)
	self.core.damage:onKilled(scored) -- also covers environmental deaths; recordKill deduplicates

	return self
end
function MatchSession:register(id,name)
	if self.flow.players[id] then return false end
	self.flow:register(id,name);self.scope:join(id);self.scheduler:register(id)
	return true
end
function MatchSession:select(id,characterId,now)
	self:updatePhase(now)
	if not self.controller:isCharacterSupported(characterId) then return false,"unsupported_character" end
	local ok,why=self.flow:select(id,characterId,now)
	if not ok then return false,why end
	local result=self.controller:selectCharacter(id,characterId)
	if self.flow.phase~="RESULTS" then self.scheduler:retryExhausted(id,now) end
	if why=="first_selection" and self.flow.phase~="RESULTS" then
		self.scheduler:resume(id);self.scheduler:requestInitial(id,now)
	end
	return true,result
end
function MatchSession:remove(id,now)
	self:updatePhase(now)
	self.flow:remove(id,now) -- remove damage authority before any cancellation callback
	self.scope:leave(id)
	self.core.ultimate:forceEnd(id,"PlayerLeft")
	self.projectiles:cancelOwner(id,now)
	self.scheduler:remove(id)
end
function MatchSession:_transition(previous,phase,now,reason)
	self.scope:invalidate()
	for id in self.flow.players do
		self.scheduler:cancel(id)
		self.controller:clearMatchTransient(id)
	end
	-- Force-end callbacks may have created effects: cancel all AFTER they run.
	self.projectiles:clearAll(now)
	self.controller:clearMatchObjects(now) -- 던진 폭탄·볼·Bullseye 탄·충전 상태(5캐릭터 지연 작업)
	if phase=="ACTIVE" then
		self.controller:beginMatch(now,function(id)
			local p=self.flow.players[id];return p~=nil and p.selected and p.ready and p.alive
		end)
	end
	if phase~="RESULTS" then for id in self.flow.players do self.scheduler:resume(id) end end
	if self.onBoundary then self.onBoundary(previous,phase,now,reason) end
	if self.onTransition then self.onTransition(previous,phase,now,reason) end
end
function MatchSession:updatePhase(now) self.flow:update(now) end
function MatchSession:tick(now)
	self:updatePhase(now)
	if self.flow.phase=="RESULTS" then return end
	for id,p in self.flow.players do
		if p.selected and not p.ready and not self.scheduler:isLoading(id) and not self.scheduler:isExhausted(id) and (not p.respawnAt or now>=p.respawnAt) then
			self.scheduler:resume(id);self.scheduler:requestInitial(id,now)
		end
	end
end
function MatchSession:due(now)
	if self.flow.phase=="RESULTS" then return {} end
	return self.scheduler:due(now)
end
function MatchSession:captureLoad(id)
	return {scope=self.scope:capture(id),id=id,attempt=self.scheduler:getAttempt(id)}
end
function MatchSession:validLoad(ticket)
	if not ticket or ticket.accepted or not self.scope:valid(ticket.scope) or self.flow.phase=="RESULTS" then return false end
	local p=self.flow.players[ticket.id]
	return p~=nil and p.selected and ticket.attempt==self.scheduler:getAttempt(ticket.id)
end
function MatchSession:discardLoad(ticket)
	if ticket and ticket.attempt==self.scheduler:getAttempt(ticket.id) then self.scheduler:cancel(ticket.id) end
end
function MatchSession:spawned(id,ticket,now)
	self:updatePhase(now)
	if not self:validLoad(ticket) then return false end
	self.scheduler:onSpawned(id)
	self.controller:respawn(id,now)
	self.flow:spawned(id,now)
	ticket.accepted=true
	return true
end
function MatchSession:environmentDeath(id,now)
	self:updatePhase(now)
	if self.core.damage:forceKill(id,now) then return true end
	local p=self.flow.players[id]
	if p and p.selected and p.alive then
		-- Practice fall/reset: restore physical character without damage/KO/death score or charge.
		self.core.ultimate:handleDeath(id)
		self.core.status:clear(id)
		self.controller:handleDeath(id,now)
		return true
	end
	return false
end
function MatchSession:augmentSnapshot(id,snap,now)
	local data=self.flow:snapshot(id,now);local p=self.flow.players[id]
	data.player.respawnPaused=self.flow.phase=="RESULTS"
	data.player.spawnStatus=self.scheduler:isHung(id) and "Hung" or self.scheduler:isExhausted(id) and "Failed" or self.scheduler:isLoading(id) and "Loading" or p and p.ready and "Ready" or p and p.selected and "Pending" or "Menu"
	snap.match=data
	snap.alive=p~=nil and p.ready and p.alive and snap.alive
	snap.canAct=snap.canAct and snap.alive and self.flow.phase~="RESULTS" and p.selected
	-- Compatibility envelope for the already delivered UI. Canonical phases remain uppercase in snap.match.
	snap.ui=snap.ui or {};snap.ui.version=1
	snap.ui.match={phase=data.phase=="RESULTS" and "Results" or "Playing",endsAt=data.endsAt,
		results=data.results,resultsEndsAt=data.resultsEndsAt,state=data.phase,matchId=data.matchId,
		countdownEndsAt=data.countdownEndsAt,cancelled=data.cancelled}
	return snap
end
return MatchSession
