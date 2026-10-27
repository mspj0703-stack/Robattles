--!nonstrict
local T = require("./TestRunner")
local Config = require("../map/BrickyardConfig")
local MapLayout = require("../map/MapLayout")
local MapValidator = require("../map/MapValidator")
local MapBuilder = require("../map/MapBuilder")
local SpawnAnalysis = require("../map/SpawnAnalysis")
local SpawnRegistry = require("../map/SpawnRegistry")
local SpawnRisk = require("../map/SpawnRisk")

local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local c = {}
	for k, x in v do c[k] = deepCopy(x) end
	return c
end

local function fresh()
	return MapLayout.generate(Config.copy())
end

local function copyLayout(layout)
	local c = {}
	for k, v in layout do
		if k ~= "cfg" and k ~= "buildings" then c[k] = deepCopy(v) end
	end
	c.cfg = layout.cfg
	c.buildings = {}
	for id, b in layout.buildings do
		local nb = deepCopy({ id = b.id, sx = b.sx, sz = b.sz, cx = b.cx, cz = b.cz, roofTop = b.roofTop, steps = b.steps, stair = b.stair, hole = b.hole, size = b.size, roofProbe = b.roofProbe })
		nb.toWorld = b.toWorld
		c.buildings[id] = nb
	end
	return c
end

local function addBox(layout, group, name, x0, x1, y0, y1, z0, z1, solid)
	table.insert(layout.parts, {
		name = name, group = group, min = { X = x0, Y = y0, Z = z0 }, max = { X = x1, Y = y1, Z = z1 },
		pos = { X = (x0 + x1) / 2, Y = (y0 + y1) / 2, Z = (z0 + z1) / 2 },
		size = { X = x1 - x0, Y = y1 - y0, Z = z1 - z0 }, solid = solid ~= false, canCollide = true, color = { 0, 0, 0 }, material = "Plastic", attributes = {},
	})
end

local function failedNames(report)
	local s = {}
	for _, f in report.failures do table.insert(s, f) end
	return table.concat(s, " | ")
end

local function find(layout, group, name)
	for _, p in layout.parts do
		if p.group == group and p.name == name then return p end
	end
end

T.describe("설정 파일", function()
	T.it("확정 기본값: 180×180, 광장 76, 스폰 20, 점프대 2", function()
		T.expectEqual(Config.MapSize, 180)
		T.expectEqual(Config.PlazaSize, 76)
		T.expectEqual(Config.Spawns.Total, 20)
		T.expectEqual(#Config.Spawns.Ground, 16)
		T.expectEqual(#Config.Spawns.Roof, 4)
		T.expectEqual(#Config.JumpPads, 2)
	end)
	T.it("with(): 원본 불변, 중첩 값 병합, 배열은 통째 교체", function()
		local c = Config.with({ MapSize = 200, Building = { CenterOffset = 70 }, Dummies = { { x = 1, z = 2 } } })
		T.expectEqual(c.MapSize, 200)
		T.expectEqual(c.Building.CenterOffset, 70)
		T.expectEqual(c.Building.Size, 26) -- 병합: 다른 키 유지
		T.expectEqual(#c.Dummies, 1)
		T.expectEqual(Config.MapSize, 180)
		T.expectEqual(Config.Building.CenterOffset, 59)
		T.expectEqual(#Config.Dummies, 4)
	end)
end)

T.describe("레이아웃 생성", function()
	local L = fresh()
	T.it("결정적: 같은 설정이면 같은 결과", function()
		local L2 = fresh()
		T.expectEqual(#L.parts, #L2.parts)
		for i, p in L.parts do
			T.expect(p.group == L2.parts[i].group and p.name == L2.parts[i].name and p.pos.X == L2.parts[i].pos.X and p.pos.Y == L2.parts[i].pos.Y and p.pos.Z == L2.parts[i].pos.Z)
		end
	end)
	T.it("광장 76×76 중앙, 지면 5조각 윗면 y=0", function()
		local pl = find(L, "Ground", "Plaza")
		T.expectEqual(pl.size.X, 76)
		T.expectEqual(pl.size.Z, 76)
		T.expectEqual(pl.pos.X, 0)
		T.expectEqual(pl.max.Y, 0)
	end)
	T.it("건물 4개: 4개 모서리 대칭, 각각 벽·옥상·계단·옥상 엄폐물", function()
		local count = 0
		for id, b in L.buildings do
			count += 1
			T.expectEqual(math.abs(b.cx), 59)
			T.expectEqual(math.abs(b.cz), 59)
			T.expect(find(L, "Buildings/" .. id .. "/Walls", "OuterX") ~= nil)
			T.expect(find(L, "Buildings/" .. id .. "/Roof", "Slab_A") ~= nil)
			T.expect(find(L, "Buildings/" .. id .. "/Stairs", "Step_14") ~= nil)
			T.expect(find(L, "Buildings/" .. id .. "/RoofCover", "RoofCoverA") ~= nil)
		end
		T.expectEqual(count, 4)
	end)
	T.it("계단: 14단, 단 높이 1, 마지막 단 윗면 = 옥상 윗면(Y=14)", function()
		local b = L.buildings.PP
		T.expectEqual(b.steps, 14)
		T.expectEqual(L.roofTop, 14)
		T.expectEqual(find(L, "Buildings/PP/Stairs", "Step_14").max.Y, 14)
	end)
	T.it("스폰 20개: 외곽 지상 16(S01~S16) + 옥상 4(S17~S20), 광장 내부 없음", function()
		local ground, roof = 0, 0
		for i, sp in L.spawns do
			T.expectEqual(sp.id, string.format("S%02d", i))
			if sp.kind == "Ground" then
				ground += 1
				T.expectEqual(sp.height, 0)
				T.expect(math.abs(sp.pos.X) >= 38 or math.abs(sp.pos.Z) >= 38)
			else
				roof += 1
				T.expectEqual(sp.height, 14)
			end
			T.expect(sp.zone ~= nil and sp.enabled == true)
			local len = math.sqrt(sp.facing.X ^ 2 + sp.facing.Z ^ 2)
			T.expect(math.abs(len - 1) < 1e-6)
			T.expect(sp.facing.X * -sp.pos.X + sp.facing.Z * -sp.pos.Z >= 0) -- 기본은 맵 중심을 향함
		end
		T.expectEqual(ground, 16)
		T.expectEqual(roof, 4)
		T.expectEqual(#L.spawns, 20)
	end)
	T.it("옥상 스폰 비활성 설정: 20개 유지, 옥상 4개만 Enabled=false, 활성 16개", function()
		local cfg = Config.with({ Spawns = { RoofEnabled = false } })
		local L2 = MapLayout.generate(cfg)
		T.expectEqual(#L2.spawns, 20)
		local list = SpawnRegistry.normalize((function()
			local r = {}
			for _, sp in L2.spawns do table.insert(r, { x = sp.pos.X, z = sp.pos.Z, attrs = sp.part.attributes }) end
			return r
		end)())
		T.expectEqual(#SpawnRegistry.active(list), 16)
		local report = MapValidator.validate(L2, cfg)
		T.expect(report.ok, failedNames(report))
	end)
	T.it("스폰 좌표를 설정에서 교체하면 반영(설계안 표 붙여넣기 시나리오)", function()
		local ground = deepCopy(Config.Spawns.Ground)
		ground[1].x, ground[1].z = -76, -26
		local cfg = Config.with({ Spawns = { Ground = ground } })
		local L2 = MapLayout.generate(cfg)
		T.expectEqual(L2.spawns[1].pos.X, -76)
		T.expectEqual(L2.spawns[1].pos.Z, -26)
		T.expectEqual(L2.spawns[2].pos.X, -80)
	end)
	T.it("스폰 마커는 비충돌·비고체, 점프대는 속도 속성 보유", function()
		for _, s in L.spawns do
			T.expect(s.part.solid == false and s.part.canCollide == false)
		end
		for _, jp in L.jumpPads do
			T.expect(jp.part.attributes.JumpPad == true and jp.part.attributes.LaunchVelocity ~= nil)
		end
	end)
	T.it("색·재질: 클래식 Plastic, 회색 계열(점프대·스폰 제외)", function()
		for _, p in L.parts do
			T.expectEqual(p.material, "Plastic")
			if p.group ~= "JumpPads" and p.group ~= "Spawns" then
				local c = p.color
				T.expect(math.abs(c[1] - c[2]) < 8 and math.abs(c[2] - c[3]) < 8)
			end
		end
	end)
	T.it("크기·좌표 설정 변경이 반영됨(맵 200, 광장 80, 건물 오프셋 72) — 구역 폭 목표는 위반으로 검출", function()
		local cfg = Config.with({ MapSize = 200, PlazaSize = 80, Building = { CenterOffset = 72 } })
		local L2 = MapLayout.generate(cfg)
		T.expectEqual(find(L2, "Ground", "Plaza").size.X, 80)
		T.expectEqual(math.abs(L2.buildings.PP.cx), 72)
		T.expectEqual(L2.half, 100)
		local report = MapValidator.validate(L2, cfg)
		T.expect(not report.ok and string.find(failedNames(report), "구역 폭", 1, true) ~= nil)
	end)
end)

T.describe("검증 도구: 기본 맵", function()
	local report = MapValidator.validate(fresh())
	T.it("모든 검사 통과", function()
		T.expect(report.ok, failedNames(report))
		T.expect(#report.checks >= 15)
	end)
	T.it("보장되는 지상 통로 폭이 최소 요구(5) 이상", function()
		T.expect(report.maxGroundPassage >= 5)
	end)
	T.it("리포트 문자열 생성", function()
		T.expect(string.find(MapValidator.format(report), "PASS", 1, true) ~= nil)
	end)
end)

T.describe("검증 도구: 결함 탐지(음성 테스트)", function()
	local function mutate(fn)
		local L = copyLayout(fresh())
		fn(L)
		return MapValidator.validate(L, L.cfg)
	end
	T.it("부품 겹침 탐지", function()
		local r = mutate(function(L) addBox(L, "Cover", "Bad", 0, 4, 0, 4, 0, 4) end)
		T.expect(not r.ok and string.find(failedNames(r), "겹침", 1, true) ~= nil)
	end)
	T.it("스폰이 벽 안에 있으면 탐지", function()
		local r = mutate(function(L) L.spawns[1].pos = { X = 0, Y = 0, Z = 0 } end)
		T.expect(not r.ok and string.find(failedNames(r), "스폰", 1, true) ~= nil)
	end)
	T.it("스폰 간격이 너무 가까우면 탐지", function()
		local r = mutate(function(L) L.spawns[2].pos = { X = L.spawns[1].pos.X + 2, Y = 0, Z = L.spawns[1].pos.Z } end)
		T.expect(not r.ok and string.find(failedNames(r), "간격", 1, true) ~= nil)
	end)
	T.it("스폰 개수 부족 탐지", function()
		local r = mutate(function(L) table.remove(L.spawns) end)
		T.expect(not r.ok and string.find(failedNames(r), "개수", 1, true) ~= nil)
	end)
	T.it("계단이 한 칸 빠지면 옥상 접근 불가 탐지", function()
		local r = mutate(function(L)
			for i = #L.parts, 1, -1 do
				local p = L.parts[i]
				if p.group == "Buildings/PP/Stairs" and p.name == "Step_07" then table.remove(L.parts, i) end
			end
		end)
		T.expect(not r.ok and string.find(failedNames(r), "옥상", 1, true) ~= nil)
	end)
	T.it("계단 단 높이가 너무 크면 탐지", function()
		local r = mutate(function(L) L.buildings.PP.stair.rise = 2.5 end)
		T.expect(not r.ok and string.find(failedNames(r), "계단", 1, true) ~= nil)
	end)
	T.it("옥상 개구부가 막히면 머리 닿음 탐지", function()
		local r = mutate(function(L)
			local b = L.buildings.PP
			-- 개구부 위를 덮는 천장
			local x0, z0 = b.toWorld(b.hole.x0, b.hole.z0)
			local x1, z1 = b.toWorld(b.hole.x1, b.hole.z1)
			addBox(L, "Buildings/PP/Roof", "Cap", math.min(x0, x1), math.max(x0, x1), 12, 13, math.min(z0, z1), math.max(z0, z1))
		end)
		T.expect(not r.ok)
	end)
	local function sealDoors(L, which)
		local b = L.buildings.PP
		local function seal(name, a, bq, c, d)
			local x0, z0 = b.toWorld(a, c)
			local x1, z1 = b.toWorld(bq, d)
			addBox(L, "Buildings/PP/Walls", name, math.min(x0, x1), math.max(x0, x1), 0, 9, math.min(z0, z1), math.max(z0, z1))
		end
		if which ~= "Z" then seal("SealX", -13, -11, -4, 4) end -- 안쪽 벽(-X 로컬)의 출입구
		if which ~= "X" then seal("SealZ", -4, 4, -13, -11) end -- 안쪽 벽(-Z 로컬)의 출입구
	end
	T.it("출입구 하나를 막아도 다른 출입구로 접근 가능(검증기가 이를 허용)", function()
		local r = mutate(function(L)
			sealDoors(L, "X")
		end)
		-- 문 폭 검사는 해당 문이 막혔다고 보고하지만, 건물 접근성(걸어서 도달)은 유지된다
		local text = failedNames(r)
		T.expect(string.find(text, "걸어서 도달", 1, true) == nil, text)
		T.expect(string.find(text, "옥상 접근", 1, true) == nil, text)
	end)
	T.it("출입구를 둘 다 막으면 옥상 도달 불가·출입구 폭 위반 탐지", function()
		local r = mutate(function(L) sealDoors(L, "both") end)
		local text = failedNames(r)
		T.expect(not r.ok)
		T.expect(string.find(text, "옥상", 1, true) ~= nil, text)
		T.expect(string.find(text, "구역 폭", 1, true) ~= nil, text)
	end)
	T.it("통로가 좁아지면(폭 4 틈) 통로 폭 검사만 실패하고 보행 도달은 유지", function()
		local r = mutate(function(L)
			-- 광장과 건물 사이(z=43~45) 가로 담: 북쪽으로 가는 길을 폭 4 틈(−2..2)만 남기고 막음
			addBox(L, "Cover", "Fence1", -88, -2, 0, 6, 43, 45)
			addBox(L, "Cover", "Fence2", 2, 88, 0, 6, 43, 45)
		end)
		local text = failedNames(r)
		T.expect(not r.ok)
		T.expect(string.find(text, "통로 폭", 1, true) ~= nil, text)
		T.expect(string.find(text, "걸어서 도달", 1, true) == nil, text)
	end)
	T.it("점프대 속도가 부족하면 도착점 불일치 탐지", function()
		local r = mutate(function(L)
			local v = L.jumpPads[1].velocity
			L.jumpPads[1].velocity = { X = v.X * 0.5, Y = v.Y, Z = v.Z * 0.5 }
		end)
		T.expect(not r.ok and string.find(failedNames(r), "점프대", 1, true) ~= nil)
	end)
	T.it("점프대 궤적이 건물 벽을 지나면 충돌 탐지", function()
		local r = mutate(function(L)
			local jp = L.jumpPads[1]
			addBox(L, "Cover", "Pillar", 40, 44, 0, 60, 40, 44)
		end)
		T.expect(not r.ok)
	end)
	T.it("더미가 고체 안이면 탐지", function()
		local r = mutate(function(L) L.dummies[1].pos = { X = 0, Y = 0, Z = 0 } end)
		T.expect(not r.ok and string.find(failedNames(r), "더미", 1, true) ~= nil)
	end)
	T.it("맵 밖 부품 탐지", function()
		local r = mutate(function(L) addBox(L, "Cover", "Out", 95, 99, 0, 3, 0, 3) end)
		T.expect(not r.ok)
	end)
end)

-- 가짜 환경: 생성된 모든 객체를 레지스트리로 추적(Roblox 없이 멱등성 검증)
local function fakeEnv()
	local env = { registry = {}, created = 0 }
	local top = {}
	local function node(kind, name, parent)
		local n = { kind = kind, name = name, parent = parent, children = {} }
		env.registry[n] = true
		env.created += 1
		if parent then table.insert(parent.children, n) else table.insert(top, n) end
		return n
	end
	function env.clearExisting(rootName)
		for i = #top, 1, -1 do
			local t = top[i]
			if t.name == rootName then
				local function kill(n)
					for _, c in n.children do kill(c) end
					env.registry[n] = nil
				end
				kill(t)
				table.remove(top, i)
			end
		end
	end
	function env.createFolder(name, parent) return node("Folder", name, parent) end
	function env.createPart(spec, parent)
		local n = node(spec.className or "Part", spec.name, parent)
		n.spec = spec
		return n
	end
	function env.liveCount()
		local c = 0
		for _ in env.registry do c += 1 end
		return c
	end
	function env.topCount() return #top end
	return env
end

T.describe("빌더: 중복 생성 방지(멱등성)", function()
	local cfg = Config.copy()
	local L = MapLayout.generate(cfg)
	T.it("한 번 생성하면 부품 수 = 레이아웃 부품 수, 최상위 루트 1개", function()
		local env = fakeEnv()
		local res = MapBuilder.build(L, cfg, env)
		T.expectEqual(res.partCount, #L.parts)
		T.expectEqual(env.topCount(), 1)
	end)
	T.it("여러 번 생성해도 객체 수가 늘어나지 않음", function()
		local env = fakeEnv()
		MapBuilder.build(L, cfg, env)
		local n1 = env.liveCount()
		for _ = 1, 5 do MapBuilder.build(L, cfg, env) end
		T.expectEqual(env.liveCount(), n1)
		T.expectEqual(env.topCount(), 1)
	end)
	T.it("설정을 바꿔 다시 생성하면 이전 결과가 남지 않음", function()
		local env = fakeEnv()
		MapBuilder.build(L, cfg, env)
		local cfg2 = Config.with({ MapSize = 200 })
		local L2 = MapLayout.generate(cfg2)
		MapBuilder.build(L2, cfg2, env)
		local parts = 0
		for n in env.registry do if n.kind == "Part" then parts += 1 end end
		T.expectEqual(parts, #L2.parts)
		T.expectEqual(env.topCount(), 1)
	end)
	T.it("그룹 폴더 구조: Buildings/PP/Walls 등 계층 생성", function()
		local env = fakeEnv()
		local res = MapBuilder.build(L, cfg, env)
		local p = res.parts["Buildings/PP/Walls/OuterX"]
		T.expect(p ~= nil)
		T.expectEqual(p.parent.name, "Walls")
		T.expectEqual(p.parent.parent.name, "PP")
		T.expectEqual(p.parent.parent.parent.name, "Buildings")
		T.expectEqual(p.parent.parent.parent.parent.name, "BRICKYARD")
	end)
	T.it("spawnLocations 옵션: 스폰 마커만 SpawnLocation 으로 생성", function()
		local env = fakeEnv()
		local res = MapBuilder.build(L, cfg, env, { spawnLocations = true })
		local sl, other = 0, 0
		for n in env.registry do
			if n.kind == "SpawnLocation" then sl += 1 elseif n.kind == "Part" then other += 1 end
		end
		T.expectEqual(sl, 20)
		T.expectEqual(other, #L.parts - 20)
		-- 옵션이 레이아웃 원본을 오염시키지 않음
		T.expect(L.spawns[1].part.className == nil)
	end)
end)

T.describe("테스트 더미 좌표", function()
	T.it("더미 4개, 지면 위, 광장 안", function()
		local L = fresh()
		T.expectEqual(#L.dummies, 4)
		for _, d in L.dummies do
			T.expect(math.abs(d.pos.X) < 38 and math.abs(d.pos.Z) < 38 and d.pos.Y == 0)
		end
	end)
end)

T.describe("구역별 통로·입구·계단 검증", function()
	local L = fresh()
	local report = MapValidator.validate(L)
	T.it("외곽 주 통로 16 (목표 14~18), 건물 연결부 8 (목표 8~10), 출입구 8", function()
		T.expectEqual(#report.zoneWidths, 16)
		for _, w in report.zoneWidths do
			T.expect(w.width >= w.min and w.width <= w.max, w.name)
			if string.find(w.name, "외곽 주 통로", 1, true) then T.expectEqual(w.width, 16) else T.expectEqual(w.width, 8) end
		end
	end)
	T.it("건물을 바깥으로 밀어 주 통로가 14 미만이 되면 위반", function()
		local cfg = Config.with({ Building = { CenterOffset = 62 } })
		local r = MapValidator.validate(MapLayout.generate(cfg), cfg)
		T.expect(not r.ok and string.find(failedNames(r), "구역 폭", 1, true) ~= nil)
	end)
	T.it("출입구 폭이 6 미만이면 위반", function()
		local cfg = Config.with({ Building = { DoorWidth = 4 } })
		local r = MapValidator.validate(MapLayout.generate(cfg), cfg)
		T.expect(not r.ok and string.find(failedNames(r), "구역 폭", 1, true) ~= nil)
	end)
	T.it("계단 입구·진입 여유 검사 통과, 진입점을 막으면 실패", function()
		T.expect(report.ok, failedNames(report))
		local r = (function()
			local C = copyLayout(fresh())
			local b = C.buildings.PP
			local x0, z0 = b.toWorld(b.stair.x0 - 3, 6)
			local x1, z1 = b.toWorld(b.stair.x0 - 1, 10)
			addBox(C, "Buildings/PP/Walls", "Crate", math.min(x0, x1), math.max(x0, x1), 0, 3, math.min(z0, z1), math.max(z0, z1))
			return MapValidator.validate(C, C.cfg)
		end)()
		T.expect(not r.ok and string.find(failedNames(r), "계단", 1, true) ~= nil, failedNames(r))
	end)
	T.it("계단 앞 공간이 좁은 설계(첫 단 앞 여유 0.5)는 접근 불가로 검출", function()
		local cfg = Config.with({ Building = { Stair = { Run = 1.5, StartMargin = 0.5 } } })
		local r = MapValidator.validate(MapLayout.generate(cfg), cfg)
		T.expect(not r.ok)
	end)
end)

T.describe("회피·교전 공간 검증", function()
	local report = MapValidator.validate(fresh())
	T.it("모든 스폰에서 회피 거리(14)를 끝까지 갈 수 있는 방향 ≥ 2", function()
		for id, n in report.dodgeDirs do T.expect(n >= 2, id .. " " .. n) end
	end)
	T.it("모든 스폰 주변 교전 넓이 ≥ 200, 3인 여유 원 존재", function()
		for id, area in report.combatArea do T.expect(area >= 200, id .. " " .. area) end
	end)
	T.it("스폰 주변을 담으로 둘러싸면 회피·교전 공간 위반", function()
		local C = copyLayout(fresh())
		local sp = C.spawns[1]
		addBox(C, "Cover", "Pen1", sp.pos.X - 5, sp.pos.X + 5, 0, 8, sp.pos.Z + 4, sp.pos.Z + 5)
		addBox(C, "Cover", "Pen2", sp.pos.X - 5, sp.pos.X + 5, 0, 8, sp.pos.Z - 5, sp.pos.Z - 4)
		addBox(C, "Cover", "Pen3", sp.pos.X + 4, sp.pos.X + 5, 0, 8, sp.pos.Z - 4, sp.pos.Z + 4)
		addBox(C, "Cover", "Pen4", sp.pos.X - 5, sp.pos.X - 4, 0, 8, sp.pos.Z - 4, sp.pos.Z + 4)
		local r = MapValidator.validate(C, C.cfg)
		local text = failedNames(r)
		T.expect(not r.ok)
		T.expect(string.find(text, "회피", 1, true) ~= nil and string.find(text, "교전 공간", 1, true) ~= nil, text)
	end)
	T.it("dodgeFreeLength: 벽 앞에서 거리가 줄어듦", function()
		local L = fresh()
		-- 중앙 엄폐물(±5) 앞 x=-10 에서 +x 방향: 몸통 반지름 1 → 약 4 만 이동 가능
		local len = MapValidator.dodgeFreeLength(L, L.cfg, { X = -10, Y = 0, Z = 0 }, 1, 0, 14)
		T.expect(len > 3 and len < 5, tostring(len))
		T.expectEqual(MapValidator.dodgeFreeLength(L, L.cfg, { X = -30, Y = 0, Z = 30 }, 0, 1, 14), 14)
	end)
end)

T.describe("점프대 궤적 (옥상 Y=14 기준)", function()
	local report = MapValidator.validate(fresh())
	T.it("착지 Y = 옥상 14 + 몸 높이 3 + 여유 0.5, 수평 ≤ 35, 체공 ≤ 0.8, 최고점 ≤ +20", function()
		T.expectEqual(#report.jumpPads, 2)
		for _, j in report.jumpPads do
			T.expect(math.abs(j.landingY - 17.5) < 1e-6)
			T.expect(j.horizontal <= 35 and j.horizontal > 20)
			T.expect(j.flightTime <= 0.8)
			T.expect(j.apexRel <= 20 and j.apexRel > 14)
			T.expect(j.apexAbs < 25) -- 이전 설계(최고 26 이상)보다 낮음
		end
	end)
	T.it("체공 시간을 늘리면 최고점·체공 한계 위반", function()
		local cfg = Config.with({ JumpPad = { FlightTime = 1.2 } })
		local r = MapValidator.validate(MapLayout.generate(cfg), cfg)
		T.expect(not r.ok and string.find(failedNames(r), "점프대", 1, true) ~= nil)
	end)
	T.it("점프대를 너무 멀리 두면 수평 거리 한계 위반", function()
		local cfg = Config.with({ JumpPads = { { id = "PadA", x = 12, z = 12, target = "PP", lx = -8, lz = -8 }, { id = "PadB", x = -33, z = -33, target = "NN", lx = -8, lz = -8 } } })
		local r = MapValidator.validate(MapLayout.generate(cfg), cfg)
		T.expect(not r.ok)
	end)
	T.it("궤적이 외곽 벽·구조물과 충돌하지 않음(전 구간 몸통 검사 + 여유 1)", function()
		-- 기본 맵이 점프대 검사를 통과했는지로 확인
		for _, c in report.checks do
			if string.find(c.name, "점프대", 1, true) then T.expect(c.ok, c.detail) end
		end
	end)
end)

T.describe("스폰 정적 분석·레지스트리·위험도", function()
	local L = fresh()
	SpawnAnalysis.annotate(L)
	T.it("선분-상자 교차: 중앙 엄폐물이 시야를 막음, 위로 지나가면 통과", function()
		local solids = SpawnAnalysis.solids(L)
		T.expect(not SpawnAnalysis.lineOfSight(solids, { X = -10, Y = 3, Z = 0 }, { X = 10, Y = 3, Z = 0 }))
		T.expect(SpawnAnalysis.lineOfSight(solids, { X = -10, Y = 8, Z = 0 }, { X = 10, Y = 8, Z = 0 }))
	end)
	T.it("annotate: 모든 스폰에 노출도(0~1)·엄폐물 거리 기록", function()
		for _, sp in L.spawns do
			T.expect(sp.exposure >= 0 and sp.exposure <= 1)
			T.expect(sp.nearestCover > 0)
			T.expectEqual(sp.part.attributes.Exposure, sp.exposure)
		end
	end)
	T.it("완전히 막힌 곳은 노출도 0", function()
		local C = copyLayout(fresh())
		local sp = C.spawns[1]
		addBox(C, "Cover", "WallA", sp.pos.X - 8, sp.pos.X + 8, 0, 10, sp.pos.Z + 5, sp.pos.Z + 7)
		addBox(C, "Cover", "WallB", sp.pos.X - 8, sp.pos.X + 8, 0, 10, sp.pos.Z - 7, sp.pos.Z - 5)
		addBox(C, "Cover", "WallC", sp.pos.X + 5, sp.pos.X + 7, 0, 10, sp.pos.Z - 5, sp.pos.Z + 5)
		addBox(C, "Cover", "WallD", sp.pos.X - 7, sp.pos.X - 5, 0, 10, sp.pos.Z - 5, sp.pos.Z + 5)
		local solids = SpawnAnalysis.solids(C)
		T.expect(SpawnAnalysis.exposure(solids, sp.pos, { openLen = 25 }).exposure < 0.3)
	end)
	local function records(layout)
		local r = {}
		for _, sp in layout.spawns do table.insert(r, { x = sp.pos.X, z = sp.pos.Z, attrs = sp.part.attributes }) end
		return r
	end
	T.it("SpawnRegistry: 맵 속성에서 20개 복원(ID·위치·방향·높이·구역·활성)", function()
		local list, errors = SpawnRegistry.normalize(records(L))
		T.expectEqual(#errors, 0)
		T.expectEqual(#list, 20)
		T.expectEqual(list[1].id, "S01")
		T.expectEqual(list[20].id, "S20")
		T.expectEqual(list[17].height, 14)
		T.expectEqual(list[1].pos.X, L.spawns[1].pos.X)
		T.expect(list[1].zone == "Edge_W" and list[1].facing ~= nil and list[1].yawDeg ~= nil)
	end)
	T.it("SpawnRegistry: 누락 속성·ID 중복은 오류로 보고하고 목록에서 제외", function()
		local rec = records(L)
		rec[1].attrs = { SpawnId = "S01" } -- 누락
		table.insert(rec, { x = 1, z = 1, attrs = L.spawns[2].part.attributes }) -- 중복
		local list, errors = SpawnRegistry.normalize(rec)
		T.expectEqual(#errors, 2)
		T.expectEqual(#list, 19)
	end)
	local list = SpawnRegistry.normalize(records(L))
	T.it("SpawnRisk: 가까운 적이 있는 스폰의 위험도가 더 높음", function()
		local enemies = { { pos = { X = list[1].pos.X + 5, Y = 0, Z = list[1].pos.Z } } }
		local scored = SpawnRisk.evaluate(list, enemies, {})
		local byId = {}
		for _, s in scored do byId[s.id] = s end
		T.expect(byId.S01.risk > byId.S02.risk)
		T.expect(byId.S01.risk > byId.S05.risk)
	end)
	T.it("SpawnRisk: 시야가 막힌 적은 덜 위험, 사망한 적은 무시", function()
		local enemies = { { pos = { X = list[1].pos.X + 5, Y = 0, Z = list[1].pos.Z } } }
		local seen = SpawnRisk.evaluate(list, enemies, { los = function() return true end })[1].risk
		local hidden = SpawnRisk.evaluate(list, enemies, { los = function() return false end })[1].risk
		T.expect(hidden < seen)
		enemies[1].alive = false
		T.expectEqual(SpawnRisk.evaluate(list, enemies, {})[1].risk, 0)
	end)
	T.it("SpawnRisk: 비활성(옥상 끄기) 스폰은 후보에서 제외, 동점은 ID 순", function()
		local cfg = Config.with({ Spawns = { RoofEnabled = false } })
		local L2 = MapLayout.generate(cfg)
		local l2 = SpawnRegistry.normalize(records(L2))
		local pick, scored = SpawnRisk.pick(l2, {}, {})
		T.expectEqual(#scored, 16)
		T.expectEqual(pick.id, "S01")
	end)
	T.it("SpawnRisk: 직전 사용 스폰은 감점되어 다른 스폰 선택, 적 근처는 회피", function()
		local enemies = { { pos = { X = list[1].pos.X + 3, Y = 0, Z = list[1].pos.Z } } }
		local pick = SpawnRisk.pick(list, enemies, { recent = { S02 = true } })
		T.expect(pick.id ~= "S01" and pick.id ~= "S02")
	end)
end)

T.describe("스폰 폴더 계약 (빌더 결과)", function()
	T.it("Spawns 폴더에 S01~S20 부품이 있고 재생성해도 20개 유지", function()
		local cfg = Config.copy()
		local L = SpawnAnalysis.annotate(MapLayout.generate(cfg))
		local env = fakeEnv()
		for _ = 1, 3 do MapBuilder.build(L, cfg, env) end
		local spawnParts = 0
		for n in env.registry do
			if n.kind == "Part" and n.parent and n.parent.name == "Spawns" then
				spawnParts += 1
				T.expect(n.spec.attributes.SpawnId ~= nil and n.spec.attributes.Exposure ~= nil)
			end
		end
		T.expectEqual(spawnParts, 20)
	end)
end)
return true
