--!nonstrict
-- 서버 권위 이동·회피 검증 (순수 로직, CLI 테스트 가능). A41 후속.
--
-- Roblox 플레이어 캐릭터는 클라이언트가 물리 소유권을 가지므로 서버는 이동을 "막을 수" 없고,
-- 복제된 위치를 표본으로 관찰해 허용 범위를 벗어나면 마지막 유효 위치로 되돌린다(correction).
-- 일반 이동을 과차단하지 않도록 ① 속도 허용 배율 ② 지연 여유 ③ 초과 이동 누적(leaky bucket) ④ 순간이동만 즉시 보정 을 쓴다.
--
-- deps: { config?, world? = { cast(p0,p1,radius) } }  (world 없으면 벽/지면 검사 생략)
local Link = require(script.Parent.Link)
local Vec = Link.shared("Vec")

local MovementValidator = {}
MovementValidator.__index = MovementValidator

function MovementValidator.new(deps)
	deps = deps or {}
	return setmetatable({
		_cfg = deps.config or Link.shared("Config"),
		_world = deps.world,
		_s = {},
		onLog = deps.onLog, -- 선택: function(kind, playerId, detail)
	}, MovementValidator)
end

function MovementValidator:_log(kind, id, detail)
	if self.onLog then
		self.onLog(kind, id, detail)
	end
end

function MovementValidator:register(id, pos, now)
	self._s[id] = {
		last = pos, t = now, excess = 0, bucket = math.huge, upBucket = math.huge, permits = {}, lastIssued = {}, airDodges = 0, airborne = false,
		corrections = {}, stats = { corrections = 0, soft = 0, wall = 0, teleport = 0, speed = 0, up = 0 },
	}
end

function MovementValidator:remove(id)
	self._s[id] = nil
end

-- 서버가 직접 옮긴 경우(리스폰·보정 후 등): 기준점을 새로 잡는다. 초과 이동 누적/회피/충격은 초기화.
function MovementValidator:teleported(id, pos, now)
	local s = self._s[id]
	if not s then
		return self:register(id, pos, now)
	end
	s.last, s.t, s.excess, s.permits, s.airDodges, s.airborne = pos, now, 0, {}, 0, false
	s.bucket, s.upBucket = math.huge, math.huge
end

function MovementValidator:getLastValid(id)
	local s = self._s[id]
	return s and s.last or nil
end

function MovementValidator:getStats(id)
	local s = self._s[id]
	return s and s.stats or nil
end

-- 이동 허가(permit) 발급. **서버 코드만 호출한다**(RemoteEvent 경로 없음 — 클라이언트는 허가를 요청할 수 없다).
-- kind 는 Config.MoveCheck.Permits 에 정의된 종류여야 하고, params 는 종류별 상한을 넘을 수 없다.
-- params: { speed = 수평 속도, up = 상승 속도(선택), duration = 유효 시간, dir = 방향(directional 종류는 필수) }
-- 반환: ok, reason  (unknown_kind | no_state | bad_params | exceeds_cap | rate_limited | too_many_permits)
function MovementValidator:issue(id, kind, now, params)
	local s = self._s[id]
	if not s then
		return false, "no_state"
	end
	local mc = self._cfg.MoveCheck
	local def = type(kind) == "string" and mc.Permits[kind] or nil
	if not def then
		return false, "unknown_kind"
	end
	if type(params) ~= "table" then
		return false, "bad_params"
	end
	local function num(v, default)
		if v == nil then
			return default
		end
		if type(v) ~= "number" or v ~= v or v == math.huge or v < 0 then
			return nil
		end
		return v
	end
	local speed, up, duration = num(params.speed, 0), num(params.up, 0), num(params.duration, nil)
	if speed == nil or up == nil or duration == nil or duration <= 0 then
		return false, "bad_params"
	end
	if speed > def.maxSpeed or up > def.maxUp or duration > def.maxDuration then
		return false, "exceeds_cap"
	end
	local dir
	if def.directional then
		dir = type(params.dir) == "table" and Vec.flatten(params.dir) or nil
		if not dir then
			return false, "bad_params"
		end
	end
	local last = s.lastIssued[kind]
	if last ~= nil and now - last < def.minInterval then
		return false, "rate_limited"
	end
	-- 만료된 허가 정리 후 개수 상한 확인
	local live = {}
	for _, p in s.permits do
		if now <= p.untilT then
			table.insert(live, p)
		end
	end
	s.permits = live
	if #live >= mc.MaxActivePermits then
		return false, "too_many_permits"
	end
	s.lastIssued[kind] = now
	local total = duration + mc.ImpulseGrace
	table.insert(s.permits, {
		kind = kind, untilT = now + total + mc.LatencySlackSeconds,
		remaining = speed * total, upRemaining = up * total, dir = dir,
	})
	return true, nil
end

function MovementValidator:getPermitCount(id, now)
	local s = self._s[id]
	local n = 0
	for _, p in (s and s.permits or {}) do
		if now <= p.untilT then
			n += 1
		end
	end
	return n
end

-- 서버 기준 체공 판정: 클라이언트가 보고한 airborne 이거나 발 아래 지면이 없으면 공중.
function MovementValidator:isAirborne(pos, claimedAirborne)
	if claimedAirborne then
		return true
	end
	local world = self._world
	if not world then
		return false
	end
	local hit = world.cast(pos, { X = pos.X, Y = pos.Y - self._cfg.MoveCheck.GroundProbe, Z = pos.Z }, 0)
	return hit == nil
end

-- 회피 사전 확인(충전 소비 전에 호출). 반환 ok, reason
function MovementValidator:canDodge(id, pos, claimedAirborne, now)
	local s = self._s[id]
	if not s then
		return false, "no_movement_state"
	end
	local cfg = self._cfg
	if self:isAirborne(pos, claimedAirborne) then
		if not cfg.Dodge.AllowAirborne then
			return false, "airborne_disabled"
		end
		if s.airDodges >= cfg.MoveCheck.MaxAirDodges then
			return false, "air_dodge_limit"
		end
	end
	return true, nil
end

-- 회피 계획: 방향을 수평 단위 벡터로 정규화하고, 벽에 막히면 거리를 줄인다. 반환 plan | nil, reason
function MovementValidator:planDodge(id, pos, direction, claimedAirborne, now)
	local s = self._s[id]
	if not s then
		return nil, "no_movement_state"
	end
	local cfg = self._cfg
	local mc, d = cfg.MoveCheck, cfg.Dodge
	local dir = type(direction) == "table" and Vec.flatten(direction) or nil
	if not dir then
		return nil, "bad_direction"
	end
	local airborne = self:isAirborne(pos, claimedAirborne)
	local distance = d.Distance
	local blocked = false
	if self._world then
		local hit = self._world.cast(pos, Vec.add(pos, Vec.scale(dir, d.Distance)), mc.BodyRadius)
		if hit then
			distance = math.max(0, hit.fraction * d.Distance - mc.WallSkin)
			blocked = true
		end
	end
	if airborne then
		s.airDodges += 1
	end
	-- 일반 회피도 같은 허가 구조를 쓴다(충전은 DodgeService 가 관리하므로 발급 간격 제한 없음). 방향 성분만 인정.
	table.insert(s.permits, {
		kind = "Dodge", untilT = now + d.Duration + mc.DodgeWindowGrace + mc.LatencySlackSeconds,
		remaining = distance * mc.DodgeTolerance, upRemaining = 0, dir = dir,
	})
	return { direction = dir, distance = distance, duration = d.Duration, blocked = blocked, airborne = airborne }
end

local function flatDist(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- 위치 표본 관찰. 반환 { status = "ok"|"soft"|"correct", reason?, correctTo?, moved, allowed }
function MovementValidator:observe(id, pos, now, state)
	local s = self._s[id]
	if not s then
		return { status = "ok", moved = 0, allowed = 0 }
	end
	local cfg = self._cfg
	local mc = cfg.MoveCheck
	state = state or {}
	local dt = now - s.t
	if dt <= 0 then
		return { status = "ok", moved = 0, allowed = 0 }
	end
	local cdt = math.min(dt, mc.MaxSampleDt)
	local prev = s.last

	-- 착지하면 공중 회피 횟수 복구
	local airborne = self:isAirborne(pos, state.airborne)
	if not airborne then
		s.airDodges = 0
	end
	s.airborne = airborne

	-- 허용량은 "토큰 버킷"이다: 기본 속도로 쌓이는 허용 이동량 + 지연 여유(버킷 상한). 한 번에 몰아서 도착해도(지연) 버킷 안이면 허용되지만,
	-- 지속적으로 빠른 이동은 버킷이 바닥나 초과분이 누적된다. 회피/충격은 "총량"이 있는 추가 버킷이다(표본마다 새로 주어지지 않음).
	local maxSpeed = cfg.Movement.RunSpeed * mc.SpeedTolerance
	local cap = maxSpeed * mc.LatencySlackSeconds
	local upCap = mc.MaxUpSpeed * mc.LatencySlackSeconds
	local base = math.min(cap, s.bucket) + maxSpeed * cdt
	local upBase = math.min(upCap, s.upBucket) + mc.MaxUpSpeed * cdt

	local moved = flatDist(pos, prev)
	local dy = pos.Y - prev.Y
	local rem = moved
	local upRem = math.max(0, dy)

	local usedBase = math.min(rem, base)
	s.bucket = base - usedBase
	rem -= usedBase
	local usedUp = math.min(upRem, upBase)
	s.upBucket = upBase - usedUp
	upRem -= usedUp

	-- 서버가 발급한 허가만 추가 이동으로 인정한다. 방향 허가는 허가 방향의 성분만 소모할 수 있다.
	local mvx, mvz = pos.X - prev.X, pos.Z - prev.Z
	local kept = {}
	for _, p in s.permits do
		if now <= p.untilT then
			if rem > 0 and p.remaining > 0 then
				local avail = rem
				if p.dir then
					avail = math.min(avail, math.max(0, mvx * p.dir.X + mvz * p.dir.Z))
				end
				local take = math.min(avail, p.remaining)
				p.remaining -= take
				rem -= take
			end
			if upRem > 0 and p.upRemaining > 0 then
				local take = math.min(upRem, p.upRemaining)
				p.upRemaining -= take
				upRem -= take
			end
			table.insert(kept, p)
		end
	end
	s.permits = kept

	local allowed = moved - rem
	local over, upOver = rem, upRem
	local reason
	local hard = false

	if over > mc.HardStep or upOver > mc.HardStep then
		reason, hard = "teleport", true
		s.stats.teleport += 1
	end

	-- 벽 관통: 마지막 유효 위치 → 현재 위치 사이에 고체가 있고 충분히 가로질렀으면 위반
	if not reason and self._world and moved + math.abs(dy) > 0.01 then
		local hit = self._world.cast(prev, pos, 0)
		if hit then
			local total = Vec.dist(prev, pos)
			local remaining = total - hit.fraction * total
			if remaining >= mc.WallPenetration then
				reason, hard = "wall", true
				s.stats.wall += 1
			end
		end
	end

	if not reason then
		-- 초과 이동 누적(감쇠하는 합)
		s.excess = math.max(0, s.excess - mc.ExcessDecayPerSecond * cdt) + over + upOver
		if s.excess > mc.ExcessThreshold then
			if upOver > 0 and over == 0 then
				reason = "up_speed"
				s.stats.up += 1
			else
				reason = "speed"
				s.stats.speed += 1
			end
		elseif over > 0 or upOver > 0 then
			s.t = now
			s.last = pos
			s.stats.soft += 1
			return { status = "soft", moved = moved, allowed = allowed, excess = s.excess }
		end
	end

	if reason then
		-- 보정 빈도 기록(남발 시 로그)
		local recent = {}
		for _, t in s.corrections do
			if now - t < 1 then
				table.insert(recent, t)
			end
		end
		table.insert(recent, now)
		s.corrections = recent
		s.stats.corrections += 1
		if #recent > mc.MaxCorrectionsPerSecond then
			self:_log("correction_storm", id, { reason = reason, count = #recent })
		end
		self:_log("correct", id, { reason = reason, moved = moved, allowed = allowed })
		local to = s.last
		s.t = now
		s.excess = 0
		s.permits = {}
		return { status = "correct", reason = reason, correctTo = to, moved = moved, allowed = allowed, hard = hard }
	end

	s.last = pos
	s.t = now
	return { status = "ok", moved = moved, allowed = allowed, excess = s.excess }
end

return MovementValidator
