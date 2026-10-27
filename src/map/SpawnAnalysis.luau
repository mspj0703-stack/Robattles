--!nonstrict
-- 스폰 정적 분석(순수 로직): 시야 노출도, 가장 가까운 엄폐물 거리, 선분-직육면체 교차(시야 판정).
-- 전투 쪽 스폰 위험도 계산(SpawnRisk)이 읽을 수 있는 정적 데이터를 만든다.
local SpawnAnalysis = {}

-- 선분 p0→p1 이 직육면체 b 와 교차하는가 (slab 방식)
function SpawnAnalysis.segmentHitsBox(p0, p1, b)
	local tmin, tmax = 0, 1
	for _, ax in { "X", "Y", "Z" } do
		local d = p1[ax] - p0[ax]
		if math.abs(d) < 1e-9 then
			if p0[ax] < b.min[ax] or p0[ax] > b.max[ax] then
				return false
			end
		else
			local t1: number = (b.min[ax] - p0[ax]) / d
			local t2: number = (b.max[ax] - p0[ax]) / d
			if t1 > t2 then t1, t2 = t2, t1 end
			tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
			if tmin > tmax then
				return false
			end
		end
	end
	return true
end

function SpawnAnalysis.solids(layout)
	local list = {}
	for _, p in layout.parts do
		if p.solid then table.insert(list, p) end
	end
	return list
end

-- 두 점 사이가 고체에 막히지 않았는가
function SpawnAnalysis.lineOfSight(solids, a, b)
	for _, s in solids do
		if SpawnAnalysis.segmentHitsBox(a, b, s) then
			return false
		end
	end
	return true
end

local EYE = 2.5

-- 16방향 수평 광선(눈 높이)이 maxLen 안에서 막히는 길이. 노출도 = 길이가 openLen 이상인 방향 비율
function SpawnAnalysis.exposure(solids, pos, opts)
	opts = opts or {}
	local maxLen, openLen, n = opts.maxLen or 60, opts.openLen or 25, 16
	local open, nearest = 0, math.huge
	local eye = { X = pos.X, Y = pos.Y + EYE, Z = pos.Z }
	for k = 0, n - 1 do
		local a = k * 2 * math.pi / n
		local e = { X = eye.X + math.cos(a) * maxLen, Y = eye.Y, Z = eye.Z + math.sin(a) * maxLen }
		-- 가장 가까운 교차 거리를 이분 탐색 없이 샘플링으로 근사(0.5 간격)
		local hitLen = maxLen
		local t = 0.5
		while t <= maxLen do
			local q = { X = eye.X + math.cos(a) * t, Y = eye.Y, Z = eye.Z + math.sin(a) * t }
			local blocked = false
			for _, s in solids do
				if q.X >= s.min.X and q.X <= s.max.X and q.Y >= s.min.Y and q.Y <= s.max.Y and q.Z >= s.min.Z and q.Z <= s.max.Z then
					blocked = true
					break
				end
			end
			if blocked then
				hitLen = t
				break
			end
			t += 0.5
		end
		if hitLen >= openLen then open += 1 end
		nearest = math.min(nearest, hitLen)
	end
	return { exposure = open / n, nearestCover = nearest == math.huge and maxLen or nearest }
end

-- 레이아웃의 모든 스폰에 Exposure / NearestCover 속성을 기록한다(부품 attributes 포함).
function SpawnAnalysis.annotate(layout, opts)
	local solids = SpawnAnalysis.solids(layout)
	for _, sp in layout.spawns do
		local r = SpawnAnalysis.exposure(solids, sp.pos, opts)
		sp.exposure, sp.nearestCover = r.exposure, r.nearestCover
		sp.part.attributes.Exposure = r.exposure
		sp.part.attributes.NearestCover = r.nearestCover
	end
	return layout
end

return SpawnAnalysis
