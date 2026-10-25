--!nonstrict
-- SUPERBALL 전용 서버 로직(Phase 2): LMB Super Throw(충전), RMB Bounce Dash, 스킬 1~3, 궁극기 Ball Cyclone, 패시브 Trick Master.
-- 볼 비행·튕김·귀환·공전은 BallService 가 시뮬레이션하고, 이 모듈은 요청 검증·자원·쿨타임·볼 총량(12) 관리·패시브를 맡는다.
-- 수치: shared/Data/Characters.SUPERBALL (확정/임시 구분은 그 파일 주석과 docs/ASSUMPTIONS.md A72~A75).
-- deps 형태는 PaintballSkills 와 동일하다.
local Link = require(script.Parent.Link)
local Vec = Link.shared("Vec")
local Geometry = require(script.Parent.Geometry)
local BallService = require(script.Parent.BallService)

local SuperballSkills = {}
SuperballSkills.__index = SuperballSkills

local ID = "SUPERBALL"

function SuperballSkills.new(deps)
	local chars = deps.characters or Link.shared("Data/Characters")
	local self = setmetatable({
		_d = deps,
		_cfg = deps.cfg,
		_core = deps.core,
		_def = chars.SUPERBALL,
		_life = {}, -- [playerId] = 생애 번호(부활/캐릭터 변경/퇴장 때 증가 → 이전 생애 볼의 패시브 무효)
		_charge = {}, -- [playerId] = { startAt }
		_lock = {}, -- [playerId] = Trick Master 재발동 가능 시각
		_dash = {}, -- [playerId] = 대시 종료 시각(표시용)
		_ult = {}, -- [playerId] = { startAt, endAt, nextShot, serial }
		_counter = 0,
		_lastNow = 0,
	}, SuperballSkills)
	self.balls = BallService.new({
		config = deps.cfg,
		damage = deps.core.damage,
		targets = deps.targets,
		world = deps.world,
		getPose = deps.getPose,
		emit = deps.emit,
		onHit = function(ball, targetId, result, time)
			self:_onBallHit(ball, targetId, result, time)
		end,
	})
	return self
end

function SuperballSkills:isBusy(_id)
	return false
end

function SuperballSkills:onDodge(_id, _now) end

function SuperballSkills:onTargetGone(_targetId) end

local function aimOf(payload, pose)
	local a = payload and payload.aimDirection
	return (a and Vec.normalize(a)) or Vec.normalize(pose.forward) or { X = 0, Y = 0, Z = -1 }
end

function SuperballSkills:_eye(pose)
	return Vec.add(pose.pos, { X = 0, Y = self._cfg.Combat.EyeHeight, Z = 0 })
end

local function isUlt(b)
	return b.ultimate
end
local function isNormal(b)
	return not b.ultimate
end

-- 사망·부활·캐릭터 변경·퇴장: 충전·궁극기 정리, 설치물 개념이 없으므로 볼은 모두 제거한다(서버/클라이언트 상태 일치: BallEnd 이벤트).
function SuperballSkills:reset(id, now, _reason)
	self._life[id] = (self._life[id] or 0) + 1
	self._charge[id] = nil
	self._lock[id] = nil
	self._dash[id] = nil
	if self._ult[id] then
		self._ult[id] = nil
		self._d.emit({ type = "CharSkill", cue = "ball.cyclone.end", skill = "BallCyclone", phase = "End", playerId = id, time = now or self._lastNow })
	end
	self.balls:removeWhere(id, nil, "OwnerReset", now or self._lastNow)
end

-- ── 볼 총량(12) ─────────────────────────────────────────────
-- 일반 볼이 들어갈 수 있는 슬롯 수(궁극기 볼은 밀어내지 못한다).
function SuperballSkills:_normalSlots(id)
	return math.max(0, self._def.ballCap - self.balls:count(id, isUlt))
end

-- n 개의 일반 볼을 위한 공간을 만든다: 총량을 넘으면 가장 오래된 일반 볼부터 제거. 반환: 실제로 만들 수 있는 개수
function SuperballSkills:_makeRoom(id, n, now)
	local allowed = math.min(n, self:_normalSlots(id))
	if allowed <= 0 then
		return 0
	end
	local over = self.balls:count(id) + allowed - self._def.ballCap
	if over > 0 then
		self.balls:evictOldest(id, over, isNormal, now)
	end
	return allowed
end

function SuperballSkills:_spawnNormal(id, pose, dir, spec, damage, now)
	return self.balls:spawn({
		owner = id, life = self._life[id] or 0, kind = "Normal", pos = self:_eye(pose), dir = dir, speed = spec.speed, gravity = spec.gravity,
		radius = spec.radius, damage = damage, bounces = spec.bounces, lifetime = spec.lifetime, restitution = spec.restitution, now = now,
	})
end

-- ── 패시브 Trick Master ─────────────────────────────────────
-- 지형에서 1회 이상 튕긴 볼이 적에게 실제 피해를 준 경우(귀환 적중 포함). 쿨타임이 남은 스킬 1~3 중 가장 긴 것을 0.5초 줄이고 1초간 재발동 불가.
-- 줄일 대상이 없으면 발동도 잠금도 없다(A73). 이전 생애의 볼·죽은 소유자·다른 캐릭터로 바뀐 소유자는 무효.
function SuperballSkills:_onBallHit(ball, targetId, result, time)
	if not (result and result.applied) or targetId == ball.owner or (ball.bounces or 0) < 1 then
		return
	end
	local owner = ball.owner
	if ball.life ~= (self._life[owner] or 0) then
		return
	end
	local st = self._d.state(owner)
	if not st or not st.alive or st.characterId ~= ID then
		return
	end
	if time < (self._lock[owner] or 0) then
		return
	end
	local cd = self._core.cooldown
	local bestKey, bestRem = nil, 0
	for i = 1, 3 do
		local key = "skill" .. i
		local rem = cd:remaining(owner, key, time)
		if rem > bestRem + 1e-9 then
			bestKey, bestRem = key, rem
		end
	end
	if not bestKey then
		return
	end
	local p = self._def.passive
	local amount = math.min(p.reduceSeconds, bestRem)
	cd:reduce(owner, bestKey, amount, time)
	self._lock[owner] = time + p.lockSeconds
	self._d.emit({
		type = "CharSkill", cue = "ball.trick", skill = "TrickMaster", playerId = owner, targetId = targetId, reducedKey = bestKey,
		reduced = amount, time = time,
	})
end

-- ── LMB Super Throw (Press = 충전 시작, Release = 던지기) ──────
function SuperballSkills:_throw(id, pose, dir, charged, now)
	local prim = self._def.primary
	local spec = charged and prim.charged or prim.normal
	if self:_makeRoom(id, 1, now) < 1 then
		return false, "no_ball_slot"
	end
	local b = self:_spawnNormal(id, pose, dir, spec, charged and prim.chargedDamage or prim.damage, now)
	self._core.cooldown:start(id, "primary", prim.fireInterval, now)
	self._d.stopRunning(id)
	self._d.approve(id, prim, now)
	self._d.emit({ type = "CharSkill", cue = charged and "ball.throw.charged" or "ball.throw", skill = "SuperThrow", playerId = id, ballId = b.id, charged = charged, time = now })
	return true, { ballId = b.id, charged = charged, damage = b.damage }
end

function SuperballSkills:_fireCyclone(id, pose, dir, now)
	local u = self._ult[id]
	local def = self._def.ultimate
	if now < (u.nextShot or 0) then
		return false, "on_cooldown"
	end
	local orbit = self.balls:list(id, function(b)
		return b.ultimate and b.mode == "Orbit"
	end)
	-- 조준 방향 앞쪽(수평)에 가장 가까이 있는 공전 볼을 쏜다: 조준선과 발사 위치가 크게 어긋나지 않게 한다.
	local ball, bestDot = nil, -math.huge
	local aimFlat = Vec.flatten(dir) or { X = 0, Y = 0, Z = 1 }
	for _, b in orbit do
		local rel = Vec.sub(b.pos, pose.pos)
		local d = rel.X * aimFlat.X + rel.Z * aimFlat.Z
		if d > bestDot then
			ball, bestDot = b, d
		end
	end
	if not ball then
		return false, "no_orbit_ball"
	end
	local sh = def.shot
	-- 공전 → 비행 전환: 같은 볼이 현재 위치에서 조준 방향으로 나간다(총량·궁극기 소속 유지)
	ball.mode = "Fly"
	ball.kind = "CycloneShot"
	ball.orbit = nil
	ball.vel = Vec.scale(dir, sh.speed)
	ball.gravity = sh.gravity
	ball.radius = sh.radius
	ball.damage = def.shotDamage
	ball.bouncesLeft = sh.bounces
	ball.restitution = sh.restitution
	ball.stage += 1
	ball.expireAt = now + sh.lifetime
	ball.t = now
	ball.inside = {}
	u.nextShot = now + def.shotInterval
	self._d.stopRunning(id)
	self._d.approve(id, { kind = "Projectile", damage = def.shotDamage }, now)
	self._d.emit({
		type = "BallMode", ballId = ball.id, ownerId = id, mode = "Fly", pos = ball.pos, vel = ball.vel, gravity = ball.gravity, lifetime = sh.lifetime, time = now,
	})
	self._d.emit({ type = "CharSkill", cue = "ball.cyclone.shot", skill = "BallCyclone", phase = "Shot", playerId = id, ballId = ball.id, time = now })
	return true, { ballId = ball.id, damage = def.shotDamage }
end

function SuperballSkills:primary(id, payload, pose, now)
	local prim = self._def.primary
	local phase = payload.phase
	local dir = aimOf(payload, pose)
	if phase == "Release" then
		local c = self._charge[id]
		if not c then
			return false, "not_charging" -- 중복/늦은 Release: 아무 일도 일어나지 않는다
		end
		self._charge[id] = nil
		self._d.setSlow(id, 0, 1)
		local held = now - c.startAt
		if held > prim.maxHoldSeconds then
			return false, "charge_expired" -- 너무 오래 쥔 충전은 취소(쿨타임·보호 영향 없음)
		end
		if not self._core.cooldown:isReady(id, "primary", now) then
			return false, "on_cooldown"
		end
		return self:_throw(id, self._d.getPose(id) or pose, dir, held >= prim.chargeSeconds - 1e-6, now)
	end
	if self._ult[id] then
		return self:_fireCyclone(id, pose, dir, now)
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
		self._d.emit({ type = "CharSkill", cue = "ball.charge", skill = "SuperThrow", phase = "Charge", playerId = id, time = now, chargeSeconds = prim.chargeSeconds })
		return true, { charging = true }
	end
	return self:_throw(id, pose, dir, false, now) -- phase 생략 = 즉시 일반 던지기
end

-- ── RMB Bounce Dash ─────────────────────────────────────────
function SuperballSkills:secondary(id, payload, pose, now)
	local d = self._def.secondary
	if not self._core.cooldown:isReady(id, "secondary", now) then
		return false, "on_cooldown"
	end
	local dir = Vec.flatten(aimOf(payload, pose)) or Vec.flatten(pose.forward) or { X = 0, Y = 0, Z = -1 }
	local dist = d.distance
	local world = self._d.world
	if world.cast then
		local mc = self._cfg.MoveCheck
		local hit = world.cast(pose.pos, Vec.add(pose.pos, Vec.scale(dir, dist)), mc.BodyRadius)
		if hit then
			dist = math.max(0, hit.fraction * dist - mc.WallSkin)
		end
	end
	if dist < d.minDistance then
		return false, "blocked"
	end
	local speed = dist / d.duration
	if self._d.movement then
		local ok, why = self._d.movement:issue(id, d.permit, now, { speed = speed, duration = d.duration, dir = dir })
		if not ok then
			return false, "movement_denied:" .. tostring(why)
		end
	end
	self._core.cooldown:start(id, "secondary", d.cooldown, now)
	self._dash[id] = now + d.duration
	self._d.approve(id, d, now) -- 판정 없는 이동기 → 비공격: 부활 보호 유지
	self._d.emit({
		type = "CharSkill", cue = "ball.dash", skill = "BounceDash", playerId = id, direction = dir, distance = dist,
		dash = { speed = speed, duration = d.duration, permit = d.permit }, time = now,
	})
	return true, { distance = dist, speed = speed }
end

-- ── 스킬 1·2·3 ──────────────────────────────────────────────
function SuperballSkills:_volley(id, slot, payload, pose, now)
	local d = self._def.skills[slot]
	local key = "skill" .. slot
	if not self._core.cooldown:isReady(id, key, now) then
		return false, "on_cooldown"
	end
	local n = self:_makeRoom(id, d.balls, now)
	if n < 1 then
		return false, "no_ball_slot"
	end
	local dir = aimOf(payload, pose)
	local ids = {}
	for i = 1, n do
		local off = d.spread[i] or { 0, 0 }
		local b = self:_spawnNormal(id, pose, Geometry.spread(dir, off[1], off[2]), d.ball, d.damage, now)
		table.insert(ids, b.id)
	end
	self._core.cooldown:start(id, key, d.cooldown, now)
	self._d.approve(id, d, now)
	self._d.emit({
		type = "CharSkill", cue = slot == 1 and "ball.rapid" or "ball.scatter", skill = d.id, playerId = id, ballIds = ids, time = now,
	})
	return true, { ballIds = ids }
end

function SuperballSkills:_recall(id, _payload, _pose, now)
	local d = self._def.skills[3]
	if not self._core.cooldown:isReady(id, "skill3", now) then
		return false, "on_cooldown"
	end
	local targets = self.balls:list(id, function(b)
		return not b.ultimate and b.mode == "Fly"
	end)
	if #targets == 0 then
		return false, "nothing_to_recall" -- 쿨타임 소모 없음
	end
	local n = 0
	for _, b in targets do
		if self.balls:recall(b, d.returnSpeed, d.damage, now) then
			n += 1
		end
	end
	self._core.cooldown:start(id, "skill3", d.cooldown, now)
	self._d.approve(id, d, now)
	self._d.emit({ type = "CharSkill", cue = "ball.recall", skill = "Recall", playerId = id, count = n, time = now })
	return true, { recalled = n }
end

function SuperballSkills:skill(id, slot, payload, pose, now)
	if payload.phase == "Release" then
		return false, "not_charging"
	end
	if slot == 1 or slot == 2 then
		return self:_volley(id, slot, payload, pose, now)
	elseif slot == 3 then
		return self:_recall(id, payload, pose, now)
	end
	return false, "skill_not_implemented"
end

-- ── 궁극기 Ball Cyclone ─────────────────────────────────────
function SuperballSkills:canUltimate(id, _payload, _pose, _now)
	if self._ult[id] then
		return false, "already_active"
	end
	return true
end

function SuperballSkills:ultimateDef(id, _now)
	local u = self._def.ultimate
	return {
		duration = u.duration,
		onEnd = function(reason)
			if self._ult[id] then
				self._ult[id] = nil
				self.balls:removeWhere(id, isUlt, "CycloneEnd", self._lastNow)
				self._d.emit({ type = "CharSkill", cue = "ball.cyclone.end", skill = "BallCyclone", phase = "End", playerId = id, reason = reason, time = self._lastNow })
			end
		end,
	}
end

-- 게이지 소모가 성공한 뒤에만 호출된다. 총량 12 를 지키기 위해 가장 오래된 일반 볼부터 제거하고 공전 볼 10개를 만든다.
function SuperballSkills:startUltimate(id, payload, pose, now)
	local def = self._def.ultimate
	self._counter += 1
	self._lastNow = now
	self._charge[id] = nil -- 충전 중이던 던지기는 취소
	self._d.setSlow(id, 0, 1)
	local over = self.balls:count(id) + def.balls - self._def.ballCap
	if over > 0 then
		self.balls:evictOldest(id, over, isNormal, now)
	end
	self._ult[id] = { startAt = now, endAt = now + def.duration, nextShot = now, serial = self._counter }
	local ownerContact = {}
	local omega = 2 * math.pi / def.orbitSeconds
	for i = 1, def.balls do
		local phase = (i - 1) / def.balls * 2 * math.pi
		local pos = Vec.add(pose.pos, { X = math.cos(phase) * def.orbitRadius, Y = def.orbitHeight, Z = math.sin(phase) * def.orbitRadius })
		self.balls:spawn({
			owner = id, life = self._life[id] or 0, kind = "Cyclone", ultimate = true, mode = "Orbit", pos = pos, radius = 0.6, lifetime = def.duration,
			now = now, damage = def.contactDamage,
			orbit = {
				phase = phase, omega = omega, startAt = now, radius = def.orbitRadius, height = def.orbitHeight,
				contactInterval = def.contactInterval, targetInterval = def.targetInterval, contactDamage = def.contactDamage, ownerContact = ownerContact,
			},
		})
	end
	self._d.stopRunning(id)
	self._d.emit({ type = "CharSkill", cue = "ball.cyclone.start", skill = "BallCyclone", phase = "Start", playerId = id, time = now, duration = def.duration })
end

function SuperballSkills:onAim(_id, _dir, _now)
	return false
end

function SuperballSkills:update(now)
	self._lastNow = now
	self.balls:step(now)
	for id, c in table.clone(self._charge) do
		if now - c.startAt > self._def.primary.maxHoldSeconds + 0.5 then
			self._charge[id] = nil -- Release 가 오지 않은 충전 정리(느려짐 해제)
			self._d.setSlow(id, 0, 1)
		end
	end
	for id, untilT in self._dash do
		if now >= untilT then
			self._dash[id] = nil
		end
	end
end

function SuperballSkills:hudInfo(id, now)
	local cd = self._core.cooldown
	local sk = self._def.skills
	local c = self._charge[id]
	local u = self._ult[id]
	local function entry(i)
		return { implemented = true, name = sk[i].name, readyAt = cd:readyAt(id, "skill" .. i) or 0, total = sk[i].cooldown }
	end
	return {
		skills = { entry(1), entry(2), entry(3) },
		passive = { id = self._def.passive.id, lockedUntil = self._lock[id] or 0 },
		ultimate = { name = self._def.ultimate.name, active = u ~= nil },
		secondary = { readyAt = cd:readyAt(id, "secondary") or 0, total = self._def.secondary.cooldown },
		extra = {
			balls = self.balls:count(id),
			ballCap = self._def.ballCap,
			chargeFrac = c and math.clamp((now - c.startAt) / self._def.primary.chargeSeconds, 0, 1) or nil,
			cycloneUntil = u and u.endAt or nil,
		},
	}
end

return SuperballSkills
