--!nonstrict
-- 서버측 공간 판정(순수 기하). 위치는 서버가 가진 캐릭터 위치만 사용한다.
-- 벽 차단은 lineOfSight(a, b) -> boolean 콜백으로 주입한다(Studio에서는 Raycast, 테스트에서는 가짜).
local Link = require(script.Parent.Link)
local Vec = Link.shared("Vec")

local HitboxService = {}

-- 클라이언트가 주장한 조준 원점이 서버 캐릭터 위치 근처인지
function HitboxService.validateOrigin(claimed, serverPos, maxDeviation)
	if Vec.dist(claimed, serverPos) > maxDeviation then
		return false, "origin_mismatch"
	end
	return true, nil
end

-- 근접 부채꼴. 각도는 수평면 기준. 반환: ok, reason, distance
function HitboxService.isInMeleeArc(pos, forward, targetPos, targetRadius, range, arcDegrees, tolerance)
	local r = targetRadius or 0
	local delta = Vec.sub(targetPos, pos)
	local dist = Vec.len(delta)
	if dist - r > range + (tolerance or 0) then
		return false, "out_of_range", dist
	end
	local fwd = Vec.flatten(forward)
	if not fwd then
		return false, "bad_forward", dist
	end
	local flatDelta = Vec.flatten(delta)
	if not flatDelta then
		return true, nil, dist -- 거의 같은 수평 위치(바로 위/아래)
	end
	local allowance = 0
	if dist > 1e-6 then
		allowance = math.deg(math.asin(math.min(1, r / dist)))
	end
	if Vec.angleDeg(fwd, flatDelta) > arcDegrees / 2 + allowance then
		return false, "outside_arc", dist
	end
	return true, nil, dist
end

-- attacker = { pos, forward }, candidates = { {id, pos, radius?, alive?} }
-- params = { attackerId, range, arcDegrees, tolerance, maxTargets?, lineOfSight? }
function HitboxService.selectMeleeTargets(attacker, candidates, params)
	local found = {}
	for _, c in candidates do
		if c.id ~= params.attackerId and c.alive ~= false then
			local ok, _, dist = HitboxService.isInMeleeArc(
				attacker.pos, attacker.forward, c.pos, c.radius, params.range, params.arcDegrees, params.tolerance
			)
			if ok and (params.lineOfSight == nil or params.lineOfSight(attacker.pos, c.pos)) then
				table.insert(found, { id = c.id, dist = dist })
			end
		end
	end
	table.sort(found, function(a, b)
		if a.dist ~= b.dist then
			return a.dist < b.dist
		end
		return tostring(a.id) < tostring(b.id)
	end)
	local out = {}
	for i, f in found do
		if params.maxTargets and i > params.maxTargets then
			break
		end
		table.insert(out, f.id)
	end
	return out
end

-- 구형 범위. 반환: { {id, distance} } (거리는 대상 반지름만큼 보정)
function HitboxService.entitiesInRadius(center, radius, candidates, lineOfSight)
	local out = {}
	for _, c in candidates do
		if c.alive ~= false then
			local d = math.max(0, Vec.dist(center, c.pos) - (c.radius or 0))
			if d <= radius and (lineOfSight == nil or lineOfSight(center, c.pos)) then
				table.insert(out, { id = c.id, distance = d })
			end
		end
	end
	table.sort(out, function(a, b)
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		return tostring(a.id) < tostring(b.id)
	end)
	return out
end

-- 중심 1.0 → 가장자리 falloffMin 으로 선형 감소, 반경 밖은 0
function HitboxService.explosionMultiplier(distance, radius, falloffMin)
	if distance > radius then
		return 0
	end
	return 1 - (1 - falloffMin) * (distance / radius)
end

-- 근접 전용 약한 방향 보정: 가장 가까운 각도의 대상 쪽으로 최대 assistDegrees 회전. 콘 밖이면 그대로.
function HitboxService.assistedMeleeDirection(aimDir, pos, candidates, assistDegrees, excludeId, maxRange)
	local aim = Vec.normalize(aimDir)
	if not aim then
		return aimDir
	end
	local bestDir, bestAngle = nil, math.huge
	for _, c in candidates do
		if c.id ~= excludeId and c.alive ~= false then
			local d = Vec.sub(c.pos, pos)
			if Vec.len(d) <= maxRange then
				local a = Vec.angleDeg(aim, d)
				if a <= assistDegrees * 2 and a < bestAngle then
					bestAngle, bestDir = a, d
				end
			end
		end
	end
	if not bestDir then
		return aim
	end
	return Vec.rotateToward(aim, bestDir, assistDegrees)
end

-- 원거리 공격은 조준 보정을 하지 않는다(확정 규칙). 입력 방향 그대로.
function HitboxService.rangedDirection(aimDir)
	return Vec.normalize(aimDir) or aimDir
end

return HitboxService
