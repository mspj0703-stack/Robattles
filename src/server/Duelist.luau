--!nonstrict
-- SWORD 패시브 Duelist (순수 로직, CLI 테스트 가능).
-- 확정: 동일 대상 3회 연속 유효 적중 시 세 번째 공격 +8 피해, 대상별 카운터, 전역 재발동 제한 4초.
-- 임시(ASSUMPTION A66): "연속" = 같은 대상에게 windowSeconds 안에 이어진 유효 적중(다른 대상 적중은 카운터를 끊지 않음),
--   재발동 제한 중의 적중은 카운트하지 않음, 발동 후 그 대상 카운터 0, 공격자 사망/부활 시 전체 초기화, 대상 사망/퇴장 시 해당 대상 카운터 제거.
-- 유효 적중 = DamageService 가 실제로 피해를 적용한 경우(차단·보호·회피 무적·중복 방지 거부는 제외).
local Duelist = {}
Duelist.__index = Duelist

function Duelist.new(def)
	return setmetatable({
		_def = def, -- { consecutiveHits, bonusDamage, lockSeconds, windowSeconds }
		_s = {}, -- [attackerId] = { counts = { [targetId] = { n, last } }, lockUntil }
	}, Duelist)
end

function Duelist:_state(attackerId)
	local s = self._s[attackerId]
	if not s then
		s = { counts = {}, lockUntil = 0 }
		self._s[attackerId] = s
	end
	return s
end

function Duelist:isLocked(attackerId, now)
	local s = self._s[attackerId]
	return s ~= nil and now < s.lockUntil
end

function Duelist:lockRemaining(attackerId, now)
	local s = self._s[attackerId]
	return s and math.max(0, s.lockUntil - now) or 0
end

function Duelist:count(attackerId, targetId, now)
	local s = self._s[attackerId]
	local c = s and s.counts[targetId]
	if not c or now - c.last > self._def.windowSeconds then
		return 0
	end
	return c.n
end

-- 이번 공격이 발동 대상인가: 지금 적중하면 (카운터+1)이 연속 횟수에 도달하고 재발동 제한 중이 아니면 보너스 피해.
function Duelist:bonusFor(attackerId, targetId, now)
	if self:isLocked(attackerId, now) then
		return 0
	end
	if self:count(attackerId, targetId, now) + 1 >= self._def.consecutiveHits then
		return self._def.bonusDamage
	end
	return 0
end

-- 피해가 실제로 적용된 뒤 호출. bonusApplied 이면 발동 처리(제한 시작, 해당 대상 카운터 0). 반환: 발동했는가.
function Duelist:onValidHit(attackerId, targetId, now, bonusApplied)
	local s = self:_state(attackerId)
	if bonusApplied then
		s.lockUntil = now + self._def.lockSeconds
		s.counts[targetId] = nil
		return true
	end
	if now < s.lockUntil then
		return false -- 재발동 제한 중 적중은 카운트하지 않음
	end
	local c = s.counts[targetId]
	if not c or now - c.last > self._def.windowSeconds then
		c = { n = 0, last = now }
		s.counts[targetId] = c
	end
	c.n += 1
	c.last = now
	return false
end

function Duelist:clearTarget(targetId)
	for _, s in self._s do
		s.counts[targetId] = nil
	end
end

function Duelist:clearAttacker(attackerId)
	self._s[attackerId] = nil
end

return Duelist
