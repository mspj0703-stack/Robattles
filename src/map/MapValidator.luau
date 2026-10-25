--!nonstrict
-- BRICKYARD 검증 도구(순수 로직). 플레이어 충돌·통로 폭·계단 접근성·스폰·점프대 궤적을 검사한다.
-- 한계: Roblox 물리(Humanoid 실제 계단 오르기, 충돌 캡슐)를 그대로 재현하지 않는 근사 모델이다.
-- 따라서 이 검증을 통과해도 Studio 실플레이 확인이 필요하다(docs/MAP_BRICKYARD.md 참고).
local MapValidator = {}

local EPS = 1e-6

local function overlapVolume(a, b)
	local dx = math.min(a.max.X, b.max.X) - math.max(a.min.X, b.min.X)
	local dy = math.min(a.max.Y, b.max.Y) - math.max(a.min.Y, b.min.Y)
	local dz = math.min(a.max.Z, b.max.Z) - math.max(a.min.Z, b.min.Z)
	if dx > EPS and dy > EPS and dz > EPS then
		return dx * dy * dz
	end
	return 0
end

local function solids(layout)
	local list = {}
	for _, p in layout.parts do
		if p.solid then
			table.insert(list, p)
		end
	end
	return list
end

local function pathOf(p)
	return p.group .. "/" .. p.name
end

-- ===== 격자 기반 보행 가능 면 그래프 =====
local Grid = {}
Grid.__index = Grid

function Grid.new(layout, cfg)
	local self = setmetatable({}, Grid)
	self.half = layout.half
	self.cell = cfg.Agent.CellSize
	self.n = math.floor(cfg.MapSize / self.cell + 0.5)
	self.A = cfg.Agent
	self.buckets = {}
	local n, cell, half = self.n, self.cell, self.half
	for _, b in solids(layout) do
		local i0 = math.max(0, math.floor((b.min.X + half) / cell + EPS))
		local i1 = math.min(n - 1, math.ceil((b.max.X + half) / cell - EPS) - 1)
		local j0 = math.max(0, math.floor((b.min.Z + half) / cell + EPS))
		local j1 = math.min(n - 1, math.ceil((b.max.Z + half) / cell - EPS) - 1)
		for i = i0, i1 do
			for j = j0, j1 do
				local k = j * n + i + 1
				local list = self.buckets[k]
				if not list then
					list = {}
					self.buckets[k] = list
				end
				table.insert(list, b)
			end
		end
	end
	self.nodes = {} -- [cellKey] = { y, ... }
	self.validCache = {}
	for j = 0, n - 1 do
		for i = 0, n - 1 do
			local k = j * n + i + 1
			local list = self.buckets[k]
			if list then
				local x, z = (i + 0.5) * cell - half, (j + 0.5) * cell - half
				local ys = {}
				for _, b in list do
					if x >= b.min.X - EPS and x <= b.max.X + EPS and z >= b.min.Z - EPS and z <= b.max.Z + EPS then
						local top = b.max.Y
						local dup = false
						for _, y in ys do
							if math.abs(y - top) < 0.01 then
								dup = true
								break
							end
						end
						if not dup then
							table.insert(ys, top)
						end
					end
				end
				table.sort(ys)
				if #ys > 0 then
					self.nodes[k] = ys
				end
			end
		end
	end
	return self
end

function Grid:cellOf(x, z)
	local i = math.floor((x + self.half) / self.cell)
	local j = math.floor((z + self.half) / self.cell)
	return i, j
end

-- 점 (x,z) 에서 높이 y 기준으로 몸통(두께 Height)을 막는 물체가 있는가
function Grid:blocked(x, y, z)
	if math.abs(x) > self.half or math.abs(z) > self.half then
		return true
	end
	local i, j = self:cellOf(x, z)
	i = math.clamp(i, 0, self.n - 1)
	j = math.clamp(j, 0, self.n - 1)
	local list = self.buckets[j * self.n + i + 1]
	if not list then
		return false
	end
	local A = self.A
	for _, b in list do
		if x >= b.min.X - EPS and x <= b.max.X + EPS and z >= b.min.Z - EPS and z <= b.max.Z + EPS then
			if b.max.Y > y + A.MaxStep + 0.05 and b.min.Y < y + A.Height - EPS then
				return true
			end
		end
	end
	return false
end

local RING = {}
for k = 0, 7 do
	RING[k + 1] = { math.cos(k * math.pi / 4), math.sin(k * math.pi / 4) }
end

function Grid:nodeValid(i, j, y, r)
	local key = (j * self.n + i + 1) .. ":" .. string.format("%.2f", y) .. ":" .. r
	local c = self.validCache[key]
	if c ~= nil then
		return c
	end
	local x, z = (i + 0.5) * self.cell - self.half, (j + 0.5) * self.cell - self.half
	local ok = not self:blocked(x, y, z)
	if ok then
		for _, d in RING do
			if self:blocked(x + d[1] * r, y, z + d[2] * r) then
				ok = false
				break
			end
		end
	end
	self.validCache[key] = ok
	return ok
end

function Grid:findNode(x, y, z)
	local i, j = self:cellOf(x, z)
	local ys = self.nodes[j * self.n + i + 1]
	if ys then
		for _, ny in ys do
			if math.abs(ny - y) < 0.1 then
				return { i = i, j = j, y = ny }
			end
		end
	end
	return nil
end

-- 너비 우선 탐색. planeOnly=true 면 같은 높이 면에서만 이동(통로 폭 검사용).
function Grid:reach(start, r, planeOnly, bound)
	local visited = {}
	local function key(nd) return (nd.j * self.n + nd.i + 1) .. ":" .. string.format("%.2f", nd.y) end
	if not start or not self:nodeValid(start.i, start.j, start.y, r) then
		return visited, key, 0, {}
	end
	local queue, head = { start }, 1
	visited[key(start)] = true
	local count = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		for di = -1, 1 do
			for dj = -1, 1 do
				if di ~= 0 or dj ~= 0 then
					local ni, nj = cur.i + di, cur.j + dj
					if ni >= 0 and nj >= 0 and ni < self.n and nj < self.n then
						local ys = self.nodes[nj * self.n + ni + 1]
						if ys then
							for _, ny in ys do
								local dy = math.abs(ny - cur.y)
								local okStep = (planeOnly and dy < 0.05) or (not planeOnly and dy <= self.A.MaxStep + 1e-6)
								if okStep then
									local nd = { i = ni, j = nj, y = ny }
									local kk = key(nd)
									local inBound = true
									if bound then
										local bx = (ni + 0.5) * self.cell - self.half - bound.x
										local bz = (nj + 0.5) * self.cell - self.half - bound.z
										inBound = bx * bx + bz * bz <= bound.radius * bound.radius
									end
									if inBound and not visited[kk] and self:nodeValid(ni, nj, ny, r) then
										visited[kk] = true
										count += 1
										table.insert(queue, nd)
									end
								end
							end
						end
					end
				end
			end
		end
	end
	return visited, key, count, queue
end

-- ===== 개별 검사 =====
local function check(report, name, ok, detail)
	table.insert(report.checks, { name = name, ok = ok, detail = detail })
	if not ok then
		report.ok = false
		table.insert(report.failures, name .. ": " .. detail)
	end
end

local function spawnNodeAt(grid, s)
	return grid:findNode(s.pos.X, s.pos.Y, s.pos.Z)
end

function MapValidator.checkSpec(layout, cfg, report)
	local half = layout.half
	local ph = cfg.PlazaSize / 2
	-- 지면이 맵 전체를 빈틈·겹침 없이 덮는지(면적 합)
	local area, plaza = 0, nil
	for _, p in layout.parts do
		if p.group == "Ground" then
			area += p.size.X * p.size.Z
			if p.name == "Plaza" then plaza = p end
			-- 윗면은 모두 y=0
			if math.abs(p.max.Y) > EPS then
				check(report, "지면 윗면 높이", false, pathOf(p) .. " 윗면 " .. p.max.Y)
			end
		end
	end
	check(report, "지면 면적 = 맵 크기²", math.abs(area - cfg.MapSize * cfg.MapSize) < 1e-6, string.format("합 %.1f / 기대 %.1f", area, cfg.MapSize * cfg.MapSize))
	check(report, "중앙 광장 크기", plaza ~= nil and math.abs(plaza.size.X - cfg.PlazaSize) < EPS and math.abs(plaza.size.Z - cfg.PlazaSize) < EPS and math.abs(plaza.pos.X) < EPS and math.abs(plaza.pos.Z) < EPS,
		plaza and string.format("%.1f×%.1f", plaza.size.X, plaza.size.Z) or "광장 없음")
	local nb = 0
	for _ in layout.buildings do nb += 1 end
	check(report, "모서리 건물 4개", nb == 4, tostring(nb))
	local covers, roofCovers = 0, 0
	for _, p in layout.parts do
		if p.group == "Cover" then covers += 1 end
		if string.find(p.group, "/RoofCover", 1, true) then roofCovers += 1 end
	end
	check(report, "중앙 엄폐물 존재", covers > 0, tostring(covers))
	check(report, "옥상 엄폐물 존재(건물마다)", roofCovers >= 4 and roofCovers % 4 == 0, tostring(roofCovers))
	check(report, "점프대 2개", #layout.jumpPads == 2, tostring(#layout.jumpPads))
	local nGround, nRoof, inPlaza, ids, dupId, incomplete = 0, 0, {}, {}, {}, {}
	for _, sp in layout.spawns do
		if sp.kind == "Ground" then nGround += 1 else nRoof += 1 end
		if math.abs(sp.pos.X) < ph and math.abs(sp.pos.Z) < ph then table.insert(inPlaza, sp.id) end
		if ids[sp.id] then table.insert(dupId, sp.id) end
		ids[sp.id] = true
		if not (sp.id and sp.pos and sp.facing and sp.height and sp.zone and sp.yawDeg ~= nil and sp.enabled ~= nil) then
			table.insert(incomplete, tostring(sp.id))
		end
	end
	check(report, "스폰 후보 개수(전체)", #layout.spawns == cfg.Spawns.Total, string.format("%d / %d", #layout.spawns, cfg.Spawns.Total))
	check(report, "외곽 지상 스폰 16개", nGround == 16, tostring(nGround))
	check(report, "옥상 스폰 4개", nRoof == 4, tostring(nRoof))
	check(report, "중앙 광장 내부 스폰 없음", #inPlaza == 0, table.concat(inPlaza, ", "))
	check(report, "스폰 ID 고유·정보(ID/위치/방향/높이/구역) 완비", #dupId == 0 and #incomplete == 0, table.concat(dupId, ",") .. table.concat(incomplete, ","))
	-- 모든 부품이 맵 경계 안
	local out = {}
	for _, p in layout.parts do
		if p.min.X < -half - EPS or p.max.X > half + EPS or p.min.Z < -half - EPS or p.max.Z > half + EPS then
			table.insert(out, pathOf(p))
		end
	end
	check(report, "모든 부품이 맵 경계 안", #out == 0, table.concat(out, ", "))
	-- 부품 이름 중복
	local seen, dup = {}, {}
	for _, p in layout.parts do
		local k = pathOf(p)
		if seen[k] then table.insert(dup, k) end
		seen[k] = true
	end
	check(report, "부품 경로 중복 없음", #dup == 0, table.concat(dup, ", "))
	-- 건물이 광장·외곽 벽과 겹치지 않는지는 겹침 검사에서 확인
	local B = cfg.Building
	check(report, "건물이 광장 밖", B.CenterOffset - B.Size / 2 >= ph, string.format("건물 안쪽 끝 %.1f ≥ 광장 끝 %.1f", B.CenterOffset - B.Size / 2, ph))
end

function MapValidator.checkOverlaps(layout, report)
	local s = solids(layout)
	local bad = {}
	for i = 1, #s do
		for j = i + 1, #s do
			if overlapVolume(s[i], s[j]) > 0 then
				table.insert(bad, pathOf(s[i]) .. " ∩ " .. pathOf(s[j]))
				if #bad >= 5 then break end
			end
		end
		if #bad >= 5 then break end
	end
	check(report, "고체 부품 겹침 없음", #bad == 0, table.concat(bad, "; "))
end

local function boxBody(x, y, z, r, h)
	return { min = { X = x - r, Y = y, Z = z - r }, max = { X = x + r, Y = y + h, Z = z + r } }
end

function MapValidator.checkSpawns(layout, cfg, report)
	local A = cfg.Agent
	local s = solids(layout)
	local bad, floor = {}, {}
	for _, sp in layout.spawns do
		local body = boxBody(sp.pos.X, sp.pos.Y + 0.05, sp.pos.Z, A.Radius, A.Height)
		for _, b in s do
			if overlapVolume(body, b) > 0 then
				table.insert(bad, sp.id .. " ∩ " .. pathOf(b))
				break
			end
		end
		-- 바닥 지지: 발 아래에 윗면이 spawn y 인 고체가 있는지
		local supported = false
		for _, b in s do
			if math.abs(b.max.Y - sp.pos.Y) < 0.01 and sp.pos.X >= b.min.X and sp.pos.X <= b.max.X and sp.pos.Z >= b.min.Z and sp.pos.Z <= b.max.Z then
				supported = true
				break
			end
		end
		if not supported then table.insert(floor, sp.id) end
	end
	check(report, "스폰 위치가 고체와 겹치지 않음", #bad == 0, table.concat(bad, "; "))
	check(report, "스폰 발 아래 바닥 존재", #floor == 0, table.concat(floor, ", "))
	local close = {}
	for i = 1, #layout.spawns do
		for j = i + 1, #layout.spawns do
			local a, b = layout.spawns[i].pos, layout.spawns[j].pos
			local d = math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2)
			if d < A.MinSpawnSpacing then
				table.insert(close, string.format("%s-%s(%.1f)", layout.spawns[i].id, layout.spawns[j].id, d))
			end
		end
	end
	check(report, "스폰 간 최소 간격", #close == 0, table.concat(close, ", "))
end

function MapValidator.checkStairs(layout, cfg, report)
	local A = cfg.Agent
	local s = solids(layout)
	local msgs = {}
	for id, b in layout.buildings do
		local st = b.stair
		if st.rise > A.MaxStairRise + EPS then table.insert(msgs, id .. " 계단 높이 " .. st.rise) end
		if st.run < A.MinStairRun - EPS then table.insert(msgs, id .. " 계단 깊이 " .. st.run) end
		if st.width < A.MinStairWidth - EPS then table.insert(msgs, id .. " 계단 폭 " .. st.width) end
		-- 마지막 단 윗면 = 옥상 윗면(턱 없음)
		if math.abs(st.steps * st.rise - b.roofTop) > 0.01 then
			table.insert(msgs, string.format("%s 마지막 단 %.2f ≠ 옥상 %.2f", id, st.steps * st.rise, b.roofTop))
		end
		-- 머리 여유: 각 단 중심에서 몸통(반지름 r, 높이 H)이 천장과 겹치지 않아야 함
		for n = 1, st.steps do
			local cxl = st.x0 + st.run * (n - 0.5)
			local czl = (st.z0 + st.z1) / 2
			local wx, wz = b.toWorld(cxl, czl)
			local body = boxBody(wx, n * st.rise + 0.05, wz, A.Radius, A.Height)
			for _, p in s do
				if string.find(p.group, id, 1, true) and not string.find(p.group, "/Stairs", 1, true) and overlapVolume(body, p) > 0 then
					table.insert(msgs, string.format("%s 단%d 머리 닿음(%s)", id, n, pathOf(p)))
					break
				end
			end
		end
	end
	check(report, "계단 규격·머리 여유", #msgs == 0, table.concat(msgs, "; "))
end

function MapValidator.checkReachability(layout, cfg, grid, report)
	local A = cfg.Agent
	local start = spawnNodeAt(grid, layout.spawns[1])
	local visited, key = grid:reach(start, A.Radius, false)
	local bad = {}
	for _, sp in layout.spawns do
		local nd = spawnNodeAt(grid, sp)
		if not nd or not visited[key(nd)] then
			table.insert(bad, string.format("%s(%s)", sp.id, sp.kind))
		end
	end
	check(report, "모든 스폰이 걸어서 도달 가능(반지름 " .. A.Radius .. ")", #bad == 0, table.concat(bad, ", "))
	-- 건물별 옥상 접근(계단 위쪽 끝 → 옥상 중앙)
	local roofBad = {}
	for id, b in layout.buildings do
		local wx, wz = b.toWorld(b.roofProbe.lx, b.roofProbe.lz)
		local nd = grid:findNode(wx, b.roofTop, wz)
		if not nd or not visited[key(nd)] then
			table.insert(roofBad, id)
		end
	end
	check(report, "계단으로 모든 옥상 접근 가능", #roofBad == 0, table.concat(roofBad, ", "))
end

-- 같은 높이 면에서 폭 MinPassage 로 연결되는지. 지상 스폰 전부, 옥상 스폰은 계단 출구에서 연결.
function MapValidator.checkPassageWidth(layout, cfg, grid, report)
	local A = cfg.Agent
	local r = A.MinPassage / 2
	local first = spawnNodeAt(grid, layout.spawns[1])
	local visited, key = grid:reach(first, r, true)
	local bad = {}
	for _, sp in layout.spawns do
		if sp.pos.Y < 0.05 then
			local nd = spawnNodeAt(grid, sp)
			if not nd or not visited[key(nd)] then
				table.insert(bad, string.format("%s(%s)", sp.id, sp.kind))
			end
		end
	end
	check(report, string.format("지상 통로 폭 ≥ %.1f 로 스폰 연결", A.MinPassage), #bad == 0, table.concat(bad, ", "))

	local roofBad = {}
	for id, b in layout.buildings do
		-- 계단 끝 바로 옆 옥상(개구부 뒤쪽 조각) 에서 출발
		local ex, ez = b.toWorld(b.hole.x1 + 1.5, (b.hole.z0 + b.hole.z1) / 2)
		local start = grid:findNode(ex, b.roofTop, ez)
		local vis, k2 = grid:reach(start, r, true)
		for _, sp in layout.spawns do
			if sp.kind == "Roof" and math.abs(sp.pos.X - b.cx) < cfg.Building.Size / 2 and math.abs(sp.pos.Z - b.cz) < cfg.Building.Size / 2 then
				local nd = spawnNodeAt(grid, sp)
				if not start or not nd or not vis[k2(nd)] then
					table.insert(roofBad, id)
				end
			end
		end
	end
	check(report, string.format("옥상 통로 폭 ≥ %.1f 로 계단 출구와 스폰 연결", A.MinPassage), #roofBad == 0, table.concat(roofBad, ", "))

	-- 달성 가능한 최대 통로 폭 보고(지상 스폰 전부 연결 유지하는 가장 큰 반지름)
	local best = 0
	for rr = 1, 4, 0.5 do
		local vis, kk = grid:reach(first, rr, true)
		local all = true
		for _, sp in layout.spawns do
			if sp.pos.Y < 0.05 then
				local nd = spawnNodeAt(grid, sp)
				if not nd or not vis[kk(nd)] then all = false break end
			end
		end
		if all then best = rr end
	end
	report.maxGroundPassage = best * 2
end

function MapValidator.checkJumpPads(layout, cfg, report)
	local A = cfg.Agent
	local J = cfg.JumpPad
	local s = solids(layout)
	local msgs = {}
	local summary = {}
	report.jumpPads = {}
	for _, jp in layout.jumpPads do
		local g, T = jp.gravity, jp.flightTime
		local v = jp.velocity
		local apexRel = v.Y > 0 and v.Y * v.Y / (2 * g) or 0
		local hdist = math.sqrt((jp.to.X - jp.from.X) ^ 2 + (jp.to.Z - jp.from.Z) ^ 2)
		local vyEnd = v.Y - g * T
		local steps = 60
		local hit, tight
		for k = 0, steps do
			local t = T * k / steps
			local px = jp.from.X + v.X * t
			local py = jp.from.Y + v.Y * t - 0.5 * g * t * t
			local pz = jp.from.Z + v.Z * t
			-- 몸통: 반지름 r, 발(py-3) ~ 머리(py+2.5)
			local body = { min = { X = px - A.Radius, Y = py - 3, Z = pz - A.Radius }, max = { X = px + A.Radius, Y = py + 2.5, Z = pz + A.Radius } }
			-- 여유 검사용 확장 몸통(출발 직후 0.12초와 착지 직전 0.05초는 발판/옥상 접촉 때문에 제외)
			local pad = J.MinClearance
			local fat = { min = { X = body.min.X - pad, Y = body.min.Y - pad, Z = body.min.Z - pad }, max = { X = body.max.X + pad, Y = body.max.Y + pad, Z = body.max.Z + pad } }
			for _, b in s do
				if not hit and overlapVolume(body, b) > 0 then
					hit = string.format("t=%.2f %s", t, pathOf(b))
				end
				if not tight and t > 0.12 and t < T - 0.05 and overlapVolume(fat, b) > 0 then
					tight = string.format("t=%.2f %s", t, pathOf(b))
				end
			end
		end
		if hit then table.insert(msgs, jp.id .. " 궤적 충돌 " .. hit) end
		if tight then table.insert(msgs, jp.id .. " 구조물과 여유 부족(<" .. J.MinClearance .. ") " .. tight) end
		local ex = jp.from.X + v.X * T
		local ey = jp.from.Y + v.Y * T - 0.5 * g * T * T
		local ez = jp.from.Z + v.Z * T
		if math.abs(ex - jp.to.X) > 0.3 or math.abs(ey - jp.to.Y) > 0.3 or math.abs(ez - jp.to.Z) > 0.3 then
			table.insert(msgs, string.format("%s 도착점 불일치 (%.1f,%.1f,%.1f)", jp.id, ex, ey, ez))
		end
		-- 착지 지점 아래 옥상 바닥(옥상 윗면 높이와 일치)과 엄폐물 비겹침
		local floorOk = false
		for _, b in s do
			if math.abs(b.max.Y - layout.roofTop) < 0.01 and string.find(b.group, "Buildings/" .. jp.target, 1, true) == 1 and string.find(b.group, "/Roof", 1, true)
				and ex - A.Radius >= b.min.X and ex + A.Radius <= b.max.X and ez - A.Radius >= b.min.Z and ez + A.Radius <= b.max.Z then
				floorOk = true
				break
			end
		end
		if not floorOk then table.insert(msgs, jp.id .. " 도착점 아래 옥상 바닥 없음") end
		local land = boxBody(ex, ey - 3 + 0.05, ez, A.Radius, A.Height)
		for _, b in s do
			if overlapVolume(land, b) > 0 and b.max.Y > layout.roofTop + 0.01 then
				table.insert(msgs, jp.id .. " 착지점이 엄폐물과 겹침: " .. pathOf(b))
				break
			end
		end
		-- 높이·체공 시간·수평 거리 한계
		if apexRel > J.MaxApexAboveLaunch + 1e-6 then table.insert(msgs, string.format("%s 최고점 +%.1f > %.1f", jp.id, apexRel, J.MaxApexAboveLaunch)) end
		if T > J.MaxFlightTime + 1e-6 then table.insert(msgs, string.format("%s 체공 %.2fs > %.2fs", jp.id, T, J.MaxFlightTime)) end
		if hdist > J.MaxHorizontalDistance + 1e-6 then table.insert(msgs, string.format("%s 수평 거리 %.1f > %.1f", jp.id, hdist, J.MaxHorizontalDistance)) end
		if math.abs(layout.roofTop - 14) > 1e-6 and cfg.Building.WallHeight + cfg.Building.RoofThickness == 14 then
			table.insert(msgs, jp.id .. " 옥상 높이 불일치")
		end
		local info = { id = jp.id, apexAbs = jp.from.Y + apexRel, apexRel = apexRel, flightTime = T, horizontal = hdist, landingY = ey, landingVy = vyEnd, launchSpeed = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z), landing = { X = ex, Y = ey, Z = ez } }
		table.insert(report.jumpPads, info)
		table.insert(summary, string.format("%s 수평 %.1f, 체공 %.2fs, 최고 Y=%.1f(+%.1f), 착지 (%.1f,%.1f,%.1f) 하강속도 %.0f", jp.id, hdist, T, info.apexAbs, apexRel, ex, ey, ez, -vyEnd))
	end
	check(report, "점프대 궤적(충돌·여유·착지·높이·체공)", #msgs == 0, #msgs > 0 and table.concat(msgs, "; ") or table.concat(summary, " | "))
end

-- 지정 점에서 축 방향으로 몸통 높이 대역을 막는 고체 사이의 자유 폭 측정
local function freeSpan(layout, cfg, x, z, axis)
	local A = cfg.Agent
	local lo, hi = A.MaxStep + 0.05, A.Height
	local left, right = -math.huge, math.huge
	for _, b in solids(layout) do
		if b.min.Y < hi and b.max.Y > lo then
			local c, cmin, cmax, o, omin, omax
			if axis == "X" then
				c, o = z, x
				cmin, cmax, omin, omax = b.min.Z, b.max.Z, b.min.X, b.max.X
			else
				c, o = x, z
				cmin, cmax, omin, omax = b.min.X, b.max.X, b.min.Z, b.max.Z
			end
			if c > cmin + EPS and c < cmax - EPS then
				if o > omin + EPS and o < omax - EPS then
					return 0, o, o
				end
				if omax <= o + EPS then left = math.max(left, omax) end
				if omin >= o - EPS then right = math.min(right, omin) end
			end
		end
	end
	return right - left, left, right
end
MapValidator.freeSpan = freeSpan

local function wallBounds(layout, id)
	local mn, mx
	for _, p in layout.parts do
		if string.find(p.group, "Buildings/" .. id .. "/Walls", 1, true) == 1 then
			mn = mn or { X = math.huge, Z = math.huge }
			mx = mx or { X = -math.huge, Z = -math.huge }
			mn.X, mn.Z = math.min(mn.X, p.min.X), math.min(mn.Z, p.min.Z)
			mx.X, mx.Z = math.max(mx.X, p.max.X), math.max(mx.Z, p.max.Z)
		end
	end
	return mn, mx
end

-- 구역별 폭: 외곽 주 통로(건물 바깥 면 ↔ 외곽 벽) 14~18, 건물 연결부(광장 가장자리 ↔ 건물 안쪽 면) 8~10, 출입구 폭
function MapValidator.checkZones(layout, cfg, report)
	local Z = cfg.Zones
	local plaza
	for _, p in layout.parts do
		if p.group == "Ground" and p.name == "Plaza" then plaza = p end
	end
	local ph = plaza.max.X
	local msgs, found = {}, {}
	report.zoneWidths = {}
	for id, b in layout.buildings do
		local mn, mx = wallBounds(layout, id)
		local innerX = b.sx > 0 and mn.X or -mx.X
		local outerX = b.sx > 0 and mx.X or -mn.X
		local innerZ = b.sz > 0 and mn.Z or -mx.Z
		local outerZ = b.sz > 0 and mx.Z or -mn.Z
		-- 외곽 주 통로: 건물 중간 높이 선에서 실제 고체 사이 폭 측정
		local midX = b.sx * (outerX + 1)
		local midZ = b.sz * (outerZ + 1)
		local wx = freeSpan(layout, cfg, midX, b.cz, "X")
		local wz = freeSpan(layout, cfg, b.cx, midZ, "Z")
		local cx_, cz_ = innerX - ph, innerZ - ph
		local entries = {
			{ id .. " 외곽 주 통로(X측)", wx, Z.OuterCorridor }, { id .. " 외곽 주 통로(Z측)", wz, Z.OuterCorridor },
			{ id .. " 건물 연결부(X측)", cx_, Z.Connector }, { id .. " 건물 연결부(Z측)", cz_, Z.Connector },
		}
		for _, e in entries do
			table.insert(report.zoneWidths, { name = e[1], width = e[2], min = e[3].Min, max = e[3].Max })
			if e[2] < e[3].Min - EPS or e[2] > e[3].Max + EPS then
				table.insert(msgs, string.format("%s %.1f ∉ [%g,%g]", e[1], e[2], e[3].Min, e[3].Max))
			end
		end
		-- 출입구 폭(두 면)
		local dx, dz = b.toWorld(-12, 0)
		local dw1 = freeSpan(layout, cfg, dx, dz, "Z")
		local ex, ez = b.toWorld(0, -12)
		local dw2 = freeSpan(layout, cfg, ex, ez, "X")
		table.insert(found, string.format("%s 문 %.1f/%.1f", id, dw1, dw2))
		if dw1 < Z.MinDoorWidth or dw2 < Z.MinDoorWidth then
			table.insert(msgs, string.format("%s 출입구 폭 %.1f/%.1f < %g", id, dw1, dw2, Z.MinDoorWidth))
		end
	end
	local sample = report.zoneWidths[1]
	check(report, string.format("구역 폭 목표(주 통로 %g~%g, 연결부 %g~%g, 출입구 ≥%g)", Z.OuterCorridor.Min, Z.OuterCorridor.Max, Z.Connector.Min, Z.Connector.Max, Z.MinDoorWidth),
		#msgs == 0, #msgs > 0 and table.concat(msgs, "; ") or string.format("주 통로 %.1f, 연결부 %.1f, %s", report.zoneWidths[1].width, report.zoneWidths[3].width, found[1]))
end

-- 건물 입구와 계단의 충돌 여유: 입구 밖 → 계단 진입점 → 첫 단 → 옥상 출구가 이어지고, 진입점 주변에 여유 원이 있어야 함
function MapValidator.checkStairEntrance(layout, cfg, grid, report)
	local A, Z = cfg.Agent, cfg.Zones
	local msgs = {}
	for id, b in layout.buildings do
		local st = b.stair
		local approach = { b.toWorld(st.x0 - 1.25, (st.z0 + st.z1) / 2) } -- 첫 단 앞
		local an = grid:findNode(approach[1], 0, approach[2])
		if not an or not grid:nodeValid(an.i, an.j, an.y, Z.StairApproachClearRadius) then
			table.insert(msgs, id .. " 계단 진입점 여유 반지름 " .. Z.StairApproachClearRadius .. " 부족")
		end
		local doors = { { -15, 0 }, { 0, -15 } }
		for k, d in doors do
			local wx, wz = b.toWorld(d[1], d[2])
			local start = grid:findNode(wx, 0, wz)
			local vis, key = grid:reach(start, A.Radius, false)
			local s1x, s1z = b.toWorld(st.x0 + st.run * 0.5, (st.z0 + st.z1) / 2)
			local step1 = grid:findNode(s1x, st.rise, s1z)
			local rx, rz = b.toWorld(b.roofProbe.lx, b.roofProbe.lz)
			local roof = grid:findNode(rx, b.roofTop, rz)
			if not start or not step1 or not vis[key(step1)] then table.insert(msgs, string.format("%s 문%d → 첫 단 도달 불가", id, k)) end
			if not roof or not vis[key(roof)] then table.insert(msgs, string.format("%s 문%d → 옥상 도달 불가", id, k)) end
		end
	end
	check(report, "건물 입구 ↔ 계단 충돌 여유·접근", #msgs == 0, table.concat(msgs, "; "))
end

-- 회피: 8방향 중 회피 거리를 벽 관통 없이 끝까지 이동할 수 있는 방향 수
local DIRS8 = {}
for k = 0, 7 do DIRS8[k + 1] = { math.cos(k * math.pi / 4), math.sin(k * math.pi / 4) } end

function MapValidator.dodgeFreeLength(layout, cfg, pos, dx, dz, maxLen)
	local A = cfg.Agent
	local s = solids(layout)
	local free = 0
	local t = 0
	while t < maxLen do
		t = math.min(maxLen, t + 0.5)
		local body = boxBody(pos.X + dx * t, pos.Y + 0.05, pos.Z + dz * t, A.Radius, A.Height)
		for _, b in s do
			-- 발 밑 낮은 단차(≤MaxStep)는 장애로 보지 않음
			if b.max.Y > pos.Y + A.MaxStep + 0.05 and overlapVolume(body, b) > 0 then
				return free
			end
		end
		free = t
	end
	return free
end

function MapValidator.checkDodge(layout, cfg, report)
	local A = cfg.Agent
	local bad = {}
	report.dodgeDirs = {}
	for _, sp in layout.spawns do
		local n = 0
		for _, d in DIRS8 do
			if MapValidator.dodgeFreeLength(layout, cfg, sp.pos, d[1], d[2], A.DodgeDistance) >= A.DodgeDistance - 0.01 then n += 1 end
		end
		report.dodgeDirs[sp.id] = n
		if n < A.MinFreeDodgeDirections then table.insert(bad, string.format("%s(%d방향)", sp.id, n)) end
	end
	check(report, string.format("스폰에서 회피(%g) 가능 방향 ≥ %d (벽 끼임 방지)", A.DodgeDistance, A.MinFreeDodgeDirections), #bad == 0, table.concat(bad, ", "))
end

-- 교전 공간: 스폰 주변 반경 내 같은 면에서 걸을 수 있는 넓이와, 3인이 설 수 있는 여유 원
function MapValidator.checkCombatSpace(layout, cfg, grid, report)
	local A = cfg.Agent
	local bad = {}
	report.combatArea = {}
	for _, sp in layout.spawns do
		local nd = spawnNodeAt(grid, sp)
		local _, _, count, list = grid:reach(nd, A.Radius, true, { x = sp.pos.X, z = sp.pos.Z, radius = A.CombatRadius })
		local clear = false
		for _, n in list do
			if grid:nodeValid(n.i, n.j, n.y, A.CombatClearRadius) then clear = true break end
		end
		report.combatArea[sp.id] = count
		if count * grid.cell * grid.cell < A.CombatMinArea or not clear then
			table.insert(bad, string.format("%s(넓이 %d, 여유원 %s)", sp.id, count, tostring(clear)))
		end
	end
	check(report, string.format("스폰 주변 교전 공간(반경 %g, 넓이 ≥%d, 여유 반지름 %g)", A.CombatRadius, A.CombatMinArea, A.CombatClearRadius), #bad == 0, table.concat(bad, ", "))
end

function MapValidator.checkDummies(layout, cfg, report)
	local A = cfg.Agent
	local s = solids(layout)
	local bad = {}
	for _, d in layout.dummies do
		local body = boxBody(d.pos.X, d.pos.Y + 0.05, d.pos.Z, A.Radius, A.Height)
		for _, b in s do
			if overlapVolume(body, b) > 0 then
				table.insert(bad, "Dummy" .. d.index)
				break
			end
		end
	end
	check(report, "더미 위치가 고체와 겹치지 않음", #bad == 0, table.concat(bad, ", "))
end

-- 전체 검증. 반환: { ok, checks, failures, maxGroundPassage }
function MapValidator.validate(layout, cfg)
	cfg = cfg or layout.cfg
	local report = { ok = true, checks = {}, failures = {} }
	MapValidator.checkSpec(layout, cfg, report)
	MapValidator.checkOverlaps(layout, report)
	MapValidator.checkSpawns(layout, cfg, report)
	MapValidator.checkStairs(layout, cfg, report)
	local grid = Grid.new(layout, cfg)
	MapValidator.checkReachability(layout, cfg, grid, report)
	MapValidator.checkPassageWidth(layout, cfg, grid, report)
	MapValidator.checkZones(layout, cfg, report)
	MapValidator.checkStairEntrance(layout, cfg, grid, report)
	MapValidator.checkDodge(layout, cfg, report)
	MapValidator.checkCombatSpace(layout, cfg, grid, report)
	MapValidator.checkJumpPads(layout, cfg, report)
	MapValidator.checkDummies(layout, cfg, report)
	return report
end

function MapValidator.format(report)
	local lines = {}
	for _, c in report.checks do
		table.insert(lines, string.format("[%s] %s%s", c.ok and "PASS" or "FAIL", c.name, (c.detail and c.detail ~= "") and (" — " .. c.detail) or ""))
	end
	if report.maxGroundPassage then
		table.insert(lines, string.format("보장되는 지상 통로 폭(스폰 전체 연결 유지): %.1f studs", report.maxGroundPassage))
	end
	return table.concat(lines, "\n")
end

MapValidator.Grid = Grid
return MapValidator
