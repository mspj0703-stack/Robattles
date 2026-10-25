--!nonstrict
-- SLINGSHOT RMB Aim Mode 궤적 계산(순수 로직, CLI 테스트 가능). 표시 전용이며 에임 보조·서버 상태 변화가 없다.
-- 서버가 쓰는 포물선과 같은 식(등속 + 중력)이다: pos(t) = origin + dir*speed*t - 0.5*g*t² (아래로).
local Link = require(script.Parent.Parent.Link)
local Vec = Link.shared("Vec")

local AimModel = {}

-- 충전 비율(0~1)에 따른 속도·수명. 서버 Characters.SLINGSHOT.primary.shot 과 같은 선형 보간.
function AimModel.shotParams(primary, charge)
	local c = math.clamp(charge or 0, 0, 1)
	local sh = primary.shot
	return {
		speed = sh.speedMin + (sh.speedMax - sh.speedMin) * c,
		lifetime = sh.lifetimeMin + (sh.lifetimeMax - sh.lifetimeMin) * c,
		gravity = sh.gravity,
	}
end

-- 궤적 점 목록. steps 개 구간, 수명까지. world.cast(p0, p1, r) 가 있으면 첫 충돌에서 끊는다.
-- 반환: { points = { V3... }, hit = V3? }
function AimModel.trajectory(origin, dir, speed, gravity, lifetime, steps, world, radius)
	local d = Vec.normalize(dir)
	local out = { points = {}, hit = nil }
	if not d then
		return out
	end
	steps = math.max(1, steps or 24)
	local prev = origin
	table.insert(out.points, origin)
	for i = 1, steps do
		local t = lifetime * i / steps
		local p = {
			X = origin.X + d.X * speed * t,
			Y = origin.Y + d.Y * speed * t - 0.5 * gravity * t * t,
			Z = origin.Z + d.Z * speed * t,
		}
		if world and world.cast then
			local hit = world.cast(prev, p, radius or 0)
			if hit then
				local f = hit.fraction
				local q = {
					X = prev.X + (p.X - prev.X) * f,
					Y = prev.Y + (p.Y - prev.Y) * f,
					Z = prev.Z + (p.Z - prev.Z) * f,
				}
				table.insert(out.points, q)
				out.hit = q
				return out
			end
		end
		table.insert(out.points, p)
		prev = p
	end
	return out
end

return AimModel
