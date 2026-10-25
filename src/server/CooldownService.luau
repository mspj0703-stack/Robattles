--!nonstrict
-- 쿨타임 + 요청 빈도 제한. 시간은 항상 호출자가 now(초)로 전달한다(서버 시계, 테스트 결정성).
local Link = require(script.Parent.Link)

local CooldownService = {}
CooldownService.__index = CooldownService

function CooldownService.new(config)
	return setmetatable({
		_cfg = config or Link.shared("Config"),
		_ready = {}, -- [entityId][key] = readyAt
		_requests = {}, -- [entityId][name] = { timestamps }
	}, CooldownService)
end

function CooldownService:start(id, key, duration, now)
	local e = self._ready[id]
	if not e then
		e = {}
		self._ready[id] = e
	end
	e[key] = now + duration
end

function CooldownService:remaining(id, key, now)
	local e = self._ready[id]
	local readyAt = e and e[key]
	if not readyAt or now >= readyAt - 1e-6 then -- 부동소수 오차 허용
		return 0
	end
	return readyAt - now
end

-- 준비되는 서버 시각(HUD 스냅샷용). 기록이 없으면 nil.
function CooldownService:readyAt(id, key)
	local e = self._ready[id]
	return e and e[key]
end

function CooldownService:isReady(id, key, now)
	return self:remaining(id, key, now) == 0
end

-- 준비됐으면 쿨타임을 시작하고 true. 아니면 false, "on_cooldown".
function CooldownService:tryUse(id, key, duration, now)
	if type(duration) ~= "number" or duration ~= duration or duration < 0 then
		return false, "bad_duration"
	end
	if not self:isReady(id, key, now) then
		return false, "on_cooldown"
	end
	self:start(id, key, duration, now)
	return true, nil
end

function CooldownService:reduce(id, key, amount, now)
	local e = self._ready[id]
	if e and e[key] and amount > 0 then
		e[key] = math.max(now, e[key] - amount)
	end
end

function CooldownService:clearEntity(id)
	self._ready[id] = nil
	self._requests[id] = nil
end

-- 1초 슬라이딩 윈도우 요청 제한. 허용이면 true.
function CooldownService:allowRequest(id, name, now)
	local byName = self._requests[id]
	if not byName then
		byName = {}
		self._requests[id] = byName
	end
	local list = byName[name]
	if not list then
		list = {}
		byName[name] = list
	end
	local cutoff = now - 1
	local i = 1
	while list[i] ~= nil and list[i] <= cutoff do
		i += 1
	end
	if i > 1 then
		local kept = {}
		for j = i, #list do
			table.insert(kept, list[j])
		end
		list = kept
		byName[name] = list
	end
	if #list >= self._cfg.Net.MaxRequestsPerSecond then
		return false
	end
	table.insert(list, now)
	return true
end

return CooldownService
