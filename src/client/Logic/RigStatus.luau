--!nonstrict
-- R6 리그 준비 상태 판정 (순수 로직, CLI 테스트 가능).
-- CharacterId 속성이 관절보다 먼저 복제될 수 있으므로 "아직 준비 안 됨(pending)"과 "영구 미지원(unsupported, R15 등)"을 구분한다.
--   ready       : Humanoid 가 R6 이고 필요한 Motor6D 가 모두 있다.
--   pending     : Humanoid 가 아직 없거나, R6 인데 관절이 일부 없다 → 자식이 추가되면 재시도한다(제한 시간 있음).
--   unsupported : Humanoid 가 있고 RigType 이 R6 가 아니다 → 재시도하지 않는다(기존 애니메이션 유지).
local RigStatus = {}

RigStatus.MAX_WAIT = 10 -- 관절이 이 시간(초) 안에 준비되지 않으면 재시도를 포기한다

-- info = { hasHumanoid = bool, rigType = "R6"|"R15"|nil, missingJoints = number }
function RigStatus.classify(info)
	if type(info) ~= "table" or info.hasHumanoid ~= true then
		return "pending"
	end
	if info.rigType ~= "R6" then
		return "unsupported"
	end
	if (info.missingJoints or 0) > 0 then
		return "pending"
	end
	return "ready"
end

function RigStatus.shouldGiveUp(elapsed)
	return type(elapsed) ~= "number" or elapsed ~= elapsed or elapsed >= RigStatus.MAX_WAIT
end

return RigStatus
