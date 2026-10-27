--!nonstrict
-- 특수 이동 허가(permit) 구조: 향후 스킬(Lunge/TripleSlash/PaintSlide/BounceDash/BlastJump), 일반 회피, 점프대, 서버 넉백.
-- 허가는 서버 코드만 발급한다. 위조 요청(원격 페이로드·알 수 없는 원격·가짜 필드)은 허가를 만들 수 없음을 검증한다.
-- 이번 단계에서 미구현 스킬은 구현하지 않았다: 아래 종류는 "예약된 허가 종류"의 상한/방향/빈도 검증만 한다.
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local H = require(script.Parent.Helpers)
local Movement = Env.server("MovementValidator")
local Knockback = Env.server("KnockbackApplier")
local Core = Env.server("CombatCore")
local ProjectileService = Env.server("ProjectileService")
local Controller = Env.server("CharacterController")
local Gate = Env.server("RemoteGate")
local Router = Env.server("ServerRouter")
local RemoteSpec = Env.shared("RemoteSpec")
local Config = Env.shared("Config")

local v = H.v
local Y = 3.2

local function make(cfg)
	local m = Movement.new({ config = cfg, world = H.fakeWorld({ { point = v(0, 0, 0), normal = v(0, 1, 0) } }) })
	m:register("p1", v(0, Y, 0), 0)
	return m
end

-- 방향 dir 로 speed(스터드/초) 이동하며 dt 간격 표본을 duration 동안 관찰. 첫 보정 결과 또는 nil
local function move(m, from, dir, speed, t0, duration, state)
	local t, x, z = t0, from.X, from.Z
	local dt = 1 / 30
	while t < t0 + duration - 1e-9 do
		t += dt
		x += dir.X * speed * dt
		z += dir.Z * speed * dt
		local r = m:observe("p1", v(x, Y, z), t, state or { airborne = false })
		if r.status == "correct" then
			return r, t, x, z
		end
	end
	return nil, t, x, z
end

local KINDS = { "JumpPad", "Knockback", "Lunge", "TripleSlash", "PaintSlide", "BounceDash", "BlastJump" }
local X = v(1, 0, 0)

T.describe("이동 허가 발급 규칙", function()
	T.it("정의된 모든 종류는 상한 이내에서 발급 가능", function()
		for _, kind in KINDS do
			local def = Config.MoveCheck.Permits[kind]
			T.expect(def ~= nil, kind)
			local m = make()
			local ok, why = m:issue("p1", kind, 0, { speed = def.maxSpeed, up = def.maxUp, duration = def.maxDuration, dir = X })
			T.expect(ok, kind .. ": " .. tostring(why))
			T.expectEqual(m:getPermitCount("p1", 0.1), 1)
		end
	end)
	T.it("알 수 없는 종류·미등록 플레이어·잘못된 인자 거부", function()
		local m = make()
		T.expectEqual(select(2, m:issue("p1", "Teleport", 0, { speed = 1, duration = 1 })), "unknown_kind")
		T.expectEqual(select(2, m:issue("p1", 5, 0, { speed = 1, duration = 1 })), "unknown_kind")
		T.expectEqual(select(2, m:issue("ghost", "Knockback", 0, { speed = 1, duration = 1 })), "no_state")
		T.expectEqual(select(2, m:issue("p1", "Knockback", 0, nil)), "bad_params")
		T.expectEqual(select(2, m:issue("p1", "Knockback", 0, { speed = 1 })), "bad_params") -- duration 없음
		T.expectEqual(select(2, m:issue("p1", "Knockback", 0, { speed = -1, duration = 1 })), "bad_params")
		T.expectEqual(select(2, m:issue("p1", "Knockback", 0, { speed = 0 / 0, duration = 0.1 })), "bad_params")
		T.expectEqual(select(2, m:issue("p1", "Knockback", 0, { speed = math.huge, duration = 0.1 })), "bad_params")
		T.expectEqual(select(2, m:issue("p1", "Knockback", 0, { speed = "9", duration = 0.1 })), "bad_params")
		T.expectEqual(select(2, m:issue("p1", "Knockback", 0, { speed = 1, duration = 0 })), "bad_params")
	end)
	T.it("종류별 상한 초과(속도·상승·시간)는 exceeds_cap", function()
		local m = make()
		local d = Config.MoveCheck.Permits.Lunge
		T.expectEqual(select(2, m:issue("p1", "Lunge", 0, { speed = d.maxSpeed + 1, duration = 0.1, dir = X })), "exceeds_cap")
		T.expectEqual(select(2, m:issue("p1", "Lunge", 0, { speed = 1, up = d.maxUp + 1, duration = 0.1, dir = X })), "exceeds_cap")
		T.expectEqual(select(2, m:issue("p1", "Lunge", 0, { speed = 1, duration = d.maxDuration + 0.1, dir = X })), "exceeds_cap")
		T.expectEqual(m:getPermitCount("p1", 0), 0)
	end)
	T.it("방향 허가 종류는 dir 필수", function()
		local m = make()
		T.expectEqual(select(2, m:issue("p1", "Lunge", 0, { speed = 10, duration = 0.2 })), "bad_params")
		T.expectEqual(select(2, m:issue("p1", "Lunge", 0, { speed = 10, duration = 0.2, dir = v(0, 5, 0) })), "bad_params") -- 수평 성분 없음
		T.expect((m:issue("p1", "Lunge", 0, { speed = 10, duration = 0.2, dir = v(0, 5, 3) })))
	end)
	T.it("같은 종류 재발급은 minInterval 이후에만(빈도 제한)", function()
		local m = make()
		T.expect((m:issue("p1", "Lunge", 0, { speed = 10, duration = 0.2, dir = X })))
		T.expectEqual(select(2, m:issue("p1", "Lunge", 0.5, { speed = 10, duration = 0.2, dir = X })), "rate_limited")
		T.expect((m:issue("p1", "Lunge", 1.0, { speed = 10, duration = 0.2, dir = X })))
		-- 다른 종류는 독립
		T.expect((m:issue("p1", "BlastJump", 1.0, { speed = 10, duration = 0.2 })))
	end)
	T.it("동시 활성 허가 개수 상한", function()
		local m = make()
		for i = 1, Config.MoveCheck.MaxActivePermits do
			T.expect((m:issue("p1", "Knockback", 0, { speed = 5, duration = 0.5 })), tostring(i))
		end
		T.expectEqual(select(2, m:issue("p1", "Knockback", 0, { speed = 5, duration = 0.5 })), "too_many_permits")
		-- 만료 후에는 다시 발급 가능
		T.expect((m:issue("p1", "Knockback", 5, { speed = 5, duration = 0.5 })))
	end)
end)

T.describe("허가에 따른 이동 허용/거부", function()
	T.it("허가 없는 고속 이동은 어떤 종류 이름이어도 보정된다", function()
		for _, _kind in KINDS do
			local m = make()
			local r = move(m, v(0, 0, 0), X, 80, 0, 0.5)
			T.expect(r ~= nil)
		end
	end)
	T.it("Lunge 허가: 방향 +X 로 허가량 안의 전진은 허용, 옆(+Z) 이동은 허가를 쓸 수 없어 보정", function()
		local m = make()
		T.expect((m:issue("p1", "Lunge", 0, { speed = 60, duration = 0.3, dir = X })))
		T.expect(move(m, v(0, 0, 0), X, 70, 0, 0.3) == nil)
		local m2 = make()
		T.expect((m2:issue("p1", "Lunge", 0, { speed = 60, duration = 0.3, dir = X })))
		T.expect(move(m2, v(0, 0, 0), v(0, 0, 1), 70, 0, 0.5) ~= nil)
	end)
	T.it("허가 총량 초과·만료 후 이동은 보정(허가가 무한정 늘지 않는다)", function()
		local m = make()
		T.expect((m:issue("p1", "Lunge", 0, { speed = 40, duration = 0.2, dir = X }))) -- 총량 ≈ 40×0.45
		local r = move(m, v(0, 0, 0), X, 90, 0, 1.5)
		T.expect(r ~= nil)
		-- 만료 후 새 구간
		local m2 = make()
		T.expect((m2:issue("p1", "Lunge", 0, { speed = 40, duration = 0.2, dir = X })))
		m2:observe("p1", v(0, Y, 0), 3, {})
		T.expect(move(m2, v(0, 0, 0), X, 80, 3, 0.5) ~= nil)
	end)
	T.it("각 예약 종류(TripleSlash/PaintSlide/BounceDash/BlastJump)가 자기 상한 안에서 허용", function()
		local cases = { TripleSlash = X, PaintSlide = X, BounceDash = X, BlastJump = X }
		for kind, dir in cases do
			local def = Config.MoveCheck.Permits[kind]
			local m = make()
			T.expect((m:issue("p1", kind, 0, { speed = def.maxSpeed * 0.8, duration = def.maxDuration * 0.5, dir = dir })), kind)
			local r = move(m, v(0, 0, 0), dir, def.maxSpeed * 0.8, 0, def.maxDuration * 0.5, { airborne = true })
			T.expect(r == nil, kind .. " 허용 구간에서 보정됨")
		end
	end)
	T.it("BlastJump 상승 허가: 허가 없는 수직 급상승은 보정, 허가가 있으면 허용", function()
		local function climb(m, vy)
			local t, y = 0, Y
			for _ = 1, 20 do
				t += 1 / 30
				y += vy / 30
				if m:observe("p1", v(0, y, 0), t, { airborne = true }).status == "correct" then return true end
			end
			return false
		end
		T.expect(climb(make(), 140))
		local m = make()
		T.expect((m:issue("p1", "BlastJump", 0, { speed = 0, up = 110, duration = 0.6 })))
		T.expect(not climb(m, 120))
	end)
	T.it("일반 회피도 같은 구조: 회피 방향 성분만 허용(옆으로 순간이동 불가)", function()
		local m = make()
		m:planDodge("p1", v(0, Y, 0), X, false, 0)
		T.expect(move(m, v(0, 0, 0), X, 14 / 0.25, 0, 0.25) == nil)
		local m2 = make()
		m2:planDodge("p1", v(0, Y, 0), X, false, 0)
		T.expect(move(m2, v(0, 0, 0), v(0, 0, 1), 14 / 0.25 + 40, 0, 0.5) ~= nil)
	end)
	T.it("보정이 일어나면 남은 허가는 모두 폐기", function()
		local m = make()
		T.expect((m:issue("p1", "Knockback", 0, { speed = 50, duration = 0.5 })))
		m:observe("p1", v(900, Y, 0), 0.1, {})
		T.expectEqual(m:getPermitCount("p1", 0.1), 0)
	end)
end)

T.describe("위조 요청 방어: 클라이언트는 이동 허가를 만들 수 없다", function()
	T.it("RemoteSpec 에 이동/허가 관련 원격이 없다", function()
		for name in RemoteSpec.Remotes do
			local lower = string.lower(name)
			T.expect(string.find(lower, "permit", 1, true) == nil and string.find(lower, "move", 1, true) == nil and string.find(lower, "grant", 1, true) == nil
				and string.find(lower, "teleport", 1, true) == nil and string.find(lower, "knock", 1, true) == nil, name)
		end
	end)
	T.it("알려지지 않은 원격 이름은 모두 거부", function()
		for _, name in { "IssuePermit", "GrantMovement", "Teleport", "SetPosition", "Knockback", "Lunge", "BlastJump" } do
			local ok = RemoteSpec.validate(name, { kind = "Lunge", speed = 999, duration = 9, dir = { X = 1, Y = 0, Z = 0 } })
			T.expect(not ok, name)
		end
	end)
	T.it("Dodge/SetRun/Attack 페이로드에 가짜 이동 필드를 붙이면 스키마에서 거부", function()
		local d = { X = 1, Y = 0, Z = 0 }
		for _, extra in { "distance", "speed", "permit", "kind", "position", "velocity", "duration", "ignoreWalls" } do
			local payload = { direction = d }
			payload[extra] = 999
			T.expect(not (RemoteSpec.validate("Dodge", payload)), "Dodge+" .. extra)
		end
		T.expect(not (RemoteSpec.validate("SetRun", { enabled = true, speed = 99 })))
		T.expect(not (RemoteSpec.validate("Attack", { action = "Primary", aimOrigin = { X = 0, Y = 0, Z = 0 }, aimDirection = d, clientTime = 0, lunge = true })))
	end)
	T.it("서버 라우터: 위조된 원격 이름·페이로드는 허가를 만들지 않는다", function()
		local core = Core.new()
		local world = H.fakeWorld({})
		local movement = Movement.new({ world = world })
		movement:register("p1", v(0, Y, 0), 0)
		local ps = ProjectileService.new({ damage = core.damage, targets = function() return {} end, world = world })
		local controller = Controller.new({ core = core, projectiles = ps, world = world, movement = movement, targets = function() return {} end,
			getPose = function() return { pos = v(0, Y, 0), forward = v(0, 0, 1), airborne = false } end })
		controller:addPlayer("p1", "SWORD")
		controller:respawn("p1", 0)
		local gate = Gate.new({ cooldown = core.cooldown, getState = function() return { alive = true, pos = v(0, Y, 0), serverTime = 5 } end })
		local router = Router.new({ gate = gate, controller = controller })
		local before = movement:getPermitCount("p1", 5)
		T.expect(not (router:dispatch("p1", "IssuePermit", { kind = "BlastJump", speed = 70, duration = 1, up = 110 }, 5)))
		T.expect(not (router:dispatch("p1", "Dodge", { direction = { X = 1, Y = 0, Z = 0 }, permit = "BlastJump", distance = 500 }, 5)))
		T.expectEqual(movement:getPermitCount("p1", 5), before)
	end)
	T.it("서버가 스키마를 통과한 Dodge 라도 거리·속도는 서버 값만 사용(payload 의 distance 무시)", function()
		local core = Core.new()
		local world = H.fakeWorld({})
		local movement = Movement.new({ world = world })
		movement:register("p1", v(0, Y, 0), 0)
		local ps = ProjectileService.new({ damage = core.damage, targets = function() return {} end, world = world })
		local c = Controller.new({ core = core, projectiles = ps, world = world, movement = movement, targets = function() return {} end,
			getPose = function() return { pos = v(0, Y, 0), forward = v(0, 0, 1), airborne = false } end })
		c:addPlayer("p1", "SWORD")
		c:respawn("p1", 0)
		local ok, info = c:handleDodge("p1", { direction = X, distance = 999, speed = 999 }, 5)
		T.expect(ok)
		T.expectEqual(info.distance, Config.Dodge.Distance)
		-- 위조 거리로 이동한 위치는 보정된다
		T.expect(move(movement, v(0, 0, 0), X, 999 / 0.25, 5, 0.25) ~= nil)
	end)
	T.it("Dodge 로 얻은 허가를 다른 종류로 재사용할 수 없다(Dodge 는 issue 대상이 아님)", function()
		local m = make()
		T.expectEqual(select(2, m:issue("p1", "Dodge", 0, { speed = 14, duration = 0.25, dir = X })), "unknown_kind")
	end)
end)

T.describe("서버 넉백 적용 인터페이스(KnockbackApplier)", function()
	local function rig(enabled)
		local cfg = H.clone(Config)
		cfg.Knockback.Enabled = enabled
		local core = Core.new(cfg)
		local movement = Movement.new({ config = cfg, world = H.fakeWorld({}) })
		movement:register("p1", v(0, Y, 0), 0)
		local applied = {}
		local kb = Knockback.new({ config = cfg, movement = movement, setVelocity = function(id, vel) table.insert(applied, { id = id, vel = vel }) end })
		kb:attach(core.damage)
		core.damage:register("ATT")
		core.damage:register("p1")
		return core, movement, applied, kb
	end
	local function hit(core, power, upward, now, aid)
		return core.damage:applyDamage({
			attackerId = "ATT", targetId = "p1", attackId = aid or 1, amount = 5, kind = "Melee",
			effects = { { type = "Knockback", direction = v(1, 0, 0), power = power, upward = upward or 0 } },
		}, now or 1)
	end

	T.it("기본 설정(꺼짐)에서는 속도를 적용하지 않고 허가도 발급하지 않는다", function()
		T.expect(Config.Knockback.Enabled == false)
		local core, movement, applied = rig(false)
		T.expect(hit(core, 12, 0).applied)
		T.expectEqual(#applied, 0)
		T.expectEqual(movement:getPermitCount("p1", 1), 0)
	end)
	T.it("켜면 피격 효과 결과가 속도로 적용되고 Knockback 허가가 발급된다", function()
		local core, movement, applied = rig(true)
		T.expect(hit(core, 60, 10).applied)
		T.expectEqual(#applied, 1)
		T.expectEqual(applied[1].id, "p1")
		T.expectNear(applied[1].vel.X, 60, 1e-6)
		T.expectNear(applied[1].vel.Y, 10, 1e-6)
		T.expectEqual(movement:getPermitCount("p1", 1.1), 1)
	end)
	T.it("넉백으로 밀려난 이동은 보정되지 않지만, 허가량을 넘는 이동은 보정", function()
		local core, movement = rig(true)
		hit(core, 60, 0, 1)
		T.expect(move(movement, v(0, 0, 0), X, 60, 1, 0.4) == nil)
		local core2, movement2 = rig(true)
		hit(core2, 60, 0, 1)
		T.expect(move(movement2, v(0, 0, 0), X, 200, 1, 0.5) ~= nil)
	end)
	T.it("보호 중/회피 무적 대상은 피해가 없으므로 넉백도 없다", function()
		local core, _, applied = rig(true)
		core.damage:setProtection("p1", 5)
		T.expect(not hit(core, 60, 0, 1).applied)
		T.expectEqual(#applied, 0)
	end)
	T.it("상한 초과 속도·잘못된 벡터는 적용하지 않는다", function()
		local _, movement, applied, kb = rig(true)
		local ok, why = kb:apply("p1", v(500, 0, 0), 1)
		T.expect(not ok and why == "exceeds_cap")
		T.expect(not (kb:apply("p1", { X = 0 / 0, Y = 0, Z = 0 }, 1)))
		T.expect(not (kb:apply("p1", "x", 1)))
		T.expectEqual(#applied, 0)
		T.expectEqual(movement:getPermitCount("p1", 1), 0)
	end)
	T.it("미등록(퇴장한) 대상에는 적용하지 않는다", function()
		local _, _, applied, kb = rig(true)
		local ok, why = kb:apply("ghost", v(10, 0, 0), 1)
		T.expect(not ok and why == "no_state")
		T.expectEqual(#applied, 0)
	end)
end)
return true
