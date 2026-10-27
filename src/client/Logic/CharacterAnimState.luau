--!nonstrict
-- SWORD 외 캐릭터(PAINTBALL, SLINGSHOT …) 애니메이션 상태기계 (순수 로직, CLI 테스트 가능). 캐릭터 1명당 인스턴스 1개.
-- SwordAnimState 의 우선순위/커밋/만료/블렌드/사망 정리 규칙을 그대로 쓰고, 이벤트 → 모션 매핑만 캐릭터별로 바꾼다.
-- 서버가 이미 확정한 Feedback 이벤트(Spawned/Reloaded/CharSkill/Died/Respawned)를 시각으로만 옮긴다. 전투 판정·이동·Remote 와 무관.
--
-- 궁극기(ColorBreak / Bullseye)는 SwordAnimState 의 `_storm` 잠금을 그대로 써서 priority 5 미만 모션을 막고,
-- 종료 이벤트가 유실돼도 SwordAnimState.update 의 폭풍 잠금 최대 지속시간(3.8초)과 hold 모션의 maxDuration 으로 풀린다.
-- 12초짜리 Ball Cyclone 처럼 3.8초보다 오래 가는 궁극기는 `_longUlt` 가 잠금 시각을 갱신해 서버가 알려 준 duration 동안만 유지하고,
-- 그 시각(+1초 여유)이 지나면 End 이벤트가 없어도 스스로 풀린다. (GPT 의 Blade Storm Tick 패치와의 충돌 지점: docs/CHARACTER_ANIMATION.md)
local SwordAnimState = require(script.Parent.SwordAnimState)
local GunLocomotion = require(script.Parent.GunLocomotion)
local MotionMath = require(script.Parent.MotionMath)

local CharacterAnimState = setmetatable({}, { __index = SwordAnimState })
CharacterAnimState.__index = CharacterAnimState

-- data = CharacterMotions[characterId]. opts.assetDriven(id) 는 SwordAnimState 와 동일.
function CharacterAnimState.new(characterId, data, opts)
	opts = opts or {}
	local self = SwordAnimState.new(data, { assetDriven = opts.assetDriven, baseSampler = GunLocomotion.sample })
	self._cid = characterId
	self._longUlt = nil -- { start, untilT, holdId } 3.8초 넘게 지속되는 궁극기(Ball Cyclone)
	self._pendingRelease = nil -- { at, serial } 로컬 입력 해제 후 서버 확인을 기다리는 충전 모션
	return setmetatable(self, CharacterAnimState)
end

-- 사망·리스폰·캐릭터 변경·매치 종료(reset)에서 서브클래스 상태도 함께 비운다(SwordAnimState.kill/revive 가 reset 을 호출한다).
function CharacterAnimState:reset()
	self._longUlt = nil
	self._pendingRelease = nil
	SwordAnimState.reset(self)
end

-- 충전 모션: 입력 해제를 서버가 받아들이지 않으면(쿨다운·사망 직전 등) 종료 이벤트가 오지 않는다.
local CHARGE_IDS = { SlingCharge = true, BallCharge = true }
local RELEASE_GRACE = 0.4 -- 로컬 해제 후 서버 발사 이벤트를 기다리는 시간(지연이 커도 이후에 이벤트가 오면 정상 재생)

-- hold 모션을 이어 붙일 때 남은 궁극기 시간만큼만 유지하도록 만료를 정한다(chain 은 params 없이 호출된다).
function CharacterAnimState:_play(id, now, params, startAt)
	local lu = self._longUlt
	if params == nil and lu ~= nil and id == lu.holdId then
		params = { maxDuration = math.max(lu.untilT - now - 0.5, 0.35) }
	end
	return SwordAnimState._play(self, id, now, params, startAt)
end

function CharacterAnimState:characterId()
	return self._cid
end

-- 테스트 전용: 현재 궁극기 잠금 테이블(없으면 nil)
function CharacterAnimState:_stormForTest()
	return self._storm
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

local function positive(v, default, lo, hi)
	local n = tonumber(v)
	if n == nil or n ~= n or n < lo then
		return default
	end
	return math.min(n, hi)
end

-- 서버 Feedback 이벤트 1건 처리(소유자 이벤트만 넘길 것). 알 수 없는 이벤트·다른 캐릭터의 cue 는 무시한다.
-- 추가 합성 이벤트(본인 화면 전용, 서버 이벤트 없음):
--   { type = "ReloadStart" }  — 재장전 시작(로컬 State 스냅샷에서 감지)
--   { type = "LocalRelease" } — 충전 입력 해제(로컬 입력). 서버 확인이 grace 안에 없으면 충전 자세를 푼다.
function CharacterAnimState:onEvent(e, now)
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
	if t == "LocalRelease" then
		local cur = self._action
		if cur ~= nil and CHARGE_IDS[cur.id] then
			self._pendingRelease = { at = now, serial = cur.serial }
		end
		return
	end
	local start = now - lagOf(self, e, now)
	if self._cid == "SUPERBALL" then
		self:_onSuperball(e, now, start)
	elseif self._cid == "TIMEBOMB" then
		self:_onTimebomb(e, now, start)
	elseif self._cid == "PAINTBALL" then
		self:_onPaintball(e, now, start)
	elseif self._cid == "SLINGSHOT" then
		self:_onSlingshot(e, now, start)
	end
end

-- 궁극기 잠금 상태. lastActivity 는 GPT 의 Blade Storm Tick 패치(SwordAnimState: 잠금 해제 = lastActivity + 2초)가 읽는 필드다.
-- 현재 기준 코드(a598bcb)는 읽지 않는 여분 필드이지만, 패치가 병합돼도 nil 연산 오류가 나지 않도록 항상 채운다.
local function newStorm(now, tick)
	return { start = now, lastTick = tick, lastActivity = now }
end

local function touchStorm(self, now)
	if self._storm ~= nil then
		self._storm.lastActivity = now
	end
end

local function isUlt(a, prefix)
	return a ~= nil and string.sub(a.id, 1, #prefix) == prefix
end

-- ── PAINTBALL ───────────────────────────────────────────────
function CharacterAnimState:_onPaintball(e, now, start)
	local t = e.type
	if t == "Spawned" then
		if e.defId == "paint_shot" then
			self:_play("PaintFire", now, nil, start) -- 자동 연사: 발사체 생성마다 짧은 반동
		end
	elseif t == "ReloadStart" then
		self:_play("PaintReload", now, nil, now)
	elseif t == "Reloaded" then
		local cur = self._action
		if cur ~= nil and cur.id == "PaintReload" then
			self:_clearAction(now, nil) -- 로컬 장전 모션이 남아 있으면 끊고 완료 동작으로 이어 붙인다
		end
		self:_play("PaintReloadDone", now, nil, start)
	elseif t == "CharSkill" then
		local cue = e.cue
		if cue == "paint.burst" then
			self:_play("PaintBurst", now, nil, start)
		elseif cue == "paint.bomb.throw" then
			self:_play("BombThrow", now, nil, start)
		elseif cue == "paint.pierce.fire" then
			self:_play("PierceFire", now, nil, start)
		elseif cue == "paint.slide" then
			local dash = type(e.dash) == "table" and e.dash or {}
			self:_play("PaintSlide", now, { duration = positive(dash.duration, nil, 0.1, 2) }, start)
		elseif e.skill == "ColorBreak" then
			self:_onColorBreak(e, now, start)
		end
	end
end

function CharacterAnimState:_onColorBreak(e, now, start)
	local phase = e.phase
	if phase == "Windup" then
		self._storm = newStorm(now, nil)
		local w = positive(e.windup, 0.8, 0.1, 3)
		self:_play("ColorBreakWindup", now, { duration = w }, start)
	elseif phase == "Tick" then
		if self._storm == nil then
			return
		end
		self._storm.lastTick = now
		touchStorm(self, now)
		local cur = self._action
		if cur == nil or cur.id == "ColorBreakWindup" then
			self:_play("ColorBreakBeam", now, nil, now) -- 전조가 끝나기 전에 첫 틱이 오면 즉시 빔 자세로
			cur = self._action
		end
		if cur ~= nil and cur.id == "ColorBreakBeam" then
			-- 서버 틱을 따라 유지 시간 연장: 틱 횟수·간격이 바뀌어도 빔 자세가 유지/종료된다
			cur.maxDuration = math.max(cur.maxDuration, (now - cur.start) + (cur.def.tickExtend or 0.6))
		end
	elseif phase == "End" then
		if self._storm ~= nil then
			self._storm = nil
			if isUlt(self._action, "ColorBreak") then
				self:_clearAction(now, nil)
			end
			self:_play("ColorBreakRecover", now, nil, now)
		end
	end
end

-- ── SLINGSHOT ───────────────────────────────────────────────
function CharacterAnimState:_onSlingshot(e, now, start)
	if e.type ~= "CharSkill" then
		return
	end
	local cue = e.cue
	if cue == "sling.charge" then
		local cs = positive(e.chargeSeconds, 1.0, 0.1, 5)
		self:_play("SlingCharge", now, { duration = cs, maxDuration = 5.0 + 0.5 }, start)
	elseif cue == "sling.shot" then
		local cur = self._action
		if cur ~= nil and cur.id == "SlingCharge" then
			self:_clearAction(now, nil) -- 충전 해제: 방출 반동으로 이어 붙인다
		end
		self:_play("SlingRelease", now, nil, start)
	elseif cue == "sling.triple" then
		self:_play("SlingTriple", now, nil, start)
	elseif cue == "sling.snare" then
		self:_play("SlingSnare", now, nil, start)
	elseif cue == "sling.backstep" then
		local dash = type(e.dash) == "table" and e.dash or {}
		self:_play("SlingBackstep", now, { duration = positive(dash.duration, nil, 0.1, 2) }, start)
	elseif e.skill == "Bullseye" then
		local phase = e.phase
		if phase == "Windup" then
			self._storm = newStorm(now, nil)
			local w = positive(e.windup, 0.7, 0.1, 3)
			self:_play("BullseyeAim", now, { duration = w }, start)
		elseif phase == "Fire" then
			if self._storm ~= nil then
				touchStorm(self, now)
				self:_play("BullseyeFire", now, nil, start)
			end
		elseif phase == "End" then
			if self._storm ~= nil then
				self._storm = nil
				local cur = self._action
				if cur ~= nil and cur.id == "BullseyeAim" then
					self:_clearAction(now, nil) -- 발사 없이 종료(중단): 조준 자세에서 복귀
					self:_play("BullseyeRecover", now, nil, now)
				end
				-- BullseyeFire 는 자체 길이로 끝난다. 이미 끝난 경우 Idle 레이어가 이어받는다.
			end
		end
	end
end

-- ── SUPERBALL ───────────────────────────────────────────────
function CharacterAnimState:_onSuperball(e, now, start)
	if e.type ~= "CharSkill" then
		return
	end
	local cue = e.cue
	if cue == "ball.charge" then
		self:_play("BallCharge", now, { duration = positive(e.chargeSeconds, 1.0, 0.1, 4) }, start)
	elseif cue == "ball.throw" or cue == "ball.throw.charged" then
		local cur = self._action
		if cur ~= nil and cur.id == "BallCharge" then
			self:_clearAction(now, nil) -- 충전 해제: 투구 동작으로 이어 붙인다
		end
		self:_play(cue == "ball.throw.charged" and "BallThrowCharged" or "BallThrow", now, nil, start)
	elseif cue == "ball.dash" then
		local dash = type(e.dash) == "table" and e.dash or {}
		self:_play("BounceDash", now, { duration = positive(dash.duration, nil, 0.1, 2) }, start)
	elseif cue == "ball.rapid" then
		self:_play("RapidBounce", now, nil, start)
	elseif cue == "ball.scatter" then
		self:_play("ScatterBall", now, nil, start)
	elseif cue == "ball.recall" then
		self:_play("Recall", now, nil, start)
	elseif e.skill == "BallCyclone" then
		local phase = e.phase
		if phase == "Start" then
			local dur = positive(e.duration, 12, 1, 30)
			self._storm = newStorm(now, now)
			self._longUlt = { start = now, untilT = now + dur + 1.0, holdId = "CycloneSpin" }
			self:_play("CycloneStart", now, nil, start)
		elseif phase == "Shot" then
			if self._storm ~= nil then
				touchStorm(self, now)
				self:_play("CycloneShot", now, nil, start)
			end
		elseif phase == "End" then
			if self._storm ~= nil then
				self._storm = nil
				self._longUlt = nil
				if isUlt(self._action, "Cyclone") then
					self:_clearAction(now, nil)
				end
				self:_play("CycloneRecover", now, nil, now)
			end
		end
	end
end

-- ── TIMEBOMB ────────────────────────────────────────────────
-- 서버 폭발 시각(BombLand/BombExplode/BombEnd, 퓨즈 1·3초 뒤)은 모션과 무관하다. 모션은 던지기·설치·기폭 "입력 이벤트" 시각에만 맞춘다.
function CharacterAnimState:_onTimebomb(e, now, start)
	if e.type ~= "CharSkill" then
		return
	end
	local cue = e.cue
	if cue == "bomb.throw" then
		self:_play("TimedThrow", now, nil, start)
	elseif cue == "bomb.guard" then
		self:_play("BlastGuard", now, nil, start)
	elseif cue == "bomb.cluster" then
		self:_play("ClusterThrow", now, nil, start)
	elseif cue == "bomb.remote" then
		self:_play("RemotePlace", now, nil, start)
	elseif cue == "bomb.detonate" then
		self:_play("RemoteDetonate", now, nil, start)
	elseif cue == "bomb.jump" then
		local dash = type(e.dash) == "table" and e.dash or {}
		self:_play("BlastJump", now, { duration = positive(dash.duration, nil, 0.1, 2) }, start)
	elseif cue == "bomb.bigbang" then
		self:_play("BigBangThrow", now, nil, start)
	end
end

-- 매 프레임: 장시간 궁극기 잠금 유지/만료, 로컬 해제 후 충전 자세 해제, 몸 회전(bodySpin) 후처리. 나머지는 SwordAnimState.update 와 같다.
function CharacterAnimState:update(now)
	local lu = self._longUlt
	if lu ~= nil and not self._dead then
		if now > lu.untilT then
			-- End 이벤트가 유실됐다: 잠금·유지 모션을 스스로 푼다
			self._longUlt = nil
			self._storm = nil
			if self._action ~= nil and self._action.id == lu.holdId then
				self:_clearAction(now, 0.12)
			end
		elseif self._storm ~= nil then
			self._storm.start = now -- SwordAnimState 의 폭풍 잠금 3.8초 제한(및 활동 기반 제한)을 이 구간에서는 갱신해 둔다
			self._storm.lastTick = now
			self._storm.lastActivity = now -- 패치된 SwordAnimState 의 활동 기반 잠금 해제(2초)도 이 구간에서는 갱신
		end
	end
	local pr = self._pendingRelease
	if pr ~= nil then
		local cur = self._action
		if cur == nil or cur.serial ~= pr.serial then
			self._pendingRelease = nil -- 서버 이벤트가 먼저 와서 이미 교체/종료됨
		elseif now - pr.at >= RELEASE_GRACE then
			self._pendingRelease = nil
			self:_clearAction(now, 0.12) -- 서버가 해제를 받아들이지 않았다: 충전 자세가 남지 않게 푼다
		end
	end
	local pose, info = SwordAnimState.update(self, now)
	if pose ~= nil and info.action ~= nil and self._longUlt ~= nil then
		local def = self._data.Motions[info.action]
		if def ~= nil and def.bodySpin ~= nil then
			pose = MotionMath.copy(pose) -- _last(블렌드 기준)를 오염시키지 않도록 복사본에만 회전을 더한다
			pose.Root.ry += def.bodySpin.degPerSec * (now - self._longUlt.start)
		end
	end
	return pose, info
end

return CharacterAnimState
