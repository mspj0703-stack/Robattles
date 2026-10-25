--!nonstrict
-- SWORD R6 애니메이션 순수 로직 테스트: 레지스트리 누락, 상태 전환, 연속 입력, 충전 취소, 사망/리스폰/캐릭터 전환 정리,
-- 우선순위, 실제 서버 이벤트 연동. Roblox 의존부(SwordAnimator: Motor6D 적용, Animator 충돌, 재생 자연스러움)는 Studio 미검증.
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local H = require(script.Parent.Helpers)
local Math = Env.client("Logic/MotionMath")
local Loco = Env.client("Logic/LocomotionPose")
local AnimState = Env.client("Logic/SwordAnimState")
local Data = Env.shared("Data/SwordMotions")
local Registry = Env.shared("Data/MotionRegistry")
local RigStatus = Env.client("Logic/RigStatus")
local AnimCache = Env.client("Logic/AnimationCache")
local Core = Env.server("CombatCore")
local ProjectileService = Env.server("ProjectileService")
local Controller = Env.server("CharacterController")
local Config = Env.shared("Config")
local Characters = Env.shared("Data/Characters")

local v = H.v
local fwd = v(0, 0, 1)

local function newState(opts)
	return AnimState.new(Data, opts)
end
local function action(s)
	return s:snapshot().actionId
end
local function step(s, from, to, dt)
	local t = from
	while t < to do
		t += dt
		s:update(t)
	end
	return t
end
local function logKinds(entries, kind, id)
	local n = 0
	for _, e in entries do
		if e.kind == kind and (id == nil or e.id == id) then
			n += 1
		end
	end
	return n
end

T.describe("SWORD 애니메이션: 모션 레지스트리", function()
	T.it("검증 통과(모션·키프레임·관절·impact·hold 만료 누락 없음)", function()
		local problems = Registry.validate()
		T.expectEqual(#problems, 0, table.concat(problems, " | "))
	end)
	T.it("요구 모션 10종 그룹이 모두 존재하고 Locomotion 외에는 모션 데이터가 있다", function()
		local groups = { "Idle", "Run", "Slash1", "Slash2", "Slash3", "Parry", "TripleSlash", "Lunge", "BladeWave", "BladeStorm" }
		for _, g in groups do
			T.expect(Registry.Groups[g] ~= nil, "그룹 누락 " .. g)
			for _, id in Registry.Groups[g] do
				T.expect(Registry.Entries[id] ~= nil, "항목 누락 " .. id)
				if Registry.Entries[id].kind ~= "Locomotion" then
					T.expect(Registry.Motions[id] ~= nil, "데이터 누락 " .. id)
				end
			end
		end
	end)
	T.it("검증기가 누락·역전·알 수 없는 관절을 실제로 잡아낸다(음성 테스트)", function()
		local saved = Registry.Motions.Slash1
		Registry.Motions.Slash1 = nil
		T.expect(#Registry.validate() > 0, "모션 데이터 삭제를 못 잡음")
		Registry.Motions.Slash1 = { priority = 2, duration = 0.5, impact = 0.06, keys = {
			{ t = 0.3, pose = { Foo = { rx = 1 } } }, { t = 0.1, pose = { Foo = { rx = 1 } } },
		} }
		local p = table.concat(Registry.validate(), "|")
		T.expect(string.find(p, "알 수 없는 관절", 1, true) ~= nil and string.find(p, "시간 역전", 1, true) ~= nil)
		Registry.Motions.Slash1 = saved
		T.expectEqual(#Registry.validate(), 0)
	end)
	T.it("에셋 ID 가 비어 있으면 에셋 구동 아님(assetIdOf nil), 지정하면 반환", function()
		T.expect(Registry.assetIdOf("Slash1") == nil)
		Registry.Entries.Slash1.assetId = "rbxassetid://1"
		T.expectEqual(Registry.assetIdOf("Slash1"), "rbxassetid://1")
		Registry.Entries.Slash1.assetId = ""
	end)
end)

T.describe("SWORD 애니메이션: 포즈 수학", function()
	T.it("sampleKeys: 범위 밖 고정, 중간 보간, 이징", function()
		local keys = { { t = 0, pose = { RArm = { rx = 0 } } }, { t = 1, ease = "linear", pose = { RArm = { rx = 100 } } } }
		T.expectNear(Math.sampleKeys(keys, -1).RArm.rx, 0)
		T.expectNear(Math.sampleKeys(keys, 0.5).RArm.rx, 50)
		T.expectNear(Math.sampleKeys(keys, 9).RArm.rx, 100)
		keys[2].ease = "in"
		T.expectNear(Math.sampleKeys(keys, 0.5).RArm.rx, 25)
	end)
	T.it("lerpPose shortest: 350°→10° 은 20° 이동(반대로 340° 돌지 않는다)", function()
		local r = Math.lerpPose({ Root = { ry = 350 } }, { Root = { ry = 10 } }, 0.5, true)
		T.expectNear(math.abs(Math.wrap180(r.Root.ry - 0)), 0, 1e-6)
	end)
	T.it("layer: overlay 에 없는 관절(하체)은 base 그대로 유지", function()
		local base = Math.neutral()
		base.RLeg.rx = 30
		local out = Math.layer(base, { RArm = { rx = 90 } }, 1)
		T.expectNear(out.RLeg.rx, 30)
		T.expectNear(out.RArm.rx, 90)
		T.expectNear(Math.layer(base, { RArm = { rx = 90 } }, 0).RArm.rx, 0)
	end)
	T.it("모든 모션의 모든 시각 샘플이 유한한 숫자", function()
		for id, def in Registry.Motions do
			for i = 0, 20 do
				local pose = Math.sampleKeys(def.keys, def.duration * i / 20)
				T.expect(not Math.hasBadNumber(pose), id .. " @" .. i)
			end
		end
	end)
end)

T.describe("SWORD 애니메이션: Idle / Run 기본 이동 레이어", function()
	T.it("정지 = Idle(공격 없음), 달리면 다리가 크게 흔들리고 Root 가 앞으로 숙인다", function()
		local s = newState()
		s:setLocomotion(0, false)
		local idle = s:update(0)
		s:setLocomotion(23, false)
		local pose
		for i = 1, 30 do
			pose = s:update(i * 0.02)
		end
		T.expect(math.abs(idle.RLeg.rx) < 15)
		T.expect(math.abs(pose.RLeg.rx) > 5 or math.abs(pose.LLeg.rx) > 5)
		T.expect(pose.Root.rx < idle.Root.rx, "달리기는 앞으로 숙임")
		T.expectEqual(action(s), nil)
	end)
	T.it("공격 중 Idle/Run 이 상체 모션을 덮지 않는다(상체는 공격, 하체는 Run 유지)", function()
		local s = newState()
		s:setLocomotion(23, false)
		step(s, 0, 0.3, 0.02)
		s:onEvent({ type = "Swing", playerId = 1, step = 1, time = 0.3 }, 0.3)
		local pose = s:update(0.36) -- impact(0.06s)
		T.expect(pose.RArm.rx > 85, "공격 팔이 앞으로")
		T.expect(math.abs(pose.RLeg.rx) > 1 or math.abs(pose.LLeg.rx) > 1, "하체는 달리기 유지")
		-- 이동 상태가 바뀌어도(정지) 공격 중 상체는 그대로
		s:setLocomotion(0, false)
		T.expect(s:update(0.37).RArm.rx > 85)
	end)
	T.it("비정상 이동 속도(NaN/음수)는 0 으로 처리, 시간 역행/급점프에도 포즈는 유한", function()
		local s = newState()
		s:setLocomotion(0 / 0, false)
		T.expect(not Math.hasBadNumber((s:update(1))))
		s:setLocomotion(-5, false)
		T.expect(not Math.hasBadNumber((s:update(0.5)))) -- 시간 역행
		T.expect(not Math.hasBadNumber((s:update(500)))) -- 급점프
	end)
end)

T.describe("SWORD 애니메이션: 콤보·연속 입력", function()
	T.it("Swing 1→2→3 이 Slash1/2/3 을 재생하고 후딜 뒤 Idle 로 돌아온다", function()
		local s = newState()
		local t = 0
		for stepNo = 1, 3 do
			s:onEvent({ type = "Swing", playerId = 1, step = stepNo, time = t }, t)
			T.expectEqual(action(s), "Slash" .. stepNo)
			t = step(s, t, t + 0.55, 0.02)
		end
		step(s, t, t + 1.2, 0.02)
		T.expectEqual(action(s), nil)
	end)
	T.it("연타: 매 프레임 같은 이벤트가 쏟아져도 상태가 깨지지 않고 포즈는 유한", function()
		local s = newState()
		local t = 0
		for i = 1, 200 do
			t += 0.016
			s:onEvent({ type = "Swing", playerId = 1, step = (i % 3) + 1, time = t }, t)
			s:onEvent({ type = "SwordSkill", skill = "TripleSlash", step = (i % 3) + 1, time = t }, t)
			s:onEvent({ type = "Parry", playerId = 1, time = t }, t)
			local pose = s:update(t)
			T.expect(pose ~= nil and not Math.hasBadNumber(pose))
		end
		step(s, t, t + 2, 0.02)
		T.expectEqual(action(s), nil, "연타 후에도 만료되어 Idle 복귀")
	end)
	T.it("Triple Slash 3단계가 각자 모션으로 이어지고 마무리가 가장 크다", function()
		local s = newState()
		local t = 0
		for n = 1, 3 do
			s:onEvent({ type = "SwordSkill", skill = "TripleSlash", step = n, time = t }, t)
			T.expectEqual(action(s), "TripleSlash" .. n)
			t = step(s, t, t + 0.32, 0.02)
		end
		local d = Registry.Motions
		T.expect(d.TripleSlash3.duration > d.TripleSlash1.duration)
	end)
	T.it("잘못된 step 값(NaN/0/99/문자열)도 1~3 으로 제한", function()
		for _, bad in { 0, 99, -3, "x", 0 / 0 } do
			local s = newState()
			s:onEvent({ type = "Swing", playerId = 1, step = bad, time = 0 }, 0)
			local id = action(s)
			T.expect(id == "Slash1" or id == "Slash2" or id == "Slash3", tostring(bad) .. " → " .. tostring(id))
		end
	end)
	T.it("알 수 없는 이벤트/잘못된 입력은 무시하고 예외 없음", function()
		local s = newState()
		s:onEvent(nil, 0)
		s:onEvent({}, 0)
		s:onEvent({ type = 5 }, 0)
		s:onEvent({ type = "Nope" }, 0)
		s:onEvent({ type = "SwordSkill", skill = "Nope", phase = "X" }, 0)
		T.expectEqual(action(s), nil)
	end)
end)

T.describe("SWORD 애니메이션: 우선순위", function()
	T.it("높은 우선순위(Parry)는 낮은 모션(Slash)을 즉시 끊는다", function()
		local s = newState()
		s:onEvent({ type = "Swing", step = 1, time = 0 }, 0)
		s:update(0.02)
		s:onEvent({ type = "Parry", time = 0.02 }, 0.02)
		T.expectEqual(action(s), "ParryGuard")
	end)
	T.it("낮은 우선순위 이벤트는 commit 시간 동안 높은 모션을 끊지 못하고, 지나면 끊는다", function()
		local s = newState()
		s:onEvent({ type = "Parry", time = 0 }, 0)
		s:update(0.1)
		s:onEvent({ type = "Swing", step = 1, time = 0.1 }, 0.1)
		T.expectEqual(action(s), "ParryGuard", "commit 0.4s 안")
		s:update(0.45)
		s:onEvent({ type = "Swing", step = 1, time = 0.45 }, 0.45)
		T.expectEqual(action(s), "Slash1", "commit 이후")
	end)
	T.it("Blade Storm 중에는 priority 5 미만 모션(Slash/Parry/Wave)을 모두 거부", function()
		local s = newState()
		s:onEvent({ type = "SwordSkill", skill = "BladeStorm", phase = "Start", time = 0 }, 0)
		step(s, 0, 0.5, 0.02)
		T.expectEqual(action(s), "StormLoop")
		for _, ev in {
			{ type = "Swing", step = 1 }, { type = "Parry" }, { type = "SwordSkill", skill = "BladeWave" },
			{ type = "SwordSkill", skill = "TripleSlash", step = 1 }, { type = "SwordSkill", skill = "Lunge", phase = "Charge" },
		} do
			ev.time = 0.5
			s:onEvent(ev, 0.5)
			T.expectEqual(action(s), "StormLoop", ev.type)
		end
	end)
	T.it("Lunge 방출(commit 전체)은 Slash 로 끊기지 않는다", function()
		local s = newState()
		s:onEvent({ type = "SwordSkill", skill = "Lunge", phase = "Charge", chargeSeconds = 1, time = 0 }, 0)
		s:onEvent({ type = "SwordSkill", skill = "Lunge", phase = "Dash", charge = 1, dash = { speed = 57, duration = 0.28 }, time = 1 }, 1)
		s:update(1.05)
		s:onEvent({ type = "Swing", step = 1, time = 1.05 }, 1.05)
		T.expectEqual(action(s), "LungeRelease")
	end)
end)

T.describe("SWORD 애니메이션: Lunge 충전/방출/취소", function()
	local function charge(s, t, cs)
		s:onEvent({ type = "SwordSkill", skill = "Lunge", phase = "Charge", chargeSeconds = cs or 1, time = t }, t)
	end
	T.it("Charge → Dash → End 순서로 LungeCharge → LungeRelease → LungeRecover → Idle", function()
		local s = newState()
		charge(s, 0)
		T.expectEqual(action(s), "LungeCharge")
		step(s, 0, 0.8, 0.02)
		T.expectEqual(action(s), "LungeCharge")
		s:onEvent({ type = "SwordSkill", skill = "Lunge", phase = "Dash", charge = 0.8, dash = { speed = 57, duration = 0.28 }, time = 0.8 }, 0.8)
		T.expectEqual(action(s), "LungeRelease")
		step(s, 0.8, 1.1, 0.02)
		s:onEvent({ type = "SwordSkill", skill = "Lunge", phase = "End", time = 1.1 }, 1.1)
		T.expectEqual(action(s), "LungeRecover")
		step(s, 1.1, 1.6, 0.02)
		T.expectEqual(action(s), nil)
	end)
	T.it("충전 도중 취소(Cancel): 충전 자세를 즉시 정리하고 복귀 모션 후 Idle", function()
		local s = newState()
		charge(s, 0)
		step(s, 0, 0.4, 0.02)
		s:onEvent({ type = "SwordSkill", skill = "Lunge", phase = "Cancel", reason = "dodge", time = 0.4 }, 0.4)
		T.expectEqual(action(s), "LungeRecover")
		step(s, 0.4, 0.8, 0.02)
		T.expectEqual(action(s), nil)
	end)
	T.it("종료 이벤트가 영영 안 와도 충전 모션은 maxDuration 에서 만료된다(고착 방지)", function()
		local s = newState()
		charge(s, 0, 1.0)
		step(s, 0, 4.0, 0.05)
		T.expectEqual(action(s), nil)
	end)
	T.it("충전 시간이 길수록 포즈가 진행(뒤로 더 젖힘/더 낮춤)", function()
		local s = newState()
		charge(s, 0, 1.0)
		local early = s:update(0.1)
		local late = s:update(1.0)
		T.expect(late.Root.py < early.Root.py, "몸을 더 낮춤")
		T.expect(late.RArm.ry < early.RArm.ry, "검을 더 뒤로")
	end)
	T.it("방출 모션 길이가 서버 돌진 시간(dash.duration)에 맞춰진다", function()
		local s = newState()
		s:onEvent({ type = "SwordSkill", skill = "Lunge", phase = "Dash", dash = { duration = 0.5 }, time = 0 }, 0)
		s:update(0.02)
		T.expectEqual(action(s), "LungeRelease")
		step(s, 0.02, 0.45, 0.02)
		T.expectEqual(action(s), "LungeRelease")
		T.expectNear(s._action.duration, 0.5, 1e-6)
		step(s, 0.45, 0.8, 0.02) -- hold 최대 0.6s 에서 만료(End 이벤트가 유실돼도 고착 안 됨)
		T.expectEqual(action(s), nil)
	end)
	T.it("Charge 없이 End/Cancel 이 먼저 와도(늦게 접속 등) 오류 없이 무시", function()
		local s = newState()
		s:onEvent({ type = "SwordSkill", skill = "Lunge", phase = "End", time = 0 }, 0)
		s:onEvent({ type = "SwordSkill", skill = "Lunge", phase = "Cancel", time = 0 }, 0)
		T.expectEqual(action(s), nil)
	end)
end)

T.describe("SWORD 애니메이션: Blade Wave / Blade Storm / Parry", function()
	T.it("Blade Wave 재생 후 복귀", function()
		local s = newState()
		s:onEvent({ type = "SwordSkill", skill = "BladeWave", time = 0 }, 0)
		T.expectEqual(action(s), "BladeWave")
		step(s, 0, 0.8, 0.02)
		T.expectEqual(action(s), nil)
	end)
	T.it("Storm: Start → Loop(자동 전환) → Finisher → End → Recover → Idle", function()
		local s = newState()
		s:onEvent({ type = "SwordSkill", skill = "BladeStorm", phase = "Start", time = 0 }, 0)
		T.expectEqual(action(s), "StormStart")
		local t = step(s, 0, 0.5, 0.02)
		T.expectEqual(action(s), "StormLoop")
		for i = 1, 8 do
			s:onEvent({ type = "SwordSkill", skill = "BladeStorm", phase = "Tick", index = i, time = t }, t)
		end
		T.expectEqual(action(s), "StormLoop", "Tick 은 모션을 바꾸지 않는다")
		t = step(s, t, 2.7, 0.02)
		s:onEvent({ type = "SwordSkill", skill = "BladeStorm", phase = "Finisher", time = t }, t)
		T.expectEqual(action(s), "StormFinisher")
		t = step(s, t, 3.0, 0.02)
		s:onEvent({ type = "SwordSkill", skill = "BladeStorm", phase = "End", time = t }, t)
		T.expectEqual(action(s), "StormRecover")
		T.expect(not s:snapshot().storm)
		step(s, t, t + 0.8, 0.02)
		T.expectEqual(action(s), nil)
	end)
	T.it("Storm 회전은 Root.ry 가 시간에 따라 증가, Tick 직후 팔이 더 벌어졌다 돌아온다", function()
		local s = newState()
		s:onEvent({ type = "SwordSkill", skill = "BladeStorm", phase = "Start", time = 0 }, 0)
		step(s, 0, 1.0, 0.02)
		local a = s:update(1.02).Root.ry
		local b = s:update(1.12).Root.ry
		T.expect(b > a)
		local calm = s:update(1.3).RArm.rz
		s:onEvent({ type = "SwordSkill", skill = "BladeStorm", phase = "Tick", time = 1.3 }, 1.3)
		local pulsed = s:update(1.31).RArm.rz
		local after = s:update(1.5).RArm.rz
		T.expect(pulsed > calm + 5)
		T.expectNear(after, calm, 1.0)
	end)
	T.it("Storm 종료 이벤트가 유실돼도 최대 지속시간 뒤 모션과 잠금이 해제된다", function()
		local s = newState()
		s:onEvent({ type = "SwordSkill", skill = "BladeStorm", phase = "Start", time = 0 }, 0)
		step(s, 0, 5.0, 0.05)
		T.expectEqual(action(s), nil)
		T.expect(not s:snapshot().storm)
		s:onEvent({ type = "Swing", step = 1, time = 5 }, 5)
		T.expectEqual(action(s), "Slash1", "잠금 해제 후 공격 모션 재생")
	end)
	T.it("Parry: 가드는 0.4초 후 복귀, 성공 시 반격 모션으로 전환", function()
		local s = newState()
		s:onEvent({ type = "Parry", playerId = 1, time = 0 }, 0)
		T.expectEqual(action(s), "ParryGuard")
		step(s, 0, 0.7, 0.02)
		T.expectEqual(action(s), nil)
		s:onEvent({ type = "Parry", playerId = 1, time = 1 }, 1)
		s:update(1.1)
		s:onEvent({ type = "ParrySuccess", playerId = 1, countered = true, time = 1.1 }, 1.1)
		T.expectEqual(action(s), "ParryCounter")
		step(s, 1.1, 1.6, 0.02)
		T.expectEqual(action(s), nil)
	end)
	T.it("늦게 도착한 이벤트는 MaxCatchUp 만큼만 시간을 앞당긴다", function()
		local s = newState()
		s:onEvent({ type = "Swing", step = 1, time = 0 }, 5) -- 5초 늦게 도착
		local lateBy = s._action.start
		T.expectNear(5 - lateBy, Data.MaxCatchUp, 1e-6)
	end)
end)

T.describe("SWORD 애니메이션: 사망·리스폰·캐릭터 전환 정리", function()
	T.it("사망 시 모든 모션/폭풍 잠금 정리, 사망 중 이벤트 무시, 출력 nil", function()
		local s = newState()
		s:onEvent({ type = "SwordSkill", skill = "BladeStorm", phase = "Start", time = 0 }, 0)
		step(s, 0, 0.5, 0.02)
		s:onEvent({ type = "Died", playerId = 1, time = 0.5 }, 0.5)
		local snap = s:snapshot()
		T.expect(snap.dead and snap.actionId == nil and not snap.storm)
		s:onEvent({ type = "Swing", step = 1, time = 0.6 }, 0.6)
		T.expectEqual(action(s), nil)
		local pose, info = s:update(0.7)
		T.expect(pose == nil and info.dead)
	end)
	T.it("충전 중 사망: 충전 모션 정리, 리스폰 후 깨끗한 Idle 에서 다시 시작", function()
		local s = newState()
		s:onEvent({ type = "SwordSkill", skill = "Lunge", phase = "Charge", chargeSeconds = 1, time = 0 }, 0)
		step(s, 0, 0.3, 0.02)
		s:onEvent({ type = "Died", time = 0.3 }, 0.3)
		s:onEvent({ type = "Respawned", time = 4.3 }, 4.3)
		T.expect(s:isIdle())
		local pose = s:update(4.4)
		T.expect(pose ~= nil and not Math.hasBadNumber(pose))
		s:onEvent({ type = "Swing", step = 1, time = 4.5 }, 4.5)
		T.expectEqual(action(s), "Slash1")
	end)
	T.it("reset(캐릭터 전환): 재생 중 모션 정리 + 정지 로그 발행", function()
		local s = newState()
		s:onEvent({ type = "SwordSkill", skill = "Lunge", phase = "Charge", chargeSeconds = 1, time = 0 }, 0)
		s:drain()
		s:reset()
		T.expect(s:isIdle())
		local log = s:drain()
		T.expectEqual(logKinds(log, "stop", "LungeCharge"), 1)
		T.expectEqual(logKinds(log, "stopAll"), 1)
	end)
	T.it("play/stop 로그: 모션마다 serial 이 고유하고 교체 시 이전 모션 stop 이 나간다(에셋 트랙 누수 방지)", function()
		local s = newState()
		s:onEvent({ type = "Swing", step = 1, time = 0 }, 0)
		s:onEvent({ type = "Parry", time = 0.01 }, 0.01) -- Slash1 을 끊음
		s:update(0.02)
		local log = s:drain()
		T.expectEqual(logKinds(log, "play"), 2)
		T.expectEqual(logKinds(log, "stop", "Slash1"), 1, "교체되는 모션은 stop 이 나간다")
		step(s, 0.02, 1.0, 0.02)
		local log2 = s:drain()
		T.expectEqual(logKinds(log2, "stop", "ParryGuard"), 1)
	end)
	T.it("로그는 소비자가 없어도 무한히 쌓이지 않는다", function()
		local s = newState()
		for i = 1, 500 do
			s:onEvent({ type = "Swing", step = 1, time = i }, i)
		end
		T.expect(#s:drain() <= 64)
	end)
end)

T.describe("SWORD 애니메이션: 에셋 모션 교체 구조", function()
	T.it("assetDriven 모션 구동 중에는 절차 포즈 출력 nil(Animator 출력 보존), 끝나면 절차 포즈로 복귀", function()
		local s = newState({ assetDriven = function(id) return id == "Slash1" end })
		s:onEvent({ type = "Swing", step = 1, time = 0 }, 0)
		local pose, info = s:update(0.1)
		T.expect(pose == nil and info.assetDriven and info.action == "Slash1")
		step(s, 0.1, 0.7, 0.02)
		local after = s:update(0.8)
		T.expect(after ~= nil)
	end)
	T.it("에셋 구동이어도 우선순위·만료·정리 규칙은 그대로(상태기계가 관리)", function()
		local s = newState({ assetDriven = function() return true end })
		s:onEvent({ type = "SwordSkill", skill = "Lunge", phase = "Charge", chargeSeconds = 1, time = 0 }, 0)
		step(s, 0, 4, 0.05)
		T.expectEqual(action(s), nil)
	end)
end)

-- ── 실제 서버 이벤트로 구동: 서버가 내보내는 필드 이름·순서가 애니메이션 상태기계와 맞는지 확인 ──
T.describe("SWORD 애니메이션: 실제 서버 이벤트 연동", function()
	local function setup(ids)
		local core = Core.new()
		local pos, face = {}, {}
		local world = H.fakeWorld({})
		local function targets()
			local list = {}
			for id in ids do
				table.insert(list, { id = id, pos = pos[id], radius = Config.Combat.HitRadius, alive = core.damage:isAlive(id) })
			end
			return list
		end
		local ps = ProjectileService.new({ damage = core.damage, targets = targets, world = world })
		local c = Controller.new({ characters = H.legacyChars(Characters), core = core, projectiles = ps, targets = targets, world = world,
			getPose = function(id) return { pos = pos[id], forward = face[id], airborne = false } end })
		local events = {}
		c:onFeedback(function(e) table.insert(events, e) end)
		for id, ch in ids do
			c:addPlayer(id, ch)
			pos[id] = v(0, 0, 0)
			face[id] = fwd
		end
		return c, core, pos, events
	end
	local function feed(s, events, from, owner)
		for i = from, #events do
			if events[i].playerId == owner then
				s:onEvent(events[i], events[i].time or 0)
			end
		end
		return #events + 1
	end

	T.it("서버 콤보 3타 → Slash1/2/3 순서로 재생", function()
		local c, core, pos, events = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 3)
		local s, seen, idx, t = newState(), {}, 1, 0
		for _ = 1, 3 do
			T.expect((c:handleAttack("a", { action = "Primary", aimDirection = fwd }, t)))
			idx = feed(s, events, idx, "a")
			table.insert(seen, action(s))
			t += 0.7
			c:update(t, 0.7)
			step(s, t - 0.7, t, 0.02)
		end
		T.expectEqual(table.concat(seen, ","), "Slash1,Slash2,Slash3")
	end)
	T.it("서버 Triple Slash 3회 입력 → TripleSlash1~3", function()
		local c, core, pos, events = setup({ a = "SWORD" })
		local s, seen, idx, t = newState(), {}, 1, 0
		for _ = 1, 3 do
			T.expect((c:handleSkill("a", { slot = 1, aimDirection = fwd }, t)))
			idx = feed(s, events, idx, "a")
			table.insert(seen, action(s))
			t += 0.35
			c:update(t, 0.35)
		end
		T.expectEqual(table.concat(seen, ","), "TripleSlash1,TripleSlash2,TripleSlash3")
	end)
	T.it("서버 Lunge: 충전 시작/자동 방출/종료가 모션으로 이어지고 충전 시간이 서버 값(chargeSeconds)을 따른다", function()
		local c, core, pos, events = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 10)
		local s, idx = newState(), 1
		T.expect((c:handleSkill("a", { slot = 2, aimDirection = fwd, phase = "Press" }, 0)))
		idx = feed(s, events, idx, "a")
		T.expectEqual(action(s), "LungeCharge")
		T.expectNear(s._action.duration, Characters.SWORD.skills[2].chargeSeconds, 1e-6)
		c:update(1.0, 0.05)
		c:update(1.6, 0.05) -- 자동 방출
		idx = feed(s, events, idx, "a")
		T.expectEqual(action(s), "LungeRelease")
		c:update(3.0, 1.4)
		feed(s, events, idx, "a")
		T.expect(action(s) == "LungeRecover" or action(s) == "LungeRelease" or action(s) == nil)
	end)
	T.it("서버 Lunge 충전 중 회피 → Cancel 이벤트로 충전 모션 정리", function()
		local c, core, pos, events = setup({ a = "SWORD" })
		local s, idx = newState(), 1
		c:handleSkill("a", { slot = 2, aimDirection = fwd, phase = "Press" }, 0)
		idx = feed(s, events, idx, "a")
		T.expectEqual(action(s), "LungeCharge")
		c:handleDodge("a", { direction = fwd }, 0.2)
		feed(s, events, idx, "a")
		T.expect(action(s) ~= "LungeCharge", "충전 모션이 남아 있다: " .. tostring(action(s)))
	end)
	T.it("서버 Blade Storm: 틱 8 + 마무리 1 이벤트로 모션이 Start→Loop→Finisher→Recover 로 진행", function()
		local c, core, pos, events = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 5)
		for _ = 1, 5 do core.ultimate:addKill("a") end
		T.expect((c:handleUltimate("a", {}, 0)))
		local s, idx, t, seen = newState(), 1, 0, {}
		while t < 3.3 do
			t += 0.05
			c:update(t, 0.05)
			idx = feed(s, events, idx, "a")
			s:update(t)
			local a = action(s)
			if seen[#seen] ~= a then table.insert(seen, a) end
		end
		local joined = table.concat(seen, ",")
		T.expect(string.find(joined, "StormStart,StormLoop,StormFinisher,StormRecover", 1, true) ~= nil, joined)
	end)
	T.it("서버 Parry/ParrySuccess → ParryGuard/ParryCounter", function()
		local c, core, pos, events = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 3)
		local s, idx = newState(), 1
		T.expect((c:handleAttack("a", { action = "Secondary", aimDirection = fwd }, 0)))
		idx = feed(s, events, idx, "a")
		T.expectEqual(action(s), "ParryGuard")
	end)
	T.it("서버 사망(Died)/부활(Respawned)로 애니메이션 정리", function()
		local c, core, pos, events = setup({ a = "SWORD", b = "SWORD" })
		local s, idx = newState(), 1
		c:handleSkill("a", { slot = 2, aimDirection = fwd, phase = "Press" }, 0)
		idx = feed(s, events, idx, "a")
		T.expectEqual(action(s), "LungeCharge")
		c:handleDeath("a", 0.5)
		idx = feed(s, events, idx, "a")
		T.expect(s:snapshot().dead)
		c:respawn("a", 4.5)
		feed(s, events, idx, "a")
		T.expect(s:isIdle())
	end)
end)

T.describe("SWORD 애니메이션: 판정/Remote 불변(코드 경계)", function()
	T.it("SWORD 정의의 피해·쿨타임·타이밍 값이 애니메이션 데이터에 의해 바뀌지 않는다(스냅샷)", function()
		local S = Characters.SWORD
		T.expectEqual(S.primary.combo.damages[1], 14)
		T.expectEqual(S.primary.combo.damages[3], 18)
		T.expectEqual(S.skills[1].damages[3], 22)
		T.expectEqual(S.skills[2].minDamage, 18)
		T.expectEqual(S.skills[2].maxDamage, 32)
		T.expectEqual(S.skills[3].damage, 20)
		T.expectEqual(S.ultimate.ticks, 8)
		T.expectEqual(S.ultimate.tickDamage, 5)
		T.expectEqual(S.ultimate.finisherDamage, 25)
		T.expectNear(S.secondary.windowSeconds, 0.4)
		T.expectNear(S.secondary.cooldown, 10)
	end)
	T.it("모션 길이가 서버 후딜/쿨타임 안에서 끝난다(콤보 0.55·3타 0.8·Parry 창 0.4 유지)", function()
		local M = Registry.Motions
		T.expect(M.Slash1.duration <= 0.55 and M.Slash2.duration <= 0.55)
		T.expect(M.Slash3.duration <= 0.8)
		T.expect(M.ParryGuard.keys[3].t >= Characters.SWORD.secondary.windowSeconds - 1e-6, "가드 유지 구간이 패링 창 이상")
		T.expectNear(M.LungeRelease.duration, Characters.SWORD.skills[2].dashDuration, 1e-6)
		T.expect(M.TripleSlash1.duration >= Characters.SWORD.skills[1].stepInterval - 0.05)
	end)
end)

T.describe("SWORD 애니메이션: R6 리그 준비 판정 (RigStatus)", function()
	T.it("Humanoid 없음(CharacterId 가 먼저 복제됨) → pending", function()
		T.expectEqual(RigStatus.classify({ hasHumanoid = false }), "pending")
		T.expectEqual(RigStatus.classify(nil), "pending")
		T.expectEqual(RigStatus.classify({}), "pending")
	end)
	T.it("R6 인데 관절이 일부 없음 → pending, 모두 있으면 ready", function()
		T.expectEqual(RigStatus.classify({ hasHumanoid = true, rigType = "R6", missingJoints = 3 }), "pending")
		T.expectEqual(RigStatus.classify({ hasHumanoid = true, rigType = "R6", missingJoints = 0 }), "ready")
	end)
	T.it("R15 는 관절 유무와 관계없이 unsupported(재시도 안 함)", function()
		T.expectEqual(RigStatus.classify({ hasHumanoid = true, rigType = "R15", missingJoints = 0 }), "unsupported")
		T.expectEqual(RigStatus.classify({ hasHumanoid = true, rigType = "R15", missingJoints = 6 }), "unsupported")
		T.expectEqual(RigStatus.classify({ hasHumanoid = true, rigType = nil }), "unsupported")
	end)
	T.it("대기 제한: MAX_WAIT 이상 또는 비정상 값이면 포기", function()
		T.expect(not RigStatus.shouldGiveUp(0))
		T.expect(not RigStatus.shouldGiveUp(RigStatus.MAX_WAIT - 0.01))
		T.expect(RigStatus.shouldGiveUp(RigStatus.MAX_WAIT))
		T.expect(RigStatus.shouldGiveUp(0 / 0))
		T.expect(RigStatus.shouldGiveUp(nil))
	end)
end)

T.describe("SWORD 애니메이션: 에셋 해석 캐시 (AnimationCache)", function()
	T.it("같은 id 는 한 번만 해석한다(없음 결과 포함) — 프레임마다 인스턴스 생성 금지", function()
		local calls = 0
		local cache = AnimCache.new(function(id)
			calls += 1
			return id == "Slash1" and { id = id } or nil
		end)
		for _ = 1, 500 do
			T.expect(cache:has("Slash1"))
			T.expect(not cache:has("Slash2"))
		end
		T.expectEqual(calls, 2)
		T.expectEqual(cache.resolveCalls, 2)
		T.expect(cache:get("Slash1") == cache:get("Slash1"), "같은 인스턴스를 돌려준다")
	end)
	T.it("invalidate 후에는 다시 해석하고, 비워진 이전 값을 돌려준다(정리용)", function()
		local n = 0
		local cache = AnimCache.new(function() n += 1 return { n = n } end)
		local first = cache:get("X")
		local dropped = cache:invalidate("X")
		T.expectEqual(#dropped, 1)
		T.expect(dropped[1] == first)
		T.expect(cache:get("X") ~= first)
		T.expectEqual(#cache:invalidate(), 1)
		T.expectEqual(n, 2)
	end)
	T.it("상태기계가 매 프레임 assetDriven 을 물어도 해석은 모션당 1회", function()
		local cache = AnimCache.new(function(id) return id == "Slash1" and {} or nil end)
		local s = newState({ assetDriven = function(id) return cache:has(id) end })
		s:onEvent({ type = "Swing", step = 1, time = 0 }, 0)
		step(s, 0, 1.0, 0.016)
		s:onEvent({ type = "Swing", step = 2, time = 1 }, 1)
		step(s, 1, 2.0, 0.016)
		T.expect(cache.resolveCalls <= 2, "resolveCalls=" .. cache.resolveCalls)
	end)
	T.it("에셋 구동 → 절차 구동 전환: 에셋 모션 종료 후 포즈가 다시 나온다(Transform 원복 후 재작성)", function()
		local s = newState({ assetDriven = function(id) return id == "Slash1" end })
		s:onEvent({ type = "Swing", step = 1, time = 0 }, 0)
		T.expect(s:update(0.1) == nil, "에셋 구동 중 nil")
		local sawPose = false
		for i = 1, 60 do
			local pose = s:update(0.1 + i * 0.02)
			if pose ~= nil then sawPose = true break end
		end
		T.expect(sawPose, "종료 후 절차 포즈 복귀")
	end)
end)
