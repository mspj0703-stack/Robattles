--!nonstrict
-- 키 설정 편집 로직(순수). 검증은 공유 Keybinds.resolve 가 담당한다.
-- 영구 저장(DataStore/로컬)은 미구현이며 세션 동안만 유지된다(ASSUMPTIONS A45).
local Link = require(script.Parent.Parent.Link)
local Keybinds = Link.shared("Keybinds")

local KeybindSettings = {}
KeybindSettings.__index = KeybindSettings

function KeybindSettings.new(config)
	return setmetatable({ _config = config, _overrides = {}, binds = Keybinds.defaults(config) }, KeybindSettings)
end

-- 반환: ok, 오류 메시지. 실패하면 기존 바인딩을 그대로 유지한다.
function KeybindSettings:set(action, keyName)
	local trial = {}
	for k, v in self._overrides do
		trial[k] = v
	end
	trial[action] = keyName
	local binds, err = Keybinds.resolve(trial, self._config)
	if not binds then
		return false, err
	end
	self._overrides = trial
	self.binds = binds
	return true, nil
end

function KeybindSettings:reset(action)
	if action == nil then
		self._overrides = {}
	else
		self._overrides[action] = nil
	end
	self.binds = Keybinds.resolve(self._overrides, self._config)
end

function KeybindSettings:serialize()
	return self._overrides
end

-- 저장된 값을 불러올 때: 일부가 잘못돼도 전체를 기본값으로 안전하게 되돌린다.
function KeybindSettings:load(overrides)
	local binds = Keybinds.resolve(overrides, self._config)
	if not binds then
		self:reset()
		return false
	end
	self._overrides = overrides or {}
	self.binds = binds
	return true
end

return KeybindSettings
