--!nonstrict
-- 서버 공용 순수 기하 헬퍼(Phase 2 캐릭터 모듈용). 판정은 서버가 가진 위치로만 한다.
local Link = require(script.Parent.Link)
local Vec = Link.shared("Vec")

local Geometry = {}

-- 선분 p0→p1 이 구(c, R)와 처음 만나는 비율 f∈[0,1]. 시작점이 이미 안이면 0. 만나지 않으면 nil.
function Geometry.segmentSphere(p0, p1, c, R)
	local d = Vec.sub(p1, p0)
	local m = Vec.sub(p0, c)
	local cc = Vec.dot(m, m) - R * R
	if cc <= 0 then
		return 0
	end
	local a = Vec.dot(d, d)
	if a < 1e-12 then
		return nil
	end
	local b = Vec.dot(m, d)
	local disc = b * b - a * cc
	if disc < 0 then
		return nil
	end
	local f = (-b - math.sqrt(disc)) / a
	if f < 0 or f > 1 then
		return nil
	end
	return f
end

function Geometry.lerp(p0, p1, f)
	return { X = p0.X + (p1.X - p0.X) * f, Y = p0.Y + (p1.Y - p0.Y) * f, Z = p0.Z + (p1.Z - p0.Z) * f }
end

-- 점-선분 3D 거리
function Geometry.distToSegment(p, a, b)
	local ab = Vec.sub(b, a)
	local len2 = Vec.dot(ab, ab)
	local t = 0
	if len2 > 1e-9 then
		t = math.clamp(Vec.dot(Vec.sub(p, a), ab) / len2, 0, 1)
	end
	return Vec.dist(p, Vec.add(a, Vec.scale(ab, t)))
end

-- 조준 방향 기준 직교 기저(right, up). 거의 수직이면 X 축 기준.
function Geometry.basis(dir)
	local d = Vec.normalize(dir) or { X = 0, Y = 0, Z = 1 }
	local right = Vec.cross(d, { X = 0, Y = 1, Z = 0 })
	right = Vec.normalize(right) or { X = 1, Y = 0, Z = 0 }
	local up = Vec.normalize(Vec.cross(right, d)) or { X = 0, Y = 1, Z = 0 }
	return d, right, up
end

-- dir 을 yaw/pitch 도(오른쪽/위 방향) 만큼 틀어 단위 벡터로 반환
function Geometry.spread(dir, yawDeg, pitchDeg)
	local d, right, up = Geometry.basis(dir)
	local out = Vec.add(d, Vec.add(Vec.scale(right, math.tan(math.rad(yawDeg))), Vec.scale(up, math.tan(math.rad(pitchDeg)))))
	return Vec.normalize(out) or d
end

return Geometry
