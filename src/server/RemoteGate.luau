--!nonstrict
-- RemoteEvent 서버 진입 관문. 핸들러는 check()를 통과한 요청만 처리한다.
-- deps: { cooldown, getState(playerId) -> { alive, pos, serverTime, character? } | nil, config? }
local Link = require(script.Parent.Link)
local RemoteSpec = Link.shared("RemoteSpec")
local Hitbox = require(script.Parent.HitboxService)

local RemoteGate = {}
RemoteGate.__index = RemoteGate

function RemoteGate.new(deps)
	return setmetatable({
		_cfg = deps.config or Link.shared("Config"),
		_cooldown = deps.cooldown,
		_getState = deps.getState,
	}, RemoteGate)
end

-- 반환: ok, reason
function RemoteGate:check(playerId, remoteName, payload, now)
	if type(remoteName) ~= "string" or RemoteSpec.Remotes[remoteName] == nil then
		return false, "unknown_remote"
	end
	if not self._cooldown:allowRequest(playerId, remoteName, now) then
		return false, "rate_limited"
	end
	local ok, err = RemoteSpec.validate(remoteName, payload)
	if not ok then
		return false, "invalid_payload: " .. tostring(err)
	end
	local state = self._getState(playerId)
	if not state then
		return false, "no_character"
	end
	if not state.alive then
		return false, "dead"
	end
	local net = self._cfg.Net
	if payload.clientTime ~= nil and math.abs(payload.clientTime - state.serverTime) > net.MaxClientTimeSkew then
		return false, "time_skew"
	end
	if payload.aimOrigin ~= nil then
		local originOk = Hitbox.validateOrigin(payload.aimOrigin, state.pos, net.MaxOriginDeviation)
		if not originOk then
			return false, "origin_mismatch"
		end
	end
	if remoteName == "Reload" and not (state.character and state.character.ammo) then
		return false, "no_reload" -- 탄약이 없는 캐릭터는 재장전 불가
	end
	return true, nil
end

return RemoteGate
