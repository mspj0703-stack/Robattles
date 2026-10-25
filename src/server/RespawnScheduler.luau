--!nonstrict
-- 부활 대기·캐릭터 로드 스케줄러 (순수 로직, CLI 테스트 가능).
-- 사망 후 Match.RespawnSeconds(4초) 뒤 로드 대상이 된다. 중복 사망 통지는 무시하고, 로드 실패는 상한까지만 재시도하며,
-- 창(LoadWindowSeconds) 안의 로드 횟수를 제한해 무한 리스폰을 막는다.
--
-- 로드 경쟁 상태 방지 (LoadCharacterAsync 는 yield 함수이고 타임아웃이 와도 실행 중인 호출은 취소되지 않는다):
--  1) 호출 단위 시도 ID(attemptId, 스케줄러 전역 고유): due() 가 로드 대상을 돌려줄 때 새 ID 를 발급하고 inFlight=true 로 표시한다.
--     호출한 쪽은 호출이 반환(성공/오류)하면 반드시 finishCall(id, attemptId, ok, now) 를 부른다.
--  2) 겹침 금지: inFlight 인 동안에는 타임아웃이 지나도 새 로드를 시작하지 않는다. 타임아웃 플래그만 초기화해서 겹치지 않게 한다.
--     (실행 중인 호출이 남아 있는 한 inFlight 는 finishCall 로만 풀린다.)
--  3) 오래된 완료 무시: attemptId 가 현재 시도와 다르거나 플레이어가 퇴장(remove)·재입장했다면 finishCall 은 아무 상태도 바꾸지 않는다.
--  4) 무한 대기 방지: 호출이 LoadHangSeconds 넘게 반환하지 않으면 "hung" 으로 기록하고 재시도를 중단한다(호출은 취소하지 않는다 — 엔진이 나중에
--     캐릭터를 만들면 onSpawned 로 정상 복구된다).
local Link = require(script.Parent.Link)

local RespawnScheduler = {}
RespawnScheduler.__index = RespawnScheduler

function RespawnScheduler.new(deps)
	deps = deps or {}
	return setmetatable({
		_cfg = deps.config or Link.shared("Config"),
		_s = {}, -- [id] = { dueAt, loading, inFlight, attemptId, attempts, loads = { t... }, ... }
		_nextAttempt = 0,
		onLog = deps.onLog,
	}, RespawnScheduler)
end

function RespawnScheduler:_log(kind, id, detail)
	if self.onLog then
		self.onLog(kind, id, detail)
	end
end

function RespawnScheduler:register(id)
	if not self._s[id] then
		self._s[id] = { dueAt = nil, loading = false, inFlight = false, attemptId = nil, attempts = 0, loads = {} }
	end
end

function RespawnScheduler:remove(id)
	self._s[id] = nil
end

-- 사망 통지. 이미 대기/로드 중이면 false(중복 무시).
function RespawnScheduler:onDeath(id, now)
	self:register(id)
	local s = self._s[id]
	if s.dueAt ~= nil or s.loading or s.hung then
		return false
	end
	s.dueAt = now + self._cfg.Match.RespawnSeconds
	s.attempts = 0
	return true
end

function RespawnScheduler:getDueAt(id)
	local s = self._s[id]
	return s and s.dueAt or nil
end

function RespawnScheduler:getAttempt(id)
	local s = self._s[id]
	return s and s.attemptId or nil
end

function RespawnScheduler:isHung(id)
	local s = self._s[id]
	return s ~= nil and s.hung == true
end

function RespawnScheduler:isInFlight(id)
	local s = self._s[id]
	return s ~= nil and s.inFlight
end

-- 첫 입장 등 즉시 로드가 필요한 플레이어(대기 없이 due 목록에 오른다).
function RespawnScheduler:requestInitial(id, now)
	self:register(id)
	local s = self._s[id]
	if s.dueAt == nil and not s.loading and not s.hung then
		s.dueAt = now
	end
end

-- 로드 실패 처리(재시도 예약 또는 포기). 내부용.
function RespawnScheduler:_fail(s, id, now)
	s.loading = false
	s.inFlight = false
	s.returnedAt = nil
	s.attempts += 1
	if s.attempts >= self._cfg.Match.MaxLoadAttempts then
		s.dueAt = nil
		self:_log("respawn_gave_up", id, { attempts = s.attempts })
		return false
	end
	s.dueAt = now + 1
	return true
end

-- 지금 로드해야 할 플레이어 목록. 반환된 플레이어는 loading+inFlight 상태가 되며 새 attemptId 를 받는다(getAttempt).
-- 호출자는 호출이 끝나면 finishCall 을, 캐릭터가 추가되면 onSpawned 를 불러야 한다.
function RespawnScheduler:due(now)
	local out = {}
	local c = self._cfg.Match
	for id, s in self._s do
		if s.inFlight then
			-- 아직 실행 중인 호출: 절대 새로 시작하지 않는다. 느리면 한 번 기록, 너무 오래면 중단.
			local age = now - s.inFlightSince
			if age >= c.LoadTimeoutSeconds and not s.slowLogged then
				s.slowLogged = true
				self:_log("respawn_load_slow", id, { attemptId = s.attemptId, seconds = age })
			end
			if age >= c.LoadHangSeconds and not s.hung then
				s.hung = true
				s.dueAt = nil
				self:_log("respawn_load_hung", id, { attemptId = s.attemptId, seconds = age })
			end
		elseif s.loading then
			-- 호출은 반환했지만 CharacterAdded 가 아직 없다: 타임아웃이면 실패 처리
			if s.returnedAt ~= nil and now - s.returnedAt >= c.LoadTimeoutSeconds then
				self:_log("respawn_load_timeout", id, { attemptId = s.attemptId })
				self:_fail(s, id, now)
			end
		end
	end
	for id, s in self._s do
		if s.dueAt ~= nil and not s.loading and not s.inFlight and now >= s.dueAt then
			local recent = {}
			for _, t in s.loads do
				if now - t < c.LoadWindowSeconds then
					table.insert(recent, t)
				end
			end
			s.loads = recent
			if #recent >= c.MaxLoadsPerWindow then
				s.dueAt = now + c.RespawnSeconds -- 로드 과다: 한 번 더 늦춘다
				self:_log("respawn_throttled", id, { loads = #recent })
			else
				self._nextAttempt += 1
				s.attemptId = self._nextAttempt
				s.loading, s.inFlight, s.slowLogged = true, true, false
				s.inFlightSince = now
				s.returnedAt = nil
				table.insert(s.loads, now)
				table.insert(out, id)
			end
		end
	end
	table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
	return out
end

-- 로드 호출이 반환했다(오류면 ok=false). 오래된 attemptId·퇴장한 플레이어는 무시한다. 반환: 이 완료가 현재 시도에 해당했는가.
function RespawnScheduler:finishCall(id, attemptId, ok, now)
	local s = self._s[id]
	if not s or s.attemptId ~= attemptId or not s.inFlight then
		return false
	end
	s.inFlight = false
	if ok then
		s.returnedAt = now -- 아직 loading: CharacterAdded 를 기다린다(타임아웃은 due 가 처리). 이미 onSpawned 가 처리됐다면 loading=false
	else
		self:_fail(s, id, now)
	end
	return true
end

-- 하위 호환: 호출 오류 통지(현재 시도 기준). 새 코드는 finishCall 을 쓴다.
function RespawnScheduler:onLoadFailed(id, now)
	local s = self._s[id]
	if not s then
		return false
	end
	return self:_fail(s, id, now)
end

-- 캐릭터가 실제로 추가됐다. 반환: 로드/대기를 기다리고 있었는가(예상된 스폰). 어떤 경우에도 대기 상태를 정리한다
-- (늦게 도착한 오래된 로드의 캐릭터도 "캐릭터가 존재한다"는 사실이므로 재시도 예약을 취소한다).
function RespawnScheduler:onSpawned(id)
	local s = self._s[id]
	if not s then
		return false
	end
	local expected = s.loading or s.dueAt ~= nil or s.hung == true
	s.dueAt, s.loading, s.attempts, s.returnedAt, s.hung = nil, false, 0, nil, nil
	-- inFlight 는 풀지 않는다: 호출이 아직 실행 중이면 finishCall 이 풀 때까지 새 호출을 막는다.
	return expected
end

return RespawnScheduler
