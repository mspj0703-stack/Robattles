--!nonstrict
-- SWORD 애니메이션 상태기계 (순수 로직, CLI 테스트 가능). 캐릭터 1명당 인스턴스 1개.
-- 입력: 서버 Feedback 이벤트(onEvent), 이동 상태(setLocomotion), 시각(update 의 now).
-- 출력: update(now) → 포즈(MotionMath 형식) 또는 nil(에셋 모션 구동 중 = Animator 출력을 그대로 둔다).
-- 이 모듈은 전투 판정·이동·Remote 를 전혀 건드리지 않는다. 서버가 이미 확정한 이벤트를 시각으로만 옮긴다.
--
-- 우선순위: 새 모션 priority ≥ 현재 모션 priority 이면 항상 재생. 낮으면 현재 모션의 commit 시간이 지난 뒤에만 끊고,
-- Blade Storm 중에는 priority 5 미만 모션을 모두 거부한다. 모든 모션에는 만료(duration 또는 hold 의 maxDuration)가 있어
-- 종료 이벤트가 유실돼도 자세가 고착되지 않는다.
local MotionMath = require(script.Parent.MotionMath)
local LocomotionPose = require(script.Parent.LocomotionPose)

local SwordAnimState = {}
SwordAnimState.__index = SwordAnimState

-- motions = { Motions = {...}, Locomotion = {...}, MaxCatchUp, DefaultBlendIn } (shared/Data/SwordMotions)
-- opts.assetDriven(id) → true 이면 그 모션은 절차 포즈 대신 Animator 트랙이 재생한다(출력 nil).
function SwordAnimState.new(motions, opts)
	opts = opts or {}
	return setmetatable({
		_data = motions,
		_assetDriven = opts.assetDriven,
		_action = nil, -- { id, def, start, duration, maxDuration, params, serial }
		_storm = nil, -- { start, lastTick }
		_dead = false,
		_last = nil, -- 직전 프레임 출력(전환 블렌드 기준)
		_blend = nil, -- { from, start, dur }
		_loco = LocomotionPose.new(),
		_log = {},
		_serial = 0,
	}, SwordAnimState)
end

function SwordAnimState:_emitLog(entry)
	table.insert(self._log, entry)
	if #self._log > 64 then
		table.remove(self._log, 1) -- 소비자가 없을 때 무한 증가 방지
	end
end

-- 에셋 재생기 등이 소비하는 재생/정지 로그. 호출하면 비운다. { kind="play"|"stop", id, serial, duration, speed } / { kind="stopAll" }
function SwordAnimState:drain()
	local out = self._log
	self._log = {}
	return out
end

function SwordAnimState:setLocomotion(speed, airborne)
	if type(speed) ~= "number" or speed ~= speed or speed < 0 then
		speed = 0
	end
	self._loco.speed = speed
	self._loco.airborne = airborne == true
end

function SwordAnimState:snapshot()
	local a = self._action
	return {
		actionId = a and a.id or nil,
		storm = self._storm ~= nil,
		dead = self._dead,
	}
end

function SwordAnimState:isIdle()
	return self._action == nil and not self._dead
end

local function elapsedOf(a, now)
	return now - a.start
end

function SwordAnimState:_expired(a, now)
	local el = elapsedOf(a, now)
	if a.def.hold then
		return el >= a.maxDuration
	end
	return el >= a.duration
end

-- 행동 모션 재생 시도. 반환: 재생했으면 true.
function SwordAnimState:_play(id, now, params, startAt)
	if self._dead then
		return false
	end
	local def = self._data.Motions[id]
	if def == nil then
		return false
	end
	local cur = self._action
	if cur ~= nil and not self:_expired(cur, now) then
		local stormLocked = self._storm ~= nil and def.priority < 5
		local pastCommit = elapsedOf(cur, now) >= (cur.def.commit or 0)
		local allowed = (def.priority >= cur.def.priority and not stormLocked) or (pastCommit and not stormLocked)
		if not allowed then
			return false
		end
	elseif self._storm ~= nil and def.priority < 5 then
		return false
	end
	params = params or {}
	local duration = params.duration or def.duration
	if type(duration) ~= "number" or duration ~= duration or duration <= 0.02 then
		duration = def.duration
	end
	local maxDuration = params.maxDuration or def.maxDuration
	if maxDuration ~= nil then
		maxDuration = math.max(maxDuration, duration) -- 만료 시각은 항상 모션 길이 이상
	end
	if self._last ~= nil then
		self._blend = { from = self._last, start = now, dur = def.blendIn or self._data.DefaultBlendIn or 0.04 }
	end
	if cur ~= nil then
		self:_emitLog({ kind = "stop", id = cur.id, serial = cur.serial }) -- 교체되는 모션의 에셋 트랙 정리
	end
	self._serial += 1
	self._action = {
		id = id, def = def, start = startAt or now, duration = duration, maxDuration = maxDuration or duration,
		params = params, serial = self._serial,
	}
	self:_emitLog({ kind = "play", id = id, serial = self._serial, duration = duration, speed = def.duration / duration })
	return true
end

function SwordAnimState:_clearAction(now, blendDur)
	if self._action ~= nil then
		self:_emitLog({ kind = "stop", id = self._action.id, serial = self._action.serial })
		if self._last ~= nil and blendDur ~= nil then
			self._blend = { from = self._last, start = now, dur = blendDur }
		end
	end
	self._action = nil
end

-- 사망·캐릭터 변경·리스폰: 재생 중이던 모든 모션을 정리하고 처음 상태로 돌린다.
function SwordAnimState:reset()
	if self._action ~= nil then
		self:_emitLog({ kind = "stop", id = self._action.id, serial = self._action.serial })
	end
	self._action = nil
	self._storm = nil
	self._blend = nil
	self._last = nil
	self._dead = false
	self._loco = LocomotionPose.new()
	self:_emitLog({ kind = "stopAll" })
end

-- 사망: 정리 후 Respawned/reset 전까지 모든 이벤트를 무시한다(출력은 nil → 포즈 적용 안 함).
function SwordAnimState:kill()
	self:reset()
	self._dead = true
end

function SwordAnimState:revive()
	self:reset()
end

-- 콤보/Triple Slash 단계 값 정규화: NaN·문자열·범위 밖은 1~3 으로 제한(비정상 값은 1단계)
local function stepOf(v)
	local n = tonumber(v)
	if n == nil or n ~= n then
		return 1
	end
	return math.clamp(math.floor(n), 1, 3)
end

local function lagOf(self, e, now)
	local maxLag = self._data.MaxCatchUp or 0.12
	local t = type(e.time) == "number" and e.time or now
	local lag = now - t
	if lag ~= lag or lag < 0 then
		return 0
	end
	return math.min(lag, maxLag)
end

-- 서버 Feedback 이벤트 1건 처리. 이 상태기계의 소유자 이벤트(playerId 일치)만 넘겨야 한다. 알 수 없는 이벤트는 무시.
function SwordAnimState:onEvent(e, now)
	if type(e) ~= "table" or type(e.type) ~= "string" then
		return
	end
	local t = e.type
	if t == "Died" then
		self:kill()
		return
	elseif t == "Respawned" then
		self:revive()
		return
	end
	if self._dead then
		return
	end
	local start = now - lagOf(self, e, now)
	if t == "Swing" then
		self:_play("Slash" .. stepOf(e.step), now, nil, start)
	elseif t == "Parry" then
		self:_play("ParryGuard", now, nil, start)
	elseif t == "ParrySuccess" then
		self:_play("ParryCounter", now, nil, start)
	elseif t == "SwordSkill" then
		self:_onSkill(e, now, start)
	end
end

function SwordAnimState:_onSkill(e, now, start)
	local skill, phase = e.skill, e.phase
	if skill == "TripleSlash" then
		self:_play("TripleSlash" .. stepOf(e.step), now, nil, start)
	elseif skill == "BladeWave" then
		self:_play("BladeWave", now, nil, start)
	elseif skill == "Lunge" then
		local cur = self._action
		if phase == "Charge" then
			local cs = tonumber(e.chargeSeconds)
			if cs == nil or cs ~= cs or cs < 0.1 then
				cs = 1.0
			end
			self:_play("LungeCharge", now, { duration = cs, maxDuration = cs + 1.2 }, start)
		elseif phase == "Dash" then
			local dash = type(e.dash) == "table" and e.dash or {}
			local dur = tonumber(dash.duration)
			self:_play("LungeRelease", now, { duration = dur, charge = e.charge }, start)
		elseif phase == "End" then
			if cur ~= nil and cur.id == "LungeRelease" then
				self:_clearAction(now, nil)
				self:_play("LungeRecover", now, nil, now)
			end
		elseif phase == "Cancel" then
			-- 충전 중 취소(피격·사망·회피 등): 충전/방출 모션을 끊고 빠르게 복귀한다
			if cur ~= nil and (cur.id == "LungeCharge" or cur.id == "LungeRelease") then
				self:_clearAction(now, nil)
				self:_play("LungeRecover", now, { duration = 0.2 }, now)
			end
		end
	elseif skill == "BladeStorm" then
		if phase == "Start" then
			self._storm = { start = now, lastTick = nil }
			-- 진행 중인 낮은 우선순위 모션은 폭풍 시작이 끊는다(storm 잠금은 _play 가 priority 5 로 통과시킨다)
			self:_play("StormStart", now, nil, start)
		elseif phase == "Tick" then
			if self._storm ~= nil then
				self._storm.lastTick = now
			end
		elseif phase == "Finisher" then
			if self._storm ~= nil then
				self:_play("StormFinisher", now, nil, start)
			end
		elseif phase == "End" then
			if self._storm ~= nil then
				self._storm = nil
				local cur = self._action
				if cur ~= nil and (cur.id == "StormStart" or cur.id == "StormLoop" or cur.id == "StormFinisher") then
					self:_clearAction(now, nil)
				end
				self:_play("StormRecover", now, nil, now)
			end
		end
	end
end

-- 매 프레임 호출. 반환: pose, info — pose 는 MotionMath 형식 또는 nil(사망 / 에셋 구동 중).
-- info = { action = 모션 id 또는 nil, weight = 행동 가중치, dead = bool, assetDriven = bool }
function SwordAnimState:update(now)
	if self._dead then
		return nil, { dead = true }
	end
	local p = self._data.Locomotion
	LocomotionPose.advance(self._loco, now, p)
	if self._storm ~= nil and now > self._storm.start + 3.8 then
		self._storm = nil -- 종료 이벤트 유실 대비: 최대 지속시간 뒤 폭풍 잠금 해제(액션 유무와 무관)
	end

	local a = self._action
	if a ~= nil and self:_expired(a, now) then
		local chain = a.def.next
		local wasHold = a.def.hold == true
		self:_clearAction(now, wasHold and 0.12 or nil)
		a = nil
		if chain ~= nil and self._storm ~= nil then
			self:_play(chain, now, nil, now)
			a = self._action
		end
	end

	local base = LocomotionPose.sample(self._loco, p)
	local composed = base
	local weight = 0
	local assetDriven = false
	if a ~= nil then
		if self._assetDriven ~= nil and self._assetDriven(a.id) then
			assetDriven = true
		else
			local def = a.def
			local el = elapsedOf(a, now)
			local scale = def.duration / a.duration
			local te = math.min(math.max(el * scale, 0), def.duration)
			local sample = MotionMath.sampleKeys(def.keys, te)
			if def.spin ~= nil and self._storm ~= nil then
				local j = sample[def.spin.joint]
				if j ~= nil then
					j[def.spin.field] += def.spin.degPerSec * (now - self._storm.start)
				end
			end
			if def.wobble ~= nil then
				local j = sample[def.wobble.joint]
				if j ~= nil then
					local prog = math.min(el / a.duration, 1)
					j[def.wobble.field] += math.sin(el * def.wobble.hz * math.pi * 2) * def.wobble.amp * prog
				end
			end
			if def.pulse ~= nil and self._storm ~= nil and self._storm.lastTick ~= nil then
				local k = 1 - (now - self._storm.lastTick) / def.pulse.decay
				if k > 0 then
					MotionMath.addOffsets(sample, def.pulse.add, k)
				end
			end
			weight = 1
			if not def.hold and def.fadeOut ~= nil and def.fadeOut > 0 then
				weight = MotionMath.clamp((a.duration - el) / def.fadeOut, 0, 1)
			end
			composed = MotionMath.layer(base, sample, weight)
		end
	end

	if assetDriven then
		self._last = nil -- Animator 출력 중에는 절차 블렌드 기준이 없다
		self._blend = nil
		return nil, { action = a.id, weight = 1, dead = false, assetDriven = true }
	end

	local blend = self._blend
	if blend ~= nil then
		local k = MotionMath.clamp((now - blend.start) / math.max(blend.dur, 1e-6), 0, 1)
		composed = MotionMath.lerpPose(blend.from, composed, MotionMath.ease("inout", k), true)
		if k >= 1 then
			self._blend = nil
		end
	end
	self._last = composed
	return composed, { action = a and a.id or nil, weight = weight, dead = false, assetDriven = false }
end

return SwordAnimState
