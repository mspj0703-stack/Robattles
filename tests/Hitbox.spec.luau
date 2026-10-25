--!nonstrict
local T = require(script.Parent.TestRunner)
local Env = require(script.Parent.Env)
local H = require(script.Parent.Helpers)
local Hitbox = Env.server("HitboxService")
local Vec = Env.shared("Vec")
local Config = Env.shared("Config")

local origin = H.v(0, 0, 0)
local fwd = H.v(0, 0, 1)

T.describe("HitboxService", function()
	T.it("조준 원점 검증: 서버 위치와 멀면 거부", function()
		T.expect((Hitbox.validateOrigin(H.v(1, 0, 1), origin, 6)))
		local ok, reason = Hitbox.validateOrigin(H.v(50, 0, 0), origin, 6)
		T.expect(not ok and reason == "origin_mismatch")
	end)
	T.it("근접 사거리: 범위 안 통과, 허용 오차 밖 거부 (공격 거리 검증)", function()
		T.expect((Hitbox.isInMeleeArc(origin, fwd, H.v(0, 0, 6), 1, 7, 110, 2)))
		T.expect((Hitbox.isInMeleeArc(origin, fwd, H.v(0, 0, 9.5), 1, 7, 110, 2))) -- 7+2+반지름
		local ok, reason = Hitbox.isInMeleeArc(origin, fwd, H.v(0, 0, 30), 1, 7, 110, 2)
		T.expect(not ok and reason == "out_of_range")
	end)
	T.it("부채꼴: 뒤쪽·옆 대상 거부", function()
		local ok, reason = Hitbox.isInMeleeArc(origin, fwd, H.v(0, 0, -4), 0, 7, 110, 0)
		T.expect(not ok and reason == "outside_arc")
		T.expect(not (Hitbox.isInMeleeArc(origin, fwd, H.v(5, 0, 0.5), 0, 7, 110, 0)))
		T.expect((Hitbox.isInMeleeArc(origin, fwd, H.v(3, 0, 3), 0, 7, 110, 0))) -- 45°
	end)
	T.it("대상 선택: 자기 자신·사망자 제외, 거리순, maxTargets, 벽 차단", function()
		local cands = {
			{ id = "me", pos = origin },
			{ id = "far", pos = H.v(0, 0, 6) },
			{ id = "near", pos = H.v(0, 0, 3) },
			{ id = "dead", pos = H.v(0, 0, 2), alive = false },
			{ id = "behind", pos = H.v(0, 0, -3) },
		}
		local p = { attackerId = "me", range = 7, arcDegrees = 110, tolerance = 0 }
		local r = Hitbox.selectMeleeTargets({ pos = origin, forward = fwd }, cands, p)
		T.expectEqual(table.concat(r, ","), "near,far")
		p.maxTargets = 1
		T.expectEqual(#Hitbox.selectMeleeTargets({ pos = origin, forward = fwd }, cands, p), 1)
		p.maxTargets = nil
		p.lineOfSight = function(_, b)
			return b.Z < 5
		end
		T.expectEqual(table.concat(Hitbox.selectMeleeTargets({ pos = origin, forward = fwd }, cands, p), ","), "near")
	end)
	T.it("범위 폭발: 반지름 안만 포함, 거리순, 벽 차단", function()
		local cands = { { id = "a", pos = H.v(3, 0, 0) }, { id = "b", pos = H.v(20, 0, 0) }, { id = "c", pos = H.v(1, 0, 0) } }
		local r = Hitbox.entitiesInRadius(origin, 12, cands)
		T.expectEqual(#r, 2)
		T.expectEqual(r[1].id, "c")
		T.expectEqual(#Hitbox.entitiesInRadius(origin, 12, cands, function() return false end), 0)
	end)
	T.it("폭발 피해 배율: 중심 1.0, 가장자리 falloffMin, 밖 0", function()
		T.expectEqual(Hitbox.explosionMultiplier(0, 12, 0.4), 1)
		T.expect(math.abs(Hitbox.explosionMultiplier(12, 12, 0.4) - 0.4) < 1e-9)
		T.expectEqual(Hitbox.explosionMultiplier(13, 12, 0.4), 0)
	end)
	T.it("원거리는 조준 보정 없음 (입력 방향 그대로)", function()
		T.expect(Config.Camera.RangedAimAssist == false)
		local d = Hitbox.rangedDirection(H.v(0, 0, 3))
		T.expectEqual(d.Z, 1)
	end)
	T.it("근접 방향 보정: 약하게 회전, 콘 밖이면 그대로", function()
		local aim = H.v(0, 0, 1)
		-- 대상이 10° 옆: 보정 12° 이내라 대상 쪽으로 정렬
		local t = H.v(math.sin(math.rad(10)) * 5, 0, math.cos(math.rad(10)) * 5)
		local d = Hitbox.assistedMeleeDirection(aim, origin, { { id = "t", pos = t } }, 12, "me", 8)
		T.expect(math.abs(Vec.angleDeg(d, t)) < 0.01)
		-- 대상이 20° 옆: 12°만 회전 (완전 정렬 아님)
		local t2 = H.v(math.sin(math.rad(20)) * 5, 0, math.cos(math.rad(20)) * 5)
		local d2 = Hitbox.assistedMeleeDirection(aim, origin, { { id = "t", pos = t2 } }, 12, "me", 8)
		T.expect(math.abs(Vec.angleDeg(aim, d2) - 12) < 0.01)
		-- 대상이 90° 옆: 콘(24°) 밖이라 변화 없음
		local d3 = Hitbox.assistedMeleeDirection(aim, origin, { { id = "t", pos = H.v(5, 0, 0) } }, 12, "me", 8)
		T.expect(math.abs(Vec.angleDeg(aim, d3)) < 0.01)
		-- 사거리 밖은 무시
		local d4 = Hitbox.assistedMeleeDirection(aim, origin, { { id = "t", pos = t } }, 12, "me", 2)
		T.expect(math.abs(Vec.angleDeg(aim, d4)) < 0.01)
	end)
end)
return true
