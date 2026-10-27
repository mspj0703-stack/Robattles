--!nonstrict
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local Core = Env.server("CombatCore")

local function room(n)
	local core = Core.new()
	for i = 1, n do
		core:addPlayer("p" .. i)
	end
	return core
end

T.describe("CombatCore 통합", function()
	T.it("12인 동시 공격: 모두 적중, 처치 1회, 마지막 일격이 처치 인정", function()
		local core = room(12)
		local kills = {}
		core.damage:onKilled(function(e)
			table.insert(kills, e.attackerId)
		end)
		local applied = 0
		for i = 2, 12 do -- 11명이 p1을 같은 순간에 공격
			local r = core.damage:applyDamage({ attackerId = "p" .. i, targetId = "p1", attackId = "atk" .. i, amount = 10 }, 50)
			if r.applied then
				applied += 1
			end
		end
		T.expectEqual(applied, 10) -- 10번째에서 체력 0, 이후는 사망 대상 거부
		T.expectEqual(#kills, 1)
		T.expectEqual(kills[1], "p11")
		T.expectEqual(core.damage:getHealth("p1"), 0)
	end)
	T.it("서로 동시에 공격(난전): 각자 독립적으로 피해", function()
		local core = room(12)
		for i = 1, 12 do
			local target = "p" .. (i % 12 + 1)
			T.expect(core.damage:applyDamage({ attackerId = "p" .. i, targetId = target, attackId = "s" .. i, amount = 7 }, 1).applied)
		end
		for i = 1, 12 do
			T.expectEqual(core.damage:getHealth("p" .. i), 93)
		end
	end)
	T.it("피해와 처치가 궁극기 게이지를 충전, 피해자는 사망 시 초기화", function()
		local core = room(3)
		core.damage:applyDamage({ attackerId = "p1", targetId = "p2", attackId = "a", amount = 50 }, 0)
		T.expectEqual(core.ultimate:getGauge("p1"), 10)
		core.damage:applyDamage({ attackerId = "p1", targetId = "p2", attackId = "b", amount = 60 }, 0)
		T.expectEqual(core.ultimate:getGauge("p1"), 10 + 10 + 20)
		T.expectEqual(core.ultimate:getGauge("p2"), 0)
	end)
	T.it("사망 시 연결된 궁극기 효과 종료·상태이상 해제", function()
		local core = room(2)
		for _ = 1, 5 do
			core.ultimate:addKill("p2")
		end
		local stopped = false
		core.ultimate:activate("p2", 0, { duration = 10 })
		core.ultimate:attach("p2", function() stopped = true end)
		core.status:apply("p2", { type = "Slow", multiplier = 0.5, duration = 5 }, 0)
		core.damage:applyDamage({ attackerId = "p1", targetId = "p2", attackId = "k", amount = 500 }, 1)
		T.expect(stopped)
		T.expectEqual(core.status:getSpeedMultiplier("p2", 1.1), 1)
	end)
	T.it("회피 무적 중 12인 동시 공격도 무효, 무적 직후엔 적중", function()
		local core = room(12)
		core.dodge:tryDodge("p1", 5)
		for i = 2, 12 do
			T.expect(not core.damage:applyDamage({ attackerId = "p" .. i, targetId = "p1", attackId = "d" .. i, amount = 5 }, 5.1).applied)
		end
		T.expect(core.damage:applyDamage({ attackerId = "p2", targetId = "p1", attackId = "d2", amount = 5 }, 5.16).applied)
	end)
	T.it("respawn: 체력·회피·궁극기·쿨타임 초기화", function()
		local core = room(2)
		core.cooldown:start("p2", "primary", 99, 0)
		core.damage:applyDamage({ attackerId = "p1", targetId = "p2", attackId = "k", amount = 500 }, 1)
		core:respawn("p2")
		T.expectEqual(core.damage:getHealth("p2"), 100)
		T.expect(core.cooldown:isReady("p2", "primary", 2))
		T.expectEqual(core.dodge:getCharges("p2", 2), 2)
	end)
	T.it("removePlayer 후 피해 요청은 unknown_target", function()
		local core = room(2)
		core:removePlayer("p2")
		T.expect(core.damage:applyDamage({ attackerId = "p1", targetId = "p2", attackId = "z", amount = 5 }, 0).reason == "unknown_target")
	end)
end)

T.describe("CombatCore: 궁극기 상태 관리 회귀 (확정 기획)", function()
	T.it("사망·같은 캐릭터 리스폰에서 게이지 유지", function()
		local core = Core.new()
		core:addPlayer("a", "SWORD")
		core:addPlayer("b", "SWORD")
		for _ = 1, 3 do core.ultimate:addKill("a") end
		core.damage:applyDamage({ attackerId = "b", targetId = "a", attackId = "k", amount = 999 }, 0)
		T.expectEqual(core.ultimate:getGauge("a"), 60)
		core:respawn("a")
		T.expectEqual(core.ultimate:getGauge("a"), 60)
	end)
	T.it("새 경기 시작(resetMatch): 게이지·체력·회피·쿨타임 전부 초기화", function()
		local core = Core.new()
		core:addPlayer("a", "SWORD")
		core:addPlayer("b", "SWORD")
		for _ = 1, 3 do core.ultimate:addKill("a") end
		core.damage:applyDamage({ attackerId = "b", targetId = "a", attackId = "k", amount = 30 }, 0)
		core.dodge:tryDodge("a", 0)
		core.cooldown:start("a", "primary", 50, 0)
		core:setCharacter("a", "PAINTBALL")
		core:resetMatch()
		T.expectEqual(core.ultimate:getGauge("a"), 0)
		T.expectEqual(core.damage:getHealth("a"), 100)
		T.expectEqual(core.dodge:getCharges("a", 0.1), 2)
		T.expect(core.cooldown:isReady("a", "primary", 1))
		T.expectEqual(core.ultimate:getCharacter("a"), "PAINTBALL")
	end)
end)

return true
