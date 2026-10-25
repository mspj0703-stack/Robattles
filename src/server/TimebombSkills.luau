--!nonstrict
-- TIMEBOMB 전용 서버 로직(Phase 2): LMB Timed Bomb, RMB Blast Guard, 스킬 1~3, 궁극기 Big Bang, 패시브 Chain Reaction.
-- 폭탄 비행·폭발·연쇄는 BombService 가 서버 권위로 처리한다. 이 모듈은 요청 검증·충전/쿨타임·이동 허가·소유권 정리를 맡는다.
-- 수치: shared/Data/Characters.TIMEBOMB (확정/임시 구분은 그 파일 주석과 docs/ASSUMPTIONS.md A76~A78). deps 형태는 PaintballSkills 와 동일.
local Link = require(script.Parent.Link)
local Vec = Link.shared("Vec")
local BombService = require(script.Parent.BombService)

local TimebombSkills = {}
TimebombSkills.__index = TimebombSkills

local ID = "TIMEBOMB"

function TimebombSkills.new(deps)
	local chars = deps.characters or Link.shared("Data/Characters")
	local self = setmetatable({
		_d = deps,
		_cfg = deps.cfg,
		_core = deps.core,
		_def = chars.TIMEBOMB,
		_life = {}, -- [playerId] = 생애 번호
		_hold = {}, -- [playerId] = { startAt } : Remote Bomb 키 누름
		_charges = {}, -- [playerId] = { 충전 복구 시각, ... } (사용한 충전만, 각각 독립적으로 11초 뒤 복구)
		_jumpAt = {}, -- [playerId] = 마지막 Blast Jump 시각(Big Bang 원거리 투척 판정)
		_lastNow = 0,
	}, TimebombSkills)
	self.bombs = BombService.new({
		config = deps.cfg,
		damage = deps.core.damage,
		targets = deps.targets,
		world = deps.world,
		emit = deps.emit,
	})
	return self
end

function TimebombSkills:isBusy(_id)
	return false
end

function TimebombSkills:onDodge(_id, _now) end

function TimebombSkills:onTargetGone(_targetId) end

local function isPlaced(b)
	return b.placed
end

-- 사망·부활·캐릭터 변경: 설치물(원격 폭탄)과 누르기 상태 정리. 퇴장(Removed)이면 던진 폭탄도 전부 제거(폭발 없음).
function TimebombSkills:reset(id, now, reason)
	self._life[id] = (self._life[id] or 0) + 1
	self._hold[id] = nil
	self._jumpAt[id] = nil
	local t = now or self._lastNow
	self.bombs:removeWhere(id, isPlaced, "OwnerReset", t)
	if reason == "Removed" then
		self.bombs:removeWhere(id, nil, "OwnerRemoved", t)
		self._charges[id] = nil
	end
end

local function aimOf(payload, pose)
	local a = payload and payload.aimDirection
	return (a and Vec.normalize(a)) or Vec.normalize(pose.forward) or { X = 0, Y = 0, Z = -1 }
end

function TimebombSkills:_eye(pose)
	return Vec.add(pose.pos, { X = 0, Y = self._cfg.Combat.EyeHeight, Z = 0 })
end

-- ── 충전 ────────────────────────────────────────────────────
function TimebombSkills:_available(id, now)
	local d = self._def.skills[2]
	local list = self._charges[id]
	if not list then
		return d.charges
	end
	local keep = {}
	for _, at in list do
		if at > now + 1e-9 then
			table.insert(keep, at)
		end
	end
	self._charges[id] = keep
	return d.charges - #keep, keep
end

-- ── 투척 공통 ───────────────────────────────────────────────
function TimebombSkills:_throw(id, pose, dir, kind, spec, throwSpec, now)
	return self.bombs:spawn({
		owner = id, life = self._life[id] or 0, kind = kind, pos = self:_eye(pose), dir = dir, speed = spec.speed, gravity = spec.gravity,
		radius = spec.bombRadius, now = now,
		explosion = throwSpec.explosion, explodeAt = throwSpec.explodeAt, fuseAfterLand = throwSpec.fuseAfterLand, expireAt = throwSpec.expireAt,
		placed = throwSpec.placed, chainTarget = throwSpec.chainTarget, onExplode = throwSpec.onExplode,
	})
end

-- ── LMB Timed Bomb ──────────────────────────────────────────
function TimebombSkills:primary(id, payload, pose, now)
	local prim = self._def.primary
	if not self._core.cooldown:isReady(id, "primary", now) then
		return false, "on_cooldown"
	end
	local b, err = self:_throw(id, pose, aimOf(payload, pose), "Timed", prim.bomb, {
		explosion = { radius = prim.radius, damage = prim.damage, falloffMin = prim.falloffMin },
		explodeAt = now + prim.fuse,
	}, now)
	if not b then
		return false, err
	end
	self._core.cooldown:start(id, "primary", prim.fireInterval, now)
	self._d.stopRunning(id)
	self._d.approve(id, prim, now)
	self._d.emit({ type = "CharSkill", cue = "bomb.throw", skill = "TimedBomb", playerId = id, bombId = b.id, time = now })
	return true, { bombId = b.id, explodeAt = b.explodeAt }
end

-- ── RMB Blast Guard ─────────────────────────────────────────
function TimebombSkills:secondary(id, payload, pose, now)
	local d = self._def.secondary
	if not self._core.cooldown:isReady(id, "secondary", now) then
		return false, "on_cooldown"
	end
	local aim = aimOf(payload, pose)
	local back = Vec.flatten(Vec.scale(aim, -1)) or Vec.flatten(Vec.scale(pose.forward, -1)) or { X = 0, Y = 0, Z = 1 }
	local r = d.recoil
	local dist = r.distance
	local world = self._d.world
	if world.cast then
		local mc = self._cfg.MoveCheck
		local hit = world.cast(pose.pos, Vec.add(pose.pos, Vec.scale(back, dist)), mc.BodyRadius)
		if hit then
			dist = math.max(0, hit.fraction * dist - mc.WallSkin)
		end
	end
	local recoil -- 벽에 막혀 반동 거리가 너무 짧으면 반동만 생략하고 폭발(방어)은 그대로 한다
	if dist >= r.minDistance then
		local speed = dist / r.duration
		if self._d.movement then
			local ok, why = self._d.movement:issue(id, r.permit, now, { speed = speed, duration = r.duration, dir = back })
			if not ok then
				return false, "movement_denied:" .. tostring(why)
			end
		end
		recoil = { speed = speed, duration = r.duration, permit = r.permit }
	end
	self._core.cooldown:start(id, "secondary", d.cooldown, now)
	local center = Vec.add(pose.pos, { X = 0, Y = 1, Z = 0 })
	local results = self.bombs:blast(id, center, d, now, string.format("bg_%s_%s", tostring(id), tostring(self._d.nextAttackId(id))))
	self._d.approve(id, d, now)
	self._d.emit({
		type = "CharSkill", cue = "bomb.guard", skill = "BlastGuard", playerId = id, pos = center, radius = d.radius, direction = back,
		dash = recoil, distance = recoil and recoil.speed * recoil.duration or 0, time = now,
	})
	self.bombs:chainFrom(id, center, now)
	return true, { results = results, recoil = recoil }
end

-- ── 스킬 1 Cluster Bomb ─────────────────────────────────────
function TimebombSkills:_cluster(id, payload, pose, now)
	local d = self._def.skills[1]
	if not self._core.cooldown:isReady(id, "skill1", now) then
		return false, "on_cooldown"
	end
	local owner = id
	local life = self._life[id] or 0
	local mini = d.mini
	local b, err = self:_throw(id, pose, aimOf(payload, pose), "Cluster", d.bomb, {
		explosion = { radius = d.radius, damage = d.damage, falloffMin = d.falloffMin },
		explodeAt = now + d.fuse,
		onExplode = function(bomb, _results, _stage, time)
			-- 자탄 N개: 폭발 위치에서 균등한 수평 각도, 위쪽 pitch 로 흩어지며 0.35초 간격으로 차례로 폭발한다
			for k = 1, mini.count do
				local ang = (k - 1) / mini.count * 2 * math.pi
				local pitch = math.rad(mini.pitchDeg)
				local dir = { X = math.cos(ang) * math.cos(pitch), Y = math.sin(pitch), Z = math.sin(ang) * math.cos(pitch) }
				self.bombs:spawn({
					owner = owner, life = life, kind = "Mini", pos = Vec.add(bomb.pos, { X = 0, Y = 0.3, Z = 0 }), dir = dir, speed = mini.speed,
					gravity = mini.gravity, radius = 0.3, now = time, chainTarget = false, explodeAt = time + mini.fuse + mini.fuseStep * (k - 1),
					explosion = { radius = mini.radius, damage = mini.damage, falloffMin = 1 },
				})
			end
		end,
	}, now)
	if not b then
		return false, err
	end
	self._core.cooldown:start(id, "skill1", d.cooldown, now)
	self._d.approve(id, d, now)
	self._d.emit({ type = "CharSkill", cue = "bomb.cluster", skill = "ClusterBomb", playerId = id, bombId = b.id, time = now })
	return true, { bombId = b.id }
end

-- ── 스킬 2 Remote Bomb (Press = 누르기 시작, Release = 짧으면 설치, 0.4초 이상이면 전체 기폭) ──
function TimebombSkills:_remote(id, payload, pose, now)
	local d = self._def.skills[2]
	if payload.phase ~= "Release" then
		if self._hold[id] then
			return false, "already_holding"
		end
		self._hold[id] = { startAt = now }
		return true, { holding = true }
	end
	local h = self._hold[id]
	if not h then
		return false, "not_holding" -- 중복/늦은 Release: 설치도 기폭도 일어나지 않는다
	end
	self._hold[id] = nil
	local held = now - h.startAt
	if held > d.maxHoldSeconds then
		return false, "hold_expired"
	end
	if held >= d.holdSeconds - 1e-9 then
		-- 전체 기폭(충전 소모 없음). 설치된 폭탄이 없으면 거부.
		if self.bombs:count(id, isPlaced) == 0 then
			return false, "nothing_to_detonate"
		end
		self._d.approve(id, { kind = "Detonate", detonate = true }, now)
		local n = self.bombs:detonate(id, isPlaced, now)
		self._d.emit({ type = "CharSkill", cue = "bomb.detonate", skill = "RemoteBomb", phase = "Detonate", playerId = id, count = n, time = now })
		return true, { detonated = n }
	end
	-- 설치(던지기)
	if not self._core.cooldown:isReady(id, "skill2", now) then
		return false, "on_cooldown"
	end
	local avail = self:_available(id, now)
	if avail <= 0 then
		return false, "no_charge"
	end
	if self.bombs:count(id, isPlaced) >= d.maxPlaced then
		return false, "max_placed"
	end
	local b, err = self:_throw(id, pose, aimOf(payload, pose), "Remote", d.bomb, {
		explosion = { radius = d.radius, damage = d.damage, falloffMin = d.falloffMin },
		placed = true, expireAt = now + d.placedLifetime,
	}, now)
	if not b then
		return false, err
	end
	local list = self._charges[id] or {}
	table.insert(list, now + d.rechargeSeconds)
	self._charges[id] = list
	self._core.cooldown:start(id, "skill2", d.throwInterval, now)
	self._d.approve(id, d, now)
	self._d.emit({ type = "CharSkill", cue = "bomb.remote", skill = "RemoteBomb", phase = "Place", playerId = id, bombId = b.id, time = now })
	return true, { bombId = b.id, chargesLeft = avail - 1 }
end

-- ── 스킬 3 Blast Jump ───────────────────────────────────────
function TimebombSkills:_blastJump(id, payload, pose, now)
	local d = self._def.skills[3]
	if not self._core.cooldown:isReady(id, "skill3", now) then
		return false, "on_cooldown"
	end
	local aim = aimOf(payload, pose)
	local dir = Vec.normalize({ X = aim.X, Y = math.max(aim.Y, d.minUp), Z = aim.Z }) or { X = 0, Y = 1, Z = 0 }
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
	local total = dist / d.duration
	local horiz = total * math.sqrt(dir.X * dir.X + dir.Z * dir.Z)
	local up = total * dir.Y
	if self._d.movement then
		local ok, why = self._d.movement:issue(id, d.permit, now, { speed = horiz, up = up, duration = d.duration, dir = dir })
		if not ok then
			return false, "movement_denied:" .. tostring(why)
		end
	end
	self._core.cooldown:start(id, "skill3", d.cooldown, now)
	self._jumpAt[id] = now
	self._d.approve(id, d, now) -- 판정(피해) 없는 이동기 → 부활 보호 유지
	self._d.emit({
		type = "CharSkill", cue = "bomb.jump", skill = "BlastJump", playerId = id, pos = pose.pos, direction = dir, distance = dist,
		dash = { speed = horiz, up = up, duration = d.duration, permit = d.permit }, time = now,
	})
	self.bombs:chainFrom(id, pose.pos, now) -- 발밑 폭발: 자기 폭탄 근처면 연쇄 기폭(피해 없음)
	return true, { distance = dist, speed = total }
end

function TimebombSkills:skill(id, slot, payload, pose, now)
	if slot == 2 then
		return self:_remote(id, payload, pose, now)
	end
	if payload.phase == "Release" then
		return false, "not_charging"
	end
	if slot == 1 then
		return self:_cluster(id, payload, pose, now)
	elseif slot == 3 then
		return self:_blastJump(id, payload, pose, now)
	end
	return false, "skill_not_implemented"
end

-- ── 궁극기 Big Bang ─────────────────────────────────────────
function TimebombSkills:canUltimate(_id, _payload, _pose, _now)
	return true
end

function TimebombSkills:ultimateDef(_id, _now)
	return { duration = self._def.ultimate.duration, onEnd = function() end }
end

-- 게이지 소모가 성공한 뒤에만 호출된다. 착지 위치는 서버의 실제 충돌로 정해지고, 착지 3초 뒤 폭발한다.
function TimebombSkills:startUltimate(id, payload, pose, now)
	local u = self._def.ultimate
	self._lastNow = now
	local airborne = pose.airborne == true and self._jumpAt[id] ~= nil and now - self._jumpAt[id] <= u.airWindow
	local b = self.bombs:spawn({
		owner = id, life = self._life[id] or 0, kind = "BigBang", pos = self:_eye(pose), dir = aimOf(payload, pose),
		speed = airborne and u.airSpeed or u.speed, gravity = u.gravity, radius = u.bombRadius, now = now,
		explodeAt = now + u.flightLimit, fuseAfterLand = u.fuseAfterLand, chainTarget = false,
		explosion = { radius = u.radius, damage = u.damage, falloffMin = u.edgeDamage / u.damage },
	})
	self._d.stopRunning(id)
	if b then
		self._d.emit({ type = "CharSkill", cue = "bomb.bigbang", skill = "BigBang", phase = "Throw", playerId = id, bombId = b.id, far = airborne, time = now })
	end
end

function TimebombSkills:onAim(_id, _dir, _now)
	return false
end

function TimebombSkills:update(now)
	self._lastNow = now
	self.bombs:step(now)
	for id, h in table.clone(self._hold) do
		if now - h.startAt > self._def.skills[2].maxHoldSeconds + 0.5 then
			self._hold[id] = nil -- Release 가 오지 않은 누르기 정리
		end
	end
end

function TimebombSkills:hudInfo(id, now)
	local cd = self._core.cooldown
	local d2 = self._def.skills[2]
	local avail, list = self:_available(id, now)
	local nextAt = 0
	if avail <= 0 and list then
		nextAt = math.huge
		for _, at in list do
			nextAt = math.min(nextAt, at)
		end
	end
	local sk = self._def.skills
	local placed = self.bombs:count(id, isPlaced)
	return {
		skills = {
			{ implemented = true, name = sk[1].name, readyAt = cd:readyAt(id, "skill1") or 0, total = sk[1].cooldown },
			{
				implemented = true, name = d2.name, readyAt = nextAt, total = d2.rechargeSeconds, charges = avail, maxCharges = d2.charges, placed = placed,
				holding = self._hold[id] ~= nil,
			},
			{ implemented = true, name = sk[3].name, readyAt = cd:readyAt(id, "skill3") or 0, total = sk[3].cooldown },
		},
		passive = { id = self._def.passive.id, lockedUntil = 0 },
		ultimate = { name = self._def.ultimate.name, active = false },
		secondary = { readyAt = cd:readyAt(id, "secondary") or 0, total = self._def.secondary.cooldown },
		extra = { placed = placed, maxPlaced = d2.maxPlaced, charges = avail, bombs = self.bombs:count(id) },
	}
end

return TimebombSkills
