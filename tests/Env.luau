--!strict
-- Studio용 모듈 로더. (CLI 실행 시 tools/run_tests.py가 이 파일을 CLI용으로 교체한다.)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Env = {}

function Env.shared(path: string): any
	local node: Instance = ReplicatedStorage:WaitForChild("RoBattles"):WaitForChild("Shared")
	for part in string.gmatch(path, "[^/]+") do
		node = node:WaitForChild(part)
	end
	return require(node :: ModuleScript)
end

function Env.server(path: string): any
	local node: Instance = game:GetService("ServerScriptService"):WaitForChild("RoBattles")
	for part in string.gmatch(path, "[^/]+") do
		node = node:WaitForChild(part)
	end
	return require(node :: ModuleScript)
end

-- 맵 모듈(선택): 통합 프로젝트의 ServerScriptService.BrickyardMap
function Env.map(path: string): any
	local node: Instance = game:GetService("ServerScriptService"):WaitForChild("BrickyardMap")
	for part in string.gmatch(path, "[^/]+") do
		node = node:WaitForChild(part)
	end
	return require(node :: ModuleScript)
end

function Env.client(path: string): any
	local node: Instance = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("RoBattles")
	for part in string.gmatch(path, "[^/]+") do
		node = node:WaitForChild(part)
	end
	return require(node :: ModuleScript)
end

return Env
