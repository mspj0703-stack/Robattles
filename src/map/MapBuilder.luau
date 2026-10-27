--!nonstrict
-- 레이아웃 → 실제 인스턴스 생성. Roblox API 는 env(주입) 뒤에 숨겨 CLI에서 가짜 env 로 멱등성을 테스트한다.
-- env 인터페이스:
--   env.clearExisting(rootName)              기존 BRICKYARD(및 태그된 잔여물)를 모두 제거
--   env.createFolder(name, parent) -> folder (parent=nil 이면 최상위 컨테이너)
--   env.createPart(spec, parent) -> part
local MapBuilder = {}

-- options.spawnLocations=true 면 스폰 마커를 SpawnLocation 으로 생성(단독 테스트 플레이용)
function MapBuilder.build(layout, cfg, env, options)
	options = options or {}
	env.clearExisting(cfg.RootName) -- 여러 번 생성해도 중복되지 않는다
	local root = env.createFolder(cfg.RootName, nil)
	local folders = { [""] = root }
	local function folderFor(path)
		if folders[path] then
			return folders[path]
		end
		local parentPath, name = string.match(path, "^(.*)/([^/]+)$")
		if not parentPath then
			parentPath, name = "", path
		end
		local f = env.createFolder(name, folderFor(parentPath))
		folders[path] = f
		return f
	end
	local count = 0
	local parts = {}
	for _, spec in layout.parts do
		local s = spec
		if options.spawnLocations and spec.group == "Spawns" then
			s = setmetatable({ className = "SpawnLocation" }, { __index = spec })
		end
		local p = env.createPart(s, folderFor(spec.group))
		parts[spec.group .. "/" .. spec.name] = p
		count += 1
	end
	return { root = root, partCount = count, parts = parts }
end

return MapBuilder
