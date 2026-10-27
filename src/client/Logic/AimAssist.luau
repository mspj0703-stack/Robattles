--!nonstrict
-- 근접 공격 전용 약한 방향 보정. 원거리(투사체·빔)에는 절대 적용하지 않는다(확정).
local Link = require(script.Parent.Parent.Link)
local Config = Link.shared("Config")
local Vec = Link.shared("Vec")

local AimAssist = {}

-- kind: "Melee" | "Projectile" | "Beam" | ... ; targets: [{ pos, alive }]
-- 가장 가까이 겨눈 대상 방향으로 최대 MeleeAimAssistDegrees 만큼만 회전.
function AimAssist.adjust(kind, origin, aimDir, targets, range, config)
	local cfg = config or Config
	if kind ~= "Melee" then
		return aimDir
	end
	local best, bestAngle
	for _, t in targets do
		if t.alive ~= false then
			local to = Vec.sub(t.pos, origin)
			if Vec.len(to) <= range then
				local ang = Vec.angleDeg(aimDir, to)
				if ang <= cfg.Camera.MeleeAimAssistDegrees and (bestAngle == nil or ang < bestAngle) then
					best, bestAngle = to, ang
				end
			end
		end
	end
	if best == nil then
		return aimDir
	end
	return Vec.rotateToward(aimDir, best, cfg.Camera.MeleeAimAssistDegrees)
end

return AimAssist
