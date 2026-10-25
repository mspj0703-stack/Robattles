--!nonstrict
-- 스코어보드 집계(킬/데스). 서버 권위. 환경 사망은 데스만 오르고 킬은 오르지 않는다.
local ScoreboardService = {}
ScoreboardService.__index = ScoreboardService

function ScoreboardService.new()
	return setmetatable({ _rows = {} }, ScoreboardService)
end

function ScoreboardService:register(id, name)
	self._rows[id] = { id = id, name = name, kills = 0, deaths = 0 }
end

function ScoreboardService:remove(id)
	self._rows[id] = nil
end

-- DamageService.onKilled 이벤트 연결용
function ScoreboardService:onKill(attackerId, targetId)
	local t = self._rows[targetId]
	if t then
		t.deaths += 1
	end
	local a = self._rows[attackerId]
	if a and attackerId ~= targetId then
		a.kills += 1
	end
end

-- 킬 많은 순 → 데스 적은 순 → 이름 순
function ScoreboardService:snapshot()
	local list = {}
	for _, r in self._rows do
		table.insert(list, { id = r.id, name = r.name, kills = r.kills, deaths = r.deaths })
	end
	table.sort(list, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		if a.deaths ~= b.deaths then
			return a.deaths < b.deaths
		end
		return tostring(a.name) < tostring(b.name)
	end)
	return list
end

return ScoreboardService
