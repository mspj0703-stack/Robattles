--!nonstrict
-- PAINTBALL 전용 서버 로직(Phase 2): LMB Paint Shot, RMB Paint Burst, 스킬 1~3, 궁극기 Color Break, 패시브 Color Reload.
-- 피해·탄약·쿨타임·명중은 전부 서버가 정한다. 클라이언트는 조준 의사(방향, 궁극기 중에는 Aim 갱신)만 보낸다.
-- 수치: shared/Data/Characters.PAINTBALL (확정/임시 구분은 그 파일 주석과 docs/ASSUMPTIONS.md A68~A71).
--
-- deps (CharacterController 가 주입; 모든 모듈이 같은 형태):
--   cfg, core, characters, projectiles, getPose(id), targets(), world { cast?, lineOfSight }, movement | nil,
--   emit(event), approve(id, actionDef, now), nextAttackId(id), setSlow(id, untilT, mult), stopRunning(id),
--   canAct(id, now), state(id) -> 컨트롤러 플레이어 상태(ammo, reloadingUntil, alive, characterId), startReload(id, now)
local Link = require(script.Parent.Link)
local Vec = Link.shared("Vec")
local Hitbox = require(script.Parent.HitboxService)
local Geometry = require(script.Parent.Geometry)

local PaintballSkills = {}
PaintballSkills.__index = PaintballSkills

local ID = "PAINTBALL"

function PaintballSkills.new(deps)
	local chars = deps.characters or Link.shared("Data/Characters")
	local self = setmetatable({
		_d = deps,
		_cfg = deps.cfg,
		_core = deps.core,
		_def = chars.PAINTBALL,
		_tags = {}, -- [projectileId] = { owner, kind, life } : 어떤 공격에서 나온 투사체인지(패시브 판정용)
		_life = {}, -- [playerId] = 생애 번호(부활/캐릭터 변경/퇴장 때 증가 → 이전 생애 투사체의 패시브 무효)
		_lock = {}, -- [playerId] = Color Reload 재발동 가능 시각
		_slide = {}, -- [playerId] = 슬라이드 종료 시각(표시용)
		_ult = {}, -- [playerId] = { startAt, nextTick, serial, aim, dmg }
		_counter = 0,
		_lastNow = 0,
	}, PaintballSkills)
	deps.projectiles:onEvent(function(e)
		self:_onProjectileEvent(e)
	end)
	return self
end

function PaintballSkills:isBusy(_id)
	return false -- 이동·사격 제한 없음(슬라이드 중에도 LMB/RMB 가능)
end

function PaintballSkills:onDodge(_id, _now) end

function PaintballSkills:onTargetGone(_targetId) end

-- 사망·부활·캐릭터 변경·퇴장: 진행 중 상태 정리. 이미 발사된 투사체는 수명 동안 유지되지만 패시브는 이전 생애로 간주해 무효.
function PaintballSkills:reset(id, _now, _reason)
	self._life[id] = (self._life[id] or 0) + 1
	self._lock[id] = nil
	self._slide[id] = nil
	if self._ult[id] then
		self._ult[id] = nil
		self._d.emit({ type = "CharSkill", cue = "paint.ult.end", skill = "ColorBreak", phase = "End", playerId = id, time = self._lastNow })
	end
end

local function aimOf(payload, pose)
	local a = payload and payload.aimDirection
	return (a and Vec.normalize(a)) or Vec.normalize(pose.forward) or { X = 0, Y = 0, Z = -1 }
end

function PaintballSkills:_eye(pose)
	return Vec.add(pose.pos, { X = 0, Y = self._cfg.Combat.EyeHeight, Z = 0 })
end

function PaintballSkills:_capacityFor(id, n)
	local lim = self._cfg.Projectile
	local ps = self._d.projectiles
	return ps:getActiveCount(id) + n <= lim.MaxActivePerOwner and ps:getActiveCount() + n <= lim.MaxActiveTotal
end

function PaintballSkills:_tag(pid, id, kind)
	self._tags[pid] = { owner = id, kind = kind, life = self._life[id] or 0 }
end

-- ── 패시브 Color Reload ─────────────────────────────────────
-- 유효 적중(Paint Burst / Color Bomb / Piercing Shot 이 실제로 피해를 준 경우)이면 탄 3 회복 + 5초 재발동 제한.
-- 재장전 중이면 재장전을 즉시 취소하고 탄을 회복한다. 회복할 것이 없으면(탄창 가득·재장전 아님) 발동·잠금 모두 일어나지 않는다(A69).
function PaintballSkills:_onValidHit(owner, tag, targetId, time)
	if tag.life ~= (self._life[owner] or 0) then
		return
	end
	local st = self._d.state(owner)
	if not st or not st.alive or st.characterId ~= ID then
		return
	end
	if time < (self._lock[owner] or 0) then
		return
	end
	local mag = self._def.ammo.magazine
	local reloading = (st.reloadingUntil or 0) > 0
	if st.ammo >= mag and not reloading then
		return
	end
	local p = self._def.passive
	self._lock[owner] = time + p.lockSeconds
	if reloading then
		st.reloadingUntil = 0 -- 재장전 취소: 완료 시점에 탄이 가득으로 덮이지 않는다
	end
	local before = st.ammo
	st.ammo = math.min(mag, st.ammo + p.ammoRestore)
	self._d.emit({
		type = "CharSkill", cue = "paint.reload.proc", skill = "ColorReload", playerId = owner, targetId = targetId,
		ammo = st.ammo, restored = st.ammo - before, cancelledReload = reloading, time = time,
	})
end

function PaintballSkills:_onProjectileEvent(e)
	if e.type == "Hit" then
		local tag = self._tags[e.projectileId]
		if tag and (tag.kind == "Burst" or tag.kind == "Pierce") and e.result and e.result.applied then
			self:_onValidHit(tag.owner, tag, e.targetId, e.time)
		end
	elseif e.type == "Explosion" then
		local tag = self._tags[e.projectileId]
		if tag and tag.kind == "Bomb" then
			for _, r in e.results or {} do
				if r.result and r.result.applied and r.targetId ~= tag.owner then
					self:_onValidHit(tag.owner, tag, r.targetId, e.time)
					break
				end
			end
		end
	elseif e.type == "Ended" then
		self._tags[e.projectileId] = nil
	end
end

-- ── LMB Paint Shot ──────────────────────────────────────────
function PaintballSkills:primary(id, payload, pose, now)
	local st = self._d.state(id)
	local prim = self._def.primary
	if now < st.reloadingUntil then
		return false, "reloading"
	end
	if st.ammo <= 0 then
		self._d.startReload(id, now)
		return false, "no_ammo"
	end
	if not self._core.cooldown:isReady(id, "primary", now) then
		return false, "on_cooldown"
	end
	local dir = Hitbox.rangedDirection(aimOf(payload, pose)) -- 원거리 자동 조준 보정 없음
	local pid, err = self._d.projectiles:spawn({ def = prim.projectile, ownerId = id, origin = self:_eye(pose), direction = dir }, now)
	if not pid then
		return false, err
	end
	self:_tag(pid, id, "Shot")
	self._core.cooldown:start(id, "primary", prim.fireInterval, now)
	st.ammo -= 1
	if st.ammo == 0 then
		self._d.startReload(id, now)
	end
	self._d.setSlow(id, now + prim.fireInterval, prim.moveSpeedMult)
	self._d.stopRunning(id)
	self._d.approve(id, prim, now)
	return true, { projectileId = pid, ammo = st.ammo }
end

-- ── RMB Paint Burst ─────────────────────────────────────────
function PaintballSkills:secondary(id, payload, pose, now)
	local st = self._d.state(id)
	local sec = self._def.secondary
	if now < st.reloadingUntil then
		return false, "reloading"
	end
	if st.ammo < sec.ammoCost then
		return false, "no_ammo"
	end
	if not self._core.cooldown:isReady(id, "secondary", now) then
		return false, "on_cooldown"
	end
	if not self:_capacityFor(id, sec.pellets) then
		return false, "too_many_projectiles"
	end
	local dir = Hitbox.rangedDirection(aimOf(payload, pose))
	local origin = self:_eye(pose)
	local ids = {}
	for i = 1, sec.pellets do
		local off = sec.spread[i] or { 0, 0 }
		local pid = self._d.projectiles:spawn({
			def = sec.projectile, ownerId = id, origin = origin, direction = Geometry.spread(dir, off[1], off[2]),
		}, now)
		if pid then
			self:_tag(pid, id, "Burst")
			table.insert(ids, pid)
		end
	end
	if #ids == 0 then
		return false, "spawn_failed"
	end
	self._core.cooldown:start(id, "secondary", sec.cooldown, now)
	st.ammo -= sec.ammoCost
	if st.ammo == 0 then
		self._d.startReload(id, now)
	end
	self._d.setSlow(id, now + sec.cooldown, sec.moveSpeedMult)
	self._d.stopRunning(id)
	self._d.approve(id, sec, now)
	self._d.emit({ type = "CharSkill", cue = "paint.burst", skill = "PaintBurst", playerId = id, pos = origin, dir = dir, time = now })
	return true, { projectileIds = ids, ammo = st.ammo }
end

-- ── 스킬 1·2·3 ──────────────────────────────────────────────
function PaintballSkills:_colorBomb(id, payload, pose, now)
	local d = self._def.skills[1]
	if not self._core.cooldown:isReady(id, "skill1", now) then
		return false, "on_cooldown"
	end
	local pid, err = self._d.projectiles:spawn({
		def = d.projectile, ownerId = id, origin = self:_eye(pose), direction = aimOf(payload, pose),
	}, now)
	if not pid then
		return false, err
	end
	self:_tag(pid, id, "Bomb")
	self._core.cooldown:start(id, "skill1", d.cooldown, now)
	self._d.approve(id, d, now)
	self._d.emit({ type = "CharSkill", cue = "paint.bomb.throw", skill = "ColorBomb", playerId = id, projectileId = pid, time = now })
	return true, { projectileId = pid }
end

function PaintballSkills:_piercing(id, payload, pose, now)
	local d = self._def.skills[2]
	if not self._core.cooldown:isReady(id, "skill2", now) then
		return false, "on_cooldown"
	end
	local pid, err = self._d.projectiles:spawn({
		def = d.projectile, ownerId = id, origin = self:_eye(pose), direction = aimOf(payload, pose),
	}, now)
	if not pid then
		return false, err
	end
	self:_tag(pid, id, "Pierce")
	self._core.cooldown:start(id, "skill2", d.cooldown, now)
	self._d.approve(id, d, now)
	self._d.emit({ type = "CharSkill", cue = "paint.pierce.fire", skill = "PiercingShot", playerId = id, projectileId = pid, time = now })
	return true, { projectileId = pid }
end

-- Paint Slide: 서버가 이동 허가(PaintSlide)를 발급해야만 시작한다. 거부(허가·벽)되면 쿨타임을 쓰지 않는다. 무적 없음.
function PaintballSkills:_paintSlide(id, payload, pose, now)
	local d = self._def.skills[3]
	if not self._core.cooldown:isReady(id, "skill3", now) then
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
	self._core.cooldown:start(id, "skill3", d.cooldown, now)
	self._slide[id] = now + d.duration
	self._d.approve(id, d, now) -- 판정 없는 이동기: ActionPolicy 가 비공격으로 분류 → 부활 보호 유지
	self._d.emit({
		type = "CharSkill", cue = "paint.slide", skill = "PaintSlide", playerId = id, direction = dir, distance = dist,
		dash = { speed = speed, duration = d.duration, permit = d.permit }, time = now,
	})
	return true, { distance = dist, speed = speed }
end

function PaintballSkills:skill(id, slot, payload, pose, now)
	if payload.phase == "Release" then
		return false, "not_charging" -- PAINTBALL 스킬에는 충전/해제가 없다
	end
	if slot == 1 then
		return self:_colorBomb(id, payload, pose, now)
	elseif slot == 2 then
		return self:_piercing(id, payload, pose, now)
	elseif slot == 3 then
		return self:_paintSlide(id, payload, pose, now)
	end
	return false, "skill_not_implemented"
end

-- ── 궁극기 Color Break ──────────────────────────────────────
function PaintballSkills:canUltimate(_id, _payload, _pose, _now)
	return true
end

-- UltimateService.activate 에 넘길 정의. 종료 사유(Completed/Death/External…)와 무관하게 정리한다.
function PaintballSkills:ultimateDef(id, _now)
	local u = self._def.ultimate
	return {
		duration = u.duration,
		onEnd = function(reason)
			if self._ult[id] then
				self._ult[id] = nil
				self._d.emit({ type = "CharSkill", cue = "paint.ult.end", skill = "ColorBreak", phase = "End", playerId = id, reason = reason, time = self._lastNow })
			end
		end,
	}
end

-- 게이지 소모가 성공한 뒤에만 호출된다.
function PaintballSkills:startUltimate(id, payload, pose, now)
	self._counter += 1
	self._lastNow = now
	self._ult[id] = { startAt = now, nextTick = 1, serial = self._counter, aim = aimOf(payload, pose), dmg = {} }
	self._d.stopRunning(id)
	self._d.emit({ type = "CharSkill", cue = "paint.ult.windup", skill = "ColorBreak", phase = "Windup", playerId = id, time = now, windup = self._def.ultimate.windup })
end

-- Aim 리모트: 빔 시전 중 조준 방향 갱신(서버가 단위 벡터 검증을 이미 마친 값). 반환 ok
function PaintballSkills:onAim(id, dir, _now)
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

function PaintballSkills:_beamTick(id, u, scheduledAt, now)
	local def = self._def.ultimate
	local pose = self._d.getPose(id)
	if not pose then
		return
	end
	local origin = self:_eye(pose)
	local dir = u.aim
	local tip = Vec.add(origin, Vec.scale(dir, def.length))
	local world = self._d.world
	if world.cast then
		local wall = world.cast(origin, tip, 0)
		if wall then
			tip = Geometry.lerp(origin, tip, wall.fraction)
		end
	end
	local hits = 0
	local attackBase = string.format("cb%d_%s_%d", u.serial, tostring(id), u.nextTick)
	for _, t in self._d.targets() do
		if t.id ~= id and t.alive ~= false then
			local f = Geometry.segmentSphere(origin, tip, t.pos, (t.radius or self._cfg.Combat.HitRadius) + def.radius)
			if f then
				local used = u.dmg[t.id] or 0
				local amount = math.min(def.tickDamage, def.maxPerTarget - used)
				if amount > 0 then
					local r = self._core.damage:applyDamage({
						attackerId = id, targetId = t.id, attackId = attackBase, amount = amount, kind = "Beam",
						blockable = def.blockable == true, sourceDir = Vec.scale(dir, -1),
					}, scheduledAt)
					if r.applied then
						u.dmg[t.id] = used + r.amount
						hits += 1
					end
				end
			end
		end
	end
	self._d.emit({
		type = "CharSkill", cue = "paint.ult.beam", skill = "ColorBreak", phase = "Tick", index = u.nextTick, playerId = id,
		origin = origin, tip = tip, hits = hits, time = now,
	})
end

function PaintballSkills:_updateUlt(id, u, now)
	local def = self._def.ultimate
	local ticks = math.floor(def.beamSeconds / def.tickInterval + 1e-6)
	local guard = 0
	while u.nextTick <= ticks and guard < 16 do
		local at = u.startAt + def.windup + u.nextTick * def.tickInterval
		if now + 1e-6 < at then
			break
		end
		self:_beamTick(id, u, at, now)
		u.nextTick += 1
		guard += 1
	end
end

function PaintballSkills:update(now)
	self._lastNow = now
	for id, u in table.clone(self._ult) do
		if self._ult[id] == u then
			self:_updateUlt(id, u, now)
		end
	end
	for id, untilT in self._slide do
		if now >= untilT then
			self._slide[id] = nil
		end
	end
end

-- HUD 스냅샷용 상태
function PaintballSkills:hudInfo(id, now)
	local cd = self._core.cooldown
	local sk = self._def.skills
	local u = self._ult[id]
	local function entry(i, key, state)
		return { implemented = true, name = sk[i].name, readyAt = cd:readyAt(id, key) or 0, total = sk[i].cooldown, state = state }
	end
	return {
		skills = {
			entry(1, "skill1"),
			entry(2, "skill2"),
			entry(3, "skill3", self._slide[id] and now < self._slide[id] and "sliding" or nil),
		},
		passive = { id = self._def.passive.id, lockedUntil = self._lock[id] or 0 },
		ultimate = { name = self._def.ultimate.name, active = u ~= nil, windupUntil = u and (u.startAt + self._def.ultimate.windup) or nil },
	}
end

return PaintballSkills
