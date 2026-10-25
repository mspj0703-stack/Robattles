--!nonstrict
-- 테스트 공용 헬퍼
local Helpers = {}

function Helpers.clone(t)
	local c = {}
	for k, v in t do
		c[k] = if type(v) == "table" then Helpers.clone(v) else v
	end
	return c
end

-- 체력 비교용(Phase 2): 캐릭터별 최대 체력이 달라져도 기존 "100 HP 기준 받은 피해" 단언을 유지하도록 100 기준으로 환산한 체력.
-- 사망(0)은 0 그대로. 캐릭터별 최대 체력 자체는 Hp.spec 이 따로 검증한다.
function Helpers.hp(core, id)
	local h = core.damage:getHealth(id)
	if h <= 0 then
		return 0
	end
	return h - (core.damage:getMaxHealth(id) - 100)
end

-- 공통 경로(구현 모듈이 없는 캐릭터) 회귀용 테스트 전용 캐릭터 GUNNER = Phase 1 의 옛 PAINTBALL 데이터(자동 연사 30발·재장전 1.8초·자리표시자 궁극기·스킬 없음).
-- PAINTBALL 이 Phase 2 에서 전용 모듈로 구현되면서, "스킬/궁극기 미구현 거부", 공통 사격/탄약/재장전 경로 같은 보안·회귀 검사를
-- 삭제하지 않고 이 캐릭터로 계속 검증한다. 실제 게임 데이터(Characters)에는 포함되지 않는다.
function Helpers.legacyChars(Characters)
	local c = {}
	for k, val in Characters do
		c[k] = val
	end
	c.GUNNER = {
		id = "GUNNER",
		displayName = "Gunner",
		primary = {
			kind = "Projectile", automatic = true, fireInterval = 0.12, damage = 4, moveSpeedMult = 0.9, stagger = false,
			projectile = {
				id = "gunner_pellet", type = "Linear", collision = { mode = "Spherecast", radius = 0.3 },
				speed = 220, gravity = 0, lifetime = 2, maxRange = 300, damage = 4, rehitInterval = 0,
			},
		},
		ammo = { magazine = 30, reloadSeconds = 1.8 },
		ultimate = { duration = 3, placeholder = true },
	}
	return c
end

function Helpers.v(x, y, z)
	return { X = x, Y = y or 0, Z = z or 0 }
end

-- 무한 평면 벽으로 이루어진 가짜 월드. planes = { {point = V3, normal = V3(방문 가능한 쪽을 향함)} }
function Helpers.fakeWorld(planes)
	local function dot(a, b)
		return a.X * b.X + a.Y * b.Y + a.Z * b.Z
	end
	local world = {}
	function world.cast(p0, p1, radius)
		local best
		for _, pl in planes do
			local d0 = dot(pl.normal, { X = p0.X - pl.point.X, Y = p0.Y - pl.point.Y, Z = p0.Z - pl.point.Z })
			local d1 = dot(pl.normal, { X = p1.X - pl.point.X, Y = p1.Y - pl.point.Y, Z = p1.Z - pl.point.Z })
			if d0 > radius and d1 <= radius then
				local f = (d0 - radius) / (d0 - d1)
				if best == nil or f < best.fraction then
					best = {
						fraction = f,
						position = { X = p0.X + (p1.X - p0.X) * f, Y = p0.Y + (p1.Y - p0.Y) * f, Z = p0.Z + (p1.Z - p0.Z) * f },
						normal = pl.normal,
					}
				end
			end
		end
		return best
	end
	function world.lineOfSight(a, b)
		for _, pl in planes do
			local da = dot(pl.normal, { X = a.X - pl.point.X, Y = a.Y - pl.point.Y, Z = a.Z - pl.point.Z })
			local db = dot(pl.normal, { X = b.X - pl.point.X, Y = b.Y - pl.point.Y, Z = b.Z - pl.point.Z })
			if (da > 0) ~= (db > 0) then
				return false
			end
		end
		return true
	end
	return world
end

-- 축 정렬 직육면체로 이루어진 가짜 월드(실제 BRICKYARD 레이아웃용). boxes: [{ min = V3, max = V3 }]
-- cast 는 구 반지름만큼 상자를 부풀려 첫 충돌을 반환한다(근사). 시작점이 상자 안이면 fraction 0.
function Helpers.boxWorld(boxes)
	local world = {}
	local function hit(p0, p1, b, r)
		local tmin, tmax = 0, 1
		for _, ax in { "X", "Y", "Z" } do
			local lo, hi = b.min[ax] - r, b.max[ax] + r
			local d = p1[ax] - p0[ax]
			if math.abs(d) < 1e-12 then
				if p0[ax] < lo or p0[ax] > hi then
					return nil
				end
			else
				local t1, t2 = (lo - p0[ax]) / d, (hi - p0[ax]) / d
				if t1 > t2 then t1, t2 = t2, t1 end
				tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
				if tmin > tmax then
					return nil
				end
			end
		end
		return tmin
	end
	function world.cast(p0, p1, radius)
		local best
		for _, b in boxes do
			local t = hit(p0, p1, b, radius)
			if t and (best == nil or t < best) then
				best = t
			end
		end
		if best == nil then
			return nil
		end
		return {
			fraction = best,
			position = { X = p0.X + (p1.X - p0.X) * best, Y = p0.Y + (p1.Y - p0.Y) * best, Z = p0.Z + (p1.Z - p0.Z) * best },
			normal = { X = 0, Y = 1, Z = 0 },
		}
	end
	function world.lineOfSight(a, b)
		return world.cast(a, b, 0) == nil
	end
	function world.inside(p, margin)
		for _, bx in boxes do
			if p.X > bx.min.X - margin and p.X < bx.max.X + margin and p.Y > bx.min.Y - margin and p.Y < bx.max.Y + margin and p.Z > bx.min.Z - margin and p.Z < bx.max.Z + margin then
				return true
			end
		end
		return false
	end
	return world
end

return Helpers
