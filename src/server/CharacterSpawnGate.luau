--!nonstrict
-- CharacterAdded 처리 경쟁 방지 (순수 로직, CLI 테스트 가능).
-- 같은 모델에 대한 중복 CharacterAdded 는 무시하고, 더 새로운 스폰이 시작되면 이전 처리(yield 중)를 무효화(stale)하며,
-- 이미 교체된/퇴장한 캐릭터의 늦은 Died 이벤트가 현재 상태를 덮어쓰지 못하게 한다.
local CharacterSpawnGate = {}
CharacterSpawnGate.__index = CharacterSpawnGate

function CharacterSpawnGate.new()
	return setmetatable({ _nextEpoch = 0, _epoch = {}, _current = {}, _seen = setmetatable({}, { __mode = "k" }) }, CharacterSpawnGate)
end

-- 새 캐릭터 처리 시작. 이미 처리했거나 현재 모델이면 nil(중복), 아니면 epoch 번호.
function CharacterSpawnGate:begin(id, model)
	if self._seen[model] then
		return nil
	end
	self._seen[model] = true
	self._nextEpoch += 1
	local e = self._nextEpoch -- never reuse an epoch after a player reconnects
	self._epoch[id] = e
	return e
end

-- yield 이후에 호출: 더 새로운 스폰이 시작됐거나 플레이어가 제거됐다면 true → 처리 중단
function CharacterSpawnGate:isStale(id, epoch)
	return self._epoch[id] ~= epoch
end

-- 초기화가 끝나 이 모델이 현재 캐릭터가 됐다.
function CharacterSpawnGate:commit(id, epoch, model)
	if self:isStale(id, epoch) then
		return false
	end
	self._current[id] = model
	return true
end

-- 현재 캐릭터의 사망만 인정(오래된 모델의 늦은 Died 무시)
function CharacterSpawnGate:acceptsDeath(id, epoch, model)
	return not self:isStale(id, epoch) and self._current[id] == model
end

function CharacterSpawnGate:getCurrent(id)
	return self._current[id]
end

-- 퇴장: 진행 중인 모든 처리를 stale 로 만든다.
function CharacterSpawnGate:remove(id)
	self._epoch[id] = nil
	self._current[id] = nil
end

return CharacterSpawnGate
