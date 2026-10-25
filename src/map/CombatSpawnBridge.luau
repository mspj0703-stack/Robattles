--!nonstrict
-- 선택 사항(기본 비활성, Studio 미검증): 맵 Spawns 폴더 + SpawnRisk 로 캐릭터 스폰 위치를 고르는 연결 모듈.
-- 전투 코어 코드를 수정하지 않고, CharacterAdded 때 캐릭터를 옮기는 방식이다.
-- 전투 쪽이 자체 스폰 선택을 구현하면 이 모듈 대신 SpawnRegistry/SpawnRisk 를 직접 쓰면 된다.
-- 중복 설치 방지: install 은 이미 설치되어 있으면 기존 연결을 끊고 다시 연결한다.
local Players = game:GetService("Players")

local SpawnRegistry = require(script.Parent.SpawnRegistry)
local SpawnRisk = require(script.Parent.SpawnRisk)
local Config = require(script.Parent.BrickyardConfig)

local Bridge = {}

local connections = {}
local recent = {}

function Bridge.uninstall()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	table.clear(recent)
end

local function enemiesOf(player)
	local list = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Character then
			local hum = p.Character:FindFirstChildOfClass("Humanoid")
			local hrp = p.Character:FindFirstChild("HumanoidRootPart")
			if hum and hrp and hum.Health > 0 then
				table.insert(list, { pos = { X = hrp.Position.X, Y = hrp.Position.Y - 3, Z = hrp.Position.Z }, alive = true })
			end
		end
	end
	return list
end

function Bridge.install(options)
	options = options or {}
	Bridge.uninstall()
	local function place(player, character)
		local hrp = character:WaitForChild("HumanoidRootPart", 5)
		if not hrp then
			return
		end
		local spawns = SpawnRegistry.active((SpawnRegistry.fromWorkspace(Config.RootName)))
		if #spawns == 0 then
			return
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore = {}
		for _, p in Players:GetPlayers() do
			if p.Character then table.insert(ignore, p.Character) end
		end
		params.FilterDescendantsInstances = ignore
		local pick = SpawnRisk.pick(spawns, enemiesOf(player), {
			recent = recent,
			los = function(a, b)
				local from, to = Vector3.new(a.X, a.Y, a.Z), Vector3.new(b.X, b.Y, b.Z)
				return workspace:Raycast(from, to - from, params) == nil
			end,
			topN = options.topN, rng = options.topN and function(lo, hi) return math.random(lo, hi) end or nil,
		})
		if pick then
			recent = { [pick.id] = true }
			local s = pick.spawn
			local pos = Vector3.new(s.pos.X, s.pos.Y + 3.2, s.pos.Z)
			character:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(s.facing.X, 0, s.facing.Z)))
		end
	end
	table.insert(connections, Players.PlayerAdded:Connect(function(player)
		table.insert(connections, player.CharacterAdded:Connect(function(ch) place(player, ch) end))
	end))
	for _, player in Players:GetPlayers() do
		table.insert(connections, player.CharacterAdded:Connect(function(ch) place(player, ch) end))
	end
end

return Bridge
