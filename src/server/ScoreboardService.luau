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

function ScoreboardService:has(id) return self._rows[id] ~= nil end

function ScoreboardService:reset() self._rows = {} end

function ScoreboardService:setConnected(id, connected, name)
	local r = self._rows[id]
	if r then r.connected = connected; if name then r.name = name end end
end

-- KO descending / deaths ascending. Name/id only stabilize display; they do not break rank ties.
function ScoreboardService:snapshot()
	local list = {}
	for _, r in self._rows do
		table.insert(list, { id = r.id, name = r.name, kills = r.kills, deaths = r.deaths, connected = r.connected ~= false })
	end
	table.sort(list, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		if a.deaths ~= b.deaths then
			return a.deaths < b.deaths
		end
		if tostring(a.name) ~= tostring(b.name) then return tostring(a.name) < tostring(b.name) end
		return tostring(a.id) < tostring(b.id)
	end)
	local rank = 0
	for i, r in list do
		local prev = list[i - 1]
		if not prev or r.kills ~= prev.kills or r.deaths ~= prev.deaths then rank = i end
		r.rank = rank -- competition ranking: 1, 1, 3
	end
	return list
end

return ScoreboardService
