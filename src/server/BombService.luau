--!nonstrict
-- TIMEBOMB 전용 폭탄 시뮬레이션(서버 권위): 비행(포물선, 지형에서 정지) → 타이머/원격 기폭 → 폭발(차폐·거리 감쇠·자기 피해 면역) → 연쇄 반응.
-- ProjectileService 와 별개인 이유: 폭탄은 ① 착지 후에도 남고 ② 소유자별 설치 한도·원격 기폭이 있고 ③ 연쇄 반응(자기 폭탄에만, 최대 3단계)을 서버가 결정론적으로 처리해야 한다.
-- 시간은 항상 호출자가 now 로 전달한다. 폭발 순서 = (폭발 시각, 생성 순번) 오름차순, 연쇄는 단계 순(FIFO).
--
-- deps = { config, damage, targets() -> { {id,pos,radius,alive} }, world { cast, lineOfSight }, emit(event) }
local Link = require(script.Parent.Link)
local Vec = Link.shared("Vec")
local Hitbox = require(script.Parent.HitboxService)

local BombService = {}
BombService.__index = BombService

local EPS = 1e-9
BombService.MaxPerOwner = 24 -- ASSUMPTION A77: 소유자당 동시 폭탄 상한(클러스터 자탄 포함)
BombService.ChainRadius = 7 -- 확정
BombService.ChainStages = 3 -- 확정: 최초 폭발을 1단계로 센다

function BombService.new(deps)
	return setmetatable({
		_cfg = deps.config or Link.shared("Config"),
		_damage = deps.damage,
		_targets = deps.targets,
		_world = deps.world,
		_emit = deps.emit or function() end,
		_list = {},
		_byId = {},
		_serial = 0,
		_resolving = false,
	}, BombService)
end

function BombService:get(id)
	return self._byId[id]
end

function BombService:count(ownerId, filter)
	local n = 0
	for _, b in self._list do
		if not b.dead and (ownerId == nil or b.owner == ownerId) and (filter == nil or filter(b)) then
			n += 1
		end
	end
	return n
end

function BombService:list(ownerId, filter)
	local out = {}
	for _, b in self._list do
		if not b.dead and b.owner == ownerId and (filter == nil or filter(b)) then
			table.insert(out, b)
		end
	end
	return out
end

-- spec = { owner, life, kind, pos, dir?, speed?, gravity?, radius?, now, explodeAt?, fuseAfterLand?, expireAt?, explosion, placed?, chainTarget?,
--          onExplode?(bomb, results, stage, time), tag? }
function BombService:spawn(spec)
	if self:count(spec.owner) >= BombService.MaxPerOwner then
		return nil, "too_many_bombs"
	end
	self._serial += 1
	local dir = spec.dir and Vec.normalize(spec.dir) or { X = 0, Y = 1, Z = 0 }
	local b = {
		id = string.format("bm%d", self._serial),
		serial = self._serial,
		owner = spec.owner,
		life = spec.life or 0,
		kind = spec.kind or "Timed",
		placed = spec.placed == true,
		pos = Vec.new(spec.pos.X, spec.pos.Y, spec.pos.Z),
		vel = Vec.scale(dir, spec.speed or 0),
		gravity = spec.gravity or 0,
		radius = spec.radius or 0.4,
		mode = "Fly",
		spawnedAt = spec.now,
		t = spec.now,
		explodeAt = spec.explodeAt,
		fuseAfterLand = spec.fuseAfterLand,
		expireAt = spec.expireAt,
		explosion = spec.explosion,
		chainTarget = spec.chainTarget ~= false,
		onExplode = spec.onExplode,
		tag = spec.tag,
		dead = false,
		queued = false,
	}
	self._byId[b.id] = b
	table.insert(self._list, b)
	self._emit({
		type = "BombSpawn", bombId = b.id, ownerId = b.owner, kind = b.kind, placed = b.placed, pos = b.pos, vel = b.vel, gravity = b.gravity,
		radius = b.radius, explodeAt = b.explodeAt, blastRadius = b.explosion.radius, time = spec.now,
	})
	return b
end

function BombService:_end(b, reason, time)
	if b.dead then
		return
	end
	b.dead = true
	self._byId[b.id] = nil
	self._emit({ type = "BombEnd", bombId = b.id, ownerId = b.owner, kind = b.kind, reason = reason, pos = b.pos, time = time })
end

function BombService:removeWhere(ownerId, filter, reason, now)
	local n = 0
	for _, b in table.clone(self._list) do
		if not b.dead and b.owner == ownerId and (filter == nil or filter(b)) then
			self:_end(b, reason, now)
			n += 1
		end
	end
	return n
end

-- ── 폭발 ────────────────────────────────────────────────────
-- 범위 피해(자기 자신은 체력 피해 없음). explosion = { radius, damage, falloffMin, knockback? }. 반환: 결과 목록
-- 감쇠(100% → 60% → 30%)는 DamageService 가 공격자·대상별로 관리한다(explosionProfile = "Timebomb").
function BombService:blast(owner, center, explosion, time, attackId)
	local hits = Hitbox.entitiesInRadius(center, explosion.radius, self._targets(), self._world.lineOfSight)
	local results = {}
	for _, h in hits do
		if h.id ~= owner then
			local mult = Hitbox.explosionMultiplier(h.distance, explosion.radius, explosion.falloffMin or 1)
			local amount = explosion.damage * mult
			if amount > 0 then
				local effects
				if (explosion.knockback or 0) > 0 then
					for _, t in self._targets() do
						if t.id == h.id then
							local away = Vec.sub(t.pos, center)
							if not Vec.normalize(away) then
								away = { X = 0, Y = 1, Z = 0 }
							end
							effects = { { type = "Knockback", direction = away, power = math.min(200, explosion.knockback * mult), upward = 4 } }
						end
					end
				end
				local r = self._damage:applyDamage({
					attackerId = owner, targetId = h.id, attackId = attackId, amount = amount, kind = "Explosion", explosionProfile = "Timebomb",
					effects = effects,
				}, time)
				table.insert(results, { targetId = h.id, applied = r.applied, amount = r.amount, reason = r.reason })
			end
		end
	end
	return results
end

-- center 근처(7스터드)의 소유자 자신의 폭탄 중 아직 기폭 대기 중이 아닌 것(생성 순)
function BombService:_chainCandidates(owner, center, except)
	local out = {}
	for _, o in self._list do
		if not o.dead and not o.queued and o ~= except and o.owner == owner and o.chainTarget and Vec.dist(center, o.pos) <= BombService.ChainRadius + EPS then
			table.insert(out, o)
		end
	end
	return out
end

function BombService:_run(queue, time)
	local i = 1
	while i <= #queue do
		local e = queue[i]
		i += 1
		local b = e.bomb
		if not b.dead then
			b.exploded = true
			local center = b.pos
			local candidates
			if b.explosion.chain ~= false and e.stage < BombService.ChainStages then
				candidates = self:_chainCandidates(b.owner, center, b)
				for _, o in candidates do
					o.queued = true -- 같은 폭탄은 두 번 기폭되지 않는다
				end
			end
			self:_end(b, "Exploded", time)
			local results = self:blast(b.owner, center, b.explosion, time, b.id .. "#exp")
			self._emit({
				type = "BombExplode", bombId = b.id, ownerId = b.owner, kind = b.kind, pos = center, radius = b.explosion.radius, stage = e.stage,
				results = results, time = time,
			})
			if candidates then
				for _, o in candidates do
					table.insert(queue, { bomb = o, stage = e.stage + 1 })
				end
			end
			if b.onExplode then
				b.onExplode(b, results, e.stage, time) -- 자탄 생성 등(연쇄 후보를 정한 뒤에 호출되므로 새 자탄은 연쇄에 휘말리지 않는다)
			end
		end
	end
end

-- time 에 기폭 시각이 도래한 폭탄을 (시각, 순번) 순으로 1단계 폭발로 처리하고 연쇄를 전파한다.
function BombService:_resolve(time)
	local due = {}
	for _, b in self._list do
		if not b.dead and not b.queued and b.explodeAt and b.explodeAt <= time + EPS then
			table.insert(due, b)
		end
	end
	if #due == 0 then
		return 0
	end
	table.sort(due, function(a, b)
		if a.explodeAt ~= b.explodeAt then
			return a.explodeAt < b.explodeAt
		end
		return a.serial < b.serial
	end)
	local queue = {}
	for _, b in due do
		b.queued = true
		table.insert(queue, { bomb = b, stage = 1 })
	end
	self:_run(queue, time)
	return #due
end

-- 원격 기폭: 조건에 맞는 소유자의 폭탄 모두를 지금 폭발시킨다. 반환: 기폭한 폭탄 수(중복 호출은 0)
function BombService:detonate(ownerId, filter, now)
	local n = 0
	for _, b in self._list do
		if not b.dead and not b.queued and b.owner == ownerId and (filter == nil or filter(b)) then
			b.explodeAt = now
			n += 1
		end
	end
	if n > 0 then
		self:_resolve(now)
	end
	return n
end

-- 폭탄이 아닌 폭발(Blast Guard / Blast Jump)이 소유자의 근처 폭탄을 연쇄 기폭한다(첫 폭발 = 1단계, 이 폭탄들은 2단계부터).
function BombService:chainFrom(owner, center, time)
	local candidates = self:_chainCandidates(owner, center, nil)
	if #candidates == 0 then
		return 0
	end
	local queue = {}
	for _, o in candidates do
		o.queued = true
		table.insert(queue, { bomb = o, stage = 2 })
	end
	self:_run(queue, time)
	return #candidates
end

-- ── 비행·시간 진행 ──────────────────────────────────────────
function BombService:_advance(b, to)
	local maxStep = self._cfg.Projectile.MaxStepSeconds
	local guard = 0
	while not b.dead and b.t < to - EPS do
		if b.mode ~= "Fly" then
			b.t = to
			break
		end
		local dt = math.min(to - b.t, maxStep)
		local p0, v0 = b.pos, b.vel
		local g = { X = 0, Y = -b.gravity, Z = 0 }
		local p1 = Vec.add(Vec.add(p0, Vec.scale(v0, dt)), Vec.scale(g, 0.5 * dt * dt))
		local v1 = Vec.add(v0, Vec.scale(g, dt))
		local hit = self._world.cast(p0, p1, b.radius)
		if hit then
			b.t += dt * hit.fraction
			b.pos = hit.position
			b.vel = { X = 0, Y = 0, Z = 0 }
			b.mode = "Landed"
			if b.fuseAfterLand then
				b.explodeAt = b.t + b.fuseAfterLand
			end
			self._emit({ type = "BombLand", bombId = b.id, ownerId = b.owner, pos = b.pos, explodeAt = b.explodeAt, time = b.t })
		else
			b.pos, b.vel, b.t = p1, v1, b.t + dt
		end
		guard += 1
		if guard > 4096 then
			break
		end
	end
end

function BombService:_advanceAll(to)
	for _, b in self._list do
		if not b.dead then
			self:_advance(b, to)
		end
	end
end

function BombService:_nextEvent()
	local best
	for _, b in self._list do
		if not b.dead and not b.queued then
			local t = b.explodeAt
			if b.expireAt and (t == nil or b.expireAt < t) then
				t = b.expireAt
			end
			if t and (best == nil or t < best) then
				best = t
			end
		end
	end
	return best
end

function BombService:step(now)
	local guard = 0
	while guard < 256 do
		guard += 1
		local tNext = self:_nextEvent()
		if tNext == nil or tNext > now + EPS then
			break
		end
		tNext = math.max(tNext, 0)
		self:_advanceAll(tNext)
		self:_resolve(tNext)
		for _, b in table.clone(self._list) do
			if not b.dead and b.expireAt and b.expireAt <= tNext + EPS then
				self:_end(b, "Expired", tNext) -- 설치 수명 만료: 폭발 없이 사라진다
			end
		end
	end
	self:_advanceAll(now)
	local alive = {}
	for _, b in self._list do
		if not b.dead then
			table.insert(alive, b)
		end
	end
	self._list = alive
end

return BombService
