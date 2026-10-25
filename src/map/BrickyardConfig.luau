--!nonstrict
-- BRICKYARD 맵 설정. 맵 크기·좌표·색상은 전부 여기서 수정한다(전투 코어와 무관한 독립 설정).
-- 좌표계: 맵 중심이 원점(0,0,0), 지면 윗면이 y=0, 단위 studs. 맵은 X/Z로 ±MapSize/2.
-- 건물 로컬 좌표(lx,lz): 건물 중심 기준, +방향이 맵 모서리(바깥) 쪽. 4개 모서리에 부호를 곱해 대칭 배치한다.
-- 건물 ID: 부호 (+X,+Z)=PP, (+X,-Z)=PN, (-X,-Z)=NN, (-X,+Z)=NP
-- 표시된 ASSUMPTION Mxx 항목은 확정되지 않은 임시값이며 docs/ASSUMPTIONS.md 에 기록한다.

local Config = {
	RootName = "BRICKYARD",

	MapSize = 180, -- 확정: 180×180 studs
	GroundThickness = 4, -- ASSUMPTION M01
	PlazaSize = 76, -- 확정: 중앙 76×76 광장
	Perimeter = { Height = 20, Thickness = 2 }, -- ASSUMPTION M02: 외곽 벽(낙하 방지)

	-- 모서리 건물 4개 (1층 + 옥상 + 계단). ASSUMPTION M03: 세부 치수는 임시.
	-- 치수 근거(M09): 광장 끝 38 + 연결부 8 + 건물 26 + 외곽 주 통로 16 = 외곽 벽 안쪽 면 88
	Building = {
		Size = 26,
		CenterOffset = 59, -- 건물 중심의 |X|,|Z| (안쪽 면 46, 바깥 면 72)
		WallThickness = 2,
		WallHeight = 12,
		RoofThickness = 2, -- 옥상 윗면 = WallHeight + RoofThickness = 14 (확정 Y=14)
		DoorWidth = 8,
		DoorHeight = 9,
		Stair = {
			Rise = 1, -- 옥상 높이를 나누어떨어져야 함
			Run = 1.25,
			Width = 6,
			StartMargin = 3.5, -- 안쪽 벽에서 첫 단까지 여유(계단 앞에 서 있을 공간)
			HoleMargin = 2, -- 옥상 개구부를 머리 닿는 단보다 앞쪽으로 더 여는 길이
			HoleSideMargin = 1, -- 개구부를 계단 폭 바깥으로 더 여는 길이
		},
		-- 옥상 엄폐물(건물 로컬 좌표, 중심과 크기)
		RoofCover = {
			{ id = "RoofCoverA", lx = 5, lz = -6, sx = 3, sy = 4, sz = 8 },
			{ id = "RoofCoverB", lx = -7, lz = 1, sx = 8, sy = 4, sz = 3 },
		},
	},

	-- 중앙 광장 엄폐물(월드 좌표). ASSUMPTION M04
	PlazaCover = {
		{ id = "Center", x = 0, z = 0, sx = 10, sy = 6, sz = 10 },
		{ id = "WallE", x = 20, z = 0, sx = 3, sy = 6, sz = 12 },
		{ id = "WallW", x = -20, z = 0, sx = 3, sy = 6, sz = 12 },
		{ id = "WallN", x = 0, z = 20, sx = 12, sy = 6, sz = 3 },
		{ id = "WallS", x = 0, z = -20, sx = 12, sy = 6, sz = 3 },
		{ id = "BlockPP", x = 22, z = 22, sx = 6, sy = 4, sz = 6 },
		{ id = "BlockPN", x = 22, z = -22, sx = 6, sy = 4, sz = 6 },
		{ id = "BlockNN", x = -22, z = -22, sx = 6, sy = 4, sz = 6 },
		{ id = "BlockNP", x = -22, z = 22, sx = 6, sy = 4, sz = 6 },
	},

	-- 점프대 2개 (M05 개정): 광장 모서리 → 대각선 건물 옥상(Y=14). 비행 0.6초, 최고점은 발사 지점 +약 17.
	JumpPads = {
		{ id = "PadA", x = 33, z = 33, target = "PP", lx = -8, lz = -8 },
		{ id = "PadB", x = -33, z = -33, target = "NN", lx = -8, lz = -8 },
	},
	JumpPad = {
		Size = { X = 8, Y = 0.6, Z = 8 },
		FlightTime = 0.6, -- 초
		Gravity = 196.2, -- workspace.Gravity 기본값
		HrpHeight = 3, -- 발 → HumanoidRootPart 높이
		LandingBias = 0.5, -- 착지 목표를 옥상 위로 조금 띄움
		Cooldown = 0.6, -- 같은 플레이어 재발동 대기(초)
		-- 검증 한계
		MaxApexAboveLaunch = 20, -- 발사 지점 대비 최고점 상한
		MaxFlightTime = 0.8,
		MaxHorizontalDistance = 35,
		MinClearance = 1, -- 지나가는 구조물 위 최소 여유(몸통 외곽 확장)
	},

	-- 스폰 후보 20개 = 지상 16(S01~S16) + 옥상 4(S17~S20). 중앙 광장 내부에는 두지 않는다.
	-- 좌표 기준: 북쪽 = -Z, 남쪽 = +Z, 동쪽 = +X, 서쪽 = -X (맵 전체 통일). 원본 설계안 S01~S20 좌표를 그대로 적용했다(M07 개정).
	-- 모든 좌표는 월드 좌표다. yaw 를 생략하면 맵 중심을 바라본다(yaw 0 = -Z=북, 양수 = 왼쪽).
	-- 옥상(Roof)은 y 가 건물 옥상 윗면(14)과 일치해야 하며 어느 건물인지는 좌표 부호로 결정된다.
	-- 충돌/간격/도달성 문제는 MapValidator 가 보고하며, 수정한 좌표는 Adjusted 에 이유와 함께 기록한다.
	Spawns = {
		RoofEnabled = true, -- false 면 옥상 스폰(S17~S20)은 Enabled=false 로 표시되어 선택 대상에서 제외
		Ground = {
			{ id = "S01", zone = "Edge_W", x = -80, z = -30 }, { id = "S02", zone = "Edge_W", x = -80, z = 0 },
			{ id = "S03", zone = "Edge_W", x = -80, z = 30 },
			{ id = "S04", zone = "Edge_N", x = -30, z = -80 }, { id = "S05", zone = "Edge_N", x = 0, z = -80 },
			{ id = "S06", zone = "Edge_N", x = 30, z = -80 },
			{ id = "S07", zone = "Edge_E", x = 80, z = -30 }, { id = "S08", zone = "Edge_E", x = 80, z = 0 },
			{ id = "S09", zone = "Edge_E", x = 80, z = 30 },
			{ id = "S10", zone = "Edge_S", x = -30, z = 80 }, { id = "S11", zone = "Edge_S", x = 0, z = 80 },
			{ id = "S12", zone = "Edge_S", x = 30, z = 80 },
			{ id = "S13", zone = "Connector_NW", x = -40, z = -40 }, { id = "S14", zone = "Connector_NE", x = 40, z = -40 },
			{ id = "S15", zone = "Connector_SW", x = -40, z = 40 }, { id = "S16", zone = "Connector_SE", x = 40, z = 40 },
		},
		Roof = { -- 월드 좌표(y = 옥상 윗면)
			{ id = "S17", x = -60, y = 14, z = -60 }, { id = "S18", x = 60, y = 14, z = -60 },
			{ id = "S19", x = -60, y = 14, z = 60 }, { id = "S20", x = 60, y = 14, z = 60 },
		},
		Total = 20,
		-- 검증 후 원본 좌표에서 바꾼 항목 기록: { id = "Sxx", from = {x,z}, reason = "..." }
		Adjusted = {},
	},

	-- 테스트용 더미(월드 좌표, 지면). 광장 안.
	Dummies = { { x = 12, z = 12 }, { x = -12, z = 12 }, { x = -12, z = -12 }, { x = 12, z = -12 } },

	-- 구역별 폭 목표(M09). 외곽 주 통로 = 건물 바깥 면 ↔ 외곽 벽, 건물 연결부 = 광장 가장자리 ↔ 건물 안쪽 면.
	Zones = {
		OuterCorridor = { Min = 14, Max = 18 },
		Connector = { Min = 8, Max = 10 },
		MinDoorWidth = 6,
		StairApproachClearRadius = 1.5, -- 계단 진입 지점(첫 단 앞) 주변 여유 반지름
	},

	-- 검증 기준(플레이어 규격은 Roblox R15 기본에 맞춘 근사값). ASSUMPTION M06
	Agent = {
		Radius = 1,
		Height = 6,
		MaxStep = 1.5, -- 한 걸음 오를 수 있는 높이(계단 1단은 Rise)
		MinPassage = 5, -- 최소 통로 폭
		MinStairWidth = 5,
		MaxStairRise = 1.5,
		MinStairRun = 1.0,
		MinSpawnSpacing = 8,
		CellSize = 1,
		DodgeDistance = 14, -- 전투 코어 Dodge.Distance(A02)와 같은 값을 쓰지만 독립 복제본이다
		MinFreeDodgeDirections = 2, -- 스폰에서 8방향 중 회피 거리를 끝까지 갈 수 있는 방향 수 최소
		CombatRadius = 12, -- 교전 공간 평가 반경
		CombatMinArea = 200, -- 반경 내 같은 면에서 걸어갈 수 있는 넓이(studs²) 최소
		CombatClearRadius = 3, -- 3인이 서 있을 수 있는 여유 원 반지름 존재 여부
	},

	-- 자동 실행 스크립트 기본값 (통합 시 SpawnLocations=false 권장)
	AutoRun = { Enabled = true, Dummies = true, SpawnLocations = true },

	-- 클래식 Roblox 스타일: 기본 Plastic 재질, 회색 계열(회색 블록아웃). 색은 RGB.
	Style = {
		Material = "Plastic",
		Ground = { 163, 162, 165 }, -- Medium stone grey
		Plaza = { 99, 95, 98 }, -- Dark stone grey
		Perimeter = { 99, 95, 98 },
		Wall = { 229, 228, 223 }, -- Light stone grey
		Roof = { 163, 162, 165 },
		Stair = { 196, 196, 196 },
		Cover = { 131, 130, 133 },
		RoofCover = { 131, 130, 133 },
		JumpPad = { 13, 105, 172 }, -- Bright blue (식별용 유일한 강조색)
		Spawn = { 75, 151, 75 },
		SpawnTransparency = 0.6,
	},
}

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local c = {}
	for k, x in v do
		c[k] = deepCopy(x)
	end
	return c
end

local function isArray(t)
	return type(t) == "table" and #t > 0
end

local function merge(base, over)
	for k, v in over do
		if type(v) == "table" and type(base[k]) == "table" and not isArray(v) then
			merge(base[k], v)
		else
			base[k] = deepCopy(v) -- 배열과 값은 통째로 교체
		end
	end
end

-- 기본 설정을 복사해 overrides 를 덮어쓴 새 설정을 돌려준다(원본 불변).
function Config.with(overrides)
	local c = deepCopy(Config)
	c.with = nil
	c.copy = nil
	if overrides then
		merge(c, overrides)
	end
	return c
end

function Config.copy()
	return Config.with(nil)
end

return Config
