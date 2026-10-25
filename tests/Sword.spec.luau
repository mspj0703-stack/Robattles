--!nonstrict
-- Phase 2 Step 1: SWORD 전체 스킬(서버 로직) 회귀. 3타 콤보, Triple Slash, Lunge, Blade Wave, Blade Storm, Duelist, 이동 허가, 보안.
-- 확정/임시 수치 구분은 Data/Characters.SWORD 주석과 docs/ASSUMPTIONS.md A65~A67. Roblox 실제 동작(이동 적용·충돌·렌더)은 Studio 미검증.
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local H = require(script.Parent.Helpers)
local Core = Env.server("CombatCore")
local ProjectileService = Env.server("ProjectileService")
local Controller = Env.server("CharacterController")
local Movement = Env.server("MovementValidator")
local Duelist = Env.server("Duelist")
local Characters = Env.shared("Data/Characters")
local Config = Env.shared("Config")
local RemoteSpec = Env.shared("RemoteSpec")
local Gate = Env.server("RemoteGate")
local Router = Env.server("ServerRouter")
local InputState = Env.client("Logic/InputState")
local MovementModel = Env.client("Logic/MovementModel")
local EffectsModel = Env.client("Logic/EffectsModel")
local FeedbackModel = Env.client("Logic/FeedbackModel")
local HudModel = Env.client("Logic/HudModel")

local v = H.v
local fwd = v(0, 0, 1)
local S = Characters.SWORD

local function setup(ids, opts)
	opts = opts or {}
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
	local movement
	if opts.movement then
		movement = Movement.new({ world = H.fakeWorld({ { point = v(0, 0, 0), normal = v(0, 1, 0) } }) })
	end
	local c = Controller.new({ characters = H.legacyChars(Env.shared("Data/Characters")),
		core = core, projectiles = ps, targets = targets, world = world, movement = movement,
		getPose = function(id) return { pos = pos[id], forward = face[id], airborne = false } end,
	})
	local events = {}
	c:onFeedback(function(e) table.insert(events, e) end)
	for id, ch in ids do
		c:addPlayer(id, ch)
		pos[id] = v(0, 0, 0)
		face[id] = fwd
		if movement then movement:register(id, v(0, 3.2, 0), 0) end
	end
	return c, core, pos, events, movement, face
end

local function skill(slot, phase) return { slot = slot, aimDirection = fwd, phase = phase } end
local function prim() return { action = "Primary", aimDirection = fwd } end
local function hp(core, id) return H.hp(core, id) end
-- Duelist 보너스를 배제하고 순수 단계 피해를 측정할 때 사용(테스트 전용)
local function noDuelist(c) c._sword:duelist():clearAttacker("a") end
local function count(events, ty, f)
	local n = 0
	for _, e in events do if e.type == ty and (not f or f(e)) then n += 1 end end
	return n
end

T.describe("SWORD LMB 3타 콤보 (14/14/18)", function()
	T.it("1·2·3타 피해 14/14/18, 3타 뒤 다시 1타", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 4)
		local t = 0
		local expected = { 14, 14, 18, 14 }
		for i, dmg in expected do
			noDuelist(c)
			local before = hp(core, "b")
			T.expect((c:handleAttack("a", prim(), t)), "공격 " .. i)
			T.expectEqual(before - hp(core, "b"), dmg, "타 " .. i)
			core.damage:respawn("b") -- 체력 초기화로 반복 측정
			t += 1.0 -- 쿨타임·이어짐 창 안(1.2초 이내)
		end
	end)
	T.it("이어짐 창(1.2초)을 넘기면 1타부터 다시", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 4)
		c:handleAttack("a", prim(), 0) -- 1타
		core.damage:respawn("b")
		c:handleAttack("a", prim(), 0.6) -- 2타
		core.damage:respawn("b")
		noDuelist(c)
		c:handleAttack("a", prim(), 3.0) -- 창 초과 → 다시 1타(14)
		T.expectEqual(100 - hp(core, "b"), 14)
	end)
	T.it("타격별 다중 대상 적중: 부채꼴 안의 모든 적", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD", d = "SWORD", e = "SWORD" })
		pos.b, pos.d, pos.e = v(0, 0, 4), v(1.5, 0, 4), v(0, 0, -4) -- e 는 뒤쪽
		local ok, info = c:handleAttack("a", prim(), 0)
		T.expect(ok)
		T.expectEqual(#info.hits, 2)
		T.expectEqual(hp(core, "b"), 86)
		T.expectEqual(hp(core, "d"), 86)
		T.expectEqual(hp(core, "e"), 100)
	end)
	T.it("쿨타임 안의 재입력은 거부(콤보 단계 유지), 부활 보호는 승인 시에만 해제", function()
		local c, core, pos, events = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 4)
		c:respawn("a", 0)
		T.expect((c:handleAttack("a", prim(), 10))) -- 승인
		T.expect(not c:isProtected("a", 10.01))
		local ok, why = c:handleAttack("a", prim(), 10.1)
		T.expect(not ok and why == "on_cooldown")
		core.damage:respawn("b")
		c:handleAttack("a", prim(), 10.7) -- 2타(14): 단계가 건너뛰어지지 않았다
		T.expectEqual(100 - hp(core, "b"), 14)
	end)
	T.it("패링에 막힌 타격은 피해 없음 + 자동 반격 18, 사망 후 입력 거부", function()
		local c, core, pos, _, _, face = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 4)
		face.b = v(0, 0, -1)
		T.expect(c:handleAttack("b", { action = "Secondary", aimDirection = v(0, 0, -1) }, 0))
		T.expect(c:handleAttack("a", prim(), 0.1))
		T.expectEqual(hp(core, "b"), 100)
		T.expectEqual(hp(core, "a"), 82)
		core.damage:applyDamage({ attackerId = "b", targetId = "a", attackId = "k", amount = 999 }, 0.2)
		local ok, why = c:handleAttack("a", prim(), 1.5)
		T.expect(not ok)
	end)
end)

T.describe("SWORD Skill 1 — Triple Slash (10/14/22)", function()
	T.it("키 세 번: 10 → 14 → 22, 3번째 후 쿨타임(8초) 시작", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 4)
		local expected = { 10, 14, 22 }
		local t = 0
		for i, dmg in expected do
			core.damage:respawn("b")
			noDuelist(c)
			local ok, info = c:handleSkill("a", skill(1), t)
			T.expect(ok, "step " .. i)
			T.expectEqual(info.step, i)
			T.expectEqual(100 - hp(core, "b"), dmg)
			t += 0.4
		end
		local ok, why = c:handleSkill("a", skill(1), t)
		T.expect(not ok and why == "on_cooldown")
		T.expect(c:handleSkill("a", skill(1), t + 8))
	end)
	T.it("연계 사이 최소 간격(0.3초) 미만 거부, 창(1.5초) 만료 시 쿨타임 시작 후 처음부터", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 4)
		T.expect(c:handleSkill("a", skill(1), 0))
		local ok, why = c:handleSkill("a", skill(1), 0.1)
		T.expect(not ok and why == "too_soon")
		-- 창 만료(1.5초) → 쿨타임이 만료 시점부터
		local ok2, why2 = c:handleSkill("a", skill(1), 1.6)
		T.expect(not ok2 and why2 == "on_cooldown")
		T.expect(c:handleSkill("a", skill(1), 1.5 + 8 + 0.01))
	end)
	T.it("타격별 전진: 이동 허가(TripleSlash)를 단계마다 발급, 이벤트에 dash 정보", function()
		local c, core, pos, events, movement = setup({ a = "SWORD", b = "SWORD" }, { movement = true })
		pos.b = v(0, 0, 4)
		T.expect(c:handleSkill("a", skill(1), 1))
		T.expectEqual(movement:getPermitCount("a", 1.01), 1)
		T.expect(c:handleSkill("a", skill(1), 1.4))
		T.expectEqual(movement:getPermitCount("a", 1.41), 2) -- 단계마다 새 허가
		T.expect(c:handleSkill("a", skill(1), 1.8))
		T.expect(movement:getPermitCount("a", 1.81) >= 1)
		local e
		for _, ev in events do if ev.type == "SwordSkill" and ev.skill == "TripleSlash" and ev.step == 1 then e = ev end end
		T.expect(e and e.dash and e.dash.speed > 0 and e.dash.duration == S.skills[1].advanceDuration)
	end)
	T.it("이동 허가 거부(제한 초과) 시 쿨타임·연계·보호를 소모하지 않는다", function()
		local c, core, pos, events, movement = setup({ a = "SWORD", b = "SWORD" }, { movement = true })
		pos.b = v(0, 0, 4)
		c:respawn("a", 0)
		-- 허가를 가득 채운다(Knockback 은 최소 간격 0)
		for _ = 1, Config.MoveCheck.MaxActivePermits do T.expect((movement:issue("a", "Knockback", 1.0, { duration = 0.6, speed = 1 }))) end
		local ok, why = c:handleSkill("a", skill(1), 1.1)
		T.expect(not ok and string.find(why, "movement_denied") ~= nil, tostring(why))
		T.expect(core.cooldown:isReady("a", "skill1", 1.1))
		T.expectEqual(hp(core, "b"), 100) -- 거부된 요청은 피해를 주지 않는다
		T.expect(c:isProtected("a", 1.1)) -- 거부된 요청은 부활 보호를 해제하지 않는다
	end)
	T.it("패링에 막힌 타격은 피해 없음 + 반격", function()
		local c, core, pos, events, _, face = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 4)
		face.b = v(0, 0, -1)
		T.expect(c:handleAttack("b", { action = "Secondary", aimDirection = v(0, 0, -1) }, 0))
		T.expect(c:handleSkill("a", skill(1), 0.1))
		T.expectEqual(hp(core, "b"), 100)
		T.expectEqual(hp(core, "a"), 82)
	end)
end)

T.describe("SWORD Skill 2 — Lunge (충전 18~32, 경로 다중 적중)", function()
	local function lungeAt(c, core, pos, t0, holdSeconds)
		T.expect((c:handleSkill("a", skill(2, "Press"), t0)))
		return c:handleSkill("a", skill(2, "Release"), t0 + holdSeconds)
	end
	T.it("충전량에 비례한 피해: 즉시 18, 0.5초 25, 1초 이상 32", function()
		for _, case in { { 0, 18 }, { 0.5, 25 }, { 1.0, 32 }, { 1.4, 32 } } do
			local c, core, pos, events = setup({ a = "SWORD", b = "SWORD" })
			pos.b = v(0, 0, 10)
			local ok, info = lungeAt(c, core, pos, 0, case[1])
			T.expect(ok)
			T.expectNear(info.damage, case[2], 1e-6)
			-- 돌진: a 가 b 쪽으로 이동하며 경로 판정
			local t = case[1]
			for _ = 1, 12 do
				t += 1 / 30
				pos.a = v(0, 0, math.min(16, pos.a.Z + 16 / 0.28 / 30))
				c:update(t, 1 / 30)
			end
			T.expectNear(100 - hp(core, "b"), case[2], 1e-6, "충전 " .. case[1])
		end
	end)
	T.it("이동 경로상의 여러 적을 한 번씩 적중, 경로 밖/뒤쪽 적은 제외", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD", d = "SWORD", e = "SWORD", f = "SWORD" })
		pos.b, pos.d, pos.e, pos.f = v(0, 0, 6), v(0.5, 0, 12), v(12, 0, 8), v(0, 0, -6)
		local ok = lungeAt(c, core, pos, 0, 0)
		T.expect(ok)
		local t = 0
		for _ = 1, 14 do
			t += 1 / 30
			pos.a = v(0, 0, math.min(16, pos.a.Z + 16 / 0.28 / 30))
			c:update(t, 1 / 30)
		end
		T.expectEqual(hp(core, "b"), 82)
		T.expectEqual(hp(core, "d"), 82)
		T.expectEqual(hp(core, "e"), 100)
		T.expectEqual(hp(core, "f"), 100)
	end)
	T.it("같은 돌진에서 한 대상은 한 번만 맞는다(여러 틱 중복 없음)", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 6)
		lungeAt(c, core, pos, 0, 0)
		local t = 0
		for _ = 1, 30 do
			t += 1 / 30
			pos.a = v(0, 0, math.min(7, pos.a.Z + 1))
			c:update(t, 1 / 30)
		end
		T.expectEqual(hp(core, "b"), 82)
	end)
	T.it("Release 는 충전 중일 때만 유효(위조 Release·중복 Release 거부), 충전 중 재Press 거부", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD" })
		local ok, why = c:handleSkill("a", skill(2, "Release"), 0)
		T.expect(not ok and why == "not_charging")
		T.expect(c:handleSkill("a", skill(2, "Press"), 1))
		local ok2, why2 = c:handleSkill("a", skill(2, "Press"), 1.1)
		T.expect(not ok2 and why2 == "already_charging")
		T.expect(c:handleSkill("a", skill(2, "Release"), 1.5))
		local ok3, why3 = c:handleSkill("a", skill(2, "Release"), 1.6)
		T.expect(not ok3 and why3 == "not_charging")
	end)
	T.it("쿨타임: 돌진 시작부터 9초, 그 사이 Press 거부", function()
		local c = setup({ a = "SWORD" })
		T.expect(c:handleSkill("a", skill(2, "Press"), 0))
		T.expect(c:handleSkill("a", skill(2, "Release"), 0.2))
		c:update(1.0, 0.8) -- 돌진 종료 처리
		local ok, why = c:handleSkill("a", skill(2, "Press"), 5)
		T.expect(not ok and why == "on_cooldown")
		c:update(9.3, 0.1)
		T.expect(c:handleSkill("a", skill(2, "Press"), 9.3))
	end)
	T.it("키를 떼는 요청이 없어도 최대 충전 + 유예 후 서버가 자동 발사", function()
		local c, core, pos, events = setup({ a = "SWORD", b = "SWORD" })
		c:handleSkill("a", skill(2, "Press"), 0)
		c:update(1.0, 0.05)
		T.expectEqual(count(events, "SwordSkill", function(e) return e.skill == "Lunge" and e.phase == "Dash" end), 0)
		c:update(1.6, 0.05)
		T.expectEqual(count(events, "SwordSkill", function(e) return e.skill == "Lunge" and e.phase == "Dash" end), 1)
	end)
	T.it("충전 중 다른 공격·스킬·궁극기는 busy, 회피는 충전 취소(쿨타임 소모 없음)", function()
		local c, core = setup({ a = "SWORD" })
		c:handleSkill("a", skill(2, "Press"), 0)
		local ok, why = c:handleAttack("a", prim(), 0.2)
		T.expect(not ok and why == "busy")
		T.expect(select(2, c:handleSkill("a", skill(3), 0.2)) == "busy")
		T.expect(select(2, c:handleSkill("a", skill(1), 0.2)) == "busy")
		T.expect(select(2, c:handleAttack("a", { action = "Secondary", aimDirection = fwd }, 0.2)) == "busy")
		T.expect(c:handleDodge("a", { direction = v(1, 0, 0) }, 0.3))
		T.expect(core.cooldown:isReady("a", "skill2", 0.3))
		T.expect(c:handleAttack("a", prim(), 0.5)) -- 취소 후 다시 가능
	end)
	T.it("이동 허가(Lunge) 발급", function()
		local c, core, pos, events, movement = setup({ a = "SWORD" }, { movement = true })
		c:handleSkill("a", skill(2, "Press"), 1)
		T.expect(c:handleSkill("a", skill(2, "Release"), 1.5))
		T.expectEqual(movement:getPermitCount("a", 1.51), 1)
	end)
	T.it("이동 허가 거부 시 충전은 취소되고 쿨타임을 쓰지 않으며 돌진도 없다", function()
		local c, core, pos, events, movement = setup({ a = "SWORD", b = "SWORD" }, { movement = true })
		pos.b = v(0, 0, 6)
		T.expect(c:handleSkill("a", skill(2, "Press"), 1))
		for _ = 1, Config.MoveCheck.MaxActivePermits do T.expect((movement:issue("a", "Knockback", 1.2, { duration = 0.6, speed = 1 }))) end
		local ok, why = c:handleSkill("a", skill(2, "Release"), 1.3)
		T.expect(not ok and string.find(why, "movement_denied") ~= nil, tostring(why))
		T.expect(core.cooldown:isReady("a", "skill2", 1.3))
		T.expectEqual(count(events, "SwordSkill", function(e) return e.skill == "Lunge" and e.phase == "Cancel" end), 1)
		local ok2, why2 = c:handleSkill("a", skill(2, "Release"), 1.4)
		T.expect(not ok2 and why2 == "not_charging")
		T.expectEqual(hp(core, "b"), 100)
	end)
	T.it("사망 시 충전/돌진 상태 정리", function()
		local c, core, pos, events = setup({ a = "SWORD", b = "SWORD" })
		c:handleSkill("a", skill(2, "Press"), 0)
		core.damage:applyDamage({ attackerId = "b", targetId = "a", attackId = "k", amount = 999 }, 0.2)
		T.expect(not select(1, c:handleSkill("a", skill(2, "Release"), 0.3)))
		c:respawn("a", 5)
		local ok, why = c:handleSkill("a", skill(2, "Release"), 5.1)
		T.expect(not ok and why == "not_charging")
	end)
end)

T.describe("SWORD Skill 3 — Blade Wave (20, 부채꼴 광역)", function()
	T.it("전방 부채꼴 안의 모든 적에게 20 피해, 뒤/밖은 제외", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD", d = "SWORD", e = "SWORD", f = "SWORD" })
		pos.b, pos.d, pos.e, pos.f = v(0, 0, 10), v(3, 0, 10), v(0, 0, -5), v(0, 0, 25)
		local ok, info = c:handleSkill("a", skill(3), 0)
		T.expect(ok)
		T.expectEqual(#info.hits, 2)
		T.expectEqual(hp(core, "b"), 80)
		T.expectEqual(hp(core, "d"), 80)
		T.expectEqual(hp(core, "e"), 100)
		T.expectEqual(hp(core, "f"), 100)
	end)
	T.it("쿨타임 6초, 거부 시 상태 유지", function()
		local c = setup({ a = "SWORD" })
		T.expect(c:handleSkill("a", skill(3), 0))
		local ok, why = c:handleSkill("a", skill(3), 3)
		T.expect(not ok and why == "on_cooldown")
		T.expect(c:handleSkill("a", skill(3), 6.01))
	end)
	T.it("패링한 상대에게는 차단되고 반격을 받는다", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 8)
		-- b 는 -Z(= a 쪽)를 보고 패링
		local c2, core2, pos2, _, _, face2 = setup({ a = "SWORD", b = "SWORD" })
		pos2.b = v(0, 0, 4)
		face2.b = v(0, 0, -1)
		T.expect(c2:handleAttack("b", { action = "Secondary", aimDirection = v(0, 0, -1) }, 0))
		T.expect(c2:handleSkill("a", skill(3), 0.1))
		T.expectEqual(hp(core2, "b"), 100) -- 차단
		T.expectEqual(hp(core2, "a"), 82) -- 자동 반격 18
	end)
end)

T.describe("SWORD Ultimate — Blade Storm (5×8 + 25)", function()
	local function full(core, id) for _ = 1, 5 do core.ultimate:addKill(id) end end
	T.it("게이지 부족은 거부(소모 없음), 가득이면 발동하고 100% 소모", function()
		local c, core = setup({ a = "SWORD" })
		local ok, why = c:handleUltimate("a", {}, 0)
		T.expect(not ok and why == "not_ready")
		full(core, "a")
		T.expect((c:handleUltimate("a", {}, 0)))
		T.expectEqual(core.ultimate:getGauge("a"), 0)
	end)
	T.it("틱 8회 × 5 + 마무리 25 = 총 65, 반경 안의 모든 적, 밖은 제외", function()
		local c, core, pos, events = setup({ a = "SWORD", b = "SWORD", d = "SWORD", e = "SWORD" })
		pos.b, pos.d, pos.e = v(0, 0, 5), v(-6, 0, 3), v(0, 0, 30)
		full(core, "a")
		T.expect((c:handleUltimate("a", {}, 0)))
		local t = 0
		while t < 3.2 do
			t += 0.05
			c:update(t, 0.05)
		end
		T.expectEqual(hp(core, "b"), 100 - 65)
		T.expectEqual(hp(core, "d"), 100 - 65)
		T.expectEqual(hp(core, "e"), 100)
		T.expectEqual(count(events, "SwordSkill", function(e) return e.skill == "BladeStorm" and e.phase == "Tick" end), 8)
		T.expectEqual(count(events, "SwordSkill", function(e) return e.skill == "BladeStorm" and e.phase == "Finisher" end), 1)
		T.expect(not core.ultimate:isActive("a"))
	end)
	T.it("시전 중 다른 공격/스킬/재발동은 busy, 끝나면 다시 가능", function()
		local c, core = setup({ a = "SWORD" })
		full(core, "a")
		c:handleUltimate("a", {}, 0)
		T.expect(select(2, c:handleAttack("a", prim(), 0.5)) == "busy")
		T.expect(select(2, c:handleSkill("a", skill(3), 0.5)) == "busy")
		local t = 0
		while t < 3.2 do t += 0.05; c:update(t, 0.05) end
		T.expect((c:handleAttack("a", prim(), 3.5)))
	end)
	T.it("시전 중 사망하면 남은 틱·마무리는 발생하지 않는다", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD", k = "SWORD" })
		pos.b = v(0, 0, 5)
		full(core, "a")
		c:handleUltimate("a", {}, 0)
		local t = 0
		while t < 0.7 do t += 0.05; c:update(t, 0.05) end
		core.damage:applyDamage({ attackerId = "k", targetId = "a", attackId = "x", amount = 999 }, 0.75)
		local hpAt = hp(core, "b")
		while t < 3.3 do t += 0.05; c:update(t, 0.05) end
		T.expectEqual(hp(core, "b"), hpAt)
		T.expectEqual(core.ultimate:getGauge("a") < 100, true) -- 게이지는 발동 시 소모됨
	end)
	T.it("부활 보호 중인 적은 맞지 않는다(체력·점수 변화 없음)", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 5)
		c:respawn("b", 0)
		full(core, "a")
		c:handleUltimate("a", {}, 0)
		local t = 0
		while t < 1.5 do t += 0.05; c:update(t, 0.05) end
		T.expectEqual(hp(core, "b"), 100)
	end)
	T.it("승인 시 부활 보호 해제, 거부(not_ready)는 보호 유지", function()
		local c, core = setup({ a = "SWORD" })
		c:respawn("a", 0)
		T.expect(not (c:handleUltimate("a", {}, 0.1)))
		T.expect(c:isProtected("a", 0.2))
		full(core, "a")
		T.expect((c:handleUltimate("a", {}, 0.3)))
		T.expect(not c:isProtected("a", 0.31))
	end)
end)

T.describe("SWORD Passive — Duelist (3연속 +8, 전역 4초)", function()
	local d = Characters.SWORD.passive
	T.it("순수 로직: 같은 대상 3번째 적중에 +8, 발동 후 4초 전역 제한", function()
		local du = Duelist.new(d)
		T.expectEqual(du:bonusFor("a", "b", 0), 0)
		du:onValidHit("a", "b", 0, false)
		T.expectEqual(du:bonusFor("a", "b", 0.5), 0)
		du:onValidHit("a", "b", 0.5, false)
		T.expectEqual(du:bonusFor("a", "b", 1.0), 8)
		T.expect(du:onValidHit("a", "b", 1.0, true))
		-- 전역 제한: 다른 대상도 4초 동안 발동 없음
		for i = 1, 3 do du:onValidHit("a", "c", 1 + i * 0.1, false) end
		T.expectEqual(du:bonusFor("a", "c", 2.0), 0)
		T.expectEqual(du:bonusFor("a", "c", 5.1), 0) -- 제한 중 적중은 카운트하지 않았으므로 새로 시작
		du:onValidHit("a", "c", 5.1, false)
		du:onValidHit("a", "c", 5.2, false)
		T.expectEqual(du:bonusFor("a", "c", 5.3), 8)
	end)
	T.it("대상별 카운터는 독립, 다른 대상 적중이 카운터를 끊지 않음, 창(3초) 초과 시 초기화", function()
		local du = Duelist.new(d)
		du:onValidHit("a", "b", 0, false)
		du:onValidHit("a", "c", 0.2, false)
		du:onValidHit("a", "b", 0.4, false)
		T.expectEqual(du:bonusFor("a", "b", 0.6), 8)
		T.expectEqual(du:bonusFor("a", "c", 0.6), 0)
		T.expectEqual(du:bonusFor("a", "b", 4.0), 0) -- 창 초과로 초기화
	end)
	T.it("공격자별 독립, 대상 사망/퇴장 시 해당 카운터 제거", function()
		local du = Duelist.new(d)
		du:onValidHit("a", "b", 0, false)
		du:onValidHit("a", "b", 0.1, false)
		du:onValidHit("x", "b", 0.1, false)
		du:clearTarget("b")
		T.expectEqual(du:bonusFor("a", "b", 0.2), 0)
		T.expectEqual(du:bonusFor("x", "b", 0.2), 0)
		du:onValidHit("a", "b", 0.3, false)
		du:onValidHit("a", "b", 0.4, false)
		du:clearAttacker("a")
		T.expectEqual(du:bonusFor("a", "b", 0.5), 0)
	end)
	T.it("통합: 같은 대상 LMB 3번째 적중 = 18 + 8 = 26, 이후 4초간 재발동 없음", function()
		local c, core, pos, events = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 4)
		local total = 0
		local steps = { 14, 14, 26 } -- 1·2타 일반, 3타 18+8
		local t = 0
		for i, expect in steps do
			core.damage:respawn("b")
			c:handleAttack("a", prim(), t)
			T.expectEqual(100 - hp(core, "b"), expect, "타 " .. i)
			t += 0.9
		end
		T.expectEqual(count(events, "Duelist"), 1)
		-- 제한 4초 안: 같은 대상에 3연속 해도 보너스 없음
		for i = 1, 3 do
			core.damage:respawn("b")
			c:handleAttack("a", prim(), t)
			t += 0.3 < 0.55 and 0.6 or 0.6
		end
		T.expectEqual(count(events, "Duelist"), 1)
	end)
	T.it("차단(패링)·부활 보호·회피 무적으로 피해가 적용되지 않은 공격은 카운트되지 않는다", function()
		local c, core, pos, events = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 4)
		c:respawn("b", 0) -- 보호 중
		c:handleAttack("a", prim(), 0.1)
		c:handleAttack("a", prim(), 0.7)
		c:handleAttack("a", prim(), 1.3)
		T.expectEqual(hp(core, "b"), 100)
		T.expectEqual(count(events, "Duelist"), 0)
		T.expectEqual(c._sword:duelist():count("a", "b", 1.3), 0)
	end)
	T.it("Triple Slash 3타(22)도 Duelist 대상: 세 번째 22+8 = 30", function()
		local c, core, pos, events = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 4)
		local t = 0
		local seen = {}
		for i = 1, 3 do
			core.damage:respawn("b")
			c:handleSkill("a", skill(1), t)
			seen[i] = 100 - hp(core, "b")
			t += 0.4
		end
		T.expectEqual(seen[1], 10)
		T.expectEqual(seen[2], 14)
		T.expectEqual(seen[3], 30)
	end)
	T.it("Blade Storm 틱은 Duelist 카운트/발동에 영향을 주지 않는다(임시 규칙 A66)", function()
		local c, core, pos, events = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 5)
		for _ = 1, 5 do core.ultimate:addKill("a") end
		c:handleUltimate("a", {}, 0)
		local t = 0
		while t < 3.2 do t += 0.05; c:update(t, 0.05) end
		T.expectEqual(count(events, "Duelist"), 0)
		T.expectEqual(c._sword:duelist():count("a", "b", 3.2), 0)
	end)
end)

T.describe("SWORD 보안: 위조 입력·원격 검증·서버 권위", function()
	local function router(c, core, pos)
		local gate = Gate.new({
			cooldown = core.cooldown,
			getState = function(id) return { alive = core.damage:isAlive(id), pos = pos[id], serverTime = 0, character = Characters.SWORD } end,
		})
		return Router.new({ gate = gate, controller = c })
	end
	T.it("RemoteSpec: Skill phase 는 Press/Release 만, 피해/대상 필드는 허용되지 않는다", function()
		local base = { slot = 2, aimOrigin = v(0, 0, 0), aimDirection = v(0, 0, 1), clientTime = 0 }
		T.expect(RemoteSpec.validate("Skill", base))
		base.phase = "Release"
		T.expect(RemoteSpec.validate("Skill", base))
		base.phase = "Hack"
		T.expect(not RemoteSpec.validate("Skill", base))
		base.phase = "Press"
		base.damage = 999
		T.expect(not RemoteSpec.validate("Skill", base))
		base.damage, base.targetId = nil, "b"
		T.expect(not RemoteSpec.validate("Skill", base))
		T.expect(not RemoteSpec.validate("Skill", { slot = 4, aimOrigin = v(0, 0, 0), aimDirection = v(0, 0, 1), clientTime = 0 }))
	end)
	T.it("라우터 경유: 스킬 3 정상 처리, 같은 요청 반복은 쿨타임 거부", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 8)
		local r = router(c, core, pos)
		local payload = { slot = 3, aimOrigin = v(0, 0, 0), aimDirection = v(0, 0, 1), clientTime = 0 }
		T.expect((r:dispatch("a", "Skill", payload, 0)))
		local ok, why = r:dispatch("a", "Skill", payload, 0.2)
		T.expect(not ok and why == "on_cooldown")
		T.expectEqual(hp(core, "b"), 80)
	end)
	T.it("시간 왜곡/원점 위조 요청은 게이트에서 거부되어 스킬이 실행되지 않는다", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 8)
		local r = router(c, core, pos)
		local ok, why = r:dispatch("a", "Skill", { slot = 3, aimOrigin = v(0, 0, 0), aimDirection = v(0, 0, 1), clientTime = 99 }, 0)
		T.expect(not ok and why == "time_skew")
		local ok2, why2 = r:dispatch("a", "Skill", { slot = 3, aimOrigin = v(50, 0, 0), aimDirection = v(0, 0, 1), clientTime = 0 }, 0)
		T.expect(not ok2 and why2 == "origin_mismatch")
		T.expect(core.cooldown:isReady("a", "skill3", 0))
		T.expectEqual(hp(core, "b"), 100)
	end)
	T.it("기절/행동 불가 중에는 스킬·콤보·궁극기 거부, 쿨타임 소모 없음", function()
		local c, core = setup({ a = "SWORD" })
		core.status:apply("a", { type = "Stun", duration = 1 }, 0, { strong = true })
		T.expect(not (c:handleSkill("a", skill(3), 0.1)))
		T.expect(not (c:handleAttack("a", prim(), 0.1)))
		T.expect(core.cooldown:isReady("a", "skill3", 0.1))
		T.expect(core.cooldown:isReady("a", "primary", 0.1))
	end)
	T.it("스킬은 클라이언트가 보낸 대상·피해 없이 서버 판정만 사용(조준 방향만 의사)", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 8)
		local ok, info = c:handleSkill("a", { slot = 3, aimDirection = fwd, damage = 9999, targetId = "b" }, 0)
		T.expect(ok)
		T.expectEqual(hp(core, "b"), 80)
	end)
	T.it("HUD 스냅샷: SWORD 스킬 3칸 구현됨(이름·쿨타임), 콤보 단계, Duelist 제한 시각, 궁극기 구현됨", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 4)
		c:handleSkill("a", skill(3), 0)
		c:handleAttack("a", prim(), 0)
		local snap = c:getHudSnapshot("a", 0.1)
		for i = 1, 3 do T.expect(snap.skills[i].implemented == true and type(snap.skills[i].name) == "string") end
		T.expect(snap.skills[3].readyAt > 0.1)
		T.expectEqual(snap.combo.step, 2)
		T.expect(snap.ultimate.implemented == true)
		T.expect(snap.passive.id == "Duelist")
	end)
end)

T.describe("SWORD 클라이언트 순수 로직 (입력·이동·연출·HUD) — 실제 렌더/입력은 Studio 미검증", function()
	T.it("숫자 2 누르면 Press, 떼면 Release 전송(서버 스키마 통과), 누르지 않은 Release 는 없음", function()
		local i = InputState.new()
		local down = i:press("Two", 0)[1]
		T.expect(down.remote == "Skill" and down.slot == 2 and down.phase == "Press")
		local up = i:release("Two")[1]
		T.expect(up.remote == "Skill" and up.slot == 2 and up.phase == "Release")
		T.expectEqual(#i:release("Two"), 0)
		local payload = { slot = up.slot, phase = up.phase, aimOrigin = v(0, 0, 0), aimDirection = v(0, 0, 1), clientTime = 0 }
		T.expect(RemoteSpec.validate("Skill", payload))
	end)
	T.it("포커스를 잃으면 누르고 있던 Lunge 를 Release 로 정리", function()
		local i = InputState.new()
		i:press("Two", 0)
		local cmds = i:releaseAll()
		local found = false
		for _, c in cmds do if c.remote == "Skill" and c.phase == "Release" then found = true end end
		T.expect(found)
		T.expectEqual(#i:releaseAll(), 0)
	end)
	T.it("UI 가 열려 있으면 스킬 Press 는 막히고, 이미 누른 키의 Release 는 정리된다", function()
		local i = InputState.new()
		i:press("Two", 0)
		i:setUiBlocking(true)
		T.expectEqual(#i:press("One", 0), 0)
		T.expectEqual(#i:release("Two"), 1)
	end)
	T.it("dashVelocity: 서버 확정 속도·시간 동안만, 허가 상한 이하로 제한, 비정상 값은 nil", function()
		local d = v(0, 0, -1)
		local vel = MovementModel.dashVelocity(10, d, 57, 0.28, 10.1)
		T.expectNear(vel.Z, -57, 1e-6)
		T.expect(MovementModel.dashVelocity(10, d, 57, 0.28, 10.3) == nil)
		T.expect(MovementModel.dashVelocity(10, d, 57, 0.28, 9.9) == nil)
		T.expectNear(MovementModel.dashVelocity(10, d, 9999, 0.28, 10.1).Z, -80, 1e-6) -- Permits 최대 속도
		T.expect(MovementModel.dashVelocity(10, d, -5, 0.28, 10.1) == nil)
		T.expect(MovementModel.dashVelocity(10, d, 0 / 0, 0.28, 10.1) == nil)
		T.expect(MovementModel.dashVelocity(10, v(0, 5, 0), 57, 0.28, 10.1) == nil) -- 수평 방향 없음
	end)
	T.it("acceptDashEvent: 내 이벤트·dash 포함·최근·중복 아님만", function()
		local e = { type = "SwordSkill", playerId = "me", dash = { speed = 1, duration = 1 }, time = 5 }
		T.expect(MovementModel.acceptDashEvent(e, "me", 5.2, nil, 1))
		T.expect(not MovementModel.acceptDashEvent(e, "other", 5.2, nil, 1))
		T.expect(not MovementModel.acceptDashEvent(e, "me", 7, nil, 1))
		T.expect(not MovementModel.acceptDashEvent(e, "me", 5.2, 5, 1))
		T.expect(not MovementModel.acceptDashEvent({ type = "SwordSkill", playerId = "me", time = 5 }, "me", 5.2, nil, 1))
	end)
	T.it("EffectsModel: 콤보 3타/스킬/궁극기/Duelist 연출 큐", function()
		local function cues(e) local out = {} for _, c in EffectsModel.translate(e, "me") do out[c.cue] = c end return out end
		T.expect(cues({ type = "Swing", playerId = "me", step = 3 })["sword.slash3"])
		T.expect(cues({ type = "Swing", playerId = "me", step = 1 })["sword.slash"])
		for step = 1, 3 do T.expect(cues({ type = "SwordSkill", skill = "TripleSlash", step = step, playerId = "x" })["skill.triple" .. step]) end
		T.expect(cues({ type = "SwordSkill", skill = "Lunge", phase = "Charge", playerId = "me" })["skill.lunge.charge"])
		local dash = cues({ type = "SwordSkill", skill = "Lunge", phase = "Dash", playerId = "me", direction = v(0, 0, 1), dash = { speed = 57, duration = 0.28 } })["skill.lunge.dash"]
		T.expect(dash and dash.mine and math.abs(dash.distance - 15.96) < 0.01)
		T.expect(cues({ type = "SwordSkill", skill = "BladeWave", playerId = "me" })["skill.bladewave"])
		T.expect(cues({ type = "SwordSkill", skill = "BladeStorm", phase = "Tick", playerId = "me" })["skill.storm.tick"])
		T.expect(cues({ type = "SwordSkill", skill = "BladeStorm", phase = "Finisher", playerId = "me" })["skill.storm.finish"])
		T.expect(cues({ type = "Duelist", playerId = "me", targetId = "t", bonus = 8 })["duelist.proc"])
		T.expectEqual(#EffectsModel.translate({ type = "SwordSkill", skill = "Unknown", playerId = "me" }, "me"), 0) -- 알 수 없는 스킬은 무시
	end)
	T.it("모든 SWORD 연출 큐가 EffectCatalog 에 정의되어 있다", function()
		local Catalog = Env.shared("Data/EffectCatalog")
		for _, name in { "sword.slash3", "skill.triple1", "skill.triple2", "skill.triple3", "skill.lunge.charge", "skill.lunge.dash", "skill.bladewave", "skill.storm.start", "skill.storm.tick", "skill.storm.finish", "duelist.proc" } do
			T.expect(Catalog.Cues[name] ~= nil, name)
		end
	end)
	T.it("FeedbackModel: 내 스킬 적중은 타격 표시, 내 Duelist 만 토스트, busy 거부 안내", function()
		local fx = FeedbackModel.translate({ type = "SwordSkill", skill = "BladeWave", playerId = "me", hits = { "a", "b" } }, "me")
		T.expectEqual(fx[1].kind, "HitMarker")
		T.expectEqual(#FeedbackModel.translate({ type = "SwordSkill", skill = "BladeWave", playerId = "other", hits = { "a" } }, "me"), 0)
		T.expectEqual(FeedbackModel.translate({ type = "Duelist", playerId = "me", bonus = 8 }, "me")[1].text, "Duelist +8")
		T.expectEqual(#FeedbackModel.translate({ type = "Duelist", playerId = "other", bonus = 8 }, "me"), 0)
		T.expect(FeedbackModel.translate({ type = "Rejected", remote = "Skill", reason = "busy" }, "me")[1].kind == "Toast")
		T.expectEqual(#FeedbackModel.translate({ type = "Rejected", remote = "Skill", reason = "on_cooldown" }, "me"), 0)
	end)
	T.it("HudModel: SWORD 스킬 이름·쿨타임·연계/충전 상태, 콤보, Duelist, 궁극기", function()
		local c, core, pos = setup({ a = "SWORD", b = "SWORD" })
		pos.b = v(0, 0, 4)
		local m0 = HudModel.build(c:getHudSnapshot("a", 0), 0)
		T.expectEqual(m0.skills[1].label, "Triple Slash 준비")
		T.expect(m0.skills[2].ready and m0.skills[3].ready)
		T.expectEqual(m0.combo.text, "콤보 1/3")
		T.expectEqual(m0.passive.text, "Duelist 준비")
		c:handleSkill("a", skill(1), 0)
		c:handleSkill("a", skill(3), 0)
		c:handleSkill("a", skill(2, "Press"), 0.5)
		local m1 = HudModel.build(c:getHudSnapshot("a", 0.7), 0.7)
		T.expectEqual(m1.skills[1].label, "Triple Slash 1/3")
		T.expect(string.find(m1.skills[3].label, "Blade Wave") and m1.skills[3].remaining > 5)
		T.expect(string.find(m1.skills[2].label, "충전") ~= nil)
		for _ = 1, 5 do core.ultimate:addKill("a") end
		local m2 = HudModel.build(c:getHudSnapshot("a", 0.7), 0.7)
		T.expect(m2.ultimate.ready and m2.ultimate.implemented and string.find(m2.ultimate.label, "Blade Storm") ~= nil)
		-- Duelist 발동 후 제한 표시
		local c2, core2, pos2 = setup({ a = "SWORD", b = "SWORD" })
		pos2.b = v(0, 0, 4)
		local t = 0
		for _ = 1, 3 do c2:handleAttack("a", prim(), t); t += 0.7 end
		local m3 = HudModel.build(c2:getHudSnapshot("a", t), t)
		T.expect(m3.passive.lockRemaining > 0 and not m3.passive.ready)
	end)
	T.it("구현 모듈이 없는 캐릭터(GUNNER)는 스킬/궁극기 미구현 표시", function()
		local c = setup({ p = "GUNNER" })
		local m = HudModel.build(c:getHudSnapshot("p", 0), 0)
		for i = 1, 3 do T.expect(not m.skills[i].implemented and m.skills[i].label == "미구현") end
		T.expect(m.ultimate.implemented == false)
		T.expect(m.combo == nil and m.passive == nil)
	end)
end)
return true
