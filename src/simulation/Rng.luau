--!nonstrict
-- 시드 고정 의사난수(xorshift32). 같은 시드는 항상 같은 수열을 만든다. math.random 은 쓰지 않는다.
-- 시뮬레이션 전용: 게임 실제 코드와 무관하다.
local Rng = {}
Rng.__index = Rng

local M32 = 4294967296

-- 32비트 곱셈(double 정밀도 안에서 정확하도록 16비트로 쪼갠다)
local function mul32(a, b)
	local ah, al = math.floor(a / 65536), a % 65536
	return ((ah * b % M32) * 65536 + al * b) % M32
end
Rng.mul32 = mul32

function Rng.new(seed)
	local s = mul32((math.floor(seed) % M32) + 1, 2654435761) % M32
	if s == 0 then
		s = 0x9E3779B9
	end
	local self = setmetatable({ _s = s }, Rng)
	for _ = 1, 8 do
		self:nextU32() -- 작은 시드 간 상관을 없애는 워밍업
	end
	return self
end

function Rng:nextU32()
	local x = self._s
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self._s = x
	return x
end

-- [0, 1)
function Rng:next()
	return self:nextU32() / M32
end

function Rng:range(lo, hi)
	return lo + (hi - lo) * self:next()
end

function Rng:chance(p)
	return self:next() < p
end

-- 대략 정규 분포(균등 4개 합), 평균 0, 표준편차 약 1
function Rng:gauss()
	return (self:next() + self:next() + self:next() + self:next() - 2) * 1.7320508
end

-- FNV-1a 32비트 해시(재현성 지문)
function Rng.fnv(hash, str)
	for i = 1, #str do
		hash = mul32(bit32.bxor(hash, string.byte(str, i)), 16777619)
	end
	return hash
end

Rng.FNV_OFFSET = 2166136261

return Rng
