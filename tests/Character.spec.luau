--!nonstrict
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local H = require(script.Parent.Helpers)
local Core = Env.server("CombatCore")
local ProjectileService = Env.server("ProjectileService")
local Controller = Env.server("CharacterController")
local Router = Env.server("ServerRouter")
local Gate = Env.server("RemoteGate")
local Characters = Env.shared("Data/Characters")
local Config = Env.shared("Config")

local v = H.v
local fwd = v(0, 0, 1)

-- chars: { id = "SWORD" | "PAINTBALL" }
local function setup(chars, planes, opts)
	local core = Core.new()
	local pos, face = {}, {}
	local world = H.fakeWorld(planes or {})
	local function targets()
		local list = {}
		for id in chars do
			table.insert(list, { id = id, pos = pos[id], radius = Config.Combat.HitRadius, alive = core.damage:isAlive(id) })
		end
		return list
	end
	local ps = ProjectileService.new({ damage = core.damage, targets = targets, world = world })
	local controller = Controller.new({
		core = core,
		projectiles = ps,
		getPose = function(id)
			return { pos = pos[id], forward = face[id], airborne = pos[id].Y > 5 }
		end,
		targets = targets,
		world = world,
		allowMockUltimate = opts and opts.allowMockUltimate or false,
	})
	for id, ch in chars do
		controller:addPlayer(id, ch)
		pos[id] = v(0, 0, 0)
		face[id] = fwd
	end
	return controller, core, ps, pos, face
end

local function atk(action, dir)
	return { action = action or "Primary", aimDirection = dir or fwd }
end

local function run(controller, from, to, dt)
	local t = from
	while t < to - 1e-9 do
		t = math.min(t + (dt or 0.05), to)
		controller:update(t, dt or 0.05)
	end
end

T.describe("CharacterController: SWORD", function()
	T.it("전방 부채꼴 대상만 피해, 뒤쪽·사거리 밖 제외 (공격 거리 검증)", function()
		local c, core, _, pos = setup({ p1 = "SWORD", p2 = "SWORD", p3 = "SWORD", p4 = "SWORD" })
		pos.p2, pos.p3, pos.p4 = v(0, 0, 4), v(0, 0, -4), v(0, 0, 30)
		local ok, info = c:handleAttack("p1", atk(), 0)
		T.expect(ok)
		T.expectEqual(#info.hits, 1)
		T.expectEqual(core.damage:getHealth("p2"), 86)
		T.expectEqual(core.damage:getHealth("p3"), 100)
		T.expectEqual(core.damage:getHealth("p4"), 100)
	end)
	T.it("쿨타임 0.55초: 도중 재공격 거부, 이후 허용", function()
		local c, core, _, pos = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 4)
		T.expect((c:handleAttack("p1", atk(), 0)))
		local ok, why = c:handleAttack("p1", atk(), 0.3)
		T.expect(not ok and why == "on_cooldown")
		T.expect((c:handleAttack("p1", atk(), 0.55)))
		T.expectEqual(core.damage:getHealth("p2"), 72)
	end)
	T.it("기본 공격은 경직 없음, 피격자는 계속 행동 가능", function()
		local c, core, _, pos = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 4)
		c:handleAttack("p1", atk(), 0)
		T.expect(core.status:canAct("p2", 0.01))
	end)
	T.it("벽 뒤 대상은 근접 공격 불가", function()
		local c, core, _, pos = setup({ p1 = "SWORD", p2 = "SWORD" }, { { point = v(0, 0, 2), normal = v(0, 0, -1) } })
		pos.p2 = v(0, 0, 4)
		c:handleAttack("p1", atk(), 0)
		T.expectEqual(core.damage:getHealth("p2"), 100)
	end)
	T.it("여러 대상 동시 적중, 사망자 제외", function()
		local c, core, _, pos = setup({ p1 = "SWORD", p2 = "SWORD", p3 = "SWORD", p4 = "SWORD" })
		pos.p2, pos.p3, pos.p4 = v(1, 0, 4), v(-1, 0, 4), v(0, 0, 5)
		core.damage:applyDamage({ attackerId = "p1", targetId = "p4", attackId = "x", amount = 999 }, 0)
		local _, info = c:handleAttack("p1", atk(), 1)
		T.expectEqual(#info.hits, 2)
		T.expectEqual(core.damage:getHealth("p4"), 0)
	end)
	T.it("패들볼 캐릭터는 보조 공격 없음", function()
		local c = setup({ p1 = "PAINTBALL" })
		local ok, why = c:handleAttack("p1", atk("Secondary"), 0)
		T.expect(not ok and why == "no_secondary")
	end)
end)

T.describe("CharacterController: PAINTBALL (자동 연사·탄약·재장전)", function()
	T.it("연사 간격 0.12초 제한, 탄약 소모", function()
		local c = setup({ p1 = "PAINTBALL" })
		T.expect((c:handleAttack("p1", atk(), 0)))
		local ok, why = c:handleAttack("p1", atk(), 0.05)
		T.expect(not ok and why == "on_cooldown")
		T.expect((c:handleAttack("p1", atk(), 0.12)))
		T.expectEqual(c:getAmmo("p1"), 28)
	end)
	T.it("탄약 0이면 자동 재장전 시작, 장전 중 발사 불가, 1.8초 후 가득", function()
		local c = setup({ p1 = "PAINTBALL" })
		for i = 0, 29 do
			T.expect((c:handleAttack("p1", atk(), i * 0.12)), "shot " .. i)
		end
		T.expectEqual(c:getAmmo("p1"), 0)
		local t = 29 * 0.12 + 0.2
		local ok, why = c:handleAttack("p1", atk(), t)
		T.expect(not ok and why == "reloading")
		run(c, t, t + 1.5)
		T.expect(c:isReloading("p1", t + 1.5))
		run(c, t + 1.5, 29 * 0.12 + 1.9)
		T.expectEqual(c:getAmmo("p1"), 30)
		T.expect((c:handleAttack("p1", atk(), 29 * 0.12 + 2)))
	end)
	T.it("수동 재장전: 가득이면 거부, 일부 소모 시 허용", function()
		local c = setup({ p1 = "PAINTBALL" })
		local ok, why = c:handleReload("p1", 0)
		T.expect(not ok and why == "full")
		c:handleAttack("p1", atk(), 0)
		T.expect((c:handleReload("p1", 1)))
		local ok2, why2 = c:handleReload("p1", 1.2)
		T.expect(not ok2 and why2 == "already_reloading")
	end)
	T.it("SWORD는 재장전 불가", function()
		local c = setup({ p1 = "SWORD" })
		local ok, why = c:handleReload("p1", 0)
		T.expect(not ok and why == "no_reload")
	end)
	T.it("투사체가 날아가 명중, 서버가 피해(4) 계산", function()
		local c, core, _, pos = setup({ p1 = "PAINTBALL", p2 = "SWORD" })
		pos.p2 = v(0, 0, 40)
		c:handleAttack("p1", atk(), 0)
		T.expectEqual(core.damage:getHealth("p2"), 100)
		run(c, 0, 0.5)
		T.expectEqual(core.damage:getHealth("p2"), 96)
	end)
	T.it("원거리 자동 조준 보정 없음: 15도 빗나간 조준은 명중하지 않음", function()
		local c, core, _, pos = setup({ p1 = "PAINTBALL", p2 = "SWORD" })
		pos.p2 = v(0, 0, 40)
		local a = math.rad(15)
		c:handleAttack("p1", atk("Primary", v(math.sin(a), 0, math.cos(a))), 0)
		run(c, 0, 1)
		T.expectEqual(core.damage:getHealth("p2"), 100)
	end)
	T.it("발사 후 사망해도 이미 발사한 투사체는 유지되어 명중, 장전은 취소", function()
		local c, core, ps, pos = setup({ p1 = "PAINTBALL", p2 = "SWORD" })
		pos.p2 = v(0, 0, 60)
		c:handleAttack("p1", atk(), 0)
		core.damage:applyDamage({ attackerId = "p2", targetId = "p1", attackId = "k", amount = 999 }, 0.05)
		T.expect(not c:isReloading("p1", 0.06))
		run(c, 0.05, 1)
		T.expectEqual(core.damage:getHealth("p2"), 96)
		local ok, why = c:handleAttack("p1", atk(), 1)
		T.expect(not ok and why == "dead")
	end)
end)

T.describe("CharacterController: 이동·회피·궁극기·캐릭터 변경", function()
	T.it("이동 속도: 걷기 17 / 달리기 23 / 둔화·공격 보정", function()
		local c, core = setup({ p1 = "SWORD", p2 = "SWORD" })
		T.expectEqual(c:getMoveSpeed("p1", 0), 17)
		c:handleSetRun("p1", true)
		T.expectEqual(c:getMoveSpeed("p1", 0), 23)
		core.status:apply("p1", { type = "Slow", multiplier = 0.5, duration = 5 }, 0)
		T.expectEqual(c:getMoveSpeed("p1", 1), 11.5)
		c:handleSetRun("p1", false)
		c:handleAttack("p1", atk(), 10) -- 공격 중 이동 가능, SWORD 0.85 보정 (둔화 만료 후)
		T.expect(math.abs(c:getMoveSpeed("p1", 10.1) - 17 * 0.85) < 1e-9)
		T.expectEqual(c:getMoveSpeed("p1", 11), 17)
	end)
	T.it("회피 2회, 3회째 거부, 회피 중 무적으로 피해 무효, 공중 회피 허용", function()
		local c, core, _, pos = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 4)
		T.expect((c:handleDodge("p1", { direction = fwd }, 0)))
		T.expect(not core.damage:applyDamage({ attackerId = "p2", targetId = "p1", attackId = "a", amount = 5 }, 0.1).applied)
		T.expect(core.damage:applyDamage({ attackerId = "p2", targetId = "p1", attackId = "b", amount = 5 }, 0.2).applied)
		pos.p1 = v(0, 10, 0) -- 공중
		T.expect((c:handleDodge("p1", { direction = fwd }, 1)))
		local ok, why = c:handleDodge("p1", { direction = fwd }, 2)
		T.expect(not ok and why == "no_charges")
	end)
	T.it("사망 후에는 회피·공격·재장전 불가", function()
		local c, core = setup({ p1 = "PAINTBALL", p2 = "SWORD" })
		core.damage:applyDamage({ attackerId = "p2", targetId = "p1", attackId = "k", amount = 999 }, 0)
		T.expect(select(2, c:handleDodge("p1", { direction = fwd }, 1)) == "dead")
		T.expect(select(2, c:handleAttack("p1", atk(), 1)) == "dead")
		T.expect(select(2, c:handleReload("p1", 1)) == "dead")
		T.expectEqual(c:getMoveSpeed("p1", 1), 0)
	end)
	T.it("궁극기: 게이지 부족 거부, 가득이면 발동·100% 소모", function()
		local c, core = setup({ p1 = "SWORD" }, nil, { allowMockUltimate = true })
		T.expect(select(2, c:handleUltimate("p1", {}, 0)) == "not_ready")
		for _ = 1, 5 do core.ultimate:addKill("p1") end
		T.expect((c:handleUltimate("p1", {}, 0)))
		T.expectEqual(core.ultimate:getGauge("p1"), 0)
		T.expect(select(2, c:handleUltimate("p1", {}, 1)) == "busy") -- SWORD: Blade Storm 진행 중 재발동 거부(게이지 소모 전)
		-- 모의 궁극기(PAINTBALL)는 이미 발동 중이면 already_active
		local c2, core2 = setup({ p1 = "PAINTBALL" }, nil, { allowMockUltimate = true })
		for _ = 1, 5 do core2.ultimate:addKill("p1") end
		T.expect((c2:handleUltimate("p1", {}, 0)))
		T.expect(select(2, c2:handleUltimate("p1", {}, 1)) == "already_active")
	end)
	T.it("캐릭터 변경은 다음 리스폰부터, 게이지 min(기존, 40) 이월, 같은 캐릭터면 유지", function()
		local c, core = setup({ p1 = "SWORD", p2 = "SWORD" })
		for _ = 1, 4 do core.ultimate:addKill("p1") end -- 80
		T.expectEqual(c:selectCharacter("p1", "PAINTBALL"), "pending")
		T.expectEqual(c:getCharacterId("p1"), "SWORD")
		core.damage:applyDamage({ attackerId = "p2", targetId = "p1", attackId = "k", amount = 999 }, 1)
		T.expectEqual(core.ultimate:getGauge("p1"), 80) -- 사망해도 유지
		c:respawn("p1", 5)
		T.expectEqual(c:getCharacterId("p1"), "PAINTBALL")
		T.expectEqual(c:getAmmo("p1"), 30)
		T.expectEqual(core.ultimate:getGauge("p1"), 40)
		-- 같은 캐릭터로 부활: 유지
		core.ultimate:addKill("p1")
		core.damage:applyDamage({ attackerId = "p2", targetId = "p1", attackId = "k2", amount = 999 }, 6)
		c:respawn("p1", 10)
		T.expectEqual(core.ultimate:getGauge("p1"), 60)
	end)
	T.it("환경 사망(낙사)도 동일 경로로 처리, 궁극기 충전 없음", function()
		local c, core = setup({ p1 = "SWORD" })
		T.expect(core.damage:forceKill("p1", 1))
		T.expect(not core.damage:isAlive("p1"))
		T.expectEqual(core.ultimate:getGauge("p1"), 0)
		T.expect(not core.damage:forceKill("p1", 2))
		T.expect(select(2, c:handleAttack("p1", atk(), 3)) == "dead")
	end)
	T.it("12인 동시 근접 공격: 피해자 p1의 처치는 정확히 1회, 체력 0 고정", function()
		local chars = {}
		for i = 1, 12 do chars["p" .. i] = "SWORD" end
		local c, core, _, pos, face = setup(chars)
		pos.p1 = v(0, 0, 0)
		local kills = 0
		core.damage:onKilled(function(e)
			if e.targetId == "p1" then kills += 1 end
		end)
		for i = 2, 12 do
			local a = math.rad(i * 30)
			pos["p" .. i] = v(math.cos(a) * 4, 0, math.sin(a) * 4)
			face["p" .. i] = v(-math.cos(a), 0, -math.sin(a))
		end
		local applied = 0
		for i = 2, 12 do
			local ok, info = c:handleAttack("p" .. i, atk("Primary", face["p" .. i]), 5)
			if ok then
				for _, id in info.hits do
					if id == "p1" then applied += 1 end
				end
			end
		end
		T.expect(applied >= 7, "applied=" .. applied) -- 100/14 ≈ 7.14 → 8번째 일격에 사망
		T.expectEqual(kills, 1)
		T.expectEqual(core.damage:getHealth("p1"), 0)
	end)
end)

T.describe("ServerRouter: 비정상 RemoteEvent 요청 거부", function()
	local function routerSetup(chars)
		local c, core, ps, pos, face = setup(chars)
		local clock = { t = 100 }
		local gate = Gate.new({
			cooldown = core.cooldown,
			getState = function(id)
				if not pos[id] then return nil end
				return { alive = core.damage:isAlive(id), pos = pos[id], serverTime = clock.t, character = Characters[c:getCharacterId(id)] }
			end,
		})
		return Router.new({ gate = gate, controller = c }), c, core, pos, clock
	end
	local function attack(extra, clock)
		local p = { action = "Primary", aimOrigin = v(0, 1, 0), aimDirection = fwd, clientTime = clock.t }
		for k, val in extra or {} do p[k] = val end
		return p
	end

	T.it("정상 요청은 컨트롤러까지 도달해 피해 적용", function()
		local r, c, core, pos, clock = routerSetup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 4)
		local ok = r:dispatch("p1", "Attack", attack(nil, clock), clock.t)
		T.expect(ok)
		T.expectEqual(core.damage:getHealth("p2"), 86)
	end)
	T.it("클라이언트가 보낸 피해량/명중 대상은 무시되지 않고 요청 자체를 거부", function()
		local r, c, core, pos, clock = routerSetup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 4)
		local ok, why = r:dispatch("p1", "Attack", attack({ damage = 9999, targets = { "p2" } }, clock), clock.t)
		T.expect(not ok and string.find(why, "invalid_payload", 1, true) ~= nil)
		T.expectEqual(core.damage:getHealth("p2"), 100)
	end)
	T.it("쓰레기·NaN·비단위벡터·알 수 없는 리모트·잘못된 캐릭터 거부, 상태 불변", function()
		local r, c, core, pos, clock = routerSetup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 4)
		local bad = {
			{ "Attack", "hack" },
			{ "Attack", nil },
			{ "Attack", attack({ aimDirection = v(0 / 0, 0, 1) }, clock) },
			{ "Attack", attack({ aimDirection = v(0, 0, 40) }, clock) },
			{ "Attack", attack({ action = "Ultimate" }, clock) },
			{ "Dodge", { direction = "up" } },
			{ "GiveAdmin", {} },
			{ "SelectCharacter", { characterId = "ADMIN" } },
			{ "SetRun", { enabled = 1 } },
		}
		for i, b in bad do
			local ok = r:dispatch("p1", b[1], b[2], clock.t)
			T.expect(not ok, "통과해버림 #" .. i)
		end
		T.expectEqual(core.damage:getHealth("p2"), 100)
		T.expectEqual(c:getCharacterId("p1"), "SWORD")
	end)
	T.it("시각 위조·조준 원점 위조·사망 상태·재장전 불가 캐릭터 거부", function()
		local r, c, core, pos, clock = routerSetup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 4)
		T.expect(select(2, r:dispatch("p1", "Attack", attack({ clientTime = 9999 }, clock), clock.t)) == "time_skew")
		T.expect(select(2, r:dispatch("p1", "Attack", attack({ aimOrigin = v(100, 0, 0) }, clock), clock.t)) == "origin_mismatch")
		T.expect(select(2, r:dispatch("p1", "Reload", {}, clock.t)) == "no_reload")
		core.damage:applyDamage({ attackerId = "p2", targetId = "p1", attackId = "k", amount = 999 }, 1)
		T.expect(select(2, r:dispatch("p1", "Attack", attack(nil, clock), clock.t)) == "dead")
	end)
	T.it("요청 폭주(초당 30회 초과)는 거부되어 서버 상태 영향 제한", function()
		local r, c, core, pos, clock = routerSetup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 4)
		local rejected = 0
		for i = 1, 200 do
			local ok, why = r:dispatch("p1", "Attack", attack(nil, clock), clock.t + i * 0.001)
			if not ok and why == "rate_limited" then rejected += 1 end
		end
		T.expect(rejected >= 150, "rejected=" .. rejected)
		T.expect(core.damage:getHealth("p2") >= 100 - 14 * 1) -- 쿨타임 0.55초 → 0.2초 안에 1회만 적용
	end)
	T.it("SelectCharacter는 다음 리스폰까지 대기", function()
		local r, c, core, pos, clock = routerSetup({ p1 = "SWORD" })
		local ok, info = r:dispatch("p1", "SelectCharacter", { characterId = "PAINTBALL" }, clock.t)
		T.expect(ok and info == "pending")
		T.expectEqual(c:getCharacterId("p1"), "SWORD")
	end)
end)
return true
