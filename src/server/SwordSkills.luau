--!nonstrict
-- SWORD 전용 서버 로직: LMB 3타 콤보, Skill 1 Triple Slash, Skill 2 Lunge(충전 돌진), Skill 3 Blade Wave,
-- Ultimate Blade Storm, Passive Duelist 연동. 피해·쿨타임·명중은 전부 서버가 정하고, 클라이언트는 조준 의사만 보낸다.
-- 수치는 shared/Data/Characters.SWORD 에 있고, 확정/임시 구분은 그 파일 주석과 docs/ASSUMPTIONS.md(A65~A67)를 따른다.
--
-- deps = {
--   cfg, core, characters,
--   getPose(id) -> { pos, forward, airborne? } | nil
--   targets() -> { {id, pos, radius, alive} }
--   world { lineOfSight(a, b) }
--   movement  MovementValidator | nil   (돌진 허가 발급; 없으면 허가 생략 — 테스트용)
--   emit(event)
--   approve(id, actionDef, now)         공통 행동 승인(부활 보호 해제)
--   nextAttackId(id) -> string
--   setSlow(id, untilT, mult), stopRunning(id)
-- }
local Link = require(script.Parent.Link)
local Vec = Link.shared("Vec")
local Hitbox = require(script.Parent.HitboxService)
local Duelist = require(script.Parent.Duelist)

local SwordSkills = {}
SwordSkills.__index = SwordSkills

local function lerp(a, b, t)
	return a + (b - a) * t
end

function SwordSkills.new(deps)
	local chars = deps.characters or Link.shared("Data/Characters")
	local def = chars.SWORD
	return setmetatable({
		_d = deps,
		_cfg = deps.cfg,
		_core = deps.core,
		_def = def,
		_duelist = Duelist.new(def.passive),
		_combo = {}, -- [id] = { step = 다음에 칠 타수-1, lastAt }
		_triple = {}, -- [id] = { step, lastAt, windowUntil }
		_lunge = {}, -- [id] = { state = "charging" | "dashing", ... }
		_storm = {}, -- [id] = { startAt, nextTick, finisherDone }
		_counter = 0,
	}, SwordSkills)
end

function SwordSkills:duelist()
	return self._duelist
end

-- 부활·사망·퇴장 시 진행 중 상태 정리
function SwordSkills:reset(id)
	self._combo[id] = nil
	self._triple[id] = nil
	self._lunge[id] = nil
	self._storm[id] = nil
	self._duelist:clearAttacker(id)
end

function SwordSkills:onTargetGone(targetId)
	self._duelist:clearTarget(targetId)
end

function SwordSkills:isBusy(id)
	return self._lunge[id] ~= nil or self._storm[id] ~= nil
end

local function aimDir(payload, pose)
	local a = payload and payload.aimDirection
	return (a and Vec.flatten(a)) or Vec.flatten(pose.forward) or { X = 0, Y = 0, Z = -1 }
end

-- Duelist 가 적용되는 공격(콤보·스킬 1·2·3)은 이 함수로 피해를 준다. 반환: DamageService 결과
function SwordSkills:_strike(id, tid, amount, req, now, useDuelist)
	local bonus = useDuelist and self._duelist:bonusFor(id, tid, now) or 0
	req.attackerId, req.targetId = id, tid
	req.amount = amount + bonus
	local r = self._core.damage:applyDamage(req, now)
	if r.applied and useDuelist then
		local triggered = self._duelist:onValidHit(id, tid, now, bonus > 0)
		if triggered then
			self._d.emit({ type = "Duelist", playerId = id, targetId = tid, bonus = bonus, time = now })
		end
	end
	return r
end

-- 부채꼴 근접 선택(콤보·Triple Slash·Blade Wave 공통). 반환: ids, dir
function SwordSkills:_arcTargets(id, payload, pose, range, arc)
	local targets = self._d.targets()
	local dir = Hitbox.assistedMeleeDirection(payload.aimDirection or pose.forward, pose.pos, targets, self._cfg.Camera.MeleeAimAssistDegrees, id, range)
	local ids = Hitbox.selectMeleeTargets({ pos = pose.pos, forward = dir }, targets, {
		attackerId = id,
		range = range,
		arcDegrees = arc,
		tolerance = self._cfg.Net.MeleeRangeTolerance,
		lineOfSight = self._d.world.lineOfSight,
	})
	return ids, dir, targets
end

local function posOf(targets, tid)
	for _, t in targets do
		if t.id == tid then
			return t.pos
		end
	end
	return nil
end

-- ── LMB 3타 콤보 ─────────────────────────────────────────────
function SwordSkills:primary(id, payload, pose, now)
	if self:isBusy(id) then
		return false, "busy"
	end
	local prim = self._def.primary
	local combo = prim.combo
	local c = self._combo[id] or { done = 0, lastAt = -1e9 }
	if c.done > 0 and now - c.lastAt > combo.resetSeconds then
		c.done = 0 -- 콤보 이어짐 창이 지나면 1타부터
	end
	local step = c.done + 1
	local ok, reason = self._core.cooldown:tryUse(id, "primary", step == #combo.damages and combo.finishCooldown or prim.cooldown, now)
	if not ok then
		return false, reason
	end
	local ids, _, targets = self:_arcTargets(id, payload, pose, prim.range, prim.arcDegrees)
	local attackId = self._d.nextAttackId(id)
	local hits = {}
	for _, tid in ids do
		local effects = {}
		local away = posOf(targets, tid) and Vec.flatten(Vec.sub(posOf(targets, tid), pose.pos))
		if prim.knockback and prim.knockback > 0 and away then
			table.insert(effects, { type = "Knockback", direction = away, power = prim.knockback, upward = 0 })
		end
		local r = self:_strike(id, tid, combo.damages[step], {
			attackId = attackId, kind = "Melee", blockable = true, sourcePos = pose.pos, strong = prim.stagger == true, effects = effects,
		}, now, true)
		if r.applied then
			table.insert(hits, tid)
		end
	end
	c.done = step == #combo.damages and 0 or step
	c.lastAt = now
	self._combo[id] = c
	self._d.setSlow(id, now + prim.cooldown, prim.moveSpeedMult) -- ASSUMPTION A32
	self._d.stopRunning(id)
	self._d.emit({ type = "Swing", playerId = id, hits = hits, step = step, time = now })
	return true, { hits = hits, step = step }, prim
end

-- ── Skill 1: Triple Slash ───────────────────────────────────
function SwordSkills:_expireTriple(id, now)
	local t = self._triple[id]
	if t and now > t.windowUntil then
		self._triple[id] = nil
		self._core.cooldown:start(id, "skill1", self._def.skills[1].cooldown, t.windowUntil) -- 연계 창이 끝난 시점부터 쿨타임
	end
end

function SwordSkills:_tripleSlash(id, payload, pose, now)
	local d = self._def.skills[1]
	self:_expireTriple(id, now)
	local t = self._triple[id]
	if t == nil then
		if not self._core.cooldown:isReady(id, "skill1", now) then
			return false, "on_cooldown"
		end
	elseif now - t.lastAt < d.stepInterval then
		return false, "too_soon"
	end
	local step = t and t.step + 1 or 1
	local dir = aimDir(payload, pose)
	-- 이동 허가를 먼저 확인한다: 거부되면 쿨타임·상태를 소모하지 않는다.
	local speed = d.advance / d.advanceDuration
	if self._d.movement then
		local okMove, why = self._d.movement:issue(id, d.permit, now, { speed = speed, duration = d.advanceDuration, dir = dir })
		if not okMove then
			return false, "movement_denied:" .. tostring(why)
		end
	end
	local ids = self:_arcTargets(id, payload, pose, d.range + d.advance, d.arcDegrees)
	local attackId = self._d.nextAttackId(id)
	local hits = {}
	for _, tid in ids do
		local r = self:_strike(id, tid, d.damages[step], {
			attackId = attackId, kind = "Melee", blockable = true, sourcePos = pose.pos,
		}, now, true)
		if r.applied then
			table.insert(hits, tid)
		end
	end
	self._d.approve(id, d, now)
	if step >= #d.damages then
		self._triple[id] = nil
		self._core.cooldown:start(id, "skill1", d.cooldown, now)
	else
		self._triple[id] = { step = step, lastAt = now, windowUntil = now + d.chainWindow }
	end
	self._d.setSlow(id, now + d.advanceDuration, 1)
	self._d.stopRunning(id)
	self._d.emit({
		type = "SwordSkill", skill = "TripleSlash", step = step, playerId = id, hits = hits, direction = dir,
		dash = { speed = speed, duration = d.advanceDuration }, time = now,
	})
	return true, { hits = hits, step = step }
end

-- ── Skill 2: Lunge ──────────────────────────────────────────
function SwordSkills:_startDash(id, pose, dir, charge, now)
	local d = self._def.skills[2]
	local speed = d.dashDistance / d.dashDuration
	if self._d.movement then
		local okMove, why = self._d.movement:issue(id, d.permit, now, { speed = speed, duration = d.dashDuration, dir = dir })
		if not okMove then
			return false, "movement_denied:" .. tostring(why)
		end
	end
	local damage = lerp(d.minDamage, d.maxDamage, charge)
	self._lunge[id] = {
		state = "dashing", startAt = now, endAt = now + d.dashDuration + self._cfg.MoveCheck.ImpulseGrace,
		dir = dir, damage = damage, lastPos = pose.pos, hit = {}, attackId = self._d.nextAttackId(id),
	}
	self._core.cooldown:start(id, "skill2", d.cooldown, now)
	self._d.setSlow(id, 0, 1)
	self._d.emit({
		type = "SwordSkill", skill = "Lunge", phase = "Dash", playerId = id, charge = charge, damage = damage, direction = dir,
		dash = { speed = speed, duration = d.dashDuration }, time = now,
	})
	return true, { damage = damage, charge = charge }
end

function SwordSkills:_lunge2(id, payload, pose, now)
	local d = self._def.skills[2]
	local cur = self._lunge[id]
	if payload.phase == "Release" then
		if not cur or cur.state ~= "charging" then
			return false, "not_charging"
		end
		local charge = math.clamp((now - cur.startAt) / d.chargeSeconds, 0, 1)
		local ok, why = self:_startDash(id, pose, aimDir(payload, pose), charge, now)
		if not ok then
			self._lunge[id] = nil
			self._d.setSlow(id, 0, 1)
			self._d.emit({ type = "SwordSkill", skill = "Lunge", phase = "Cancel", playerId = id, reason = why, time = now })
		end
		return ok, why
	end
	if cur then
		return false, cur.state == "charging" and "already_charging" or "busy"
	end
	if self:isBusy(id) then
		return false, "busy"
	end
	if not self._core.cooldown:isReady(id, "skill2", now) then
		return false, "on_cooldown"
	end
	self._lunge[id] = { state = "charging", startAt = now }
	self._d.approve(id, d, now)
	self._d.stopRunning(id)
	self._d.setSlow(id, now + d.chargeSeconds + d.autoReleaseGrace + 0.2, d.chargeMoveMult)
	self._d.emit({ type = "SwordSkill", skill = "Lunge", phase = "Charge", playerId = id, time = now, chargeSeconds = d.chargeSeconds })
	return true, { charging = true }
end

-- 점-선분 수평 거리
local function distToSegment(p, a, b)
	local abx, abz = b.X - a.X, b.Z - a.Z
	local len2 = abx * abx + abz * abz
	local t = 0
	if len2 > 1e-9 then
		t = math.clamp(((p.X - a.X) * abx + (p.Z - a.Z) * abz) / len2, 0, 1)
	end
	local cx, cz = a.X + abx * t, a.Z + abz * t
	local dx, dz = p.X - cx, p.Z - cz
	return math.sqrt(dx * dx + dz * dz)
end
SwordSkills._distToSegment = distToSegment

function SwordSkills:_updateLunge(id, st, now)
	local d = self._def.skills[2]
	local l = self._lunge[id]
	if not l then
		return
	end
	local pose = self._d.getPose(id)
	if l.state == "charging" then
		if not self._d.canAct(id, now) then
			self:cancelLunge(id, now, "CannotAct")
		elseif pose and now - l.startAt >= d.chargeSeconds + d.autoReleaseGrace then
			-- 키를 떼는 요청이 오지 않아도 자동 발사(최대 충전)
			local ok, why = self:_startDash(id, pose, Vec.flatten(pose.forward) or { X = 0, Y = 0, Z = -1 }, 1, now)
			if not ok then
				self:cancelLunge(id, now, why)
			end
		end
		return
	end
	-- 돌진 중: 이전 샘플과 현재 위치를 잇는 선분 위의 모든 적을 한 번씩 적중
	if not pose or not self._d.canAct(id, now) then
		self._lunge[id] = nil
		return
	end
	local targets = self._d.targets()
	for _, t in targets do
		if t.id ~= id and t.alive ~= false and not l.hit[t.id] then
			local reach = d.pathRadius + (t.radius or 0)
			if distToSegment(t.pos, l.lastPos, pose.pos) <= reach and self._d.world.lineOfSight(l.lastPos, t.pos) then
				local r = self:_strike(id, t.id, l.damage, {
					attackId = l.attackId, kind = "Melee", blockable = true, sourcePos = l.lastPos,
				}, now, true)
				if r.applied or r.reason ~= "invulnerable" then
					l.hit[t.id] = true -- 회피 무적으로 막힌 경우만 다음 샘플에서 다시 시도
				end
			end
		end
	end
	l.lastPos = pose.pos
	if now >= l.endAt then
		self._lunge[id] = nil
		self._d.emit({ type = "SwordSkill", skill = "Lunge", phase = "End", playerId = id, time = now })
	end
end

function SwordSkills:cancelLunge(id, now, reason)
	local l = self._lunge[id]
	if not l then
		return false
	end
	self._lunge[id] = nil
	self._d.setSlow(id, 0, 1)
	-- 충전만 하고 돌진하지 않은 취소는 쿨타임을 쓰지 않는다. 돌진 중 취소는 이미 쿨타임이 시작됐다.
	self._d.emit({ type = "SwordSkill", skill = "Lunge", phase = "Cancel", playerId = id, reason = reason, time = now })
	return true
end

-- 회피는 충전/돌진을 끊는다(임시 A65)
function SwordSkills:onDodge(id, now)
	if self._lunge[id] then
		self:cancelLunge(id, now, "Dodge")
	end
end

-- ── Skill 3: Blade Wave ─────────────────────────────────────
function SwordSkills:_bladeWave(id, payload, pose, now)
	local d = self._def.skills[3]
	if self:isBusy(id) then
		return false, "busy"
	end
	local ok, reason = self._core.cooldown:tryUse(id, "skill3", d.cooldown, now)
	if not ok then
		return false, reason
	end
	local ids, dir = self:_arcTargets(id, payload, pose, d.range, d.arcDegrees)
	local attackId = self._d.nextAttackId(id)
	local hits = {}
	for _, tid in ids do
		local r = self:_strike(id, tid, d.damage, { attackId = attackId, kind = "Melee", blockable = true, sourcePos = pose.pos }, now, true)
		if r.applied then
			table.insert(hits, tid)
		end
	end
	self._d.approve(id, d, now)
	self._d.stopRunning(id)
	self._d.setSlow(id, now + 0.3, 0.7)
	self._d.emit({ type = "SwordSkill", skill = "BladeWave", playerId = id, hits = hits, direction = dir, range = d.range, arc = d.arcDegrees, time = now })
	return true, { hits = hits }
end

-- 스킬 1~3 진입점. 반환: ok, info|reason
function SwordSkills:skill(id, slot, payload, pose, now)
	if slot == 1 then
		if self:isBusy(id) then
			return false, "busy"
		end
		return self:_tripleSlash(id, payload, pose, now)
	elseif slot == 2 then
		return self:_lunge2(id, payload, pose, now)
	elseif slot == 3 then
		return self:_bladeWave(id, payload, pose, now)
	end
	return false, "skill_not_implemented"
end

-- ── Ultimate: Blade Storm ───────────────────────────────────
-- 게이지 소모(UltimateService.activate)가 성공한 뒤에만 호출한다.
function SwordSkills:startStorm(id, now)
	self._counter += 1
	self._storm[id] = { startAt = now, nextTick = 1, finisherDone = false, serial = self._counter }
	self._d.stopRunning(id)
	self._d.emit({ type = "SwordSkill", skill = "BladeStorm", phase = "Start", playerId = id, time = now })
end

function SwordSkills:endStorm(id, reason, now)
	if self._storm[id] then
		self._storm[id] = nil
		self._d.emit({ type = "SwordSkill", skill = "BladeStorm", phase = "End", playerId = id, reason = reason, time = now })
	end
end

function SwordSkills:_stormHit(id, s, kind, index, amount, now)
	local u = self._def.ultimate
	local pose = self._d.getPose(id)
	if not pose then
		return 0
	end
	local cands = {}
	for _, t in self._d.targets() do
		if t.id ~= id and t.alive ~= false then
			table.insert(cands, { id = t.id, pos = t.pos, radius = t.radius, alive = true })
		end
	end
	local near = Hitbox.entitiesInRadius(pose.pos, u.radius, cands, function(a, b)
		return self._d.world.lineOfSight(a, b)
	end)
	local n = 0
	local attackId = string.format("storm%d_%s_%s%d", s.serial, tostring(id), kind, index)
	for _, e in near do
		local r = self._core.damage:applyDamage({
			attackerId = id, targetId = e.id, attackId = attackId, amount = amount, kind = "Melee",
			blockable = u.blockable == true, sourcePos = pose.pos,
		}, now)
		if r.applied then
			n += 1
		end
	end
	self._d.emit({
		type = "SwordSkill", skill = "BladeStorm", phase = kind == "tick" and "Tick" or "Finisher", index = index, playerId = id,
		hits = n, radius = u.radius, time = now,
	})
	return n
end

function SwordSkills:_updateStorm(id, now)
	local s = self._storm[id]
	if not s then
		return
	end
	local u = self._def.ultimate
	local guard = 0
	while s.nextTick <= u.ticks and now >= s.startAt + s.nextTick * u.tickInterval and guard < 16 do
		self:_stormHit(id, s, "tick", s.nextTick, u.tickDamage, now)
		s.nextTick += 1
		guard += 1
	end
	if not s.finisherDone and s.nextTick > u.ticks and now >= s.startAt + u.finisherAt then
		s.finisherDone = true
		self:_stormHit(id, s, "finisher", 1, u.finisherDamage, now)
	end
end

-- 서버 루프
function SwordSkills:update(now)
	for id in self._triple do
		self:_expireTriple(id, now)
	end
	for id in self._lunge do
		self:_updateLunge(id, nil, now)
	end
	for id in self._storm do
		self:_updateStorm(id, now)
	end
end

-- HUD 스냅샷용 스킬 상태
function SwordSkills:hudInfo(id, now)
	local cd = self._core.cooldown
	local sk = self._def.skills
	self:_expireTriple(id, now)
	local t = self._triple[id]
	local l = self._lunge[id]
	local combo = self._combo[id]
	local comboStep = 1
	if combo and combo.done > 0 and now - combo.lastAt <= self._def.primary.combo.resetSeconds then
		comboStep = combo.done + 1
	end
	return {
		skills = {
			{
				implemented = true, name = sk[1].name, readyAt = cd:readyAt(id, "skill1") or 0, total = sk[1].cooldown,
				state = t and "Chain" or nil, step = t and t.step or 0, steps = #sk[1].damages, windowUntil = t and t.windowUntil or nil,
			},
			{
				implemented = true, name = sk[2].name, readyAt = cd:readyAt(id, "skill2") or 0, total = sk[2].cooldown,
				state = l and l.state or nil, chargeFrac = (l and l.state == "charging") and math.clamp((now - l.startAt) / sk[2].chargeSeconds, 0, 1) or nil,
			},
			{ implemented = true, name = sk[3].name, readyAt = cd:readyAt(id, "skill3") or 0, total = sk[3].cooldown },
		},
		comboStep = comboStep,
		comboSteps = #self._def.primary.combo.damages,
		duelistLockedUntil = now + self._duelist:lockRemaining(id, now),
		stormActive = self._storm[id] ~= nil,
	}
end

return SwordSkills
