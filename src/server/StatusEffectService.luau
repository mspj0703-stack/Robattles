--!nonstrict
-- 상태이상: Slow, Reveal(위치 노출), Knockback(속도 계산), Stagger(강한 공격 전용, 연속 저항), Stun/Airborne(제한적).
local Link = require(script.Parent.Link)
local Vec = Link.shared("Vec")

local StatusEffectService = {}
StatusEffectService.__index = StatusEffectService

local KNOWN = { Slow = true, Reveal = true, Stagger = true, Stun = true, Airborne = true, Knockback = true }
local MAX_SLOWS = 8

local function validDuration(d, max)
	return type(d) == "number" and d == d and d > 0 and d <= max
end

function StatusEffectService.new(config)
	return setmetatable({ _cfg = config or Link.shared("Config"), _s = {} }, StatusEffectService)
end

function StatusEffectService:_get(id)
	local s = self._s[id]
	if not s then
		s = {
			slows = {},
			revealUntil = 0,
			staggerUntil = 0,
			stunUntil = 0,
			airUntil = 0,
			staggerCount = 0,
			lastStaggerAt = -math.huge,
			ccImmuneUntil = 0,
		}
		self._s[id] = s
	end
	return s
end

-- ctx: { strong: boolean }. 반환: ok, info | reason
function StatusEffectService:apply(id, effect, now, ctx)
	if type(effect) ~= "table" or not KNOWN[effect.type] then
		return false, "unknown_effect"
	end
	local c = self._cfg.Combat
	local s = self:_get(id)
	local t = effect.type

	if t == "Knockback" then
		local p, up = effect.power, effect.upward or 0
		if type(p) ~= "number" or p ~= p or p <= 0 or p > 200 then
			return false, "bad_power"
		end
		if type(up) ~= "number" or up ~= up or up < 0 or up > 100 then
			return false, "bad_upward"
		end
		local dir = type(effect.direction) == "table" and Vec.normalize(effect.direction) or nil
		if dir == nil or dir.X ~= dir.X then
			return false, "bad_direction"
		end
		return true, { velocity = { X = dir.X * p, Y = dir.Y * p + up, Z = dir.Z * p } }
	end

	if not validDuration(effect.duration, 60) then
		return false, "bad_duration"
	end
	local d = effect.duration

	if t == "Slow" then
		local m = effect.multiplier
		if type(m) ~= "number" or m ~= m or m < 0.05 or m > 0.95 then
			return false, "bad_multiplier"
		end
		local live = {}
		for _, sl in s.slows do
			if sl.endsAt > now then
				table.insert(live, sl)
			end
		end
		if #live >= MAX_SLOWS then
			-- 가득 차면 가장 먼저 끝나는 둔화를 버린다(강한 둔화 보호). 합산·곱셈은 하지 않는다.
			local idx = 1
			for i, sl in live do
				if sl.endsAt < live[idx].endsAt then
					idx = i
				end
			end
			table.remove(live, idx)
		end
		table.insert(live, { mult = m, endsAt = now + d })
		s.slows = live
		return true, { duration = d }
	elseif t == "Reveal" then
		s.revealUntil = math.max(s.revealUntil, now + d)
		return true, { duration = d }
	elseif t == "Stagger" then
		if not (ctx and ctx.strong == true) then
			return false, "basic_no_stagger" -- 기본 공격 경직 없음
		end
		if now - s.lastStaggerAt > c.StaggerResistWindow then
			s.staggerCount = 0
		end
		local applied = math.min(d, c.StaggerMaxDuration) * (c.StaggerResistFactor ^ s.staggerCount)
		if applied < 0.05 then
			return false, "stagger_resisted"
		end
		s.staggerCount += 1
		s.lastStaggerAt = now
		s.staggerUntil = math.max(s.staggerUntil, now + applied)
		return true, { duration = applied }
	else -- Stun, Airborne
		if now < s.ccImmuneUntil then
			return false, "cc_immune"
		end
		local applied = math.min(d, c.HardCCMaxDuration)
		if t == "Stun" then
			s.stunUntil = math.max(s.stunUntil, now + applied)
		else
			s.airUntil = math.max(s.airUntil, now + applied)
		end
		s.ccImmuneUntil = now + applied + c.HardCCImmunity
		return true, { duration = applied }
	end
end

-- 가장 강한 둔화 하나만 적용(중첩 곱 없음). 경직·기절·에어본 중엔 0.
function StatusEffectService:getSpeedMultiplier(id, now)
	local s = self._s[id]
	if not s then
		return 1
	end
	if now < s.staggerUntil or now < s.stunUntil or now < s.airUntil then
		return 0
	end
	local best = 1
	for _, sl in s.slows do
		if sl.endsAt > now and sl.mult < best then
			best = sl.mult
		end
	end
	return best
end

function StatusEffectService:canAct(id, now)
	local s = self._s[id]
	if not s then
		return true
	end
	return not (now < s.staggerUntil or now < s.stunUntil or now < s.airUntil)
end

function StatusEffectService:isRevealed(id, now)
	local s = self._s[id]
	return s ~= nil and now < s.revealUntil
end

function StatusEffectService:clear(id)
	self._s[id] = nil
end

return StatusEffectService
