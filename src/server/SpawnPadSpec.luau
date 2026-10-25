--!nonstrict
-- 서버 소유 스폰 패드(SpawnLocation)의 필수 설정과 RespawnLocation 유효성 판단 (순수 로직 + Roblox 적용 헬퍼).
-- 핵심: Duration=0 으로 Roblox 기본 ForceField 를 만들지 않는다. 부활 보호 2초는 서버 DamageService 만이 관리한다.
-- (SpawnLocation.Duration 의 기본값/0 의 의미는 공식 문서에 명시되어 있지 않다 — Studio 에서 확인 필요, 그래서 ForceField 제거 안전망도 둔다.)
local SpawnPadSpec = {}

SpawnPadSpec.Props = {
	Duration = 0, -- 명시: ForceField 없음
	Neutral = true, -- 어떤 팀/무팀 플레이어도 사용 가능
	Enabled = true,
	AllowTeamChangeOnTouch = false,
	Anchored = true,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	Transparency = 1,
}

-- info: { isSpawnLocation, inWorkspace, enabled, neutral, duration }. 반환 ok, problems(문자열 목록)
function SpawnPadSpec.validate(info)
	local problems = {}
	if type(info) ~= "table" then
		return false, { "info 없음" }
	end
	if info.isSpawnLocation ~= true then
		table.insert(problems, "SpawnLocation 이 아님")
	end
	if info.inWorkspace ~= true then
		table.insert(problems, "Workspace 하위가 아님")
	end
	if info.enabled ~= true then
		table.insert(problems, "Enabled=false")
	end
	if info.neutral ~= true then
		table.insert(problems, "Neutral=false")
	end
	if info.duration ~= 0 then
		table.insert(problems, "Duration~=0 (ForceField 가능)")
	end
	return #problems == 0, problems
end

-- Roblox 전용: 패드 인스턴스에서 info 읽기 / 규격 적용 / ForceField 제거
function SpawnPadSpec.inspect(pad)
	if pad == nil then
		return { isSpawnLocation = false, inWorkspace = false }
	end
	return {
		isSpawnLocation = pad:IsA("SpawnLocation"),
		inWorkspace = pad:IsDescendantOf(workspace),
		enabled = pad.Enabled,
		neutral = pad.Neutral,
		duration = pad.Duration,
	}
end

function SpawnPadSpec.apply(pad)
	for k, v in SpawnPadSpec.Props do
		pad[k] = v
	end
end

-- ForceField 분류(순수). "strip" = 엔진 스폰 보호로 명확히 식별되어 제거, "report" = 식별 불가라 제거하지 않고 경고만, "keep" = 대상 아님/보존.
-- 엔진 스폰 ForceField 로 식별하려면 모두 만족해야 한다: 스폰 직후 창 안 / 기본 이름("ForceField") / 속성·태그 없음 / 서버 관리 표시 없음.
-- 하나라도 어긋나면(다른 이름, 속성·태그 있음, 창 이후) 의도된 보호 효과일 수 있으므로 제거하지 않는다. (Duration=0 이면 엔진 ForceField 는 생기지 않아야 한다 — Studio 미검증)
function SpawnPadSpec.classifyForceField(info)
	if info.isForceField ~= true or info.managed == true then
		return "keep"
	end
	if info.sinceSpawn == nil or info.sinceSpawn < 0 or info.sinceSpawn > info.windowSeconds then
		return "keep"
	end
	if info.name == "ForceField" and info.hasAttributes ~= true and info.tagged ~= true then
		return "strip"
	end
	return "report"
end

function SpawnPadSpec.shouldStripForceField(info)
	return SpawnPadSpec.classifyForceField(info) == "strip"
end

SpawnPadSpec.ManagedAttribute = "RoBattlesManaged"

-- Roblox 전용: 스폰 직후 짧은 시간 동안만 엔진이 붙인 ForceField 를 제거한다. 연결을 반환(창이 끝나면 자동으로 끊긴다).
function SpawnPadSpec.guardForceField(character, windowSeconds, onRemoved)
	local startedAt = os.clock()
	local function check(inst)
		local verdict = SpawnPadSpec.classifyForceField({
			isForceField = inst:IsA("ForceField"),
			managed = inst:GetAttribute(SpawnPadSpec.ManagedAttribute) == true,
			name = inst.Name,
			hasAttributes = next(inst:GetAttributes()) ~= nil,
			tagged = #game:GetService("CollectionService"):GetTags(inst) > 0,
			sinceSpawn = os.clock() - startedAt,
			windowSeconds = windowSeconds,
		})
		if verdict == "strip" then
			inst:Destroy()
			if onRemoved then
				onRemoved("removed")
			end
		elseif verdict == "report" and onRemoved then
			onRemoved("reported") -- 제거하지 않음: 의도된 보호 효과일 수 있어 경고만
		end
	end
	for _, c in character:GetChildren() do
		check(c)
	end
	local conn
	conn = character.ChildAdded:Connect(function(inst)
		if os.clock() - startedAt > windowSeconds then
			conn:Disconnect()
			return
		end
		check(inst)
	end)
	task.delay(windowSeconds + 0.1, function()
		if conn.Connected then
			conn:Disconnect()
		end
	end)
	return conn
end

return SpawnPadSpec
