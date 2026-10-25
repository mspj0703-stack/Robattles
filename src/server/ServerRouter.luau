--!nonstrict
-- RemoteEvent → 컨트롤러 연결. 모든 요청은 RemoteGate(스키마·빈도·상태·시각·원점 검증)를 먼저 통과해야 한다.
local ServerRouter = {}
ServerRouter.__index = ServerRouter

function ServerRouter.new(deps)
	return setmetatable({ _gate = deps.gate, _controller = deps.controller, _match = deps.match }, ServerRouter)
end

-- 반환: ok, info | reason
function ServerRouter:dispatch(playerId, remoteName, payload, now)
	if self._match then self._match:updatePhase(now) end
	local ok, reason = self._gate:check(playerId, remoteName, payload, now)
	if not ok then
		return false, reason
	end
	if self._match then
		local allowed, why = self._match.flow:canAct(playerId, remoteName, payload)
		if not allowed then return false, why end
		if remoteName == "SelectCharacter" then return self._match:select(playerId, payload.characterId, now) end
	end
	local c = self._controller
	if remoteName == "Attack" then
		return c:handleAttack(playerId, payload, now)
	elseif remoteName == "Skill" then
		return c:handleSkill(playerId, payload, now)
	elseif remoteName == "Aim" then
		return c:handleAim(playerId, payload, now)
	elseif remoteName == "Reload" then
		return c:handleReload(playerId, now)
	elseif remoteName == "Dodge" then
		return c:handleDodge(playerId, payload, now)
	elseif remoteName == "Ultimate" then
		return c:handleUltimate(playerId, payload, now)
	elseif remoteName == "SetRun" then
		return c:handleSetRun(playerId, payload.enabled)
	elseif remoteName == "SelectCharacter" then
		return true, c:selectCharacter(playerId, payload.characterId)
	end
	return false, "unhandled_remote"
end

return ServerRouter
