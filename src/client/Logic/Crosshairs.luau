--!nonstrict
-- 캐릭터별 조준선 확장 구조. 새 캐릭터는 register 한 번으로 고유 조준선을 추가한다.
local Crosshairs = {}

local registry = {
	DEFAULT = { style = "Dot", size = 6, spread = 0 },
	SWORD = { style = "Ring", size = 18, spread = 0 }, -- 임시 디자인 (미확정)
	PAINTBALL = { style = "Cross", size = 14, spread = 4 }, -- 임시 디자인 (미확정)
	TIMEBOMB = { style = "Cross", size = 14, spread = 8 }, -- 임시 디자인 (미확정)
	SLINGSHOT = { style = "Dot", size = 8, spread = 0 }, -- 임시 디자인 (미확정): 에임 보조 없음, 정밀 조준용 작은 점
	SUPERBALL = { style = "Ring", size = 16, spread = 6 }, -- 임시 디자인 (미확정)
}

function Crosshairs.register(characterId, def)
	if type(characterId) ~= "string" or type(def) ~= "table" or type(def.style) ~= "string" then
		return false
	end
	registry[characterId] = def
	return true
end

function Crosshairs.get(characterId)
	return registry[characterId] or registry.DEFAULT
end

return Crosshairs
