--!nonstrict
-- SUPERBALL 전용 볼 시뮬레이션(서버 권위). ProjectileService 와 별개인 이유: 볼은 ① 지형에서 튕기고 적에게 맞아도 튕겨 나가며 계속 날고
-- ② 비행 "단계"(= 튕김 사이 구간)별로 같은 대상 중복 피해를 통제하고 ③ 리콜(귀환)·공전(Cyclone)·교체(상한 12) 모드를 가지기 때문이다.
-- 판정은 매 스텝 이전→새 위치 선분을 월드(cast)와 대상(구)에 대해 스윕한다(터널링 없음). 시간은 항상 호출자가 now 로 전달한다.
--
-- deps = { config, damage, targets() -> { {id,pos,radius,alive} }, world { cast, lineOfSight }, getPose(ownerId) -> { pos }?, emit(event), onHit(ball, targetId, result, now)? }
local Link = require(script.Parent.Link)
local Vec = Link.shared("Vec")
local Geometry = require(script.Parent.Geometry)

local BallService = {}
BallService.__index = BallService

local EPS = 1e-9

function BallService.new(deps)
	return setmetatable({
		_cfg = deps.config or Link.shared("Config"),
		_damage = deps.damage,
		_targets = deps.targets,
		_world = deps.world,
		_getPose = deps.getPose,
		_emit = deps.emit or function() end,
		_onHit = deps.onHit,
		_list = {}, -- 생성 순서(오래된 것이 앞)
		_byId = {},
		_serial = 0,
	}, BallService)
end

function BallService:get(id)
	return self._byId[id]
end

function BallService:count(ownerId, filter)
	local n = 0
	for _, b in self._list do
		if not b.dead and (ownerId == nil or b.owner == ownerId) and (filter == nil or filter(b)) then
			n += 1
		end
	end
	return n
end

-- 살아 있는 볼 목록(오래된 순). filter(b) -> boolean
function BallService:list(ownerId, filter)
	local out = {}
	for _, b in self._list do
		if not b.dead and b.owner == ownerId and (filter == nil or filter(b)) then
			table.insert(out, b)
		end
	end
	return out
end

-- spec = { owner, life, kind = "Normal"|"Cyclone"|"CycloneShot", ultimate = bool, pos, dir, speed, gravity, radius,
--          damage, bounces, lifetime, restitution, now, source? }  /  공전: mode = "Orbit", orbit = {...}
function BallService:spawn(spec)
	self._serial += 1
	local dir = spec.dir and Vec.normalize(spec.dir) or { X = 0, Y = 0, Z = 1 }
	local b = {
		id = string.format("bl%d", self._serial),
		serial = self._serial,
		owner = spec.owner,
		life = spec.life or 0,
		kind = spec.kind or "Normal",
		ultimate = spec.ultimate == true,
		mode = spec.mode or "Fly",
		pos = Vec.new(spec.pos.X, spec.pos.Y, spec.pos.Z),
		vel = Vec.scale(dir, spec.speed or 0),
		gravity = spec.gravity or 0,
		radius = spec.radius or 0.6,
		damage = spec.damage or 0,
		bouncesLeft = spec.bounces or 0,
		bounces = 0, -- 지금까지 지형에서 튕긴 횟수(Trick Master 판정)
		stage = 0, -- 비행 단계: 지형에서 튕기거나 적에게 맞아 튕겨 나갈 때마다 증가
		restitution = spec.restitution or 0.8,
		spawnedAt = spec.now,
		t = spec.now,
		expireAt = spec.now + (spec.lifetime or 5),
		hitStage = {}, -- [targetId] = 마지막으로 맞힌 단계(같은 단계 중복 피해 방지)
		inside = {}, -- [targetId] = true : 이미 접촉 중인 대상(튕겨 나온 직후 재접촉 방지)
		orbit = spec.orbit,
		contactAt = {}, -- [targetId] = 공전 접촉 피해 마지막 시각
		returnHit = {}, -- 귀환 중 맞힌 대상(볼당 대상당 1회)
		dead = false,
		shotDamage = spec.shotDamage,
	}
	self._byId[b.id] = b
	table.insert(self._list, b)
	self._emit({
		type = "BallSpawn", ballId = b.id, ownerId = b.owner, kind = b.kind, mode = b.mode, pos = b.pos, vel = b.vel, gravity = b.gravity,
		radius = b.radius, lifetime = spec.lifetime or 5, orbit = b.orbit, time = spec.now,
	})
	return b
end

function BallService:remove(b, reason, now)
	if b.dead then
		return
	end
	b.dead = true
	self._byId[b.id] = nil
	self._emit({ type = "BallEnd", ballId = b.id, ownerId = b.owner, reason = reason, pos = b.pos, time = now })
end

function BallService:removeWhere(ownerId, filter, reason, now)
	local n = 0
	for _, b in table.clone(self._list) do
		if not b.dead and b.owner == ownerId and (filter == nil or filter(b)) then
			self:remove(b, reason, now)
			n += 1
		end
	end
	return n
end

-- 이 소유자의 가장 오래된 볼부터 n 개를 filter 조건에서 제거(교체). 반환: 제거한 수
function BallService:evictOldest(ownerId, n, filter, now)
	local removed = 0
	for _, b in self._list do
		if removed >= n then
			break
		end
		if not b.dead and b.owner == ownerId and (filter == nil or filter(b)) then
			self:remove(b, "Evicted", now)
			removed += 1
		end
	end
	return removed
end

-- ── 귀환(리콜) ──────────────────────────────────────────────
-- 날고 있는 볼을 귀환 모드로 바꾼다. 귀환 중에는 소유자 쪽으로 직선 비행하며 경로상의 적을 볼당 대상당 1회 맞힌다(적 유도 없음).
function BallService:recall(b, speed, damage, now)
	if b.dead or b.mode ~= "Fly" then
		return false
	end
	b.mode = "Return"
	b.returnSpeed = speed
	b.returnDamage = damage
	b.returnStarted = now
	b.returnHit = {}
	b.inside = {}
	b.gravity = 0
	self._emit({ type = "BallMode", ballId = b.id, ownerId = b.owner, mode = "Return", pos = b.pos, speed = speed, time = now })
	return true
end

-- ── 스윕 ────────────────────────────────────────────────────
local function reflect(v, n)
	return Vec.sub(v, Vec.scale(n, 2 * Vec.dot(v, n)))
end

-- p0→p1 에서 가장 먼저 일어나는 충돌: { kind = "World"|"Target", f, ... }
function BallService:_nearest(b, p0, p1, allowTargets, skip)
	local best
	local w = self._world.cast(p0, p1, b.radius)
	if w then
		best = { kind = "World", f = w.fraction, position = w.position, normal = w.normal }
	end
	if allowTargets then
		for _, t in self._targets() do
			if t.id ~= b.owner and t.alive ~= false and not (skip and skip(t)) then
				local f = Geometry.segmentSphere(p0, p1, t.pos, (t.radius or self._cfg.Combat.HitRadius) + b.radius)
				if f and (best == nil or f < best.f) then
					best = { kind = "Target", f = f, target = t }
				end
			end
		end
	end
	return best
end

-- 대상과의 접촉 상태 갱신: 볼이 대상 구 밖으로 나가면 inside 해제
function BallService:_updateInside(b)
	for tid in b.inside do
		local found = false
		for _, t in self._targets() do
			if t.id == tid then
				found = true
				if Vec.dist(b.pos, t.pos) > (t.radius or self._cfg.Combat.HitRadius) + b.radius + 0.05 then
					b.inside[tid] = nil
				end
			end
		end
		if not found then
			b.inside[tid] = nil
		end
	end
end

-- 날아가는 볼이 대상에 닿았을 때. 반환: "removed" | "continue"
function BallService:_hitTarget(b, t, time)
	local attackId = string.format("%s#s%d", b.id, b.stage)
	local r = self._damage:applyDamage({
		attackerId = b.owner, targetId = t.id, attackId = attackId, amount = b.damage, kind = "Projectile", blockable = true,
		sourceDir = Vec.scale(Vec.normalize(b.vel) or { X = 0, Y = 0, Z = 1 }, -1),
	}, time)
	if not r.applied and r.reason == "parried" then
		self:remove(b, "Parried", time)
		return "removed"
	end
	b.hitStage[t.id] = b.stage
	b.inside[t.id] = true
	if not r.applied then
		return "continue" -- 회피 무적·부활 보호·사망 등: 통과(피해 없음, 튕기지 않음)
	end
	self._emit({ type = "BallHit", ballId = b.id, ownerId = b.owner, targetId = t.id, result = r, bounces = b.bounces, time = time })
	if self._onHit then
		self._onHit(b, t.id, r, time)
	end
	-- 적 몸에서 튕겨 나간다: 대상 중심에서 볼 쪽으로의 법선, 새 비행 단계 시작
	local n = Vec.normalize(Vec.sub(b.pos, t.pos)) or Vec.scale(Vec.normalize(b.vel) or { X = 0, Y = 0, Z = 1 }, -1)
	b.vel = Vec.scale(reflect(b.vel, n), b.restitution)
	b.stage += 1
	b.pos = Vec.add(b.pos, Vec.scale(n, 0.05))
	self._emit({ type = "BallBounce", ballId = b.id, pos = b.pos, vel = b.vel, onTarget = true, time = time })
	return "continue"
end

function BallService:_stepFly(b, dt)
	local g = { X = 0, Y = -b.gravity, Z = 0 }
	local p0, v0 = b.pos, b.vel
	local p1 = Vec.add(Vec.add(p0, Vec.scale(v0, dt)), Vec.scale(g, 0.5 * dt * dt))
	local v1 = Vec.add(v0, Vec.scale(g, dt))
	local ev = self:_nearest(b, p0, p1, true, function(t)
		return b.hitStage[t.id] == b.stage or b.inside[t.id]
	end)
	if not ev then
		b.pos, b.vel, b.t = p1, v1, b.t + dt
		self:_updateInside(b)
		return
	end
	local tau = dt * ev.f
	local time = b.t + tau
	b.t = time
	if ev.kind == "World" then
		b.pos = ev.position
		b.vel = Vec.add(v0, Vec.scale(g, tau))
		if b.bouncesLeft > 0 then
			b.bouncesLeft -= 1
			b.bounces += 1
			b.stage += 1
			b.vel = Vec.scale(reflect(b.vel, ev.normal), b.restitution)
			b.pos = Vec.add(ev.position, Vec.scale(ev.normal, self._cfg.Projectile.SurfaceEpsilon))
			self._emit({ type = "BallBounce", ballId = b.id, pos = b.pos, vel = b.vel, count = b.bounces, time = time })
			b.inside = {}
		else
			self:remove(b, "World", time)
		end
	else
		b.pos = Geometry.lerp(p0, p1, ev.f)
		b.vel = Vec.add(v0, Vec.scale(g, tau))
		self:_hitTarget(b, ev.target, time)
	end
	-- 이벤트가 있었으면 남은 시간은 호출자 루프가 이어서 처리(b.t 가 now 에 도달할 때까지)
end

function BallService:_stepReturn(b, dt)
	local pose = self._getPose and self._getPose(b.owner)
	if not pose then
		self:remove(b, "OwnerGone", b.t)
		return
	end
	local target = Vec.add(pose.pos, { X = 0, Y = self._cfg.Combat.EyeHeight, Z = 0 })
	local to = Vec.sub(target, b.pos)
	local dist = Vec.len(to)
	if dist <= 3 then -- 소유자에게 도착(회수)
		self:remove(b, "Recalled", b.t)
		return
	end
	local dir = Vec.scale(to, 1 / dist)
	local step = math.min(dist, b.returnSpeed * dt)
	local p0 = b.pos
	local p1 = Vec.add(p0, Vec.scale(dir, step))
	b.vel = Vec.scale(dir, b.returnSpeed)
	local ev = self:_nearest(b, p0, p1, true, function(t)
		return b.returnHit[t.id]
	end)
	if not ev then
		b.pos, b.t = p1, b.t + dt
		return
	end
	local time = b.t + dt * ev.f
	b.t = time
	if ev.kind == "World" then
		b.pos = ev.position
		self:remove(b, "ReturnBlocked", time) -- 귀환 경로가 지형에 막히면 소멸(A72)
		return
	end
	b.pos = Geometry.lerp(p0, p1, ev.f)
	b.returnHit[ev.target.id] = true -- 대상당 1회(귀환 단계)
	local r = self._damage:applyDamage({
		attackerId = b.owner, targetId = ev.target.id, attackId = b.id .. "#ret", amount = b.returnDamage, kind = "Projectile", blockable = true,
		sourceDir = Vec.scale(dir, -1),
	}, time)
	if not r.applied and r.reason == "parried" then
		self:remove(b, "Parried", time)
		return
	end
	if r.applied then
		self._emit({ type = "BallHit", ballId = b.id, ownerId = b.owner, targetId = ev.target.id, result = r, bounces = b.bounces, returning = true, time = time })
		if self._onHit then
			self._onHit(b, ev.target.id, r, time)
		end
	end
end

-- 공전: 소유자 중심 원운동. 이전 위치→새 위치 선분으로 접촉을 판정하고 접촉 피해는 볼·대상별 간격(contactInterval)을 둔다.
function BallService:_stepOrbit(b, dt)
	local pose = self._getPose and self._getPose(b.owner)
	if not pose then
		self:remove(b, "OwnerGone", b.t)
		return
	end
	local o = b.orbit
	local t = b.t + dt
	local ang = o.phase + o.omega * (t - o.startAt)
	local p0 = b.pos
	local p1 = Vec.add(pose.pos, { X = math.cos(ang) * o.radius, Y = o.height, Z = math.sin(ang) * o.radius })
	b.t = t
	for _, tg in self._targets() do
		if tg.id ~= b.owner and tg.alive ~= false then
			local f = Geometry.segmentSphere(p0, p1, tg.pos, (tg.radius or self._cfg.Combat.HitRadius) + b.radius)
			if f then
				local last = b.contactAt[tg.id]
				local sinceAny = o.ownerContact and o.ownerContact[tg.id]
				if (last == nil or t - last >= o.contactInterval - 1e-6) and (sinceAny == nil or t - sinceAny >= o.targetInterval - 1e-6) then
					local r = self._damage:applyDamage({
						attackerId = b.owner, targetId = tg.id, attackId = string.format("%s#c%d", b.id, math.floor(t * 1000)),
						amount = o.contactDamage, kind = "Projectile", blockable = false,
					}, t)
					if r.applied then
						b.contactAt[tg.id] = t
						if o.ownerContact then
							o.ownerContact[tg.id] = t
						end
						self._emit({ type = "BallHit", ballId = b.id, ownerId = b.owner, targetId = tg.id, result = r, bounces = 0, contact = true, time = t })
						if self._onHit then
							self._onHit(b, tg.id, r, t)
						end
					end
				end
			end
		end
	end
	b.pos = p1
end

-- now 까지 모든 볼 전진. 한 볼에서 이벤트가 연속으로 많이 나도 상한(MaxEventsPerAdvance)으로 끊는다.
function BallService:step(now)
	local maxStep = self._cfg.Projectile.MaxStepSeconds
	local cap = self._cfg.Projectile.MaxEventsPerAdvance
	for _, b in table.clone(self._list) do
		local guard = 0
		while not b.dead do
			if b.t >= b.expireAt - EPS then
				self:remove(b, "Expired", b.expireAt)
				break
			end
			if b.mode == "Return" and b.t - b.returnStarted > 3 then
				self:remove(b, "ReturnTimeout", b.t)
				break
			end
			if b.t >= now - EPS then
				break
			end
			local dt = math.min(math.min(now, b.expireAt) - b.t, maxStep)
			local before = b.t
			if b.mode == "Fly" then
				self:_stepFly(b, dt)
			elseif b.mode == "Return" then
				self:_stepReturn(b, dt)
			else
				self:_stepOrbit(b, dt)
			end
			if b.t - before < 1e-7 then
				guard += 1
				if guard > cap then
					self:remove(b, "EventCap", now)
					break
				end
			end
		end
	end
	local alive = {}
	for _, b in self._list do
		if not b.dead then
			table.insert(alive, b)
		end
	end
	self._list = alive
end

function BallService:clearAll(now)
	for _, b in table.clone(self._list) do
		self:remove(b, "Cancelled", now)
	end
end

return BallService
