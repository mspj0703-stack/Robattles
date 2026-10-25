--!nonstrict
-- 순수 벡터 헬퍼. {X,Y,Z} 테이블과 Vector3 둘 다 입력으로 받고 항상 테이블을 반환한다(CLI 테스트 가능).
local Vec = {}

function Vec.new(x, y, z)
	return { X = x, Y = y, Z = z }
end
function Vec.add(a, b)
	return { X = a.X + b.X, Y = a.Y + b.Y, Z = a.Z + b.Z }
end
function Vec.sub(a, b)
	return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }
end
function Vec.scale(a, k)
	return { X = a.X * k, Y = a.Y * k, Z = a.Z * k }
end
function Vec.dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function Vec.len(a)
	return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
end
function Vec.dist(a, b)
	return Vec.len(Vec.sub(a, b))
end
function Vec.normalize(a)
	local l = Vec.len(a)
	if l < 1e-9 then
		return nil
	end
	return Vec.scale(a, 1 / l)
end
function Vec.flatten(a)
	return Vec.normalize({ X = a.X, Y = 0, Z = a.Z })
end
function Vec.angleDeg(a, b)
	local na, nb = Vec.normalize(a), Vec.normalize(b)
	if not na or not nb then
		return 0
	end
	return math.deg(math.acos(math.clamp(Vec.dot(na, nb), -1, 1)))
end

-- from 방향에서 to 방향으로 최대 maxDeg만큼 회전한 단위 벡터
function Vec.rotateToward(from, to, maxDeg)
	local na, nb = Vec.normalize(from), Vec.normalize(to)
	if not na then
		return nb
	end
	if not nb then
		return na
	end
	local theta = math.acos(math.clamp(Vec.dot(na, nb), -1, 1))
	local maxRad = math.rad(maxDeg)
	if theta <= maxRad then
		return nb
	end
	if theta > math.pi - 1e-4 then
		return na
	end
	local t = maxRad / theta
	local s = math.sin(theta)
	local w1 = math.sin((1 - t) * theta) / s
	local w2 = math.sin(t * theta) / s
	return Vec.normalize(Vec.add(Vec.scale(na, w1), Vec.scale(nb, w2)))
end

return Vec
