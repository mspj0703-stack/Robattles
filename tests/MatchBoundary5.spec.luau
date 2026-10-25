--!nonstrict
-- 경기 경계(MatchSession._transition 이 호출하는 정리 순서) × 5캐릭터. 지연 스킬·투사체·설치물·충전·볼·Bullseye 탄이 라운드를 넘어가지 않는다.
-- CLI 로직 검증만이며 Roblox 실제 동작은 Studio 미검증이다.
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local H = require(script.Parent.Helpers)
local Core = Env.server("CombatCore")
local ProjectileService = Env.server("ProjectileService")
local Controller = Env.server("CharacterController")
local Config = Env.shared("Config")
local v = H.v
local CHARS = { "SWORD", "PAINTBALL", "SUPERBALL", "TIMEBOMB", "SLINGSHOT" }
local floor = { point = v(0, 0, 0), normal = v(0, 1, 0) }

local function build()
	local core = Core.new(Config)
	local pos, world = {}, H.fakeWorld({ floor })
	local ids = {}
	for i, ch in CHARS do ids["p" .. i] = ch end
	local function targets()
		local out = {}
		for id, p in pos do table.insert(out, { id = id, pos = p, radius = Config.Combat.HitRadius, alive = core.damage:isAlive(id) }) end
		return out
	end
	local ps = ProjectileService.new({ damage = core.damage, targets = targets, world = world, config = Config })
	local c = Controller.new({ config = Config, core = core, projectiles = ps, targets = targets, world = world,
		getPose = function(id) return { pos = pos[id], forward = v(0, 0, 1), airborne = false } end })
	local events = 0
	local function count(e)
		if e.type == "Explosion" or e.type == "Hit" or e.type == "Damaged" then events += 1 end
	end
	c:onFeedback(count)
	ps:onEvent(count)
	local i = 0
	for id, ch in ids do
		i += 1
		c:addPlayer(id, ch)
		pos[id] = v(i * 40, 1.5, 0) -- 서로 맞지 않도록 멀리 배치
		c:respawn(id, 0)
	end
	return c, core, ps, ids, function() return events end
end

local function dirOf() return v(0, 0, 1) end
local function atk(action, phase) return { action = action, aimDirection = dirOf(), aimOrigin = v(0, 0, 0), clientTime = 0, phase = phase } end
local function sk(slot, phase) return { slot = slot, aimDirection = dirOf(), aimOrigin = v(0, 0, 0), clientTime = 0, phase = phase } end

-- MatchSession._transition 과 같은 순서
local function boundary(c, ps, ids, now)
	for id in ids do c:clearMatchTransient(id) end
	ps:clearAll(now)
	c:clearMatchObjects(now)
end

T.describe("경기 경계 × 5캐릭터", function()
	T.it("모든 캐릭터의 스킬을 누른 뒤 경계 정리 → 폭탄·볼·탄·투사체 0, 이후 시간이 흘러도 효과 없음", function()
		local c, core, ps, ids, events = build()
		for id in ids do
			for _ = 1, 5 do core.ultimate:addKill(id) end
			c:handleAttack(id, atk("Primary", "Press"), 1)
			c:handleSkill(id, sk(1, "Press"), 1.1)
			c:handleSkill(id, sk(2, "Press"), 1.2)
			c:handleSkill(id, sk(3, "Press"), 1.3)
			c:handleAttack(id, atk("Secondary"), 1.4)
			c:handleUltimate(id, { aimDirection = dirOf() }, 1.5)
		end
		for t = 1.6, 2.5, 0.1 do c:update(t, 0.1) end
		boundary(c, ps, ids, 2.6)
		T.expectEqual(ps:getActiveCount(), 0, "투사체")
		for id, ch in ids do
			local impl = c._impl[ch] or {}
			if impl.bombs then T.expectEqual(impl.bombs:count(), 0, ch .. " 폭탄") end
			if impl.balls then T.expectEqual(impl.balls:count(), 0, ch .. " 볼") end
			if ch == "SLINGSHOT" then T.expectEqual(#impl._shots, 0, "Bullseye 탄") end
		end
		local before = events()
		for t = 2.7, 12, 0.1 do c:update(t, 0.1) end
		T.expectEqual(events(), before, "경계 이후 지연 효과 발생")
	end)

	T.it("경계 후 늦게 도착한 Release 는 어떤 캐릭터에서도 투사체·폭탄·볼·탄을 만들지 못한다", function()
		local c, core, ps, ids = build()
		for id in ids do
			c:handleAttack(id, atk("Primary", "Press"), 1)
			c:handleSkill(id, sk(2, "Press"), 1.1)
		end
		boundary(c, ps, ids, 2)
		for id, ch in ids do
			-- 주무기가 phase 를 무시하는 캐릭터(PAINTBALL 연사, TIMEBOMB 투척, SWORD 콤보)는 Release 도 정상 공격이다. 충전형만 검증한다.
			if ch == "SUPERBALL" or ch == "SLINGSHOT" then
				c:handleAttack(id, atk("Primary", "Release"), 2.2)
				T.expectEqual(ps:getActiveCount(), 0, ch .. " Primary Release 투사체")
			end
			c:handleSkill(id, sk(2, "Release"), 2.3)
			T.expectEqual(ps:getActiveCount(), 0, ch .. " Skill2 Release 투사체")
		end
		for id, ch in ids do
			local impl = c._impl[ch] or {}
			if impl.bombs then T.expectEqual(impl.bombs:count(), 0, ch .. " 폭탄") end
			if impl.balls then T.expectEqual(impl.balls:count(), 0, ch .. " 볼") end
			if ch == "SLINGSHOT" then T.expectEqual(#impl._shots, 0, "Bullseye 탄") end
		end
	end)

	T.it("clearAll 은 반복 호출해도 안전하다", function()
		local c, _, ps, ids = build()
		boundary(c, ps, ids, 1)
		boundary(c, ps, ids, 2)
		T.expectEqual(ps:getActiveCount(), 0)
	end)
end)

return true
