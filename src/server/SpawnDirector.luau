--!nonstrict
-- 전투 쪽 스폰 선택(순수 로직, CLI 테스트 가능). 맵의 SpawnRegistry/SpawnRisk 를 주입받아 사용한다(맵 모듈에 직접 의존하지 않음).
-- 규칙: 활성 스폰만 / 생존 적 근처 제외(대안이 없으면 완화) / 최근 사용·타 플레이어 예약 감점 / 위험도 최저(또는 하위 N 중 무작위).
-- 항상 스폰 위치를 돌려주는 것이 목표다: 후보가 모두 위험해도 가장 덜 위험한 곳을 쓴다(fallback=true).
--
-- deps: {
--   config?, risk = SpawnRisk 모듈({ pick }), getSpawns() -> 정규화된 스폰 목록,
--   getEnemies(playerId) -> [{ pos, alive }], los? = function(a,b)->boolean, rng? = function(lo,hi), onLog?
-- }
local Link = require(script.Parent.Link)

local SpawnDirector = {}
SpawnDirector.__index = SpawnDirector

function SpawnDirector.new(deps)
	return setmetatable({
		_cfg = deps.config or Link.shared("Config"),
		_risk = deps.risk,
		_getSpawns = deps.getSpawns,
		_getEnemies = deps.getEnemies,
		_los = deps.los,
		_rng = deps.rng,
		_onLog = deps.onLog,
		_history = {}, -- [playerId] = { id, ... } 최신순
		_reserved = {}, -- [spawnId] = { by, untilT }
	}, SpawnDirector)
end

function SpawnDirector:removePlayer(id)
	self._history[id] = nil
	for sid, r in self._reserved do
		if r.by == id then
			self._reserved[sid] = nil
		end
	end
end

local function flatDist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- 반환: result | nil, reason. result = { id, spawn, position, facing, yawDeg, fallback, risk }
function SpawnDirector:choose(playerId, now)
	local sp = self._cfg.Spawn
	local all = self._getSpawns() or {}
	local active = {}
	for _, s in all do
		if s.enabled then
			table.insert(active, s)
		end
	end
	if #active == 0 then
		return nil, "no_spawns"
	end
	local enemies = self._getEnemies(playerId) or {}

	-- 예약 만료 정리
	for sid, r in self._reserved do
		if now >= r.untilT then
			self._reserved[sid] = nil
		end
	end

	local safe = {}
	for _, s in active do
		local ok = true
		for _, e in enemies do
			if e.alive ~= false and flatDist(s.pos, e.pos) < sp.MinEnemyDistance and math.abs(s.pos.Y - (e.pos.Y or s.pos.Y)) < 8 then
				ok = false
				break
			end
		end
		local r = self._reserved[s.id]
		if ok and r and r.by ~= playerId then
			ok = false
		end
		if ok then
			table.insert(safe, s)
		end
	end
	local fallback = #safe == 0
	local candidates = fallback and active or safe

	local recent = {}
	for _, sid in self._history[playerId] or {} do
		recent[sid] = true
	end
	local pick = self._risk.pick(candidates, enemies, {
		recent = recent, los = self._los,
		topN = sp.TopN, rng = self._rng,
	})
	if not pick then
		return nil, "no_pick"
	end
	local s = pick.spawn
	local hist = self._history[playerId] or {}
	table.insert(hist, 1, s.id)
	while #hist > sp.RecentCount do
		table.remove(hist)
	end
	self._history[playerId] = hist
	self._reserved[s.id] = { by = playerId, untilT = now + sp.ReserveSeconds }
	if fallback and self._onLog then
		self._onLog("spawn_fallback", playerId, { id = s.id })
	end
	return {
		id = s.id, spawn = s,
		position = { X = s.pos.X, Y = s.pos.Y + sp.HrpOffset, Z = s.pos.Z },
		facing = s.facing, yawDeg = s.yawDeg, fallback = fallback, risk = pick.risk,
	}
end

-- 이미 선택한 스폰 위치에 캐릭터가 도착했는지 확인(중복 이동 방지). 도착했으면 false, 벗어났으면 true.
-- current/target: { X, Y, Z } (HRP 위치), tolerance 스터드.
function SpawnDirector.needsCorrection(current, target, tolerance)
	local dx, dy, dz = current.X - target.X, current.Y - target.Y, current.Z - target.Z
	return math.sqrt(dx * dx + dz * dz) > tolerance or math.abs(dy) > tolerance
end

return SpawnDirector
