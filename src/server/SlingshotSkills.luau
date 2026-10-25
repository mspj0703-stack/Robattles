--!nonstrict
-- SLINGSHOT 전용 서버 로직(Phase 2): LMB 충전 샷, RMB Aim Mode(클라이언트 전용), 스킬 1~3, 궁극기 Bullseye, 패시브 Bullseye Mark.
-- 충전량·피해·속도·표식은 전부 서버가 정한다(클라이언트는 Press/Release 의사와 조준 방향만 보낸다). 에임 보조 없음.
-- 수치: shared/Data/Characters.SLINGSHOT (확정/임시 구분은 그 파일 주석과 docs/ASSUMPTIONS.md A79~A80). deps 형태는 PaintballSkills 와 동일.
local Link = require(script.Parent.Link)
local Vec = Link.shared("Vec")
local Hitbox = require(script.Parent.HitboxService)
local Geometry = require(script.Parent.Geometry)

local SlingshotSkills = {}
SlingshotSkills.__index = SlingshotSkills

local ID = "SLINGSHOT"
local EPS = 1e-9

function SlingshotSkills.new(deps)
	local chars = deps.characters or Link.shared("Data/Characters")
	local self = setmetatable({
		_d = deps,
		_cfg = deps.cfg,
		_core = deps.core,
		_def = chars.SLINGSHOT,
		_tags = {}, -- [projectileId] = { owner, kind, life }
		_life = {}, -- [playerId] = 생애 번호
		_charge = {}, -- [playerId] = { startAt }
		_marks = {}, -- [owner][target] = 표식 만료 시각
		_counts = {}, -- [owner][target] = { n, firstAt }
		_ult = {}, -- [playerId] = { startAt, fireAt, aim }
		_shots = {}, -- Bullseye 고속탄 목록
		_serial = 0,
		_lastNow = 0,
	}, SlingshotSkills)
	deps.projectiles:onEvent(function(e)
		self:_onProjectileEvent(e)
	end)
	return self
end

function SlingshotSkills:isBusy(id)
	return self._ult[id] ~= nil
end

function SlingshotSkills:onDodge(_id, _now) end

-- 대상이 죽거나 나가면 그 대상에 걸린 표식·카운트를 모든 소유자에서 지운다
function SlingshotSkills:onTargetGone(targetId)
	for _, byTarget in self._marks do
		byTarget[targetId] = nil
	end
	for _, byTarget in self._counts do
		byTarget[targetId] = nil
	end
end

function SlingshotSkills:reset(id, now, _reason)
	self._life[id] = (self._life[id] or 0) + 1
	self._charge[id] = nil
	self._marks[id] = nil
	self._counts[id] = nil
	if self._ult[id] then
		self._ult[id] = nil
		self._d.emit({ type = "CharSkill", cue = "sling.ult.end", skill = "Bullseye", phase = "End", playerId = id, time = now or self._lastNow })
	end
	self._d.setSlow(id, 0, 1)
end

-- 경기 경계(MatchSession): 비행 중인 Bullseye 탄·충전·표식·조준을 모두 버린다.
function SlingshotSkills:clearAll(now)
	self._shots = {}
	table.clear(self._charge)
	table.clear(self._ult)
	table.clear(self._marks)
	table.clear(self._counts)
	table.clear(self._tags)
	for id in self._life do
		self._life[id] += 1
		self._d.setSlow(id, 0, 1)
	end
end

local function aimOf(payload, pose)
	local a = payload and payload.aimDirection
	return (a and Vec.normalize(a)) or Vec.normalize(pose.forward) or { X = 0, Y = 0, Z = -1 }
end

function SlingshotSkills:_eye(pose)
	return Vec.add(pose.pos, { X = 0, Y = self._cfg.Combat.EyeHeight, Z = 0 })
end

function SlingshotSkills:_capacityFor(id, n)
	local lim = self._cfg.Projectile
	local ps = self._d.projectiles
	return ps:getActiveCount(id) + n <= lim.MaxActivePerOwner and ps:getActiveCount() + n <= lim.MaxActiveTotal
end

-- 한 발 발사(에임 보조 없음). 반환: projectileId | nil, reason
function SlingshotSkills:_shoot(id, origin, dir, kind, shot, damage, speed, lifetime, now, effects)
	local def = {
		id = "sling_" .. kind, type = "Arc", collision = { mode = "Spherecast", radius = shot.radius },
		speed = speed, gravity = shot.gravity, lifetime = lifetime, maxRange = math.min(5000, speed * lifetime + 5), damage = damage, rehitInterval = 0,
	}
	local pid, err = self._d.projectiles:spawn({
		def = def, ownerId = id, origin = origin, direction = Hitbox.rangedDirection(dir), effects = effects,
	}, now)
	if pid then
		self._tags[pid] = { owner = id, kind = kind, life = self._life[id] or 0 }
	end
	return pid, err
end

-- ── 패시브 Bullseye Mark ────────────────────────────────────
function SlingshotSkills:_activeMark(owner, target, time)
	local m = self._marks[owner]
	local untilT = m and m[target]
	if untilT and untilT > time + EPS then
		return untilT
	end
	if m and untilT then
		m[target] = nil
	end
	return nil
end

-- LMB 샷이 실제로 피해를 준 경우. 표식 대상이면 +8 후 표식 소모, 아니면 카운트를 올려 2회째에 표식 생성.
function SlingshotSkills:_onLmbHit(tag, targetId, pid, time)
	local owner = tag.owner
	if tag.life ~= (self._life[owner] or 0) then
		return
	end
	local st = self._d.state(owner)
	if not st or not st.alive or st.characterId ~= ID or targetId == owner then
		return
	end
	local p = self._def.passive
	if self:_activeMark(owner, targetId, time) then
		self._marks[owner][targetId] = nil -- 표식 소모(다른 대상의 표식은 건드리지 않는다)
		if self._counts[owner] then
			self._counts[owner][targetId] = nil
		end
		local r = self._core.damage:applyDamage({
			attackerId = owner, targetId = targetId, attackId = tostring(pid) .. "#mark", amount = p.bonusDamage, kind = "Projectile", blockable = false,
		}, time)
		self._d.emit({ type = "CharSkill", cue = "sling.mark.proc", skill = "BullseyeMark", playerId = owner, targetId = targetId, bonus = r.applied and r.amount or 0, time = time })
		return
	end
	local counts = self._counts[owner]
	if not counts then
		counts = {}
		self._counts[owner] = counts
	end
	local c = counts[targetId]
	if c and time - c.firstAt > p.countWindow then
		c = nil
	end
	if not c then
		c = { n = 0, firstAt = time }
		counts[targetId] = c
	end
	c.n += 1
	if c.n >= p.hitsToMark then
		counts[targetId] = nil
		self._marks[owner] = self._marks[owner] or {}
		self._marks[owner][targetId] = time + p.markSeconds
		self._d.emit({ type = "CharSkill", cue = "sling.mark", skill = "BullseyeMark", playerId = owner, targetId = targetId, markUntil = time + p.markSeconds, time = time })
	end
end

function SlingshotSkills:_onProjectileEvent(e)
	if e.type == "Hit" then
		local tag = self._tags[e.projectileId]
		if tag and e.result and e.result.applied then
			if tag.kind == "Lmb" then
				self:_onLmbHit(tag, e.targetId, e.projectileId, e.time)
			elseif tag.kind == "Snare" then
				local pos
				for _, t in self._d.targets() do
					if t.id == e.targetId then
						pos = t.pos
					end
				end
				self._d.emit({ type = "CharSkill", cue = "sling.snare.mark", skill = "SnareShot", playerId = tag.owner, targetId = e.targetId, pos = pos, time = e.time })
			end
		end
	elseif e.type == "Ended" then
		self._tags[e.projectileId] = nil
	end
end

-- ── LMB 충전 샷 (Press = 충전 시작, Release = 발사) ───────────
function SlingshotSkills:_fireCharged(id, pose, dir, charge, now)
	local prim = self._def.primary
	local sh = prim.shot
	local damage = prim.minDamage + (prim.maxDamage - prim.minDamage) * charge
	local speed = sh.speedMin + (sh.speedMax - sh.speedMin) * charge
	local lifetime = sh.lifetimeMin + (sh.lifetimeMax - sh.lifetimeMin) * charge
	if not self:_capacityFor(id, 1) then
		return false, "too_many_projectiles"
	end
	local pid, err = self:_shoot(id, self:_eye(pose), dir, "Lmb", sh, damage, speed, lifetime, now)
	if not pid then
		return false, err
	end
	self._core.cooldown:start(id, "primary", prim.fireInterval, now)
	self._d.stopRunning(id)
	self._d.approve(id, prim, now)
	self._d.emit({ type = "CharSkill", cue = "sling.shot", skill = "ChargedShot", playerId = id, projectileId = pid, charge = charge, damage = damage, time = now })
	return true, { projectileId = pid, charge = charge, damage = damage, speed = speed }
end

function SlingshotSkills:primary(id, payload, pose, now)
	local prim = self._def.primary
	local phase = payload.phase
	local dir = aimOf(payload, pose)
	if self._ult[id] then
		return false, "ultimate_aiming" -- Bullseye 조준 중에는 다른 사격 불가
	end
	if phase == "Release" then
		local c = self._charge[id]
		if not c then
			return false, "not_charging"
		end
		self._charge[id] = nil
		self._d.setSlow(id, 0, 1)
		local held = now - c.startAt
		if held > prim.maxHoldSeconds then
			return false, "charge_expired"
		end
		if not self._core.cooldown:isReady(id, "primary", now) then
			return false, "on_cooldown"
		end
		return self:_fireCharged(id, self._d.getPose(id) or pose, dir, math.clamp(held / prim.chargeSeconds, 0, 1), now)
	end
	if not self._core.cooldown:isReady(id, "primary", now) then
		return false, "on_cooldown"
	end
	if phase == "Press" then
		if self._charge[id] then
			return false, "already_charging"
		end
		self._charge[id] = { startAt = now }
		self._d.setSlow(id, now + prim.maxHoldSeconds, prim.chargeMoveMult)
		self._d.emit({ type = "CharSkill", cue = "sling.charge", skill = "ChargedShot", phase = "Charge", playerId = id, time = now, chargeSeconds = prim.chargeSeconds })
		return true, { charging = true }
	end
	return self:_fireCharged(id, pose, dir, 0, now) -- phase 생략 = 즉시(충전 0) 발사
end

-- RMB Aim Mode 는 클라이언트 표시 전용이다. 서버 상태·자원을 건드리지 않는다.
function SlingshotSkills:secondary(_id, _payload, _pose, _now)
	return false, "client_only"
end

-- ── 스킬 1·2·3 ──────────────────────────────────────────────
function SlingshotSkills:_triple(id, payload, pose, now)
	local d = self._def.skills[1]
	if not self._core.cooldown:isReady(id, "skill1", now) then
		return false, "on_cooldown"
	end
	if not self:_capacityFor(id, d.shots) then
		return false, "too_many_projectiles"
	end
	local dir = aimOf(payload, pose)
	local origin = self:_eye(pose)
	local ids = {}
	for i = 1, d.shots do
		local off = d.spread[i] or { 0, 0 }
		local pid = self:_shoot(id, origin, Geometry.spread(dir, off[1], off[2]), "Triple", d.shot, d.damage, d.shot.speed, d.shot.lifetime, now)
		if pid then
			table.insert(ids, pid)
		end
	end
	if #ids == 0 then
		return false, "spawn_failed"
	end
	self._core.cooldown:start(id, "skill1", d.cooldown, now)
	self._d.approve(id, d, now)
	self._d.emit({ type = "CharSkill", cue = "sling.triple", skill = "TripleShot", playerId = id, projectileIds = ids, time = now })
	return true, { projectileIds = ids }
end

function SlingshotSkills:_snare(id, payload, pose, now)
	local d = self._def.skills[2]
	if not self._core.cooldown:isReady(id, "skill2", now) then
		return false, "on_cooldown"
	end
	if not self:_capacityFor(id, 1) then
		return false, "too_many_projectiles"
	end
	local pid, err = self:_shoot(id, self:_eye(pose), aimOf(payload, pose), "Snare", d.shot, d.damage, d.shot.speed, d.shot.lifetime, now, {
		{ type = "Slow", multiplier = d.slowMult, duration = d.slowSeconds },
	})
	if not pid then
		return false, err
	end
	self._core.cooldown:start(id, "skill2", d.cooldown, now)
	self._d.approve(id, d, now)
	self._d.emit({ type = "CharSkill", cue = "sling.snare", skill = "SnareShot", playerId = id, projectileId = pid, time = now })
	return true, { projectileId = pid }
end

-- Backstep Shot: 조준 반대 수평 방향으로 후방 이동(서버 이동 허가 + 벽 충돌) 하면서 조준 방향으로 사격. 거부되면 사격·쿨타임 모두 없음.
function SlingshotSkills:_backstep(id, payload, pose, now)
	local d = self._def.skills[3]
	if not self._core.cooldown:isReady(id, "skill3", now) then
		return false, "on_cooldown"
	end
	local aim = aimOf(payload, pose)
	local back = Vec.flatten(Vec.scale(aim, -1)) or Vec.flatten(Vec.scale(pose.forward, -1)) or { X = 0, Y = 0, Z = 1 }
	local dist = d.distance
	local world = self._d.world
	if world.cast then
		local mc = self._cfg.MoveCheck
		local hit = world.cast(pose.pos, Vec.add(pose.pos, Vec.scale(back, dist)), mc.BodyRadius)
		if hit then
			dist = math.max(0, hit.fraction * dist - mc.WallSkin)
		end
	end
	if dist < d.minDistance then
		return false, "blocked"
	end
	if not self:_capacityFor(id, 1) then
		return false, "too_many_projectiles"
	end
	local speed = dist / d.duration
	if self._d.movement then
		local ok, why = self._d.movement:issue(id, d.permit, now, { speed = speed, duration = d.duration, dir = back })
		if not ok then
			return false, "movement_denied:" .. tostring(why)
		end
	end
	local pid, err = self:_shoot(id, self:_eye(pose), aim, "Backstep", d.shot, d.damage, d.shot.speed, d.shot.lifetime, now)
	if not pid then
		return false, err
	end
	self._core.cooldown:start(id, "skill3", d.cooldown, now)
	self._d.approve(id, d, now)
	self._d.emit({
		type = "CharSkill", cue = "sling.backstep", skill = "BackstepShot", playerId = id, projectileId = pid, direction = back, distance = dist,
		dash = { speed = speed, duration = d.duration, permit = d.permit }, time = now,
	})
	return true, { projectileId = pid, distance = dist }
end

function SlingshotSkills:skill(id, slot, payload, pose, now)
	if payload.phase == "Release" then
		return false, "not_charging"
	end
	if self._ult[id] then
		return false, "ultimate_aiming"
	end
	if slot == 1 then
		return self:_triple(id, payload, pose, now)
	elseif slot == 2 then
		return self:_snare(id, payload, pose, now)
	elseif slot == 3 then
		return self:_backstep(id, payload, pose, now)
	end
	return false, "skill_not_implemented"
end

-- ── 궁극기 Bullseye ─────────────────────────────────────────
function SlingshotSkills:canUltimate(id, _payload, _pose, _now)
	if self._ult[id] then
		return false, "already_active"
	end
	return true
end

function SlingshotSkills:ultimateDef(id, _now)
	return {
		duration = self._def.ultimate.duration,
		onEnd = function(reason)
			if self._ult[id] then
				self._ult[id] = nil
				self._d.emit({ type = "CharSkill", cue = "sling.ult.end", skill = "Bullseye", phase = "End", playerId = id, reason = reason, time = self._lastNow })
			end
		end,
	}
end

function SlingshotSkills:startUltimate(id, payload, pose, now)
	local u = self._def.ultimate
	self._lastNow = now
	self._charge[id] = nil -- 충전 중이던 샷은 취소
	self._d.setSlow(id, 0, 1)
	self._ult[id] = { startAt = now, fireAt = now + u.windup, aim = aimOf(payload, pose) }
	self._d.stopRunning(id)
	self._d.emit({ type = "CharSkill", cue = "sling.ult.windup", skill = "Bullseye", phase = "Windup", playerId = id, time = now, windup = u.windup })
end

-- Aim 리모트: 조준 중 방향 갱신. 에임 보조 없음.
function SlingshotSkills:onAim(id, dir, _now)
	local u = self._ult[id]
	if not u then
		return false
	end
	local n = Vec.normalize(dir)
	if not n then
		return false
	end
	u.aim = n
	return true
end

function SlingshotSkills:_fireBullseye(id, u, now)
	local d = self._def.ultimate
	local pose = self._d.getPose(id)
	self._ult[id] = nil
	if not pose then
		return
	end
	self._serial += 1
	local origin = self:_eye(pose)
	table.insert(self._shots, {
		serial = self._serial, owner = id, origin = origin, pos = origin, dir = u.aim, t = u.fireAt,
		expireAt = u.fireAt + d.lifetime, traveled = 0,
	})
	self._d.emit({
		type = "CharSkill", cue = "sling.ult.fire", skill = "Bullseye", phase = "Fire", playerId = id, origin = origin, dir = u.aim, speed = d.speed, time = now,
		tip = Vec.add(origin, Vec.scale(u.aim, d.range)), -- 연출용 궤적 끝(벽에서 잘리는 보정은 Studio 에서 확인)
	})
end

-- 고속탄 한 단계 전진: 이전→새 위치 선분 전체를 스윕한다(터널링 없음). 반환: 끝났는가
function SlingshotSkills:_stepShot(s, to)
	local d = self._def.ultimate
	local maxStep = self._cfg.Projectile.MaxStepSeconds
	local guard = 0
	while s.t < to - EPS and guard < 64 do
		guard += 1
		local t1 = math.min(to, s.expireAt, s.t + maxStep)
		local len = math.min(d.speed * (t1 - s.t), d.range - s.traveled)
		if len <= 1e-9 then
			return true
		end
		local p0 = s.pos
		local p1 = Vec.add(p0, Vec.scale(s.dir, len))
		local world = self._d.world
		local wallHit = world.cast and world.cast(p0, p1, d.shotRadius)
		if wallHit then
			p1 = Geometry.lerp(p0, p1, wallHit.fraction)
		end
		local best, bestF
		for _, tg in self._d.targets() do
			if tg.id ~= s.owner and tg.alive ~= false then
				local f = Geometry.segmentSphere(p0, p1, tg.pos, (tg.radius or self._cfg.Combat.HitRadius) + d.shotRadius)
				if f and (bestF == nil or f < bestF) then
					best, bestF = tg, f
				end
			end
		end
		if best then
			local time = s.t + (t1 - s.t) * bestF
			-- 정밀 판정: 사선이 대상 표준 몸통 중심에서 preciseRadius 안을 지나는가(머리 판정 아님)
			local rel = Vec.sub(best.pos, s.origin)
			local perp = Vec.len(Vec.cross(rel, s.dir))
			local precise = perp <= d.preciseRadius
			local r = self._core.damage:applyDamage({
				attackerId = s.owner, targetId = best.id, attackId = string.format("bull%d", s.serial), amount = precise and d.preciseDamage or d.damage,
				kind = "Projectile", blockable = true, sourceDir = Vec.scale(s.dir, -1),
			}, time)
			if r.applied or r.reason == "parried" then
				self._d.emit({
					type = "CharSkill", cue = precise and "sling.ult.precise" or "sling.ult.hit", skill = "Bullseye", phase = "Hit", playerId = s.owner,
					targetId = best.id, precise = precise, amount = r.applied and r.amount or 0, time = time,
				})
				return true
			end
			-- 회피 무적·보호 중이면 통과(투사체 소모 없음)
		end
		s.pos = p1
		s.traveled += Vec.dist(p0, p1)
		s.t = t1
		if wallHit then
			return true
		end
		if s.traveled >= d.range - 1e-9 or s.t >= s.expireAt - EPS then
			return true
		end
	end
	return false
end

function SlingshotSkills:update(now)
	self._lastNow = now
	for id, u in table.clone(self._ult) do
		if self._ult[id] == u and now + 1e-9 >= u.fireAt then
			self:_fireBullseye(id, u, now)
		end
	end
	local alive = {}
	for _, s in self._shots do
		if not self:_stepShot(s, now) then
			table.insert(alive, s)
		end
	end
	self._shots = alive
	for id, c in table.clone(self._charge) do
		if now - c.startAt > self._def.primary.maxHoldSeconds + 0.5 then
			self._charge[id] = nil
			self._d.setSlow(id, 0, 1)
		end
	end
	for _, byTarget in self._marks do
		for target, untilT in byTarget do
			if untilT <= now then
				byTarget[target] = nil
			end
		end
	end
end

function SlingshotSkills:hudInfo(id, now)
	local cd = self._core.cooldown
	local sk = self._def.skills
	local c = self._charge[id]
	local u = self._ult[id]
	local marks = {}
	for target, untilT in self._marks[id] or {} do
		if untilT > now then
			table.insert(marks, { targetId = target, untilT = untilT })
		end
	end
	local function entry(i)
		return { implemented = true, name = sk[i].name, readyAt = cd:readyAt(id, "skill" .. i) or 0, total = sk[i].cooldown }
	end
	return {
		skills = { entry(1), entry(2), entry(3) },
		passive = { id = self._def.passive.id, lockedUntil = 0 },
		ultimate = { name = self._def.ultimate.name, active = u ~= nil, windupUntil = u and u.fireAt or nil },
		extra = {
			chargeFrac = c and math.clamp((now - c.startAt) / self._def.primary.chargeSeconds, 0, 1) or nil,
			marks = marks,
		},
	}
end

return SlingshotSkills
