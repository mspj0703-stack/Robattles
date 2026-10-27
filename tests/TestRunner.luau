--!strict
-- 의존성 없는 경량 테스트 러너. Roblox(Studio)와 Luau CLI 양쪽에서 동일하게 동작한다.

local TestRunner = {}

export type Result = { name: string, ok: boolean, err: string? }

local results: { Result } = {}
local currentSuite = ""

function TestRunner.describe(name: string, body: () -> ())
	local prev = currentSuite
	currentSuite = if prev == "" then name else prev .. " > " .. name
	body()
	currentSuite = prev
end

function TestRunner.it(name: string, body: () -> ())
	local full = currentSuite .. " > " .. name
	local ok, err = pcall(body)
	table.insert(results, { name = full, ok = ok, err = if ok then nil else tostring(err) })
end

function TestRunner.expect(cond: any, message: string?)
	if not cond then
		error(message or "expect 실패", 2)
	end
end

function TestRunner.expectEqual(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(string.format("%s: 기대 %s, 실제 %s", message or "expectEqual", tostring(expected), tostring(actual)), 2)
	end
end

-- 실패 시 지정 조건이 아니라 "거부(false)"를 기대하는 헬퍼
function TestRunner.expectNear(actual: number, expected: number, tolerance: number?, message: string?)
	local tol = tolerance or 1e-6
	if type(actual) ~= "number" or math.abs(actual - expected) > tol then
		error(message or string.format("expectNear: 기대 %s ±%s, 실제 %s", tostring(expected), tostring(tol), tostring(actual)), 2)
	end
end

function TestRunner.expectRejected(ok: boolean, err: string?, message: string?)
	if ok then
		error((message or "거부되어야 함") .. " (통과해버림)", 2)
	end
	if err == nil or err == "" then
		error((message or "거부") .. ": 오류 메시지 없음", 2)
	end
end

-- 결과 출력. 실패가 있으면 false 반환.
function TestRunner.report(): boolean
	local passed, failed = 0, 0
	for _, r in results do
		if r.ok then
			passed += 1
			print("PASS  " .. r.name)
		else
			failed += 1
			print("FAIL  " .. r.name .. "\n      " .. (r.err or ""))
		end
	end
	print(string.format("\n합계: %d 통과 / %d 실패 / %d 전체", passed, failed, passed + failed))
	return failed == 0
end

function TestRunner.reset()
	table.clear(results)
	currentSuite = ""
end

return TestRunner
