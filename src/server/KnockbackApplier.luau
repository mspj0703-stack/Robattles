--!nonstrict
-- 서버 넉백 적용 인터페이스 (순수 로직). DamageService 가 계산한 Knockback 효과 결과(velocity)를 받아
-- ① MovementValidator 에 "Knockback" 이동 허가를 발급하고 ② 주입된 setVelocity(id, velocity) 로 실제 속도를 적용한다.
-- 허가 발급에 실패하면 속도를 적용하지 않는다(상한 초과·빈도 제한 등). 기본은 꺼짐(Config.Knockback.Enabled=false, A59):
-- 켜기 전에는 DamageService 가 계산만 하고 월드에는 아무 영향도 없다. 이번 단계에서 새 스킬은 구현하지 않는다.
--
-- deps: { config?, movement = MovementValidator, setVelocity = function(id, {X,Y,Z}) }
local Link = require(script.Parent.Link)

local KnockbackApplier = {}
KnockbackApplier.__index = KnockbackApplier

function KnockbackApplier.new(deps)
	return setmetatable({
		_cfg = deps.config or Link.shared("Config"),
		_movement = deps.movement,
		_setVelocity = deps.setVelocity,
	}, KnockbackApplier)
end

-- 속도 벡터를 직접 적용(향후 스킬·폭발에서도 사용). 반환 ok, reason
function KnockbackApplier:apply(id, velocity, now)
	if not self._cfg.Knockback.Enabled then
		return false, "disabled"
	end
	if type(velocity) ~= "table" or type(velocity.X) ~= "number" or type(velocity.Y) ~= "number" or type(velocity.Z) ~= "number" then
		return false, "bad_velocity"
	end
	local horizontal = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
	local ok, why = self._movement:issue(id, "Knockback", now, {
		speed = horizontal, up = math.max(0, velocity.Y), duration = self._cfg.Knockback.Duration,
	})
	if not ok then
		return false, why
	end
	self._setVelocity(id, velocity)
	return true, nil
end

-- DamageService:onEffect 구독용
function KnockbackApplier:attach(damage)
	damage:onEffect(function(e)
		for _, r in e.effects do
			if r.type == "Knockback" and r.ok and r.info and r.info.velocity then
				self:apply(e.targetId, r.info.velocity, e.now)
			end
		end
	end)
end

return KnockbackApplier
