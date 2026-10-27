--!nonstrict
-- SpawnDirector: 전투 쪽 스폰 선택 규칙 (합성 스폰 목록 사용)
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local H = require(script.Parent.Helpers)
local Director = Env.server("SpawnDirector")
local Risk = Env.map("SpawnRisk")
local Config = Env.shared("Config")

local v = H.v

local function sp(id, x, z, extra)
	local s = { id = id, index = 1, kind = "Ground", zone = "Z", enabled = true, pos = v(x, 0, z), height = 0, yawDeg = 0, facing = v(0, 0, -1), exposure = 0, nearestCover = 0 }
	for k, val in extra or {} do s[k] = val end
	return s
end

local function make(spawns, enemies, extra)
	local logs = {}
	local d = Director.new({
		risk = Risk,
		getSpawns = function() return spawns end,
		getEnemies = function(id) return enemies[id] or enemies.all or {} end,
		onLog = function(kind, id, detail) table.insert(logs, kind) end,
		rng = extra and extra.rng,
	})
	return d, logs
end

local ring = function()
	return {
		sp("A", -80, 0), sp("B", 80, 0), sp("C", 0, -80), sp("D", 0, 80),
	}
end

T.describe("SpawnDirector", function()
	T.it("적이 없으면 어떤 활성 스폰이든 반환하고 HRP 높이를 더한다", function()
		local d = make(ring(), {})
		local r = d:choose("p1", 0)
		T.expect(r ~= nil and not r.fallback)
		T.expectEqual(r.position.Y, Config.Spawn.HrpOffset)
		T.expect(r.facing ~= nil)
	end)
	T.it("비활성(Enabled=false) 스폰은 선택하지 않는다", function()
		local list = ring()
		for _, s in list do if s.id ~= "C" then s.enabled = false end end
		local d = make(list, {})
		for i = 1, 5 do
			T.expectEqual(d:choose("p" .. i, i * 10).id, "C")
		end
	end)
	T.it("활성 스폰이 하나도 없으면 nil, no_spawns", function()
		local list = ring()
		for _, s in list do s.enabled = false end
		local r, why = make(list, {}):choose("p1", 0)
		T.expect(r == nil and why == "no_spawns")
		local r2, why2 = make({}, {}):choose("p1", 0)
		T.expect(r2 == nil and why2 == "no_spawns")
	end)
	T.it("생존 적이 가까운 스폰(MinEnemyDistance 이내)은 제외", function()
		local enemies = { all = { { pos = v(-75, 0, 0), alive = true } } } -- A 근처
		local d = make(ring(), enemies)
		for i = 1, 10 do
			T.expect(d:choose("p" .. i, i * 10).id ~= "A")
		end
	end)
	T.it("죽은 적은 위험으로 보지 않는다", function()
		local enemies = { all = { { pos = v(-75, 0, 0), alive = false } } }
		local list = { sp("A", -80, 0) }
		local r = make(list, enemies):choose("p1", 0)
		T.expect(r ~= nil and not r.fallback)
	end)
	T.it("모든 스폰이 위험하면 fallback 으로라도 가장 덜 위험한 곳을 반환(스폰 실패 없음)", function()
		local enemies = { all = {
			{ pos = v(-78, 0, 0), alive = true }, { pos = v(78, 0, 0), alive = true },
			{ pos = v(0, 0, -78), alive = true }, { pos = v(0, 0, 78), alive = true },
		} }
		local d, logs = make(ring(), enemies)
		local r = d:choose("p1", 0)
		T.expect(r ~= nil and r.fallback)
		T.expectEqual(logs[1], "spawn_fallback")
	end)
	T.it("같은 플레이어는 직전 스폰을 연속해서 쓰지 않는다(최근 사용 감점)", function()
		local d = make(ring(), {})
		local first = d:choose("p1", 0).id
		local second = d:choose("p1", 100).id
		T.expect(first ~= second)
	end)
	T.it("다른 플레이어가 방금 고른 스폰은 예약 시간 동안 피한다", function()
		local d = make(ring(), {})
		local a = d:choose("p1", 0).id
		local b = d:choose("p2", 0.5).id
		T.expect(a ~= b)
	end)
	T.it("예약은 ReserveSeconds 이후 풀린다", function()
		local list = { sp("A", 0, 0) }
		local d = make(list, {})
		d:choose("p1", 0)
		local r = d:choose("p2", Config.Spawn.ReserveSeconds + 0.1)
		T.expect(r ~= nil and not r.fallback)
	end)
	T.it("스폰 12개 순차 요청: 4개뿐일 때도 항상 결과를 반환", function()
		local d = make(ring(), {})
		for i = 1, 12 do
			T.expect(d:choose("p" .. i, i * 0.01) ~= nil)
		end
	end)
	T.it("removePlayer: 기록·예약 정리", function()
		local d = make({ sp("A", 0, 0) }, {})
		d:choose("p1", 0)
		d:removePlayer("p1")
		local r = d:choose("p2", 0.1)
		T.expect(r ~= nil and not r.fallback)
	end)
	T.it("시야가 막힌 적은 시야가 열린 적보다 덜 위험(SpawnRisk 연동)", function()
		local list = { sp("A", -40, 0), sp("B", 40, 0) }
		local enemies = { all = { { pos = v(-10, 0, 0), alive = true }, { pos = v(10, 0, 0), alive = true } } }
		local d = Director.new({
			risk = Risk, getSpawns = function() return list end, getEnemies = function() return enemies.all end,
			los = function(a, b) return a.X > 0 end, -- B 쪽만 시야 열림
		})
		T.expectEqual(d:choose("p1", 0).id, "A")
	end)
	T.it("TopN 무작위: rng 가 있으면 하위 위험 N개 중에서 고른다", function()
		local calls = 0
		local d = make(ring(), {}, { rng = function(lo, hi) calls += 1; return hi end })
		local r = d:choose("p1", 0)
		T.expect(r ~= nil and calls == 1)
	end)
end)
return true
