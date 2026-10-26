--!nonstrict
-- 모션 id → 에셋(Animation 인스턴스 등) 해석 결과 캐시 (순수 로직, CLI 테스트 가능).
-- 상태기계가 매 프레임 "이 모션은 에셋으로 구동되는가"를 묻기 때문에, 해석(resolve)이 인스턴스를 만들거나 폴더를 뒤지면
-- 프레임마다 비용·누수가 생긴다. 결과(없음 포함)를 id 별로 한 번만 계산하고, 에셋이 바뀌면 invalidate 로 비운다.
local AnimationCache = {}
AnimationCache.__index = AnimationCache

-- resolve(id) → 값 또는 nil. 반환된 nil 도 캐시한다(없는 에셋을 매 프레임 다시 찾지 않는다).
function AnimationCache.new(resolve)
	return setmetatable({ _resolve = resolve, _values = {}, _known = {}, resolveCalls = 0 }, AnimationCache)
end

function AnimationCache:get(id)
	if not self._known[id] then
		self.resolveCalls += 1
		self._values[id] = self._resolve(id)
		self._known[id] = true
	end
	return self._values[id]
end

function AnimationCache:has(id)
	return self:get(id) ~= nil
end

-- id 를 주면 그 항목만, 생략하면 전부 비운다. 비워진 값은 다음 get 에서 다시 해석한다.
-- 반환: 비워진 이전 값들의 배열(호출부가 인스턴스 Destroy/트랙 정리에 사용).
function AnimationCache:invalidate(id)
	local dropped = {}
	if id ~= nil then
		if self._values[id] ~= nil then
			table.insert(dropped, self._values[id])
		end
		self._values[id] = nil
		self._known[id] = nil
	else
		for _, v in self._values do
			table.insert(dropped, v)
		end
		table.clear(self._values)
		table.clear(self._known)
	end
	return dropped
end

return AnimationCache
