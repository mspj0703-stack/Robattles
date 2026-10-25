--!nonstrict
-- 맵의 Spawns 폴더 계약(전투 스폰 시스템이 읽는 형식). 순수 정규화 + Roblox 폴더 읽기.
--
-- Spawns 폴더의 각 부품(BasePart) 속성:
--   SpawnId: string ("S01"~"S20")   SpawnIndex: number   SpawnKind: "Ground" | "Roof"
--   Zone: string                    Height: number (발이 닿는 바닥 높이, y)
--   Enabled: boolean (옥상 스폰 비활성화 시 false)
--   FacingYaw: number (도, 0 = -Z)  Facing: Vector3 (수평 단위 벡터)
--   Exposure: number (0~1, 정적 시야 노출도)  NearestCover: number (가장 가까운 엄폐물까지 거리)
-- 위치 = 부품 Position 의 X,Z + Height.
local SpawnRegistry = {}

local REQUIRED = { "SpawnId", "SpawnKind", "Zone", "Height", "Enabled", "FacingYaw" }

-- records: [{ x, z, attrs = { SpawnId=..., ... } }] → 정규화된 목록(ID 순). 불완전한 항목은 errors 로 반환.
function SpawnRegistry.normalize(records)
	local list, errors, seen = {}, {}, {}
	for i, r in records do
		local a = r.attrs or {}
		local missing = {}
		for _, k in REQUIRED do
			if a[k] == nil then table.insert(missing, k) end
		end
		if #missing > 0 then
			table.insert(errors, string.format("#%d 누락 속성: %s", i, table.concat(missing, ",")))
		elseif seen[a.SpawnId] then
			table.insert(errors, "ID 중복: " .. a.SpawnId)
		elseif type(r.x) ~= "number" or type(r.z) ~= "number" then
			table.insert(errors, a.SpawnId .. " 위치 없음")
		else
			seen[a.SpawnId] = true
			local f = a.Facing
			table.insert(list, {
				id = a.SpawnId, index = a.SpawnIndex, kind = a.SpawnKind, zone = a.Zone, enabled = a.Enabled == true,
				pos = { X = r.x, Y = a.Height, Z = r.z }, height = a.Height, yawDeg = a.FacingYaw,
				facing = f and { X = f.X, Y = f.Y, Z = f.Z } or nil,
				exposure = a.Exposure or 0, nearestCover = a.NearestCover or 0,
			})
		end
	end
	table.sort(list, function(x, y) return x.id < y.id end)
	return list, errors
end

-- 활성 스폰만 (옥상 스폰 비활성화 설정 반영)
function SpawnRegistry.active(list)
	local out = {}
	for _, s in list do
		if s.enabled then table.insert(out, s) end
	end
	return out
end

-- Roblox: BRICKYARD/Spawns 폴더 읽기 (Studio 미검증)
function SpawnRegistry.fromFolder(folder)
	local records = {}
	for _, p in folder:GetChildren() do
		if p:IsA("BasePart") then
			table.insert(records, { x = p.Position.X, z = p.Position.Z, attrs = p:GetAttributes() })
		end
	end
	return SpawnRegistry.normalize(records)
end

-- Roblox: 맵 루트에서 Spawns 폴더를 찾아 읽기 (Studio 미검증)
function SpawnRegistry.fromWorkspace(rootName)
	local root = workspace:FindFirstChild(rootName or "BRICKYARD")
	local folder = root and root:FindFirstChild("Spawns")
	if not folder then
		return {}, { "BRICKYARD/Spawns 없음" }
	end
	return SpawnRegistry.fromFolder(folder)
end

return SpawnRegistry
