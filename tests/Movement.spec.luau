--!nonstrict
-- 서버 이동·회피 검증(A41) 테스트: 속도/순간이동/벽 관통/회피/공중 회피/충격 허용/네트워크 지연 허용
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local H = require(script.Parent.Helpers)
local Movement = Env.server("MovementValidator")
local Config = Env.shared("Config")
local Core = Env.server("CombatCore")
local ProjectileService = Env.server("ProjectileService")
local Controller = Env.server("CharacterController")

local v = H.v
local Y = 3.2 -- HRP 높이(지면 위)

local ground = { point = v(0, 0, 0), normal = v(0, 1, 0) }
local wallX10 = { point = v(10, 0, 0), normal = v(-1, 0, 0) } -- x<10 쪽에서 접근, x=10 에 벽면

local function make(planes)
	local world = H.fakeWorld(planes or { ground })
	local logs = {}
	local m = Movement.new({ world = world, onLog = function(kind, id, d) table.insert(logs, { kind = kind, id = id, d = d }) end })
	m:register("p1", v(0, Y, 0), 0)
	return m, logs
end

-- 직선으로 speed(스터드/초)를 유지하며 dt 간격으로 duration 동안 이동. 마지막 결과 배열 반환
local function walk(m, startX, speed, from, duration, dt, state)
	local results = {}
	local t = from
	local x = startX
	while t < from + duration - 1e-9 do
		t += dt
		x += speed * dt
		table.insert(results, m:observe("p1", v(x, Y, 0), t, state or { airborne = false }))
	end
	return results, x, t
end

local function anyCorrect(results)
	for _, r in results do
		if r.status == "correct" then
			return r
		end
	end
	return nil
end

T.describe("MovementValidator: 일반 이동은 막지 않는다", function()
	T.it("달리기 속도(23)로 30Hz 샘플 3초 이동: 보정 없음", function()
		local m = make()
		local res = walk(m, 0, Config.Movement.RunSpeed, 0, 3, 1 / 30)
		T.expect(anyCorrect(res) == nil)
		T.expectEqual(m:getStats("p1").corrections, 0)
	end)
	T.it("프레임 지터·0.3초 끊김 뒤 몰아서 도착해도 허용(지연 여유)", function()
		local m = make()
		local r1 = m:observe("p1", v(23 * 0.1, Y, 0), 0.1, { airborne = false })
		local r2 = m:observe("p1", v(23 * 0.1 + 23 * 0.3, Y, 0), 0.4, { airborne = false })
		T.expect(r1.status ~= "correct" and r2.status ~= "correct")
	end)
	T.it("점프(상승 50스터드/초, 0.2초)와 낙하는 허용", function()
		local m = make()
		local t, y = 0, Y
		local bad = false
		for _ = 1, 6 do
			t += 1 / 30
			y += 50 / 30
			if m:observe("p1", v(0, y, 0), t, { airborne = true }).status == "correct" then bad = true end
		end
		for _ = 1, 20 do
			t += 1 / 30
			y -= 70 / 30
			if m:observe("p1", v(0, math.max(y, Y), 0), t, { airborne = true }).status == "correct" then bad = true end
		end
		T.expect(not bad)
	end)
	T.it("제자리 정지·미세 이동은 항상 ok", function()
		local m = make()
		for i = 1, 50 do
			T.expectEqual(m:observe("p1", v(0.01 * i, Y, 0), i / 30, { airborne = false }).status, "ok")
		end
	end)
	T.it("같은 시각 중복 표본·과거 시각 표본은 무시", function()
		local m = make()
		m:observe("p1", v(1, Y, 0), 1, {})
		T.expectEqual(m:observe("p1", v(500, Y, 0), 1, {}).status, "ok")
		T.expectEqual(m:observe("p1", v(500, Y, 0), 0.5, {}).status, "ok")
	end)
	T.it("미등록 플레이어는 검사하지 않는다(오차단 방지)", function()
		local m = make()
		T.expectEqual(m:observe("nobody", v(999, 999, 999), 5, {}).status, "ok")
	end)
end)

T.describe("MovementValidator: 비정상 이동 탐지", function()
	T.it("속도 2배(46)로 2초 이동: 보정, 마지막 유효 위치로 되돌림", function()
		local m, logs = make()
		local res = walk(m, 0, 46, 0, 2, 1 / 30)
		local c = anyCorrect(res)
		T.expect(c ~= nil)
		T.expectEqual(c.reason, "speed")
		T.expect(c.correctTo.X > 0 and c.correctTo.X < 46 * 2)
		T.expect(#logs >= 1)
	end)
	T.it("보정 후 되돌린 위치가 새 기준이 된다", function()
		local m = make()
		local c
		local x, t = 0, 0
		while not c and t < 2 do
			t += 1 / 30
			x += 2
			local r = m:observe("p1", v(x, Y, 0), t, { airborne = false })
			if r.status == "correct" then c = r end
		end
		T.expect(c ~= nil)
		T.expectEqual(m:getLastValid("p1").X, c.correctTo.X)
		-- 되돌려진 위치에서 정상 이동은 다시 허용
		local t0 = t
		local res2 = walk(m, c.correctTo.X, 20, t0, 1, 1 / 30)
		T.expect(anyCorrect(res2) == nil)
	end)
	T.it("순간이동(100스터드)은 누적 없이 즉시 보정", function()
		local m = make()
		local r = m:observe("p1", v(100, Y, 0), 0.1, { airborne = false })
		T.expectEqual(r.status, "correct")
		T.expectEqual(r.reason, "teleport")
		T.expectEqual(r.correctTo.X, 0)
	end)
	T.it("상승 속도 과다(비행): 보정", function()
		local m = make()
		local t, y, found = 0, Y, nil
		for _ = 1, 30 do
			t += 1 / 30
			y += 200 / 30
			local r = m:observe("p1", v(0, y, 0), t, { airborne = true })
			if r.status == "correct" then found = r break end
		end
		T.expect(found ~= nil)
		T.expect(found.reason == "up_speed" or found.reason == "teleport")
	end)
	T.it("벽 관통(얇은 벽을 한 표본에 가로지름): 보정", function()
		local m = make({ ground, wallX10 })
		m:observe("p1", v(9, Y, 0), 1 / 30, { airborne = false })
		local r = m:observe("p1", v(12, Y, 0), 2 / 30, { airborne = false })
		T.expectEqual(r.status, "correct")
		T.expectEqual(r.reason, "wall")
		T.expectEqual(r.correctTo.X, 9)
	end)
	T.it("벽에 붙어 서는 것은 정상(관통 아님)", function()
		local m = make({ ground, wallX10 })
		local r = m:observe("p1", v(9.7, Y, 0), 1 / 30, { airborne = false })
		T.expect(r.status ~= "correct")
	end)
	T.it("보정 남발은 로그(correction_storm)로 남는다", function()
		local m, logs = make()
		for i = 1, 6 do
			m:observe("p1", v(100 * i, Y, 0), i * 0.1, {})
		end
		local storm = false
		for _, l in logs do
			if l.kind == "correction_storm" then storm = true end
		end
		T.expect(storm)
	end)
	T.it("teleported(): 서버가 옮긴 뒤에는 기준이 새로 잡혀 오탐이 없다", function()
		local m = make()
		m:teleported("p1", v(80, Y, 80), 5)
		local r = m:observe("p1", v(80.5, Y, 80), 5.05, {})
		T.expect(r.status ~= "correct")
	end)
end)

T.describe("MovementValidator: 회피", function()
	T.it("벽이 없으면 회피 거리 14, 방향은 수평 단위 벡터로 정규화", function()
		local m = make()
		local plan = m:planDodge("p1", v(0, Y, 0), v(0, 0.5, 2), false, 0)
		T.expectEqual(plan.distance, Config.Dodge.Distance)
		T.expectEqual(plan.direction.Y, 0)
		T.expectNear(math.sqrt(plan.direction.X ^ 2 + plan.direction.Z ^ 2), 1, 1e-6)
		T.expect(not plan.blocked)
	end)
	T.it("벽 앞 회피는 벽 직전에서 멈추도록 거리가 줄어든다", function()
		local m = make({ ground, wallX10 })
		m:teleported("p1", v(5, Y, 0), 0)
		local plan = m:planDodge("p1", v(5, Y, 0), v(1, 0, 0), false, 0)
		T.expect(plan.blocked)
		T.expect(plan.distance < Config.Dodge.Distance and plan.distance > 2)
		T.expect(5 + plan.distance <= 10 - Config.MoveCheck.BodyRadius + 1e-6)
	end)
	T.it("벽에 붙은 채 회피하면 거리 0(무적만 적용)", function()
		local m = make({ ground, wallX10 })
		m:teleported("p1", v(8.9, Y, 0), 0)
		local plan = m:planDodge("p1", v(8.9, Y, 0), v(1, 0, 0), false, 0)
		T.expectEqual(plan.distance, 0)
	end)
	T.it("정상 회피(14스터드/0.25초)는 보정되지 않는다", function()
		local m = make()
		m:planDodge("p1", v(0, Y, 0), v(1, 0, 0), false, 0)
		local res, x = walk(m, 0, 14 / 0.25, 0, 0.25, 1 / 30)
		T.expect(anyCorrect(res) == nil)
		T.expect(x < 15.5)
	end)
	T.it("회피 지연 도착(네트워크 지연 0.2초 뒤 한꺼번에 14 이동)도 허용", function()
		local m = make()
		m:planDodge("p1", v(0, Y, 0), v(1, 0, 0), false, 0)
		local r = m:observe("p1", v(14, Y, 0), 0.25 + 0.2, { airborne = false })
		T.expect(r.status ~= "correct")
	end)
	T.it("회피 허용량을 크게 넘는 이동(40스터드)은 보정", function()
		local m = make()
		m:planDodge("p1", v(0, Y, 0), v(1, 0, 0), false, 0)
		local res = walk(m, 0, 160, 0, 0.5, 1 / 30)
		T.expect(anyCorrect(res) ~= nil)
	end)
	T.it("회피를 이용한 벽 통과(벽 앞에서 회피한 뒤 벽 너머 도착): 보정", function()
		local m = make({ ground, wallX10 })
		m:teleported("p1", v(5, Y, 0), 0)
		m:planDodge("p1", v(5, Y, 0), v(1, 0, 0), false, 0)
		local r = m:observe("p1", v(18, Y, 0), 0.2, { airborne = false })
		T.expectEqual(r.status, "correct")
		T.expectEqual(r.reason, "wall")
	end)
	T.it("잘못된 방향(0벡터·비테이블)은 계획 거부", function()
		local m = make()
		T.expect(m:planDodge("p1", v(0, Y, 0), v(0, 0, 0), false, 0) == nil)
		T.expect(m:planDodge("p1", v(0, Y, 0), "x", false, 0) == nil)
	end)
end)

T.describe("MovementValidator: 공중 회피", function()
	local airPos = v(0, 20, 0)
	T.it("공중에서 1회는 허용, 착지 전 2회째는 air_dodge_limit", function()
		local m = make()
		m:teleported("p1", airPos, 0)
		T.expect((m:canDodge("p1", airPos, true, 0)))
		m:planDodge("p1", airPos, v(1, 0, 0), true, 0)
		local ok, why = m:canDodge("p1", airPos, true, 1)
		T.expect(not ok and why == "air_dodge_limit")
	end)
	T.it("착지(지면 확인)하면 공중 회피 횟수 복구", function()
		local m = make()
		m:teleported("p1", airPos, 0)
		m:planDodge("p1", airPos, v(1, 0, 0), true, 0)
		m:observe("p1", v(0, Y, 0), 0.3, { airborne = false })
		T.expect((m:canDodge("p1", v(0, Y, 0), false, 1)))
		m:planDodge("p1", v(0, Y, 0), v(1, 0, 0), false, 1) -- 지상 회피는 공중 횟수를 소비하지 않는다
		T.expect((m:canDodge("p1", v(0, Y, 0), false, 2)))
	end)
	T.it("클라이언트가 지면이라고 속여도 발 아래 지면이 없으면 공중으로 판정", function()
		local m = make()
		m:teleported("p1", airPos, 0)
		m:planDodge("p1", airPos, v(1, 0, 0), true, 0)
		local ok, why = m:canDodge("p1", airPos, false, 1)
		T.expect(not ok and why == "air_dodge_limit")
	end)
	T.it("AllowAirborne=false 설정이면 공중 회피 거부", function()
		local cfg = H.clone(Config)
		cfg.Dodge.AllowAirborne = false
		local m = Movement.new({ config = cfg, world = H.fakeWorld({ ground }) })
		m:register("p1", airPos, 0)
		local ok, why = m:canDodge("p1", airPos, true, 0)
		T.expect(not ok and why == "airborne_disabled")
	end)
end)

T.describe("MovementValidator: 점프대·충격 허용", function()
	T.it("허용 충격 없이 0.5초에 60스터드 수평 이동: 보정", function()
		local m = make()
		local res = walk(m, 0, 120, 0, 0.5, 1 / 30)
		T.expect(anyCorrect(res) ~= nil)
	end)
	T.it("점프대 충격 허용 중에는 같은 이동도 보정하지 않는다", function()
		local m = make()
		T.expect((m:issue("p1", "JumpPad", 0, { duration = 0.8, speed = 45, up = 60 })))
		local res = walk(m, 0, 80, 0, 0.5, 1 / 30, { airborne = true })
		T.expect(anyCorrect(res) == nil)
	end)
	T.it("충격 허용은 시간이 지나면 만료", function()
		local m = make()
		T.expect((m:issue("p1", "Knockback", 0, { duration = 0.5, speed = 100 })))
		m:observe("p1", v(0, Y, 0), 5, {}) -- 만료 후 표본
		local res = walk(m, 0, 120, 5, 0.5, 1 / 30)
		T.expect(anyCorrect(res) ~= nil)
	end)
end)

T.describe("CharacterController + MovementValidator 연동", function()
	local function setup(planes)
		local core = Core.new()
		local pos = { p1 = v(0, Y, 0) }
		local airborne = false
		local world = H.fakeWorld(planes or { ground })
		local movement = Movement.new({ world = world })
		movement:register("p1", pos.p1, 0)
		local ps = ProjectileService.new({ damage = core.damage, targets = function() return {} end, world = world })
		local c = Controller.new({
			core = core, projectiles = ps, world = world, movement = movement,
			getPose = function() return { pos = pos.p1, forward = v(0, 0, 1), airborne = airborne } end,
			targets = function() return {} end,
		})
		c:addPlayer("p1", "SWORD")
		c:respawn("p1", 0)
		return c, core, pos, movement, function(a) airborne = a end
	end

	T.it("벽 앞 회피: Dodge 이벤트 distance 가 줄어들고 blocked=true", function()
		local c, _, pos = setup({ ground, wallX10 })
		pos.p1 = v(5, Y, 0)
		local events = {}
		c:onFeedback(function(e) if e.type == "Dodge" then table.insert(events, e) end end)
		local ok, info = c:handleDodge("p1", { direction = v(1, 0, 0) }, 1)
		T.expect(ok)
		T.expect(info.blocked and info.distance < Config.Dodge.Distance)
		T.expectEqual(#events, 1)
		T.expectEqual(events[1].info.distance, info.distance)
	end)
	T.it("벽이 없으면 기본 거리·정규화된 방향", function()
		local c = setup()
		local ok, info = c:handleDodge("p1", { direction = v(0, 0, 3) }, 1)
		T.expect(ok)
		T.expectEqual(info.distance, Config.Dodge.Distance)
		T.expectNear(info.direction.Z, 1, 1e-6)
	end)
	T.it("공중 회피 2회째는 거부되고 충전이 소비되지 않는다", function()
		local c, core, pos, _, setAir = setup()
		pos.p1 = v(0, 30, 0)
		setAir(true)
		T.expect((c:handleDodge("p1", { direction = v(1, 0, 0) }, 1)))
		local charges = core.dodge:getCharges("p1", 2)
		local ok, why = c:handleDodge("p1", { direction = v(1, 0, 0) }, 2)
		T.expect(not ok and why == "air_dodge_limit")
		T.expectEqual(core.dodge:getCharges("p1", 2), charges)
	end)
	T.it("movement 가 없어도(기존 동작) 회피는 그대로 동작", function()
		local core = Core.new()
		local world = H.fakeWorld({})
		local ps = ProjectileService.new({ damage = core.damage, targets = function() return {} end, world = world })
		local c = Controller.new({ core = core, projectiles = ps, world = world, targets = function() return {} end,
			getPose = function() return { pos = v(0, 0, 0), forward = v(0, 0, 1), airborne = false } end })
		c:addPlayer("p1", "SWORD")
		c:respawn("p1", 0)
		T.expect((c:handleDodge("p1", { direction = v(1, 0, 0) }, 1)))
	end)
end)
return true
