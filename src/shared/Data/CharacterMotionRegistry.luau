--!nonstrict
-- SWORD 외 캐릭터 모션 레지스트리(순수 데이터 + 검증). MotionRegistry(SWORD)와 같은 규칙을 캐릭터별로 적용한다.
-- 정식 에셋 교체: Entries[캐릭터][모션 id].assetId = "rbxassetid://..." 또는 ReplicatedStorage.RoBattles.Assets.Animations.<캐릭터>.<모션 id>
-- (Animation 인스턴스가 우선). 에셋이 지정된 모션은 절차 포즈가 꺼지고 Animator 트랙이 재생된다. 타이밍·우선순위·정리는 상태기계가 계속 관리.
local Data = require(script.Parent.CharacterMotions)

local Registry = {}

Registry.Data = Data

-- Locomotion(Idle/Run)은 절차 전용. 나머지는 Action.
local function entriesFor(def)
	local e = { Idle = { kind = "Locomotion", assetId = "" }, Run = { kind = "Locomotion", assetId = "" } }
	for id in def.Motions do
		e[id] = { kind = "Action", assetId = "" }
	end
	return e
end

Registry.Entries = {}
for characterId, def in Data do
	Registry.Entries[characterId] = entriesFor(def)
end

function Registry.characterIds()
	local ids = {}
	for id in Registry.Entries do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function Registry.assetIdOf(characterId, motionId)
	local e = Registry.Entries[characterId] and Registry.Entries[characterId][motionId]
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

local function jointSet(key)
	local names = {}
	for j in key.pose do
		table.insert(names, j)
	end
	table.sort(names)
	return table.concat(names, ",")
end

-- 문제 목록(문자열 배열). 비어 있으면 통과. characterId 를 주면 그 캐릭터만 검사.
function Registry.validate(onlyId)
	local problems = {}
	local function add(msg)
		table.insert(problems, msg)
	end
	for characterId, def in Data do
		if onlyId == nil or onlyId == characterId then
			local entries = Registry.Entries[characterId]
			local P = characterId .. ": "
			for group, ids in def.Groups do
				for _, id in ids do
					if entries[id] == nil then
						add(string.format("%s그룹 %s: 항목 누락 %s", P, group, id))
					elseif entries[id].kind ~= "Locomotion" and def.Motions[id] == nil then
						add(string.format("%s그룹 %s: 모션 데이터 누락 %s", P, group, id))
					end
				end
			end
			for _, key in { "strideHz", "runLegSwing", "runLean", "stance" } do
				if def.Locomotion[key] == nil then
					add(P .. "Locomotion." .. key .. " 누락")
				end
			end
			for j, jt in def.Locomotion.stance or {} do
				if not JOINTS[j] then
					add(P .. "stance 알 수 없는 관절 " .. j)
				end
				for f, v in jt do
					if not FIELDS[f] or badNumber(v) then
						add(P .. "stance 비정상 값 " .. j .. "." .. f)
					end
				end
			end
			for id, m in def.Motions do
				if badNumber(m.duration) or m.duration <= 0 then
					add(P .. id .. ": duration 비정상")
				end
				if type(m.priority) ~= "number" or m.priority < 1 or m.priority > 9 then
					add(P .. id .. ": priority 비정상")
				end
				if m.next ~= nil and def.Motions[m.next] == nil then
					add(P .. id .. ": next 모션 없음 " .. tostring(m.next))
				end
				if m.hold and (badNumber(m.maxDuration) or m.maxDuration < m.duration) then
					add(P .. id .. ": hold 모션은 maxDuration(≥duration) 필요 — 종료 이벤트가 유실돼도 정리되어야 함")
				end
				if m.keys == nil or #m.keys < 2 then
					add(P .. id .. ": 키프레임 2개 이상 필요")
				else
					local prev, first, hasImpact = -1, nil, m.impact == nil
					for i, key in m.keys do
						if badNumber(key.t) or key.t < 0 or key.t > m.duration + 1e-6 then
							add(string.format("%s%s: 키 %d 시간 범위 밖", P, id, i))
						elseif key.t < prev then
							add(string.format("%s%s: 키 %d 시간 역전", P, id, i))
						end
						prev = key.t
						if m.impact ~= nil and math.abs(key.t - m.impact) < 1e-6 then
							hasImpact = true
						end
						local set = jointSet(key)
						first = first or set
						if set ~= first then
							add(string.format("%s%s: 키 %d 관절 구성이 첫 키와 다름", P, id, i))
						end
						for j, jt in key.pose do
							if not JOINTS[j] then
								add(string.format("%s%s: 알 수 없는 관절 %s", P, id, j))
							end
							for f, v in jt do
								if not FIELDS[f] then
									add(string.format("%s%s: 알 수 없는 필드 %s.%s", P, id, j, f))
								elseif badNumber(v) then
									add(string.format("%s%s: %s.%s 숫자 비정상", P, id, j, f))
								end
							end
						end
					end
					if not hasImpact then
						add(P .. id .. ": impact 시각에 해당하는 키프레임 없음")
					end
				end
			end
		end
	end
	return problems
end

return Registry
