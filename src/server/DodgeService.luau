--!nonstrict
-- 방향 회피: 최대 충전 횟수, 충전당 재충전(순차), 시작 직후 무적. 스태미나 없음.
local Link = require(script.Parent.Link)

local DodgeService = {}
DodgeService.__index = DodgeService

function DodgeService.new(config)
	return setmetatable({ _cfg = config or Link.shared("Config"), _s = {} }, DodgeService)
end

function DodgeService:register(id)
	self._s[id] = {
		charges = self._cfg.Dodge.MaxCharges,
		nextChargeAt = nil,
		invulnUntil = 0,
		dodgingUntil = 0,
	}
end

function DodgeService:remove(id)
	self._s[id] = nil
end

function DodgeService:reset(id)
	self:register(id)
end

function DodgeService:_update(s, now)
	local d = self._cfg.Dodge
	while s.charges < d.MaxCharges and s.nextChargeAt ~= nil and now >= s.nextChargeAt do
		s.charges += 1
		if s.charges < d.MaxCharges then
			s.nextChargeAt += d.RechargeSeconds
		else
			s.nextChargeAt = nil
		end
	end
end

function DodgeService:getCharges(id, now)
	local s = self._s[id]
	if not s then
		return 0
	end
	self:_update(s, now)
	return s.charges
end

-- opts: { airborne: boolean, canAct: boolean (StatusEffectService 결과) }
function DodgeService:tryDodge(id, now, opts)
	local s = self._s[id]
	if not s then
		return false, "not_registered"
	end
	local d = self._cfg.Dodge
	opts = opts or {}
	self:_update(s, now)
	if opts.canAct == false then
		return false, "cannot_act"
	end
	if opts.airborne and not d.AllowAirborne then
		return false, "airborne_disabled"
	end
	if now < s.dodgingUntil then
		return false, "already_dodging"
	end
	if s.charges <= 0 then
		return false, "no_charges"
	end
	s.charges -= 1
	if s.nextChargeAt == nil then
		s.nextChargeAt = now + d.RechargeSeconds
	end
	s.invulnUntil = now + d.InvulnSeconds
	s.dodgingUntil = now + d.Duration
	return true, { distance = d.Distance, duration = d.Duration, invulnUntil = s.invulnUntil }
end

-- HUD용 상태: 현재 충전 수, 다음 충전 시각(없으면 nil), 최대·재충전 시간
function DodgeService:getState(id, now)
	local s = self._s[id]
	if not s then
		return nil
	end
	self:_update(s, now)
	local d = self._cfg.Dodge
	return { charges = s.charges, max = d.MaxCharges, nextChargeAt = s.nextChargeAt, recharge = d.RechargeSeconds }
end

-- 무적은 [시작, 시작+InvulnSeconds) 구간.
function DodgeService:isInvulnerable(id, now)
	local s = self._s[id]
	return s ~= nil and now < s.invulnUntil
end

function DodgeService:isDodging(id, now)
	local s = self._s[id]
	return s ~= nil and now < s.dodgingUntil
end

return DodgeService
