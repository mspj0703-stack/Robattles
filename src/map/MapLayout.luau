--!nonstrict
-- BRICKYARD 레이아웃 생성(순수 로직, Roblox API 없음). 설정 → 직육면체 목록.
-- 결과는 결정적이다(같은 설정 → 같은 결과). 실제 Part 생성은 MapBuilder 가 담당한다.
local DefaultConfig = require(script.Parent.BrickyardConfig)

local MapLayout = {}

local CORNERS = {
	{ id = "PP", sx = 1, sz = 1 },
	{ id = "PN", sx = 1, sz = -1 },
	{ id = "NN", sx = -1, sz = -1 },
	{ id = "NP", sx = -1, sz = 1 },
}
MapLayout.Corners = CORNERS

local function color(c)
	return { c[1], c[2], c[3] }
end

local function newPart(list, used, spec)
	local path = spec.group .. "/" .. spec.name
	assert(not used[path], "중복 부품 이름: " .. path)
	used[path] = true
	spec.pos = {
		X = (spec.min.X + spec.max.X) / 2,
		Y = (spec.min.Y + spec.max.Y) / 2,
		Z = (spec.min.Z + spec.max.Z) / 2,
	}
	spec.size = { X = spec.max.X - spec.min.X, Y = spec.max.Y - spec.min.Y, Z = spec.max.Z - spec.min.Z }
	table.insert(list, spec)
	return spec
end

function MapLayout.generate(cfg)
	cfg = cfg or DefaultConfig
	local half = cfg.MapSize / 2
	local ph = cfg.PlazaSize / 2
	local S = cfg.Style
	local B = cfg.Building
	local St = B.Stair
	local parts, used = {}, {}

	local function add(group, name, x0, x1, y0, y1, z0, z1, col, extra)
		local spec = {
			name = name, group = group,
			min = { X = math.min(x0, x1), Y = math.min(y0, y1), Z = math.min(z0, z1) },
			max = { X = math.max(x0, x1), Y = math.max(y0, y1), Z = math.max(z0, z1) },
			color = color(col), material = S.Material, solid = true, canCollide = true, transparency = 0,
			attributes = {},
		}
		if extra then
			for k, v in extra do
				spec[k] = v
			end
		end
		return newPart(parts, used, spec)
	end

	-- 지면: 광장 + 둘레 4조각(윗면 모두 y=0, 서로 겹치지 않음)
	local gt = cfg.GroundThickness
	add("Ground", "Plaza", -ph, ph, -gt, 0, -ph, ph, S.Plaza)
	add("Ground", "South", -half, half, -gt, 0, ph, half, S.Ground)
	add("Ground", "North", -half, half, -gt, 0, -half, -ph, S.Ground)
	add("Ground", "West", -half, -ph, -gt, 0, -ph, ph, S.Ground)
	add("Ground", "East", ph, half, -gt, 0, -ph, ph, S.Ground)

	-- 외곽 벽(겹침 방지를 위해 동서 벽은 남북 벽 사이만)
	local pt, pH = cfg.Perimeter.Thickness, cfg.Perimeter.Height
	add("Perimeter", "South", -half, half, 0, pH, half - pt, half, S.Perimeter)
	add("Perimeter", "North", -half, half, 0, pH, -half, -half + pt, S.Perimeter)
	add("Perimeter", "West", -half, -half + pt, 0, pH, -half + pt, half - pt, S.Perimeter)
	add("Perimeter", "East", half - pt, half, 0, pH, -half + pt, half - pt, S.Perimeter)

	-- 광장 엄폐물
	for _, c in cfg.PlazaCover do
		add("Cover", c.id, c.x - c.sx / 2, c.x + c.sx / 2, 0, c.sy, c.z - c.sz / 2, c.z + c.sz / 2, S.Cover)
	end

	-- 건물
	local WH, RT = B.WallHeight, B.RoofThickness
	local roofTop = WH + RT
	local Bh = B.Size / 2
	local I = Bh - B.WallThickness
	local WT = B.WallThickness
	local DW2 = B.DoorWidth / 2
	local buildings = {}

	-- 계단 파라미터(건물 로컬, 모든 건물 동일)
	local steps = math.ceil(roofTop / St.Rise - 1e-9)
	local sx0 = -I + St.StartMargin
	local sz0, sz1 = I - St.Width, I
	-- 머리가 닿는 첫 단 번호(옥상 아래 여유 높이 < Agent.Height)
	local firstHeadStep = math.max(1, math.floor((WH - cfg.Agent.Height) / St.Rise + 1e-9) + 1)
	local hole = {
		x0 = sx0 + St.Run * (firstHeadStep - 1) - St.HoleMargin,
		x1 = sx0 + St.Run * steps,
		z0 = sz0 - St.HoleSideMargin,
		z1 = sz1,
	}

	-- 건물별 옥상 검증 지점: 그 건물의 첫 옥상 스폰(건물 로컬 좌표), 없으면 기본값
	local function roofProbe(corner, cx, cz)
		for _, sp in cfg.Spawns.Roof do
			if (sp.x >= 0) == (corner.sx > 0) and (sp.z >= 0) == (corner.sz > 0) then
				return { lx = corner.sx * (sp.x - cx), lz = corner.sz * (sp.z - cz) }
			end
		end
		return { lx = -1, lz = -6 }
	end

	for _, corner in CORNERS do
		local cx, cz = corner.sx * B.CenterOffset, corner.sz * B.CenterOffset
		local g = "Buildings/" .. corner.id
		local function lbox(sub, name, lx0, lx1, y0, y1, lz0, lz1, col, extra)
			local xa, xb = cx + corner.sx * lx0, cx + corner.sx * lx1
			local za, zb = cz + corner.sz * lz0, cz + corner.sz * lz1
			return add(g .. "/" .. sub, name, xa, xb, y0, y1, za, zb, col, extra)
		end

		-- 바깥쪽 벽(+X, +Z 로컬): 통짜
		lbox("Walls", "OuterX", I, Bh, 0, WH, -Bh, Bh, S.Wall)
		lbox("Walls", "OuterZ", -I, I, 0, WH, I, Bh, S.Wall)
		-- 안쪽 벽(-X, -Z 로컬): 중앙에 출입구
		lbox("Walls", "InnerX_A", -Bh, -I, 0, WH, -Bh, -DW2, S.Wall)
		lbox("Walls", "InnerX_B", -Bh, -I, 0, WH, DW2, Bh, S.Wall)
		lbox("Walls", "InnerX_Lintel", -Bh, -I, B.DoorHeight, WH, -DW2, DW2, S.Wall)
		lbox("Walls", "InnerZ_A", -I, -DW2, 0, WH, -Bh, -I, S.Wall)
		lbox("Walls", "InnerZ_B", DW2, I, 0, WH, -Bh, -I, S.Wall)
		lbox("Walls", "InnerZ_Lintel", -DW2, DW2, B.DoorHeight, WH, -Bh, -I, S.Wall)

		-- 옥상(계단 개구부 포함)
		lbox("Roof", "Slab_A", -Bh, Bh, WH, roofTop, -Bh, hole.z0, S.Roof)
		lbox("Roof", "Slab_B", -Bh, Bh, WH, roofTop, hole.z1, Bh, S.Roof)
		lbox("Roof", "Slab_C", -Bh, hole.x0, WH, roofTop, hole.z0, hole.z1, S.Roof)
		lbox("Roof", "Slab_D", hole.x1, Bh, WH, roofTop, hole.z0, hole.z1, S.Roof)

		-- 계단: 바깥 벽을 따라 로컬 +x 방향으로 한 단씩 상승(단은 바닥부터 쌓인 직육면체)
		for n = 1, steps do
			lbox("Stairs", string.format("Step_%02d", n), sx0 + St.Run * (n - 1), sx0 + St.Run * n, 0, n * St.Rise, sz0, sz1, S.Stair)
		end

		-- 옥상 엄폐물
		for _, c in B.RoofCover do
			lbox("RoofCover", c.id, c.lx - c.sx / 2, c.lx + c.sx / 2, roofTop, roofTop + c.sy, c.lz - c.sz / 2, c.lz + c.sz / 2, S.RoofCover)
		end

		buildings[corner.id] = {
			id = corner.id, sx = corner.sx, sz = corner.sz, cx = cx, cz = cz, roofTop = roofTop, steps = steps,
			stair = { x0 = sx0, z0 = sz0, z1 = sz1, rise = St.Rise, run = St.Run, width = St.Width, steps = steps },
			hole = hole, size = B.Size, roofProbe = roofProbe(corner, cx, cz),
			toWorld = function(lx, lz) return cx + corner.sx * lx, cz + corner.sz * lz end,
		}
	end

	-- 점프대: 이동 속도는 목표 지점까지 FlightTime 안에 도달하도록 탄도 계산
	local JP = cfg.JumpPad
	local jumpPads = {}
	for _, p in cfg.JumpPads do
		local bld = buildings[p.target]
		local tx, tz = bld.toWorld(p.lx, p.lz)
		local pad = add("JumpPads", p.id, p.x - JP.Size.X / 2, p.x + JP.Size.X / 2, 0, JP.Size.Y, p.z - JP.Size.Z / 2, p.z + JP.Size.Z / 2, S.JumpPad)
		local from = { X = p.x, Y = JP.Size.Y + JP.HrpHeight, Z = p.z }
		local to = { X = tx, Y = roofTop + JP.HrpHeight + JP.LandingBias, Z = tz }
		local T = JP.FlightTime
		local vel = {
			X = (to.X - from.X) / T,
			Y = (to.Y - from.Y + 0.5 * JP.Gravity * T * T) / T,
			Z = (to.Z - from.Z) / T,
		}
		pad.attributes.JumpPad = true
		pad.attributes.LaunchVelocity = vel
		pad.attributes.Cooldown = JP.Cooldown
		table.insert(jumpPads, { id = p.id, part = pad, from = from, to = to, velocity = vel, flightTime = T, gravity = JP.Gravity, target = p.target })
	end

	-- 스폰 후보(마커 부품, 충돌 없음). 정보: ID, 위치, 방향, 높이, 구역, 활성 여부
	local spawns = {}
	local function addSpawn(id, kind, zone, x, z, y, enabled, building, yawDeg)
		local n = #spawns + 1
		local fx, fz
		if yawDeg then
			-- yaw 0 = -Z(Roblox 전방), 양의 yaw = 왼쪽
			fx, fz = -math.sin(math.rad(yawDeg)), -math.cos(math.rad(yawDeg))
		else
			local len = math.sqrt(x * x + z * z)
			fx, fz = len > 1e-6 and -x / len or 0, len > 1e-6 and -z / len or -1
		end
		local yaw = math.deg(math.atan2(-fx, -fz)) % 360
		local part = add("Spawns", id, x - 2, x + 2, y, y + 0.4, z - 2, z + 2, S.Spawn, {
			solid = false, canCollide = false, transparency = S.SpawnTransparency,
			attributes = {
				SpawnId = id, SpawnIndex = n, SpawnKind = kind, Zone = zone, Height = y, Enabled = enabled,
				FacingYaw = yaw, Facing = { X = fx, Y = 0, Z = fz },
			},
		})
		table.insert(spawns, {
			id = id, index = n, kind = kind, zone = zone, enabled = enabled, building = building,
			pos = { X = x, Y = y, Z = z }, height = y, facing = { X = fx, Y = 0, Z = fz }, yawDeg = yaw, part = part,
		})
	end
	for _, sp in cfg.Spawns.Ground do
		addSpawn(sp.id, "Ground", sp.zone, sp.x, sp.z, 0, true, nil, sp.yaw)
	end
	for _, sp in cfg.Spawns.Roof do
		local bid = (sp.x >= 0 and "P" or "N") .. (sp.z >= 0 and "P" or "N") -- 코너 id = X부호 Z부호
		addSpawn(sp.id, "Roof", "Roof_" .. bid, sp.x, sp.z, sp.y or roofTop, cfg.Spawns.RoofEnabled == true, bid, sp.yaw)
	end

	local dummies = {}
	for i, d in cfg.Dummies do
		table.insert(dummies, { index = i, pos = { X = d.x, Y = 0, Z = d.z } })
	end

	return {
		cfg = cfg, half = half, parts = parts, buildings = buildings, jumpPads = jumpPads,
		spawns = spawns, dummies = dummies, roofTop = roofTop,
	}
end

return MapLayout
