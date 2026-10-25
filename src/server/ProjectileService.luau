--!nonstrict
-- 서버 권위 투사체 시뮬레이션. 7종: Linear, Arc, Bounce, Pierce, Explosion, Beam, Placed.
-- 기본은 실제로 이동하는 투사체이며, 매 스텝 이전 위치→새 위치 구간을 연속 충돌 검사(스윕)한다.
-- 히트스캔은 def.collision.mode == "Hitscan" + allowHitscan=true 인 개별 공격에서만 선택 가능하다.
--
-- 외부 의존(모두 주입):
--   damage    DamageService
--   targets() -> { {id, pos, radius, alive} }                  피격 대상 목록(서버가 가진 위치)
--   world     { cast(p0, p1, radius) -> {fraction, position, normal}?, lineOfSight(a, b) -> boolean }
--   getPose(ownerId) -> { pos, dir }?                           Beam이 소유자를 따라가기 위한 현재 자세
--
-- 생존/상태 규칙:
--   * 투사체는 발사 시점의 데이터를 복사(스냅샷)해 보관한다. 이후 소유자가 부활하거나 캐릭터를 바꿔도
--     살아있는 캐릭터 상태를 참조하지 않는다. (피해 귀속은 ownerId만 사용)
--   * 소유자 사망: Beam(캐릭터 연결 지속 공격)만 종료. 이미 발사한 투사체와 설치물은 남은 수명 동안 유지.
--     (설치물은 placed.survivesOwnerDeath=false 인 경우에만 종료되며 이때 폭발하지 않는다.)
local Link = require(script.Parent.Link)
local Vec = Link.shared("Vec")
local ProjectileSpec = Link.shared("ProjectileSpec")
local Schema = Link.shared("Schema")
local Hitbox = require(script.Parent.HitboxService)

local ProjectileService = {}
ProjectileService.__index = ProjectileService

local EPS = 1e-9

local function deepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in t do
		c[k] = deepCopy(v)
	end
	return c
end

-- 선분 p0→p1 이 구(c, R)와 처음 만나는 비율 f∈[0,1]. 시작점이 이미 안이면 0.
local function segmentSphere(p0, p1, c, R)
	local d = Vec.sub(p1, p0)
	local m = Vec.sub(p0, c)
	local cc = Vec.dot(m, m) - R * R
	if cc <= 0 then
		return 0
	end
	local a = Vec.dot(d, d)
	if a < 1e-12 then
		return nil
	end
	local b = Vec.dot(m, d)
	local disc = b * b - a * cc
	if disc < 0 then
		return nil
	end
	local f = (-b - math.sqrt(disc)) / a
	if f < 0 or f > 1 then
		return nil
	end
	return f
end

local function lerp(p0, p1, f)
	return { X = p0.X + (p1.X - p0.X) * f, Y = p0.Y + (p1.Y - p0.Y) * f, Z = p0.Z + (p1.Z - p0.Z) * f }
end

function ProjectileService.new(deps)
	return setmetatable({
		_cfg = deps.config or Link.shared("Config"),
		_damage = deps.damage,
		_targets = deps.targets or function()
			return {}
		end,
		_world = deps.world or {
			cast = function()
				return nil
			end,
			lineOfSight = function()
				return true
			end,
		},
		_getPose = deps.getPose,
		_list = {}, -- 활성 투사체 (순서 보장용)
		_byId = {},
		_perOwner = {},
		_life = {}, -- [ownerId] = 현재 생애 번호
		_counter = 0,
		_total = 0,
		_listeners = {},
		_validated = setmetatable({}, { __mode = "k" }),
	}, ProjectileService)
end

function ProjectileService:onEvent(fn)
	table.insert(self._listeners, fn)
end

function ProjectileService:_emit(event)
	for _, fn in self._listeners do
		fn(event)
	end
end

function ProjectileService:getActiveCount(ownerId)
	if ownerId ~= nil then
		return self._perOwner[ownerId] or 0
	end
	return self._total
end

function ProjectileService:get(id)
	local p = self._byId[id]
	if not p then
		return nil
	end
	return { id = p.id, type = p.def.type, ownerId = p.ownerId, pos = p.pos, vel = p.vel, bounces = p.bounces, hits = p.hitCount }
end

-- params = { def, ownerId, origin, direction, strong?, effects?, knockback? }
-- 반환: projectileId | nil, reason
function ProjectileService:spawn(params, now)
	if type(params) ~= "table" or type(params.def) ~= "table" then
		return nil, "bad_params"
	end
	local ownerId = params.ownerId
	if type(ownerId) ~= "string" and type(ownerId) ~= "number" then
		return nil, "bad_owner"
	end
	if not Schema.validate(Schema.vector3(), params.origin) or not Schema.validate(Schema.vector3(), params.direction) then
		return nil, "bad_vector"
	end
	local dir = Vec.normalize(params.direction)
	if not dir and params.def.type ~= "Explosion" and params.def.type ~= "Placed" then
		return nil, "zero_direction"
	end
	if self._validated[params.def] == nil then
		local ok, err = ProjectileSpec.validate(params.def)
		if not ok then
			return nil, "invalid_def: " .. tostring(err)
		end
		self._validated[params.def] = true
	end
	local lim = self._cfg.Projectile
	if (self._perOwner[ownerId] or 0) >= lim.MaxActivePerOwner or self._total >= lim.MaxActiveTotal then
		return nil, "too_many_projectiles"
	end

	local def = deepCopy(params.def) -- 스냅샷
	self._counter += 1
	local p = {
		id = string.format("pj%d", self._counter),
		def = def,
		ownerId = ownerId,
		lifeId = self._life[ownerId] or 0,
		pos = Vec.new(params.origin.X, params.origin.Y, params.origin.Z),
		origin = Vec.new(params.origin.X, params.origin.Y, params.origin.Z),
		dir = dir or { X = 0, Y = 0, Z = 1 },
		vel = dir and Vec.scale(dir, def.speed > 0 and def.speed or 1) or { X = 0, Y = 0, Z = 0 },
		strong = params.strong == true,
		effects = deepCopy(params.effects),
		knockback = params.knockback,
		blockable = def.blockable,
		spawnedAt = now,
		t = now,
		travelled = 0,
		bounces = 0,
		hitCount = 0,
		hitAt = {},
		ignore = {}, -- 회피 무적 등으로 통과한 대상: 이 투사체는 해당 대상을 더 이상 판정하지 않는다
		dead = false,
		detonated = false,
		pierceLeft = def.pierce and def.pierce.maxHits or 1,
		bounceLeft = def.bounce and def.bounce.maxBounces or 0,
	}
	if p.blockable == nil then
		-- 기본: 직접 피해 투사체만 방어 가능. 폭발·빔·설치형은 방어 불가(일반 광역 폭발은 패링으로 막지 않는다)
		p.blockable = def.type == "Linear" or def.type == "Arc" or def.type == "Bounce" or def.type == "Pierce"
	end
	p.expireAt = now + def.lifetime
	if def.type == "Beam" then
		p.expireAt = now + def.beam.duration
	elseif def.type == "Placed" then
		p.expireAt = now + math.min(def.placed.fuseTime, def.lifetime)
		p.armedAt = now + def.placed.armTime
	end

	self._byId[p.id] = p
	table.insert(self._list, p)
	self._perOwner[ownerId] = (self._perOwner[ownerId] or 0) + 1
	self._total += 1
	self:_emit({
		type = "Spawned", projectileId = p.id, projectileType = def.type, ownerId = ownerId, pos = p.pos, dir = p.dir,
		defId = def.id, speed = def.speed, gravity = def.gravity, radius = def.collision.radius, lifetime = def.lifetime, time = now,
	})

	if def.type == "Explosion" then
		self:_finish(p, "Detonated", p.pos, now)
	elseif def.type == "Beam" then
		p.nextTick = now + def.beam.tickInterval
		self:_beamTick(p, now)
	elseif def.collision.mode == "Hitscan" then
		self:_hitscan(p, now)
	end
	return p.id, nil
end

function ProjectileService:_remove(p)
	p.dead = true
	self._byId[p.id] = nil
	self._total -= 1
	self._perOwner[p.ownerId] = math.max(0, (self._perOwner[p.ownerId] or 1) - 1)
end

function ProjectileService:_finish(p, reason, pos, time)
	if p.dead then
		return
	end
	self:_remove(p)
	if p.def.explosion and reason ~= "Cancelled" then
		self:_detonate(p, pos or p.pos, time)
	end
	self:_emit({ type = "Ended", projectileId = p.id, reason = reason, pos = pos or p.pos, time = time })
end

-- 폭발: 한 투사체당 한 번만(detonated 플래그 + DamageService attackId 중복 방지)
function ProjectileService:_detonate(p, pos, time)
	if p.detonated then
		return
	end
	p.detonated = true
	local ex = p.def.explosion
	local hits = Hitbox.entitiesInRadius(pos, ex.radius, self._targets(), self._world.lineOfSight)
	local results = {}
	for _, h in hits do
		local isOwner = h.id == p.ownerId
		if not isOwner or ex.friendlyOwnerDamage then
			local mult = Hitbox.explosionMultiplier(h.distance, ex.radius, ex.falloffMin)
			local amount = ex.damage * mult
			if amount > 0 then
				local effects = deepCopy(p.effects) or {}
				local targetPos
				for _, t in self._targets() do
					if t.id == h.id then
						targetPos = t.pos
					end
				end
				if ex.knockback > 0 and targetPos then
					local away = Vec.sub(targetPos, pos)
					if not Vec.normalize(away) then
						away = { X = 0, Y = 1, Z = 0 }
					end
					table.insert(effects, { type = "Knockback", direction = away, power = math.min(200, ex.knockback * mult), upward = 4 })
				end
				local r = self._damage:applyDamage({
					attackerId = p.ownerId,
					targetId = h.id,
					attackId = p.id .. "#exp",
					amount = amount,
					kind = "Explosion",
					strong = p.strong,
					allowSelf = isOwner,
					effects = effects,
				}, time)
				table.insert(results, { targetId = h.id, result = r })
			end
		end
	end
	self:_emit({ type = "Explosion", projectileId = p.id, ownerId = p.ownerId, pos = pos, radius = ex.radius, results = results, time = time })
end

function ProjectileService:_hitTarget(p, t, hitTime)
	local def = p.def
	local mult = 1
	if def.bounce then
		mult = def.bounce.damageMultPerBounce ^ p.bounces
	end
	local amount = def.damage * mult
	local result
	if amount > 0 then
		local effects = deepCopy(p.effects) or {}
		if p.knockback then
			local dir = Vec.normalize(p.vel) or p.dir
			table.insert(effects, { type = "Knockback", direction = dir, power = p.knockback, upward = 0 })
		end
		result = self._damage:applyDamage({
			attackerId = p.ownerId,
			targetId = t.id,
			attackId = p.id,
			amount = amount,
			kind = "Projectile",
			strong = p.strong,
			blockable = p.blockable,
			sourceDir = Vec.scale(Vec.normalize(p.vel) or p.dir, -1), -- 대상 기준 투사체가 온 방향
			rehitInterval = def.rehitInterval > 0 and math.max(0, def.rehitInterval - 1e-6) or 0,
			effects = effects,
		}, hitTime)
		if not result.applied and result.reason == "parried" then
			-- 패링으로 차단됨: 투사체는 소멸한다(원격 반격은 패링 로직이 거리로 판단)
			self:_emit({ type = "Blocked", projectileId = p.id, ownerId = p.ownerId, targetId = t.id, time = hitTime })
			return "blocked"
		end
		-- 적용되지 않은 경우(회피 무적·사망·중복 등)는 통과한다: 투사체 소모 없음
		if not result.applied then
			if result.reason == "duplicate_hit" then
				p.hitAt[t.id] = hitTime
			else
				p.ignore[t.id] = true
			end
			return false
		end
	end
	p.hitAt[t.id] = hitTime
	p.hitCount += 1
	self:_emit({ type = "Hit", projectileId = p.id, ownerId = p.ownerId, targetId = t.id, result = result, time = hitTime })
	return true
end

function ProjectileService:_canHit(p, t, time)
	if t.id == p.ownerId or t.alive == false or p.ignore[t.id] then
		return false
	end
	local last = p.hitAt[t.id]
	if last == nil then
		return true
	end
	return p.def.rehitInterval > 0 and time - last >= p.def.rehitInterval - 1e-6
end

-- p0→p1 구간에서 가장 먼저 일어나는 충돌: 월드 또는 대상
function ProjectileService:_nearest(p, p0, p1, t0, dt)
	local radius = p.def.collision.radius
	local best
	local w = self._world.cast(p0, p1, radius)
	if w then
		best = { kind = "World", f = w.fraction, position = w.position, normal = w.normal }
	end
	for _, t in self._targets() do
		if t.id ~= p.ownerId and t.alive ~= false and not p.ignore[t.id] then
			local f = segmentSphere(p0, p1, t.pos, (t.radius or self._cfg.Combat.HitRadius) + radius)
			if f and (best == nil or f < best.f) and self:_canHit(p, t, t0 + dt * f) then
				best = { kind = "Target", f = f, target = t }
			end
		end
	end
	return best
end

-- 한 구간을 처리(히트스캔/일반 공용). 반환: 구간 끝까지 이벤트 없이 통과했으면 true
function ProjectileService:_processSegment(p, p0, p1, t0, dt)
	local ev = self:_nearest(p, p0, p1, t0, dt)
	if not ev then
		return true
	end
	local time = t0 + dt * ev.f -- 충돌 시각(회피 무적 판정 등에 사용)
	local pos = ev.kind == "World" and ev.position or lerp(p0, p1, ev.f)
	p.pos = pos
	if ev.kind == "Target" then
		local hit = self:_hitTarget(p, ev.target, time)
		if hit == "blocked" then
			self:_finish(p, "Parried", pos, time)
		elseif hit then
			p.pierceLeft -= 1
			if p.def.type ~= "Pierce" or p.pierceLeft <= 0 then
				self:_finish(p, p.def.type == "Pierce" and "PierceExhausted" or "Hit", pos, time)
			end
		end
	else
		if p.def.type == "Bounce" and p.bounceLeft > 0 then
			p.bounceLeft -= 1
			p.bounces += 1
			local v = p.vel
			local n = ev.normal
			local vn = Vec.dot(v, n)
			local reflected = Vec.sub(v, Vec.scale(n, 2 * vn))
			p.vel = Vec.scale(reflected, p.def.bounce.restitution)
			p.dir = Vec.normalize(p.vel) or p.dir
			p.pos = Vec.add(pos, Vec.scale(n, self._cfg.Projectile.SurfaceEpsilon))
			self:_emit({ type = "Bounce", projectileId = p.id, pos = pos, normal = n, count = p.bounces, time = time })
			if Vec.len(p.vel) < 1e-6 then
				self:_finish(p, "Stopped", pos, time)
			end
		else
			self:_finish(p, "World", pos, time)
		end
	end
	return false, ev
end

-- 히트스캔(선택 기능): 발사 즉시 maxRange 만큼 한 번에 검사. 관통/반사 설정을 그대로 따른다.
function ProjectileService:_hitscan(p, now)
	local remaining = p.def.maxRange
	local guard = 0
	while not p.dead and remaining > 1e-6 and guard < self._cfg.Projectile.MaxEventsPerAdvance do
		guard += 1
		local p0 = p.pos
		local p1 = Vec.add(p0, Vec.scale(p.dir, remaining))
		local clear, ev = self:_processSegment(p, p0, p1, now, 0)
		if clear then
			p.pos = p1
			break
		end
		if ev then
			remaining -= Vec.dist(p0, p.pos)
		end
	end
	if not p.dead then
		self:_finish(p, "Range", p.pos, now)
	end
end

function ProjectileService:_beamTick(p, time)
	local def = p.def
	local origin, dir = p.origin, p.dir
	if self._getPose then
		local pose = self._getPose(p.ownerId)
		if pose then
			origin, dir = pose.pos, Vec.normalize(pose.dir) or dir
		end
	end
	local length = def.beam.length
	local tip = Vec.add(origin, Vec.scale(dir, length))
	local wall = self._world.cast(origin, tip, def.collision.radius)
	if wall then
		tip = lerp(origin, tip, wall.fraction)
	end
	p.origin, p.dir = origin, dir
	local interval = def.rehitInterval > 0 and def.rehitInterval or def.beam.tickInterval
	for _, t in self._targets() do
		if t.id ~= p.ownerId and t.alive ~= false then
			local f = segmentSphere(origin, tip, t.pos, (t.radius or self._cfg.Combat.HitRadius) + def.collision.radius)
			if f then
				local r = self._damage:applyDamage({
					attackerId = p.ownerId,
					targetId = t.id,
					attackId = p.id,
					amount = def.damage,
					kind = "Beam",
					strong = p.strong,
					blockable = p.blockable,
					sourceDir = Vec.scale(dir, -1),
					rehitInterval = math.max(0, interval - 1e-6),
					effects = deepCopy(p.effects),
				}, time)
				if r.applied then
					p.hitCount += 1
				end
				self:_emit({ type = "Hit", projectileId = p.id, ownerId = p.ownerId, targetId = t.id, result = r, time = time })
			end
		end
	end
	self:_emit({ type = "BeamTick", projectileId = p.id, origin = origin, tip = tip, time = time })
end

function ProjectileService:_moveStep(p, dt)
	local def = p.def
	if def.type == "Placed" then
		p.t += dt
		return
	end
	if def.type == "Beam" then
		local tEnd = p.t + dt
		while p.nextTick <= tEnd + EPS and p.nextTick <= p.expireAt + EPS do
			self:_beamTick(p, p.nextTick)
			p.nextTick += def.beam.tickInterval
		end
		p.t = tEnd
		return
	end

	local g = { X = 0, Y = -def.gravity, Z = 0 }
	local p0, v0 = p.pos, p.vel
	local p1 = Vec.add(Vec.add(p0, Vec.scale(v0, dt)), Vec.scale(g, 0.5 * dt * dt))
	local v1 = Vec.add(v0, Vec.scale(g, dt))
	local segLen = Vec.dist(p0, p1)
	local clippedRange = false
	if def.maxRange and p.travelled + segLen >= def.maxRange then
		local rem = math.max(0, def.maxRange - p.travelled)
		if segLen > EPS then
			p1 = lerp(p0, p1, rem / segLen)
		end
		segLen = rem
		clippedRange = true
	end

	local clear, ev = self:_processSegment(p, p0, p1, p.t, dt)
	if clear then
		p.travelled += segLen
		p.pos, p.vel = p1, v1
		p.t += dt
		if clippedRange then
			self:_finish(p, "Range", p1, p.t)
		end
		return
	end
	-- 이벤트 발생: 이벤트 지점까지만 진행한 것으로 처리
	local f = ev.f
	local tau = dt * f
	p.travelled += segLen * f
	p.t += tau
	if not p.dead and not (def.type == "Bounce" and ev.kind == "World") then
		p.vel = Vec.add(v0, Vec.scale(g, tau))
	end
end

function ProjectileService:_advance(p, now)
	local maxStep = self._cfg.Projectile.MaxStepSeconds
	local events = 0
	while not p.dead do
		if p.t >= p.expireAt - EPS then
			self:_finish(p, "Expired", p.pos, p.expireAt)
			break
		end
		if p.t >= now - EPS then
			break
		end
		local dt = math.min(math.min(now, p.expireAt) - p.t, maxStep)
		local before = p.t
		self:_moveStep(p, dt)
		if p.t - before < 1e-7 then
			events += 1
			if events > self._cfg.Projectile.MaxEventsPerAdvance then
				self:_finish(p, "EventCap", p.pos, now)
			end
		end
	end
end

-- 서버 루프에서 now(서버 시계, 초)로 호출
function ProjectileService:step(now)
	local list = table.clone(self._list)
	for _, p in list do
		if not p.dead then
			self:_advance(p, now)
		end
	end
	local alive = {}
	for _, p in self._list do
		if not p.dead then
			table.insert(alive, p)
		end
	end
	self._list = alive
end

-- 설치형 폭탄 원격 기폭: 장전(armTime) 이후에만 가능
function ProjectileService:trigger(id, now)
	local p = self._byId[id]
	if not p or p.def.type ~= "Placed" then
		return false, "not_placed"
	end
	if now < p.armedAt then
		return false, "not_armed"
	end
	self:_finish(p, "Triggered", p.pos, now)
	return true, nil
end

-- 소유자 사망: Beam만 종료. 투사체·설치물은 유지(survivesOwnerDeath=false 설치물만 폭발 없이 제거).
function ProjectileService:ownerDied(ownerId, now)
	for _, p in table.clone(self._list) do
		if p.ownerId == ownerId and not p.dead then
			if p.def.type == "Beam" then
				self:_finish(p, "OwnerDied", p.pos, now)
			elseif p.def.type == "Placed" and p.def.placed.survivesOwnerDeath == false then
				self:_finish(p, "Cancelled", p.pos, now)
			end
		end
	end
	self._life[ownerId] = (self._life[ownerId] or 0) + 1
end

function ProjectileService:ownerRespawned(ownerId)
	self._life[ownerId] = (self._life[ownerId] or 0) + 1
end

-- 플레이어 퇴장: Beam 종료, 나머지는 남은 수명 동안 유지(피해 귀속 ID는 그대로)
function ProjectileService:ownerRemoved(ownerId, now)
	self:ownerDied(ownerId, now)
end

-- 새 경기 등: 모든 투사체를 폭발 없이 제거
function ProjectileService:clearAll(now)
	for _, p in table.clone(self._list) do
		self:_finish(p, "Cancelled", p.pos, now)
	end
end

return ProjectileService
