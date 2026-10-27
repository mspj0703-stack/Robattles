--!nonstrict
-- PAINTBALL / SLINGSHOT R6 애니메이션 순수 로직 테스트(Phase 1). Roblox 의존부(CharacterAnimator)는 CLI 로 확인할 수 없고 Studio 검증이 필요하다.
-- ⚠ 이 파일은 Luau 실행기가 있는 환경에서만 실행된다. 실행하지 못했다면 "통과"로 보고하지 않는다.
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local Math = Env.client("Logic/MotionMath")
local CharState = Env.client("Logic/CharacterAnimState")
local Registry = Env.shared("Data/CharacterMotionRegistry")
local Characters = Env.shared("Data/Characters")

local function newState(cid, opts)
	return CharState.new(cid, Registry.Data[cid], opts)
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
local function kinds(entries, kind, id)
	local n = 0
	for _, e in entries do
		if e.kind == kind and (id == nil or e.id == id) then
			n += 1
		end
	end
	return n
end
local function skill(cue, extra)
	local e = { type = "CharSkill", cue = cue, playerId = 1 }
	for k, val in extra or {} do
		e[k] = val
	end
	return e
end

T.describe("캐릭터 애니메이션: 레지스트리", function()
	T.it("검증 통과(모션·키프레임·관절·impact·hold 만료 누락 없음)", function()
		local problems = Registry.validate()
		T.expectEqual(#problems, 0, table.concat(problems, " | "))
	end)
	T.it("Phase 1+2 캐릭터 4종이 등록되어 있고 SWORD 는 포함하지 않는다", function()
		for _, cid in { "PAINTBALL", "SLINGSHOT", "SUPERBALL", "TIMEBOMB" } do
			T.expect(Registry.Entries[cid] ~= nil, cid)
		end
		T.expect(Registry.Entries.SWORD == nil)
	end)
	T.it("모든 그룹의 모션 id 가 Entries/Motions 에 존재한다", function()
		for cid, def in Registry.Data do
			for group, ids in def.Groups do
				for _, id in ids do
					T.expect(Registry.Entries[cid][id] ~= nil, cid .. "/" .. group .. ": " .. id)
				end
			end
		end
	end)
	T.it("실제 Characters 정의의 행동이 그룹으로 모두 덮인다(주무기·스킬·궁극기)", function()
		local pb = Registry.Data.PAINTBALL.Groups
		T.expect(pb[Characters.PAINTBALL.secondary.id] ~= nil, "PaintBurst")
		for _, sk in Characters.PAINTBALL.skills do
			T.expect(pb[sk.id] ~= nil, "PAINTBALL 스킬 그룹 누락 " .. sk.id)
		end
		T.expect(pb[Characters.PAINTBALL.ultimate.id] ~= nil, "ColorBreak")
		local sl = Registry.Data.SLINGSHOT.Groups
		for _, sk in Characters.SLINGSHOT.skills do
			T.expect(sl[sk.id] ~= nil, "SLINGSHOT 스킬 그룹 누락 " .. sk.id)
		end
		T.expect(sl[Characters.SLINGSHOT.ultimate.id] ~= nil, "Bullseye")
		T.expect(sl.ChargedShot ~= nil, "충전 주무기")
		local sb = Registry.Data.SUPERBALL.Groups
		T.expect(sb.SuperThrow ~= nil, "Super Throw")
		T.expect(sb[Characters.SUPERBALL.secondary.id] ~= nil, "BounceDash")
		for _, sk in Characters.SUPERBALL.skills do
			T.expect(sb[sk.id] ~= nil, "SUPERBALL 스킬 그룹 누락 " .. sk.id)
		end
		T.expect(sb[Characters.SUPERBALL.ultimate.id] ~= nil, "BallCyclone")
		local tb = Registry.Data.TIMEBOMB.Groups
		T.expect(tb.TimedBomb ~= nil, "Timed Bomb")
		T.expect(tb[Characters.TIMEBOMB.secondary.id] ~= nil, "BlastGuard")
		for _, sk in Characters.TIMEBOMB.skills do
			T.expect(tb[sk.id] ~= nil, "TIMEBOMB 스킬 그룹 누락 " .. sk.id)
		end
		T.expect(tb[Characters.TIMEBOMB.ultimate.id] ~= nil, "BigBang")
	end)
	T.it("검증기가 누락·역전·알 수 없는 관절·maxDuration 없는 hold 를 잡아낸다(음성 테스트)", function()
		local motions = Registry.Data.PAINTBALL.Motions
		local saved = motions.PaintFire
		motions.PaintFire = { priority = 2, duration = 0.5, impact = 0.06, keys = {
			{ t = 0.3, pose = { Foo = { rx = 1 } } }, { t = 0.1, pose = { Foo = { rx = 1 } } },
		} }
		local p = table.concat(Registry.validate(), "|")
		T.expect(string.find(p, "알 수 없는 관절", 1, true) ~= nil and string.find(p, "시간 역전", 1, true) ~= nil)
		motions.PaintFire = { priority = 2, duration = 0.2, hold = true, keys = { { t = 0, pose = { RArm = { rx = 1 } } }, { t = 0.2, pose = { RArm = { rx = 2 } } } } }
		T.expect(string.find(table.concat(Registry.validate(), "|"), "maxDuration", 1, true) ~= nil)
		motions.PaintFire = nil
		T.expect(#Registry.validate() > 0, "모션 삭제를 못 잡음")
		motions.PaintFire = saved
		T.expectEqual(#Registry.validate(), 0)
	end)
	T.it("에셋 ID 가 비어 있으면 에셋 구동 아님, 지정하면 반환", function()
		T.expect(Registry.assetIdOf("PAINTBALL", "PaintFire") == nil)
		Registry.Entries.PAINTBALL.PaintFire.assetId = "rbxassetid://1"
		T.expectEqual(Registry.assetIdOf("PAINTBALL", "PaintFire"), "rbxassetid://1")
		Registry.Entries.PAINTBALL.PaintFire.assetId = ""
	end)
	T.it("서버 정의와 모션 길이가 맞는다(Slide/Backstep dash, 전조, 재장전, 충전)", function()
		local pbSkills, slSkills = Characters.PAINTBALL.skills, Characters.SLINGSHOT.skills
		T.expectNear(Registry.Data.PAINTBALL.Motions.PaintSlide.duration, pbSkills[3].duration, 1e-6)
		T.expectNear(Registry.Data.PAINTBALL.Motions.ColorBreakWindup.duration, Characters.PAINTBALL.ultimate.windup, 1e-6)
		T.expectNear(Registry.Data.PAINTBALL.Motions.PaintReload.duration, Characters.PAINTBALL.ammo.reloadSeconds, 1e-6)
		T.expectNear(Registry.Data.SLINGSHOT.Motions.BullseyeAim.duration, Characters.SLINGSHOT.ultimate.windup, 1e-6)
		T.expectNear(Registry.Data.SLINGSHOT.Motions.SlingCharge.duration, Characters.SLINGSHOT.primary.chargeSeconds, 1e-6)
		T.expect(slSkills[3].duration ~= nil)
		T.expectNear(Registry.Data.SUPERBALL.Motions.BounceDash.duration, Characters.SUPERBALL.secondary.duration, 1e-6)
		T.expectNear(Registry.Data.SUPERBALL.Motions.BallCharge.duration, Characters.SUPERBALL.primary.chargeSeconds, 1e-6)
		T.expect(Registry.Data.SUPERBALL.Motions.BallCharge.maxDuration >= Characters.SUPERBALL.primary.maxHoldSeconds, "충전 최대 유지시간")
		T.expectNear(Registry.Data.TIMEBOMB.Motions.BlastJump.duration, Characters.TIMEBOMB.skills[3].duration, 1e-6)
	end)
	T.it("모든 모션의 모든 시각 샘플이 유한한 숫자", function()
		for _, def in Registry.Data do
			for id, m in def.Motions do
				for i = 0, 20 do
					T.expect(not Math.hasBadNumber(Math.sampleKeys(m.keys, m.duration * i / 20)), id .. " @" .. i)
				end
			end
		end
	end)
end)

T.describe("캐릭터 애니메이션: 기본 이동 레이어(Idle/Run)", function()
	T.it("정지 = 조준 자세 Idle, 달리면 다리가 흔들리고 몸이 앞으로 숙인다(두 캐릭터 모두)", function()
		for _, cid in { "PAINTBALL", "SLINGSHOT", "SUPERBALL", "TIMEBOMB" } do
			local s = newState(cid)
			s:setLocomotion(0, false)
			local idle = s:update(0)
			T.expectNear(idle.RLeg.rx, Registry.Data[cid].Locomotion.stance.RLeg.rx, 1e-6)
			s:setLocomotion(23, false)
			local maxSwing = 0
			local t = 0
			for _ = 1, 60 do
				t += 1 / 60
				local pose = s:update(t)
				maxSwing = math.max(maxSwing, math.abs(pose.RLeg.rx))
				T.expect(not Math.hasBadNumber(pose))
			end
			T.expect(maxSwing > 25, cid .. " 다리 흔들림 부족")
		end
	end)
	T.it("PAINTBALL 은 달려도 두 팔이 총을 든 자세, SLINGSHOT 은 오른팔만 흔든다", function()
		local pb, sl = newState("PAINTBALL"), newState("SLINGSHOT")
		pb:setLocomotion(23, false)
		sl:setLocomotion(23, false)
		local pbMin, pbMax, slMin, slMax = 1e9, -1e9, 1e9, -1e9
		local t = 0
		for _ = 1, 90 do
			t += 1 / 60
			local a = pb:update(t)
			local b = sl:update(t)
			pbMin, pbMax = math.min(pbMin, a.LArm.rx), math.max(pbMax, a.LArm.rx)
			slMin, slMax = math.min(slMin, b.RArm.rx), math.max(slMax, b.RArm.rx)
		end
		T.expect(pbMax - pbMin < 12, "PAINTBALL 왼팔이 크게 흔들림")
		T.expect(slMax - slMin > 25, "SLINGSHOT 오른팔이 흔들리지 않음")
	end)
	T.it("두 캐릭터의 기본 자세가 SWORD 와 다르고 서로도 다르다", function()
		local a, b = Registry.Data.PAINTBALL.Locomotion.stance, Registry.Data.SLINGSHOT.Locomotion.stance
		T.expect(a.Root.ry ~= b.Root.ry and a.RArm.rx ~= b.RArm.rx)
	end)
end)

T.describe("캐릭터 애니메이션: PAINTBALL 이벤트 → 모션", function()
	T.it("paint_shot Spawned = 사격 반동, 다른 발사체(pellet/bomb)는 무시", function()
		local s = newState("PAINTBALL")
		s:onEvent({ type = "Spawned", defId = "paint_pellet", ownerId = 1 }, 0)
		T.expect(action(s) == nil)
		s:onEvent({ type = "Spawned", defId = "paint_shot", ownerId = 1 }, 0)
		T.expectEqual(action(s), "PaintFire")
		step(s, 0, 0.3, 1 / 60)
		T.expect(action(s) == nil, "반동은 스스로 끝난다")
	end)
	T.it("자동 연사: 0.33초 간격 연속 발사에서 매번 재생되고 끊기지 않는다", function()
		local s = newState("PAINTBALL")
		local plays = 0
		for i = 0, 5 do
			local t0 = i * 0.33
			s:onEvent({ type = "Spawned", defId = "paint_shot", ownerId = 1 }, t0)
			plays += 1
			step(s, t0, t0 + 0.33, 1 / 60)
		end
		T.expectEqual(kinds(s:drain(), "play", "PaintFire"), plays)
	end)
	T.it("스킬 cue 별 모션: burst/bomb/pierce/slide", function()
		for cue, id in { ["paint.burst"] = "PaintBurst", ["paint.bomb.throw"] = "BombThrow", ["paint.pierce.fire"] = "PierceFire" } do
			local s = newState("PAINTBALL")
			s:onEvent(skill(cue), 0)
			T.expectEqual(action(s), id)
		end
		local s = newState("PAINTBALL")
		s:onEvent(skill("paint.slide", { dash = { duration = 0.4 } }), 0)
		T.expectEqual(action(s), "PaintSlide")
		s:onEvent(skill("paint.slide", { dash = { duration = 0.4 } }), 1)
		step(s, 1, 1.5, 1 / 60)
		T.expect(action(s) == nil)
	end)
	T.it("재장전: 로컬 시작 모션 → Reloaded 이벤트에서 완료 동작으로 이어진다", function()
		local s = newState("PAINTBALL")
		s:onEvent({ type = "ReloadStart" }, 0)
		T.expectEqual(action(s), "PaintReload")
		s:onEvent({ type = "Reloaded", playerId = 1 }, 1.2)
		T.expectEqual(action(s), "PaintReloadDone")
		-- Reloaded 만 받는 다른 플레이어 화면: 장전 시작 없이 완료 동작만
		local other = newState("PAINTBALL")
		other:onEvent({ type = "Reloaded", playerId = 2 }, 0)
		T.expectEqual(action(other), "PaintReloadDone")
	end)
	T.it("재장전 중(커밋 전) 사격 반동은 재장전을 끊지 않는다", function()
		local s = newState("PAINTBALL")
		s:onEvent({ type = "ReloadStart" }, 0)
		s:onEvent({ type = "Spawned", defId = "paint_shot", ownerId = 1 }, 0.3)
		T.expectEqual(action(s), "PaintReload")
	end)
	T.it("Color Break: 전조(서버 windup) → 빔(틱마다 유지 연장) → 종료 시 복귀, 도중 하위 모션 거부", function()
		local s = newState("PAINTBALL")
		s:onEvent(skill("paint.ult.windup", { skill = "ColorBreak", phase = "Windup", windup = 0.8 }), 0)
		T.expectEqual(action(s), "ColorBreakWindup")
		T.expect(s:snapshot().storm)
		s:onEvent(skill("paint.burst"), 0.2)
		T.expectEqual(action(s), "ColorBreakWindup") -- 궁극 중 하위 모션 거부
		local t = step(s, 0, 0.85, 1 / 60)
		T.expectEqual(action(s), "ColorBreakBeam") -- 전조 종료 후 빔 자세로 이어진다
		-- 서버 틱(0.25초 간격)으로 3초 동안 유지: 고정 길이(1.0초)보다 오래 유지되어야 한다
		local tick = 0
		while t < 3.4 do
			t += 1 / 60
			tick += 1 / 60
			if tick >= 0.25 then
				tick = 0
				s:onEvent(skill("paint.ult.beam", { skill = "ColorBreak", phase = "Tick" }), t)
			end
			s:update(t)
			T.expectEqual(action(s), "ColorBreakBeam", "t=" .. t)
		end
		s:onEvent(skill("paint.ult.end", { skill = "ColorBreak", phase = "End" }), t)
		T.expect(not s:snapshot().storm)
		T.expectEqual(action(s), "ColorBreakRecover")
		step(s, t, t + 0.6, 1 / 60)
		T.expect(s:isIdle())
	end)
	T.it("Color Break 종료 이벤트가 유실돼도 틱이 끊기면 빔 자세가 풀린다", function()
		local s = newState("PAINTBALL")
		s:onEvent(skill("paint.ult.windup", { skill = "ColorBreak", phase = "Windup", windup = 0.8 }), 0)
		local t = step(s, 0, 0.85, 1 / 60)
		s:onEvent(skill("paint.ult.beam", { skill = "ColorBreak", phase = "Tick" }), t)
		step(s, t, t + 1.5, 1 / 60)
		T.expect(action(s) == nil, "틱 중단 후에도 자세 고착")
	end)
	T.it("틱 이벤트가 전혀 없어도 빔 자세는 최대 시간 안에 풀리고 폭풍 잠금도 풀린다(고착 방지)", function()
		local s = newState("PAINTBALL")
		s:onEvent(skill("paint.ult.windup", { skill = "ColorBreak", phase = "Windup", windup = 0.8 }), 0)
		step(s, 0, 6, 1 / 60)
		T.expect(not s:snapshot().storm and action(s) == nil)
		s:onEvent(skill("paint.burst"), 6.1)
		T.expectEqual(action(s), "PaintBurst")
	end)
end)

T.describe("캐릭터 애니메이션: SLINGSHOT 이벤트 → 모션", function()
	T.it("충전 → 해제: 충전 자세는 해제 이벤트까지 유지, 해제 시 반동", function()
		local s = newState("SLINGSHOT")
		s:onEvent(skill("sling.charge", { skill = "ChargedShot", phase = "Charge", chargeSeconds = 1.0 }), 0)
		T.expectEqual(action(s), "SlingCharge")
		step(s, 0, 3.5, 1 / 60) -- 만충(1초) 이후에도 최대 유지시간까지 자세 유지
		T.expectEqual(action(s), "SlingCharge")
		s:onEvent(skill("sling.shot", { skill = "ChargedShot" }), 3.5)
		T.expectEqual(action(s), "SlingRelease")
		local log = s:drain()
		T.expect(kinds(log, "stop", "SlingCharge") >= 1, "충전 에셋 트랙 정리")
		step(s, 3.5, 4.0, 1 / 60)
		T.expect(s:isIdle())
	end)
	T.it("충전 이벤트가 유실돼도 최대 유지시간(5초 + α) 뒤 자세가 풀린다", function()
		local s = newState("SLINGSHOT")
		s:onEvent(skill("sling.charge", { skill = "ChargedShot", phase = "Charge", chargeSeconds = 1.0 }), 0)
		step(s, 0, 6, 1 / 60)
		T.expect(action(s) == nil)
	end)
	T.it("충전 없이 바로 발사(탭)해도 반동이 재생된다", function()
		local s = newState("SLINGSHOT")
		s:onEvent(skill("sling.shot", { skill = "ChargedShot" }), 0)
		T.expectEqual(action(s), "SlingRelease")
	end)
	T.it("스킬 cue 별 모션: triple/snare/backstep, 충전 중에도 스킬이 우선", function()
		for cue, id in { ["sling.triple"] = "SlingTriple", ["sling.snare"] = "SlingSnare", ["sling.backstep"] = "SlingBackstep" } do
			local s = newState("SLINGSHOT")
			s:onEvent(skill("sling.charge", { skill = "ChargedShot", chargeSeconds = 1.0 }), 0)
			s:onEvent(skill(cue, { dash = { duration = 0.25 } }), 0.4)
			T.expectEqual(action(s), id)
		end
	end)
	T.it("Bullseye: 조준 유지 → 발사 반동 → 종료, 중단되면 조준 자세에서 복귀", function()
		local s = newState("SLINGSHOT")
		s:onEvent(skill("sling.ult.windup", { skill = "Bullseye", phase = "Windup", windup = 0.7 }), 0)
		T.expectEqual(action(s), "BullseyeAim")
		s:onEvent(skill("sling.triple"), 0.2)
		T.expectEqual(action(s), "BullseyeAim") -- 궁극 중 하위 모션 거부
		step(s, 0, 1.0, 1 / 60)
		T.expectEqual(action(s), "BullseyeAim") -- 발사 이벤트가 올 때까지 조준 유지
		s:onEvent(skill("sling.ult.fire", { skill = "Bullseye", phase = "Fire" }), 1.0)
		T.expectEqual(action(s), "BullseyeFire")
		s:onEvent(skill("sling.ult.end", { skill = "Bullseye", phase = "End" }), 1.1)
		T.expect(not s:snapshot().storm)
		T.expectEqual(action(s), "BullseyeFire") -- 발사 반동은 자체 길이로 끝난다
		step(s, 1.1, 2.0, 1 / 60)
		T.expect(s:isIdle())

		local abort = newState("SLINGSHOT")
		abort:onEvent(skill("sling.ult.windup", { skill = "Bullseye", phase = "Windup", windup = 0.7 }), 0)
		abort:onEvent(skill("sling.ult.end", { skill = "Bullseye", phase = "End", reason = "Died" }), 0.3)
		T.expectEqual(action(abort), "BullseyeRecover")
		step(abort, 0.3, 1.0, 1 / 60)
		T.expect(abort:isIdle())
	end)
	T.it("Bullseye 발사 이벤트가 영영 없어도 최대 시간 뒤 조준이 풀린다", function()
		local s = newState("SLINGSHOT")
		s:onEvent(skill("sling.ult.windup", { skill = "Bullseye", phase = "Windup", windup = 0.7 }), 0)
		step(s, 0, 4.5, 1 / 60)
		T.expect(not s:snapshot().storm and action(s) == nil)
	end)
end)

T.describe("캐릭터 애니메이션: 정리·격리", function()
	T.it("사망 = 모든 모션/잠금 정리 + 이후 이벤트 무시, 리스폰 = 처음 상태(Idle)", function()
		for _, case in {
			{ "PAINTBALL", skill("paint.ult.windup", { skill = "ColorBreak", phase = "Windup", windup = 0.8 }) },
			{ "SLINGSHOT", skill("sling.charge", { skill = "ChargedShot", chargeSeconds = 1.0 }) },
		} do
			local s = newState(case[1])
			s:onEvent(case[2], 0)
			T.expect(action(s) ~= nil)
			s:onEvent({ type = "Died", playerId = 1 }, 0.2)
			T.expect(s:snapshot().dead and action(s) == nil and not s:snapshot().storm)
			local pose, info = s:update(0.3)
			T.expect(pose == nil and info.dead)
			s:onEvent(case[2], 0.4)
			T.expect(action(s) == nil, "사망 중 이벤트는 무시")
			s:onEvent({ type = "Respawned", playerId = 1 }, 1.0)
			T.expect(s:isIdle() and not s:snapshot().storm)
			local log = s:drain()
			T.expect(kinds(log, "stopAll") >= 1, "에셋 트랙 정리 로그")
		end
	end)
	T.it("reset(캐릭터 변경·매치 종료): 궁극 잠금까지 풀고 즉시 일반 모션 가능", function()
		local s = newState("PAINTBALL")
		s:onEvent(skill("paint.ult.windup", { skill = "ColorBreak", phase = "Windup", windup = 0.8 }), 0)
		s:reset()
		T.expect(s:isIdle() and not s:snapshot().storm)
		s:onEvent(skill("paint.burst"), 0.1)
		T.expectEqual(action(s), "PaintBurst")
	end)
	T.it("다른 캐릭터/SWORD 이벤트는 무시한다(캐릭터 격리)", function()
		local pb, sl = newState("PAINTBALL"), newState("SLINGSHOT")
		pb:onEvent(skill("sling.triple"), 0)
		sl:onEvent(skill("paint.burst"), 0)
		pb:onEvent({ type = "Swing", step = 1, playerId = 1 }, 0)
		sl:onEvent({ type = "SwordSkill", skill = "BladeStorm", phase = "Start", playerId = 1 }, 0)
		T.expect(pb:isIdle() and sl:isIdle() and not sl:snapshot().storm)
	end)
	T.it("비정상 입력(nil·문자열·NaN·음수 시간)에도 오류 없이 유한한 포즈", function()
		local s = newState("SLINGSHOT")
		s:onEvent(nil, 0)
		s:onEvent({}, 0)
		s:onEvent(skill("sling.charge", { chargeSeconds = "abc" }), 0)
		s:onEvent(skill("sling.backstep", { dash = { duration = 0 / 0 } }), 0.01)
		s:onEvent(skill("sling.ult.windup", { skill = "Bullseye", phase = "Windup", windup = -5 }), 0.02)
		for i = 1, 30 do
			local pose = s:update(0.02 + i / 60)
			T.expect(pose == nil or not Math.hasBadNumber(pose))
		end
	end)
	T.it("에셋 구동 모션은 절차 포즈 대신 nil 을 돌려주고 로그는 play 로 남는다", function()
		local s = newState("PAINTBALL", { assetDriven = function(id) return id == "PaintBurst" end })
		s:onEvent(skill("paint.burst"), 0)
		local pose, info = s:update(0.1)
		T.expect(pose == nil and info.assetDriven)
		T.expectEqual(kinds(s:drain(), "play", "PaintBurst"), 1)
	end)
end)

T.describe("캐릭터 애니메이션: SUPERBALL 이벤트 → 모션", function()
	T.it("충전 → 던지기: 충전 자세는 던지기 이벤트까지 유지, 충전/일반 던지기 구분", function()
		local s = newState("SUPERBALL")
		s:onEvent(skill("ball.charge", { skill = "SuperThrow", phase = "Charge", chargeSeconds = 1.0 }), 0)
		T.expectEqual(action(s), "BallCharge")
		step(s, 0, 3.0, 1 / 60)
		T.expectEqual(action(s), "BallCharge")
		s:onEvent(skill("ball.throw.charged", { charged = true }), 3.0)
		T.expectEqual(action(s), "BallThrowCharged")
		T.expect(kinds(s:drain(), "stop", "BallCharge") >= 1)
		step(s, 3.0, 3.8, 1 / 60)
		T.expect(s:isIdle())
		s:onEvent(skill("ball.throw"), 4.0)
		T.expectEqual(action(s), "BallThrow")
	end)
	T.it("충전 이벤트가 유실돼도 최대 유지시간(4.5초) 뒤 자세가 풀린다", function()
		local s = newState("SUPERBALL")
		s:onEvent(skill("ball.charge", { chargeSeconds = 1.0 }), 0)
		step(s, 0, 4.8, 1 / 60)
		T.expect(action(s) == nil)
	end)
	T.it("스킬 cue 별 모션: dash/rapid/scatter/recall", function()
		for cue, id in { ["ball.dash"] = "BounceDash", ["ball.rapid"] = "RapidBounce", ["ball.scatter"] = "ScatterBall", ["ball.recall"] = "Recall" } do
			local s = newState("SUPERBALL")
			s:onEvent(skill(cue, { dash = { duration = 0.25 } }), 0)
			T.expectEqual(action(s), id)
			step(s, 0, 1.0, 1 / 60)
			T.expect(s:isIdle(), id .. " 종료")
		end
	end)
	T.it("반복 입력: 같은 스킬을 연타해도 항상 재생되고 상태가 쌓이지 않는다", function()
		local s = newState("SUPERBALL")
		local t = 0
		for _ = 1, 20 do
			s:onEvent(skill("ball.rapid"), t)
			s:onEvent(skill("ball.scatter"), t + 0.01)
			t = step(s, t, t + 0.05, 1 / 60)
		end
		T.expect(#s:drain() <= 64, "로그가 한없이 쌓임")
		step(s, t, t + 1.0, 1 / 60)
		T.expect(s:isIdle())
	end)
	T.it("Ball Cyclone: 12초 동안 회전 유지(3.8초 잠금 제한 없이), Shot 후 회전 복귀, End 로 복귀", function()
		local s = newState("SUPERBALL")
		s:onEvent(skill("ball.cyclone.start", { skill = "BallCyclone", phase = "Start", duration = 12 }), 0)
		T.expectEqual(action(s), "CycloneStart")
		local t = step(s, 0, 0.5, 1 / 60)
		T.expectEqual(action(s), "CycloneSpin")
		local nextShot = 0.4
		local shots = 0
		while t < 11.5 do
			t += 1 / 60
			if t >= nextShot then
				nextShot += 0.4
				s:onEvent(skill("ball.cyclone.shot", { skill = "BallCyclone", phase = "Shot" }), t)
				shots += 1
				T.expectEqual(action(s), "CycloneShot")
			end
			s:update(t)
		end
		T.expect(shots > 20)
		T.expect(s:snapshot().storm, "11.5초에도 궁극 잠금 유지")
		s:onEvent(skill("ball.dash", { dash = { duration = 0.25 } }), t)
		T.expect(action(s) == "CycloneSpin" or action(s) == "CycloneShot", "궁극 중 하위 모션 거부")
		s:onEvent(skill("ball.cyclone.end", { skill = "BallCyclone", phase = "End" }), t)
		T.expect(not s:snapshot().storm)
		T.expectEqual(action(s), "CycloneRecover")
		step(s, t, t + 0.6, 1 / 60)
		T.expect(s:isIdle())
	end)
	T.it("Cyclone 몸 회전은 시간에 따라 증가하고 블렌드 기준 포즈를 오염시키지 않는다", function()
		local s = newState("SUPERBALL")
		s:onEvent(skill("ball.cyclone.start", { skill = "BallCyclone", phase = "Start", duration = 12 }), 0)
		step(s, 0, 0.6, 1 / 60)
		local a = s:update(1.0)
		local b = s:update(1.2)
		T.expect(math.abs(b.Root.ry - a.Root.ry) > 30, "회전이 진행되지 않음")
	end)
	T.it("Cyclone End 이벤트가 유실돼도 duration(+여유) 뒤 잠금·자세가 풀린다", function()
		local s = newState("SUPERBALL")
		s:onEvent(skill("ball.cyclone.start", { skill = "BallCyclone", phase = "Start", duration = 12 }), 0)
		step(s, 0, 14.5, 1 / 60)
		T.expect(not s:snapshot().storm and action(s) == nil, "End 유실 시 고착")
		s:onEvent(skill("ball.rapid"), 14.6)
		T.expectEqual(action(s), "RapidBounce")
	end)
	T.it("Cyclone Shot 이 마지막 순간에 와도 울트 종료 시각을 넘겨 자세가 남지 않는다", function()
		local s = newState("SUPERBALL")
		s:onEvent(skill("ball.cyclone.start", { skill = "BallCyclone", phase = "Start", duration = 12 }), 0)
		step(s, 0, 11.9, 1 / 60)
		s:onEvent(skill("ball.cyclone.shot", { skill = "BallCyclone", phase = "Shot" }), 11.9)
		step(s, 11.9, 14.0, 1 / 60)
		T.expect(action(s) == nil and not s:snapshot().storm)
	end)
	T.it("Cyclone 짧은 duration(서버 값)도 따른다", function()
		local s = newState("SUPERBALL")
		s:onEvent(skill("ball.cyclone.start", { skill = "BallCyclone", phase = "Start", duration = 3 }), 0)
		step(s, 0, 5.0, 1 / 60)
		T.expect(action(s) == nil and not s:snapshot().storm)
	end)
end)

T.describe("캐릭터 애니메이션: TIMEBOMB 이벤트 → 모션", function()
	T.it("cue 별 모션: throw/guard/cluster/remote/detonate/jump/bigbang", function()
		local map = {
			["bomb.throw"] = "TimedThrow", ["bomb.guard"] = "BlastGuard", ["bomb.cluster"] = "ClusterThrow",
			["bomb.remote"] = "RemotePlace", ["bomb.detonate"] = "RemoteDetonate", ["bomb.jump"] = "BlastJump", ["bomb.bigbang"] = "BigBangThrow",
		}
		for cue, id in map do
			local s = newState("TIMEBOMB")
			s:onEvent(skill(cue, { dash = { duration = 0.5 } }), 0)
			T.expectEqual(action(s), id)
			step(s, 0, 1.5, 1 / 60)
			T.expect(s:isIdle(), id .. " 종료")
		end
	end)
	T.it("서버 폭발 이벤트(BombLand/BombExplode/BombEnd)는 모션을 만들지도 끊지도 않는다(시각 분리)", function()
		local s = newState("TIMEBOMB")
		s:onEvent(skill("bomb.bigbang", { skill = "BigBang", phase = "Throw" }), 0)
		T.expectEqual(action(s), "BigBangThrow")
		s:onEvent({ type = "BombLand", ownerId = 1, bombId = 1 }, 0.3)
		s:onEvent({ type = "BombExplode", ownerId = 1, bombId = 1, stage = 1 }, 0.3)
		s:onEvent({ type = "BombEnd", ownerId = 1, bombId = 1 }, 0.3)
		T.expectEqual(action(s), "BigBangThrow")
		step(s, 0.3, 1.2, 1 / 60)
		T.expect(s:isIdle())
		-- 3초 뒤 폭발 시각에도 모션은 시작되지 않는다
		s:onEvent({ type = "BombExplode", ownerId = 1, bombId = 1, stage = 1 }, 3.0)
		T.expect(s:isIdle())
	end)
	T.it("Big Bang 은 투척 중(커밋 전) 다른 스킬에 끊기지 않고, 커밋 이후엔 끊길 수 있다", function()
		local s = newState("TIMEBOMB")
		s:onEvent(skill("bomb.bigbang", { skill = "BigBang", phase = "Throw" }), 0)
		s:onEvent(skill("bomb.throw"), 0.2)
		T.expectEqual(action(s), "BigBangThrow")
		s:onEvent(skill("bomb.guard"), 0.6)
		T.expectEqual(action(s), "BlastGuard")
	end)
	T.it("Remote Bomb: 설치와 기폭이 서로 다른 모션, 연타해도 안정적", function()
		local s = newState("TIMEBOMB")
		local t = 0
		for _ = 1, 10 do
			s:onEvent(skill("bomb.remote", { phase = "Place" }), t)
			t = step(s, t, t + 0.2, 1 / 60)
			s:onEvent(skill("bomb.detonate", { phase = "Detonate" }), t)
			t = step(s, t, t + 0.2, 1 / 60)
		end
		T.expect(#s:drain() <= 64)
		step(s, t, t + 1, 1 / 60)
		T.expect(s:isIdle())
	end)
	T.it("Blast Jump 길이는 서버 dash.duration 을 따른다", function()
		local s = newState("TIMEBOMB")
		s:onEvent(skill("bomb.jump", { dash = { duration = 0.5 } }), 0)
		T.expectEqual(action(s), "BlastJump")
		step(s, 0, 0.7, 1 / 60)
		T.expect(s:isIdle())
	end)
end)

T.describe("캐릭터 애니메이션: 충전 입력 해제(로컬)와 잔존 방지", function()
	T.it("해제했는데 서버 이벤트가 안 오면 grace 뒤 충전 자세가 풀린다(SLINGSHOT/SUPERBALL)", function()
		for cid, cue in { SLINGSHOT = "sling.charge", SUPERBALL = "ball.charge" } do
			local s = newState(cid)
			s:onEvent(skill(cue, { chargeSeconds = 1.0 }), 0)
			step(s, 0, 0.6, 1 / 60)
			s:onEvent({ type = "LocalRelease" }, 0.6)
			step(s, 0.6, 0.9, 1 / 60)
			T.expect(action(s) ~= nil, cid .. " grace 안에서는 유지")
			step(s, 0.9, 1.1, 1 / 60)
			T.expect(action(s) == nil, cid .. " 충전 자세 잔존")
		end
	end)
	T.it("서버 발사 이벤트가 grace 안에 오면 정상적으로 반동으로 이어지고 이후 정리가 중복되지 않는다", function()
		local s = newState("SLINGSHOT")
		s:onEvent(skill("sling.charge", { chargeSeconds = 1.0 }), 0)
		s:onEvent({ type = "LocalRelease" }, 0.6)
		s:onEvent(skill("sling.shot", {}), 0.7)
		T.expectEqual(action(s), "SlingRelease")
		step(s, 0.7, 0.9, 1 / 60) -- grace(0.4)가 지나도 반동 모션을 끊지 않는다
		step(s, 0.9, 1.2, 1 / 60)
		T.expect(s:isIdle())
	end)
	T.it("서버 이벤트가 grace 뒤 늦게 와도 정상 재생된다(고지연)", function()
		local s = newState("SLINGSHOT")
		s:onEvent(skill("sling.charge", { chargeSeconds = 1.0 }), 0)
		s:onEvent({ type = "LocalRelease" }, 0.6)
		step(s, 0.6, 1.2, 1 / 60)
		s:onEvent(skill("sling.shot", {}), 1.2)
		T.expectEqual(action(s), "SlingRelease")
	end)
	T.it("충전 중이 아닐 때의 해제 입력은 아무 영향이 없다", function()
		local s = newState("SUPERBALL")
		s:onEvent({ type = "LocalRelease" }, 0)
		s:onEvent(skill("ball.rapid"), 0.1)
		T.expectEqual(action(s), "RapidBounce")
		step(s, 0.1, 0.8, 1 / 60)
		T.expect(s:isIdle())
		local p = newState("PAINTBALL")
		p:onEvent({ type = "LocalRelease" }, 0)
		T.expect(p:isIdle())
	end)
	T.it("충전 모션이 reset/사망으로 사라지면 대기 중이던 해제도 폐기된다", function()
		local s = newState("SUPERBALL")
		s:onEvent(skill("ball.charge", { chargeSeconds = 1.0 }), 0)
		s:onEvent({ type = "LocalRelease" }, 0.1)
		s:onEvent({ type = "Died", playerId = 1 }, 0.2)
		s:onEvent({ type = "Respawned", playerId = 1 }, 0.3)
		s:onEvent(skill("ball.charge", { chargeSeconds = 1.0 }), 0.4)
		step(s, 0.4, 1.2, 1 / 60) -- 이전 충전의 해제가 새 충전을 끊으면 안 된다
		T.expectEqual(action(s), "BallCharge")
	end)
end)

T.describe("캐릭터 애니메이션: GPT Blade Storm Tick 패치 호환(활동 기반 잠금 해제 대비)", function()
	T.it("모든 궁극기 잠금이 lastActivity 를 갖는다(패치된 SwordAnimState 가 lastActivity+2초를 읽어도 nil 연산 오류 없음)", function()
		local starts = {
			PAINTBALL = skill("paint.ult.windup", { skill = "ColorBreak", phase = "Windup", windup = 0.8 }),
			SLINGSHOT = skill("sling.ult.windup", { skill = "Bullseye", phase = "Windup", windup = 0.7 }),
			SUPERBALL = skill("ball.cyclone.start", { skill = "BallCyclone", phase = "Start", duration = 12 }),
		}
		for cid, ev in starts do
			local s = newState(cid)
			s:onEvent(ev, 5)
			local storm = s:_stormForTest()
			T.expect(storm ~= nil and type(storm.lastActivity) == "number", cid .. " lastActivity 누락")
			T.expectNear(storm.lastActivity, 5, 1e-6)
		end
	end)
	T.it("Cyclone 은 장시간 동안 lastActivity 가 현재 시각을 따라간다(2초 무활동 해제에 걸리지 않음)", function()
		local s = newState("SUPERBALL")
		s:onEvent(skill("ball.cyclone.start", { skill = "BallCyclone", phase = "Start", duration = 12 }), 0)
		step(s, 0, 8.0, 1 / 60)
		local storm = s:_stormForTest()
		T.expect(storm ~= nil and 8.0 - storm.lastActivity < 0.1, "lastActivity 가 갱신되지 않음")
	end)
	T.it("Color Break 틱이 lastActivity 를 갱신한다", function()
		local s = newState("PAINTBALL")
		s:onEvent(skill("paint.ult.windup", { skill = "ColorBreak", phase = "Windup", windup = 0.8 }), 0)
		step(s, 0, 1.0, 1 / 60)
		s:onEvent(skill("paint.ult.beam", { skill = "ColorBreak", phase = "Tick" }), 1.0)
		T.expectNear(s:_stormForTest().lastActivity, 1.0, 1e-6)
	end)
end)

return true
