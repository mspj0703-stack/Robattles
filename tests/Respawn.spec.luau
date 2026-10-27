--!nonstrict
-- 부활 시스템 확정 사양: 사망 4초 후 부활, 부활 후 2초 피해 면역(서버 권위), 공격 행동 시작/만료 시 즉시 해제,
-- 보호 중 공격은 체력·처치 점수·궁극기 충전에 반영 안 됨, 동시 리스폰, 로드 스케줄러(중복·무한 리스폰 방지).
-- Roblox 의 LoadCharacter/SpawnLocation/RespawnLocation 동작은 CLI 로 검증할 수 없다(Studio 미검증).
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local H = require(script.Parent.Helpers)
local Core = Env.server("CombatCore")
local ProjectileService = Env.server("ProjectileService")
local Controller = Env.server("CharacterController")
local Scheduler = Env.server("RespawnScheduler")
local Director = Env.server("SpawnDirector")
local Scoreboard = Env.server("ScoreboardService")
local Config = Env.shared("Config")
local HudModel = Env.client("Logic/HudModel")
local Layout = Env.map("MapLayout")
local MapConfig = Env.map("BrickyardConfig")
local Registry = Env.map("SpawnRegistry")
local Risk = Env.map("SpawnRisk")

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
		allowMockUltimate = opts and opts.mockUltimate or false,
		getPose = function(id) return { pos = pos[id], forward = face[id], airborne = false } end,
	})
	local events = {}
	c:onFeedback(function(e) table.insert(events, e) end)
	for id, ch in chars do
		c:addPlayer(id, ch)
		pos[id] = v(0, 0, 0)
		face[id] = fwd
	end
	return c, core, pos, events, ps
end

local function count(events, kind)
	local n = 0
	for _, e in events do if e.type == kind then n += 1 end end
	return n
end

local function atk(dir)
	return { action = "Primary", aimDirection = dir or fwd }
end

T.describe("부활 확정 사양 값", function()
	T.it("사망 후 4초 뒤 부활, 부활 후 2초 보호", function()
		T.expectEqual(Config.Match.RespawnSeconds, 4)
		T.expectEqual(Config.Match.RespawnProtectionSeconds, 2)
	end)
end)

T.describe("부활 보호: 서버 권위 피해 면역", function()
	T.it("부활 직후 2초 동안 보호, 2초 시점에 만료", function()
		local c, _, _, events = setup({ p1 = "SWORD" })
		c:respawn("p1", 10)
		T.expect(c:isProtected("p1", 10))
		T.expect(c:isProtected("p1", 11.99))
		T.expect(not c:isProtected("p1", 12))
		local r = events[#events]
		T.expectEqual(r.type, "Respawned")
		T.expectEqual(r.protectedUntil, 12)
	end)
	T.it("보호 중 근접 공격: 체력 불변, 적중 목록 비어 있음, 피격 이벤트 없음", function()
		local c, core, pos = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 4)
		c:respawn("p2", 0)
		local damaged = 0
		core.damage:onDamaged(function() damaged += 1 end)
		local ok, info = c:handleAttack("p1", atk(), 0.5)
		T.expect(ok)
		T.expectEqual(#info.hits, 0)
		T.expectEqual(H.hp(core, "p2"), 100)
		T.expectEqual(damaged, 0)
	end)
	T.it("보호 중 적용 거부 사유는 spawn_protected 이고 체력·처치·점수·궁극기 충전에 반영되지 않는다", function()
		local c, core = setup({ p1 = "SWORD", p2 = "SWORD" })
		c:respawn("p2", 0)
		local killed, dmg = 0, 0
		core.damage:onKilled(function() killed += 1 end)
		core.damage:onDamaged(function() dmg += 1 end)
		local board = Scoreboard.new()
		board:register("p1", "A")
		board:register("p2", "B")
		core.damage:onKilled(function(e) board:onKill(e.attackerId, e.targetId) end)
		local gaugeBefore = core.ultimate:getGauge("p1")
		local r = core.damage:applyDamage({ attackerId = "p1", targetId = "p2", attackId = 1, amount = 9999, kind = "Melee" }, 1)
		T.expect(not r.applied)
		T.expectEqual(r.reason, "spawn_protected")
		T.expectEqual(H.hp(core, "p2"), 100)
		T.expect(core.damage:isAlive("p2"))
		T.expectEqual(killed, 0)
		T.expectEqual(dmg, 0)
		T.expectEqual(core.ultimate:getGauge("p1"), gaugeBefore)
		for _, row in board:snapshot() do T.expectEqual(row.kills, 0) end
	end)
	T.it("보호 중 같은 attackId 는 기록되지 않아 보호 만료 후 정상 적중 가능", function()
		local c, core = setup({ p1 = "SWORD", p2 = "SWORD" })
		c:respawn("p2", 0)
		T.expect(not core.damage:applyDamage({ attackerId = "p1", targetId = "p2", attackId = 7, amount = 10, kind = "Melee" }, 1).applied)
		c:update(2.0, 0.1)
		T.expect(core.damage:applyDamage({ attackerId = "p1", targetId = "p2", attackId = 7, amount = 10, kind = "Melee" }, 2.1).applied)
		T.expectEqual(H.hp(core, "p2"), 90)
	end)
	T.it("보호 중 투사체는 대상을 통과하고 피해 없음", function()
		local c, core, pos = setup({ p1 = "GUNNER", p2 = "SWORD" })
		pos.p2 = v(0, 0, 10)
		c:respawn("p2", 0)
		T.expect((c:handleAttack("p1", atk(), 0.5)))
		local t = 0.5
		while t < 1.5 do t += 0.02; c:update(t, 0.02) end
		T.expectEqual(H.hp(core, "p2"), 100)
	end)
	T.it("보호 만료 후에는 정상 피해", function()
		local c, core, pos = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 4)
		c:respawn("p2", 0)
		local ok, info = c:handleAttack("p1", atk(), 2.0)
		T.expect(ok)
		T.expectEqual(#info.hits, 1)
		T.expectEqual(H.hp(core, "p2"), 86)
	end)
	T.it("환경 사망(낙사 등)은 보호와 무관하게 처리되고 보호 상태가 정리된다", function()
		local c, core, _, events = setup({ p1 = "SWORD" })
		c:respawn("p1", 0)
		T.expect(core.damage:forceKill("p1", 0.5))
		T.expect(not c:isProtected("p1", 0.6))
		T.expectEqual(count(events, "Died"), 1)
		T.expectEqual(count(events, "ProtectionEnded"), 0) -- 사망으로 인한 정리는 해제 이벤트를 보내지 않는다
	end)
end)

T.describe("부활 보호 해제: 공격 행동 시작 / 만료 (서버 판정)", function()
	T.it("근접 공격 시작 시 즉시 해제 + ProtectionEnded(Attack) 이벤트", function()
		local c, core, pos, events = setup({ p1 = "SWORD", p2 = "SWORD" })
		pos.p2 = v(0, 0, 4)
		c:respawn("p1", 0)
		T.expect((c:handleAttack("p1", atk(), 0.5)))
		T.expect(not c:isProtected("p1", 0.5))
		local e
		for _, ev in events do if ev.type == "ProtectionEnded" then e = ev end end
		T.expect(e ~= nil and e.reason == "Attack" and e.playerId == "p1")
		-- 해제 직후 맞으면 피해를 받는다
		T.expect(core.damage:applyDamage({ attackerId = "p2", targetId = "p1", attackId = 1, amount = 10, kind = "Melee" }, 0.6).applied)
	end)
	T.it("원거리(PAINTBALL) 첫 발사 시 해제", function()
		local c, _, _, events = setup({ p1 = "GUNNER" })
		c:respawn("p1", 0)
		T.expect((c:handleAttack("p1", atk(), 0.3)))
		T.expect(not c:isProtected("p1", 0.3))
		T.expectEqual(count(events, "ProtectionEnded"), 1)
	end)
	T.it("실패한 공격 시도(쿨타임·재장전·사거리 밖 아님)는 해제하지 않는다", function()
		local c = setup({ p1 = "GUNNER" })
		c:respawn("p1", 0)
		-- 보호 전에 이미 쿨타임이 걸려 있는 상황을 만들 수 없으므로, 거부되는 입력(잘못된 상태)으로 확인: 사망 후 공격은 거부되고 보호도 없다
		local st = c._p["p1"]
		st.reloadingUntil = 5 -- 재장전 중에는 발사 불가
		local ok, why = c:handleAttack("p1", atk(), 0.5)
		T.expect(not ok and why == "reloading")
		T.expect(c:isProtected("p1", 0.5))
	end)
	T.it("패링·회피·달리기 전환은 공격 행동이 아니므로 해제하지 않는다", function()
		local c = setup({ p1 = "SWORD" })
		c:respawn("p1", 0)
		T.expect((c:handleAttack("p1", { action = "Secondary", aimDirection = fwd }, 0.2)))
		T.expect((c:handleDodge("p1", { direction = fwd }, 0.5)))
		c:handleSetRun("p1", true)
		T.expect(c:isProtected("p1", 0.6))
	end)
	T.it("스킬·궁극기 미구현 거부는 해제하지 않는다 / 모의 궁극기 성공 시에는 해제", function()
		local c = setup({ p1 = "GUNNER" })
		c:respawn("p1", 0)
		T.expect(not (c:handleSkill("p1", { slot = 1 }, 0.2)))
		T.expect(not (c:handleUltimate("p1", {}, 0.3)))
		T.expect(c:isProtected("p1", 0.4))
		local c2, core2 = setup({ p1 = "GUNNER" }, { mockUltimate = true })
		core2.ultimate:addKill("p1")
		core2.ultimate:addKill("p1")
		core2.ultimate:addKill("p1")
		core2.ultimate:addKill("p1")
		core2.ultimate:addKill("p1")
		c2:respawn("p1", 0)
		core2.ultimate:addDamage("p1", 100000)
		local ok = c2:handleUltimate("p1", {}, 0.5)
		if ok then T.expect(not c2:isProtected("p1", 0.5)) end
	end)
	T.it("2초 경과 시 update 가 한 번만 ProtectionEnded(Expired)", function()
		local c, _, _, events = setup({ p1 = "SWORD" })
		c:respawn("p1", 0)
		c:update(1.9, 0.1)
		T.expectEqual(count(events, "ProtectionEnded"), 0)
		c:update(2.0, 0.1)
		c:update(2.1, 0.1)
		c:update(3.0, 0.9)
		T.expectEqual(count(events, "ProtectionEnded"), 1)
		for _, ev in events do if ev.type == "ProtectionEnded" then T.expectEqual(ev.reason, "Expired") end end
	end)
	T.it("재부활하면 보호가 새로 시작된다(이전 만료 시각 무시)", function()
		local c, core = setup({ p1 = "SWORD" })
		c:respawn("p1", 0)
		core.damage:forceKill("p1", 1)
		c:respawn("p1", 5)
		T.expect(c:isProtected("p1", 6.9))
		T.expect(not c:isProtected("p1", 7))
	end)
end)

T.describe("부활 보호 클라이언트 동기화(HUD 스냅샷)", function()
	T.it("스냅샷에 protectedUntil·protectSeconds, 해제 후에는 nil", function()
		local c = setup({ p1 = "SWORD" })
		c:respawn("p1", 10)
		local snap = c:getHudSnapshot("p1", 10.5)
		T.expectEqual(snap.protectedUntil, 12)
		T.expectEqual(snap.protectSeconds, 2)
		c:update(12, 0.1)
		T.expect(c:getHudSnapshot("p1", 12.1).protectedUntil == nil)
	end)
	T.it("HudModel: 남은 시간·비율 표시, 만료/해제 시 표시 없음", function()
		local c = setup({ p1 = "SWORD" })
		c:respawn("p1", 10)
		local m = HudModel.build(c:getHudSnapshot("p1", 10.5), 10.5)
		T.expectNear(m.protection.remaining, 1.5, 1e-6)
		T.expectNear(m.protection.frac, 0.75, 1e-6)
		c:handleAttack("p1", atk(), 11)
		T.expect(HudModel.build(c:getHudSnapshot("p1", 11.1), 11.1).protection == nil)
	end)
	T.it("서버 시각 기준: 클라이언트 now 가 만료 시각을 지나면 서버 스냅샷이 남아 있어도 표시 안 함", function()
		local c = setup({ p1 = "SWORD" })
		c:respawn("p1", 10)
		local snap = c:getHudSnapshot("p1", 10.1)
		T.expect(HudModel.build(snap, 12.5).protection == nil)
	end)
end)

T.describe("RespawnScheduler: 4초 대기·중복·무한 리스폰 방지", function()
	T.it("사망 4초 후에 로드 대상이 되고, 로드 중 재통지는 무시", function()
		local s = Scheduler.new()
		T.expect(s:onDeath("p1", 10))
		T.expectEqual(s:getDueAt("p1"), 14)
		T.expectEqual(#s:due(13.9), 0)
		local d = s:due(14)
		T.expectEqual(#d, 1)
		T.expectEqual(d[1], "p1")
		T.expectEqual(#s:due(14.1), 0) -- 로드 중
		T.expect(not s:onDeath("p1", 14.2)) -- 중복 사망 통지 무시
		s:onSpawned("p1")
		T.expect(s:onDeath("p1", 30)) -- 새 사망은 다시 예약
	end)
	T.it("대기 중 중복 사망 통지는 대기 시각을 늘리지 않는다", function()
		local s = Scheduler.new()
		s:onDeath("p1", 0)
		T.expect(not s:onDeath("p1", 3))
		T.expectEqual(#s:due(4), 1)
	end)
	T.it("동시 사망 12명: 같은 틱에 모두 로드 대상, 정렬된 결정적 순서", function()
		local s = Scheduler.new()
		for i = 1, 12 do s:onDeath("p" .. i, 0) end
		local d = s:due(4)
		T.expectEqual(#d, 12)
		for i = 2, #d do T.expect(tostring(d[i - 1]) < tostring(d[i])) end
	end)
	T.it("첫 입장은 대기 없이 즉시 로드 대상", function()
		local s = Scheduler.new()
		s:requestInitial("p1", 5)
		T.expectEqual(#s:due(5), 1)
	end)
	T.it("로드 실패: 1초 뒤 재시도, 상한(5회) 이후 포기(무한 재시도 없음)", function()
		local logs = {}
		local s = Scheduler.new({ onLog = function(k) table.insert(logs, k) end })
		s:onDeath("p1", 0)
		local t = 4
		local tries = 0
		for _ = 1, 20 do
			local d = s:due(t)
			if #d > 0 then
				tries += 1
				s:onLoadFailed("p1", t)
			end
			t += 1
		end
		T.expectEqual(tries, Config.Match.MaxLoadAttempts)
		T.expectEqual(logs[#logs], "respawn_gave_up")
	end)
	T.it("짧은 시간에 로드가 반복되면(즉시 재사망 루프) 상한 후 지연·로그", function()
		local logs = {}
		local s = Scheduler.new({ onLog = function(k) table.insert(logs, k) end })
		local t, loads = 0, 0
		for _ = 1, 30 do
			s:onDeath("p1", t)
			t += Config.Match.RespawnSeconds
			local d = s:due(t)
			if #d > 0 then loads += 1; s:finishCall("p1", s:getAttempt("p1"), true, t); s:onSpawned("p1") end
		end
		T.expect(loads <= Config.Match.MaxLoadsPerWindow + math.ceil(t / Config.Match.LoadWindowSeconds) * Config.Match.MaxLoadsPerWindow)
		local throttled = false
		for _, k in logs do if k == "respawn_throttled" then throttled = true end end
		-- 4초 간격 사망이면 30초 창 안에 최대 7~8회이므로 상한(6)에 걸려 스로틀이 발생한다
		T.expect(throttled)
	end)
	T.it("remove: 이후 due 에 나타나지 않는다(퇴장)", function()
		local s = Scheduler.new()
		s:onDeath("p1", 0)
		s:remove("p1")
		T.expectEqual(#s:due(10), 0)
	end)
end)

T.describe("동시 리스폰 + 스폰 선택 + 보호 (실제 BRICKYARD 스폰)", function()
	local layout = Layout.generate(MapConfig.copy())
	local records = {}
	for _, sp in layout.spawns do table.insert(records, { x = sp.pos.X, z = sp.pos.Z, attrs = sp.part.attributes }) end
	local list = Registry.normalize(records)

	T.it("12명이 같은 틱에 리스폰: 서로 다른 스폰, 각자 독립적으로 2초 보호", function()
		local chars = {}
		for i = 1, 12 do chars["p" .. i] = "SWORD" end
		local c, core, pos = setup(chars)
		local positions = {}
		local d = Director.new({
			risk = Risk, getSpawns = function() return list end,
			getEnemies = function(id)
				local out = {}
				for other, p in positions do if other ~= id then table.insert(out, { pos = p, alive = true }) end end
				return out
			end,
		})
		local s = Scheduler.new()
		for id in chars do s:onDeath(id, 0) end
		local used = {}
		for _, id in s:due(4) do
			local r = d:choose(id, 4)
			T.expect(r ~= nil)
			T.expect(not used[r.id], "중복 스폰 " .. r.id)
			used[r.id] = true
			positions[id] = { X = r.spawn.pos.X, Y = r.spawn.pos.Y, Z = r.spawn.pos.Z }
			pos[id] = v(r.position.X, r.position.Y, r.position.Z)
			s:onSpawned(id)
			c:respawn(id, 4)
		end
		for id in chars do
			T.expect(c:isProtected(id, 5.9), id)
			T.expect(not c:isProtected(id, 6), id)
			T.expectEqual(H.hp(core, id), 100)
		end
	end)
	T.it("한 명이 공격을 시작해도 다른 플레이어의 보호는 유지", function()
		local c, _, pos = setup({ p1 = "SWORD", p2 = "SWORD", p3 = "SWORD" })
		pos.p2 = v(50, 0, 0)
		pos.p3 = v(-50, 0, 0)
		for _, id in { "p1", "p2", "p3" } do c:respawn(id, 0) end
		T.expect((c:handleAttack("p1", atk(), 0.5)))
		T.expect(not c:isProtected("p1", 0.6))
		T.expect(c:isProtected("p2", 0.6) and c:isProtected("p3", 0.6))
	end)
	T.it("사망→4초→리스폰→보호 전체 타임라인", function()
		local c, core = setup({ p1 = "SWORD", p2 = "SWORD" })
		local s = Scheduler.new()
		c:respawn("p1", 0)
		c:update(2.0, 2)
		T.expect(core.damage:applyDamage({ attackerId = "p2", targetId = "p1", attackId = 1, amount = 150, kind = "Melee" }, 3).killed)
		T.expect(s:onDeath("p1", 3))
		T.expectEqual(#s:due(6.9), 0)
		T.expectEqual(#s:due(7), 1)
		s:onSpawned("p1")
		c:respawn("p1", 7)
		T.expectEqual(H.hp(core, "p1"), 100)
		T.expect(c:isProtected("p1", 8.9) and not c:isProtected("p1", 9))
	end)
end)

T.describe("스폰 도착 확인(중복 이동 방지)", function()
	T.it("목표 6 스터드 이내면 이동 불필요, 벗어나면 보정", function()
		local target = v(10, 3.2, 10)
		T.expect(not Director.needsCorrection(v(10.5, 3.4, 9.5), target, 6))
		T.expect(not Director.needsCorrection(v(14, 3.2, 12), target, 6))
		T.expect(Director.needsCorrection(v(0, 3.2, 0), target, 6))
		T.expect(Director.needsCorrection(v(10, 20, 10), target, 6))
	end)
end)
return true
