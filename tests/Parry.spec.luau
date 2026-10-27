--!nonstrict
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local H = require(script.Parent.Helpers)
local Core = Env.server("CombatCore")
local ProjectileService = Env.server("ProjectileService")
local Controller = Env.server("CharacterController")
local Templates = Env.shared("Data/ProjectileTemplates")
local Config = Env.shared("Config")

local v = H.v
local fwd = v(0, 0, 1)

local function setup(chars, opts)
	local core = Core.new()
	local pos, face = {}, {}
	local world = H.fakeWorld({})
	local function targets()
		local list = {}
		for id in chars do
			table.insert(list, { id = id, pos = pos[id], radius = Config.Combat.HitRadius, alive = core.damage:isAlive(id) })
		end
		return list
	end
	local ps = ProjectileService.new({ damage = core.damage, targets = targets, world = world })
	local c = Controller.new({ characters = H.legacyChars(Env.shared("Data/Characters")),
		core = core, projectiles = ps, targets = targets, world = world,
		getPose = function(id)
			return { pos = pos[id], forward = face[id], airborne = pos[id].Y > 5 }
		end,
		allowMockUltimate = opts and opts.allowMockUltimate or false,
	})
	for id, ch in chars do
		c:addPlayer(id, ch)
		pos[id] = v(0, 0, 0)
		face[id] = fwd
	end
	local events = {}
	c:onFeedback(function(e) table.insert(events, e) end)
	return c, core, ps, pos, face, events
end

local function atk(action, dir)
	return { action = action or "Primary", aimDirection = dir or fwd }
end

local function swing(core, attacker, target, id, now, sourcePos)
	return core.damage:applyDamage({
		attackerId = attacker, targetId = target, attackId = id, amount = 14, kind = "Melee",
		blockable = true, sourcePos = sourcePos,
	}, now)
end

local function parried(events)
	local n = 0
	for _, e in events do
		if e.type == "ParrySuccess" then n += 1 end
	end
	return n
end

T.describe("패링 확정 사양: 전방 180° / 0.4초 / 반격 18 / 쿨타임 10초", function()
	T.it("RMB 패링은 0.4초 창, 쿨타임 10초", function()
		local c, core, _, _, _, ev = setup({ p1 = "SWORD" })
		local ok, info = c:handleAttack("p1", atk("Secondary"), 0)
		T.expect(ok)
		T.expect(math.abs(info.parryUntil - 0.4) < 1e-9)
		T.expect(select(2, c:handleAttack("p1", atk("Secondary"), 9.9)) == "on_cooldown")
		T.expect((c:handleAttack("p1", atk("Secondary"), 10)))
	end)
	T.it("전방 근접 공격 차단 + 자동 반격 18 (실제 근접 공격 경로)", function()
		local c, core, _, pos, face, ev = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 4)
		face.p2 = v(0, 0, -1)
		c:handleAttack("p1", atk("Secondary"), 0)
		T.expect((c:handleAttack("p2", atk("Primary", v(0, 0, -1)), 0.1)))
		T.expectEqual(H.hp(core, "p1"), 100)
		T.expectEqual(H.hp(core, "p2"), 82)
		T.expectEqual(parried(ev), 1)
	end)
	T.it("후방 공격은 차단하지 않고 반격도 없음", function()
		local c, core, _, pos, face = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, -4)
		face.p2 = fwd
		c:handleAttack("p1", atk("Secondary"), 0)
		T.expect((c:handleAttack("p2", atk("Primary", fwd), 0.1)))
		T.expectEqual(H.hp(core, "p1"), 86)
		T.expectEqual(H.hp(core, "p2"), 100)
	end)
	T.it("180° 경계: 정확히 옆(90°)은 차단, 옆-뒤(약 104°)는 차단 안 함", function()
		local c, core = setup({ p1 = "SWORD", p2 = "SWORD" })
		c:handleAttack("p1", atk("Secondary"), 0)
		T.expect(not swing(core, "p2", "p1", "a", 0.1, v(4, 0, 0)).applied) -- 90°
		T.expect(swing(core, "p2", "p1", "b", 0.1, v(4, 0, -1)).applied) -- 약 104°
	end)
	T.it("창 경계: 0.39초는 차단, 0.4초 이후는 피해", function()
		local c, core = setup({ p1 = "SWORD", p2 = "SWORD" })
		c:handleAttack("p1", atk("Secondary"), 0)
		T.expect(not swing(core, "p2", "p1", "a", 0.39, v(0, 0, 4)).applied)
		T.expect(swing(core, "p2", "p1", "b", 0.4, v(0, 0, 4)).applied)
	end)
	T.it("중복 반격 방지: 같은 패링에서 같은 공격자는 한 번만 반격, 다른 공격자는 각각 한 번", function()
		local c, core, _, pos = setup({ p1 = "SWORD", p2 = "SWORD", p3 = "SWORD" })
		pos.p2, pos.p3 = v(0, 0, 3), v(2, 0, 3)
		c:handleAttack("p1", atk("Secondary"), 0)
		swing(core, "p2", "p1", "a1", 0.1, pos.p2)
		swing(core, "p2", "p1", "a2", 0.2, pos.p2)
		swing(core, "p2", "p1", "a3", 0.3, pos.p2)
		swing(core, "p3", "p1", "b1", 0.3, pos.p3)
		T.expectEqual(H.hp(core, "p2"), 82) -- 18 한 번만
		T.expectEqual(H.hp(core, "p3"), 82)
		T.expectEqual(H.hp(core, "p1"), 100)
	end)
	T.it("새 패링(10초 후)에서는 같은 공격자에게 다시 반격 가능", function()
		local c, core, _, pos = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 3)
		c:handleAttack("p1", atk("Secondary"), 0)
		swing(core, "p2", "p1", "a1", 0.1, pos.p2)
		c:handleAttack("p1", atk("Secondary"), 10)
		swing(core, "p2", "p1", "a2", 10.1, pos.p2)
		T.expectEqual(H.hp(core, "p2"), 64)
	end)
	T.it("반격은 방어 불가·재반격 없음: 서로 패링 중이어도 무한 반격 없이 1회씩", function()
		local c, core, _, pos, face, ev = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 4)
		face.p2 = v(0, 0, -1)
		c:handleAttack("p1", atk("Secondary"), 0)
		c:handleAttack("p2", atk("Secondary"), 0)
		swing(core, "p2", "p1", "x", 0.1, pos.p2) -- p1이 막고 p2에게 반격
		T.expectEqual(H.hp(core, "p2"), 82)
		T.expectEqual(H.hp(core, "p1"), 100)
		T.expectEqual(parried(ev), 1)
	end)
	T.it("유효 사거리 밖 공격자에게는 반격하지 않음", function()
		local c, core, _, pos, _, ev = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 40)
		c:handleAttack("p1", atk("Secondary"), 0)
		local r = swing(core, "p2", "p1", "a", 0.1, pos.p2)
		T.expect(not r.applied and r.reason == "parried")
		T.expectEqual(H.hp(core, "p2"), 100)
		for _, e in ev do
			if e.type == "ParrySuccess" then T.expect(e.countered == false) end
		end
	end)
	T.it("사망한 공격자에게는 반격하지 않음", function()
		local c, core, _, pos = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 3)
		c:handleAttack("p1", atk("Secondary"), 0)
		core.damage:forceKill("p2", 0.05)
		T.expect(not swing(core, "p2", "p1", "a", 0.1, pos.p2).applied)
		T.expectEqual(H.hp(core, "p2"), 0)
	end)
	T.it("환경 피해·일반 광역 폭발은 차단하지 않음", function()
		local c, core, ps, pos = setup({ p1 = "SWORD", p2 = "GUNNER" })
		c:handleAttack("p1", atk("Secondary"), 0)
		T.expect(core.damage:applyDamage({ attackerId = "p2", targetId = "p1", attackId = "env", amount = 5, kind = "Environment" }, 0.1).applied)
		pos.p1 = v(0, 0, 0)
		pos.p2 = v(40, 0, 0)
		ps:spawn({ def = Templates.Explosion, ownerId = "p2", origin = v(0, 1, 3), direction = v(0, 0, 0) }, 0.2)
		T.expect(H.hp(core, "p1") < 95)
	end)
	T.it("방어 가능한 투사체(원거리): 전방에서 오면 차단·소멸, 멀리 있는 공격자에게 원격 반격 없음", function()
		local c, core, ps, pos, face, ev = setup({ p1 = "SWORD", p2 = "GUNNER" })
		pos.p2 = v(0, 0, 40)
		face.p2 = v(0, 0, -1)
		c:handleAttack("p1", atk("Secondary"), 0)
		c:handleAttack("p2", atk("Primary", v(0, 0, -1)), 0)
		for t = 1, 20 do c:update(t * 0.05, 0.05) end
		T.expectEqual(H.hp(core, "p1"), 100)
		T.expectEqual(H.hp(core, "p2"), 100)
		T.expectEqual(ps:getActiveCount(), 0)
	end)
	T.it("근거리에서 쏜 방어 가능 투사체는 차단 + 자동 반격", function()
		local c, core, ps, pos, face = setup({ p1 = "SWORD", p2 = "GUNNER" })
		pos.p2 = v(0, 0, 6)
		face.p2 = v(0, 0, -1)
		c:handleAttack("p1", atk("Secondary"), 0)
		c:handleAttack("p2", atk("Primary", v(0, 0, -1)), 0)
		for t = 1, 6 do c:update(t * 0.05, 0.05) end
		T.expectEqual(H.hp(core, "p1"), 100)
		T.expectEqual(H.hp(core, "p2"), 82)
	end)
	T.it("후방에서 온 투사체는 차단되지 않음", function()
		local c, core, _, pos, face = setup({ p1 = "SWORD", p2 = "GUNNER" })
		pos.p2 = v(0, 0, -40)
		face.p2 = fwd
		c:handleAttack("p1", atk("Secondary"), 0)
		c:handleAttack("p2", atk("Primary", fwd), 0)
		for t = 1, 20 do c:update(t * 0.05, 0.05) end
		T.expectEqual(H.hp(core, "p1"), 96)
	end)
	T.it("blockable=false 로 정의된 투사체는 차단되지 않음", function()
		local c, core, ps, pos = setup({ p1 = "SWORD", p2 = "GUNNER" })
		pos.p2 = v(0, 0, 30)
		local def = H.clone(Templates.Linear)
		def.blockable = false
		c:handleAttack("p1", atk("Secondary"), 0)
		ps:spawn({ def = def, ownerId = "p2", origin = v(0, 1.5, 30), direction = v(0, 0, -1) }, 0)
		for t = 1, 20 do ps:step(t * 0.02) end
		T.expectEqual(H.hp(core, "p1"), 90)
	end)
	T.it("차단된 공격의 상태이상(넉백 등)은 적용되지 않음", function()
		local c, core, _, pos, face = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 4)
		face.p2 = v(0, 0, -1)
		c:handleAttack("p1", atk("Secondary"), 0)
		local r = core.damage:applyDamage({
			attackerId = "p2", targetId = "p1", attackId = "z", amount = 14, kind = "Melee", blockable = true, sourcePos = pos.p2,
			effects = { { type = "Slow", multiplier = 0.5, duration = 3 } },
		}, 0.1)
		T.expect(not r.applied)
		T.expectEqual(core.status:getSpeedMultiplier("p1", 0.2), 1) -- 차단된 공격의 슬로우는 걸리지 않음
	end)
	T.it("패링 방향·성공은 서버 자세로 판정: 클라이언트가 보낸 조준 방향은 영향 없음", function()
		local c, core, _, pos, face = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, -4) -- 서버 기준 p1의 뒤쪽
		face.p2 = fwd
		c:handleAttack("p1", { action = "Secondary", aimDirection = v(0, 0, -1) }, 0) -- 클라이언트가 뒤를 보고 있다고 주장
		c:handleAttack("p2", atk("Primary", fwd), 0.1)
		T.expectEqual(H.hp(core, "p1"), 86) -- 서버 forward(+z) 기준 후방이므로 피해
	end)
end)

T.describe("궁극기 자리표시자: 실플레이에서는 게이지 소모 금지", function()
	local function full(core, id)
		for _ = 1, 5 do core.ultimate:addKill(id) end
	end
	T.it("개발용 모의 허용 설정은 기본 false", function()
		T.expect(Config.Ultimate_Dev.AllowMockUltimate == false)
	end)
	T.it("미구현 궁극기(PAINTBALL)는 F를 눌러도 거부되고 게이지가 유지됨", function()
		local c, core = setup({ p1 = "GUNNER" })
		full(core, "p1")
		local ok, why = c:handleUltimate("p1", {}, 0)
		T.expect(not ok and why == "ultimate_not_implemented")
		T.expectEqual(core.ultimate:getGauge("p1"), 100)
		T.expect(not core.ultimate:isActive("p1"))
		T.expect(select(2, c:handleUltimate("p1", {}, 1)) == "ultimate_not_implemented")
		T.expectEqual(core.ultimate:getGauge("p1"), 100)
	end)
	T.it("PAINTBALL도 동일", function()
		local c, core = setup({ p1 = "GUNNER" })
		full(core, "p1")
		T.expect(select(2, c:handleUltimate("p1", {}, 0)) == "ultimate_not_implemented")
		T.expectEqual(core.ultimate:getGauge("p1"), 100)
	end)
	T.it("테스트 전용 모의 실행 옵션을 켠 경우에만 실행·소모(미구현 PAINTBALL)", function()
		local c, core = setup({ p1 = "GUNNER" }, { allowMockUltimate = true })
		full(core, "p1")
		T.expect((c:handleUltimate("p1", {}, 0)))
		T.expectEqual(core.ultimate:getGauge("p1"), 0)
	end)
	T.it("HUD 스냅샷이 미구현 상태를 알려줌(PAINTBALL), SWORD 는 구현됨, 게이지 충전은 그대로 동작", function()
		local c, core = setup({ p1 = "GUNNER", p2 = "SWORD" })
		core.ultimate:addKill("p1")
		core.ultimate:addKill("p2")
		local snap = c:getHudSnapshot("p1", 0)
		T.expectEqual(snap.ultimate.gauge, 20)
		T.expect(snap.ultimate.implemented == false)
		local snap2 = c:getHudSnapshot("p2", 0)
		T.expectEqual(snap2.ultimate.gauge, 20)
		T.expect(snap2.ultimate.implemented == true)
	end)
end)

T.describe("3단계 서버 지원: 달리기 해제·공중 공격·스킬 미구현·스냅샷", function()
	T.it("공격 시 달리기 해제 (근접·원거리·패링)", function()
		local c = setup({ p1 = "SWORD", p2 = "GUNNER" })
		c:handleSetRun("p1", true)
		T.expectEqual(c:getMoveSpeed("p1", 0), 23)
		c:handleAttack("p1", atk(), 0)
		T.expect(c:getHudSnapshot("p1", 0.1).running == false)
		c:handleSetRun("p2", true)
		c:handleAttack("p2", atk(), 0)
		T.expect(c:getHudSnapshot("p2", 0.1).running == false)
		c:handleSetRun("p1", true)
		c:handleAttack("p1", atk("Secondary"), 1)
		T.expect(c:getHudSnapshot("p1", 1.1).running == false)
	end)
	T.it("실패한 공격(쿨타임)은 달리기를 해제하지 않음", function()
		local c = setup({ p1 = "SWORD" })
		c:handleAttack("p1", atk(), 0)
		c:handleSetRun("p1", true)
		T.expect(not (c:handleAttack("p1", atk(), 0.1)))
		T.expect(c:getHudSnapshot("p1", 0.1).running == true)
	end)
	T.it("공중에서도 공격 가능 (공중 공격 허용)", function()
		local c, core, _, pos = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p1 = v(0, 10, 0)
		pos.p2 = v(0, 10, 4)
		T.expect((c:handleAttack("p1", atk(), 0)))
		T.expectEqual(H.hp(core, "p2"), 86)
	end)
	T.it("미구현 캐릭터(PAINTBALL)의 숫자 스킬은 거부되며 쿨타임·상태를 소모하지 않음", function()
		local c, core = setup({ p1 = "GUNNER" })
		for slot = 1, 3 do
			T.expect(select(2, c:handleSkill("p1", { slot = slot }, 0)) == "skill_not_implemented")
			T.expect(core.cooldown:isReady("p1", "skill" .. slot, 0))
		end
		T.expect(core.cooldown:isReady("p1", "primary", 0))
		T.expectEqual(c:getMoveSpeed("p1", 0), 17)
	end)
	T.it("HUD 스냅샷: SWORD는 탄약 없음, PAINTBALL은 탄약·쿨타임·회피 정보", function()
		local c, core = setup({ p1 = "SWORD", p2 = "GUNNER" })
		local s1 = c:getHudSnapshot("p1", 0)
		T.expect(s1.ammo == nil and s1.hasSecondary)
		T.expectEqual(s1.dodge.charges, 2)
		c:handleAttack("p1", atk("Secondary"), 0)
		T.expectEqual(c:getHudSnapshot("p1", 1).cooldowns.secondary.readyAt, 10)
		c:handleAttack("p2", atk(), 0)
		local s2 = c:getHudSnapshot("p2", 0.01)
		T.expectEqual(s2.ammo.cur, 29)
		T.expect(not s2.hasSecondary)
		c:handleDodge("p1", { direction = fwd }, 2)
		local s3 = c:getHudSnapshot("p1", 2.1)
		T.expectEqual(s3.dodge.charges, 1)
		T.expectEqual(s3.dodge.nextChargeAt, 7)
	end)
end)
return true
