--!nonstrict
-- 스폰 위험도(순수 로직). 전투 쪽이 적 위치 목록과 시야 함수(Raycast 등)를 주입하면 점수를 계산한다.
-- 점수가 낮을수록 안전하다. 가중치는 임시값이며 확정 기획의 스폰 위험도 공식으로 교체한다(ASSUMPTION M12).
local SpawnRisk = {}

local DEFAULTS = {
	radius = 40, -- 이 거리 안의 적만 위험으로 계산
	hiddenFactor = 0.4, -- 시야가 막힌 적의 가중치 배율
	exposureWeight = 0.5, -- 정적 노출도 가중치
	recentSpawnPenalty = 1.0, -- 직전에 사용한 스폰 감점(재사용 방지)
}

-- enemies: [{ pos = {X,Y,Z}, alive = bool? }]
-- opts: { radius, hiddenFactor, exposureWeight, los = function(a,b)->bool, recent = {[id]=true} }
function SpawnRisk.evaluate(spawns, enemies, opts)
	opts = opts or {}
	local o = {}
	for k, v in opts do o[k] = v end
	for k, v in DEFAULTS do
		if o[k] == nil then o[k] = v end
	end
	local out = {}
	for _, sp in spawns do
		if sp.enabled ~= false then
			local risk, near, count, visible = 0, math.huge, 0, 0
			local eye = { X = sp.pos.X, Y = sp.pos.Y + 2.5, Z = sp.pos.Z }
			for _, e in enemies do
				if e.alive ~= false then
					local d = math.sqrt((e.pos.X - sp.pos.X) ^ 2 + (e.pos.Y - sp.pos.Y) ^ 2 + (e.pos.Z - sp.pos.Z) ^ 2)
					near = math.min(near, d)
					if d < o.radius then
						count += 1
						local seen = true
						if o.los then
							seen = o.los(eye, { X = e.pos.X, Y = e.pos.Y + 2.5, Z = e.pos.Z }) == true
						end
						if seen then visible += 1 end
						local w = (1 - d / o.radius) ^ 2
						risk += w * (seen and 1 or o.hiddenFactor)
					end
				end
			end
			if count > 0 then
				risk += o.exposureWeight * (sp.exposure or 0) * (visible > 0 and 1 or 0.3)
			end
			if o.recent and o.recent[sp.id] then risk += o.recentSpawnPenalty end
			table.insert(out, { id = sp.id, spawn = sp, risk = risk, nearestEnemy = near == math.huge and nil or near, enemiesInRadius = count, visibleEnemies = visible })
		end
	end
	return out
end

-- 가장 안전한 스폰 선택. 동점이면 ID 순(결정적). opts.rng 가 있으면 상위 topN 중 무작위.
function SpawnRisk.pick(spawns, enemies, opts)
	local scored = SpawnRisk.evaluate(spawns, enemies, opts)
	if #scored == 0 then
		return nil
	end
	table.sort(scored, function(a, b)
		if math.abs(a.risk - b.risk) > 1e-9 then return a.risk < b.risk end
		return a.id < b.id
	end)
	local topN = opts and opts.topN or 1
	if opts and opts.rng and topN > 1 then
		return scored[opts.rng(1, math.min(topN, #scored))], scored
	end
	return scored[1], scored
end

return SpawnRisk
