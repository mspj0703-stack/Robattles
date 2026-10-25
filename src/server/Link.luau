--!nonstrict
-- 서버 모듈이 공유 모듈을 불러오는 유일한 통로. (CLI 테스트에서는 tools/run_tests.py가 교체한다.)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Link = {}

function Link.shared(path)
	local node = ReplicatedStorage:WaitForChild("RoBattles"):WaitForChild("Shared")
	for part in string.gmatch(path, "[^/]+") do
		node = node:WaitForChild(part)
	end
	return require(node)
end

return Link
