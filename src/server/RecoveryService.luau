--!nonstrict
-- Alpha 1.0: +20 HP on confirmed KO (one award per 1.5s), regen 6 HP/s after 6s
-- without attack/damage activity. Environmental KO attribution is limited to recent damage.
local RecoveryService = {}
RecoveryService.__index = RecoveryService
function RecoveryService.new(damage)
	return setmetatable({damage=damage,players={},lastHit={}},RecoveryService)
end
function RecoveryService:reset()
	table.clear(self.players)
	table.clear(self.lastHit)
end
function RecoveryService:remove(id)
	self.players[id]=nil
	self.lastHit[id]=nil
	for victim, hit in self.lastHit do if hit.attacker==id then self.lastHit[victim]=nil end end
end
function RecoveryService:spawn(id, now)
	self.players[id]={activity=now,regenAt=now,lastTick=now,lastKoAward=nil}
	self.lastHit[id]=nil
end
function RecoveryService:activity(id, now)
	local p=self.players[id]
	if p then p.activity=now;p.regenAt=now;p.lastTick=now end
end
function RecoveryService:damaged(e)
	self:activity(e.targetId,e.now)
	if e.attackerId~=e.targetId then
		self:activity(e.attackerId,e.now)
		if e.dealt>0 then self.lastHit[e.targetId]={attacker=e.attackerId,time=e.now} end
	end
end
function RecoveryService:recentAttacker(victim, now)
	local hit=self.lastHit[victim]
	if hit and hit.attacker~=victim and now-hit.time>=0 and now-hit.time<=5 then return hit.attacker end
	return nil
end
function RecoveryService:confirmedKo(e)
	if e.attackerId==e.targetId or not self.damage:isAlive(e.attackerId) then return 0 end
	local p=self.players[e.attackerId]
	if not p or (p.lastKoAward and e.now-p.lastKoAward<1.5) then return 0 end
	p.lastKoAward=e.now
	return self.damage:heal(e.attackerId,20)
end
function RecoveryService:tick(now,active)
	if not active then
		-- Do not backfill health earned during downtime if the caller resumes without resetting.
		for _,p in self.players do p.lastTick=now end
		return
	end
	for id,p in self.players do
		if self.damage:isAlive(id) then
			local from=math.max(p.lastTick, p.activity+6)
			if now>from then self.damage:heal(id,(now-from)*6) end
		end
		p.lastTick=now
	end
end
return RecoveryService
