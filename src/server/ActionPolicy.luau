--!nonstrict
-- 행동 분류 정책 (순수 로직): 어떤 행동이 "공격 행동 시작"이라 부활 보호를 해제하는가.
-- 원칙: 안전 쪽 기본값. 명시적으로 비공격으로 허용된 종류(Parry, Movement, Dodge, Run, Utility)가 아니면 모두 공격으로 본다.
-- 데이터가 `offensive=false` 를 선언해도 피해·투사체·히트박스·폭발·빔·설치·효과(넉백 등) 필드가 있으면 공격이다(우회 불가).
-- 이동기는 판정(피해/효과)이 없을 때만 비공격이다. 지연 공격: 설치(Place/Placed)와 원격 기폭(Detonate)은 둘 다 "시작" 시점에서 공격이다.
local ActionPolicy = {}

local NON_OFFENSIVE_KINDS = { Parry = true, Movement = true, Dodge = true, Run = true, Utility = true }
-- 이 필드 중 하나라도 있으면 공격 판정이 있는 행동이다. (counterDamage 는 패링 성공 시 반응이라 제외)
local DAMAGING_FIELDS = { "damage", "projectile", "hitbox", "explosion", "beam", "placed", "effects", "knockback", "stagger", "arcDegrees", "range", "detonate" }

ActionPolicy.OffensiveKinds = { "Melee", "Projectile", "Beam", "Explosion", "Placed", "Place", "Detonate", "Ultimate", "Skill", "Attack" }

function ActionPolicy.isOffensive(def)
	if type(def) ~= "table" then
		return true
	end
	for _, f in DAMAGING_FIELDS do
		if def[f] ~= nil then
			return true
		end
	end
	if def.kind == nil then
		return true
	end
	return NON_OFFENSIVE_KINDS[def.kind] ~= true
end

return ActionPolicy
