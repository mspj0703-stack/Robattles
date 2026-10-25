--!nonstrict
-- 키 바인딩. 기본값은 Config에서 읽고, 플레이어 설정(overrides)으로 변경할 수 있다.
-- 실제 Enum.KeyCode / UserInputType 이름 검증은 클라이언트(3단계)에서 추가로 수행한다.
local Config = require(script.Parent.Config)

local Keybinds = {}

Keybinds.Actions = {
	"CameraToggle", "RunToggle", "Dodge", "Ultimate", "Primary", "Secondary", "Reload",
	"FreeLook", "Skill1", "Skill2", "Skill3", "Scoreboard",
}

-- 이동(WASD)·점프(Space)·취소(Escape)는 Roblox 기본 조작/시스템 키라 재지정할 수 없다.
Keybinds.Reserved = { W = true, A = true, S = true, D = true, Space = true, Escape = true }

function Keybinds.defaults(config)
	local c = config or Config
	return {
		CameraToggle = c.Camera.ToggleKey,
		RunToggle = c.Input.RunToggleKey,
		Dodge = c.Input.DodgeKey,
		Ultimate = c.Input.UltimateKey,
		Primary = c.Input.PrimaryButton,
		Secondary = c.Input.SecondaryButton,
		Reload = c.Input.ReloadKey,
		FreeLook = c.Input.FreeLookButton,
		Skill1 = c.Input.Skill1Key,
		Skill2 = c.Input.Skill2Key,
		Skill3 = c.Input.Skill3Key,
		Scoreboard = c.Input.ScoreboardKey,
	}
end

local function validKeyName(k)
	return type(k) == "string" and #k >= 1 and #k <= 24 and string.match(k, "^[A-Za-z0-9]+$") ~= nil
end

-- 반환: 병합된 바인딩 | nil, 오류 메시지. 알 수 없는 액션·잘못된 키 이름·중복 키는 거부.
function Keybinds.resolve(overrides, config)
	local binds = Keybinds.defaults(config)
	if overrides ~= nil then
		if type(overrides) ~= "table" then
			return nil, "overrides가 table 아님"
		end
		for action, key in overrides do
			if binds[action] == nil then
				return nil, "알 수 없는 액션: " .. tostring(action)
			end
			if not validKeyName(key) then
				return nil, "잘못된 키 이름: " .. tostring(key)
			end
			if Keybinds.Reserved[key] then
				return nil, "예약된 키(이동/점프/취소)는 지정할 수 없음: " .. key
			end
			binds[action] = key
		end
	end
	local seen = {}
	for _, action in Keybinds.Actions do
		local key = binds[action]
		if seen[key] then
			return nil, string.format("키 중복: %s (%s, %s)", key, seen[key], action)
		end
		seen[key] = action
	end
	return binds, nil
end

return Keybinds
