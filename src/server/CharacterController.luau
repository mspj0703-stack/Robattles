--!nonstrict
-- 플레이어별 서버 전투 상태와 캐릭터 동작(SWORD, PAINTBALL). RemoteGate를 통과한 입력만 받는다.
-- 서버가 최종 결정: 쿨타임·탄약·사거리·피해·명중. 클라이언트는 의사(어느 방향으로 쏘려는지)만 보낸다.
--
-- deps = {
--   core        CombatCore
--   projectiles ProjectileService
--   getPose(id) -> { pos, forward, airborne? } | nil     서버가 가진 캐릭터 자세
--   targets()   -> { {id, pos, radius, alive} }
--   world       { lineOfSight(a, b) -> boolean }
--   characters  Data/Characters (생략 시 공유 데이터)
--   config
--   allowMockUltimate  테스트 전용: 자리표시자 궁극기 실행 허용(실플레이에서는 항상 false/nil)
-- }
local Link = require(script.Parent.Link)
local ActionPolicy = require(script.Parent.ActionPolicy)
local Vec = Link.shared("Vec")
local Hitbox = require(script.Parent.HitboxService)
local SwordSkills = require(script.Parent.SwordSkills)
local PaintballSkills = require(script.Parent.PaintballSkills)

-- 캐릭터 데이터의 `module` 이름 → 서버 로직 모듈(Phase 2). 모듈이 없는 캐릭터는 공통 경로(근접/직선 발사)로 처리한다.
local IMPLS = {
	Paintball = PaintballSkills,
}

local CharacterController = {}
CharacterController.__index = CharacterController

local DEFAULT_CHARACTER = "SWORD" -- ASSUMPTION A34

function CharacterController.new(deps)
	local self = setmetatable({
		_cfg = deps.config or Link.shared("Config"),
		_core = deps.core,
		_projectiles = deps.projectiles,
		_getPose = deps.getPose,
		_targets = deps.targets,
		_world = deps.world,
		_movement = deps.movement, -- 선택: MovementValidator (A41)
		_chars = deps.characters or Link.shared("Data/Characters"),
		_p = {},
		_attackCounter = 0,
		_listeners = {},
		_lastPrune = 0,
		_allowMockUltimate = deps.allowMockUltimate == true,
	}, CharacterController)

	-- SWORD 전용 로직(콤보·스킬 1~3·궁극기·Duelist). 다른 캐릭터에는 영향이 없다.
	self._sword = SwordSkills.new({
		cfg = self._cfg,
		core = self._core,
		characters = self._chars,
		getPose = function(id)
			return self._getPose(id)
		end,
		targets = function()
			return self._targets()
		end,
		world = self._world,
		movement = self._movement,
		emit = function(event)
			self:_emit(event)
		end,
		approve = function(id, def, now)
			self:approveAction(id, def, now)
		end,
		nextAttackId = function(id)
			return self:_nextAttackId(id)
		end,
		setSlow = function(id, untilT, mult)
			local st = self._p[id]
			if st then
				st.slowUntil, st.slowMult = untilT, mult
			end
		end,
		stopRunning = function(id)
			local st = self._p[id]
			if st then
				st.running = false
			end
		end,
		canAct = function(id, now)
			local st = self._p[id]
			return st ~= nil and st.alive and self._core.damage:isAlive(id) and self._core.status:canAct(id, now)
		end,
	})

	-- 캐릭터별 모듈(PAINTBALL 등). 모든 모듈은 같은 deps 와 같은 인터페이스(primary/secondary/skill/ultimate*/update/reset/hudInfo)를 쓴다.
	self._impl = {}
	for characterId, def in self._chars do
		local ctor = def.module and IMPLS[def.module]
		if ctor then
			self._impl[characterId] = ctor.new({
				cfg = self._cfg,
				core = self._core,
				characters = self._chars,
				projectiles = self._projectiles,
				getPose = function(id)
					return self._getPose(id)
				end,
				targets = function()
					return self._targets()
				end,
				world = self._world,
				movement = self._movement,
				emit = function(event)
					self:_emit(event)
				end,
				approve = function(id, actionDef, now)
					self:approveAction(id, actionDef, now)
				end,
				nextAttackId = function(id)
					return self:_nextAttackId(id)
				end,
				setSlow = function(id, untilT, mult)
					local st = self._p[id]
					if st then
						st.slowUntil, st.slowMult = untilT, mult
					end
				end,
				stopRunning = function(id)
					local st = self._p[id]
					if st then
						st.running = false
					end
				end,
				canAct = function(id, now)
					local st = self._p[id]
					return st ~= nil and st.alive and self._core.damage:isAlive(id) and self._core.status:canAct(id, now)
				end,
				state = function(id)
					return self._p[id]
				end,
				startReload = function(id, now)
					local st = self._p[id]
					if st then
						self:_startReload(st, now)
					end
				end,
			})
		end
	end
	self._aim = {} -- [id] = 최근 Aim 리모트 방향(검증된 단위 벡터)

	-- 패링(확정): 방어 가능한 공격이 전방 180°에서 들어올 때만 차단하고 자동 반격한다.
	self._core.damage:addBlocker(function(req, now)
		return self:_parryBlocker(req, now)
	end)
	self._core.damage:onKilled(function(e)
		self._sword:onTargetGone(e.targetId)
		self:handleDeath(e.targetId, e.now)
	end)
	return self
end

function CharacterController:onFeedback(fn)
	table.insert(self._listeners, fn)
end

function CharacterController:_emit(event)
	for _, fn in self._listeners do
		fn(event)
	end
end

function CharacterController:_def(st)
	return self._chars[st.characterId]
end

function CharacterController:_resetCharacterState(st)
	local def = self._chars[st.characterId]
	st.ammo = def.ammo and def.ammo.magazine or 0
	st.reloadingUntil = 0
	st.parryUntil = 0
	st.parryId = (st.parryId or 0) + 1
	st.counteredBy = {}
	st.slowUntil = 0
	st.slowMult = 1
	st.protectedUntil = 0
	if self._sword then
		self._sword:reset(st.id)
	end
	if self._impl then
		for _, impl in self._impl do
			impl:reset(st.id, nil, "State")
		end
	end
	self._aim[st.id] = nil
end

-- 부활 보호 해제(서버 권위). reason: "Attack" | "Expired" | "Died". 이미 해제됐으면 아무것도 하지 않는다.
function CharacterController:_releaseProtection(id, st, now, reason)
	if (st.protectedUntil or 0) <= 0 then
		return false
	end
	st.protectedUntil = 0
	self._core.damage:clearProtection(id)
	if reason ~= "Died" then
		self:_emit({ type = "ProtectionEnded", playerId = id, reason = reason, time = now })
	end
	return true
end

-- 공통 "서버가 승인한 행동 시작" 처리. 모든 행동 핸들러(기본 공격, 보조 기술, 스킬 1·2·3, 궁극기, 설치/기폭 등 향후 행동)는
-- 거부 사유를 모두 통과한 뒤 이 함수를 한 번 호출해야 한다. 거부된 요청은 호출하지 않는다 → 보호 유지.
-- actionDef: 행동 정의(kind 및 판정 필드). 공격으로 분류되면(ActionPolicy) 부활 보호를 즉시 해제한다. 반환: 보호가 해제되었는가.
function CharacterController:approveAction(id, actionDef, now)
	local st = self._p[id]
	if not st or not st.alive then
		return false
	end
	if ActionPolicy.isOffensive(actionDef) then
		return self:_releaseProtection(id, st, now, "Attack")
	end
	return false
end

function CharacterController:isProtected(id, now)
	return self._core.damage:isProtected(id, now)
end

function CharacterController:addPlayer(id, characterId)
	local ch = characterId or DEFAULT_CHARACTER
	assert(self._chars[ch], "알 수 없는 캐릭터: " .. tostring(ch))
	self._core:addPlayer(id, ch, self._chars[ch].maxHealth)
	local st = { id = id, characterId = ch, running = false, alive = true }
	self._p[id] = st
	self:_resetCharacterState(st)
end

function CharacterController:removePlayer(id, now)
	for _, impl in self._impl do
		impl:reset(id, now, "Removed")
	end
	self._aim[id] = nil
	self._sword:reset(id)
	self._sword:onTargetGone(id)
	self._projectiles:ownerRemoved(id, now)
	self._core:removePlayer(id)
	self._p[id] = nil
end

-- 캐릭터 선택: 다음 리스폰부터 적용. 반환: "set" | "pending" | "unchanged"
function CharacterController:selectCharacter(id, characterId)
	if not self._p[id] or not self._chars[characterId] then
		return "unchanged"
	end
	return self._core:setCharacter(id, characterId)
end

function CharacterController:getCharacterId(id)
	local st = self._p[id]
	return st and st.characterId
end

function CharacterController:getMaxHealth(id)
	return self._core.damage:getMaxHealth(id)
end

function CharacterController:getAmmo(id)
	local st = self._p[id]
	return st and st.ammo or 0
end

function CharacterController:isReloading(id, now)
	local st = self._p[id]
	return st ~= nil and now < st.reloadingUntil
end

-- 방어 가능 + 전방 180° + 패링 창 안 → "parried". 방향·성공 여부는 서버 자세로만 판정한다.
function CharacterController:_parryBlocker(req, now)
	local st = self._p[req.targetId]
	if not st or not st.alive or not self._cfg.Parry.Enabled or now >= st.parryUntil then
		return nil
	end
	if req.blockable ~= true or req.attackerId == req.targetId then
		return nil -- 환경 피해·일반 광역 폭발·반격 피해 등은 차단하지 않음
	end
	local pose = self._getPose(req.targetId)
	if not pose then
		return nil
	end
	local dir
	if req.sourcePos then
		dir = Vec.sub(req.sourcePos, pose.pos)
	else
		dir = req.sourceDir
	end
	if not dir then
		return nil -- 공격 방향을 알 수 없으면 차단하지 않는다(보수적)
	end
	local fwd = Vec.flatten(pose.forward)
	if not fwd then
		return nil
	end
	local flatDir = Vec.flatten(dir)
	if flatDir then
		local half = (self:_def(st).secondary.frontArcDegrees or 180) / 2
		if Vec.angleDeg(fwd, flatDir) > half + 1e-6 then
			return nil -- 후방 공격은 차단하지 않음
		end
	end
	self:_onParrySuccess(req, st, pose, now)
	return "parried"
end

-- 차단 성공: 공격자가 유효 사거리 안일 때만 자동 반격(원거리 공격자에게는 원격 반격 없음).
-- 같은 패링에서 같은 공격자에게는 한 번만 반격한다(중복 반격 방지). 반격 피해는 방어 불가·재반격 없음.
function CharacterController:_onParrySuccess(req, st, pose, now)
	local sec = self:_def(st).secondary
	local attackerId = req.attackerId
	local countered = false
	if not st.counteredBy[attackerId] and self._core.damage:isAlive(attackerId) then
		local apose = self._getPose(attackerId)
		if apose then
			local reach = Vec.dist(apose.pos, pose.pos) - self._cfg.Combat.HitRadius
			if reach <= sec.counterRange + self._cfg.Net.MeleeRangeTolerance then
				local r = self._core.damage:applyDamage({
					attackerId = req.targetId,
					targetId = attackerId,
					attackId = string.format("counter%d_%s_%s", st.parryId, tostring(req.targetId), tostring(attackerId)),
					amount = sec.counterDamage,
					kind = "Counter",
					blockable = false,
				}, now)
				if r.applied then
					countered = true
					st.counteredBy[attackerId] = true
				end
			end
		end
	end
	self:_emit({
		type = "ParrySuccess", playerId = req.targetId, attackerId = attackerId, countered = countered,
		counterDamage = countered and sec.counterDamage or 0, time = now,
	})
end

function CharacterController:handleDeath(id, now)
	local st = self._p[id]
	if not st or not st.alive then
		return
	end
	st.alive = false
	for _, impl in self._impl do
		impl:reset(id, now, "Death")
	end
	self._aim[id] = nil
	self._sword:reset(id)
	self._sword:endStorm(id, "Death", now)
	self:_releaseProtection(id, st, now, "Died")
	st.reloadingUntil = 0
	st.parryUntil = 0
	st.running = false
	-- 빔 등 캐릭터 연결 효과만 종료. 이미 발사된 투사체/설치물은 남은 수명 동안 유지된다.
	self._projectiles:ownerDied(id, now)
	self:_emit({ type = "Died", playerId = id, time = now })
end

-- 부활: 대기 중이던 캐릭터 변경을 적용한다(궁극기 게이지 이월은 UltimateService가 처리).
function CharacterController:respawn(id, now)
	local st = self._p[id]
	if not st then
		return
	end
	self._core:respawn(id)
	self._sword:onTargetGone(id)
	self._projectiles:ownerRespawned(id)
	st.characterId = self._core.ultimate:getCharacter(id) or st.characterId
	st.alive = true
	self._core.damage:setMaxHealth(id, self:_def(st).maxHealth or self._cfg.Combat.MaxHealth, true) -- 캐릭터별 HP(확정)
	self:_resetCharacterState(st)
	-- 부활 보호: 부활 직후 RespawnProtectionSeconds 동안 피해 면역. 만료/공격 시작은 서버가 판정한다.
	local protectSeconds = self._cfg.Match.RespawnProtectionSeconds
	if protectSeconds and protectSeconds > 0 then
		st.protectedUntil = now + protectSeconds
		self._core.damage:setProtection(id, st.protectedUntil)
	end
	self:_emit({ type = "Respawned", playerId = id, characterId = st.characterId, protectedUntil = st.protectedUntil, time = now })
end

function CharacterController:_actionable(id, now)
	local st = self._p[id]
	if not st then
		return nil, "no_player"
	end
	if not st.alive or not self._core.damage:isAlive(id) then
		return nil, "dead"
	end
	if not self._core.status:canAct(id, now) then
		return nil, "cannot_act"
	end
	return st, nil
end

function CharacterController:_nextAttackId(id)
	self._attackCounter += 1
	return string.format("atk%d_%s", self._attackCounter, tostring(id))
end

function CharacterController:_startReload(st, now)
	local def = self:_def(st)
	st.reloadingUntil = now + def.ammo.reloadSeconds
end

-- payload = { action = "Primary"|"Secondary", aimDirection, ... } (RemoteGate 통과 후)
function CharacterController:handleAttack(id, payload, now)
	local st, why = self:_actionable(id, now)
	if not st then
		return false, why
	end
	local pose = self._getPose(id)
	if not pose then
		return false, "no_pose"
	end
	local def = self:_def(st)
	local impl = self._impl[st.characterId]
	if impl then
		-- 캐릭터 모듈이 거부 사유를 모두 확인한 뒤 approveAction 을 직접 호출한다(거부되면 보호·쿨타임·탄약 불변).
		if payload.action == "Secondary" then
			return impl:secondary(id, payload, pose, now)
		end
		return impl:primary(id, payload, pose, now)
	end
	if payload.action == "Secondary" then
		if self._sword:isBusy(id) then
			return false, "busy"
		end
		local okSec, infoSec = self:_secondary(id, st, def, now)
		if okSec then
			self:approveAction(id, def.secondary, now) -- 패링은 비공격, 공격형 보조 기술은 공격
		end
		return okSec, infoSec
	end
	local prim = def.primary
	local ok, info
	if prim.combo then
		ok, info = self._sword:primary(id, payload, pose, now) -- SWORD 3타 콤보
	elseif prim.kind == "Melee" then
		ok, info = self:_melee(id, st, prim, payload, pose, now)
	else
		ok, info = self:_fire(id, st, def, prim, payload, pose, now)
	end
	if ok then
		self:approveAction(id, prim, now) -- 승인된 공격 시작 = 공통 처리(보호 해제 여부는 ActionPolicy 가 판단)
	end
	return ok, info
end

function CharacterController:_melee(id, st, prim, payload, pose, now)
	local ok, reason = self._core.cooldown:tryUse(id, "primary", prim.cooldown, now)
	if not ok then
		return false, reason
	end
	local targets = self._targets()
	-- 근접만 약한 방향 보정
	local dir = Hitbox.assistedMeleeDirection(payload.aimDirection, pose.pos, targets, self._cfg.Camera.MeleeAimAssistDegrees, id, prim.range)
	local ids = Hitbox.selectMeleeTargets({ pos = pose.pos, forward = dir }, targets, {
		attackerId = id,
		range = prim.range,
		arcDegrees = prim.arcDegrees,
		tolerance = self._cfg.Net.MeleeRangeTolerance,
		lineOfSight = self._world.lineOfSight,
	})
	local attackId = self:_nextAttackId(id)
	local hits = {}
	for _, tid in ids do
		local tpos
		for _, t in targets do
			if t.id == tid then
				tpos = t.pos
			end
		end
		local effects = {}
		local away = Vec.flatten(Vec.sub(tpos, pose.pos))
		if prim.knockback and prim.knockback > 0 and away then
			table.insert(effects, { type = "Knockback", direction = away, power = prim.knockback, upward = 0 })
		end
		local r = self._core.damage:applyDamage({
			attackerId = id,
			targetId = tid,
			attackId = attackId,
			amount = prim.damage,
			kind = "Melee",
			blockable = true, -- 일반 근접 공격은 방어 가능
			sourcePos = pose.pos,
			strong = prim.stagger == true, -- 기본 공격은 경직 없음
			effects = effects,
		}, now)
		if r.applied then
			table.insert(hits, tid)
		end
	end
	st.slowUntil, st.slowMult = now + prim.cooldown, prim.moveSpeedMult -- ASSUMPTION A32
	st.running = false -- 확정: 공격 시 달리기 해제
	self:_emit({ type = "Swing", playerId = id, hits = hits, time = now })
	return true, { hits = hits }
end

function CharacterController:_fire(id, st, def, prim, payload, pose, now)
	if now < st.reloadingUntil then
		return false, "reloading"
	end
	if st.ammo <= 0 then
		self:_startReload(st, now)
		return false, "no_ammo"
	end
	local ok, reason = self._core.cooldown:tryUse(id, "primary", prim.fireInterval, now)
	if not ok then
		return false, reason
	end
	local origin = Vec.add(pose.pos, { X = 0, Y = self._cfg.Combat.EyeHeight, Z = 0 })
	local dir = Hitbox.rangedDirection(payload.aimDirection) -- 원거리 자동 조준 보정 없음
	local pid, err = self._projectiles:spawn({
		def = prim.projectile,
		ownerId = id,
		origin = origin,
		direction = dir,
		strong = prim.stagger == true,
	}, now)
	if not pid then
		self._core.cooldown:clearEntity(id)
		return false, err
	end
	st.ammo -= 1
	if st.ammo == 0 then
		self:_startReload(st, now)
	end
	st.slowUntil, st.slowMult = now + prim.fireInterval, prim.moveSpeedMult
	st.running = false -- 확정: 공격 시 달리기 해제
	return true, { projectileId = pid, ammo = st.ammo }
end

function CharacterController:_secondary(id, st, def, now)
	local sec = def.secondary
	if not sec then
		return false, "no_secondary"
	end
	if sec.kind == "Parry" then
		local ok, reason = self._core.cooldown:tryUse(id, "secondary", sec.cooldown, now)
		if not ok then
			return false, reason
		end
		st.parryId += 1
		st.counteredBy = {}
		st.parryUntil = now + sec.windowSeconds
		st.running = false -- 확정: 공격 시 달리기 해제
		st.slowUntil, st.slowMult = now + sec.windowSeconds, sec.moveSpeedMult
		self:_emit({ type = "Parry", playerId = id, until_ = st.parryUntil, time = now })
		return true, { parryUntil = st.parryUntil }
	end
	return false, "unsupported_secondary"
end

-- 숫자 1·2·3 일반 스킬. 구현된 캐릭터(SWORD)만 처리하고 나머지는 쿨타임·자원 소모 없이 거부한다.
-- 구현된 스킬은 모든 거부 사유를 통과한 뒤 approveAction 을 한 번 호출한다(공격형이면 부활 보호 해제). 거부된 요청은 보호를 유지한다.
function CharacterController:handleSkill(id, payload, now)
	local st = self._p[id]
	if not st then
		return false, "no_player"
	end
	local def = self:_def(st)
	if def.skills == nil or def.skills[payload.slot] == nil then
		-- 미구현 캐릭터 스킬: 상태 확인 사유를 우선해 기존 거부 순서를 유지한다.
		local _, why = self:_actionable(id, now)
		return false, why or "skill_not_implemented"
	end
	-- 충전 해제(Release)는 기절 등으로 행동 불가여도 서버가 정리할 수 있게 상태 검사 전에 처리한다.
	if payload.phase == "Release" then
		if not st.alive or not self._core.damage:isAlive(id) then
			return false, "dead"
		end
		local pose = self._getPose(id)
		if not pose then
			return false, "no_pose"
		end
		return (self._impl[st.characterId] or self._sword):skill(id, payload.slot, payload, pose, now)
	end
	local okAct, why = self:_actionable(id, now)
	if not okAct then
		return false, why
	end
	local pose = self._getPose(id)
	if not pose then
		return false, "no_pose"
	end
	return (self._impl[st.characterId] or self._sword):skill(id, payload.slot, payload, pose, now)
end

-- Aim 리모트: 시전 중 조준 갱신(Color Break 등). 모듈이 쓰지 않는 상태에서는 저장만 한다(무해).
function CharacterController:handleAim(id, payload, now)
	local st, why = self:_actionable(id, now)
	if not st then
		return false, why
	end
	local dir = Vec.normalize(payload.aimDirection)
	if not dir then
		return false, "bad_direction"
	end
	self._aim[id] = dir
	local impl = self._impl[st.characterId]
	if impl and impl.onAim then
		return impl:onAim(id, dir, now), nil
	end
	return false, "no_aim_use"
end

function CharacterController:handleReload(id, now)
	local st, why = self:_actionable(id, now)
	if not st then
		return false, why
	end
	local def = self:_def(st)
	if not def.ammo then
		return false, "no_reload"
	end
	if now < st.reloadingUntil then
		return false, "already_reloading"
	end
	if st.ammo >= def.ammo.magazine then
		return false, "full"
	end
	self:_startReload(st, now)
	return true, { reloadSeconds = def.ammo.reloadSeconds }
end

function CharacterController:handleDodge(id, payload, now)
	local st, why = self:_actionable(id, now)
	if not st then
		return false, why
	end
	local pose = self._getPose(id)
	local movement = self._movement
	local claimedAir = pose ~= nil and pose.airborne == true
	-- 서버 이동 검증(A41): 공중 회피 횟수/방향을 충전 소비 전에 확인한다.
	if movement and pose then
		local okMove, whyMove = movement:canDodge(id, pose.pos, claimedAir, now)
		if not okMove then
			return false, whyMove
		end
	end
	local ok, info = self._core.dodge:tryDodge(id, now, { airborne = claimedAir, canAct = true })
	if not ok then
		return false, info
	end
	info.direction = payload.direction
	self._sword:onDodge(id, now)
	if movement and pose then
		local plan = movement:planDodge(id, pose.pos, payload.direction, claimedAir, now)
		if plan then
			info.direction = plan.direction
			info.distance = plan.distance -- 벽에 막히면 줄어든 거리를 클라이언트에 알린다
			info.blocked = plan.blocked
			info.airborne = plan.airborne
			info.origin = pose.pos
		end
	end
	self:_emit({ type = "Dodge", playerId = id, info = info, time = now })
	return true, info
end

function CharacterController:handleSetRun(id, enabled)
	local st = self._p[id]
	if not st or not st.alive then
		return false, "dead"
	end
	st.running = enabled
	return true, nil
end

function CharacterController:handleUltimate(id, payload, now)
	local st, why = self:_actionable(id, now)
	if not st then
		return false, why
	end
	local def = self:_def(st)
	-- 효과가 구현되지 않은 궁극기는 게이지를 소모하지 않고 거부한다(테스트 전용 모의 실행만 예외).
	if def.ultimate == nil or def.ultimate.placeholder == true then
		if not self._allowMockUltimate then
			return false, "ultimate_not_implemented"
		end
	end
	local impl = self._impl[st.characterId]
	if impl then
		local pose = self._getPose(id)
		if not pose then
			return false, "no_pose"
		end
		-- 게이지를 쓰기 전에 모든 거부 사유를 확인한다.
		local okPre, whyPre = impl:canUltimate(id, payload, pose, now)
		if not okPre then
			return false, whyPre
		end
		local ok, reason = self._core.ultimate:activate(id, now, impl:ultimateDef(id, now), { canAct = true })
		if not ok then
			return false, reason
		end
		self:approveAction(id, { kind = "Ultimate" }, now)
		impl:startUltimate(id, payload, pose, now)
		self:_emit({ type = "Ultimate", playerId = id, time = now })
		return true, nil
	end
	local isSword = def.ultimate ~= nil and def.ultimate.id == "BladeStorm"
	if isSword and self._sword:isBusy(id) then
		return false, "busy" -- 게이지를 소모하기 전에 거부
	end
	local ultDef = def.ultimate
	if isSword then
		ultDef = {
			duration = def.ultimate.duration,
			onEnd = function(reason)
				self._sword:endStorm(id, reason, now)
			end,
		}
	end
	local ok, reason = self._core.ultimate:activate(id, now, ultDef, { canAct = true })
	if not ok then
		return false, reason
	end
	self:approveAction(id, { kind = "Ultimate" }, now)
	if isSword then
		self._sword:startStorm(id, now)
	end
	self:_emit({ type = "Ultimate", playerId = id, time = now })
	return true, nil
end

-- HUD용 권위 상태 스냅샷(서버 시각 기준). 클라이언트는 이 값으로 표시·달리기 상태를 맞춘다.
function CharacterController:getHudSnapshot(id, now)
	local st = self._p[id]
	if not st then
		return nil
	end
	local def = self:_def(st)
	local core = self._core
	local snap = {
		t = now,
		characterId = st.characterId,
		pendingCharacterId = core.ultimate:getPendingCharacter(id),
		alive = st.alive and core.damage:isAlive(id),
		health = { cur = core.damage:getHealth(id), max = core.damage:getMaxHealth(id) },
		running = st.running,
		moveSpeed = self:getMoveSpeed(id, now),
		canAct = core.status:canAct(id, now),
		cooldowns = {
			primary = { readyAt = core.cooldown:readyAt(id, "primary") or 0 },
			secondary = {
				readyAt = core.cooldown:readyAt(id, "secondary") or 0,
				total = def.secondary and def.secondary.cooldown or nil,
			},
		},
		dodge = core.dodge:getState(id, now),
		ultimate = {
			gauge = core.ultimate:getGauge(id),
			max = self._cfg.Ultimate.Max,
			active = core.ultimate:isActive(id),
			implemented = not (def.ultimate == nil or def.ultimate.placeholder == true),
		},
		skills = { { implemented = false }, { implemented = false }, { implemented = false } },
		passive = def.passive and { id = def.passive.id } or nil,
		parryUntil = st.parryUntil,
		protectedUntil = st.protectedUntil > 0 and st.protectedUntil or nil,
		protectSeconds = self._cfg.Match.RespawnProtectionSeconds,
		hasSecondary = def.secondary ~= nil,
	}
	if def.skills and not self._impl[st.characterId] then
		local info = self._sword:hudInfo(id, now)
		snap.skills = info.skills
		snap.combo = { step = info.comboStep, steps = info.comboSteps }
		snap.passive = { id = def.passive.id, lockedUntil = info.duelistLockedUntil }
		snap.ultimate.name = def.ultimate.name
		snap.ultimate.active = snap.ultimate.active or info.stormActive
	end
	local implHud = self._impl[st.characterId]
	if implHud then
		local info = implHud:hudInfo(id, now)
		snap.skills = info.skills
		snap.passive = info.passive
		snap.extra = info.extra
		if info.secondary then
			snap.cooldowns.secondary = info.secondary
		end
		if info.ultimate then
			snap.ultimate.name = info.ultimate.name
			snap.ultimate.active = snap.ultimate.active or info.ultimate.active
			snap.ultimate.windupUntil = info.ultimate.windupUntil
		end
	end
	if def.ammo then
		snap.ammo = { cur = st.ammo, mag = def.ammo.magazine, reloadingUntil = st.reloadingUntil, reloadSeconds = def.ammo.reloadSeconds }
	end
	return snap
end

-- 서버가 설정할 WalkSpeed. 달리기 토글 × 상태이상 × 공격/패링 중 보정.
function CharacterController:getMoveSpeed(id, now)
	local st = self._p[id]
	if not st or not st.alive then
		return 0
	end
	local base = st.running and self._cfg.Movement.RunSpeed or self._cfg.Movement.WalkSpeed
	local mult = self._core.status:getSpeedMultiplier(id, now)
	if now < st.slowUntil then
		mult *= st.slowMult
	end
	return base * mult
end

-- 서버 루프(Heartbeat)에서 호출
function CharacterController:update(now, dt)
	for id, st in self._p do
		if st.alive and (st.protectedUntil or 0) > 0 and now >= st.protectedUntil then
			self:_releaseProtection(id, st, now, "Expired")
		end
		if st.alive and st.reloadingUntil > 0 and now >= st.reloadingUntil then
			local def = self:_def(st)
			st.ammo = def.ammo.magazine
			st.reloadingUntil = 0
			self:_emit({ type = "Reloaded", playerId = id, time = now })
		end
	end
	self._core.ultimate:tick(dt)
	self._sword:update(now) -- 돌진 경로 판정, Blade Storm 틱/마무리는 궁극기 종료 처리보다 먼저
	for _, impl in self._impl do
		impl:update(now) -- 캐릭터 모듈의 지속 효과(빔 틱 등)도 궁극기 종료 처리보다 먼저
	end
	self._core.ultimate:update(now)
	self._projectiles:step(now)
	if now - self._lastPrune >= 1 then
		self._lastPrune = now
		self._core.damage:prune(now)
	end
end

return CharacterController
