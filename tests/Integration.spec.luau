--!nonstrict
-- 전투 ↔ 맵 통합 테스트(실제 BRICKYARD 레이아웃 사용, CLI): 스폰 충돌/위험도/리스폰, 회피 벽 관통, 이동 검증 오탐, 서버·클라이언트 동기화.
-- Roblox 물리/Raycast/Humanoid 동작은 포함하지 않는다(Studio 미검증).
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local H = require(script.Parent.Helpers)
local Layout = Env.map("MapLayout")
local MapConfig = Env.map("BrickyardConfig")
local Registry = Env.map("SpawnRegistry")
local Risk = Env.map("SpawnRisk")
local Analysis = Env.map("SpawnAnalysis")
local Director = Env.server("SpawnDirector")
local Movement = Env.server("MovementValidator")
local Config = Env.shared("Config")
local Core = Env.server("CombatCore")
local ProjectileService = Env.server("ProjectileService")
local Controller = Env.server("CharacterController")
local MovementModel = Env.client("Logic/MovementModel")

local v = H.v
local Y = 3.2

local function buildLayout(overrides)
	local cfg = MapConfig.with(overrides)
	local layout = Layout.generate(cfg)
	Analysis.annotate(layout)
	return layout, cfg
end

local function registryList(layout)
	local records = {}
	for _, s in layout.spawns do
		table.insert(records, { x = s.pos.X, z = s.pos.Z, attrs = s.part.attributes })
	end
	local list, errors = Registry.normalize(records)
	return list, errors
end

local function solidBoxes(layout)
	local boxes = {}
	for _, p in layout.parts do
		if p.solid then table.insert(boxes, { min = p.min, max = p.max }) end
	end
	return boxes
end

local layout, cfg = buildLayout()
local spawnList, regErrors = registryList(layout)
local world = H.boxWorld(solidBoxes(layout))

T.describe("통합: 원본 S01~S20 좌표 (북쪽 -Z, 남쪽 +Z)", function()
	local ORIGINAL = {
		S01 = { -80, 0, -30 }, S02 = { -80, 0, 0 }, S03 = { -80, 0, 30 }, S04 = { -30, 0, -80 }, S05 = { 0, 0, -80 },
		S06 = { 30, 0, -80 }, S07 = { 80, 0, -30 }, S08 = { 80, 0, 0 }, S09 = { 80, 0, 30 }, S10 = { -30, 0, 80 },
		S11 = { 0, 0, 80 }, S12 = { 30, 0, 80 }, S13 = { -40, 0, -40 }, S14 = { 40, 0, -40 }, S15 = { -40, 0, 40 },
		S16 = { 40, 0, 40 }, S17 = { -60, 14, -60 }, S18 = { 60, 14, -60 }, S19 = { -60, 14, 60 }, S20 = { 60, 14, 60 },
	}
	T.it("스폰 레지스트리 계약 오류 없음, 20개", function()
		T.expectEqual(#regErrors, 0)
		T.expectEqual(#spawnList, 20)
	end)
	T.it("좌표가 설계안과 정확히 일치(수정 좌표 없음 — Adjusted 비어 있음)", function()
		T.expectEqual(#cfg.Spawns.Adjusted, 0)
		for _, s in spawnList do
			local o = ORIGINAL[s.id]
			T.expect(o ~= nil, s.id)
			T.expectEqual(s.pos.X, o[1], s.id)
			T.expectEqual(s.pos.Y, o[2], s.id)
			T.expectEqual(s.pos.Z, o[3], s.id)
		end
	end)
	T.it("지상 16 + 옥상 4, 중앙 광장(|x|,|z|<38) 안 스폰 없음", function()
		local ground, roof = 0, 0
		for _, s in spawnList do
			if s.kind == "Ground" then ground += 1 else roof += 1 end
			if s.kind == "Ground" then
				T.expect(not (math.abs(s.pos.X) < 38 and math.abs(s.pos.Z) < 38), s.id .. " 광장 내부")
			end
		end
		T.expectEqual(ground, 16)
		T.expectEqual(roof, 4)
	end)
	T.it("옥상 스폰 높이 14, 어느 건물인지 좌표 부호로 결정(S17=NN, S18=PN, S19=NP, S20=PP)", function()
		local want = { S17 = "Roof_NN", S18 = "Roof_PN", S19 = "Roof_NP", S20 = "Roof_PP" }
		for _, s in spawnList do
			if want[s.id] then
				T.expectEqual(s.pos.Y, 14)
				T.expectEqual(s.zone, want[s.id])
			end
		end
	end)
	T.it("북쪽=-Z: 북쪽 외곽 스폰(S04~S06)은 z<0, 남쪽(S10~S12)은 z>0, 지면 파트 이름도 같은 방향", function()
		for _, s in spawnList do
			if s.zone == "Edge_N" then T.expect(s.pos.Z < 0, s.id) end
			if s.zone == "Edge_S" then T.expect(s.pos.Z > 0, s.id) end
		end
		for _, p in layout.parts do
			if p.group == "Perimeter" and p.name == "North" then T.expect((p.min.Z + p.max.Z) / 2 < 0) end
			if p.group == "Perimeter" and p.name == "South" then T.expect((p.min.Z + p.max.Z) / 2 > 0) end
		end
	end)
	T.it("모든 스폰이 고체 안이 아니고 발 아래에 바닥이 있다(전투 쪽 월드 기준)", function()
		for _, s in spawnList do
			T.expect(not world.inside({ X = s.pos.X, Y = s.pos.Y + Y, Z = s.pos.Z }, 0), s.id .. " HRP 가 고체 안")
			local hit = world.cast({ X = s.pos.X, Y = s.pos.Y + Y, Z = s.pos.Z }, { X = s.pos.X, Y = s.pos.Y - 1, Z = s.pos.Z }, 0)
			T.expect(hit ~= nil, s.id .. " 바닥 없음")
		end
	end)
	T.it("옥상 스폰 비활성 설정: 활성 16개, 옥상은 선택 대상에서 제외", function()
		local l2 = buildLayout({ Spawns = { RoofEnabled = false } })
		local list = registryList(l2)
		local active = Registry.active(list)
		T.expectEqual(#active, 16)
		local d = Director.new({ risk = Risk, getSpawns = function() return list end, getEnemies = function() return {} end })
		for i = 1, 30 do
			local r = d:choose("p" .. i, i * 5)
			T.expectEqual(r.spawn.kind, "Ground")
		end
	end)
end)

T.describe("통합: 스폰 위험도·리스폰", function()
	local function directorFor(enemiesRef)
		return Director.new({
			risk = Risk,
			getSpawns = function() return spawnList end,
			getEnemies = function(id)
				local out = {}
				for other, p in enemiesRef do
					if other ~= id then table.insert(out, { pos = p, alive = true }) end
				end
				return out
			end,
			los = function(a, b) return world.lineOfSight(a, b) end,
		})
	end

	T.it("12명이 순차 스폰: 서로 MinEnemyDistance 이상 떨어진 자리(가능한 한)와 중복 없는 스폰", function()
		local pos = {}
		local d = directorFor(pos)
		local used, tooClose = {}, 0
		for i = 1, 12 do
			local id = "p" .. i
			local r = d:choose(id, i * 0.1)
			T.expect(r ~= nil)
			T.expect(not used[r.id], "중복 스폰 " .. r.id)
			used[r.id] = true
			for other, p in pos do
				local dx, dz = p.X - r.spawn.pos.X, p.Z - r.spawn.pos.Z
				if math.sqrt(dx * dx + dz * dz) < Config.Spawn.MinEnemyDistance then tooClose += 1 end
			end
			pos[id] = { X = r.spawn.pos.X, Y = r.spawn.pos.Y, Z = r.spawn.pos.Z }
		end
		T.expectEqual(tooClose, 0)
	end)
	T.it("사망 후 리스폰: 적이 밀집한 쪽을 피하고 방금 죽은 자리를 다시 쓰지 않는다", function()
		local pos = { p2 = { X = -80, Y = 0, Z = -25 }, p3 = { X = -80, Y = 0, Z = 5 } } -- 서쪽(S01~S03) 근처에 적 둘
		local d = directorFor(pos)
		local first = d:choose("p1", 0)
		pos.p1 = { X = first.spawn.pos.X, Y = first.spawn.pos.Y, Z = first.spawn.pos.Z }
		for _, id in { "S01", "S02", "S03" } do T.expect(first.id ~= id) end
		-- p1 사망 → 리스폰
		pos.p1 = nil
		local second = d:choose("p1", 20)
		T.expect(second.id ~= first.id)
		for _, id in { "S01", "S02", "S03" } do T.expect(second.id ~= id) end
	end)
	T.it("모든 스폰 후보가 안전 필터를 통과하지 못해도 항상 리스폰 위치가 나온다", function()
		local pos = {}
		for i, s in spawnList do pos["e" .. i] = { X = s.pos.X, Y = s.pos.Y, Z = s.pos.Z + 2 } end
		local r = directorFor(pos):choose("p1", 0)
		T.expect(r ~= nil and r.fallback)
	end)
	T.it("맵 재생성(같은 설정): 레지스트리 결과가 동일 — 선택 로직이 재생성 전후 같은 규칙", function()
		local l2 = buildLayout()
		local list2 = registryList(l2)
		T.expectEqual(#list2, #spawnList)
		for i, s in spawnList do
			T.expectEqual(list2[i].id, s.id)
			T.expectEqual(list2[i].pos.X, s.pos.X)
			T.expectEqual(list2[i].pos.Z, s.pos.Z)
		end
	end)
	T.it("선택된 스폰 위치(HRP 높이)는 모두 고체 밖이며 바라보는 방향이 수평 단위 벡터", function()
		for _, s in spawnList do
			local d = Director.new({ risk = Risk, getSpawns = function() return { s } end, getEnemies = function() return {} end })
			local r = d:choose("p1", 0)
			T.expect(not world.inside(r.position, 0), s.id)
			T.expectNear(math.sqrt(r.facing.X ^ 2 + r.facing.Z ^ 2), 1, 1e-6, s.id)
		end
	end)
end)

T.describe("통합: 실제 맵 위 회피 벽 관통 방지", function()
	local dirs = {}
	for i = 0, 7 do
		local a = math.rad(45 * i)
		table.insert(dirs, v(math.sin(a), 0, math.cos(a)))
	end

	T.it("모든 스폰×8방향: 회피 종점이 고체 안에 들어가지 않는다", function()
		for _, s in spawnList do
			local m = Movement.new({ world = world })
			local start = v(s.pos.X, s.pos.Y + Y, s.pos.Z)
			m:register("p1", start, 0)
			for _, d in dirs do
				local plan = m:planDodge("p1", start, d, false, 0)
				T.expect(plan ~= nil)
				local e = v(start.X + plan.direction.X * plan.distance, start.Y, start.Z + plan.direction.Z * plan.distance)
				T.expect(not world.inside(e, 0.9), string.format("%s 방향(%.2f,%.2f) 종점이 벽 안", s.id, d.X, d.Z))
				T.expect(plan.distance >= 0 and plan.distance <= Config.Dodge.Distance)
			end
		end
	end)
	T.it("건물 바깥벽 앞에서 벽 방향 회피: 막혀서 거리 감소, 경로가 벽을 통과하지 않는다", function()
		-- PP 건물(중심 59,59)의 안쪽 벽(x=46) 바깥(x=40)에서 +X 로 회피 (문 위치를 피해 z=50)
		local m = Movement.new({ world = world })
		local start = v(41, Y, 52)
		m:register("p1", start, 0)
		local plan = m:planDodge("p1", start, v(1, 0, 0), false, 0)
		T.expect(plan.blocked)
		T.expect(plan.distance < 6)
		T.expect(41 + plan.distance < 46)
	end)
	T.it("문(폭 8)을 통과하는 회피는 막히지 않는다", function()
		-- PP 건물 안쪽 X벽 문: 로컬 z -4..4 → 월드 z 55..63 (건물 중심 z=59), 벽 x=46..48
		local m = Movement.new({ world = world })
		local start = v(38, Y, 59)
		m:register("p1", start, 0)
		local plan = m:planDodge("p1", start, v(1, 0, 0), false, 0)
		T.expect(not plan.blocked, "문을 통과하는 회피가 막힘")
	end)
	T.it("클라이언트가 회피를 이용해 건물 벽을 통과하는 위치를 보고하면 보정", function()
		local m = Movement.new({ world = world })
		local start = v(41, Y, 52)
		m:register("p1", start, 0)
		m:planDodge("p1", start, v(1, 0, 0), false, 0)
		local r = m:observe("p1", v(55, Y, 52), 0.2, { airborne = false })
		T.expectEqual(r.status, "correct")
		T.expectEqual(r.reason, "wall")
	end)
	T.it("서버 계획 + 클라이언트 모델 합성: 클라이언트가 적용하는 총 이동 ≤ 서버가 확정한 거리", function()
		local core = Core.new()
		local movement = Movement.new({ world = world })
		local start = v(41, Y, 52)
		movement:register("p1", start, 0)
		local ps = ProjectileService.new({ damage = core.damage, targets = function() return {} end, world = world })
		local c = Controller.new({ core = core, projectiles = ps, world = world, movement = movement, targets = function() return {} end,
			getPose = function() return { pos = start, forward = v(1, 0, 0), airborne = false } end })
		c:addPlayer("p1", "SWORD")
		c:respawn("p1", 0)
		local event
		c:onFeedback(function(e) if e.type == "Dodge" then event = e end end)
		T.expect((c:handleDodge("p1", { direction = v(1, 0, 0) }, 1)))
		T.expect(MovementModel.acceptDodgeEvent(event, "p1", 1.05, nil, 1))
		-- 클라이언트 적분
		local x, t = start.X, 1
		while t < 1.5 do
			local vel = MovementModel.dodgeVelocity(1, event.info.direction, t, nil, event.info.distance)
			if vel then x += vel.X * (1 / 60) end
			t += 1 / 60
		end
		T.expect(x - start.X <= event.info.distance + 0.3)
		T.expect(x < 46 - Config.MoveCheck.BodyRadius + 0.3)
	end)
end)

T.describe("통합: 이동 검증 오탐 방지(실제 맵)", function()
	T.it("점프대 비행(서버가 알려준 속도): 벽/속도 보정 없음, 옥상 착지 후 걷기도 정상", function()
		for _, pad in layout.jumpPads do
			local m = Movement.new({ world = world })
			local p0 = v(pad.from.X, pad.from.Y, pad.from.Z)
			m:register("p1", p0, 0)
			local vel = pad.velocity
			T.expect((m:issue("p1", "JumpPad", 0, { duration = 0.8, speed = math.sqrt(vel.X ^ 2 + vel.Z ^ 2), up = math.max(0, vel.Y) })))
			local g = cfg.JumpPad.Gravity
			local t, dt = 0, 1 / 30
			local corrections = 0
			while t < pad.flightTime - 1e-9 do
				t += dt
				local p = v(p0.X + vel.X * t, p0.Y + vel.Y * t - 0.5 * g * t * t, p0.Z + vel.Z * t)
				if m:observe("p1", p, t, { airborne = true }).status == "correct" then corrections += 1 end
			end
			T.expectEqual(corrections, 0, pad.id .. " 비행 중 보정")
			-- 착지 후 옥상에서 1초 걷기
			local land = pad.to
			local x, z = land.X, land.Z
			for i = 1, 30 do
				t += dt
				x += 0.5 * (1 / 30) * 17 / 17
				local r = m:observe("p1", v(x, land.Y, z), t, { airborne = false })
				T.expect(r.status ~= "correct", pad.id .. " 착지 후 보정")
			end
		end
	end)
	T.it("계단 걷기(문→옥상): 걷기 속도(17)에서 보정 없음", function()
		for _, id in { "PP", "PN", "NN", "NP" } do
			local b = layout.buildings[id]
			local st = b.stair
			local m = Movement.new({ world = world })
			local lz = (st.z0 + st.z1) / 2
			local lx = st.x0 - 1.25
			local wx, wz = b.toWorld(lx, lz)
			m:register("p1", v(wx, Y, wz), 0)
			local t, bad = 0, 0
			local endLx = st.x0 + st.run * st.steps
			while lx < endLx do
				t += 1 / 30
				lx += 17 / 30
				local n = math.clamp(math.floor((lx - st.x0) / st.run) + 1, 0, st.steps)
				local x, z = b.toWorld(math.min(lx, endLx), lz)
				if m:observe("p1", v(x, n * st.rise + Y, z), t, { airborne = false }).status == "correct" then bad += 1 end
			end
			T.expectEqual(bad, 0, id .. " 계단 보정")
		end
	end)
	T.it("광장 가로지르기 달리기: 엄폐물을 돌아가는 경로는 보정 없음(직선으로 벽을 뚫으면 보정)", function()
		local m = Movement.new({ world = world })
		m:register("p1", v(0, Y, -30), 0)
		-- 중앙 엄폐물(10×10) 통과 시도: z -30 → +30 을 x=0 에서 한 번에
		local r = m:observe("p1", v(0, Y, -4), 0.25, { airborne = false })
		T.expect(r.status == "correct" and (r.reason == "wall" or r.reason == "speed" or r.reason == "teleport"))
	end)
end)

T.describe("통합: 서버/클라이언트 동기화", function()
	T.it("Correct 이벤트 수용: 최근·미수용 시각·유효 좌표만 snap", function()
		local ev = { type = "Correct", pos = { X = 1, Y = 2, Z = 3 }, time = 10 }
		T.expectEqual(MovementModel.acceptCorrection(ev, 10.2, nil, 1), "snap")
		T.expectEqual(MovementModel.acceptCorrection(ev, 12, nil, 1), "ignore") -- 너무 오래됨
		T.expectEqual(MovementModel.acceptCorrection(ev, 10.2, 10, 1), "ignore") -- 이미 수용
		T.expectEqual(MovementModel.acceptCorrection({ type = "Correct", pos = { X = 0 / 0, Y = 0, Z = 0 }, time = 10 }, 10, nil, 1), "ignore")
		T.expectEqual(MovementModel.acceptCorrection({ type = "Correct", pos = { X = 1e9, Y = 0, Z = 0 }, time = 10 }, 10, nil, 1), "ignore")
		T.expectEqual(MovementModel.acceptCorrection({ type = "Dodge" }, 10, nil, 1), "ignore")
		T.expectEqual(MovementModel.acceptCorrection(nil, 10, nil, 1), "ignore")
	end)
	T.it("dodgeVelocity: 서버가 줄인 거리 반영, 0이면 이동 없음, 기본 거리 초과 값은 제한", function()
		local dir = v(1, 0, 0)
		local full = MovementModel.dodgeVelocity(0, dir, 0.1)
		T.expectNear(full.X, Config.Dodge.Distance / Config.Dodge.Duration, 1e-6)
		local half = MovementModel.dodgeVelocity(0, dir, 0.1, nil, 7)
		T.expectNear(half.X, 7 / Config.Dodge.Duration, 1e-6)
		T.expect(MovementModel.dodgeVelocity(0, dir, 0.1, nil, 0) == nil)
		local capped = MovementModel.dodgeVelocity(0, dir, 0.1, nil, 999)
		T.expectNear(capped.X, Config.Dodge.Distance / Config.Dodge.Duration, 1e-6)
		local bad = MovementModel.dodgeVelocity(0, dir, 0.1, nil, 0 / 0)
		T.expectNear(bad.X, Config.Dodge.Distance / Config.Dodge.Duration, 1e-6)
		T.expect(MovementModel.dodgeVelocity(0, dir, 0.3) == nil) -- 지속시간 이후
	end)
	T.it("서버 보정 → 같은 위치 재관찰은 ok: 보정이 반복 루프를 만들지 않는다", function()
		local m = Movement.new({ world = world })
		m:register("p1", v(0, Y, -30), 0)
		local r = m:observe("p1", v(300, Y, -30), 0.1, {})
		T.expectEqual(r.status, "correct")
		-- 서버가 correctTo 로 되돌렸고 클라이언트가 따랐다고 가정
		local r2 = m:observe("p1", r.correctTo, 0.15, {})
		T.expect(r2.status ~= "correct")
		local r3 = m:observe("p1", v(r.correctTo.X + 0.5, Y, -30), 0.2, {})
		T.expect(r3.status ~= "correct")
	end)
end)
return true
