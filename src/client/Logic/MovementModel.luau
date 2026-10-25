--!nonstrict
-- 이동·회피의 클라이언트 측 순수 로직. 서버가 상태의 주인이며 클라이언트는 확인된 값만 따른다.
local Link = require(script.Parent.Parent.Link)
local Config = Link.shared("Config")
local Vec = Link.shared("Vec")

local MovementModel = {}

-- 서버가 보낸 moveSpeed를 클라이언트가 그대로 따르되, 비정상 값은 안전 범위로 제한한다.
function MovementModel.clampSpeed(serverSpeed, config)
	local cfg = config or Config
	if type(serverSpeed) ~= "number" or serverSpeed ~= serverSpeed then
		return cfg.Movement.WalkSpeed
	end
	return math.clamp(serverSpeed, 0, cfg.Movement.RunSpeed)
end

-- 회피 방향: 이동 입력이 있으면 카메라 기준 입력 방향, 없으면 캐릭터 후방(뒤로 회피). 수평 단위 벡터.
function MovementModel.dodgeDirection(moveVec, cameraLook, cameraRight, characterForward)
	local dir
	if moveVec and (moveVec.x ~= 0 or moveVec.z ~= 0) then
		local fwd = Vec.flatten(cameraLook) or characterForward
		dir = Vec.add(Vec.scale(fwd, moveVec.z), Vec.scale(cameraRight, moveVec.x))
	else
		dir = Vec.scale(characterForward, -1)
	end
	return Vec.flatten(dir) or Vec.flatten(Vec.scale(characterForward, -1)) or { X = 0, Y = 0, Z = 1 }
end

-- 서버가 Dodge 이벤트로 확인해 준 뒤에만 이동을 적용한다.
-- 시작 시각 이후 경과 시간에 따른 목표 변위 속도(스터드/초)를 반환. 회피 시간이 끝나면 nil.
-- distance: 서버가 확정한 회피 거리(벽에 막혔다면 기본값보다 짧다). 생략하면 설정값.
function MovementModel.dodgeVelocity(startTime, direction, now, config, distance)
	local cfg = config or Config
	local d = cfg.Dodge
	if now < startTime or now >= startTime + d.Duration then
		return nil
	end
	local dist = distance
	if type(dist) ~= "number" or dist ~= dist then
		dist = d.Distance
	end
	dist = math.clamp(dist, 0, d.Distance)
	if dist <= 0 then
		return nil
	end
	return Vec.scale(direction, dist / d.Duration)
end

-- SWORD 돌진/전진(Triple Slash, Lunge): 서버가 SwordSkill 이벤트로 확정한 속도·시간만 따른다(서버 이동 허가와 같은 값).
-- 반환: 수평 속도 벡터 또는 nil(시간이 끝났거나 값이 비정상). 상한은 허가 상한(Config.MoveCheck.Permits)으로 제한한다.
function MovementModel.dashVelocity(startTime, direction, speed, duration, now, config)
	local cfg = config or Config
	if type(startTime) ~= "number" or type(speed) ~= "number" or type(duration) ~= "number" or type(direction) ~= "table" then
		return nil
	end
	if speed ~= speed or duration ~= duration or speed <= 0 or duration <= 0 then
		return nil
	end
	if now < startTime or now >= startTime + math.min(duration, 1.5) then
		return nil
	end
	local dir = Vec.flatten(direction)
	if not dir then
		return nil
	end
	local cap = 0
	for _, kind in { "Lunge", "TripleSlash" } do -- SWORD 전진/돌진 허가 상한만 기준(넉백 등 다른 허가는 제외)
		local p = cfg.MoveCheck.Permits[kind]
		if p then
			cap = math.max(cap, p.maxSpeed)
		end
	end
	return Vec.scale(dir, math.min(speed, cap))
end

-- 내 SwordSkill 이벤트 중 이동을 동반한 것만 수용(최근·중복 아님)
function MovementModel.acceptDashEvent(event, myId, now, lastAcceptedTime, maxAge)
	if type(event) ~= "table" or event.type ~= "SwordSkill" or event.playerId ~= myId or type(event.dash) ~= "table" then
		return false
	end
	if type(event.time) ~= "number" or now - event.time > (maxAge or 1) then
		return false
	end
	if lastAcceptedTime and event.time <= lastAcceptedTime then
		return false
	end
	return true
end

-- 서버 위치 보정 수용 판단. 반환 "snap" | "ignore".
-- 서버가 보낸 Correct 이벤트는 최근(maxAge 초)일 때만 따르며, 이미 수용한 시각 이전 것은 무시한다.
function MovementModel.acceptCorrection(event, now, lastAcceptedTime, maxAge)
	if type(event) ~= "table" or event.type ~= "Correct" or type(event.pos) ~= "table" then
		return "ignore"
	end
	if type(event.time) ~= "number" or now - event.time > (maxAge or 1) then
		return "ignore"
	end
	if lastAcceptedTime and event.time <= lastAcceptedTime then
		return "ignore"
	end
	for _, k in { "X", "Y", "Z" } do
		local v = event.pos[k]
		if type(v) ~= "number" or v ~= v or math.abs(v) > 1e5 then
			return "ignore"
		end
	end
	return "snap"
end

-- 서버에서 확인된 회피 이벤트만 수용: 내 playerId, 최근 이벤트, 중복 아님.
function MovementModel.acceptDodgeEvent(event, myId, now, lastAcceptedTime, maxAge)
	if type(event) ~= "table" or event.type ~= "Dodge" or event.playerId ~= myId then
		return false
	end
	if type(event.time) ~= "number" then
		return false
	end
	if now - event.time > (maxAge or 1) then
		return false
	end
	if lastAcceptedTime and event.time <= lastAcceptedTime then
		return false
	end
	return true
end

return MovementModel
