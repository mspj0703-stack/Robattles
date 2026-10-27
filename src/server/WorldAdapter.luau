--!nonstrict
-- Roblox 전용 월드 어댑터: ProjectileService/HitboxService가 쓰는 cast / lineOfSight를 workspace 레이캐스트로 구현.
-- CLI에서는 실행할 수 없다. Studio 실기동 검증 대상(docs/STUDIO_TEST_PLAN.md).
local WorldAdapter = {}

function WorldAdapter.new()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.RespectCanCollide = true

	local self = { _ignore = {} }

	local function refresh()
		params.FilterDescendantsInstances = self._ignore
	end

	-- 캐릭터 모델(피격 대상)은 월드 충돌에서 제외한다: 대상 판정은 서버 위치 기반 스윕이 따로 한다.
	function self.addIgnore(instance)
		table.insert(self._ignore, instance)
		refresh()
	end
	function self.removeIgnore(instance)
		local i = table.find(self._ignore, instance)
		if i then
			table.remove(self._ignore, i)
			refresh()
		end
	end

	-- p0→p1 구간(구 반지름 radius) 첫 충돌. 반환 { fraction, position, normal } | nil
	function self.cast(p0, p1, radius)
		local origin = Vector3.new(p0.X, p0.Y, p0.Z)
		local delta = Vector3.new(p1.X - p0.X, p1.Y - p0.Y, p1.Z - p0.Z)
		local length = delta.Magnitude
		if length < 1e-6 then
			return nil
		end
		local result
		if radius > 0 then
			result = workspace:Spherecast(origin, radius, delta, params)
		else
			result = workspace:Raycast(origin, delta, params)
		end
		if not result then
			return nil
		end
		local fraction = math.clamp(result.Distance / length, 0, 1)
		local position = origin + delta * fraction
		return { fraction = fraction, position = position, normal = result.Normal }
	end

	-- a→b 사이에 월드가 가로막지 않으면 true
	function self.lineOfSight(a, b)
		local o = Vector3.new(a.X, a.Y, a.Z)
		local d = Vector3.new(b.X - a.X, b.Y - a.Y, b.Z - a.Z)
		return workspace:Raycast(o, d, params) == nil
	end

	return self
end

return WorldAdapter
