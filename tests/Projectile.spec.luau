--!nonstrict
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local H = require(script.Parent.Helpers)
local Core = Env.server("CombatCore")
local ProjectileService = Env.server("ProjectileService")
local Templates = Env.shared("Data/ProjectileTemplates")

local v = H.v

-- 테스트 방: 플레이어 위치 맵 + 가짜 월드
local function room(ids, planes, getPose)
	local core = Core.new()
	local pos = {}
	for _, id in ids do
		core:addPlayer(id)
		pos[id] = v(0, 1, 0)
	end
	local ps = ProjectileService.new({
		damage = core.damage,
		targets = function()
			local list = {}
			for _, id in ids do
				table.insert(list, { id = id, pos = pos[id], radius = 1, alive = core.damage:isAlive(id) })
			end
			return list
		end,
		world = H.fakeWorld(planes or {}),
		getPose = getPose,
	})
	local events = {}
	ps:onEvent(function(e)
		table.insert(events, e)
	end)
	return core, ps, pos, events
end

local function run(ps, from, to, dt)
	local t = from
	while t < to - 1e-9 do
		t = math.min(t + (dt or 0.05), to)
		ps:step(t)
	end
end

local function count(events, typeName)
	local n = 0
	for _, e in events do
		if e.type == typeName then
			n += 1
		end
	end
	return n
end

local function endedReason(events)
	for i = #events, 1, -1 do
		if events[i].type == "Ended" then
			return events[i].reason
		end
	end
end

local function spawn(ps, def, owner, origin, dir, now, extra)
	local params = { def = def, ownerId = owner, origin = origin, direction = dir }
	for k, val in extra or {} do
		params[k] = val
	end
	return ps:spawn(params, now or 0)
end

local fwd = v(0, 0, 1)

T.describe("ProjectileService: 직선(Linear)", function()
	T.it("직선 투사체가 실제로 이동해 명중, 서버가 피해 적용", function()
		local core, ps, pos, ev = room({ "p1", "p2" })
		pos.p2 = v(0, 1, 30)
		spawn(ps, Templates.Linear, "p1", v(0, 1, 0), fwd)
		T.expectEqual(core.damage:getHealth("p2"), 100) -- 발사 순간엔 피해 없음(히트스캔 아님)
		T.expect(ps:getActiveCount() == 1)
		run(ps, 0, 0.5)
		T.expectEqual(core.damage:getHealth("p2"), 90)
		T.expectEqual(ps:getActiveCount(), 0)
		T.expectEqual(count(ev, "Hit"), 1)
	end)
	T.it("빗나가면 수명 종료로 자연 소멸", function()
		local core, ps, pos, ev = room({ "p1", "p2" })
		pos.p2 = v(15, 1, 30)
		spawn(ps, Templates.Linear, "p1", v(0, 1, 0), fwd)
		run(ps, 0, 3.5)
		T.expectEqual(core.damage:getHealth("p2"), 100)
		T.expectEqual(ps:getActiveCount(), 0)
		T.expectEqual(endedReason(ev), "Expired")
	end)
	T.it("maxRange 도달 시 소멸", function()
		local _, ps, _, ev = room({ "p1" })
		local def = H.clone(Templates.Linear)
		def.maxRange = 50
		spawn(ps, def, "p1", v(0, 1, 0), fwd)
		run(ps, 0, 1)
		T.expectEqual(endedReason(ev), "Range")
		for _, e in ev do
			if e.type == "Ended" then
				T.expect(math.abs(e.pos.Z - 50) < 0.01, "Z=" .. e.pos.Z)
			end
		end
	end)
	T.it("벽에 막히면 뒤의 대상은 피해 없음 (투사체 벽 충돌)", function()
		local core, ps, pos, ev = room({ "p1", "p2" }, { { point = v(0, 0, 15), normal = v(0, 0, -1) } })
		pos.p2 = v(0, 1, 30)
		spawn(ps, Templates.Linear, "p1", v(0, 1, 0), fwd)
		run(ps, 0, 1)
		T.expectEqual(core.damage:getHealth("p2"), 100)
		T.expectEqual(endedReason(ev), "World")
		for _, e in ev do
			if e.type == "Ended" then
				T.expect(math.abs(e.pos.Z - 14.6) < 0.01, "Z=" .. e.pos.Z)
			end
		end
	end)
	T.it("초고속 투사체도 터널링 없이 얇은 벽/대상 판정 (스윕)", function()
		local core, ps, pos = room({ "p1", "p2", "p3" }, { { point = v(0, 0, 300), normal = v(0, 0, -1) } })
		local def = H.clone(Templates.Linear)
		def.speed = 2000
		pos.p2 = v(0, 1, 200)
		pos.p3 = v(0, 1, 400)
		spawn(ps, def, "p1", v(0, 1, 0), fwd)
		ps:step(0.5) -- 한 번에 큰 시간 전진
		T.expectEqual(core.damage:getHealth("p2"), 90)
		T.expectEqual(core.damage:getHealth("p3"), 100)
		local def2 = H.clone(def)
		pos.p2 = v(50, 1, 0)
		spawn(ps, def2, "p1", v(0, 1, 0), fwd, 1)
		ps:step(1.5)
		T.expectEqual(core.damage:getHealth("p3"), 100) -- 벽(300)이 400의 대상을 막음
	end)
	T.it("소유자는 자기 투사체에 맞지 않음", function()
		local core, ps = room({ "p1" })
		spawn(ps, Templates.Linear, "p1", v(0, 1, 0), fwd)
		run(ps, 0, 0.3)
		T.expectEqual(core.damage:getHealth("p1"), 100)
	end)
	T.it("회피 무적 중인 대상은 통과하고 뒤의 대상을 맞춤", function()
		local core, ps, pos, ev = room({ "p1", "p2", "p3" })
		pos.p2 = v(0, 1, 20)
		pos.p3 = v(0, 1, 50)
		core.dodge:tryDodge("p2", 0)
		spawn(ps, Templates.Linear, "p1", v(0, 1, 0), fwd)
		run(ps, 0, 1)
		T.expectEqual(core.damage:getHealth("p2"), 100)
		T.expectEqual(core.damage:getHealth("p3"), 90)
		T.expect(endedReason(ev) ~= "EventCap")
	end)
end)

T.describe("ProjectileService: 포물선(Arc)", function()
	T.it("중력으로 낙하: t=0.5s 에서 y≈-9, z≈35", function()
		local _, ps = room({ "p1" })
		local id = spawn(ps, Templates.Arc, "p1", v(0, 1, 0), fwd)
		run(ps, 0, 0.5, 1 / 30)
		local s = ps:get(id)
		T.expect(math.abs(s.pos.Y - -9) < 0.2, "Y=" .. s.pos.Y)
		T.expect(math.abs(s.pos.Z - 35) < 0.2, "Z=" .. s.pos.Z)
	end)
	T.it("낙하 경로 위의 대상 명중 / 바닥에 닿으면 소멸", function()
		local core, ps, pos, ev = room({ "p1", "p2" }, { { point = v(0, -20, 0), normal = v(0, 1, 0) } })
		pos.p2 = v(0, -9, 35)
		spawn(ps, Templates.Arc, "p1", v(0, 1, 0), fwd)
		run(ps, 0, 1)
		T.expectEqual(core.damage:getHealth("p2"), 90)
		local _, ps2, _, ev2 = room({ "p1" }, { { point = v(0, -20, 0), normal = v(0, 1, 0) } })
		spawn(ps2, Templates.Arc, "p1", v(0, 1, 0), fwd)
		run(ps2, 0, 2)
		T.expectEqual(endedReason(ev2), "World")
	end)
end)

T.describe("ProjectileService: 반사(Bounce)", function()
	local walls = { { point = v(0, 0, 20), normal = v(0, 0, -1) } }
	T.it("벽에 반사된 뒤 대상 명중, 반사당 피해 배율 적용", function()
		local core, ps, pos, ev = room({ "p1", "p2" }, walls)
		local def = H.clone(Templates.Bounce)
		def.bounce.damageMultPerBounce = 0.5
		pos.p2 = v(30, 1, 10)
		spawn(ps, def, "p1", v(0, 1, 0), v(1, 0, 1))
		run(ps, 0, 1)
		T.expectEqual(count(ev, "Bounce"), 1)
		T.expectEqual(core.damage:getHealth("p2"), 95)
	end)
	T.it("최대 반사 횟수 이후 소멸", function()
		local _, ps, _, ev = room({ "p1" }, {
			{ point = v(0, 0, 20), normal = v(0, 0, -1) },
			{ point = v(0, 0, -20), normal = v(0, 0, 1) },
		})
		local def = H.clone(Templates.Bounce)
		def.bounce.maxBounces = 2
		def.lifetime = 10
		spawn(ps, def, "p1", v(0, 1, 0), fwd)
		run(ps, 0, 3)
		T.expectEqual(count(ev, "Bounce"), 2)
		T.expectEqual(endedReason(ev), "World")
		T.expectEqual(ps:getActiveCount(), 0)
	end)
end)

T.describe("ProjectileService: 관통(Pierce)", function()
	T.it("maxHits까지만 관통, 대상당 1회만 피해", function()
		local core, ps, pos, ev = room({ "p1", "p2", "p3", "p4", "p5" })
		pos.p2, pos.p3, pos.p4, pos.p5 = v(0, 1, 10), v(0, 1, 20), v(0, 1, 30), v(0, 1, 40)
		spawn(ps, Templates.Pierce, "p1", v(0, 1, 0), fwd)
		run(ps, 0, 1)
		for _, id in { "p2", "p3", "p4" } do
			T.expectEqual(core.damage:getHealth(id), 90, id)
		end
		T.expectEqual(core.damage:getHealth("p5"), 100)
		T.expectEqual(count(ev, "Hit"), 3)
		T.expectEqual(endedReason(ev), "PierceExhausted")
	end)
	T.it("재적중 간격이 있으면 같은 대상을 간격 후 다시 맞출 수 있음", function()
		local core, ps, pos = room({ "p1", "p2" })
		pos.p2 = v(0, 1, 30)
		local def = H.clone(Templates.Pierce)
		def.pierce.maxHits = 10
		def.rehitInterval = 0.1
		def.speed = 20 -- 느려서 오래 머문다
		def.lifetime = 4
		spawn(ps, def, "p1", v(0, 1, 0), fwd)
		run(ps, 0, 4)
		local hp = core.damage:getHealth("p2")
		T.expect(hp <= 80 and hp >= 60, "hp=" .. hp) -- 2~4회: 여러 번 맞지만 0.1초 간격으로 제한됨
	end)
end)

T.describe("ProjectileService: 범위 폭발(Explosion)", function()
	local function boom(def, owner)
		local core, ps, pos, ev = room({ "p1", "p2", "p3" })
		pos.p2 = v(4, 1, 0)
		pos.p3 = v(40, 1, 0)
		local id, why = spawn(ps, def, owner or "p1", v(0, 1, 0), v(0, 0, 0))
		return core, ps, pos, ev, id, why
	end
	T.it("즉시 폭발: 거리 감쇠, 반경 밖 무피해, 소유자 제외", function()
		local core, _, _, ev = boom(Templates.Explosion)
		T.expect(math.abs(core.damage:getHealth("p2") - 74.5) < 1e-6, "hp=" .. core.damage:getHealth("p2"))
		T.expectEqual(core.damage:getHealth("p3"), 100)
		T.expectEqual(core.damage:getHealth("p1"), 100)
		T.expectEqual(count(ev, "Explosion"), 1)
	end)
	T.it("벽 뒤 대상은 폭발 피해 없음", function()
		local core, ps, pos = room({ "p1", "p2" }, { { point = v(2, 0, 0), normal = v(-1, 0, 0) } })
		pos.p2 = v(4, 1, 0)
		spawn(ps, Templates.Explosion, "p1", v(0, 1, 0), v(0, 0, 0))
		T.expectEqual(core.damage:getHealth("p2"), 100)
	end)
	T.it("폭발 넉백 속도가 이벤트로 전달됨", function()
		local _, _, _, ev = boom(Templates.Explosion)
		local found
		for _, e in ev do
			if e.type == "Explosion" then
				found = e.results[1].result.effects[1].info.velocity
			end
		end
		T.expect(found ~= nil and found.X > 0)
	end)
	T.it("friendlyOwnerDamage=true면 소유자도 피해", function()
		local def = H.clone(Templates.Explosion)
		def.explosion.friendlyOwnerDamage = true
		local core = boom(def)
		T.expect(core.damage:getHealth("p1") < 100)
	end)
	T.it("같은 폭발이 같은 대상에 두 번 피해를 주지 않음", function()
		local core, ps, pos = room({ "p1", "p2" })
		pos.p2 = v(4, 1, 0)
		local id = spawn(ps, Templates.Placed, "p1", v(0, 1, 0), v(0, 0, 0))
		run(ps, 0.6, 0.6)
		T.expect((ps:trigger(id, 1)))
		local hp = core.damage:getHealth("p2")
		T.expect(not (ps:trigger(id, 1.1)))
		run(ps, 1, 10)
		T.expectEqual(core.damage:getHealth("p2"), hp)
	end)
end)

T.describe("ProjectileService: 지속형 빔(Beam)", function()
	local pose = { pos = v(0, 1, 0), dir = v(0, 0, 1) }
	local function getPose()
		return pose
	end
	T.it("틱 간격마다 피해(재적중 0.25초), 시작 즉시 1틱", function()
		pose = { pos = v(0, 1, 0), dir = v(0, 0, 1) }
		local core, ps, pos = room({ "p1", "p2" }, nil, getPose)
		pos.p2 = v(0, 1, 20)
		spawn(ps, Templates.Beam, "p1", v(0, 1, 0), fwd)
		T.expectEqual(core.damage:getHealth("p2"), 90)
		ps:step(0.1)
		T.expectEqual(core.damage:getHealth("p2"), 90)
		ps:step(0.25)
		T.expectEqual(core.damage:getHealth("p2"), 80)
		run(ps, 0.25, 2.1)
		T.expectEqual(core.damage:getHealth("p2"), 10) -- 총 9틱
		T.expectEqual(ps:getActiveCount(), 0)
	end)
	T.it("소유자 사망 시 빔 종료, 이후 피해 없음", function()
		pose = { pos = v(0, 1, 0), dir = v(0, 0, 1) }
		local core, ps, pos, ev = room({ "p1", "p2" }, nil, getPose)
		pos.p2 = v(0, 1, 20)
		spawn(ps, Templates.Beam, "p1", v(0, 1, 0), fwd)
		run(ps, 0, 0.6)
		local hp = core.damage:getHealth("p2")
		ps:ownerDied("p1", 0.6)
		T.expectEqual(endedReason(ev), "OwnerDied")
		run(ps, 0.6, 3)
		T.expectEqual(core.damage:getHealth("p2"), hp)
	end)
	T.it("벽에서 빔 길이 절단", function()
		pose = { pos = v(0, 1, 0), dir = v(0, 0, 1) }
		local core, ps, pos = room({ "p1", "p2" }, { { point = v(0, 0, 10), normal = v(0, 0, -1) } }, getPose)
		pos.p2 = v(0, 1, 20)
		spawn(ps, Templates.Beam, "p1", v(0, 1, 0), fwd)
		run(ps, 0, 1)
		T.expectEqual(core.damage:getHealth("p2"), 100)
	end)
	T.it("소유자 자세를 따라감", function()
		pose = { pos = v(0, 1, 0), dir = v(0, 0, 1) }
		local core, ps, pos = room({ "p1", "p2" }, nil, getPose)
		pos.p2 = v(20, 1, 0)
		spawn(ps, Templates.Beam, "p1", v(0, 1, 0), fwd)
		T.expectEqual(core.damage:getHealth("p2"), 100)
		pose = { pos = v(0, 1, 0), dir = v(1, 0, 0) }
		ps:step(0.3)
		T.expect(core.damage:getHealth("p2") < 100)
	end)
end)

T.describe("ProjectileService: 설치형 폭탄(Placed)", function()
	T.it("퓨즈 시간 후 폭발", function()
		local core, ps, pos, ev = room({ "p1", "p2" })
		pos.p2 = v(14, 1, 0)
		spawn(ps, Templates.Placed, "p1", v(10, 1, 0), v(0, 0, 0))
		run(ps, 0, 5.9)
		T.expectEqual(core.damage:getHealth("p2"), 100)
		run(ps, 5.9, 6.1)
		T.expect(core.damage:getHealth("p2") < 100)
		T.expectEqual(count(ev, "Explosion"), 1)
		T.expectEqual(ps:getActiveCount(), 0)
	end)
	T.it("장전 전 기폭 불가, 장전 후 가능", function()
		local _, ps = room({ "p1" })
		local id = spawn(ps, Templates.Placed, "p1", v(10, 1, 0), v(0, 0, 0))
		local ok, why = ps:trigger(id, 0.2)
		T.expect(not ok and why == "not_armed")
		T.expect((ps:trigger(id, 0.6)))
	end)
	T.it("소유자가 사망해도 남은 수명 동안 유지되고 자연 폭발 (피해 귀속은 소유자)", function()
		local core, ps, pos, ev = room({ "p1", "p2" })
		pos.p2 = v(14, 1, 0)
		spawn(ps, Templates.Placed, "p1", v(10, 1, 0), v(0, 0, 0))
		core.damage:applyDamage({ attackerId = "p2", targetId = "p1", attackId = "k", amount = 500 }, 1)
		ps:ownerDied("p1", 1)
		T.expectEqual(ps:getActiveCount(), 1)
		run(ps, 1, 6.5)
		T.expect(core.damage:getHealth("p2") < 100)
		T.expectEqual(ps:getActiveCount(), 0)
	end)
	T.it("survivesOwnerDeath=false 설치물은 사망 시 폭발 없이 제거", function()
		local core, ps, pos, ev = room({ "p1", "p2" })
		pos.p2 = v(14, 1, 0)
		local def = H.clone(Templates.Placed)
		def.placed.survivesOwnerDeath = false
		spawn(ps, def, "p1", v(10, 1, 0), v(0, 0, 0))
		ps:ownerDied("p1", 1)
		run(ps, 1, 8)
		T.expectEqual(core.damage:getHealth("p2"), 100)
		T.expectEqual(count(ev, "Explosion"), 0)
	end)
	T.it("동일 소유자의 연쇄 폭발은 감쇠 (×1, ×0.5, ×0.25)", function()
		local core, ps, pos = room({ "p1", "p2" })
		core.damage:register("tank", 1000)
		core.dodge:register("tank")
		pos.tank = v(0, 1, 0)
		local def = H.clone(Templates.Placed)
		def.explosion.falloffMin = 1
		def.explosion.damage = 40
		def.explosion.knockback = 0
		def.placed.armTime = 0
		def.placed.fuseTime = 1
		local room2, ps2, pos2 = nil, nil, nil
		-- tank 를 대상 목록에 포함시키기 위해 새 서비스 구성
		local ids = { "p1", "tank" }
		local ps3 = ProjectileService.new({
			damage = core.damage,
			targets = function()
				return { { id = "tank", pos = v(0, 1, 0), radius = 1, alive = true } }
			end,
		})
		for i = 0, 2 do
			ps3:spawn({ def = def, ownerId = "p1", origin = v(0, 1, 0), direction = v(0, 0, 0) }, i * 0.1)
			ps3:trigger("pj" .. (i + 1), i * 0.1 + 0.01)
		end
		T.expect(math.abs((1000 - core.damage:getHealth("tank")) - (40 + 20 + 10)) < 1e-6, "dmg=" .. (1000 - core.damage:getHealth("tank")))
	end)
	T.it("발사 후 원본 데이터가 바뀌어도 스냅샷으로 동작 (부활·캐릭터 변경 후 오참조 방지)", function()
		local core, ps, pos = room({ "p1", "p2" })
		pos.p2 = v(14, 1, 0)
		local def = H.clone(Templates.Placed)
		def.placed.fuseTime = 1
		spawn(ps, def, "p1", v(10, 1, 0), v(0, 0, 0))
		def.explosion.damage = 999
		def.explosion.radius = 0.5
		core.damage:applyDamage({ attackerId = "p2", targetId = "p1", attackId = "k", amount = 500 }, 0.2)
		ps:ownerDied("p1", 0.2)
		core:respawn("p1")
		ps:ownerRespawned("p1")
		run(ps, 0.2, 1.5)
		local hp = core.damage:getHealth("p2")
		T.expect(hp < 100 and hp > 55, "hp=" .. hp) -- 원래 40 기반 피해
	end)
end)

T.describe("ProjectileService: 히트스캔(선택 구조)", function()
	local hs = H.clone(Templates.Linear)
	hs.collision = { mode = "Hitscan", radius = 0, allowHitscan = true }
	hs.maxRange = 100
	T.it("allowHitscan=true 개별 공격은 즉시 판정", function()
		local core, ps, pos = room({ "p1", "p2" })
		pos.p2 = v(0, 1, 50)
		spawn(ps, hs, "p1", v(0, 1, 0), fwd)
		T.expectEqual(core.damage:getHealth("p2"), 90)
		T.expectEqual(ps:getActiveCount(), 0)
	end)
	T.it("히트스캔도 벽에 막힘", function()
		local core, ps, pos = room({ "p1", "p2" }, { { point = v(0, 0, 20), normal = v(0, 0, -1) } })
		pos.p2 = v(0, 1, 50)
		spawn(ps, hs, "p1", v(0, 1, 0), fwd)
		T.expectEqual(core.damage:getHealth("p2"), 100)
	end)
	T.it("allowHitscan 없이는 거부 (기본은 히트스캔 아님)", function()
		local _, ps = room({ "p1" })
		local d = H.clone(hs)
		d.collision.allowHitscan = nil
		local id, why = spawn(ps, d, "p1", v(0, 1, 0), fwd)
		T.expect(id == nil and string.find(why, "invalid_def", 1, true) ~= nil)
	end)
end)

T.describe("ProjectileService: 소유자 생애·제한·입력 검증", function()
	T.it("발사자 사망 후에도 이미 날아간 투사체는 명중 (피해 귀속 유지)", function()
		local core, ps, pos, ev = room({ "p1", "p2" })
		pos.p2 = v(0, 1, 60)
		spawn(ps, Templates.Linear, "p1", v(0, 1, 0), fwd)
		core.damage:applyDamage({ attackerId = "p2", targetId = "p1", attackId = "k", amount = 500 }, 0.05)
		ps:ownerDied("p1", 0.05)
		run(ps, 0.05, 1)
		T.expectEqual(core.damage:getHealth("p2"), 90)
		T.expectEqual(ev[#ev - 1].ownerId, "p1")
	end)
	T.it("플레이어 퇴장 후에도 투사체는 남은 수명 동안 유지", function()
		local core, ps, pos = room({ "p1", "p2" })
		pos.p2 = v(0, 1, 60)
		spawn(ps, Templates.Linear, "p1", v(0, 1, 0), fwd)
		ps:ownerRemoved("p1", 0.01)
		core:removePlayer("p1")
		run(ps, 0.01, 1)
		T.expectEqual(core.damage:getHealth("p2"), 90)
	end)
	T.it("소유자당 활성 투사체 상한", function()
		local _, ps = room({ "p1" })
		for i = 1, 64 do
			T.expect(spawn(ps, Templates.Placed, "p1", v(i, 0, 0), v(0, 0, 0)) ~= nil)
		end
		local id, why = spawn(ps, Templates.Placed, "p1", v(99, 0, 0), v(0, 0, 0))
		T.expect(id == nil and why == "too_many_projectiles")
	end)
	T.it("잘못된 spawn 입력 거부", function()
		local _, ps = room({ "p1" })
		local bad = H.clone(Templates.Linear)
		bad.gravity = 50
		T.expect(select(2, spawn(ps, bad, "p1", v(0, 1, 0), fwd)) ~= nil)
		T.expect(select(2, spawn(ps, Templates.Linear, "p1", v(0 / 0, 1, 0), fwd)) == "bad_vector")
		T.expect(select(2, spawn(ps, Templates.Linear, "p1", v(0, 1, 0), v(0, 0, 0))) == "zero_direction")
		T.expect(select(2, spawn(ps, Templates.Linear, nil, v(0, 1, 0), fwd)) == "bad_owner")
		T.expect(select(2, ps:spawn(nil, 0)) == "bad_params")
	end)
	T.it("12인 동시 발사: 같은 순간 11발 명중, 처치 1회, 중복 피해 없음", function()
		local ids = {}
		for i = 1, 12 do
			table.insert(ids, "p" .. i)
		end
		local core, ps, pos = room(ids)
		for i = 1, 12 do
			local a = math.rad(i * 30)
			pos["p" .. i] = v(math.cos(a) * 20, 1, math.sin(a) * 20)
		end
		pos.p1 = v(0, 1, 0)
		local kills = 0
		core.damage:onKilled(function()
			kills += 1
		end)
		for i = 2, 12 do
			local o = pos["p" .. i]
			spawn(ps, Templates.Linear, "p" .. i, o, v(-o.X, 0, -o.Z))
		end
		run(ps, 0, 1)
		T.expectEqual(core.damage:getHealth("p1"), 0)
		T.expectEqual(kills, 1)
		T.expectEqual(ps:getActiveCount(), 0)
	end)
end)
return true
