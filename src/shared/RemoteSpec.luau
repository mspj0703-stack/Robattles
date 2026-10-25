--!strict
-- 클라이언트 → 서버 RemoteEvent 정의와 페이로드 검증. 서버는 이 모듈을 통과한 입력만 처리한다.
-- 클라이언트가 피해량이나 명중 대상을 보내는 필드는 의도적으로 존재하지 않는다.

local Schema = require(script.Parent.Schema)
local Config = require(script.Parent.Config)

local RemoteSpec = {}

local unitDir = Schema.vector3({ unit = true, tolerance = Config.Net.MaxAimDirectionError })

RemoteSpec.Remotes = {
	-- 공격 의사만 전달한다. 피해·명중·쿨타임은 서버가 결정한다.
	Attack = Schema.object({
		action = Schema.oneOf({ "Primary", "Secondary" }),
		-- phase: 생략 = 즉시 발사. 충전형 주무기(SUPERBALL Super Throw)만 "Press"(충전 시작)/"Release"(던지기)를 보낸다.
		phase = Schema.optional(Schema.oneOf({ "Press", "Release" })),
		aimOrigin = Schema.vector3(),
		aimDirection = unitDir,
		clientTime = Schema.number({ min = 0 }),
	}),
	-- 숫자 1·2·3 일반 스킬. 구현되지 않은 캐릭터 스킬은 서버가 skill_not_implemented 로 거부한다.
	-- phase: 생략 = "Press". 충전형 스킬(SWORD Lunge)만 키를 뗄 때 "Release" 를 보낸다(서버가 충전 중인지 검증).
	Skill = Schema.object({
		slot = Schema.oneOf({ 1, 2, 3 }),
		phase = Schema.optional(Schema.oneOf({ "Press", "Release" })),
		aimOrigin = Schema.vector3(),
		aimDirection = unitDir,
		clientTime = Schema.number({ min = 0 }),
	}),
	-- 시전 중 조준 갱신(PAINTBALL Color Break 빔 등). 서버가 해당 캐릭터의 지속 시전 중일 때만 사용하고 그 외에는 무시한다.
	Aim = Schema.object({
		aimOrigin = Schema.vector3(),
		aimDirection = unitDir,
		clientTime = Schema.number({ min = 0 }),
	}),
	Reload = Schema.object({}),
	Dodge = Schema.object({
		direction = unitDir,
	}),
	Ultimate = Schema.object({
		aimOrigin = Schema.optional(Schema.vector3()),
		aimDirection = Schema.optional(unitDir),
	}),
	-- 캐릭터 선택: 다음 리스폰부터 적용(확정 규칙). 현재는 Phase 1 테스트 캐릭터만 허용.
	SelectCharacter = Schema.object({
		characterId = Schema.oneOf({ "SWORD", "PAINTBALL", "SUPERBALL" }), -- 구현 단계마다 추가(TIMEBOMB·SLINGSHOT)
	}),
	SetRun = Schema.object({
		enabled = Schema.boolean(),
	}),
}

-- 반환: ok, 오류 메시지. 알 수 없는 리모트 이름도 거부한다.
function RemoteSpec.validate(remoteName: any, payload: any): (boolean, string?)
	if type(remoteName) ~= "string" then
		return false, "리모트 이름이 string 아님"
	end
	local spec = RemoteSpec.Remotes[remoteName]
	if spec == nil then
		return false, "알 수 없는 리모트: " .. remoteName
	end
	return Schema.validate(spec, payload)
end

return RemoteSpec
