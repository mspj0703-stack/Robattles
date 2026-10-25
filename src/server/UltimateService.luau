--!nonstrict
-- 궁극기 게이지(0~100). 피해·처치·시간 경과로 충전, F키로 발동, 자발적 취소 불가.
-- 게이지 규칙(확정): 사망해도 유지 / 같은 캐릭터로 부활하면 유지 / 캐릭터 변경은 다음 리스폰부터 적용되며
--   min(기존 게이지, CharacterSwitchCarryMax) 이월 / 정상 사용 시 100% 소모 / 새 경기 시작 시 초기화.
-- 사망/외부 강제 중단 시 "캐릭터에 연결된" 지속 효과(attach)만 종료한다.
-- 이미 발사된 투사체·설치물은 이 서비스가 추적하지 않으므로 수명 동안 유지된다.
local Link = require(script.Parent.Link)

local UltimateService = {}
UltimateService.__index = UltimateService

function UltimateService.new(config)
	return setmetatable({ _cfg = config or Link.shared("Config"), _s = {} }, UltimateService)
end

function UltimateService:setGainPolicy(policy) self._gainPolicy = policy end
function UltimateService:setPracticePolicy(policy) self._practicePolicy = policy end

function UltimateService:register(id, characterId)
	self._s[id] = { gauge = 0, alive = true, active = nil, characterId = characterId, pendingCharacterId = nil }
end

-- 캐릭터 선택. 이미 캐릭터가 있으면 다음 리스폰부터 적용(대기). 반환: "set" | "pending" | "unchanged"
function UltimateService:setCharacter(id, characterId)
	local s = self._s[id]
	if not s then
		return "unchanged"
	end
	if s.characterId == nil then
		s.characterId = characterId
		return "set"
	end
	if characterId == s.characterId then
		s.pendingCharacterId = nil
		return "unchanged"
	end
	s.pendingCharacterId = characterId
	return "pending"
end

function UltimateService:getCharacter(id)
	local s = self._s[id]
	return s and s.characterId
end

function UltimateService:getPendingCharacter(id)
	local s = self._s[id]
	return s and s.pendingCharacterId
end

function UltimateService:remove(id)
	self:forceEnd(id, "External")
	self._s[id] = nil
end

-- 부활. 같은 캐릭터면 게이지 유지, 대기 중인 캐릭터 변경이 있으면 min(게이지, 이월 상한)으로 이월.
function UltimateService:respawn(id)
	local s = self._s[id]
	if not s then
		return
	end
	s.alive, s.active = true, nil
	local pending = s.pendingCharacterId
	if pending ~= nil and pending ~= s.characterId then
		s.gauge = math.min(s.gauge, self._cfg.Ultimate.CharacterSwitchCarryMax)
		s.characterId = pending
	end
	s.pendingCharacterId = nil
end

-- 새 경기 시작: 게이지 초기화, 진행 중 궁극기 종료, 대기 캐릭터 변경은 이월 없이 적용.
function UltimateService:resetMatch(isReady)
	for id, s in self._s do
		self:forceEnd(id, "MatchReset")
		s.gauge, s.alive = 0, true
		if s.pendingCharacterId ~= nil and (isReady == nil or isReady(id)) then
			s.characterId = s.pendingCharacterId
			s.pendingCharacterId = nil
		end
	end
end

function UltimateService:getGauge(id)
	local s = self._s[id]
	return s and s.gauge or 0
end

function UltimateService:isActive(id)
	local s = self._s[id]
	return s ~= nil and s.active ~= nil
end

function UltimateService:_gain(id, amount)
	if self._gainPolicy and not self._gainPolicy(id) then return end
	local s = self._s[id]
	if not s or not s.alive or s.active ~= nil or amount ~= amount or amount <= 0 then
		return -- 사망·발동 중에는 충전 없음 (ASSUMPTION A17)
	end
	s.gauge = math.min(self._cfg.Ultimate.Max, s.gauge + amount)
end

function UltimateService:addDamage(id, dealt)
	self:_gain(id, dealt * self._cfg.Ultimate.GainPerDamage)
end

function UltimateService:addKill(id)
	self:_gain(id, self._cfg.Ultimate.GainPerKill)
end

-- 시간 경과 충전. 서버 루프에서 dt(초)마다 호출.
function UltimateService:tick(dt)
	local per = self._cfg.Ultimate.GainPerSecond * dt
	for id in self._s do
		self:_gain(id, per)
	end
end

-- opts: { canAct: boolean? }  def: { duration: number, onEnd: ((reason: string) -> ())? }
function UltimateService:activate(id, now, def, opts)
	local s = self._s[id]
	if not s then
		return false, "not_registered"
	end
	if not s.alive then
		return false, "dead"
	end
	if s.active then
		return false, "already_active"
	end
	if opts and opts.canAct == false then
		return false, "cannot_act"
	end
	local practice = self._practicePolicy and self._practicePolicy(id) == true
	if not practice and s.gauge < self._cfg.Ultimate.Max then
		return false, "not_ready"
	end
	if type(def) ~= "table" or type(def.duration) ~= "number" or def.duration ~= def.duration or def.duration <= 0 then
		return false, "bad_def"
	end
	if not practice then s.gauge = math.max(0, s.gauge - self._cfg.Ultimate.Max) end -- practice never changes gauge
	s.active = { endsAt = now + def.duration, onEnd = def.onEnd, attached = {} }
	return true, nil
end

-- 발동 중 캐릭터에 연결된 지속 효과(빔 등). 종료 시 stopFn()이 호출된다.
function UltimateService:attach(id, stopFn)
	local s = self._s[id]
	if not s or not s.active then
		return false
	end
	table.insert(s.active.attached, stopFn)
	return true
end

-- 사용자 요청 취소: 항상 거부 (확정 규칙).
function UltimateService:requestCancel(id)
	if not self._cfg.Ultimate.CancelableByUser then
		return false, "not_cancelable"
	end
	return self:forceEnd(id, "Canceled"), nil
end

-- 사망/외부 사유 강제 종료. 연결된 지속 효과만 멈춘다.
function UltimateService:forceEnd(id, reason)
	local s = self._s[id]
	if not s or not s.active then
		return false
	end
	local a = s.active
	s.active = nil
	self._cleanupErrors = self._cleanupErrors or {}
	for _, stop in a.attached do
		local ok, err = pcall(stop)
		if not ok then table.insert(self._cleanupErrors, tostring(err)) end
	end
	if a.onEnd then
		local ok, err = pcall(a.onEnd, reason)
		if not ok then table.insert(self._cleanupErrors, tostring(err)) end
	end
	return true
end

function UltimateService:handleDeath(id)
	local s = self._s[id]
	if not s then
		return
	end
	self:forceEnd(id, "Death")
	s.alive = false -- 게이지는 유지한다(확정)
end

-- 지속 시간이 지난 궁극기를 정상 종료
function UltimateService:update(now)
	for id, s in self._s do
		if s.active and now >= s.active.endsAt then
			self:forceEnd(id, "Completed")
		end
	end
end

return UltimateService
