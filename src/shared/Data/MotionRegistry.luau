--!nonstrict
-- SWORD 모션 레지스트리. 모션 id → 재생 방식. 순수 데이터 + 검증 함수(CLI 테스트 가능).
--
-- 정식 애니메이션 에셋으로 교체하는 방법(코드 수정 불필요):
--   1) 아래 Entries[id].assetId 에 "rbxassetid://..." 를 넣거나,
--   2) ReplicatedStorage.RoBattles.Assets.Animations.<모션 id> 에 Animation 인스턴스를 둔다(인스턴스가 우선).
-- 에셋이 지정된 모션은 절차적 포즈 출력이 꺼지고 Animator 트랙(Action 우선순위)이 재생된다.
-- 타이밍·우선순위·중단 규칙은 계속 SwordMotions 데이터와 SwordAnimState 가 관리한다.
local Motions = require(script.Parent.SwordMotions)

local Registry = {}

-- 에셋 교체 대상 목록. kind: Locomotion(절차 Idle/Run, 에셋 교체는 Animate 대체 필요) / Action
Registry.Entries = {
	Idle = { kind = "Locomotion", assetId = "" },
	Run = { kind = "Locomotion", assetId = "" },
	Slash1 = { kind = "Action", assetId = "" },
	Slash2 = { kind = "Action", assetId = "" },
	Slash3 = { kind = "Action", assetId = "" },
	TripleSlash1 = { kind = "Action", assetId = "" },
	TripleSlash2 = { kind = "Action", assetId = "" },
	TripleSlash3 = { kind = "Action", assetId = "" },
	LungeCharge = { kind = "Action", assetId = "" },
	LungeRelease = { kind = "Action", assetId = "" },
	LungeRecover = { kind = "Action", assetId = "" },
	BladeWave = { kind = "Action", assetId = "" },
	StormStart = { kind = "Action", assetId = "" },
	StormLoop = { kind = "Action", assetId = "" },
	StormFinisher = { kind = "Action", assetId = "" },
	StormRecover = { kind = "Action", assetId = "" },
	ParryGuard = { kind = "Action", assetId = "" },
	ParryCounter = { kind = "Action", assetId = "" },
}

Registry.Motions = Motions.Motions
Registry.Groups = Motions.Groups

function Registry.assetIdOf(id)
	local e = Registry.Entries[id]
	if e and type(e.assetId) == "string" and e.assetId ~= "" then
		return e.assetId
	end
	return nil
end

local JOINTS = { Root = true, Neck = true, RArm = true, LArm = true, RLeg = true, LLeg = true }
local FIELDS = { rx = true, ry = true, rz = true, px = true, py = true, pz = true }

local function badNumber(v)
	return type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge
end

local function keyJointSet(key)
	local names = {}
	for j in key.pose do
		table.insert(names, j)
	end
	table.sort(names)
	return table.concat(names, ",")
end

-- 레지스트리 검증. 문제 목록(문자열 배열)을 반환한다. 비어 있으면 통과.
function Registry.validate()
	local problems = {}
	local function add(msg)
		table.insert(problems, msg)
	end
	-- 요구 모션 10종 그룹의 모든 id 가 Entries 와 Motions(Locomotion 제외)에 있는가
	for group, ids in Registry.Groups do
		for _, id in ids do
			local entry = Registry.Entries[id]
			if entry == nil then
				add(string.format("그룹 %s: 레지스트리 항목 누락 %s", group, id))
			elseif entry.kind ~= "Locomotion" and Registry.Motions[id] == nil then
				add(string.format("그룹 %s: 모션 데이터 누락 %s", group, id))
			end
		end
	end
	for id, entry in Registry.Entries do
		if entry.kind ~= "Locomotion" and Registry.Motions[id] == nil then
			add("레지스트리에 있으나 모션 데이터 없음: " .. id)
		end
	end
	for id, def in Registry.Motions do
		if Registry.Entries[id] == nil then
			add("모션 데이터에 있으나 레지스트리 항목 없음: " .. id)
		end
		if type(def.priority) ~= "number" or def.priority < 1 or def.priority > 9 then
			add(id .. ": priority 비정상")
		end
		if badNumber(def.duration) or def.duration <= 0 then
			add(id .. ": duration 비정상")
		end
		if def.next ~= nil and Registry.Motions[def.next] == nil then
			add(id .. ": next 모션 없음 " .. tostring(def.next))
		end
		if def.hold and (badNumber(def.maxDuration) or def.maxDuration < def.duration) then
			add(id .. ": hold 모션은 maxDuration(≥duration) 필요 — 종료 이벤트가 유실돼도 정리되어야 함")
		end
		local keys = def.keys
		if type(keys) ~= "table" or #keys < 2 then
			add(id .. ": 키프레임 2개 이상 필요")
		else
			local prevT, firstSet, hasImpact = -1, nil, def.impact == nil
			for i, key in keys do
				if badNumber(key.t) or key.t < 0 or key.t > def.duration + 1e-6 then
					add(string.format("%s: 키 %d 시간 범위 밖", id, i))
				elseif key.t < prevT then
					add(string.format("%s: 키 %d 시간 역전", id, i))
				end
				prevT = key.t
				if def.impact ~= nil and math.abs(key.t - def.impact) < 1e-6 then
					hasImpact = true
				end
				local set = keyJointSet(key)
				firstSet = firstSet or set
				if set ~= firstSet then
					add(string.format("%s: 키 %d 관절 구성이 첫 키와 다름", id, i))
				end
				for j, jt in key.pose do
					if not JOINTS[j] then
						add(string.format("%s: 알 수 없는 관절 %s", id, j))
					end
					for f, v in jt do
						if not FIELDS[f] then
							add(string.format("%s: 알 수 없는 필드 %s.%s", id, j, f))
						elseif badNumber(v) then
							add(string.format("%s: %s.%s 숫자 비정상", id, j, f))
						end
					end
				end
			end
			if not hasImpact then
				add(id .. ": impact 시각에 해당하는 키프레임 없음")
			end
		end
	end
	return problems
end

return Registry
